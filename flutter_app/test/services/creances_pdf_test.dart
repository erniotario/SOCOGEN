import 'package:flutter_test/flutter_test.dart';

import 'package:erp/core/money/montant.dart';
import 'package:erp/modules/rapports/services/creances_pdf_service.dart';
import 'package:erp/shared/models/company_settings.dart';
import 'package:erp/shared/models/creance.dart';

/// La balance âgée imprimée.
///
/// Ce qui se vérifie sans ouvrir le fichier : qu'il se construit, et
/// qu'il tient debout là où l'application ne sait pas tout — un état
/// vide, des tickets sans client, une liste assez longue pour dépasser
/// une page.
void main() {
  const societe = CompanySettings(
    name: 'SHEMA BUSINESSES',
    city: 'Yaoundé, Cameroun',
  );

  TicketDu ticket(String numero, int reste, int jours) => TicketDu(
        ticket: numero,
        date: '2026-08-01',
        total: Montant(reste),
        regle: const Montant(0),
        jours: jours,
      );

  CreanceClient client(
    String nom, {
    int montant = 40000,
    int jours = 12,
    int? plafond,
  }) =>
      CreanceClient(
        tiersId: nom.hashCode,
        code: 'C-$nom',
        nom: nom,
        telephone: '699000000',
        tickets: [ticket('TKT-$nom', montant, jours)],
        encours: Montant(montant),
        plafond: plafond == null ? null : Montant(plafond),
      );

  EtatCreances etat({
    List<CreanceClient>? clients,
    int sansClient = 0,
    int ticketsSansClient = 0,
    int ticketsSansDate = 0,
  }) =>
      EtatCreances(
        arreteAu: '2026-09-24',
        clients: clients ?? [client('MAHIMA'), client('DADA EKOUNOU')],
        sansClient: Montant(sansClient),
        ticketsSansClient: ticketsSansClient,
        ticketsSansDate: ticketsSansDate,
      );

  test('un état se construit et porte du contenu', () async {
    final bytes = await CreancesPdfService.build(
      CreancesPdfRequest(etat: etat(), societe: societe),
    );

    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('un état sans aucune créance se dit au lieu de sortir vide',
      () async {
    final rien = etat(clients: const []);
    expect(rien.estVide, isTrue);

    final bytes = await CreancesPdfService.build(
      CreancesPdfRequest(etat: rien, societe: societe),
    );

    expect(bytes.length, greaterThan(800));
  });

  test('les dépassements de plafond ajoutent leur bloc', () async {
    final e = etat(clients: [
      client('MAHIMA', montant: 62000, plafond: 50000),
      client('DADA', montant: 10000, plafond: 50000),
    ]);
    expect(e.auDessusDuPlafond.map((c) => c.nom), ['MAHIMA']);

    final bytes = await CreancesPdfService.build(
      CreancesPdfRequest(etat: e, societe: societe),
    );

    expect(bytes.length, greaterThan(1000));
  });

  test('les réserves ajoutent le leur', () async {
    final e = etat(
      sansClient: 45000,
      ticketsSansClient: 3,
      ticketsSansDate: 2,
    );
    expect(e.aDesReserves, isTrue);

    final bytes = await CreancesPdfService.build(
      CreancesPdfRequest(etat: e, societe: societe),
    );

    expect(bytes.length, greaterThan(1000));
  });

  test('deux cents clients tiennent sur plusieurs pages', () async {
    // `MultiPage` plafonne à 20 pages ce qu'un seul widget peut
    // traverser : le tableau est découpé en morceaux de la taille
    // d'une page, et ce test vérifie que le découpage tient.
    final e = etat(clients: [
      for (var i = 0; i < 200; i++)
        client('CLIENT NUMÉRO $i', montant: 1000 * (i + 1), jours: i),
    ]);

    final bytes = await CreancesPdfService.build(
      CreancesPdfRequest(etat: e, societe: societe),
    );

    expect(bytes.length, greaterThan(5000));
  });

  test('un client par tranche remplit chaque colonne', () async {
    final e = etat(clients: [
      client('COURANT', jours: 10),
      client('UN MOIS', jours: 45),
      client('DEUX MOIS', jours: 75),
      client('ANCIEN', jours: 200),
    ]);
    expect(e.parTranche(TrancheAge.ancien), const Montant(40000));

    final bytes = await CreancesPdfService.build(
      CreancesPdfRequest(etat: e, societe: societe),
    );

    expect(bytes.length, greaterThan(1000));
  });
}
