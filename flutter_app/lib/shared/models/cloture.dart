/// La clôture de caisse d'une journée.
///
/// Ce qu'un commerçant fait le soir avant de compter son tiroir. Le
/// modèle tient **deux chiffres distincts** que tout le monde confond,
/// et les confondre est la raison pour laquelle une caisse ne tombe
/// jamais juste :
///
///   * ce qui a été **vendu** aujourd'hui — le chiffre d'affaires, qui
///     comprend ce qui est parti à crédit et n'est donc pas dans le
///     tiroir ;
///   * ce qui a été **encaissé** aujourd'hui — ce qui est dans le
///     tiroir, qui comprend des règlements de tickets d'il y a trois
///     semaines et n'est donc pas le chiffre d'affaires.
///
/// Les deux sont donnés côte à côte, et l'écart entre eux est nommé
/// plutôt que laissé à deviner.
library;

import 'package:erp/core/money/montant.dart';
import 'package:erp/shared/models/facture.dart';
import 'package:erp/shared/models/paiement.dart';

/// Ce qu'un mode de règlement a rapporté dans la journée.
class EncaisseParMode {
  final ModePaiement mode;
  final Montant montant;
  final int operations;

  const EncaisseParMode({
    required this.mode,
    required this.montant,
    required this.operations,
  });
}

class ClotureCaisse {
  /// Le jour clôturé, en `AAAA-MM-JJ`.
  final String date;

  /// Le magasin, ou nul quand la clôture porte sur tous.
  final String? magasin;

  // --- Ce qui a été vendu -------------------------------------------

  /// Le nombre de tickets distincts de la journée.
  final int tickets;

  /// Le total TTC vendu dans la journée.
  final Montant ventesTtc;

  /// La TVA collectée, par taux, sur les ventes de la journée.
  final List<VentilationTva> tva;

  /// Les lignes vendues sans prix enregistré.
  ///
  /// Comptées à part, jamais à zéro : un prix absent n'est pas un prix
  /// nul, et les additionner comme tels ferait passer « on ne sait
  /// pas » pour « ça n'a rien rapporté ».
  final int lignesSansPrix;

  /// Le TTC vendu dont le taux de TVA n'est pas connu.
  final Montant ttcSansTaux;

  /// Ce qui est parti à crédit aujourd'hui : vendu et pas encore réglé.
  final Montant creditAccorde;

  // --- Ce qui est entré dans le tiroir --------------------------------

  final List<EncaisseParMode> encaisse;

  /// La part des encaissements qui règle des ventes du jour.
  final Montant encaisseDuJour;

  /// La part qui règle des ventes antérieures — du recouvrement, pas
  /// du chiffre d'affaires.
  final Montant encaisseSurCreances;

  const ClotureCaisse({
    required this.date,
    required this.tickets,
    required this.ventesTtc,
    required this.tva,
    required this.lignesSansPrix,
    required this.ttcSansTaux,
    required this.creditAccorde,
    required this.encaisse,
    required this.encaisseDuJour,
    required this.encaisseSurCreances,
    this.magasin,
  });

  Montant get encaisseTotal {
    var somme = Montant(0, devise: ventesTtc.devise);
    for (final ligne in encaisse) {
      somme = somme + ligne.montant;
    }
    return somme;
  }

  /// Ce que le tiroir doit contenir en billets.
  ///
  /// Seules les espèces se comptent à la main ; le Mobile Money et les
  /// virements se vérifient chez l'opérateur ou à la banque, et les
  /// mêler au fond de caisse rend l'écart introuvable.
  Montant get especes =>
      encaisse
          .where((l) => l.mode == ModePaiement.especes)
          .fold(Montant(0, devise: ventesTtc.devise), (t, l) => t + l.montant);

  Montant get totalTva {
    var somme = Montant(0, devise: ventesTtc.devise);
    for (final bloc in tva) {
      somme = somme + bloc.tva;
    }
    return somme;
  }

  bool get estVide => tickets == 0 && encaisseTotal.estZero;

  /// Vrai quand une partie du chiffre n'a pas pu être ventilée.
  bool get aDesInconnues => lignesSansPrix > 0 || ttcSansTaux.estPositif;
}
