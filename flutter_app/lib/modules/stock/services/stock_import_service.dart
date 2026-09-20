import 'package:excel/excel.dart';

import 'package:socogen/modules/stock/models/stock_entry.dart';
import 'package:socogen/modules/stock/models/stock_output.dart';
import 'package:socogen/modules/stock/models/store.dart';
import 'package:socogen/shared/models/view_models.dart';
import 'package:socogen/modules/catalogue/services/catalogue_service.dart';
import 'package:socogen/core/money/montant.dart';
import 'package:socogen/modules/stock/services/stock_service.dart';
import 'package:socogen/modules/tiers/services/tiers_service.dart';
import 'package:socogen/modules/rapports/repositories/report_repository.dart';
import 'package:socogen/modules/stock/repositories/stock_entry_repository.dart';
import 'package:socogen/modules/stock/repositories/stock_output_repository.dart';
import 'package:socogen/modules/stock/repositories/store_repository.dart';

/// What one import run changed, per kind of record.
///
/// `skipped` counts rows deliberately left alone — a product/store pair
/// that already carries an opening stock, or a movement already present
/// — as opposed to [problems], which lists rows that could not be read.
class ImportReport {
  int products = 0;
  int stocks = 0;
  int entries = 0;
  int outputs = 0;
  int skipped = 0;

  /// Prix repris depuis le classeur sur un article qui n'en avait pas.
  int prixRemplis = 0;

  /// Prix laissés tels quels parce que l'article en avait déjà un.
  ///
  /// Compté et non tu : un prix déjà en place est une décision de
  /// quelqu'un, et savoir que l'import ne l'a pas touché est ce qui
  /// permet d'y revenir sciemment.
  int prixConserves = 0;

  /// (product, store) balances this run drove below zero, or drove
  /// further below zero than they already were. Pre-existing negatives
  /// are not counted: Rapports already flags those, and blaming them on
  /// whoever happened to run the next import is how a real warning gets
  /// learned as noise.
  int negatives = 0;

  /// Sheets found in the workbook, by the role they were read as.
  final List<String> sheetsRead = [];

  /// Human-readable notes worth showing after the run: unknown stores,
  /// unparseable dates, movements for a reference no product matches.
  final List<String> problems = [];

  /// One-line summary for a snackbar.
  String get summary {
    final parts = <String>[
      if (products > 0) '$products produit(s)',
      if (stocks > 0) '$stocks stock(s)',
      if (entries > 0) '$entries entrée(s)',
      if (outputs > 0) '$outputs sortie(s)',
      if (prixRemplis > 0) '$prixRemplis prix',
    ];
    if (parts.isEmpty) return 'Rien à importer.';
    var text = 'Importé : ${parts.join(', ')}';
    if (skipped > 0) text += ' — $skipped ignoré(s)';
    // Dit, et pas tu : c'est ce qui permet de revenir sciemment sur un
    // prix que l'import a refusé d'écraser.
    if (prixConserves > 0) {
      text += ' — $prixConserves prix déjà en place, conservé(s)';
    }
    if (negatives > 0) text += ' — $negatives stock(s) négatif(s)';
    return text;
  }
}

/// Reads a Sage-style export workbook into the local database.
///
/// The workbook is read sheet by sheet, each routed by its name:
/// *Produits* carries the catalogue and its opening stock per store,
/// *Entrées* and *Sorties* carry the movements. A single-sheet workbook
/// with no recognised name is read as the catalogue, which keeps the
/// files that worked before this class was introduced working.
///
/// Opening stock and movements are imported together on purpose: current
/// stock is derived as `initial_stock + entrées - sorties`, so the stock
/// column must hold the *opening* figure. Feeding it a current stock and
/// then replaying the movements would count them twice.
class StockImportService {
  StockImportService({
    CatalogueService? catalogueService,
    StoreRepository? storeRepository,
    StockEntryRepository? entryRepository,
    StockOutputRepository? outputRepository,
    ReportRepository? reportRepository,
    StockService? stockService,
    TiersService? tiersService,
  })  : _catalogue = catalogueService ?? CatalogueService(),
        _tiers = tiersService ?? TiersService(),
        _stock = stockService ?? StockService(),
        _stores = storeRepository ?? StoreRepository(),
        _entries = entryRepository ?? StockEntryRepository(),
        _outputs = outputRepository ?? StockOutputRepository(),
        _reports = reportRepository ?? ReportRepository();

