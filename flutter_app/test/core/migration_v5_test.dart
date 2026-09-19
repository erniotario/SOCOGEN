import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:socogen/core/db/schema.dart';

/// La reprise des partenaires commerciaux saisis en texte libre.
///
/// Chez le premier client, cette migration touche 4 570 sorties et 631
/// entrées d'un coup. Ce qu'elle doit faire est simple à dire et facile
/// à rater : créer une fiche par valeur distincte, rattacher par égalité
/// exacte, et ne rien deviner au-delà.
///
/// Le jeu d'essai reprend les cas réels qui ont motivé la conception :
/// « BMC » et « BCM » (deux lettres interverties), « DADA » et « DADA
/// EKOUNOU » (un préfixe), et un partenaire présent des deux côtés.
Future<Database> _baseV4AvecTexteLibre() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(version: 4, singleInstance: false),
  );
  // La v4 telle qu'elle existe avant cette migration : les mouvements
  // n'ont pas de tiers_id et le partenaire n'est qu'une chaîne.
  await db.execute('''
    CREATE TABLE stores (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)
  ''');
  await db.execute('''
    CREATE TABLE stock_entries (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT NOT NULL, supplier TEXT DEFAULT '',
      reference TEXT NOT NULL, designation TEXT NOT NULL,
      store_id INTEGER NOT NULL, quantity INTEGER NOT NULL,
      sync_id TEXT, updated_at TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE stock_outputs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT NOT NULL, reference TEXT NOT NULL,
      designation TEXT NOT NULL, invoice_number TEXT DEFAULT '',
      store_id INTEGER NOT NULL, destination TEXT DEFAULT '',
      quantity INTEGER NOT NULL, sync_id TEXT, updated_at TEXT
    )
  ''');
  await db.insert('stores', {'id': 1, 'name': 'Hysacam'});

  Future<void> entree(String fournisseur) => db.insert('stock_entries', {
        'date': '2026-01-05',
        'supplier': fournisseur,
        'reference': 'RIZ25',
        'designation': 'RIZ',
        'store_id': 1,
        'quantity': 10,
      });
  Future<void> sortie(String client) => db.insert('stock_outputs', {
        'date': '2026-02-05',
        'reference': 'RIZ25',
        'designation': 'RIZ',
        'store_id': 1,
        'destination': client,
        'quantity': 5,
      });

  await entree('DADA');
  await entree('DADA EKOUNOU');
  await entree('DADA EKOUNOU');
  await entree('SONECOMX');
  await entree('  SONECOMX  '); // espaces parasites : même fournisseur
  await entree(''); // pas de fournisseur saisi
  await entree('C0001'); // un nom qui ressemble à un code
  await sortie('BMC');
  await sortie('BMC');
  await sortie('BCM');
  await sortie('SONECOMX'); // vend aussi à un de ses fournisseurs
  return db;
}

Future<void> _migrer(Database db) async {
  for (final sql in AppSchema.migrationV4ToV5) {
    await db.execute(sql);
  }
  for (final sql in AppSchema.reprisesTiersDepuisTexte) {
    await db.execute(sql);
  }
}

