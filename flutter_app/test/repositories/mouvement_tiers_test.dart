import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:erp/modules/stock/models/stock_entry.dart';
import 'package:erp/modules/stock/models/stock_output.dart';
import 'package:erp/modules/stock/repositories/stock_entry_repository.dart';
import 'package:erp/modules/stock/repositories/stock_output_repository.dart';
import 'package:erp/modules/tiers/repositories/tiers_repository.dart';
import 'package:erp/shared/models/tiers.dart';

import 'test_database.dart';

/// Le lien entre un mouvement et la fiche de son partenaire.
///
/// Deux choses doivent tenir ensemble et sont faciles à casser
/// séparément : le mouvement porte un `tiers_id`, **et** il garde le nom
/// tapé ce jour-là. Perdre le premier laisse un mouvement orphelin ;
/// perdre le second réécrit l'historique.
void main() {
  late Database db;
  late StockEntryRepository entrees;
  late StockOutputRepository sorties;
  late TiersRepository tiers;

  setUp(() async {
    db = await openTestDatabase();
    entrees = StockEntryRepository(database: db);
    sorties = StockOutputRepository(database: db);
    tiers = TiersRepository(database: db);
  });

  tearDown(() async => db.close());

  Future<Tiers> fiche(String nom, TypeTiers type) async {
    final id = await tiers.create(Tiers(
      id: 0,
      code: await tiers.prochainCode(type),
      nom: nom,
      type: type,
    ));
    return (await tiers.getById(id))!;
  }

  group('une entrée', () {
    test('conserve la fiche choisie', () async {
      final f = await fiche('SONECOMX', TypeTiers.fournisseur);

      final id = await entrees.create(StockEntry(
        id: 0,
        date: '2026-03-01',
        supplier: f.nom,
        reference: 'REF1',
        designation: 'Produit Un',
        storeId: 1,
        quantity: 4,
        tiersId: f.id,
      ));

      final relu = (await entrees.getAll())
          .firstWhere((r) => r.entry.id == id)
          .entry;
      expect(relu.tiersId, f.id);
      expect(relu.supplier, 'SONECOMX');
    });

    test('peut être enregistrée sans fiche', () async {
      // Un magasinier qui reçoit d'un inconnu un samedi doit pouvoir
      // enregistrer l'entrée. Le mouvement part sans lien, et le nom
      // reste la seule trace — c'est un manque assumé, rattrapable
      // ensuite par la reprise.
      final id = await entrees.create(const StockEntry(
        id: 0,
        date: '2026-03-02',
        supplier: 'NOUVEAU FOURNISSEUR',
        reference: 'REF1',
        designation: 'Produit Un',
        storeId: 1,
        quantity: 2,
      ));

      final relu = (await entrees.getAll())
          .firstWhere((r) => r.entry.id == id)
          .entry;
      expect(relu.tiersId, isNull);
      expect(relu.supplier, 'NOUVEAU FOURNISSEUR');
    });

    test('garde son nom quand la fiche est renommée', () async {
      // La ligne passée doit continuer de dire ce qui a été saisi ce
      // jour-là : c'est ce qui rend l'historique relisible.
      final f = await fiche('DADA', TypeTiers.fournisseur);
      final id = await entrees.create(StockEntry(
        id: 0,
        date: '2026-03-03',
        supplier: f.nom,
        reference: 'REF1',
        designation: 'Produit Un',
        storeId: 1,
        quantity: 1,
        tiersId: f.id,
      ));

      await tiers.update(f.copyWith(nom: 'DADA EKOUNOU'));

      final relu = (await entrees.getAll())
          .firstWhere((r) => r.entry.id == id)
          .entry;
      expect(relu.supplier, 'DADA');
      expect(relu.tiersId, f.id);
    });
  });

  group('une sortie', () {
    test('conserve la fiche choisie', () async {
      final f = await fiche('BMC', TypeTiers.client);

      final id = await sorties.create(StockOutput(
        id: 0,
        date: '2026-03-01',
        reference: 'REF1',
        designation: 'Produit Un',
        invoiceNumber: 'FAC1',
        storeId: 1,
        destination: f.nom,
        quantity: 3,
        tiersId: f.id,
      ));

      final relu = (await sorties.getAll())
          .firstWhere((r) => r.output.id == id)
          .output;
      expect(relu.tiersId, f.id);
      expect(relu.destination, 'BMC');
    });

    test('suit la fiche à travers une fusion, sans changer de texte',
        () async {
      // Le cas réel : BMC et BCM. Après fusion, le mouvement compte pour
      // BMC, mais il affiche toujours BCM.
      final bmc = await fiche('BMC', TypeTiers.client);
      final bcm = await fiche('BCM', TypeTiers.client);
      final id = await sorties.create(StockOutput(
        id: 0,
        date: '2026-03-04',
        reference: 'REF1',
        designation: 'Produit Un',
        invoiceNumber: 'FAC2',
        storeId: 1,
        destination: bcm.nom,
        quantity: 5,
        tiersId: bcm.id,
      ));

      await tiers.fusionner(sourceId: bcm.id, cibleId: bmc.id);

      final relu = (await sorties.getAll())
          .firstWhere((r) => r.output.id == id)
          .output;
      expect(relu.tiersId, bmc.id);
      expect(relu.destination, 'BCM');
    });
  });

  group('le compte de mouvements', () {
    test('additionne les deux sens', () async {
      // Une fiche peut être des deux côtés : ce compte est ce qui dit
      // si elle peut être fusionnée sans y regarder à deux fois.
      final f = await fiche('DOUBLE', TypeTiers.lesDeux);
      await entrees.create(StockEntry(
        id: 0,
        date: '2026-03-05',
        supplier: f.nom,
        reference: 'REF1',
        designation: 'Produit Un',
        storeId: 1,
        quantity: 1,
        tiersId: f.id,
      ));
      await sorties.create(StockOutput(
        id: 0,
        date: '2026-03-06',
        reference: 'REF1',
        designation: 'Produit Un',
        invoiceNumber: '',
        storeId: 1,
        destination: f.nom,
        quantity: 1,
        tiersId: f.id,
      ));

      expect(await tiers.compterMouvements(f.id), 2);
    });
  });
}
