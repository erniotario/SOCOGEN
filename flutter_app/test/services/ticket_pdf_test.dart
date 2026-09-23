import 'package:flutter_test/flutter_test.dart';

import 'package:erp/core/money/montant.dart';
import 'package:erp/shared/models/company_settings.dart';
import 'package:erp/modules/rapports/services/ticket_pdf_service.dart';
import 'package:erp/shared/models/vente.dart';

/// Le ticket remis au client.
///
/// Un PDF ne se relit pas facilement : ce qui est vérifié ici est ce
/// qu'on peut vérifier sans l'ouvrir — qu'il se construit, qu'il n'est
/// pas vide, et qu'il supporte les cas où l'application ne sait pas
/// tout. Ce qu'il ne dit pas de l'allure du papier, seule une
/// impression réelle le dira.
void main() {
  const societe = CompanySettings(
    name: 'SOCOGEN Sarl',
    address: '123 Rue du Marché',
    city: 'Yaoundé, Cameroun',
    phone: '+237 699 00 00 00',
    taxId: 'M021512345678A',
  );

  const lignes = [
    LigneVente(
      reference: 'RIZ25',
      designation: 'RIZ PERLE 25KG',
      quantite: 2,
      prixUnitaire: Montant(18500),
    ),
    LigneVente(
      reference: 'HUILE',
      designation: 'HUILE OLEO 1L',
      quantite: 3,
      prixUnitaire: Montant(1450),
    ),
  ];

  TicketPdfRequest requete({
    String? caissier = 'awa',
    String? client,
    List<LigneVente> contenu = lignes,
    CompanySettings entreprise = societe,
  }) =>
      TicketPdfRequest(
        numero: 'TKT0000042',
        date: '21/09/2026 14:30',
        magasin: 'BMC',
        societe: entreprise,
        lignes: contenu,
        caissier: caissier,
        client: client,
      );

  test('un ticket se construit et porte du contenu', () async {
    final bytes = await TicketPdfService.build(requete());

    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('sans caissier, le ticket sort quand même', () async {
    // Une vente hors session n'a pas d'auteur, et un ticket vaut mieux
    // sans nom qu'avec un faux.
    final bytes = await TicketPdfService.build(requete(caissier: null));

    expect(bytes.length, greaterThan(1000));
  });

  test("sans nom d'entreprise, le ticket sort sans en-tête", () async {
    // Une installation neuve n'a pas encore dit qui elle est. Emprunter
    // le nom de quelqu'un d'autre serait pire que de n'en mettre aucun.
    final bytes = await TicketPdfService.build(
      requete(entreprise: const CompanySettings()),
    );

    expect(bytes.length, greaterThan(500));
  });

  test('avec un client nommé', () async {
    final bytes = await TicketPdfService.build(requete(client: 'BMC'));

    expect(bytes.length, greaterThan(1000));
  });

  test('un ticket long tient sur une seule page', () async {
    // Le format rouleau a une hauteur libre : trente lignes sortent
    // d'un seul tenant, sans saut de page à recoller au comptoir.
    final longues = [
      for (var i = 0; i < 30; i++)
        LigneVente(
          reference: 'ART$i',
          designation: 'ARTICLE NUMERO $i AVEC UNE DESIGNATION LONGUE',
          quantite: i + 1,
          prixUnitaire: Montant(1000 + i * 25),
        ),
    ];

    final bytes = await TicketPdfService.build(requete(contenu: longues));

    expect(bytes.length, greaterThan(2000));
    // Une seule page : le document en déclare le nombre.
    final texte = String.fromCharCodes(bytes);
    expect(texte, contains('/Count 1'));
  });

  test('un panier vide ne fait pas échouer la construction', () async {
    // Le service refuse déjà d'encaisser un panier vide ; si un ticket
    // vide arrivait quand même ici, mieux vaut un papier blanc qu'une
    // exception au comptoir.
    final bytes = await TicketPdfService.build(requete(contenu: const []));

    expect(bytes.length, greaterThan(500));
  });
}
