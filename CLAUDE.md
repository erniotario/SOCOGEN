# SOCOGEN — gestion de stock

A stock-management application for a Cameroonian wholesaler, shipping to
**Windows, Android and iOS** from one Flutter codebase in `flutter_app/`.
Real deployment: ~400 articles across three magasins (Hysacam, Ekie,
Elig-Essono), a few thousand movements a year, imported from Sage
Gestion Commerciale.

**Work in `flutter_app/`.** The Python/PySide6 application at the
repository root is the original that this was ported from; it is kept for
reference and is not developed any more. `scripts/` holds Python tooling
that still earns its place — the seed-database builders and the Sage
`.gcm` reader.

The interface is in French — labels, messages, errors, and the prose in
commits about the screens. Keep it that way. The people using this are
storekeepers, not developers: an error must say what to do about it, not
what threw.

## Commands

From `flutter_app/`:

```bash
flutter analyze              # the project's only typechecker; keep it at zero
flutter test                 # ~125 tests across 18 files
flutter build windows --release
flutter build apk --release
```

Python tooling, from the repository root:

```bash
.venv/Scripts/python.exe scripts/build_seed_db.py        # -> flutter_app/assets/db/socogen_seed.db
.venv/Scripts/python.exe scripts/gcm_to_excel.py <file.gcm>
```

## Build traps

Each of these has cost an afternoon at least once, and none announces
itself.

- **`flutter build windows` exits 0 when it fails.** Read the output
  text, not the exit code. `ISCC` piped through `tail` does the same.
- **The Windows installer must be compiled outside the project folder.**
  Output written in place trips real-time antivirus scanning and dies
  with `EndUpdateResource failed (110)`. Compile elsewhere and copy back:
  `ISCC.exe "/O<temp-dir>" installer.iss`, then copy `SOCOGEN_Setup.exe`
  into `flutter_app/dist/`.
- **`socogen.exe` keeping an old timestamp after a release build is
  normal** — it is the C++ runner shell, relinked only when the Windows
  runner sources change. The Dart code is
  `build/windows/x64/runner/Release/data/app.so`; check *that* date to
  know whether a build is current.
- `file_picker` needs its AGP9 pub-cache patch for the Android build.
- `web_report_test.dart` binds port 8765 and fails while any SOCOGEN
  build is running with its Wi-Fi sync server on.

## The domain

### Invariants

**Movements find their product by `reference`, a string — not by a
foreign key.** `stock_entries` and `stock_outputs` carry the reference
and the store; deleting a product deliberately leaves its movements
behind. Most of the surprising SQL in this repository follows from this.

**Current stock is derived, never stored:**
`initial_stock + entrées − sorties`. `product_stocks.initial_stock` is
the *opening* figure per (product, store). Anything that writes stock
writes an opening figure — feeding it a current stock and then importing
the movements counts them twice.

**A balance belongs to a product, not to a filter.** The Transactions
"stock après" is kept per product, seeded from that product's opening
stock and scoped to the selected magasin. Date, type and search choose
which rows are *shown* and never enter the balance: the stock after a
movement is a fact about the movement.

**Refuse to guess.** The Sage importer skips a movement whose magasin
matches no known store rather than filing it against a default, and
reports an unreadable date rather than assuming one — a movement in the
wrong store silently corrupts that store's balance, and a silent
corruption is worse than a rejected row. Hold that line everywhere:
where the right answer is unknown, say so and let the operator decide.

### The professional bar

This is a real ledger of a business's goods. The gaps below are known and
deliberate to name — close them when the work touches that area, and do
not make any of them worse.

- **Stock must not silently go negative.** 21 of the 400 live articles
  currently show a negative balance, which means either a sortie was
  recorded that never happened or an entrée was never entered. Nothing in
  the app prevents it and nothing flags it. A sortie beyond available
  stock should be refused, or recorded and raised as a discrepancy to
  settle — never accepted in silence.
- **A movement has no author.** The app has users and roles
  (`admin` / `magasinier`), but `stock_entries` and `stock_outputs`
  record no one. In a stock ledger, who entered a line and when is not a
  nicety. Any schema change in that area should add attribution.
- **History is edited in place.** Transactions lets a past movement be
  changed or deleted outright. Accounting practice is a corrective
  movement that leaves the original standing, so the trail stays
  readable. Prefer that shape for new work.
- **There is no physical inventory.** No way to record a count and post
  the difference as an adjustment, which is the normal way a real stock
  is reconciled with its records — and the honest fix for those negative
  balances.
