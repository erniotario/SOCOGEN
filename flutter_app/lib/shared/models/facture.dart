/// La facture d'une vente.
///
/// Une facture n'est **pas une opération** : c'est une seconde lecture
/// d'une vente déjà écrite, sur A4 au lieu du rouleau de caisse. Elle ne
/// crée rien, ne numérote rien de neuf, et se relit des mouvements comme
/// le ticket — si le papier et le registre divergeaient, c'est le papier
/// qui aurait tort et personne ne le saurait.
///
/// Ce qu'elle ajoute au ticket, c'est la ventilation de la TVA, qu'une
/// entreprise cliente doit trouver sur sa pièce justificative. Les prix
/// pratiqués sont TTC — c'est ainsi qu'on affiche au Cameroun — donc le
/// HT se retrouve en divisant par 1 + taux, jamais en retirant le taux.
library;

import 'package:erp/core/money/montant.dart';

/// Une ligne de facture : ce que le mouvement a figé, taux compris.
class LigneFacture {
  final String reference;
  final String designation;
  final int quantite;

  /// Le prix pratiqué, TTC, tel qu'il a été figé à la vente.
  final Montant prixUnitaire;

  /// Le taux appliqué ce jour-là, ou nul quand la ligne n'en porte pas.
  ///
  /// Nul n'est pas zéro : les lignes antérieures au figeage du taux ne
  /// disent rien de leur TVA, et une facture doit l'annoncer plutôt que
  /// de ventiler une taxe de zéro qu'elle aurait inventée.
  final Taux? taux;

  const LigneFacture({
    required this.reference,
    required this.designation,
    required this.quantite,
    required this.prixUnitaire,
    this.taux,
  });

  Montant get totalTtc => prixUnitaire * quantite;

  /// Le hors-taxe de cette ligne, ou nul si le taux est inconnu.
  Montant? get totalHt => taux == null ? null : totalTtc.horsTaxe(taux!);

  /// La TVA de cette ligne, ou nul si le taux est inconnu.
  Montant? get montantTva {
    final ht = totalHt;
    return ht == null ? null : totalTtc - ht;
  }
}

/// Ce qu'un taux a représenté sur cette facture.
///
/// Un bloc par taux rencontré, parce qu'un panier peut mêler du 19,25 %
/// et de l'exonéré, et qu'une facture qui n'annonce qu'un total de TVA
/// ne permet pas de la contrôler.
class VentilationTva {
  final Taux taux;
  final Montant baseHt;
  final Montant tva;

  const VentilationTva({
    required this.taux,
    required this.baseHt,
    required this.tva,
  });

  Montant get ttc => baseHt + tva;
}

/// La facture complète, prête à imprimer.
class Facture {
  /// Le numéro du ticket, qui est aussi celui de la facture.
  ///
  /// Une vente est un événement ; lui donner un second numéro parce
  /// qu'on la réimprime sur un autre format créerait deux identités
  /// pour un seul fait, et la question « laquelle est la bonne ? » se
  /// poserait au premier litige.
  final String numero;

  final String date;
  final String magasin;
  final String? client;
  final String? caissier;

  final List<LigneFacture> lignes;

  /// Un bloc par taux connu, du plus élevé au plus bas.
  final List<VentilationTva> ventilation;

  final Montant totalTtc;

  /// Ce qui a été réglé et ce qui reste dû, au moment de l'impression.
  final Montant regle;
  final Montant reste;

  const Facture({
    required this.numero,
    required this.date,
    required this.magasin,
    required this.lignes,
    required this.ventilation,
    required this.totalTtc,
    required this.regle,
    required this.reste,
    this.client,
    this.caissier,
  });

  /// Les lignes dont le taux est inconnu : leur TTC compte dans le
  /// total, jamais dans la ventilation.
  Iterable<LigneFacture> get lignesSansTaux =>
      lignes.where((l) => l.taux == null);

  /// Le TTC que cette facture ne sait pas ventiler.
  ///
  /// Nommé plutôt que fondu dans le total : une facture qui ventile la
  /// moitié de son montant sans le dire laisse croire que le reste est
  /// exonéré.
  Montant get ttcSansTaux {
    var somme = Montant(0, devise: totalTtc.devise);
    for (final ligne in lignesSansTaux) {
      somme = somme + ligne.totalTtc;
    }
    return somme;
  }

  bool get estVentilable => lignesSansTaux.isEmpty;

  Montant get totalHt {
    var somme = Montant(0, devise: totalTtc.devise);
    for (final bloc in ventilation) {
      somme = somme + bloc.baseHt;
    }
    return somme;
  }

  Montant get totalTva {
    var somme = Montant(0, devise: totalTtc.devise);
    for (final bloc in ventilation) {
      somme = somme + bloc.tva;
    }
    return somme;
  }

  bool get estReglee => !reste.estPositif;
}
