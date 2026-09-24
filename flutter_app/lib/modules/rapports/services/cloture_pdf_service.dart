import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:erp/shared/models/cloture.dart';
import 'package:erp/shared/models/company_settings.dart';

class ClosurePdfRequest {
  final ClotureCaisse cloture;
  final CompanySettings societe;

  const ClosurePdfRequest({required this.cloture, required this.societe});
}

/// Le journal de caisse du soir.
///
/// **A4 et non rouleau** : il se classe et se signe, à la différence du
/// ticket. Il s'imprime avant de compter le tiroir — ce qui en fait
/// l'ordre de lecture : d'abord ce qui est entré et en quelles espèces,
/// ensuite seulement ce qui a été vendu. Un caissier qui compte des
/// billets n'a que faire du chiffre d'affaires à cet instant.
class ClosurePdfService {
  static const _gris = PdfColor.fromInt(0xFF555555);
  static const _trait = PdfColor.fromInt(0xFFBBBBBB);

  static Future<Uint8List> buildInBackground(ClosurePdfRequest request) =>
      compute(_buildIsolate, request);

  static Future<Uint8List> _buildIsolate(ClosurePdfRequest request) =>
      build(request);

  static Future<Uint8List> build(ClosurePdfRequest request) async {
    final document = pw.Document();
    final cloture = request.cloture;

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        maxPages: 10,
        build: (context) => [
          _entete(request),
          pw.SizedBox(height: 18),
          _bloc('CE QUI EST ENTRÉ', _encaissements(cloture)),
          pw.SizedBox(height: 14),
          _bloc('CE QUI A ÉTÉ VENDU', _ventes(cloture)),
          if (cloture.tva.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            _bloc('TVA COLLECTÉE', _tva(cloture)),
          ],
          if (cloture.aDesInconnues) ...[
            pw.SizedBox(height: 10),
            _reserves(cloture),
          ],
          pw.SizedBox(height: 26),
          _signatures(),
        ],
      ),
    );

    return document.save();
  }

  static pw.Widget _entete(ClosurePdfRequest request) {
    final cloture = request.cloture;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(request.societe.name,
            style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 10),
        pw.Text('JOURNAL DE CAISSE',
            style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold)),
        pw.Text(
          [
            'Journée du ${cloture.date}',
            if (cloture.magasin != null)
              'Point de vente : ${cloture.magasin}'
            else
              'Tous les points de vente',
          ].join('  ·  '),
          style: const pw.TextStyle(fontSize: 10, color: _gris),
        ),
      ],
    );
  }

  static pw.Widget _bloc(String titre, List<pw.Widget> contenu) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(titre,
              style: pw.TextStyle(
                  fontSize: 9,
                  color: _gris,
                  fontWeight: pw.FontWeight.bold)),
          pw.Divider(color: _trait, height: 8),
          ...contenu,
        ],
      );

  static List<pw.Widget> _encaissements(ClotureCaisse cloture) => [
        for (final ligne in cloture.encaisse)
          _ligne(
            '${ligne.mode.libelle}  (${ligne.operations})',
            ligne.montant.formate(avecSymbole: false),
          ),
        if (cloture.encaisse.isEmpty)
          _ligne('Aucun règlement enregistré', ''),
        pw.Divider(color: _trait, height: 8),
        _ligne('TOTAL ENCAISSÉ', cloture.encaisseTotal.formate(), fort: true),
        pw.SizedBox(height: 4),
        // La distinction qui fait tout l'objet de ce document.
        _ligne('dont ventes du jour',
            cloture.encaisseDuJour.formate(avecSymbole: false)),
        _ligne('dont créances antérieures',
            cloture.encaisseSurCreances.formate(avecSymbole: false)),
        pw.SizedBox(height: 6),
        _ligne('Espèces à compter dans le tiroir',
            cloture.especes.formate(), fort: true),
      ];

  static List<pw.Widget> _ventes(ClotureCaisse cloture) => [
        _ligne('Tickets', '${cloture.tickets}'),
        _ligne('Total vendu TTC',
            cloture.ventesTtc.formate(), fort: true),
        // Vendu n'est pas encaissé : ce qui est parti à crédit gonfle
        // le premier sans rien mettre dans le tiroir.
        _ligne('dont resté dû ce soir',
            cloture.creditAccorde.formate(avecSymbole: false)),
      ];

  static List<pw.Widget> _tva(ClotureCaisse cloture) => [
        for (final bloc in cloture.tva)
          _ligne(
            'Base HT ${bloc.taux}   |   TVA',
            '${bloc.baseHt.formate(avecSymbole: false)}   |   '
                '${bloc.tva.formate(avecSymbole: false)}',
          ),
        pw.Divider(color: _trait, height: 8),
        _ligne('TOTAL TVA COLLECTÉE', cloture.totalTva.formate(), fort: true),
      ];

  /// Ce que le journal ne sait pas dire, dit à voix haute.
  ///
  /// Se taire présenterait un total partiel comme complet — et c'est
  /// précisément sur ce document qu'on décide que la caisse tombe
  /// juste.
  static pw.Widget _reserves(ClotureCaisse cloture) {
    final phrases = <String>[
      if (cloture.lignesSansPrix > 0)
        '${cloture.lignesSansPrix} ligne(s) vendue(s) sans prix '
            'enregistré : elles ne sont comptées dans aucun total.',
      if (cloture.ttcSansTaux.estPositif)
        '${cloture.ttcSansTaux.formate()} vendu(s) sans taux de TVA '
            'enregistré : ce montant est dans le total vendu mais dans '
            'aucune base ci-dessus.',
    ];
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _trait, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final phrase in phrases)
            pw.Text(phrase,
                style: const pw.TextStyle(fontSize: 8, color: _gris)),
        ],
      ),
    );
  }

  static pw.Widget _ligne(String libelle, String valeur, {bool fort = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
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

  /// Deux lignes à signer.
  ///
  /// C'est ce qui distingue un journal de caisse d'un écran : le papier
  /// engage celui qui a compté, et c'est ce qu'on ressort le jour où
  /// l'écart se discute.
  static pw.Widget _signatures() => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          for (final role in ['Le caissier', 'Le responsable'])
            pw.Container(
              width: 200,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(role,
                      style: const pw.TextStyle(fontSize: 9, color: _gris)),
                  pw.SizedBox(height: 28),
                  pw.Divider(color: _trait, height: 1),
                ],
              ),
            ),
        ],
      );
}
