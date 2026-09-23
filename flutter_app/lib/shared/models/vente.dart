/// Une vente, telle que ce logiciel la comprend.
///
/// « La vente est la sortie dans le magasin de la boutique » : il n'y a
/// donc **pas de table des ventes**. Une vente est un groupe de sorties
/// du magasin du point de vente, partageant un numéro de ticket, et
/// chacune portant le prix pratiqué.
///
/// Ce que cela évite : une table qui recopierait ce que les mouvements
/// disent déjà, et qui en divergerait à la première correction. Ce que
/// cela coûte : la vente n'a pas d'existence propre — pas de mode de
/// paiement, pas de remise globale. Ces deux-là viendront avec les
/// paiements, et ils auront alors une raison d'être ailleurs que sur la
/// ligne.
library;

import 'package:erp/core/money/montant.dart';

/// Une ligne de ticket : un article, une quantité, un prix.
class LigneVente {
  final String reference;
  final String designation;
  final int quantite;

  /// Le prix pratiqué, qui n'est pas forcément celui du catalogue.
  ///
  /// Un prix négocié est un fait de la vente, pas une anomalie : c'est
  /// pour cela qu'il est saisissable et qu'il se fige sur la ligne.
  final Montant prixUnitaire;

  const LigneVente({
    required this.reference,
    required this.designation,
    required this.quantite,
    required this.prixUnitaire,
  });

  Montant get total => prixUnitaire * quantite;
}

/// Ce qu'une vente a produit.
class ResultatVente {
  /// Le numéro qui identifie ce ticket, porté par chacune de ses lignes.
  final String numeroTicket;

  final int lignes;
  final Montant total;

  /// Les articles que cette vente a fait passer sous zéro, mesurés
  /// contre un relevé pris avant l'encaissement.
  ///
  /// Prévenir et non refuser : la marchandise est physiquement partie
  /// avec le client, et le nier ne la ramènerait pas. Mais un écart ne
  /// doit pas se découvrir trois semaines plus tard.
  final List<String> negatifs;

  const ResultatVente({
    required this.numeroTicket,
    required this.lignes,
    required this.total,
    this.negatifs = const [],
  });

  bool get aDesNegatifs => negatifs.isNotEmpty;
}