- **There is no valuation.** No prices anywhere, so no stock value, no
  CUMP or FIFO, nothing an accountant can use. Sage holds the prices; an
  import path exists.
- **The stock thresholds are global.** `StockStatus.fromCurrent` calls
  anything under 10 "stock faible" whether it is rice by the tonne or a
  carton of matches. These belong per article, as a stock minimum and a
  reorder point.
- **A transfer between magasins is not a concept.** Moving goods is a
  sortie in one store and an entrée in the other with nothing linking
  them, so goods in transit read as a loss here and a windfall there.
- **Units are free text.** `unit` is a label with no conversions, so
  CARTON and PIÈCE sit in the same column and cannot be totalled.

### Database

One SQLite file per device, owned by `DatabaseService`. On first launch
the bundled `assets/db/socogen_seed.db` is copied somewhere writable:

| Platform | Location |
|---|---|
| Windows | beside the executable |
| Android / iOS | app documents directory (`app_flutter/socogen_stock.db`) |
| Linux / macOS | application support directory |

The seed asset is schema **v1** and ships without indexes, so a schema
change needs an `onUpgrade` step and not only an `onCreate` one — a fresh
install runs the migrations too. Indexes live in
`AppSchema.createIndexStatements` and are applied both ways.

Queries that fan out per row are the performance trap here: the report
once ran two correlated subqueries per (product × store) and took ~3 s on
400 products. Join pre-aggregated totals instead — the same report now
takes 63 ms.

### sqflite differs by platform, and the desktop will not catch it

Android's `SQLiteDatabase.execSQL` **rejects any statement that returns
rows**. `PRAGMA journal_mode = WAL` returns a row, so running it through
`db.execute(...)` throws and the app cannot open its database at all. Use
`db.rawQuery` for anything that answers back. The desktop FFI backend has
no such rule and runs it happily, so this class of bug ships looking fine
after a full desktop test pass.

WAL on Android is the `com.tekartik.sqflite.wal_enabled` manifest flag,
not a pragma. It is currently off there.

## UI

`AdaptiveTable` (`lib/widgets/adaptive_table.dart`) draws a column table
on wide panes and one card per record below 840 px. Columns and cells are
positional — the two lists must stay the same length and order.

**Android shows less, on purpose.** `context.showsShortProductList`
(`lib/theme/app_breakpoints.dart`) cuts the Accueil and Rapport lists to
désignation / magasin / stock actuel and trims the Transactions card to
what identifies a movement and what it did to the stock. A phone is read
standing in an aisle; a desk screen is worked through.
`android_transaction_card_test.dart` holds a ceiling on the card height,
which one added field pushes straight through.

### Reports

`MultiPage` caps how many pages a *single widget* may span at 20, as an
assert: a debug build throws `TooManyPagesException`, a release build
silently spends minutes laying out pages it will not keep. Long reports
therefore raise `maxPages` and cut the body into page-sized tables — a
spanning table is re-laid-out once per page it crosses, which cost 47 s
where chunks cost 14 s for the same 4 700 rows. Column headings ride in
the page header so every page carries them.

Reports build on a background isolate (`buildInBackground`). Seconds of
layout on the UI thread is an ANR on Android and a watchdog kill on iOS.

## Tests

- Repository tests share the fixture in
  `test/repositories/test_database.dart`. Its header documents every
  expected aggregate — update it when the fixture changes.
- Screen tests pump a fixed budget rather than `pumpAndSettle`, because
  the skeleton placeholders animate on an endless repeat and settling
  never completes. A screen whose data arrives *after* that budget is
  asserted against its skeleton and passes vacuously; when a screen gets
  faster, expect previously hidden layout overflows to surface.
- Platform-conditional UI is driven with
  `debugDefaultTargetPlatformOverride`, reset **inside** the test body —
  the framework checks foundation debug vars before `tearDown` runs.
- Anything that can only fail on a device (the sqflite rule above, print
  dialogs) cannot be caught here. Say so rather than implying a green
  suite covers it.

## Sage import

`StockImportService` reads a workbook whose sheets are named *Produits*,
*Entrées* and *Sorties*. Re-importing the same file adds nothing: an
entry already on file is recognised by date, reference, magasin, quantity
and supplier or invoice number.

`scripts/gcm_to_excel.py` reads Sage's binary `.gcm` directly, but only
the article catalogue. Per-depot stock and movement dates could not be
decoded with confidence, so it leaves those columns blank rather than
inventing them; its docstring records exactly what was decoded and what
was not. Sage stores text in **Mac Roman**, not Latin-1 — an ASCII-only
scan silently drops every article with an accent or a `°`.
