import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:socogen/modules/parametres/models/company_settings.dart';
import 'package:socogen/modules/parametres/repositories/settings_repository.dart';

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
}
