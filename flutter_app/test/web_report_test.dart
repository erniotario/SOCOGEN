import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:erp/core/db/database_service.dart';
import 'package:erp/core/sync/sync_server.dart';
import 'package:erp/shared/ui/theme/app_branding.dart';

import 'repositories/test_database.dart';

/// Exercises the read-only pages the admin shares over the local
/// network. They are served by the same server as `POST /sync`, so this
/// also guards against a routing change breaking sync.
Future<({int status, String body})> _get(String path) async {
  final client = HttpClient();
  try {
    final request =
        await client.getUrl(Uri.parse('http://127.0.0.1:$syncPort$path'));
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    return (status: response.statusCode, body: body);
  } finally {
    client.close(force: true);
  }
}

void main() {
  late Database db;
  late SyncServer server;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openTestDatabase();
    DatabaseService.instance.databaseForTesting = db;
    server = SyncServer(db);
    await server.start();
  });

  tearDown(() async {
    await server.stop();
    DatabaseService.instance.databaseForTesting = null;
    await db.close();
  });

  test('the stock page renders the catalogue with live figures', () async {
    final response = await _get('/');

    expect(response.status, 200);
    expect(response.body, contains('<!doctype html>'));
    // The report is per product x store, so REF1 appears once per
    // store with that store's own current stock (StoreA=18, StoreB=10)
    // rather than the 28 aggregate shown on the dashboard.
    expect(response.body, contains('REF1'));
    expect(response.body, contains('Produit Un'));
    expect(response.body, contains('StoreA'));
    expect(response.body, contains('StoreB'));
    expect(response.body, contains('>18<'));
    expect(response.body, contains('>10<'));
    expect(response.body, contains('badge'));
    // Read-only: nothing on the page can post back.
    expect(response.body.contains('<form'), isFalse);
  });

  test('the movements page lists entries and outputs', () async {
    final response = await _get('/mouvements');

    expect(response.status, 200);
    expect(response.body, contains('Fournisseur A'));
    expect(response.body, contains('Entrée'));
    expect(response.body, contains('Sortie'));
  });

  test('free text from the database is HTML-escaped', () async {
    await db.insert('products', {
      'id': 99,
      'reference': 'X&Y',
      'designation': '<script>alert(1)</script>',
      'unit': 'u',
    });
    await db.insert('product_stocks', {
      'id': 99,
      'product_id': 99,
      'store_id': 1,
      'initial_stock': 1,
    });

    final response = await _get('/');
    expect(response.body, contains('X&amp;Y'));
    expect(response.body, contains('&lt;script&gt;'));
    expect(response.body.contains('<script>alert(1)</script>'), isFalse);
  });

  test('an unknown path returns 404 rather than the report', () async {
    expect((await _get('/nope')).status, 404);
  });

  group("l'en-tête de la page servie", () {
    test("porte le nom de l'entreprise", () async {
      // Ces pages se consultent depuis un téléphone sur le réseau du
      // magasin : la première chose à y lire est de quelle maison on
      // regarde le stock.
      await db.insert('company_settings', {'id': 1, 'name': 'Maison Kamdem'});

      final body = (await _get('/')).body;
      expect(body, contains('<h1>Maison Kamdem</h1>'));
      expect(body, contains('<title>Maison Kamdem — Stock</title>'));
      expect(body, contains('<div class="mark">M</div>'),
          reason: "l'initiale suit le nom, elle n'est pas gravée");
    });

    test("retombe sur le nom du produit tant qu'il est inconnu", () async {
      // Une base neuve n'a pas encore dit qui elle est. Un en-tête vide
      // ne dirait à personne quel stock il consulte.
      final body = (await _get('/')).body;
      expect(body, contains('<h1>${AppBranding.productName}</h1>'));
      expect(body, isNot(contains('<h1></h1>')));
    });
  });
}
