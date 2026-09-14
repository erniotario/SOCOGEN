# SOCOGEN — gestion de stock

A stock-management application for a Cameroonian wholesaler, shipping to
**Windows, Android and iOS** from one Flutter codebase in `flutter_app/`.
Real deployment: ~400 articles across three magasins (Hysacam, Ekie,
Elig-Essono), a few thousand movements a year, imported from Sage
Gestion Commerciale.

**The application is `flutter_app/`.** A Python/PySide6 version came
first and was removed once the port shipped on all three platforms; it is
in the Git history if a behaviour ever needs checking against it.
`scripts/` holds the Python tooling that still earns its place — the
clean seed-database builder and the Sage `.gcm` reader.

The interface is in French — labels, messages, errors, and the prose in
commits about the screens. Keep it that way. The people using this are
storekeepers, not developers: an error must say what to do about it, not
what threw.

## Commands

From `flutter_app/`:

```bash
flutter analyze              # the project's only typechecker; keep it at zero
flutter test                 # ~191 tests across 23 files
flutter build windows --release
flutter build apk --release
```

Python tooling, from the repository root:

```bash
.venv/Scripts/python.exe scripts/build_clean_seed_db.py  # -> flutter_app/assets/db/socogen_seed.db
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

**A database belongs to one business, and says so.** `sync_meta` carries a
`tenant_id`, minted on first sync rather than at creation — stamping on
creation would give two devices of the same business different ids and they
would refuse each other forever. `SyncEngine.reconcileTenant` settles it:
an unclaimed database adopts whoever it first syncs with, a claim is never
reassigned, and two *different* claims raise `TenantMismatch` before a
single row is applied. The check has to come first, because the merge runs
on natural keys — a store by its name, a product by its reference — so two
businesses both keeping a "Dépôt" and a "RIZ25" would not fail to merge,
they would fuse, and the newer `updated_at` would overwrite real stock with
a stranger's. `sync_tenant_test.dart` pins both halves, including a test
that the same rows *do* fuse when the claims match, so the refusal test
cannot pass for the wrong reason.

### The professional bar

This is a real ledger of a business's goods. The gaps below are known and
deliberate to name — close them when the work touches that area, and do
not make any of them worse.

- **Stock must not silently go negative.** 21 of the 400 live articles
  show a negative balance, which means either a sortie was recorded that
  never happened or an entrée was never entered. It is now *flagged* on
  both sides. `StockStatus.stockNegatif` is a state of its own, apart
  from `rupture`, so a negative no longer hides among the hundreds of
  articles legitimately sitting at zero — Rapports raises a banner
  naming the count and filters the table down to those rows. And all
  three write paths warn before creating one: the Sorties form, the
  Transactions edit dialog (via `ProductRepository.balanceExcluding`,
  which judges an edit on what it would *leave behind* rather than on a
  sum that still holds the row's old figure), and the Sage import, which
  reports per-magasin balances its run drove below zero. The chosen
  policy is warn-and-record, not refuse: a storekeeper whose goods have
  physically left must still be able to say so, and the override is no
  longer silent because it lands on the Rapports list. The import
  compares against a snapshot taken before the run, so a negative already
  on file is never blamed on whoever imports next — a warning that fires
  every time is one that gets learned as noise.

  The **cure** is the physical inventory below: counting the shelf and
  posting the difference is what actually settles one of these, and
  `inventory_service_test.dart` pins that a settled article leaves the
  Rapports anomaly list.
- **A movement has no author.** The app has users and roles
  (`admin` / `magasinier`), but `stock_entries` and `stock_outputs`
  record no one. In a stock ledger, who entered a line and when is not a
  nicety. Any schema change in that area should add attribution.
- **History is edited in place.** Transactions lets a past movement be
  changed or deleted outright. Accounting practice is a corrective
  movement that leaves the original standing, so the trail stays
  readable. Prefer that shape for new work.
- **Physical inventory — done, and it is the cure for the above.**
  `InventoryScreen` records what a shelf actually holds and posts the
  difference as a corrective movement: a surplus becomes an entrée, a
  shortfall a sortie, both carrying the counterparty
  `InventoryService.label` ("Inventaire physique") so they are
  recognisable in Transactions. Current stock is derived, so an
  inventory cannot *set* a stock — it can only move it, which is also
  the accounting shape this project wants: the original lines stay
  standing. Two rules the code holds and any change must keep. A count
  session is a **draft** — nothing is written until validation — and an
  article absent from the draft is **not counted, never assumed zero**;
  on a 400-article catalogue the other reading would empty the store.
  And `InventoryService.post` recomputes the variance against the *live*
  balance rather than the figure the operator was shown, because a draft
  can sit on screen while real movements land behind it. Still open: a
  count has no author and no session record, so "who counted what, when"
  is not on file — see the attribution gap above.
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


**A fresh database is nobody's business yet.** The seed asset ships with
no accounts, no magasins, and an empty company name, and
`AppSchema.defaultStores` is deliberately an empty list. It used to carry
the first customer's three magasins and their name, so the next business
opened the app to a stranger's premises on its own reports.
`CompanySetupScreen` asks once, after the first administrator is created,
and writes `company_settings` plus the magasins it is given. Two things
it must keep doing: suggest **no** magasin names (a suggestion here is
the inherited identity all over again), and offer the *skip* — a second
device of the same business takes its magasins from the first device by
sync, and inventing them here would merge as duplicates, since sync
matches a store by its name.

Whether the question has been answered lives in
`sync_meta.company_configured`, device-local because `sync_meta` is not
part of a `ChangeSet`. A database carrying no flag but already holding
products or movements is treated as configured and the flag is written
once: installations that predate the screen must never be dragged back
through setup, and `company_setup_test.dart` pins that.

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
- **Two in-memory databases are the same database** unless the open
  options say `singleInstance: false`. `inMemoryDatabasePath` opened twice
  hands back one handle, so a two-device sync test quietly becomes one
  device syncing with itself and every assertion about the peer passes
  because the row never went anywhere. `sync_engine_test.dart` and
  `sync_tenant_test.dart` both set it.
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
