# SM — gestion de stock

A stock-management application for Cameroonian wholesalers, shipping to
**Windows, Android and iOS** from one Flutter codebase in `flutter_app/`.
The first customer, SOCOGEN, runs ~400 articles across three magasins
(Hysacam, Ekie, Elig-Essono) and a few thousand movements a year,
imported from Sage Gestion Commerciale — most of the hard-won detail
below comes from that deployment.

**The product is named SM; the repository, the Dart package and the
database file are still `socogen`.** The app was named after its first
customer, which stopped being true once a second business could install
it. `AppBranding` (`lib/theme/app_branding.dart`) holds the product name
so the next rename is one line, and records the three identifiers that
deliberately do *not* follow it, because they are identity rather than
branding: `DatabaseService._dbFileName` (on Windows the database sits
beside the executable, so a new filename reads as an empty install),
`AppId` in `installer.iss` (Inno upgrades in place only while it
matches), and the Android `applicationId`. A customer's own name is data
— `company_settings`, filled in at first run — and appears on their
documents.

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
flutter test                 # ~369 tests across 41 files
flutter build windows --release
flutter build apk --release
```

Python tooling, from the repository root:

```bash
.venv/Scripts/python.exe scripts/build_clean_seed_db.py  # -> flutter_app/assets/db/socogen_seed.db
.venv/Scripts/python.exe scripts/gcm_to_excel.py <file.gcm>
```

## Architecture

`lib/` est rangé par domaine, pas par nature technique. L'application
évolue vers un système de gestion commerciale (catalogue, tiers, ventes,
POS, achats, comptabilité) : un classement en `data/` + `screens/` ne
disait plus rien une fois passé le premier domaine.

```
lib/
├── core/        noyau sans métier : db, auth, sync, events, money, errors
├── modules/     un dossier par domaine, chacun models/ repositories/
│                services/ ui/  (catalogue, stock, tiers,
│                utilisateurs, parametres, rapports)
├── shared/      design system et vocabulaire échangé entre modules
└── shell/       racine de composition — le seul endroit autorisé à
                 connaître tous les modules à la fois
