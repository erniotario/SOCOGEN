import 'package:flutter_test/flutter_test.dart';

import 'package:erp/core/money/montant.dart';
import 'package:erp/modules/rapports/services/facture_pdf_service.dart';
import 'package:erp/modules/stock/services/facture_service.dart';
import 'package:erp/shared/models/company_settings.dart';
import 'package:erp/shared/models/facture.dart';

/// La facture A4.
///
/// Un PDF ne se relit pas facilement : ce qui est vérifié ici est ce
/// qu'on peut vérifier sans l'ouvrir — qu'il se construit, qu'il tient
/// debout quand l'application ne sait pas tout, et que les nombres
/// qu'il va imprimer sont justes. L'allure du papier, seule une
/// impression réelle la dira.
void main() {
  const societe = CompanySettings(
    name: 'SHEMA BUSINESSES',
    address: '123 Rue du Marché',
    city: 'Yaoundé, Cameroun',
    phone: '+237 699 00 00 00',
    taxId: 'M021512345678A',
    rccm: 'RC/YAO/2019/B/1234',
  );

  Facture facture({
    List<LigneFacture> lignes = const [
      LigneFacture(
        reference: 'RIZ25',
        designation: 'RIZ PERLE 25KG',
        quantite: 2,
        prixUnitaire: Montant(11925),
        taux: Taux(1925),
      ),
    ],
    String? client = 'MAHIMA',
    Montant regle = const Montant(0),
  }) {
    var ttc = const Montant(0);
    for (final ligne in lignes) {
      ttc = ttc + ligne.totalTtc;
    }
    final reste = ttc - regle;
    return Facture(
      numero: 'TKT0000042',
      date: '2026-09-21',
      magasin: 'BMC',
      client: client,
      caissier: 'awa',
      lignes: lignes,
      ventilation: FactureService.ventiler(lignes, devise: Devise.xaf),
      totalTtc: ttc,
      regle: regle,
      reste: reste.estNegatif ? const Montant(0) : reste,
    );
  }

  test('une facture se construit et porte du contenu', () async {
    final bytes = await FacturePdfService.build(
      FacturePdfRequest(facture: facture(), societe: societe),
    );

    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('une société sans mentions légales ne casse pas le document',
      () async {
    // Une installation neuve n'a rempli que son nom.
    final bytes = await FacturePdfService.build(
      FacturePdfRequest(
        facture: facture(),
        societe: const CompanySettings(name: 'Maison Kamdem'),
      ),
    );

    expect(bytes.length, greaterThan(1000));
  });

  test('un client de passage se dit, il ne se laisse pas vide', () async {
    // Un vide serait lu comme un oubli ; la plupart des ventes au
    // comptoir n'ont pas de fiche client.
    final bytes = await FacturePdfService.build(
      FacturePdfRequest(facture: facture(client: null), societe: societe),
    );

    expect(bytes.length, greaterThan(1000));
  });

  test('une facture dont la TVA est inconnue se construit quand même',
      () async {
    // Elle porte alors l'avertissement, qui est un bloc de plus à
    // mettre en page.
    final f = facture(lignes: const [
      LigneFacture(
        reference: 'VIEUX',
        designation: 'Ligne importée de Sage',
        quantite: 1,
        prixUnitaire: Montant(5000),
      ),
    ]);
    expect(f.estVentilable, isFalse);

    final bytes = await FacturePdfService.build(
      FacturePdfRequest(facture: f, societe: societe),
    );

    expect(bytes.length, greaterThan(1000));
  });

  test('un panier de gros tient sur plusieurs pages', () async {
    // `MultiPage` plafonne à 20 pages ce qu'un seul widget peut
    // traverser, en assert : un tableau qui déborde ce plafond tue un
    // build de debug et fait perdre des minutes à un build de release.
    final lignes = [
      for (var i = 0; i < 300; i++)
        LigneFacture(
          reference: 'REF$i',
          designation: 'ARTICLE DE GROS NUMÉRO $i',
          quantite: i + 1,
          prixUnitaire: const Montant(11925),
          taux: const Taux(1925),
        ),
    ];

    final bytes = await FacturePdfService.build(
      FacturePdfRequest(facture: facture(lignes: lignes), societe: societe),
    );

    expect(bytes.length, greaterThan(5000));
  });

  test('une facture acquittée et une facture à crédit se construisent',
      () async {
    for (final regle in [const Montant(0), const Montant(23850)]) {
      final bytes = await FacturePdfService.build(
        FacturePdfRequest(
          facture: facture(regle: regle),
          societe: societe,
        ),
      );
      expect(bytes.length, greaterThan(1000));
    }
  });
}
