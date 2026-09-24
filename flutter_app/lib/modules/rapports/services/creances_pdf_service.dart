import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:erp/shared/models/company_settings.dart';
import 'package:erp/shared/models/creance.dart';

class CreancesPdfRequest {
  final EtatCreances etat;
  final CompanySettings societe;

  const CreancesPdfRequest({required this.etat, required this.societe});
}

/// La balance âgée des clients.
///
/// Le document qu'on emporte pour relancer : un client par ligne, son
/// encours réparti par ancienneté, et le téléphone à côté du nom pour
/// n'avoir pas à rouvrir une fiche entre deux appels.
///
/// L'âge est une colonne et non une note de bas de page : 200 000 dus
/// depuis quatre mois et 200 000 dus depuis huit jours ne se traitent
/// pas pareil, et une liste triée sur le seul montant ne le dit pas.
class CreancesPdfService {
  static const _gris = PdfColor.fromInt(0xFF555555);
  static const _trait = PdfColor.fromInt(0xFFBBBBBB);
  static const _alerte = PdfColor.fromInt(0xFFB42318);

  /// Lignes par tableau.
  ///
  /// Un tableau qui traverse plusieurs pages est remis en page une fois
  /// par page traversée ; le découper en morceaux de la taille d'une
  /// page évite ce coût, déjà mesuré sur le rapport de transactions.
  static const int _parPage = 26;

  static Future<Uint8List> buildInBackground(CreancesPdfRequest request) =>
      compute(_buildIsolate, request);

  static Future<Uint8List> _buildIsolate(CreancesPdfRequest request) =>
      build(request);

