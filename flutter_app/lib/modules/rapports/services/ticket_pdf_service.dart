import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:socogen/shared/models/company_settings.dart';
import 'package:socogen/shared/models/vente.dart';

/// Tout ce qu'un ticket doit dire, en un objet.
///
/// Rassemblé ainsi pour qu'il parte vers l'isolat de fond en un seul
/// message, comme le rapport de transactions.
class TicketPdfRequest {
  final String numero;
  final String date;
  final String magasin;
  final CompanySettings societe;
  final List<LigneVente> lignes;

  /// Qui a encaissé. Nul hors session — la même vérité que sur le
  /// mouvement, et un ticket vaut mieux sans nom qu'avec un faux.
  final String? caissier;

  /// Le client, quand la vente en a désigné un. Un passant n'en a pas,
  /// et c'est le cas courant au comptoir.
  final String? client;

  const TicketPdfRequest({
    required this.numero,
    required this.date,
    required this.magasin,
    required this.societe,
    required this.lignes,
    this.caissier,
    this.client,
  });
}

/// Le ticket remis au client.
///
/// Au format **rouleau 80 mm** et non A4 : c'est la largeur des
/// imprimantes de caisse, et un ticket sur une feuille entière gaspille
/// autant de papier qu'il rend la lecture malaisée. La hauteur est
/// libre, donc un ticket de trente lignes sort d'un seul tenant sans
/// saut de page.
class TicketPdfService {
  /// Largeur du rouleau, marges comprises.
  ///
  /// `roll80` fait 80 mm de large et une hauteur infinie ; les marges
  /// sont réduites à 5 mm parce que sur 80 mm chaque millimètre compte.
  static const _format = PdfPageFormat(
    80 * PdfPageFormat.mm,
    double.infinity,
    marginAll: 5 * PdfPageFormat.mm,
  );

  static const _gris = PdfColor.fromInt(0xFF555555);

  static Future<Uint8List> buildInBackground(TicketPdfRequest request) =>
      compute(_buildIsolate, request);

  static Future<Uint8List> _buildIsolate(TicketPdfRequest request) =>
      build(request);

  static Future<Uint8List> build(TicketPdfRequest request) async {
    final document = pw.Document();
    final societe = request.societe;

    document.addPage(
      pw.Page(
        pageFormat: _format,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _entete(societe),
            pw.SizedBox(height: 6),
            _identite(request),
            pw.SizedBox(height: 6),
            _separateur(),
            pw.SizedBox(height: 4),
            ..._lignes(request.lignes),
            pw.SizedBox(height: 4),
            _separateur(),
            pw.SizedBox(height: 4),
            _total(request.lignes),
            pw.SizedBox(height: 10),
            _pied(request),
          ],
        ),
      ),
    );

    return document.save();
  }

  static pw.Widget _entete(CompanySettings societe) {
    // Le nom vide est possible — une installation neuve n'a pas encore
    // dit qui elle est — et vaut mieux qu'un nom emprunté à quelqu'un
    // d'autre. Le ticket se passe alors d'en-tête.
    final lignes = <String>[
      if (societe.name.isNotEmpty) societe.name,
      if (societe.address.isNotEmpty) societe.address,
      if (societe.city.isNotEmpty) societe.city,
      if (societe.phone.isNotEmpty) 'Tél. ${societe.phone}',
      if (societe.taxId.isNotEmpty) 'NIU ${societe.taxId}',
    ];
    if (lignes.isEmpty) return pw.SizedBox();
    return pw.Column(
      children: [
        pw.Text(
          lignes.first,
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center,
        ),
        for (final ligne in lignes.skip(1))
          pw.Text(
            ligne,
            style: const pw.TextStyle(fontSize: 7, color: _gris),
            textAlign: pw.TextAlign.center,
          ),
      ],
    );
  }

  static pw.Widget _identite(TicketPdfRequest request) {
    pw.Widget ligne(String gauche, String droite) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(gauche, style: const pw.TextStyle(fontSize: 7, color: _gris)),
            pw.Text(droite, style: const pw.TextStyle(fontSize: 7)),
          ],
        );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          'TICKET ${request.numero}',
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 4),
        ligne('Date', request.date),
        ligne('Point de vente', request.magasin),
        // « Non enregistré » plutôt qu'une ligne absente : un ticket qui
        // ne nomme personne et un ticket qui tait le nom se ressemblent
        // trop pour qu'on les confonde.
        ligne('Caissier', request.caissier ?? 'non enregistré'),
        if (request.client != null && request.client!.isNotEmpty)
          ligne('Client', request.client!),
      ],
    );
  }

  static pw.Widget _separateur() => pw.Container(
        height: 0.5,
        color: _gris,
      );

  static List<pw.Widget> _lignes(List<LigneVente> lignes) {
    return [
      for (final ligne in lignes)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text(
                ligne.designation,
                style: const pw.TextStyle(fontSize: 8),
                maxLines: 2,
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '${ligne.quantite} x '
                    '${ligne.prixUnitaire.formate(avecSymbole: false)}',
                    style: const pw.TextStyle(fontSize: 8, color: _gris),
                  ),
                  pw.Text(
                    ligne.total.formate(avecSymbole: false),
                    style:
                        pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        ),
    ];
  }

  static pw.Widget _total(List<LigneVente> lignes) {
    if (lignes.isEmpty) return pw.SizedBox();
    var total = lignes.first.total;
    for (final ligne in lignes.skip(1)) {
      total = total + ligne.total;
    }
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text('TOTAL',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.Text(total.formate(),
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }

  static pw.Widget _pied(TicketPdfRequest request) => pw.Column(
        children: [
          pw.Text(
            'Merci de votre visite',
            style: const pw.TextStyle(fontSize: 8),
            textAlign: pw.TextAlign.center,
          ),
          if (request.societe.website.isNotEmpty)
            pw.Text(
              request.societe.website,
              style: const pw.TextStyle(fontSize: 7, color: _gris),
              textAlign: pw.TextAlign.center,
            ),
        ],
      );
}
