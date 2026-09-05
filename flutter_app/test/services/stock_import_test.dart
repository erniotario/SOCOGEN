import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:socogen/data/db/schema.dart';
import 'package:socogen/data/repositories/product_repository.dart';
import 'package:socogen/data/repositories/stock_entry_repository.dart';
import 'package:socogen/data/repositories/stock_output_repository.dart';
import 'package:socogen/data/repositories/store_repository.dart';
import 'package:socogen/services/excel/stock_import_service.dart';

/// An empty database with only the two magasins, so the counts a test
/// asserts belong to the import and not to a fixture.
Future<Database> _openDb() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: AppSchema.version,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        for (final statement in AppSchema.createStatements) {
          await db.execute(statement);
        }
      },
    ),
  );
  await db.insert('stores', {'id': 1, 'name': 'Magasin Central'});
  await db.insert('stores', {'id': 2, 'name': 'Dépôt Nord'});
  return db;
}

StockImportService _service(Database db) => StockImportService(
      productRepository: ProductRepository(database: db),
      storeRepository: StoreRepository(database: db),
      entryRepository: StockEntryRepository(database: db),
      outputRepository: StockOutputRepository(database: db),
    );

CellValue _t(String v) => TextCellValue(v);
CellValue _n(int v) => IntCellValue(v);

/// Builds a workbook and round-trips it through the encoder, so the test
/// reads cells back the way a real file would decode.
Excel _workbook(Map<String, List<List<CellValue>>> sheets) {
  final excel = Excel.createExcel();
  for (final entry in sheets.entries) {
    final sheet = excel[entry.key];
    for (final row in entry.value) {
      sheet.appendRow(row);
    }
  }
  excel.delete('Sheet1');
  return Excel.decodeBytes(excel.encode()!);
}

List<List<CellValue>> get _catalogue => [
      [_t('RÉFÉRENCE'), _t('DÉSIGNATION'), _t('UNITÉ'), _t('STOCK INITIAL'), _t('MAGASIN')],
      [_t('ART-1'), _t('Ciment 42.5'), _t('sac'), _n(100), _t('Magasin Central')],
      [_t('ART-2'), _t('Fer à béton'), _t('barre'), _n(50), _t('Dépôt Nord')],
    ];