  static Future<Uint8List> build(CreancesPdfRequest request) async {
    final document = pw.Document();
    final etat = request.etat;
    final morceaux = <List<CreanceClient>>[];
    for (var i = 0; i < etat.clients.length; i += _parPage) {
      morceaux.add(etat.clients.sublist(
        i,
        i + _parPage > etat.clients.length ? etat.clients.length : i + _parPage,
      ));
    }

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 24),
        maxPages: 80,
        header: (context) => context.pageNumber == 1
            ? pw.SizedBox()
            : _rappel(etat, context.pageNumber),
        footer: (context) => _pied(context),
        build: (context) => [
          _entete(request),
          pw.SizedBox(height: 16),
          if (etat.clients.isEmpty)
            pw.Text('Aucune créance en cours à cette date.',
                style: const pw.TextStyle(fontSize: 11, color: _gris))
          else ...[
            for (final morceau in morceaux) ...[
              _tableau(morceau, entete: morceau == morceaux.first),
              pw.SizedBox(height: 4),
            ],
            pw.SizedBox(height: 6),
            _totaux(etat),
          ],
          if (etat.auDessusDuPlafond.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            _plafonds(etat),
          ],
          if (etat.aDesReserves) ...[
            pw.SizedBox(height: 14),
            _reserves(etat),
          ],
        ],
      ),
    );

    return document.save();
  }

  static pw.Widget _entete(CreancesPdfRequest request) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(request.societe.name,
              style:
                  pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          pw.Text('ÉTAT DES CRÉANCES CLIENTS',
              style:
                  pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.Text(
            'Arrêté au ${request.etat.arreteAu}'
            '  ·  ${request.etat.clients.length} client(s)',
            style: const pw.TextStyle(fontSize: 10, color: _gris),
          ),
        ],
      );

  static pw.Widget _rappel(EtatCreances etat, int page) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Text(
          'Créances clients au ${etat.arreteAu}, suite (page $page)',
          style: const pw.TextStyle(fontSize: 9, color: _gris),
        ),
      );

  static const _largeurs = {
    0: pw.FlexColumnWidth(3.4),
    1: pw.FlexColumnWidth(1.8),
    2: pw.FlexColumnWidth(1.5),
    3: pw.FlexColumnWidth(1.5),
    4: pw.FlexColumnWidth(1.5),
    5: pw.FlexColumnWidth(1.5),
    6: pw.FlexColumnWidth(1.8),
  };

  static pw.Widget _tableau(List<CreanceClient> clients,
      {required bool entete}) {
    final titre = pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold);
    const cellule = pw.TextStyle(fontSize: 8.5);

    return pw.Table(
      border: pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _trait, width: 0.4),
        bottom: pw.BorderSide(color: _trait, width: 0.4),
      ),
      columnWidths: _largeurs,
      children: [
        if (entete)
          pw.TableRow(
            decoration:
                const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEFEFEF)),
            children: [
              _cell('CLIENT', titre),
              _cell('TÉLÉPHONE', titre),
              _cell('0-30 J', titre, droite: true),
              _cell('31-60 J', titre, droite: true),
              _cell('61-90 J', titre, droite: true),
              _cell('+90 J', titre, droite: true),
              _cell('TOTAL DÛ', titre, droite: true),
            ],
          ),
        for (final client in clients)
          pw.TableRow(
            children: [
              _cell(
                // Le point d'exclamation marque un dépassement de
                // plafond ; le détail est repris sous le tableau.
                client.depassePlafond ? '! ${client.nom}' : client.nom,
                client.depassePlafond
                    ? cellule.copyWith(color: _alerte)
                    : cellule,
              ),
              _cell(client.telephone ?? '', cellule),
              _cell(_ou(client, TrancheAge.courant), cellule, droite: true),
              _cell(_ou(client, TrancheAge.unMois), cellule, droite: true),
              _cell(_ou(client, TrancheAge.deuxMois), cellule, droite: true),
              _cell(_ou(client, TrancheAge.ancien), cellule, droite: true),
              _cell(client.encours.formate(avecSymbole: false),
                  cellule.copyWith(fontWeight: pw.FontWeight.bold),
                  droite: true),
            ],
          ),
      ],
    );
  }

  /// Une tranche vide s'écrit vide et non zéro : la colonne se lit
  /// d'un coup d'œil quand seules les cases qui portent quelque chose
  /// sont remplies.
  static String _ou(CreanceClient client, TrancheAge tranche) {
    final montant = client.parTranche(tranche);
    return montant.estZero ? '' : montant.formate(avecSymbole: false);
  }

  static pw.Widget _totaux(EtatCreances etat) => pw.Table(
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
                  pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              _cell('', const pw.TextStyle()),
              for (final tranche in TrancheAge.values)
                _cell(
                  etat.parTranche(tranche).formate(avecSymbole: false),
                  pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                  droite: true,
                ),
              _cell(etat.total.formate(),
                  pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                  droite: true),
            ],
          ),
        ],
      );

  static pw.Widget _plafonds(EtatCreances etat) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('AU-DESSUS DU PLAFOND ACCORDÉ',
              style: pw.TextStyle(
                  fontSize: 8.5,
                  color: _alerte,
                  fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          for (final client in etat.auDessusDuPlafond)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 1),
              child: pw.Text(
                // Les trois nombres, pas seulement le refus : un
                // dépassement qui ne dit pas de combien n'aide personne
                // à décider.
                '${client.nom} : ${client.encours.formate()} dû pour un '
                'plafond de ${client.plafond!.formate()}, soit '
                '${client.depassement.formate()} de trop.',
                style: const pw.TextStyle(fontSize: 8.5),
              ),
            ),
        ],
      );

  /// Ce que l'état ne sait pas dire.
  ///
  /// Se taire présenterait un total partiel comme complet, sur le
  /// document même qui sert à décider qui on appelle demain.
  static pw.Widget _reserves(EtatCreances etat) {
    final phrases = <String>[
      if (etat.ticketsSansClient > 0)
        '${etat.ticketsSansClient} ticket(s) impayé(s) sans fiche client, '
            'soit ${etat.sansClient.formate()} : personne à relancer, ces '
            'sommes ne sont pas dans le total ci-dessus.',
      if (etat.ticketsSansDate > 0)
        '${etat.ticketsSansDate} ticket(s) sans date lisible : comptés dans '
            'le total, absents des colonnes d\'ancienneté.',
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

  static pw.Widget _cell(String texte, pw.TextStyle style,
          {bool droite = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3.5),
        child: pw.Text(
          texte,
          style: style,
          textAlign: droite ? pw.TextAlign.right : pw.TextAlign.left,
        ),
      );

  static pw.Widget _pied(pw.Context context) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8),
        child: pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Page ${context.pageNumber}/${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: _gris)),
        ),
      );
}
