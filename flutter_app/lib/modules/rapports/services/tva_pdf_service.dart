import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:erp/shared/models/company_settings.dart';
import 'package:erp/shared/models/comptabilite.dart';

class TvaPdfRequest {
  final DeclarationTva declaration;
  final CompanySettings societe;

  const TvaPdfRequest({required this.declaration, required this.societe});
}

/// Le récapitulatif de TVA collectée sur une période.
///
/// Ce document porte **une seule moitié** de la déclaration, et le dit
/// en toutes lettres. La TVA déductible se lit sur les factures
/// d'achat, que ce logiciel n'enregistre pas encore ; annoncer une taxe
/// nette à payer en supposant zéro de déductible produirait un chiffre
/// faux et crédible, ce qui est la pire espèce de chiffre.
///
/// Il porte aussi l'état de la période : ouverte, la déclaration peut
/// être démentie par une correction le lendemain, et celui qui la lit
/// doit le savoir avant de la déposer.
class TvaPdfService {
  static const _gris = PdfColor.fromInt(0xFF555555);
  static const _trait = PdfColor.fromInt(0xFFBBBBBB);
  static const _alerte = PdfColor.fromInt(0xFFB42318);

  static Future<Uint8List> buildInBackground(TvaPdfRequest request) =>
      compute(_buildIsolate, request);

  static Future<Uint8List> _buildIsolate(TvaPdfRequest request) =>
      build(request);

