import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:erp/shared/models/company_settings.dart';
import 'package:erp/shared/models/facture.dart';

/// Tout ce que la facture doit dire, en un objet.
///
/// Rassemblé ainsi pour partir vers l'isolat de fond en un seul message,
/// comme le ticket et le rapport de transactions.
class FacturePdfRequest {
  final Facture facture;
  final CompanySettings societe;

  const FacturePdfRequest({required this.facture, required this.societe});
}

/// La facture remise à un client qui doit justifier son achat.
///
/// **A4 et non rouleau**, à l'inverse du ticket : elle se classe, se
/// photocopie et s'envoie, et elle porte des mentions légales qu'aucune
/// bande de 80 mm ne tient.
///
/// Ce qu'elle ajoute au ticket est la ventilation de la TVA. Une facture
/// qui n'annonce qu'un total de taxe ne permet pas de la contrôler ;
/// celle-ci donne, par taux rencontré, la base hors taxe et la taxe
/// correspondante.
class FacturePdfService {
  /// Ce qu'une ligne affiche quand son taux n'est pas connu.
  ///
  /// « n.c. » et non « — » : le tiret cadratin est hors WinAnsi, et le
  /// paquet `pdf` le **laisse tomber sans rien dire** avec les polices
  /// intégrées. La cellule sortirait vide, ce qui se lit comme un
  /// oubli de saisie au lieu d'un taux inconnu. L'avertissement sous le
  /// tableau dit le reste.
  static const String tauxInconnu = 'n.c.';

  static const _format = PdfPageFormat.a4;
  static const _gris = PdfColor.fromInt(0xFF555555);
  static const _trait = PdfColor.fromInt(0xFFBBBBBB);

  static Future<Uint8List> buildInBackground(FacturePdfRequest request) =>
      compute(_buildIsolate, request);

  static Future<Uint8List> _buildIsolate(FacturePdfRequest request) =>
      build(request);

  static Future<Uint8List> build(FacturePdfRequest request) async {
    final document = pw.Document();
    final facture = request.facture;

    document.addPage(
      pw.MultiPage(
        pageFormat: _format,
        margin: const pw.EdgeInsets.all(32),
        // Une facture tient normalement sur une page ; le plafond n'est
        // relevé que pour le panier de gros qui en réclame plusieurs.
        maxPages: 40,
        header: (context) => context.pageNumber == 1
            ? pw.SizedBox()
            : _enteteSuite(facture, context.pageNumber),
        footer: (context) => _pied(request, context),
        build: (context) => [
          _enSociete(request.societe),
          pw.SizedBox(height: 18),
          _enFacture(facture),
          pw.SizedBox(height: 16),
          _tableau(facture),
          pw.SizedBox(height: 14),
          _totaux(facture),
          if (!facture.estVentilable) ...[
            pw.SizedBox(height: 8),
            _avertissementVentilation(facture),
          ],
          pw.SizedBox(height: 14),
          _reglement(facture),
        ],
      ),
    );

    return document.save();
  }

  // --- En-têtes --------------------------------------------------------

