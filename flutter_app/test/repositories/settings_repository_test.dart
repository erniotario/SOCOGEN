import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:erp/shared/models/company_settings.dart';
import 'package:erp/modules/parametres/repositories/settings_repository.dart';

import 'test_database.dart';

void main() {
  late Database db;
  late SettingsRepository repo;

  setUp(() async {
    db = await openTestDatabase();
    repo = SettingsRepository(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  test('getSettings invents no company when no row exists', () async {
    final settings = await repo.getSettings();
    expect(settings.id, 1);
    expect(
      settings.name,
      '',
      reason: 'an unnamed installation is unnamed -- it used to fall back '
          'to the first customer, which put their name on the next '
          "customer's reports",
    );
  });

  test('saveSettings inserts then updates the singleton row', () async {
    await repo.saveSettings(const CompanySettings(
      name: 'SHEMAB',
      address: '123 Rue Exemple',
      city: 'Yaoundé, Cameroun',
      phone: '+237600000000',
    ));

    var settings = await repo.getSettings();
    expect(settings.name, 'SHEMAB');
    expect(settings.city, 'Yaoundé, Cameroun');

    await repo.saveSettings(settings.copyWith(phone: '+237611111111'));
    settings = await repo.getSettings();
    expect(settings.id, 1);
    expect(settings.name, 'SHEMAB');
    expect(settings.phone, '+237611111111');
  });

  group('ce que la fiche société garde', () {
    test("copyWith ne touche pas à ce qu'on ne lui donne pas", () async {
      // L'écran Paramètres ne règle qu'une partie de la fiche. Il
      // reconstruisait un enregistrement complet à l'enregistrement, si
      // bien que saisir un téléphone remettait la devise à XAF pour une
      // entreprise qui comptait en euros — une perte silencieuse, sur
      // l'écran fait pour régler ces choses.
      const depart = CompanySettings(
        name: 'Maison Test',
        devise: 'EUR',
        seuilStockParDefaut: 4,
      );

      final modifie = depart.copyWith(phone: '+237699000000');

      expect(modifie.devise, 'EUR');
      expect(modifie.seuilStockParDefaut, 4);
      expect(modifie.phone, '+237699000000');
    });

    test('la devise et le seuil traversent un aller-retour en base',
        () async {
      await repo.saveSettings(const CompanySettings(
        name: 'Maison Test',
        devise: 'EUR',
        seuilStockParDefaut: 25,
      ));

      final relu = await repo.getSettings();
      expect(relu.devise, 'EUR');
      expect(relu.seuilStockParDefaut, 25);
    });

    test('un seuil absent vaut dix, ce qui était en dur', () async {
      await repo.saveSettings(const CompanySettings(name: 'Maison Test'));

      expect((await repo.getSettings()).seuilStockParDefaut, 10);
    });
  });
}
