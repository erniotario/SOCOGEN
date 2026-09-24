import 'package:flutter_test/flutter_test.dart';

import 'package:erp/core/money/montant.dart';
import 'package:erp/modules/rapports/services/tva_pdf_service.dart';
import 'package:erp/shared/models/company_settings.dart';
import 'package:erp/shared/models/comptabilite.dart';

/// Le récapitulatif de TVA.
///
/// Ce qui se vérifie sans ouvrir le fichier : qu'il se construit, et
/// qu'il tient debout dans les deux états qui comptent — période
/// fermée, période encore ouverte — ainsi qu'avec ses réserves.
void main() {
  const societe = CompanySettings(
    name: 'SHEMA BUSINESSES',
    city: 'Yaoundé, Cameroun',
    taxId: 'M021512345678A',
    rccm: 'RC/YAO/2019/B/1234',
  );

  DeclarationTva declaration({
    String? fermeJusquau,
    int sansTaux = 0,
    int lignesSansTaux = 0,
    int lignesSansPrix = 0,
    List<LigneTva>? lignes,
  }) =>
      DeclarationTva(
        du: '2026-08-01',
        au: '2026-08-31',
        lignes: lignes ??
            const [
              LigneTva(
                taux: Taux(1925),
                ttc: Montant(2385000),
                baseHt: Montant(2000000),
                tva: Montant(385000),
              ),
              LigneTva(
                taux: Taux(0),
                ttc: Montant(150000),
                baseHt: Montant(150000),
                tva: Montant(0),
              ),
            ],
        ttcSansTaux: Montant(sansTaux),
        lignesSansTaux: lignesSansTaux,
        lignesSansPrix: lignesSansPrix,
        fermeJusquau: fermeJusquau,
      );

  test('un récapitulatif se construit et porte du contenu', () async {
    final bytes = await TvaPdfService.build(
      TvaPdfRequest(
        declaration: declaration(fermeJusquau: '2026-08-31'),
        societe: societe,
      ),
    );

    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('une période ouverte se construit aussi, et le dit', () async {
    // Le bandeau d'alerte est un bloc de plus à mettre en page.
    final d = declaration();
    expect(d.periodeFermee, isFalse);

    final bytes = await TvaPdfService.build(
      TvaPdfRequest(declaration: d, societe: societe),
    );

    expect(bytes.length, greaterThan(1000));
  });

  test('une période partiellement fermée reste ouverte', () async {
    // Fermé au 15 alors que la période va jusqu'au 31 : la fin peut
    // encore bouger, donc la déclaration aussi.
    final d = declaration(fermeJusquau: '2026-08-15');

    expect(d.periodeFermee, isFalse);
    expect(
      (await TvaPdfService.build(
        TvaPdfRequest(declaration: d, societe: societe),
      ))
          .length,
      greaterThan(1000),
    );
  });

  test('les réserves ajoutent leur bloc', () async {
    final d = declaration(
      fermeJusquau: '2026-08-31',
      sansTaux: 45000,
      lignesSansTaux: 6,
      lignesSansPrix: 3,
    );
    expect(d.aDesInconnues, isTrue);
    expect(d.totalTtc, const Montant(2385000 + 150000 + 45000));
    expect(d.totalHt, const Montant(2150000),
        reason: 'le TTC sans taux ne rejoint aucune base');

    final bytes = await TvaPdfService.build(
      TvaPdfRequest(declaration: d, societe: societe),
    );

    expect(bytes.length, greaterThan(1000));
  });

  test('un mois sans aucune vente se construit', () async {
    final bytes = await TvaPdfService.build(
      TvaPdfRequest(
        declaration: declaration(lignes: const [], fermeJusquau: '2026-08-31'),
        societe: societe,
      ),
    );

    expect(bytes.length, greaterThan(800));
  });

  test('une société sans mentions légales ne casse pas le document',
      () async {
    final bytes = await TvaPdfService.build(
      TvaPdfRequest(
        declaration: declaration(),
        societe: const CompanySettings(name: 'Maison Kamdem'),
      ),
    );

    expect(bytes.length, greaterThan(800));
  });
}