void main() {
  late Database db;

  setUp(() async => db = await _baseV4AvecTexteLibre());
  tearDown(() async => db.close());

  group('les fiches créées', () {
    test('une par valeur distincte, espaces parasites mis à part', () async {
      await _migrer(db);

      final noms = (await db.query('tiers', orderBy: 'nom'))
          .map((t) => t['nom'] as String)
          .toList();
      expect(noms,
          ['BCM', 'BMC', 'C0001', 'DADA', 'DADA EKOUNOU', 'SONECOMX']);
    });

    test('un texte vide ne crée pas de fiche fantôme', () async {
      await _migrer(db);

      expect(
        (await db.query('tiers', where: "nom = '' OR nom IS NULL")),
        isEmpty,
      );
    });

    test('le rôle vient du côté où le nom apparaît', () async {
      await _migrer(db);

      Future<String> type(String nom) async =>
          (await db.query('tiers', where: 'nom = ?', whereArgs: [nom]))
              .single['type'] as String;

      expect(await type('DADA'), 'fournisseur');
      expect(await type('BMC'), 'client');
      // Présent des deux côtés : c'est réellement les deux.
      expect(await type('SONECOMX'), 'les_deux');
    });

    test('le code se lit : C pour un client, F sinon', () async {
      await _migrer(db);

      for (final ligne in await db.query('tiers')) {
        final code = ligne['code'] as String;
        final attendu = ligne['type'] == 'client' ? 'C' : 'F';
        expect(code, startsWith(attendu), reason: '${ligne['nom']}');
        expect(code, hasLength(5), reason: code);
      }
    });
  });

  group('ce que la reprise refuse de deviner', () {
    test('BMC et BCM restent deux fiches', () async {
      // Deux lettres interverties. Les confondre serait une correction
      // orthographique déguisée en migration ; les laisser séparées les
      // rend visibles, et la fusion est une décision humaine.
      await _migrer(db);

      final noms = (await db.query('tiers')).map((t) => t['nom']).toList();
      expect(noms, containsAll(['BMC', 'BCM']));
    });

    test('un nom qui ressemble à un code obtient quand même sa fiche',
        () async {
      // Le code provisoire est marqué d'un tilde pour cette raison : si
      // la reprise posait le nom brut comme code, « C0001 » entrerait en
      // collision avec le code attribué à un autre tiers, et ce
      // fournisseur repartirait sans fiche — ses mouvements non
      // rattachés, en silence.
      await _migrer(db);

      final fiche = (await db.query('tiers', where: "nom = 'C0001'")).single;
      expect(fiche['code'], isNot('C0001'));
      expect(
        (await db.query('stock_entries', where: "supplier = 'C0001'"))
            .single['tiers_id'],
        fiche['id'],
      );
    });

    test('DADA et DADA EKOUNOU restent deux fiches', () async {
      await _migrer(db);

      expect(
        (await db.query('tiers', where: "nom LIKE 'DADA%'")),
        hasLength(2),
      );
    });
  });

  group('le rattachement', () {
    test('chaque mouvement nommé trouve sa fiche', () async {
      await _migrer(db);

      final entreesLiees = await db.query('stock_entries',
          where: 'tiers_id IS NOT NULL');
      final sortiesLiees = await db.query('stock_outputs',
          where: 'tiers_id IS NOT NULL');

      expect(entreesLiees, hasLength(6)); // celle sans nom reste à part
      expect(sortiesLiees, hasLength(4));
    });

    test('un mouvement sans nom reste sans fiche plutôt que rangé ailleurs',
        () async {
      await _migrer(db);

      final orpheline = (await db.query('stock_entries',
              where: "TRIM(COALESCE(supplier,'')) = ''"))
          .single;
      expect(orpheline['tiers_id'], isNull);
    });

    test('le texte saisi reste sur le mouvement', () async {
      // Une ligne passée doit continuer de dire ce qui a été tapé ce
      // jour-là, même si la fiche est renommée ou fusionnée ensuite.
      await _migrer(db);

      final ligne = (await db.query('stock_outputs',
              where: 'destination = ?', whereArgs: ['BCM']))
          .single;
      expect(ligne['destination'], 'BCM');
      expect(ligne['tiers_id'], isNotNull);
    });

    test('les deux écritures de SONECOMX pointent la même fiche', () async {
      await _migrer(db);

      final ids = (await db.query('stock_entries',
              where: "TRIM(supplier) = 'SONECOMX'"))
          .map((e) => e['tiers_id'])
          .toSet();
      expect(ids, hasLength(1), reason: 'les espaces parasites ne doivent '
          'pas fabriquer un second fournisseur');
    });
  });

  group('rejouabilité', () {
    test('repasser la reprise ne duplique rien', () async {
      // Pas pour cause de migration interrompue : sqflite monte la base
      // dans une transaction exclusive et n'inscrit la nouvelle version
      // qu'à l'intérieur, donc une montée échouée ne laisse rien
      // derrière elle. C'est pour la suite que ça compte — rattacher
      // les mouvements restés sans fiche est une opération d'entretien
      // qu'on voudra relancer, et elle doit pouvoir l'être sans rien
      // dupliquer.
      await _migrer(db);
      final avant = (await db.query('tiers')).length;

      for (final sql in AppSchema.reprisesTiersDepuisTexte) {
        await db.execute(sql);
      }

      expect((await db.query('tiers')), hasLength(avant));
      expect(
        (await db.query('stock_outputs', where: 'tiers_id IS NOT NULL')),
        hasLength(4),
      );
      expect(
        (await db.query('stock_entries', where: 'tiers_id IS NOT NULL')),
        hasLength(6),
      );
    });
  });
}
