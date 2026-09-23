import 'package:sqflite/sqflite.dart';

import 'package:socogen/core/db/database_service.dart';
import 'package:socogen/core/db/sync_columns.dart';
import 'package:socogen/core/errors/messages.dart';
import 'package:socogen/core/money/montant.dart';
import 'package:socogen/modules/parametres/services/parametres_service.dart';
import 'package:socogen/shared/models/paiement.dart';

/// Ce qui a été payé, et ce qui reste dû.
///
/// Le solde d'un ticket **se calcule, il ne se stocke pas** : total des
/// lignes moins somme des règlements. Un solde stocké diverge du jour où
/// une ligne est corrigée dans Transactions, et personne ne s'en aperçoit
/// avant l'inventaire de caisse.
class PaiementService {
  PaiementService({
    Database? database,
    ParametresService? parametresService,
  })  : _injectedDb = database,
        _parametres = parametresService ?? ParametresService();

  final Database? _injectedDb;
  final ParametresService _parametres;

  Future<Database> get _db async =>
      _injectedDb ?? DatabaseService.instance.database;

  /// Enregistre un règlement sur un ticket.
  ///
  /// Ce qui est refusé : un montant **nul ou négatif** — un
  /// remboursement est un avoir, pas un paiement à l'envers — et un
  /// mode à référence (Mobile Money, chèque, virement) **sans
  /// référence**, parce que c'est précisément la trace qui permet de
  /// retrouver l'argent quand un client conteste.
  ///
  /// Ce qui n'est **pas** refusé : payer plus que le dû. Le client tend
  /// un billet de 10 000 pour 8 500 ; c'est à la caisse de rendre la
  /// monnaie, pas au logiciel de refuser le billet.
  Future<void> regler({
    required String ticket,
    required ModePaiement mode,
    required Montant montant,
    String? reference,
    DateTime? le,
  }) async {
    if (!montant.estPositif) {
      throw const ErreurUtilisateur(
        'Le montant réglé doit être supérieur à 0.',
      );
    }
    if (mode.aUneReference && (reference == null || reference.trim().isEmpty)) {
      throw ErreurUtilisateur(
        'Un règlement par ${mode.libelle.toLowerCase()} demande son '
        'numéro de transaction.',
      );
    }

    final db = await _db;
    await db.insert('paiements', {
      'ticket': ticket,
      'mode': mode.code,
      'montant': montant.unites,
      'reference': reference?.trim(),
      'date': _iso(le ?? DateTime.now()),
      'sync_id': newSyncId(),
      'updated_at': nowIso(),
      ...attribution(),
    });
  }

  /// L'état d'un ticket : ce qu'il vaut, ce qui a été versé.
  Future<SoldeTicket> solde(String ticket) async {
    final db = await _db;
    final devise = await _parametres.devise();

    final total = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COALESCE(SUM(quantity * COALESCE(prix_unitaire, 0)), 0) '
          'FROM stock_outputs WHERE invoice_number = ?',
          [ticket],
        )) ??
        0;
    final regle = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COALESCE(SUM(montant), 0) FROM paiements WHERE ticket = ?',
          [ticket],
        )) ??
        0;

    return SoldeTicket(
      total: Montant(total, devise: devise),
      regle: Montant(regle, devise: devise),
    );
  }

  Future<List<Paiement>> reglementsDe(String ticket) async {
    final db = await _db;
    final devise = await _parametres.devise();
    final rows = await db.query('paiements',
        where: 'ticket = ?', whereArgs: [ticket], orderBy: 'id');
    return rows.map((r) => Paiement.fromMap(r, devise: devise)).toList();
  }

  /// Ce qu'un client doit, tous tickets confondus.
  ///
  /// La somme des tickets qui lui sont rattachés, moins ce qui a été
  /// versé dessus. C'est l'encours que le plafond de crédit borne.
  ///
  /// Les tickets sont retrouvés par `tiers_id` sur leurs lignes, et non
  /// par le texte de la destination : une fiche renommée ou fusionnée
  /// doit continuer de porter ses dettes.
  Future<Montant> encoursDe(int tiersId) async {
    final db = await _db;
    final devise = await _parametres.devise();
    final row = (await db.rawQuery('''
      SELECT
        COALESCE((
          SELECT SUM(o.quantity * COALESCE(o.prix_unitaire, 0))
          FROM stock_outputs o
          WHERE o.tiers_id = ? AND o.invoice_number <> ''
        ), 0) AS du,
        COALESCE((
          SELECT SUM(p.montant) FROM paiements p
          WHERE p.ticket IN (
            SELECT DISTINCT invoice_number FROM stock_outputs
            WHERE tiers_id = ? AND invoice_number <> ''
          )
        ), 0) AS verse
    ''', [tiersId, tiersId]))
        .first;

    final encours =
        (row['du'] as num).toInt() - (row['verse'] as num).toInt();
    return Montant(encours < 0 ? 0 : encours, devise: devise);
  }

  /// Dit si une nouvelle dette tiendrait dans le plafond d'un client.
  ///
  /// Rend null quand elle tient — ou qu'il n'y a pas de plafond, ce qui
  /// n'est pas la même chose qu'un plafond à zéro. Sinon, la phrase à
  /// montrer, qui nomme les trois nombres : ce qui est déjà dû, ce qu'on
  /// ajoute, et la limite. Un refus qui ne dit pas de combien on dépasse
  /// n'aide personne à décider.
  Future<String?> depassementDePlafond({
    required int tiersId,
    required Montant? plafond,
    required Montant aCrediter,
  }) async {
    if (plafond == null || !aCrediter.estPositif) return null;
    final encours = await encoursDe(tiersId);
    final apres = encours + aCrediter;
    if (!(apres > plafond)) return null;
    return 'Plafond de crédit dépassé : ${encours.formate()} déjà dus, '
        '${aCrediter.formate()} de plus, pour un plafond de '
        '${plafond.formate()}.';
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
