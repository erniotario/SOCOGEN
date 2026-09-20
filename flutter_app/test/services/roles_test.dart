import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:socogen/core/auth/permissions.dart';
import 'package:socogen/core/db/schema.dart';
import 'package:socogen/core/errors/messages.dart';
import 'package:socogen/modules/utilisateurs/repositories/role_repository.dart';
import 'package:socogen/modules/utilisateurs/services/utilisateurs_service.dart';

/// Les rôles, devenus des données.
///
/// La promesse faite quand le point de décision a été posé : le rendre
/// modifiable ne doit **rien changer pour personne** le jour de la mise
/// à jour. C'est ce que vérifie le premier groupe, sur une base servie
/// comme le fait l'application.
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
        for (final sql in AppSchema.rolesParDefaut) {
          await d.execute(sql);
        }
        for (final sql in AppSchema.droitsParDefaut()) {
          await d.execute(sql);
        }
      },
    ),
  );
  return db;
}

void main() {
  late Database db;
  late RoleRepository depot;
  late UtilisateursService service;

  setUp(() async {
    db = await _base();
    depot = RoleRepository(database: db);
    service = UtilisateursService(roleRepository: depot);
  });

  tearDown(() async => db.close());

  group("ce que l'installation sert", () {
    test('les deux rôles d\'origine, intégrés', () async {
      final roles = await service.listerRoles();

      expect(roles.map((r) => r.code), containsAll(['admin', 'magasinier']));
      expect(roles.every((r) => r.integre), isTrue);
    });

    test('un magasinier voit exactement ce qu\'il voyait', () async {
      // L'ancienne règle en dur : tout sauf ce qui est réservé à
      // l'administrateur. La reproduire est la promesse tenue.
      final droits = await service.droitsDe('magasinier');

      for (final p in Permissions.toutes) {
        expect(droits.autorise(p), !p.adminSeul, reason: p.code);
      }
    });

    test("l'administrateur n'a aucune ligne, et peut tout", () async {
      // Aucune donnée : c'est ce qui l'empêche de se retirer le droit de
      // gérer les droits.
      expect(await depot.droitsDe('admin'), isEmpty);

      final droits = await service.droitsDe('admin');
      for (final p in Permissions.toutes) {
        expect(droits.autorise(p), isTrue, reason: p.code);
      }
    });

    test('personne de connecté ne peut rien', () async {
      final droits = await service.droitsDe(null);

      expect(droits.estConnecte, isFalse);
      for (final p in Permissions.toutes) {
        expect(droits.autorise(p), isFalse);
      }
    });
  });

  group('modifier les droits d\'un rôle', () {
    test('remplace le bloc, sans laisser de reste', () async {
      await service.definirPermissions(
        'magasinier',
        {Permissions.consulterStock.code},
      );

      final droits = await service.droitsDe('magasinier');
      expect(droits.autorise(Permissions.consulterStock), isTrue);
      expect(droits.autorise(Permissions.saisirMouvement), isFalse,
          reason: 'un droit non renvoyé est un droit retiré');
    });

    test('accorder un droit réservé est possible', () async {
      // `adminSeul` est un défaut de service, pas un interdit : un
      // responsable de magasin qui crée les comptes de son équipe est
      // un besoin légitime.
      await service.definirPermissions(
        'magasinier',
        {Permissions.gererUtilisateurs.code},
      );

      expect(
        (await service.droitsDe('magasinier'))
            .autorise(Permissions.gererUtilisateurs),
        isTrue,
      );
    });

    test("ceux de l'administrateur sont refusés", () async {
      await expectLater(
        service.definirPermissions('admin', const {}),
        throwsA(isA<ErreurUtilisateur>()),
      );
    });
  });

  group('créer et supprimer un rôle', () {
    test('un rôle neuf n\'a aucun droit', () async {
      // Le sens d'erreur qui se rattrape : on ouvre ensuite, on ne
      // referme pas après coup.
      await service.creerRole(code: 'caissier', libelle: 'Caissier');

      final droits = await service.droitsDe('caissier');
      expect(droits.estConnecte, isTrue);
      for (final p in Permissions.toutes) {
        expect(droits.autorise(p), isFalse, reason: p.code);
      }
    });

    test('un code déjà pris est refusé', () async {
      await expectLater(
        service.creerRole(code: 'admin', libelle: 'Autre'),
        throwsA(isA<ErreurUtilisateur>()),
      );
    });

    test('un rôle intégré ne se supprime pas', () async {
      for (final code in ['admin', 'magasinier']) {
        await expectLater(
          service.supprimerRole(code),
          throwsA(isA<ErreurUtilisateur>()),
          reason: code,
        );
      }
    });

    test('un rôle encore porté par un compte ne se supprime pas', () async {
      // Sinon ces comptes se retrouveraient sans aucun droit du jour au
      // lendemain, sans que personne l'ait demandé.
      await service.creerRole(code: 'caissier', libelle: 'Caissier');
      await db.insert('users', {
        'username': 'awa',
        'password_hash': 'x',
        'password_salt': 'y',
        'role': 'caissier',
      });

      await expectLater(
        service.supprimerRole('caissier'),
        throwsA(isA<ErreurUtilisateur>()),
      );
      expect(await service.role('caissier'), isNotNull);
    });

    test('un rôle libre se supprime, avec ses droits', () async {
      await service.creerRole(code: 'caissier', libelle: 'Caissier');
      await service.definirPermissions(
        'caissier',
        {Permissions.consulterStock.code},
      );

      await service.supprimerRole('caissier');

      expect(await service.role('caissier'), isNull);
      expect(await depot.droitsDe('caissier'), isEmpty,
          reason: 'les droits partent avec le rôle');
    });
  });
}