  static Future<Uint8List> build(TvaPdfRequest request) async {
    final document = pw.Document();
    final d = request.declaration;

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        maxPages: 10,
        build: (context) => [
          _entete(request),
          pw.SizedBox(height: 20),
          _etatPeriode(d),
          pw.SizedBox(height: 16),
          _tableau(d),
          pw.SizedBox(height: 16),
          _totaux(d),
          pw.SizedBox(height: 16),
          _deductible(),
          if (d.aDesInconnues) ...[
            pw.SizedBox(height: 12),
            _reserves(d),
          ],
          pw.SizedBox(height: 30),
          _signature(),
        ],
      ),
    );

    return document.save();
  }

  static pw.Widget _entete(TvaPdfRequest request) {
    final societe = request.societe;
    final mentions = <String>[
      if (societe.taxId.isNotEmpty) 'NIU : ${societe.taxId}',
      if (societe.rccm.isNotEmpty) 'RCCM : ${societe.rccm}',
      if (societe.city.isNotEmpty) societe.city,
    ];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(societe.name,
            style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
        if (mentions.isNotEmpty)
          pw.Text(mentions.join('  ·  '),
              style: const pw.TextStyle(fontSize: 9, color: _gris)),
        pw.SizedBox(height: 12),
        pw.Text('TVA COLLECTÉE',
            style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold)),
        pw.Text(
          'Période du ${request.declaration.du} au ${request.declaration.au}',
          style: const pw.TextStyle(fontSize: 10, color: _gris),
        ),
      ],
    );
  }

  /// L'état de la période, en haut et non en note.
  ///
  /// C'est ce qui dit si le document peut encore changer. Le mettre en
  /// bas de page reviendrait à le cacher de celui qui doit en tenir
  /// compte.
  static pw.Widget _etatPeriode(DeclarationTva d) {
    final ferme = d.periodeFermee;
    return pw.Container(
      padding: const pw.EdgeInsets.all(7),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
            color: ferme ? _trait : _alerte, width: ferme ? 0.5 : 0.8),
      ),
      child: pw.Text(
        ferme
            ? 'Période clôturée au ${d.fermeJusquau} : les écritures de '
                'cette période ne peuvent plus être modifiées.'
            : 'Période NON clôturée : les écritures de cette période '
                'peuvent encore être corrigées, et ces montants changer. '
                'Clôturez avant de déposer.',
        style: pw.TextStyle(
            fontSize: 9, color: ferme ? _gris : _alerte),
      ),
    );
  }

  static const _largeurs = {
    0: pw.FlexColumnWidth(2),
    1: pw.FlexColumnWidth(2.4),
    2: pw.FlexColumnWidth(2.4),
    3: pw.FlexColumnWidth(2.4),
  };

  static pw.Widget _tableau(DeclarationTva d) {
    final titre = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);
    const cellule = pw.TextStyle(fontSize: 10);

    return pw.Table(
      border: pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _trait, width: 0.4),
        bottom: pw.BorderSide(color: _trait, width: 0.4),
      ),
      columnWidths: _largeurs,
      children: [
        pw.TableRow(
          decoration:
              const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEFEFEF)),
          children: [
            _cell('TAUX', titre),
            _cell('CHIFFRE TTC', titre, droite: true),
            _cell('BASE HT', titre, droite: true),
            _cell('TVA COLLECTÉE', titre, droite: true),
          ],
        ),
        for (final ligne in d.lignes)
          pw.TableRow(children: [
            _cell(ligne.taux.toString(), cellule),
            _cell(ligne.ttc.formate(avecSymbole: false), cellule,
                droite: true),
            _cell(ligne.baseHt.formate(avecSymbole: false), cellule,
                droite: true),
            _cell(ligne.tva.formate(avecSymbole: false),
                cellule.copyWith(fontWeight: pw.FontWeight.bold),
                droite: true),
          ]),
        if (d.lignes.isEmpty)
          pw.TableRow(children: [
            _cell('Aucune vente sur la période', cellule),
            _cell('', cellule),
            _cell('', cellule),
            _cell('', cellule),
          ]),
      ],
    );
  }

  static pw.Widget _totaux(DeclarationTva d) => pw.Table(
        columnWidths: _largeurs,
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(color: PdfColors.black, width: 0.8),
              ),
            ),
            children: [
              _cell('TOTAL',
                  pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              _cell(d.totalTtc.formate(avecSymbole: false),
                  pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                  droite: true),
              _cell(d.totalHt.formate(avecSymbole: false),
                  pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                  droite: true),
              _cell(d.totalTva.formate(),
                  pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                  droite: true),
            ],
          ),
        ],
      );

  /// La moitié manquante, nommée.
  ///
  /// Un document qui s'arrête à la TVA collectée sans le dire laisse
  /// croire que c'est la taxe à payer. C'en est le point de départ.
  static pw.Widget _deductible() => pw.Container(
        padding: const pw.EdgeInsets.all(7),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _trait, width: 0.5),
        ),
        child: pw.Text(
          'TVA déductible : non tenue par ce logiciel. Les entrées de '
          'stock ne portent ni taux ni montant de taxe, faute de saisie '
          'des factures d\'achat. Le montant ci-dessus est donc la TVA '
          'collectée, et non la TVA nette à payer : il faut lui '
          'soustraire la déductible établie par ailleurs.',
          style: const pw.TextStyle(fontSize: 8.5, color: _gris),
        ),
      );

  static pw.Widget _reserves(DeclarationTva d) {
    final phrases = <String>[
      if (d.lignesSansTaux > 0)
        '${d.lignesSansTaux} ligne(s) vendue(s) sans taux enregistré, soit '
            '${d.ttcSansTaux.formate()} : dans le chiffre TTC, hors de '
            'toute base. Ces ventes sont antérieures à l\'enregistrement '
            'du taux sur la ligne.',
      if (d.lignesSansPrix > 0)
        '${d.lignesSansPrix} ligne(s) vendue(s) sans prix : hors de tous '
            'les totaux ci-dessus.',
    ];
    return pw.Container(
      padding: const pw.EdgeInsets.all(7),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _alerte, width: 0.6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('CE QUE CE RÉCAPITULATIF NE COUVRE PAS',
              style: pw.TextStyle(
                  fontSize: 8, color: _alerte, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 3),
          for (final phrase in phrases)
            pw.Text(phrase, style: const pw.TextStyle(fontSize: 8.5)),
        ],
      ),
    );
  }

  static pw.Widget _signature() => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.Container(
            width: 220,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Le responsable',
                    style: const pw.TextStyle(fontSize: 9, color: _gris)),
                pw.SizedBox(height: 30),
                pw.Divider(color: _trait, height: 1),
              ],
            ),
          ),
        ],
      );

  static pw.Widget _cell(String texte, pw.TextStyle style,
          {bool droite = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        child: pw.Text(
          texte,
          style: style,
          textAlign: droite ? pw.TextAlign.right : pw.TextAlign.left,
        ),
      );
}