  static pw.Widget _enSociete(CompanySettings societe) {
    final coordonnees = <String>[
      if (societe.address.isNotEmpty) societe.address,
      if (societe.city.isNotEmpty) societe.city,
      if (societe.phone.isNotEmpty) 'Tél. ${societe.phone}',
      if (societe.email.isNotEmpty) societe.email,
    ];
    // Les mentions légales, que la facture doit porter pour servir de
    // pièce justificative chez le client.
    final mentions = <String>[
      if (societe.taxId.isNotEmpty) 'NIU : ${societe.taxId}',
      if (societe.rccm.isNotEmpty) 'RCCM : ${societe.rccm}',
    ];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          societe.name,
          style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold),
        ),
        if (coordonnees.isNotEmpty)
          pw.Text(coordonnees.join(' · '),
              style: const pw.TextStyle(fontSize: 9, color: _gris)),
        if (mentions.isNotEmpty)
          pw.Text(mentions.join(' · '),
              style: const pw.TextStyle(fontSize: 9, color: _gris)),
      ],
    );
  }

  static pw.Widget _enFacture(Facture facture) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('FACTURE',
                style:
                    pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            // Le numéro de la facture est celui du ticket : une vente
            // est un événement, et un second numéro pour la même vente
            // rendrait la question « laquelle est la bonne ? »
            // inévitable au premier litige.
            pw.Text('N° ${facture.numero}',
                style: const pw.TextStyle(fontSize: 11)),
            pw.Text('Date : ${facture.date}',
                style: const pw.TextStyle(fontSize: 9, color: _gris)),
            pw.Text('Point de vente : ${facture.magasin}',
                style: const pw.TextStyle(fontSize: 9, color: _gris)),
          ],
        ),
        pw.Container(
          width: 200,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _trait, width: 0.5),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('CLIENT',
                  style: pw.TextStyle(
                      fontSize: 8,
                      color: _gris,
                      fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 3),
              pw.Text(
                // Un passant n'a pas de fiche, et c'est le cas courant
                // au comptoir : le dire vaut mieux que laisser un vide
                // qu'on croira oublié.
                facture.client?.isNotEmpty == true
                    ? facture.client!
                    : 'Client de passage',
                style: pw.TextStyle(
                    fontSize: 11, fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _enteteSuite(Facture facture, int page) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: pw.Text(
          'Facture N° ${facture.numero}, suite (page $page)',
          style: const pw.TextStyle(fontSize: 9, color: _gris),
        ),
      );

  // --- Corps -----------------------------------------------------------

  static pw.Widget _tableau(Facture facture) {
    final entete = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);
    const cellule = pw.TextStyle(fontSize: 9);

    return pw.Table(
      border: pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _trait, width: 0.5),
        bottom: pw.BorderSide(color: _trait, width: 0.5),
      ),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.6),
        1: pw.FlexColumnWidth(4),
        2: pw.FlexColumnWidth(0.9),
        3: pw.FlexColumnWidth(1.4),
        4: pw.FlexColumnWidth(1.4),
        5: pw.FlexColumnWidth(1.6),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFEFEFEF),
          ),
          children: [
            _cellule('RÉFÉRENCE', entete),
            _cellule('DÉSIGNATION', entete),
            _cellule('QTÉ', entete, droite: true),
            _cellule('TVA', entete, droite: true),
            _cellule('P.U. TTC', entete, droite: true),
            _cellule('TOTAL TTC', entete, droite: true),
          ],
        ),
        for (final ligne in facture.lignes)
          pw.TableRow(
            children: [
              _cellule(ligne.reference, cellule),
              _cellule(ligne.designation, cellule),
              _cellule('${ligne.quantite}', cellule, droite: true),
              _cellule(
                // « n.c. » plutôt qu'un zéro : la ligne ne dit pas que
                // la TVA est nulle, elle ne dit rien. Et pas un tiret
                // cadratin : voir [tauxInconnu].
                ligne.taux == null ? tauxInconnu : ligne.taux.toString(),
                cellule,
                droite: true,
              ),
              _cellule(ligne.prixUnitaire.formate(avecSymbole: false), cellule,
                  droite: true),
              _cellule(ligne.totalTtc.formate(avecSymbole: false), cellule,
                  droite: true),
            ],
          ),
      ],
    );
  }

  static pw.Widget _cellule(String texte, pw.TextStyle style,
          {bool droite = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: pw.Text(
          texte,
          style: style,
          textAlign: droite ? pw.TextAlign.right : pw.TextAlign.left,
        ),
      );

  static pw.Widget _totaux(Facture facture) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Container(
          width: 260,
          child: pw.Column(
            children: [
              for (final bloc in facture.ventilation) ...[
                _totalLigne(
                  'Base HT ${bloc.taux}',
                  bloc.baseHt.formate(avecSymbole: false),
                ),
                _totalLigne(
                  'TVA ${bloc.taux}',
                  bloc.tva.formate(avecSymbole: false),
                ),
              ],
              if (facture.ventilation.isNotEmpty) ...[
                pw.Divider(color: _trait, height: 8),
                _totalLigne('Total HT',
                    facture.totalHt.formate(avecSymbole: false)),
                _totalLigne('Total TVA',
                    facture.totalTva.formate(avecSymbole: false)),
              ],
              pw.Divider(color: _trait, height: 8),
              _totalLigne(
                'TOTAL TTC',
                facture.totalTtc.formate(),
                fort: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _totalLigne(String libelle, String valeur,
          {bool fort = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(libelle,
                style: pw.TextStyle(
                  fontSize: fort ? 11 : 9,
                  fontWeight: fort ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: fort ? null : _gris,
                )),
            pw.Text(valeur,
                style: pw.TextStyle(
                  fontSize: fort ? 11 : 9,
                  fontWeight: fort ? pw.FontWeight.bold : pw.FontWeight.normal,
                )),
          ],
        ),
      );

  /// Ce que la facture ne peut pas ventiler, dit à voix haute.
  ///
  /// Se taire présenterait une ventilation partielle comme complète, et
  /// laisserait croire que le reste est exonéré. Ces lignes sont
  /// antérieures au figeage du taux : leur TVA n'a jamais été écrite.
  static pw.Widget _avertissementVentilation(Facture facture) {
    final combien = facture.lignesSansTaux.length;
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _trait, width: 0.5),
      ),
      child: pw.Text(
        '$combien ligne(s), soit '
        '${facture.ttcSansTaux.formate()}, sans taux de TVA enregistré : '
        'ce montant est compté dans le total TTC mais ne figure dans '
        'aucune base ci-dessus.',
        style: const pw.TextStyle(fontSize: 8, color: _gris),
      ),
    );
  }

  static pw.Widget _reglement(Facture facture) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _trait, width: 0.5),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            facture.estReglee ? 'FACTURE ACQUITTÉE' : 'RESTE DÛ',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            facture.estReglee
                ? facture.regle.formate()
                : facture.reste.formate(),
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  static pw.Widget _pied(FacturePdfRequest request, pw.Context context) {
    final facture = request.facture;
    final gauche = <String>[
      if (facture.caissier != null) 'Établie par ${facture.caissier}',
      if (request.societe.website.isNotEmpty) request.societe.website,
    ];
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(gauche.join(' · '),
              style: const pw.TextStyle(fontSize: 8, color: _gris)),
          pw.Text('Page ${context.pageNumber}/${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: _gris)),
        ],
      ),
    );
  }
}