```

**Un module n'atteint d'un autre que son dossier `services/`**, jamais
ses `models/` ni ses `repositories/`. `core/` et `shared/` n'importent
aucun module. Dart ne sait pas imposer ça, donc
`test/architecture_test.dart` le vérifie en lisant les imports, et c'est
la seule chose qui distingue cette arborescence d'un rangement de
dossiers. Son `_detteConnue` gèle les manquements hérités : la liste
ne peut que rétrécir, une entrée devenue inutile fait échouer le test au
même titre qu'un manquement nouveau. Chaque phase qui crée un service en
retire les lignes correspondantes.

Tous les imports intra-`lib/` sont en `package:socogen/…`. Les chemins
relatifs devenaient illisibles à trois niveaux d'imbrication, et un
chemin absolu est inspectable par le test ci-dessus.

### Ce que le noyau fournit déjà

- **`core/money`** — l'argent est un entier d'unités minimales plus sa
  devise, jamais un `double`. Le franc CFA n'a pas de subdivision. Les
  taux sont en dix-millièmes parce que la TVA camerounaise vaut 19,25 %.
  `horsTaxe()` divise par 1,1925 ; retirer 19,25 % d'un TTC ne redonne
  pas le HT, et confondre les deux est l'erreur classique sur un ticket
  saisi TTC. L'arrondi éloigne les demis de zéro dans les deux sens, pour
  qu'un remboursement rende exactement ce que la vente a encaissé.
- **`core/errors`** — `messagePour()` traduit une erreur technique en
  phrase actionnable ; aucun texte d'exception ne doit atteindre un
  écran. `ErreurUtilisateur` sert aux services à lever une cause métier
  déjà rédigée.
- **`core/auth/permissions`** — `PermissionGate` répond aux questions de
  droits. Il reproduit aujourd'hui le comportement des deux rôles en dur
  et sera remplacé en phase 4 sans toucher aux appelants. **Sans serveur,
  une permission cache un écran ; elle ne protège pas le fichier SQLite.**
- **`core/auth/password_hasher`** — PBKDF2-HMAC-SHA256, 12 000 tours,
  écrit avec `crypto` (aucune dépendance ajoutée). Les condensats hérités
  en SHA-256 à un tour restent vérifiables et sont réécrits à la
  prochaine connexion réussie, seul instant où le mot de passe en clair
  existe. Le nombre d'itérations est inscrit dans chaque condensat :
  relevable sans invalider l'existant, et il le faudra le jour où un
  hachage natif remplacera le Dart pur.

## Build traps

Each of these has cost an afternoon at least once, and none announces
itself.

- **`flutter build windows` exits 0 when it fails.** Read the output
  text, not the exit code. `ISCC` piped through `tail` does the same.
- **The Windows installer must be compiled outside the project folder.**
  Output written in place trips real-time antivirus scanning and dies
  with `EndUpdateResource failed (110)`. Compile elsewhere and copy back:
  `ISCC.exe "/O<temp-dir>" installer.iss`, then copy `SM_Setup.exe`
  into `flutter_app/dist/`.
- **`SM.exe` keeping an old timestamp after a release build is
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

**A partner is a record; the text on the movement is history.**
`tiers` holds clients and fournisseurs — one fiche can be both, because
a wholesaler sometimes buys from whoever it sells to. Movements gained a
`tiers_id`, but they keep their `supplier` / `destination` text: a past
line must go on saying what was typed that day, even after the fiche is
renamed or merged. Schema v5 reconciled the real data — 129 suppliers
and 3 destinations typed by hand across 5 201 movements, all of them
linked, in 197 ms.

The reconciliation matches on **exact equality and nothing else**, which
is the same refusal as above applied to names. The live data holds `BMC`
alongside `BCM` — two letters swapped, 4 563 movements against 5 — and
`DADA` alongside `DADA EKOUNOU`. Guessing would be spelling correction
disguised as a migration; leaving them apart makes them visible, and
`TiersRepository.fusionner` is the deliberate, human act that settles
one. It moves the movements, deactivates the source, and never deletes:
a fiche with history behind it is not erasable. The reprise also never
reclassifies a fiche it did not just create, since someone may have
corrected the rôle by hand since.

The movement forms choose a fiche instead of retyping a name, but the
field stays free text on purpose: a storekeeper receiving from a new
supplier on a Saturday must be able to record the entry without first
going to create a fiche. What the field adds is that **choosing is
easier than retyping** — and an unknown name offers to create the fiche
rather than fabricating one silently, because a fiche created on every
approximate keystroke is how the near-duplicates come back. A movement
saved with no fiche keeps its text and stays rattachable, which is why
the reprise is replayable.

Three write paths now resolve that link, and all three follow the same
rule: **the link follows the name.** Editing a movement re-resolves the
fiche only when the text changed, because looking it up every time would
undo a merge — a merged movement still reads `BCM` while counting for
`BMC`, and a quantity correction would send it back to `BCM`.
`mouvement_tiers_test.dart` pins that, and the Sage import links to an
exact existing name but never creates a fiche.

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
- **A movement carries its author — done.** `created_by` and
  `created_at` sit on `stock_entries`, `stock_outputs` and `transferts`.
  `created_at` is not the movement's `date`: a line can be back-dated,
  and "entered on the 5th for the 1st" is exactly what a ledger must be
  able to say.

  The author is **read from the session, never passed in**.
  `SessionCourante` holds who is logged in, `attribution()` in
  `sync_columns.dart` stamps it, and the repositories call it themselves
  at write time. Threading a user id through every form would mean every
  form could supply a different one, and one distracted screen would
  sign a line in someone else's name. The movement models deliberately
  have no author field, so there is nothing for a caller to fill in.

  The migration attributes **nothing**. There was one administrator in
  the live database and naming them the author of all 5 201 existing
  movements would have been signing on their behalf; `created_at` stays
  null for the same reason, since stamping `now()` would claim every old
  line was entered the day of the upgrade. "Author unknown" is the truth
  about those rows, and the Transactions dialog says so in those words.

  The limit is the same as the permissions': this records what the app
  wrote, and opposes nothing to someone editing `created_by` in the
  SQLite file. Still open: the inventory count session still has no
  record of its own — its posted movements now carry an author, but
  "who counted what, when" is not on file as a session.
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
- **The stock threshold is per article — done.** `StockStatus.pour`
  takes the threshold as a parameter; `products.stock_min` holds an
  article's own, and `company_settings.stock_min_defaut` the one that
  applies when it has none. Both arrive at 10, which is what the code
  applied to the whole catalogue before, so a migrated database behaves
  exactly as it did. Three rules the code holds: the article wins over
  the company; **no threshold is not a threshold of zero** — zero is a
  decision, "never warn me about this one"; and the threshold is
  resolved the same way in SQL and in Dart, because Rapports reads its
  badge from one and its KPI from the other and they must not judge the
  same row differently. `seuil_stock_test.dart` pins all three. Still
  open: a **reorder point** is not modelled — it would need a purchasing
  module to act on, and a column nothing reads is speculation.
- **A transfer between magasins is an operation — done.** `transferts`
  is the header: the date and the two stores, nothing else. What moved
  stays on the movements, which carry a `transfert_id`; copying the
  reference and quantity onto the header would let them diverge the
  first time someone corrects a line in Transactions. One transfer holds
  many articles, because a storekeeper loads a van, not an article.
  `TransfertRepository.creer` writes the header and both movements **in
  one transaction** — a half-written transfer is goods that left one
  store without arriving in the other. The counterparty text reads
  "Transfert vers Ekie" / "Transfert depuis Hysacam", so the history is
  legible without following the link, the same intent as "Inventaire
  physique". Negative stock is warned about, not refused, and measured
  against a snapshot taken before the run — the policy every other write
  path follows.

  The migration reprises **nothing**: past transfers were entered as an
  ordinary sortie and entrée, and nothing in the data says which went
  together. Pairing them after the fact on date and quantity would be
  guessing — the same refusal as the tiers reprise applied to movements
  — and an invented pair would make a real sale vanish from the figures.

  Still open: the Accueil KPIs count a transfer as both an entrée and a
  sortie, which overstates what entered and left the *business*. Stock
  must keep counting them (the goods really did move between stores), so
  the fix is a separate query for the business totals, not a filter on
  the stock derivation. Decide what those KPIs mean before changing
  them.
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

**The index pass runs once, after the whole chain — never inside a
step.** `createIndexStatements` is the index list for the *current*
schema, so a step that reapplies it builds today's indexes on its own
era's tables: `_migrateToV4`, running on a v3 database, reached for an
index on `tiers`, a table only v5 creates. The migration threw and the
app could not open its database at all — invisible to anyone already up
to date, fatal to anyone arriving from a version behind. The chain lives
in `DatabaseService.migrer`, public and static precisely so a test can
run it in its real order; a test that recopied the order would still
pass the day the order changed. `migration_v4_test.dart` pins it.

**A migration either lands whole or not at all.** sqflite runs
`onUpgrade` inside an exclusive transaction and writes the new version
number inside that same transaction (`sqflite_common`,
`database_mixin.dart`), so a half-migrated database is not a state that
can exist and DDL does not need to be replay-safe. Data *reprises* still
should be — not for interrupted migrations, but because rattaching rows
is the kind of maintenance someone reruns later.

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

**`setState(() => x = f())` is a trap when `f()` returns a Future.** An
arrow body *returns* its expression, so `setState(() => _future =
Future.value(rows))` hands Flutter a callback returning a Future.
Flutter asserts on that and the assignment never lands: the screen keeps
showing the previous data. It bit the Tiers search and the Inventaire
refresh, and it is invisible without a test that changes state and then
looks — the assert only fires in debug, and nothing about the code reads
as wrong. Use a block body whenever the assignment's value is a Future.

`AppEmptyState` and `AppErrorState` centre their content when the pane
has room and scroll when it does not. The icon, title, sentence and
button come to nearly 290 px — more than a phone in landscape leaves
once the page header and filter bar are placed — and an empty state is
exactly what a fresh install shows, so the overflow landed on a new
customer's first screen.

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
- `architecture_test.dart` lit les imports et refuse qu'un module
  atteigne l'intérieur d'un autre. Il échoue aussi quand une entrée de
  `_detteConnue` n'a plus de raison d'être, ce qui force à la retirer
  plutôt qu'à la laisser couvrir autre chose.
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
