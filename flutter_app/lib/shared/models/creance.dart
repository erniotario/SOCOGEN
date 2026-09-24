/// Ce que les clients doivent, et depuis combien de temps.
///
/// Rien n'est stocké : une créance est la soustraction entre ce qu'un
/// ticket a vendu et ce qui a été réglé dessus, exactement comme le
/// solde d'un ticket. Un encours rangé en base diverge le jour où une
/// ligne est corrigée dans Transactions, et personne ne s'en aperçoit
/// avant d'aller relancer quelqu'un qui a déjà payé.
///
/// L'âge d'une créance compte autant que son montant : 200 000 francs
/// dus depuis quatre mois et 200 000 dus depuis huit jours ne sont pas
/// la même affaire, et une liste triée sur le seul montant ne le dit
/// pas.
library;

import 'package:erp/core/money/montant.dart';

/// Depuis combien de temps une somme est due.
enum TrancheAge {
  courant('0 à 30 jours'),
  unMois('31 à 60 jours'),
  deuxMois('61 à 90 jours'),
  ancien('Plus de 90 jours');

  const TrancheAge(this.libelle);

  final String libelle;

  /// La tranche d'une créance vieille de [jours].
  static TrancheAge pour(int jours) {
    if (jours <= 30) return courant;
    if (jours <= 60) return unMois;
    if (jours <= 90) return deuxMois;
    return ancien;
  }
}

/// Un ticket qui n'est pas soldé.
class TicketDu {
  final String ticket;
  final String date;
  final Montant total;
  final Montant regle;

  /// Nul quand la date du ticket n'est pas lisible.
  ///
  /// Nul n'est pas zéro : une date illisible ne rend pas la créance
  /// fraîche. Le ticket compte dans l'encours et reste hors des
  /// tranches, qui le disent.
  final int? jours;

  const TicketDu({
    required this.ticket,
    required this.date,
    required this.total,
    required this.regle,
    this.jours,
  });

  Montant get reste => total - regle;

  TrancheAge? get tranche => jours == null ? null : TrancheAge.pour(jours!);
}

/// Ce qu'un client doit, tous tickets confondus.
class CreanceClient {
  final int tiersId;
  final String code;
  final String nom;
  final String? telephone;

  final List<TicketDu> tickets;
  final Montant encours;

  /// Le plafond accordé, ou nul quand il n'y en a pas.
  ///
  /// Pas de plafond n'est pas un plafond à zéro : zéro interdit tout
  /// crédit, et c'est une décision.
  final Montant? plafond;

  const CreanceClient({
    required this.tiersId,
    required this.code,
    required this.nom,
    required this.tickets,
    required this.encours,
    this.telephone,
    this.plafond,
  });

  /// L'âge de la plus vieille créance, ou nul si aucune n'a de date
  /// lisible.
  int? get joursMax {
    int? plus;
    for (final t in tickets) {
      final j = t.jours;
      if (j == null) continue;
      if (plus == null || j > plus) plus = j;
    }
    return plus;
  }

  Montant parTranche(TrancheAge tranche) {
    var somme = Montant(0, devise: encours.devise);
    for (final t in tickets) {
      if (t.tranche == tranche) somme = somme + t.reste;
    }
    return somme;
  }

  bool get depassePlafond =>
      plafond != null && encours.compareTo(plafond!) > 0;

  Montant get depassement =>
      depassePlafond ? encours - plafond! : Montant(0, devise: encours.devise);
}

/// L'état des créances à une date donnée.
class EtatCreances {
  /// La date d'arrêté : c'est d'elle que se comptent les jours.
  final String arreteAu;

  /// Les clients qui doivent quelque chose, du plus gros encours au
  /// plus petit.
  final List<CreanceClient> clients;

  /// Ce qui reste dû sur des ventes **sans client identifié**.
  ///
  /// Compté à part et jamais fondu dans le total : on ne relance pas un
  /// passant. Cette somme dit ce que la maison a laissé partir sans
  /// savoir à qui, et c'est une information sur la tenue de la caisse
  /// plus que sur une dette.
  final Montant sansClient;
  final int ticketsSansClient;

  /// Les tickets dont la date n'est pas lisible : dans l'encours, hors
  /// des tranches.
  final int ticketsSansDate;

  const EtatCreances({
    required this.arreteAu,
    required this.clients,
    required this.sansClient,
    required this.ticketsSansClient,
    required this.ticketsSansDate,
  });

  Montant get total {
    var somme = clients.isEmpty
        ? const Montant(0)
        : Montant(0, devise: clients.first.encours.devise);
    for (final client in clients) {
      somme = somme + client.encours;
    }
    return somme;
  }

  Montant parTranche(TrancheAge tranche) {
    var somme = Montant(0, devise: total.devise);
    for (final client in clients) {
      somme = somme + client.parTranche(tranche);
    }
    return somme;
  }

  Iterable<CreanceClient> get auDessusDuPlafond =>
      clients.where((c) => c.depassePlafond);

  bool get estVide => clients.isEmpty && sansClient.estZero;

  bool get aDesReserves => ticketsSansClient > 0 || ticketsSansDate > 0;
}
