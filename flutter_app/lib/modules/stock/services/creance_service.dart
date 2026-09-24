import 'package:sqflite/sqflite.dart';

import 'package:erp/core/db/database_service.dart';
import 'package:erp/core/money/montant.dart';
import 'package:erp/modules/parametres/services/parametres_service.dart';
import 'package:erp/shared/models/creance.dart';

/// Qui doit de l'argent à la maison, combien, et depuis quand.
///
/// Tout est **calculé**, rien n'est stocké : l'encours d'un client est
/// la somme des restes de ses tickets, et le reste d'un ticket est son
/// total moins ses règlements. Un encours rangé en base diverge le jour
/// où une ligne est corrigée dans Transactions, et l'écart se découvre
/// en allant relancer quelqu'un qui a déjà payé.
///
/// Une requête, une seule, pour toute la liste : le même écran a déjà
/// coûté trois secondes ailleurs dans ce projet à force de sous-requêtes
/// par ligne.
class CreanceService {
  CreanceService({
    Database? database,
    ParametresService? parametresService,
  })  : _injectedDb = database,
        _parametres = parametresService ?? ParametresService();

  final Database? _injectedDb;
  final ParametresService _parametres;

  Future<Database> get _db async =>
      _injectedDb ?? DatabaseService.instance.database;

  /// L'état des créances arrêté à [au] (aujourd'hui par défaut).
  ///
  /// La date d'arrêté est ce qui donne leur âge aux créances. La passer
  /// plutôt que d'appeler `DateTime.now()` au fond du calcul permet de
  /// rééditer l'état du 31 du mois dernier et de retrouver les mêmes
  /// tranches.
  Future<EtatCreances> etat({DateTime? au}) async {
    final db = await _db;
    final devise = await _parametres.devise();
    final zero = Montant(0, devise: devise);
    final reference = _jour(au ?? DateTime.now());

    // Un ticket par ligne de résultat : total vendu, total réglé, et la
    // fiche du client quand la vente en désigne une. Les transferts
    // sont exclus — la marchandise n'a pas quitté l'entreprise, donc
    // personne ne doit rien.
    final rows = await db.rawQuery('''
      SELECT s.invoice_number                              AS ticket,
             MIN(substr(s.date, 1, 10))                    AS date,
             SUM(s.quantity * COALESCE(s.prix_unitaire, 0)) AS total,
             MAX(s.tiers_id)                               AS tiers_id,
             t.code                                        AS code,
             t.nom                                         AS nom,
             t.telephone                                   AS telephone,
             t.plafond_credit                              AS plafond,
             COALESCE(p.regle, 0)                          AS regle
        FROM stock_outputs s
        LEFT JOIN tiers t ON t.id = s.tiers_id
        LEFT JOIN (SELECT ticket, SUM(montant) AS regle
                     FROM paiements GROUP BY ticket) p
               ON p.ticket = s.invoice_number
       WHERE TRIM(COALESCE(s.invoice_number, '')) <> ''
         AND s.transfert_id IS NULL
       GROUP BY s.invoice_number
      HAVING total > COALESCE(p.regle, 0)
    ''');

    final parClient = <int, List<TicketDu>>{};
    final fiches = <int, Map<String, Object?>>{};
    var sansClient = zero;
    var ticketsSansClient = 0;
    var ticketsSansDate = 0;

    for (final row in rows) {
      final total = Montant((row['total'] as num).toInt(), devise: devise);
      final regle = Montant((row['regle'] as num).toInt(), devise: devise);
      final date = (row['date'] as String?) ?? '';
      final vendu = DateTime.tryParse(date);
      if (vendu == null) ticketsSansDate++;

      final tiersId = row['tiers_id'] as int?;
      if (tiersId == null) {
        // On ne relance pas un passant : sa dette est comptée à part
        // plutôt que versée à un total qu'on croirait recouvrable.
        sansClient = sansClient + (total - regle);
        ticketsSansClient++;
        continue;
      }

      fiches[tiersId] = row;
      (parClient[tiersId] ??= []).add(TicketDu(
        ticket: row['ticket'] as String,
        date: date,
        total: total,
        regle: regle,
        jours: vendu == null ? null : reference.difference(vendu).inDays,
      ));
    }

    final clients = <CreanceClient>[];
    parClient.forEach((tiersId, tickets) {
      var encours = zero;
      for (final ticket in tickets) {
        encours = encours + ticket.reste;
      }
      final fiche = fiches[tiersId]!;
      final plafond = fiche['plafond'] as int?;
      tickets.sort((a, b) => a.date.compareTo(b.date));
      clients.add(CreanceClient(
        tiersId: tiersId,
        code: (fiche['code'] as String?) ?? '',
        nom: (fiche['nom'] as String?) ?? '',
        telephone: fiche['telephone'] as String?,
        tickets: tickets,
        encours: encours,
        plafond: plafond == null ? null : Montant(plafond, devise: devise),
      ));
    });

    // Du plus gros encours au plus petit : c'est l'ordre dans lequel on
    // décroche le téléphone.
    clients.sort((a, b) => b.encours.compareTo(a.encours));

    return EtatCreances(
      arreteAu: _iso(reference),
      clients: clients,
      sansClient: sansClient,
      ticketsSansClient: ticketsSansClient,
      ticketsSansDate: ticketsSansDate,
    );
  }

  /// Minuit du jour donné.
  ///
  /// L'heure ferait qu'une créance du matin et une du soir n'auraient
  /// pas le même âge en jours, ce qui déplacerait des lignes d'une
  /// tranche à l'autre selon l'heure d'impression.
  static DateTime _jour(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