  final CatalogueService _catalogue;
  final StockService _stock;
  final StoreRepository _stores;
  final StockEntryRepository _entries;
  final StockOutputRepository _outputs;
  final ReportRepository _reports;
  final TiersService _tiers;

  /// Les fiches existantes, indexées par nom, relevées une fois avant la
  /// boucle.
  ///
  /// Une requête par ligne coûterait des milliers d'allers-retours sur
  /// un fichier Sage complet — la même leçon que le rapport qui
  /// balayait les mouvements par produit.
  Map<String, int> _fichesParNom = const {};

  Future<void> _releverLesFiches() async {
    final fiches = await _tiers.lister(actifsSeuls: false);
    _fichesParNom = {for (final t in fiches) t.nom: t.id};
  }

  /// La fiche portant exactement ce nom, s'il y en a une.
  ///
  /// Égalité exacte, et rien d'autre : c'est la règle de la reprise, et
  /// la même raison. L'import ne crée pas de fiche non plus — il en
  /// créerait des centaines d'un coup, dont les quasi-doublons que ce
  /// module existe pour éviter. Un mouvement sans fiche garde son nom
  /// en clair et reste rattachable ensuite.
  int? _ficheDe(String nom) => _fichesParNom[nom.trim()];

  /// Enough to act on without burying the rest of the report.
  static const int _maxNegativesListed = 10;

  Future<ImportReport> importWorkbook(Excel workbook) async {
    final report = ImportReport();
    if (workbook.tables.isEmpty) {
      throw Exception('Le fichier Excel est vide.');
    }

    final stores = await _stores.getAllStores();
    if (stores.isEmpty) {
      throw Exception('Aucun magasin : créez-en un avant d\'importer.');
    }

    final negativesBefore = await _negativesBefore();
    await _releverLesFiches();

    final unrecognised = <String>[];
    for (final name in workbook.tables.keys) {
      final rows = workbook.tables[name]!.rows;
      if (rows.isEmpty) continue;
      final role = _roleOf(name);
      if (role == null) {
        unrecognised.add(name);
        continue;
      }
      report.sheetsRead.add('$name → ${role.label}');
      switch (role) {
        case _SheetRole.catalogue:
          await _importCatalogue(rows, stores, report);
        case _SheetRole.entries:
          await _importEntries(rows, stores, report);
        case _SheetRole.outputs:
          await _importOutputs(rows, stores, report);
      }
    }

    if (report.sheetsRead.isEmpty) {
      // No sheet named recognisably: treat the first as the catalogue, the
      // shape every workbook had before movements were supported.
      final first = workbook.tables.keys.first;
      report.sheetsRead.add('$first → produits');
      await _importCatalogue(workbook.tables[first]!.rows, stores, report);
      await _flagNegativeBalances(negativesBefore, report);
      return report;
    }

    // A sheet skipped for its name is data the operator believes was
    // imported, so say so rather than leaving a silent gap.
    for (final name in unrecognised) {
      report.problems.add(
        'Feuille « $name » ignorée : nom non reconnu '
        '(attendus : Produits, Entrées, Sorties).',
      );
    }

    await _flagNegativeBalances(negativesBefore, report);
    return report;
  }

