# SOCOGEN — gestion de stock

Two applications share this repository. **`flutter_app/` is the one under
active development**; the Python app at the root is the original it was
ported from and is kept for reference.

| | |
|---|---|
| `flutter_app/` | Flutter 3.44 / Dart 3.12. Ships to Windows, Android and iOS. |
| repository root | PySide6 + customtkinter + SQLAlchemy. `python main.py` (Qt if PySide6 imports, customtkinter otherwise). |
| `scripts/` | Python tooling: seed-database builders, Sage `.gcm` reader. |

The UI is in French throughout — labels, messages, commit prose about the
screens. Keep it that way.

## Commands

Everything Flutter runs from `flutter_app/`:

```bash
flutter analyze              # the project's only typechecker
flutter test                 # ~125 tests across 18 files
flutter build windows --release
flutter build apk --release
```

Python tooling runs from the repository root through the venv:

```bash
.venv/Scripts/python.exe main.py
.venv/Scripts/python.exe scripts/build_seed_db.py        # -> flutter_app/assets/db/socogen_seed.db
.venv/Scripts/python.exe scripts/gcm_to_excel.py <file.gcm>
```

## Build traps

These have each cost real time. None of them announce themselves.

- **`flutter build windows` exits 0 when it fails.** Read the output text,
  not the exit code. Same for `ISCC` piped through `tail`.
- **The Windows installer must be compiled outside the project folder.**
  In-place output trips real-time antivirus scanning and dies with
  `EndUpdateResource failed (110)`. Compile elsewhere, then copy back:
  `ISCC.exe "/O<temp-dir>" installer.iss` then copy `SOCOGEN_Setup.exe`
  into `flutter_app/dist/`.
- **`socogen.exe` keeping an old timestamp after a release build is
  normal.** It is the C++ runner shell and is only relinked when the
  Windows runner sources change. The Dart code is
  `build/windows/x64/runner/Release/data/app.so` — check *that* date to
  know whether a build is current.
- `file_picker` needs its AGP9 pub-cache patch for the Android build.
- `web_report_test.dart` binds port 8765. It fails while any SOCOGEN
  build is running with its Wi-Fi sync server on.

## Data model

**Movements are matched to products by `reference`, a string — not by a
foreign key.** `stock_entries` and `stock_outputs` carry the reference and
the store; deleting a product deliberately leaves its movements behind.
Nearly every surprising query in the repository follows from this.

**Current stock is derived, never stored:**
`initial_stock + entrées − sorties`. `product_stocks.initial_stock` holds
the *opening* figure per (product, store). Anything that writes stock must
write an opening figure — feeding it a current stock and then importing
the movements counts them twice.

The Transactions balance ("stock après") is kept per product, seeded from
that product's opening stock and scoped to the selected magasin. Date,
type and search filters choose which rows are *shown* and deliberately do
not enter the balance: the stock after a movement is a fact about the
movement, not about the filter.

### Database

One SQLite file per device, owned by `DatabaseService`. On first launch
the bundled `assets/db/socogen_seed.db` is copied to a writable location:

| Platform | Location |
|---|---|
| Windows | beside the executable |
| Android / iOS | the app documents directory (`app_flutter/socogen_stock.db`) |
| Linux / macOS | application support directory |

The seed asset is schema **v1** and ships without indexes, so every
schema change needs an `onUpgrade` step rather than only an `onCreate`
one — a fresh install runs the migrations too. Indexes live in
`AppSchema.createIndexStatements` and are applied both ways.

`SELECT`s that fan out per row are the performance trap here: the report
once ran two correlated subqueries per (product × store) and took ~3 s on
400 products. Join pre-aggregated totals instead.

### sqflite differs by platform — desktop will not catch it

Android's `SQLiteDatabase.execSQL` **rejects any statement that returns
rows**. `PRAGMA journal_mode = WAL` returns a row, so `db.execute(...)`
on it throws and the app cannot open its database at all. Use
`db.rawQuery` for anything that answers back. The desktop FFI backend has
no such rule and will happily run it, so this class of bug ships looking
fine.

WAL on Android is a manifest flag — `com.tekartik.sqflite.wal_enabled` —
not a pragma. It is currently off there.

## UI

`AdaptiveTable` (`lib/widgets/adaptive_table.dart`) renders a column
table on wide panes and one card per record below 840px. Columns and
cells are positional, so the two lists must stay the same length and
order.

**The Android build shows less.** `context.showsShortProductList`
(`lib/theme/app_breakpoints.dart`) cuts the Accueil and Rapport product
lists to désignation / magasin / stock actuel, and trims the Transactions
card to what identifies a movement and what it did to the stock. The desk
platforms keep the full breakdown. `android_transaction_card_test.dart`
holds a ceiling on the card's height — one field added to the Android
card pushes through it.

### PDF reports

`MultiPage` caps how many pages a *single widget* may span at 20, as an
assert: a debug build throws `TooManyPagesException` and a release build
silently spends minutes laying out pages. Long reports therefore set
`maxPages` and cut the body into page-sized tables — a spanning table is
re-laid-out once per page it crosses, which cost 47 s where chunks cost
14 s for the same 4 700 rows. Column headings ride in the page header so
every page carries them.

Reports build on a background isolate (`buildInBackground`). Seconds of
layout on the UI thread is an ANR on Android and a watchdog kill on iOS.

## Tests

- Repository tests share the fixture in `test/repositories/test_database.dart`.
  Its header documents every expected aggregate; update it when the
  fixture changes.
- Screen tests pump a fixed budget rather than `pumpAndSettle`, because
  the skeleton placeholders animate on an endless repeat and settling
  never completes. A screen whose data arrives *after* that budget is
  asserted against its skeleton and passes vacuously — if a screen starts
  loading faster, expect previously hidden layout overflows to surface.
- Platform-conditional UI is driven with `debugDefaultTargetPlatformOverride`,
  reset **inside** the test body: the framework checks foundation debug
  vars before `tearDown` runs.

## Sage import

`StockImportService` reads a workbook whose sheets are named *Produits*,
*Entrées* and *Sorties*. It refuses to guess: a movement whose magasin
matches no known store is skipped rather than filed against a default,
and an unreadable date is reported rather than assumed (French exports are
day-first — 05/03 is 5 March). Re-importing the same file adds nothing.

`scripts/gcm_to_excel.py` reads Sage's binary `.gcm` directly, but only
the article catalogue: per-depot stock and movement dates could not be
decoded with confidence, and it leaves those columns blank rather than
inventing them. Its docstring records what was decoded and what was not.
Sage stores text in **Mac Roman**, not Latin-1.
