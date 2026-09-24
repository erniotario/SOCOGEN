import 'package:flutter_test/flutter_test.dart';

import 'package:erp/core/money/montant.dart';
import 'package:erp/modules/rapports/services/cloture_pdf_service.dart';
import 'package:erp/shared/models/cloture.dart';
import 'package:erp/shared/models/company_settings.dart';
import 'package:erp/shared/models/facture.dart';
import 'package:erp/shared/models/paiement.dart';

/// Le journal de caisse.
///
/// Comme pour les autres PDF, ce qui se vérifie sans ouvrir le fichier :
/// qu'il se construit, et qu'il tient debout dans les cas où
/// l'application ne sait pas tout — une journée vide, une journée dont
/// une partie du chiffre n'est pas ventilable.
void main() {
  const societe = CompanySettings(
    name: 'SHEMA BUSINESSES',
    city: 'Yaoundé, Cameroun',
  );

  ClotureCaisse cloture({
    int tickets = 3,
    Montant ventes = const Montant(150000),
    List<VentilationTva> tva = const [
      VentilationTva(
        taux: Taux(1925),
        baseHt: Montant(125786),
        tva: Montant(24214),
      ),
    ],
    List<EncaisseParMode> encaisse = const [
      EncaisseParMode(
        mode: ModePaiement.especes,
        montant: Montant(90000),
        operations: 4,
      ),
      EncaisseParMode(
        mode: ModePaiement.mobileMoney,
        montant: Montant(35000),
        operations: 2,
      ),
    ],
    int lignesSansPrix = 0,
    Montant ttcSansTaux = const Montant(0),
  }) =>
      ClotureCaisse(
        date: '2026-09-24',
        magasin: 'BMC',
        tickets: tickets,
        ventesTtc: ventes,
        tva: tva,
        lignesSansPrix: lignesSansPrix,
        ttcSansTaux: ttcSansTaux,
        creditAccorde: const Montant(25000),
        encaisse: encaisse,
        encaisseDuJour: const Montant(125000),
        encaisseSurCreances: const Montant(0),
      );

  test('un journal se construit et porte du contenu', () async {
    final bytes = await ClosurePdfService.build(
      ClosurePdfRequest(cloture: cloture(), societe: societe),
    );

    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('une journée sans rien s\'imprime quand même', () async {
    // Un journal vide est une information : il dit que la caisse n'a
    // pas tourné, ce qui se signe aussi.
    final vide = cloture(
      tickets: 0,
      ventes: const Montant(0),
      tva: const [],
      encaisse: const [],
    );
    expect(vide.estVide, isTrue);

    final bytes = await ClosurePdfService.build(
      ClosurePdfRequest(cloture: vide, societe: societe),
    );

    expect(bytes.length, greaterThan(1000));
  });

  test('les réserves ajoutent un bloc sans casser la mise en page',
      () async {
    final bytes = await ClosurePdfService.build(
      ClosurePdfRequest(
        cloture: cloture(
          lignesSansPrix: 4,
          ttcSansTaux: const Montant(18000),
        ),
        societe: societe,
      ),
    );

    expect(bytes.length, greaterThan(1000));
  });

  test('une clôture tous magasins confondus se construit', () async {
    final tous = ClotureCaisse(
      date: '2026-09-24',
      tickets: 12,
      ventesTtc: const Montant(500000),
      tva: const [],
      lignesSansPrix: 0,
      ttcSansTaux: const Montant(0),
      creditAccorde: const Montant(0),
      encaisse: const [],
      encaisseDuJour: const Montant(0),
      encaisseSurCreances: const Montant(0),
    );
    expect(tous.magasin, isNull);

    final bytes = await ClosurePdfService.build(
      ClosurePdfRequest(cloture: tous, societe: societe),
    );

    expect(bytes.length, greaterThan(1000));
  });
}