  /// Names the (product, store) pairs this run left below zero.
  ///
  /// Movements arrive as a batch in file order, so checking row by row
  /// would cry wolf -- a sortie legitimately precedes its entrée in
  /// plenty of exports, and the balance is only meaningful once the
  /// whole sheet is in. What matters is where the run *left* each
  /// magasin, so the balances are read once at the end and compared
  /// against the snapshot taken before the first sheet.
  Future<void> _flagNegativeBalances(
    Map<String, int> before,
    ImportReport report,
  ) async {
    final after = await _reports.getReportRows(
      status: StockStatus.stockNegatif,
    );

    final worsened = after.where((row) {
      final previous = before['${row.reference}|${row.storeId}'];
      return previous == null || row.current < previous;
    }).toList();

    report.negatives = worsened.length;
    for (final row in worsened.take(_maxNegativesListed)) {
      report.problems.add(
        'Stock négatif après import : ${row.reference} '
        '(${row.storeName}) à ${row.current}. À régulariser.',
      );
    }
    final remaining = worsened.length - _maxNegativesListed;
    if (remaining > 0) {
      report.problems.add(
        '… et $remaining autre(s) référence(s) en stock négatif.',
      );
    }
  }

  /// Balances already below zero before the import touched anything,
  /// keyed by reference and store.
  Future<Map<String, int>> _negativesBefore() async {
    final rows = await _reports.getReportRows(
      status: StockStatus.stockNegatif,
    );
    return {
      for (final row in rows) '${row.reference}|${row.storeId}': row.current,
    };
  }


  // --- Catalogue + opening stock ---------------------------------------

  Future<void> _importCatalogue(
    List<List<Data?>> rows,
    List<Store> stores,
    ImportReport report,
  ) async {
    final map = _HeaderMap(rows.first);
    final referenceCol = map.find(_refNames);
    final designationCol = map.find(_designationNames);
    if (referenceCol == null || designationCol == null) {
      throw Exception(
        'Colonnes obligatoires manquantes : référence et désignation.',
      );
    }
    final unitCol = map.find(_unitNames);
    final prixVenteCol = map.find(_prixVenteNames);
    final prixAchatCol = map.find(_prixAchatNames);
    final stockCol = map.find(_openingStockNames);
    final storeCol = map.find(_storeNames);

    final defaultStoreId = stores.first.id;

    for (var r = 1; r < rows.length; r++) {
      final row = rows[r];
      final reference = _text(row, referenceCol);
      if (reference == null || reference.isEmpty) continue;
      final designation = _text(row, designationCol);
      if (designation == null || designation.isEmpty) continue;

      final unit = _text(row, unitCol) ?? 'unité';
      final openingStock = _int(row, stockCol) ?? 0;

      final storeId = _resolveStore(row, storeCol, stores) ?? defaultStoreId;

      final prixVente = _montant(row, prixVenteCol);
      final prixAchat = _montant(row, prixAchatCol);

      final existing = await _catalogue.chercherParReference(reference);
      final productId = existing?.id ??
          await _catalogue.creerArticle(
            reference: reference,
            designation: designation,
            unite: unit,
            prixVenteUnites: prixVente?.unites,
            prixAchatUnites: prixAchat?.unites,
          );
      if (existing == null) {
        report.products++;
        if (prixVente != null || prixAchat != null) report.prixRemplis++;
      } else if (prixVente != null || prixAchat != null) {
        // La règle appartient au catalogue : remplir ce qui manque,
        // ne jamais écraser ce qui est posé.
        final fait = await _catalogue.completerPrix(
          reference,
          prixVente: prixVente,
          prixAchat: prixAchat,
        );
        if (fait.pose) report.prixRemplis++;
        if (fait.conserve) report.prixConserves++;
      }

      if (await _stock.ligneDeStockExiste(
        articleId: productId,
        magasinId: storeId,
      )) {
        report.skipped++;
        continue;
      }
      await _stock.definirStockOuverture(
        articleId: productId,
        magasinId: storeId,
        quantite: openingStock,
      );
      report.stocks++;
    }
  }

  // --- Movements --------------------------------------------------------

