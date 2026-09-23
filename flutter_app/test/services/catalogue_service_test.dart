import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:erp/core/db/schema.dart';
import 'package:erp/core/errors/messages.dart';
import 'package:erp/core/money/montant.dart';
import 'package:erp/modules/catalogue/repositories/famille_repository.dart';
import 'package:erp/modules/catalogue/repositories/product_repository.dart';
import 'package:erp/modules/catalogue/services/catalogue_service.dart';
import 'package:erp/modules/parametres/repositories/settings_repository.dart';
import 'package:erp/modules/parametres/repositories/tva_repository.dart';
import 'package:erp/modules/parametres/services/parametres_service.dart';

/// Le service du catalogue, et surtout ce qu'il fait des prix.
///
/// C'est ici que des entiers rangés en base redeviennent des montants
/// dans une devise, et que la TVA d'un article s'applique. Les erreurs à
/// cet endroit ne se voient pas à l'écran : elles se voient sur un
/// ticket, un mois plus tard.
Future<Database> _base() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: AppSchema.version,
      singleInstance: false,
      onConfigure: (d) async => d.execute('PRAGMA foreign_keys = ON'),
      onCreate: (d, _) async {
        for (final sql in AppSchema.createStatements) {
          await d.execute(sql);
        }
        for (final sql in AppSchema.tauxTvaParDefaut) {
          await d.execute(sql);
        }
      },
    ),
  );
  await db.insert('company_settings', {'id': 1, 'name': 'Test', 'devise': 'XAF'});
  return db;
}

void main() {
  late Database db;
  late CatalogueService catalogue;
  late ProductRepository produits;

  setUp(() async {
    db = await _base();
    produits = ProductRepository(database: db);
    catalogue = CatalogueService(
      productRepository: produits,
      familleRepository: FamilleRepository(database: db),
      parametresService: ParametresService(
        settingsRepository: SettingsRepository(database: db),
        tvaRepository: TvaRepository(database: db),
      ),
    );
  });

  tearDown(() async => db.close());

  Future<int> tvaNormale() async {
    final rows =
        await db.query('taux_tva', where: 'code = ?', whereArgs: ['NORMAL']);
    return rows.first['id'] as int;
  }

  group('un prix absent reste absent', () {
    test('un article sans prix ne vaut pas zéro', () async {
      final id = await catalogue.creerArticle(
        reference: 'RIZ25',
        designation: 'RIZ 25KG',
      );
      final article = (await produits.getByReference('RIZ25'))!;

      expect(id, greaterThan(0));
      expect(await catalogue.prixDeVente(article), isNull);
      expect(await catalogue.prixDeVenteTtc(article), isNull);
      expect(article.estTarife, isFalse);
    });

    test('un article à zéro est tarifé, lui', () async {
      await catalogue.creerArticle(
        reference: 'ECH',
        designation: 'Échantillon',
        prixVenteUnites: 0,
      );
      final article = (await produits.getByReference('ECH'))!;

      expect(article.estTarife, isTrue);
      expect(await catalogue.prixDeVente(article), Montant.zero);
    });
  });

  group('les prix reviennent dans la devise de la société', () {
    test('un prix se relit en francs CFA', () async {
      await catalogue.creerArticle(
        reference: 'RIZ25',
        designation: 'RIZ 25KG',
        prixVenteUnites: 15000,
      );
      final article = (await produits.getByReference('RIZ25'))!;

      final prix = await catalogue.prixDeVente(article);
      expect(prix, const Montant(15000, devise: Devise.xaf));
      expect(prix!.formate().replaceAll(' ', ' '), '15 000 FCFA');
    });

    test('le TTC ajoute la TVA de l\'article', () async {
      await catalogue.creerArticle(
        reference: 'RIZ25',
        designation: 'RIZ 25KG',
        prixVenteUnites: 15000,
        tvaId: await tvaNormale(),
      );
      final article = (await produits.getByReference('RIZ25'))!;

      // 15 000 × 19,25 % = 2 887,5 → 2 888
      expect(await catalogue.prixDeVenteTtc(article), const Montant(17888));
    });

    test('un article sans TVA est servi tel quel, pas refusé', () async {
      // Les 723 articles hérités de Sage n'ont pas de taux. Bloquer leur
      // affichage rendrait le catalogue inutilisable en attendant qu'on
      // les ait tous repris un par un.
      await catalogue.creerArticle(
        reference: 'ANCIEN',
        designation: 'Article hérité',
        prixVenteUnites: 15000,
      );
      final article = (await produits.getByReference('ANCIEN'))!;

      expect(await catalogue.prixDeVenteTtc(article), const Montant(15000));
    });
  });

  group('écriture d\'un prix', () {
    test('un prix négatif est refusé avec une phrase lisible', () async {
      await catalogue.creerArticle(reference: 'RIZ25', designation: 'RIZ');
      final article = (await produits.getByReference('RIZ25'))!;

      await expectLater(
        catalogue.definirPrixDeVente(article, const Montant(-100)),
        throwsA(isA<ErreurUtilisateur>()),
      );
      expect(
        messagePour(const ErreurUtilisateur('Un prix de vente ne peut pas '
            'être négatif.')),
        contains('négatif'),
      );
    });

    test('retirer le prix le remet à inconnu, pas à zéro', () async {
      await catalogue.creerArticle(
        reference: 'RIZ25',
        designation: 'RIZ',
        prixVenteUnites: 15000,
      );
      var article = (await produits.getByReference('RIZ25'))!;

      await catalogue.definirPrixDeVente(article, null);
      article = (await produits.getByReference('RIZ25'))!;

      expect(article.prixVenteUnites, isNull);
      expect(article.estTarife, isFalse);
    });
  });

  group('recherche', () {
    test('le code-barres retrouve un article, comme le fera la douchette',
        () async {
      await catalogue.creerArticle(
        reference: 'RIZ25',
        designation: 'RIZ 25KG',
        codeBarre: '6161100000123',
      );

      final trouve = await catalogue.chercherParCodeBarre('6161100000123');
      expect(trouve?.reference, 'RIZ25');
      expect(await catalogue.chercherParCodeBarre('0000000000000'), isNull);
    });

    test('une référence déjà prise est signalée avant la tentative', () async {
      await catalogue.creerArticle(reference: 'RIZ25', designation: 'RIZ');

      expect(await catalogue.referenceExiste('RIZ25'), isTrue);
      expect(await catalogue.referenceExiste('AUTRE'), isFalse);
    });
  });

  group('familles', () {
    test('le chemin se lit de la racine à la feuille', () async {
      final familles = FamilleRepository(database: db);
      final racine = await familles.create(code: 'ALIM', nom: 'Alimentaire');
      final niveau2 =
          await familles.create(code: 'BOIS', nom: 'Boissons', parentId: racine);
      final niveau3 =
          await familles.create(code: 'SODA', nom: 'Sodas', parentId: niveau2);

      expect(
        await catalogue.cheminFamille(niveau3),
        'Alimentaire › Boissons › Sodas',
      );
    });

    test('un quatrième niveau est refusé', () async {
      final familles = FamilleRepository(database: db);
      var parent = await familles.create(code: 'N1', nom: 'Un');
      parent = await familles.create(code: 'N2', nom: 'Deux', parentId: parent);
      parent = await familles.create(code: 'N3', nom: 'Trois', parentId: parent);

      await expectLater(
        familles.create(code: 'N4', nom: 'Quatre', parentId: parent),
        throwsA(isA<ErreurUtilisateur>()),
      );
    });
  });
}
