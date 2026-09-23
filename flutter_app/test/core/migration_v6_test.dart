import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:erp/core/db/schema.dart';

/// Le seuil de stock devient une propriété de l'article.
///
/// Il valait dix en dur pour tout le catalogue. Ce que cette migration
/// doit garantir tient en une phrase : **une base migrée se comporte
/// exactement comme avant**. Aucun article n'hérite d'un seuil qu'il n'a
/// pas choisi, et le repli vaut toujours dix.
Future<Database> _baseV5() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(version: 5, singleInstance: false),
  );
  await db.execute(
    'CREATE TABLE products (id INTEGER PRIMARY KEY AUTOINCREMENT, '
    'reference TEXT NOT NULL UNIQUE, designation TEXT NOT NULL, '
    'prix_vente INTEGER, actif INTEGER NOT NULL DEFAULT 1)',
  );
  await db.execute(
    "CREATE TABLE company_settings (id INTEGER PRIMARY KEY, name TEXT, "
    "devise TEXT NOT NULL DEFAULT 'XAF')",
  );
  await db.insert('products', {
    'reference': 'RIZ25',
    'designation': 'RIZ PERLE 25KG',
    'prix_vente': 18500,
  });
  await db.insert('products',
      {'reference': 'ALLUM', 'designation': 'ALLUMETTE MYMY CT DE 10'});
  await db.insert('company_settings',
      {'id': 1, 'name': 'SOCOGEN Sarl', 'devise': 'XAF'});
  return db;
}

Future<void> _migrer(Database db) async {
  for (final sql in AppSchema.migrationV5ToV6) {
    await db.execute(sql);
  }
}

void main() {
  late Database db;

  setUp(() async => db = await _baseV5());
  tearDown(() async => db.close());

  test('rien ne se perd', () async {
    await _migrer(db);

    final articles = await db.query('products', orderBy: 'reference');
    expect(articles, hasLength(2));
    expect(articles.first['designation'], 'ALLUMETTE MYMY CT DE 10');
    expect(articles.last['prix_vente'], 18500);
    expect((await db.query('company_settings')).single['name'], 'SOCOGEN Sarl');
  });

  test("aucun article n'hérite d'un seuil qu'il n'a pas choisi", () async {
    // Inscrire dix partout aurait été le geste naturel et le mauvais :
    // on ne saurait plus distinguer un article réglé à dix d'un article
    // jamais réglé, et changer le défaut n'aurait plus d'effet.
    await _migrer(db);

    for (final article in await db.query('products')) {
      expect(article['stock_min'], isNull, reason: '${article['reference']}');
    }
  });

  test("l'entreprise reprend la valeur qui était en dur", () async {
    await _migrer(db);

    expect(
      (await db.query('company_settings')).single['stock_min_defaut'],
      10,
    );
  });

  test('la devise traverse intacte', () async {
    // Le même enregistrement porte les deux : une migration qui
    // recréerait la ligne au lieu de l'altérer la ramènerait à XAF pour
    // une entreprise qui compte en euros.
    await db.update('company_settings', {'devise': 'EUR'});

    await _migrer(db);

    expect((await db.query('company_settings')).single['devise'], 'EUR');
  });
}