  Future<void> _importEntries(
    List<List<Data?>> rows,
    List<Store> stores,
    ImportReport report,
  ) async {
    final map = _HeaderMap(rows.first);
    final referenceCol = map.find(_refNames);
    final quantityCol = map.find(_quantityNames);
    if (referenceCol == null || quantityCol == null) {
      throw Exception(
        'Feuille Entrées : colonnes référence et quantité obligatoires.',
      );
    }
    final dateCol = map.find(_dateNames);
    final designationCol = map.find(_designationNames);
    final storeCol = map.find(_storeNames);
    final supplierCol = map.find(_supplierNames);

    // Replaying a file that was already imported would double the stock,
    // so remember what is on file and skip exact repeats.
    final seen = {
      for (final row in await _entries.getAll())
        _movementKey(
          row.entry.date,
          row.entry.reference,
          row.entry.storeId,
          row.entry.quantity,
          row.entry.supplier,
        ),
    };

    for (var r = 1; r < rows.length; r++) {
      final row = rows[r];
      final reference = _text(row, referenceCol);
      if (reference == null || reference.isEmpty) continue;

      final quantity = _int(row, quantityCol);
      if (quantity == null || quantity == 0) {
        report.skipped++;
        continue;
      }

      final date = _date(row, dateCol);
      if (date == null) {
        report.problems.add('Entrées ligne ${r + 1} : date illisible.');
        report.skipped++;
        continue;
      }

      final storeId = _resolveStore(row, storeCol, stores);
      if (storeId == null) {
        report.problems.add('Entrées ligne ${r + 1} : magasin inconnu.');
        report.skipped++;
        continue;
      }

      final supplier = _text(row, supplierCol) ?? '';
      final key = _movementKey(date, reference, storeId, quantity, supplier);
      if (!seen.add(key)) {
        report.skipped++;
        continue;
      }

      await _entries.create(StockEntry(
        id: 0,
        date: date,
        supplier: supplier,
        reference: reference,
        designation: _text(row, designationCol) ?? reference,
        storeId: storeId,
        quantity: quantity,
        tiersId: _ficheDe(supplier),
      ));
      report.entries++;
    }
  }

  Future<void> _importOutputs(
    List<List<Data?>> rows,
    List<Store> stores,
    ImportReport report,
  ) async {
    final map = _HeaderMap(rows.first);
    final referenceCol = map.find(_refNames);
    final quantityCol = map.find(_quantityNames);
    if (referenceCol == null || quantityCol == null) {
      throw Exception(
        'Feuille Sorties : colonnes référence et quantité obligatoires.',
      );
    }
    final dateCol = map.find(_dateNames);
    final designationCol = map.find(_designationNames);
    final storeCol = map.find(_storeNames);
    final invoiceCol = map.find(_invoiceNames);
    final destinationCol = map.find(_destinationNames);

    final seen = {
      for (final row in await _outputs.getAll())
        _movementKey(
          row.output.date,
          row.output.reference,
          row.output.storeId,
          row.output.quantity,
          row.output.invoiceNumber,
        ),
    };

    for (var r = 1; r < rows.length; r++) {
      final row = rows[r];
      final reference = _text(row, referenceCol);
      if (reference == null || reference.isEmpty) continue;

      final quantity = _int(row, quantityCol);
      if (quantity == null || quantity == 0) {
        report.skipped++;
        continue;
      }

      final date = _date(row, dateCol);
      if (date == null) {
        report.problems.add('Sorties ligne ${r + 1} : date illisible.');
        report.skipped++;
        continue;
      }

      final storeId = _resolveStore(row, storeCol, stores);
      if (storeId == null) {
        report.problems.add('Sorties ligne ${r + 1} : magasin inconnu.');
        report.skipped++;
        continue;
      }

      final invoice = _text(row, invoiceCol) ?? '';
      final key = _movementKey(date, reference, storeId, quantity, invoice);
      if (!seen.add(key)) {
        report.skipped++;
        continue;
      }

      final destination = _text(row, destinationCol) ?? '';
      await _outputs.create(StockOutput(
        id: 0,
        date: date,
        reference: reference,
        designation: _text(row, designationCol) ?? reference,
        invoiceNumber: invoice,
        storeId: storeId,
        destination: destination,
        quantity: quantity,
        tiersId: _ficheDe(destination),
      ));
      report.outputs++;
    }
  }

