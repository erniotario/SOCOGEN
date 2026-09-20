import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:socogen/core/db/schema.dart';
import 'package:socogen/core/errors/messages.dart';
import 'package:socogen/core/money/montant.dart';
import 'package:socogen/modules/parametres/repositories/settings_repository.dart';
import 'package:socogen/modules/parametres/repositories/tva_repository.dart';
import 'package:socogen/modules/parametres/services/parametres_service.dart';
import 'package:socogen/shared/models/tiers.dart';
import 'package:socogen/modules/tiers/repositories/tiers_repository.dart';
import 'package:socogen/modules/tiers/services/tiers_service.dart';

/// Les fiches clients et fournisseurs, et la reprise du texte libre.
///
/// Ce qui se joue ici vient d'un constat sur les données réelles : 129
/// fournisseurs tapés à la main, et « BMC » à côté de « BCM » — deux
/// lettres interverties sur cinq mouvements. La reprise ne doit ni les
/// confondre ni les perdre.
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
      },
    ),
  );
  await db.insert('company_settings', {'id': 1, 'name': 'Test', 'devise': 'XAF'});
  await db.insert('stores', {'id': 1, 'name': 'Hysacam'});
  return db;
}

void main() {
  late Database db;
  late TiersService service;
  late TiersRepository depot;

  setUp(() async {
    db = await _base();
    depot = TiersRepository(database: db);
    service = TiersService(
      tiersRepository: depot,
      parametresService: ParametresService(
        settingsRepository: SettingsRepository(database: db),
        tvaRepository: TvaRepository(database: db),
      ),
    );
  });

  tearDown(() async => db.close());

  group('création', () {
    test('le code est attribué selon le rôle', () async {
      await service.creer(nom: 'BMC', type: TypeTiers.client);
      await service.creer(nom: 'SONECOMX', type: TypeTiers.fournisseur);

      expect((await service.parNom('BMC'))!.code, 'C0001');
      expect((await service.parNom('SONECOMX'))!.code, 'F0001');
    });

    test('les codes se suivent sans se marcher dessus', () async {
      for (final nom in ['A', 'B', 'C']) {
        await service.creer(nom: nom, type: TypeTiers.fournisseur);
      }

      final codes =
          (await service.listerFournisseurs()).map((t) => t.code).toList();
      expect(codes, ['F0001', 'F0002', 'F0003']);
    });

    test('un nom déjà pris est refusé en nommant la fiche existante', () async {
      await service.creer(nom: 'BMC', type: TypeTiers.client);

      await expectLater(
        service.creer(nom: 'BMC'),
        throwsA(
          isA<ErreurUtilisateur>().having(
            (e) => e.message,
            'message',
            allOf(contains('BMC'), contains('C0001')),
          ),
        ),
      );
    });

    test('un nom vide est refusé', () async {
      await expectLater(
        service.creer(nom: '   '),
        throwsA(isA<ErreurUtilisateur>()),
      );
    });
  });

  group('rôles', () {
    test('un tiers des deux côtés apparaît dans les deux listes', () async {
      // Un grossiste achète parfois à qui il vend ; deux fiches pour une
      // seule relation seraient deux historiques à recoller.
      await service.creer(nom: 'DOUBLE', type: TypeTiers.lesDeux);
      await service.creer(nom: 'CLIENT SEUL', type: TypeTiers.client);

      expect(
        (await service.listerClients()).map((t) => t.nom),
        containsAll(['DOUBLE', 'CLIENT SEUL']),
      );
      expect(
        (await service.listerFournisseurs()).map((t) => t.nom),
        ['DOUBLE'],
      );
    });
  });

  group('plafond de crédit', () {
    test('absent veut dire « pas de plafond », pas « plafond nul »', () async {
      await service.creer(nom: 'SANS', type: TypeTiers.client);
      final t = (await service.parNom('SANS'))!;

      expect(t.aUnPlafond, isFalse);
      expect(await service.plafondCredit(t), isNull);
    });

    test('un plafond se relit dans la devise de la société', () async {
      await service.creer(
        nom: 'AVEC',
        type: TypeTiers.client,
        plafondCredit: Montant.depuisUnite(500000),
      );
      final t = (await service.parNom('AVEC'))!;

      expect(await service.plafondCredit(t), const Montant(500000));
    });

    test('un plafond négatif est refusé', () async {
      await expectLater(
        service.creer(nom: 'X', plafondCredit: const Montant(-1)),
        throwsA(isA<ErreurUtilisateur>()),
      );
    });
  });

  group('retrait', () {
    test('un tiers se désactive, il ne se supprime pas', () async {
      // Ses mouvements passés le référencent : l'effacer les laisserait
      // orphelins, et le schéma les détacherait en silence.
      await service.creer(nom: 'ANCIEN', type: TypeTiers.client);
      final t = (await service.parNom('ANCIEN'))!;

      await service.desactiver(t.id);

      expect((await service.listerClients()).map((e) => e.nom),
          isNot(contains('ANCIEN')));
      expect(await service.parId(t.id), isNotNull);
      expect((await service.parId(t.id))!.actif, isFalse);
    });
  });

  group('fusion de deux fiches', () {
    /// Le cas réel : BMC et BCM, deux lettres interverties.
    Future<(int, int)> deuxFichesAvecMouvements() async {
      await service.creer(nom: 'BMC', type: TypeTiers.client);
      await service.creer(nom: 'BCM', type: TypeTiers.client);
      final bmc = (await service.parNom('BMC'))!;
      final bcm = (await service.parNom('BCM'))!;

      for (var i = 0; i < 3; i++) {
        await db.insert('stock_outputs', {
          'date': '2026-03-0${i + 1}',
          'reference': 'RIZ25',
          'designation': 'RIZ',
          'store_id': 1,
          'destination': 'BMC',
          'quantity': 10,
          'tiers_id': bmc.id,
        });
      }
      await db.insert('stock_outputs', {
        'date': '2026-03-09',
        'reference': 'RIZ25',
        'designation': 'RIZ',
        'store_id': 1,
        'destination': 'BCM',
        'quantity': 5,
        'tiers_id': bcm.id,
      });
      return (bmc.id, bcm.id);
    }

    test('les mouvements de la source passent à la cible', () async {
      final (bmc, bcm) = await deuxFichesAvecMouvements();

      final deplaces = await service.fusionner(sourceId: bcm, cibleId: bmc);

      expect(deplaces, 1);
      expect(await service.compterMouvements(bmc), 4);
      expect(await service.compterMouvements(bcm), 0);
    });

    test('la fiche fusionnée est désactivée, pas effacée', () async {
      final (bmc, bcm) = await deuxFichesAvecMouvements();
      await service.fusionner(sourceId: bcm, cibleId: bmc);

      expect((await service.parId(bcm))!.actif, isFalse);
    });

    test('le texte d\'origine reste sur le mouvement', () async {
      // Une ligne passée doit continuer de dire ce qui a été saisi ce
      // jour-là. C'est ce qui rend la fusion relisible : on voit encore
      // que quelqu'un avait tapé BCM.
      final (bmc, bcm) = await deuxFichesAvecMouvements();
      await service.fusionner(sourceId: bcm, cibleId: bmc);

      final ligne = (await db.query('stock_outputs',
              where: 'destination = ?', whereArgs: ['BCM']))
          .single;
      expect(ligne['destination'], 'BCM');
      expect(ligne['tiers_id'], bmc);
    });

    test('fusionner une fiche avec elle-même est refusé', () async {
      final (bmc, _) = await deuxFichesAvecMouvements();

      await expectLater(
        service.fusionner(sourceId: bmc, cibleId: bmc),
        throwsA(isA<ErreurUtilisateur>()),
      );
    });
  });

  group('recherche', () {
    test('trouve par nom, code, téléphone ou numéro fiscal', () async {
      await service.creer(
        nom: 'SONECOMX',
        type: TypeTiers.fournisseur,
        telephone: '699112233',
        niu: 'M021512345678A',
      );

      for (final terme in ['SONE', 'F0001', '699', 'M0215']) {
        expect(
          (await service.rechercher(terme)).map((t) => t.nom),
          ['SONECOMX'],
          reason: 'recherche « $terme »',
        );
      }
    });

    test('un terme vide rend toute la liste', () async {
      await service.creer(nom: 'A');
      await service.creer(nom: 'B');

      expect(await service.rechercher('   '), hasLength(2));
    });
  });
}