void main() {
  late Database db;

  setUp(() async => db = await _openDb());
  tearDown(() async => db.close());

  group('catalogue', () {
    test('creates products and their opening stock per magasin', () async {
      final report =
          await _service(db).importWorkbook(_workbook({'Produits': _catalogue}));

      expect(report.products, 2);
      expect(report.stocks, 2);

      final products = ProductRepository(database: db);
      final art1 = (await products.getByReference('ART-1'))!;
      expect(art1.designation, 'Ciment 42.5');
      expect(art1.unit, 'sac');

      final availability =
          await products.getStoreAvailability('ART-1', art1.id);
      expect(availability.single.storeName, 'Magasin Central');
      expect(availability.single.available, 100);
    });

    test('a second run adds nothing', () async {
      final book = _workbook({'Produits': _catalogue});
      await _service(db).importWorkbook(book);
      final second = await _service(db)
          .importWorkbook(_workbook({'Produits': _catalogue}));

      expect(second.products, 0);
      expect(second.stocks, 0);
      expect(second.skipped, 2);
    });
  });

  group('mouvements', () {
    Excel bookWithMovements() => _workbook({
          'Produits': _catalogue,
          'Entrées': [
            [_t('DATE'), _t('RÉFÉRENCE'), _t('MAGASIN'), _t('QUANTITÉ'), _t('FOURNISSEUR')],
            [_t('2026-01-15'), _t('ART-1'), _t('Magasin Central'), _n(40), _t('SOCACIM')],
          ],
          'Sorties': [
            [_t('DATE'), _t('RÉFÉRENCE'), _t('MAGASIN'), _t('QUANTITÉ'), _t('N° FACTURE'), _t('DESTINATION')],
            [_t('2026-02-03'), _t('ART-1'), _t('Magasin Central'), _n(25), _t('FA-77'), _t('Chantier Est')],
          ],
        });

    test('opening stock plus movements gives the current stock', () async {
      final report = await _service(db).importWorkbook(bookWithMovements());

      expect(report.entries, 1);
      expect(report.outputs, 1);

      final products = ProductRepository(database: db);
      final art1 = (await products.getByReference('ART-1'))!;
      final availability =
          await products.getStoreAvailability('ART-1', art1.id);

      // 100 d'ouverture + 40 entrées - 25 sorties
      expect(availability.single.available, 115);
    });

    test('re-importing the same file does not double the stock', () async {
      await _service(db).importWorkbook(bookWithMovements());
      final second = await _service(db).importWorkbook(bookWithMovements());

      expect(second.entries, 0, reason: 'entrée déjà présente');
      expect(second.outputs, 0, reason: 'sortie déjà présente');

      final products = ProductRepository(database: db);
      final art1 = (await products.getByReference('ART-1'))!;
      final availability =
          await products.getStoreAvailability('ART-1', art1.id);
      expect(availability.single.available, 115);
    });

    test('a movement for an unknown magasin is skipped, not misfiled',
        () async {
      final report = await _service(db).importWorkbook(_workbook({
        'Produits': _catalogue,
        'Entrées': [
          [_t('DATE'), _t('RÉFÉRENCE'), _t('MAGASIN'), _t('QUANTITÉ')],
          [_t('2026-01-15'), _t('ART-1'), _t('Magasin Fantôme'), _n(40)],
        ],
      }));

      expect(report.entries, 0);
      expect(report.problems, isNotEmpty);

      // The quantity must not have landed in Magasin Central instead.
      final products = ProductRepository(database: db);
      final art1 = (await products.getByReference('ART-1'))!;
      final availability =
          await products.getStoreAvailability('ART-1', art1.id);
      expect(availability.single.available, 100);
    });
  });

  group('dates', () {
    test('are read day-first, as a French export writes them', () async {
      await _service(db).importWorkbook(_workbook({
        'Produits': _catalogue,
        'Entrées': [
          [_t('DATE'), _t('RÉFÉRENCE'), _t('MAGASIN'), _t('QUANTITÉ')],
          [_t('05/03/2026'), _t('ART-1'), _t('Magasin Central'), _n(7)],
        ],
      }));

      final rows = await db.query('stock_entries', columns: ['date']);
      // 5 March, never 3 May.
      expect(rows.single['date'], '2026-03-05');
    });

    test('an unreadable date is reported rather than guessed', () async {
      final report = await _service(db).importWorkbook(_workbook({
        'Produits': _catalogue,
        'Entrées': [
          [_t('DATE'), _t('RÉFÉRENCE'), _t('MAGASIN'), _t('QUANTITÉ')],
          [_t('la semaine derniere'), _t('ART-1'), _t('Magasin Central'), _n(7)],
        ],
      }));

      expect(report.entries, 0);
      expect(report.problems.single, contains('date'));
      expect(await db.query('stock_entries'), isEmpty);
    });
  });

  test('a single unnamed sheet is still read as the catalogue', () async {
    // The shape every workbook had before movements were supported.
    final report =
        await _service(db).importWorkbook(_workbook({'Feuil1': _catalogue}));
    expect(report.products, 2);
    expect(report.problems, isEmpty);
  });

  test('a sheet skipped for its name is reported, not passed over', () async {
    final report = await _service(db).importWorkbook(_workbook({
      'Produits': _catalogue,
      // What a Sage export calls its movements when nobody renamed them.
      'Mouvements': [
        [_t('DATE'), _t('RÉFÉRENCE'), _t('MAGASIN'), _t('QUANTITÉ')],
        [_t('2026-01-15'), _t('ART-1'), _t('Magasin Central'), _n(40)],
      ],
    }));

    expect(report.products, 2, reason: 'le catalogue est lu normalement');
    expect(report.sheetsRead.single, contains('Produits'));
    expect(report.problems.single, contains('Mouvements'));
  });
}