  // --- Shared helpers ---------------------------------------------------

  String _movementKey(
    String date,
    String reference,
    int storeId,
    int quantity,
    String extra,
  ) =>
      '$date|${reference.toLowerCase()}|$storeId|$quantity|${extra.toLowerCase()}';

  /// Resolves the store named in [column], or null when the name is
  /// present but matches nothing. A movement filed against the wrong
  /// store silently corrupts that store's balance, so callers treat null
  /// as a reason to skip rather than falling back to a default.
  int? _resolveStore(List<Data?> row, int? column, List<Store> stores) {
    final name = _text(row, column);
    if (name == null || name.isEmpty) return null;
    final wanted = _fold(name);
    for (final store in stores) {
      if (_fold(store.name) == wanted) return store.id;
    }
    return null;
  }
}

// --- Sheet routing ------------------------------------------------------

enum _SheetRole {
  catalogue('produits'),
  entries('entrées'),
  outputs('sorties');

  const _SheetRole(this.label);
  final String label;
}

_SheetRole? _roleOf(String sheetName) {
  final name = _fold(sheetName);
  if (name.contains('entree')) return _SheetRole.entries;
  if (name.contains('sortie')) return _SheetRole.outputs;
  if (name.contains('produit') ||
      name.contains('article') ||
      name.contains('stock') ||
      name.contains('catalogue')) {
    return _SheetRole.catalogue;
  }
  return null;
}

// --- Header matching ----------------------------------------------------

const _refNames = ['reference', 'ref', 'code', 'code article', 'article'];
const _designationNames = [
  'designation',
  'description',
  'libelle',
  'intitule',
  'nom',
];
const _unitNames = ['unite', 'unit', 'u'];
const _prixVenteNames = [
  'prix de vente',
  'prix vente',
  'prix_vente',
  'pv',
  'prix unitaire',
  'pu',
];
const _prixAchatNames = [
  "prix d'achat",
  'prix achat',
  'prix_achat',
  'pa',
  'prix de revient',
  'cout',
];
const _openingStockNames = [
  'stock initial',
  'initial stock',
  'initial_stock',
  'stock ouverture',
  'stock d ouverture',
  'stock',
  'quantite initiale',
];
const _storeNames = ['magasin', 'store', 'store name', 'nom magasin', 'depot'];
const _dateNames = ['date', 'date mouvement', 'date piece'];
const _quantityNames = ['quantite', 'quantity', 'qte', 'qty', 'nombre'];
const _supplierNames = ['fournisseur', 'supplier'];
const _invoiceNames = [
  'facture',
  'n facture',
  'no facture',
  'numero facture',
  'invoice',
  'invoice number',
  'piece',
];
const _destinationNames = ['destination', 'client', 'destinataire'];

/// Header row indexed by folded column name.
class _HeaderMap {
  _HeaderMap(List<Data?> header) {
    for (var i = 0; i < header.length; i++) {
      final label = _cellText(header[i]?.value);
      if (label == null) continue;
      final key = _fold(label);
      if (key.isNotEmpty) _byName.putIfAbsent(key, () => i);
    }
  }

  final Map<String, int> _byName = {};

  int? find(List<String> candidates) {
    for (final candidate in candidates) {
      final hit = _byName[_fold(candidate)];
      if (hit != null) return hit;
    }
    return null;
  }
}

