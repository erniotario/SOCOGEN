import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socogen/modules/stock/services/stock_service.dart';
import 'package:socogen/modules/catalogue/services/catalogue_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:socogen/core/db/schema.dart';
import 'package:socogen/modules/catalogue/repositories/product_repository.dart';
import 'package:socogen/modules/stock/repositories/stock_repository.dart';
import 'package:socogen/modules/rapports/repositories/report_repository.dart';
import 'package:socogen/modules/stock/repositories/stock_entry_repository.dart';
import 'package:socogen/modules/stock/repositories/stock_output_repository.dart';
import 'package:socogen/modules/stock/repositories/store_repository.dart';
import 'package:socogen/modules/stock/services/stock_import_service.dart';
import 'package:socogen/modules/tiers/repositories/tiers_repository.dart';
import 'package:socogen/modules/tiers/services/tiers_service.dart';
import 'package:socogen/shared/models/tiers.dart';

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
      catalogueService: CatalogueService(
        productRepository: ProductRepository(database: db),
      ),
      stockService: StockService(
        stockRepository: StockRepository(database: db),
      ),
      storeRepository: StoreRepository(database: db),
      entryRepository: StockEntryRepository(database: db),
      outputRepository: StockOutputRepository(database: db),
      reportRepository: ReportRepository(database: db),
      tiersService: TiersService(
        tiersRepository: TiersRepository(database: db),
      ),
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
      final stock = StockRepository(database: db);
      final art1 = (await products.getByReference('ART-1'))!;
      expect(art1.designation, 'Ciment 42.5');
      expect(art1.unit, 'sac');

      final availability =
          await stock.getStoreAvailability('ART-1', art1.id);
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
      final stock = StockRepository(database: db);
      final art1 = (await products.getByReference('ART-1'))!;
      final availability =
          await stock.getStoreAvailability('ART-1', art1.id);

      // 100 d'ouverture + 40 entrées - 25 sorties
      expect(availability.single.available, 115);
    });

    test('re-importing the same file does not double the stock', () async {
      await _service(db).importWorkbook(bookWithMovements());
      final second = await _service(db).importWorkbook(bookWithMovements());

      expect(second.entries, 0, reason: 'entrée déjà présente');
      expect(second.outputs, 0, reason: 'sortie déjà présente');

      final products = ProductRepository(database: db);
      final stock = StockRepository(database: db);
      final art1 = (await products.getByReference('ART-1'))!;
      final availability =
          await stock.getStoreAvailability('ART-1', art1.id);
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
      final stock = StockRepository(database: db);
      final art1 = (await products.getByReference('ART-1'))!;
      final availability =
          await stock.getStoreAvailability('ART-1', art1.id);
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

  group('stock négatif', () {
    /// 100 d'ouverture, puis une sortie de 250 : le magasin finit à -150.
    Excel bookDrivingArt1Negative() => _workbook({
          'Produits': _catalogue,
          'Sorties': [
            [_t('DATE'), _t('RÉFÉRENCE'), _t('MAGASIN'), _t('QUANTITÉ'), _t('N° FACTURE'), _t('DESTINATION')],
            [_t('2026-02-03'), _t('ART-1'), _t('Magasin Central'), _n(250), _t('FA-99'), _t('Chantier Est')],
          ],
        });

    test('a run that drives a magasin below zero says so', () async {
      final report = await _service(db).importWorkbook(bookDrivingArt1Negative());

      expect(report.outputs, 1, reason: 'la sortie est enregistrée, pas refusée');
      expect(report.negatives, 1);
      expect(
        report.problems.any((p) => p.contains('ART-1') && p.contains('-150')),
        isTrue,
        reason: 'le rapport doit nommer la référence et le solde : '
            '${report.problems}',
      );
      expect(report.summary, contains('négatif'));
    });

    test('a clean run says nothing about negatives', () async {
      final report = await _service(db).importWorkbook(_workbook({
        'Produits': _catalogue,
        'Sorties': [
          [_t('DATE'), _t('RÉFÉRENCE'), _t('MAGASIN'), _t('QUANTITÉ'), _t('N° FACTURE'), _t('DESTINATION')],
          [_t('2026-02-03'), _t('ART-1'), _t('Magasin Central'), _n(25), _t('FA-77'), _t('Chantier Est')],
        ],
      }));

      expect(report.negatives, 0);
      expect(report.problems, isEmpty);
      expect(report.summary, isNot(contains('négatif')));
    });

    test('a negative already on file is not blamed on the next import',
        () async {
      // First run puts ART-1 at -150 and reports it.
      final first = await _service(db).importWorkbook(bookDrivingArt1Negative());
      expect(first.negatives, 1);

      // A second, unrelated import leaves that balance exactly as it
      // was. Rapports still flags it; this run did not cause it, so the
      // run must not claim it -- a warning that fires every time is one
      // the operator learns to scroll past.
      final second = await _service(db).importWorkbook(_workbook({
        'Entrées': [
          [_t('DATE'), _t('RÉFÉRENCE'), _t('MAGASIN'), _t('QUANTITÉ'), _t('FOURNISSEUR')],
          [_t('2026-03-01'), _t('ART-2'), _t('Dépôt Nord'), _n(5), _t('SOCACIM')],
        ],
      }));

      expect(second.entries, 1);
      expect(second.negatives, 0);
      expect(
        second.problems.any((p) => p.contains('ART-1')),
        isFalse,
        reason: 'déjà négatif avant ce run : ${second.problems}',
      );
    });

    test('a run that digs an existing negative deeper says so again',
        () async {
      await _service(db).importWorkbook(bookDrivingArt1Negative());

      final second = await _service(db).importWorkbook(_workbook({
        'Sorties': [
          [_t('DATE'), _t('RÉFÉRENCE'), _t('MAGASIN'), _t('QUANTITÉ'), _t('N° FACTURE'), _t('DESTINATION')],
          [_t('2026-04-04'), _t('ART-1'), _t('Magasin Central'), _n(10), _t('FA-100'), _t('Chantier Est')],
        ],
      }));

      expect(second.outputs, 1);
      expect(second.negatives, 1, reason: '-150 est devenu -160');
      expect(
        second.problems.any((p) => p.contains('-160')),
        isTrue,
        reason: '${second.problems}',
      );
    });
  });


  group('rattachement aux fiches', () {
    Future<int> creerFiche(String nom, TypeTiers type) =>
        TiersRepository(database: db).create(Tiers(
          id: 0,
          code: type == TypeTiers.client ? 'C0001' : 'F0001',
          nom: nom,
          type: type,
        ));

    Excel livreAvec(String fournisseur, String destination) => _workbook({
          'Produits': _catalogue,
          'Entrées': [
            [_t('DATE'), _t('RÉFÉRENCE'), _t('MAGASIN'), _t('QUANTITÉ'),
              _t('FOURNISSEUR')],
            [_t('2026-01-15'), _t('ART-1'), _t('Magasin Central'), _n(40),
              _t(fournisseur)],
          ],
          'Sorties': [
            [_t('DATE'), _t('RÉFÉRENCE'), _t('MAGASIN'), _t('QUANTITÉ'),
              _t('N° FACTURE'), _t('DESTINATION')],
            [_t('2026-02-03'), _t('ART-1'), _t('Magasin Central'), _n(5),
              _t('FA-77'), _t(destination)],
          ],
        });

    test('un mouvement importé trouve la fiche qui porte ce nom exact',
        () async {
      final fournisseur = await creerFiche('SOCACIM', TypeTiers.fournisseur);
      final client = await creerFiche('BMC', TypeTiers.client);

      await _service(db).importWorkbook(livreAvec('SOCACIM', 'BMC'));

      expect(
        (await db.query('stock_entries')).single['tiers_id'],
        fournisseur,
      );
      expect(
        (await db.query('stock_outputs')).single['tiers_id'],
        client,
      );
    });

    test("l'import ne crée aucune fiche", () async {
      // Il en créerait des centaines d'un coup, quasi-doublons compris.
      // Le mouvement garde son nom en clair et reste rattachable après.
      await _service(db).importWorkbook(livreAvec('INCONNU', 'AUTRE'));

      expect(await db.query('tiers'), isEmpty);
      expect((await db.query('stock_entries')).single['tiers_id'], isNull);
      expect((await db.query('stock_entries')).single['supplier'], 'INCONNU');
    });

    test('un nom approchant ne suffit pas', () async {
      // « BCM » n'est pas « BMC ». Deviner ici serait de la correction
      // orthographique, et elle se verrait sur 4 500 mouvements.
      await creerFiche('BMC', TypeTiers.client);

      await _service(db).importWorkbook(livreAvec('SOCACIM', 'BCM'));

      expect((await db.query('stock_outputs')).single['tiers_id'], isNull);
      expect((await db.query('stock_outputs')).single['destination'], 'BCM');
    });
  });


  group('les prix', () {
    Excel catalogueAvecPrix(List<List<CellValue>> lignes) => _workbook({
          'Produits': [
            [_t('RÉFÉRENCE'), _t('DÉSIGNATION'), _t('MAGASIN'),
              _t('STOCK INITIAL'), _t('PRIX DE VENTE'), _t("PRIX D'ACHAT")],
            ...lignes,
          ],
        });

    test('sont repris du classeur à la création', () async {
      await _service(db).importWorkbook(catalogueAvecPrix([
        [_t('ART-9'), _t('RIZ 25KG'), _t('Magasin Central'), _n(10),
          _n(18500), _n(15000)],
      ]));

      final article = (await db.query('products',
              where: 'reference = ?', whereArgs: ['ART-9']))
          .single;
      expect(article['prix_vente'], 18500);
      expect(article['prix_achat'], 15000);
    });

    test("remplissent un article qui n'en avait pas", () async {
      // Le catalogue réel arrive sans aucun prix : sans cette reprise,
      // il faudrait en saisir 723 à la main.
      await _service(db).importWorkbook(_workbook({'Produits': _catalogue}));
      expect(
        (await db.query('products', where: 'reference = ?', whereArgs: ['ART-1']))
            .single['prix_vente'],
        isNull,
      );

      final report = await _service(db).importWorkbook(catalogueAvecPrix([
        [_t('ART-1'), _t('Article Un'), _t('Magasin Central'), _n(0),
          _n(2500), _n(2000)],
      ]));

      expect(
        (await db.query('products', where: 'reference = ?', whereArgs: ['ART-1']))
            .single['prix_vente'],
        2500,
      );
      expect(report.prixRemplis, 1);
    });

    test("n'écrasent jamais un prix déjà en place", () async {
      // Un prix déjà posé est une décision de quelqu'un — corrigée dans
      // l'application, peut-être — et un classeur plus ancien ne doit
      // pas la défaire en silence.
      await _service(db).importWorkbook(catalogueAvecPrix([
        [_t('ART-1'), _t('Article Un'), _t('Magasin Central'), _n(0),
          _n(2500), _n(2000)],
      ]));

      final report = await _service(db).importWorkbook(catalogueAvecPrix([
        [_t('ART-1'), _t('Article Un'), _t('Magasin Central'), _n(0),
          _n(999), _n(111)],
      ]));

      final article = (await db.query('products',
              where: 'reference = ?', whereArgs: ['ART-1']))
          .single;
      expect(article['prix_vente'], 2500);
      expect(article['prix_achat'], 2000);
      expect(report.prixConserves, 1,
          reason: 'conservé, et compté — pour pouvoir y revenir sciemment');
      expect(report.prixRemplis, 0);
    });

    test('un prix négatif est ignoré plutôt que repris', () async {
      // Dans un classeur il ne signifie rien, et le laisser passer
      // contaminerait chaque total qui le rencontrerait.
      await _service(db).importWorkbook(catalogueAvecPrix([
        [_t('ART-9'), _t('RIZ'), _t('Magasin Central'), _n(0), _n(-500), _n(0)],
      ]));

      expect(
        (await db.query('products', where: 'reference = ?', whereArgs: ['ART-9']))
            .single['prix_vente'],
        isNull,
      );
    });

    test('une feuille de prix seule ne touche pas au stock', () async {
      // Une colonne absente n'est pas un zéro. Sans cette règle, un
      // classeur de prix créait une ligne d'ouverture à zéro dans le
      // magasin par défaut pour chaque article qui n'y était pas — 41
      // sur le catalogue réel, donc 41 articles apparaissant dans un
      // magasin où ils ne sont pas, et une alerte de stock négatif.
      await _service(db).importWorkbook(_workbook({'Produits': _catalogue}));
      final avant = (await db.query('product_stocks')).length;

      final report = await _service(db).importWorkbook(_workbook({
        'Produits': [
          [_t('RÉFÉRENCE'), _t('DÉSIGNATION'), _t('PRIX DE VENTE')],
          [_t('ART-1'), _t('Article Un'), _n(2500)],
        ],
      }));

      expect((await db.query('product_stocks')), hasLength(avant));
      expect(report.stocks, 0);
      expect(report.prixRemplis, 1);
    });

    test('une colonne de prix absente ne casse rien', () async {
      // Le classeur Sage d'aujourd'hui n'en a pas : l'import doit
      // continuer de marcher exactement comme avant.
      final report =
          await _service(db).importWorkbook(_workbook({'Produits': _catalogue}));

      expect(report.products, greaterThan(0));
      expect(report.prixRemplis, 0);
      expect(report.prixConserves, 0);
    });
  });

}