/// Lowercases, strips accents and collapses punctuation, so `N° Facture`,
/// `n facture` and `No. facture` all land on the same key.
String _fold(String value) {
  const accents = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'î': 'i', 'ï': 'i', 'í': 'i',
    'ô': 'o', 'ö': 'o', 'ó': 'o',
    'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c',
  };
  final buffer = StringBuffer();
  for (final char in value.toLowerCase().split('')) {
    final plain = accents[char] ?? char;
    if (RegExp(r'[a-z0-9 ]').hasMatch(plain)) {
      buffer.write(plain);
    } else {
      buffer.write(' ');
    }
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

// --- Cell reading -------------------------------------------------------

String? _text(List<Data?> row, int? column) {
  if (column == null || column >= row.length) return null;
  final value = _cellText(row[column]?.value)?.trim();
  return (value == null || value.isEmpty) ? null : value;
}

/// Lit une cellule comme un montant.
///
/// Une cellule numérique est prise telle quelle ; un texte passe par
/// [Montant.depuisSaisie], qui accepte les formes françaises « 18 500 »
/// et « 18500,50 ». Une cellule vide ou illisible rend null, et
/// l'appelant décide si cela veut dire « pas de prix » ou « corrigez ».
///
/// Un prix négatif est refusé ici plutôt que plus loin : dans un
/// classeur il ne signifie rien, et le laisser passer contaminerait
/// chaque total qui le rencontrerait.
Montant? _montant(List<Data?> row, int? column) {
  if (column == null || column >= row.length) return null;
  final brut = row[column]?.value;
  if (brut == null) return null;
  final entier = _cellInt(brut);
  final montant = entier != null
      ? Montant.depuisUnite(entier)
      : Montant.depuisSaisie(_cellText(brut) ?? '');
  if (montant == null || montant.estNegatif) return null;
  return montant;
}

int? _int(List<Data?> row, int? column) {
  if (column == null || column >= row.length) return null;
  return _cellInt(row[column]?.value);
}

/// Reads a cell as a stored date string (`yyyy-MM-dd`), accepting the
/// day-first forms a French Sage export produces as well as the serial
/// numbers Excel leaves behind when a date column loses its formatting.
String? _date(List<Data?> row, int? column) {
  if (column == null || column >= row.length) return null;
  final value = row[column]?.value;
  if (value == null) return null;

  if (value is DateCellValue) {
    return _iso(DateTime(value.year, value.month, value.day));
  }
  if (value is DateTimeCellValue) {
    return _iso(DateTime(value.year, value.month, value.day));
  }
  if (value is IntCellValue) return _fromSerial(value.value);
  if (value is DoubleCellValue) return _fromSerial(value.value.toInt());

  final text = _cellText(value)?.trim();
  if (text == null || text.isEmpty) return null;

  final match = RegExp(r'^(\d{1,4})[-/.](\d{1,2})[-/.](\d{1,4})').firstMatch(text);
  if (match == null) return null;
  final a = int.parse(match.group(1)!);
  final b = int.parse(match.group(2)!);
  final c = int.parse(match.group(3)!);

  // A four-digit leading group is a year, otherwise the French day-first
  // order applies — 03/09/2026 is 3 September, never 9 March.
  final date = a > 31 ? DateTime(a, b, c) : DateTime(c < 100 ? 2000 + c : c, b, a);
  if (date.month < 1 || date.month > 12 || date.day < 1 || date.day > 31) {
    return null;
  }
  return _iso(date);
}

/// Excel counts days from 1899-12-30 on Windows.
String? _fromSerial(int serial) {
  if (serial < 1 || serial > 100000) return null;
  return _iso(DateTime(1899, 12, 30).add(Duration(days: serial)));
}

String _iso(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String? _cellText(CellValue? value) {
  return switch (value) {
    null => null,
    TextCellValue v => v.value.toString().trim(),
    IntCellValue v => '${v.value}',
    DoubleCellValue v => '${v.value}',
    BoolCellValue v => '${v.value}',
    _ => value.toString(),
  };
}

int? _cellInt(CellValue? value) {
  return switch (value) {
    null => null,
    IntCellValue v => v.value,
    DoubleCellValue v => v.value.round(),
    TextCellValue v => int.tryParse(v.value.toString().trim()),
    _ => null,
  };
}
