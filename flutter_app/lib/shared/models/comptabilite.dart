/// Ce que la comptabilité tient : une période fermée, et ce qu'elle a
/// collecté.
library;

import 'package:erp/core/money/montant.dart';

/// Un acte de clôture ou de réouverture, tel qu'il reste au dossier.
///
/// Les deux sont conservés, jamais écrasés : « qui a rouvert mars, et
/// pourquoi » est exactement la question qu'un contrôle pose, et une
/// table qui ne garderait que l'état courant ne saurait pas y répondre.
class ActeCloture {
  final int id;

  /// Le dernier jour fermé par cet acte, en `AAAA-MM-JJ`.
  final String fermeJusquau;

  /// Obligatoire sur une réouverture, libre sur une clôture.
  final String? motif;

  /// Nul pour les actes posés hors session.
  final String? auteur;

  /// L'instant de l'acte, distinct du jour qu'il ferme.
  final String? quand;

  /// Vrai quand cet acte a **reculé** la limite.
  final bool estUneReouverture;

  const ActeCloture({
    required this.id,
    required this.fermeJusquau,
    required this.estUneReouverture,
    this.motif,
    this.auteur,
    this.quand,
  });
}

/// Ce qu'un taux a collecté sur une période.
class LigneTva {
  final Taux taux;

  /// Le chiffre d'affaires TTC soumis à ce taux.
  final Montant ttc;
  final Montant baseHt;
  final Montant tva;

  const LigneTva({
    required this.taux,
    required this.ttc,
    required this.baseHt,
    required this.tva,
  });
}

/// La TVA collectée sur une période.
///
/// **Collectée seulement.** La TVA déductible se lit sur les factures
/// d'achat, que ce logiciel n'enregistre pas encore : les entrées de
/// stock ne portent ni taux ni montant de taxe. Annoncer une TVA nette
/// à payer en supposant zéro de déductible produirait un chiffre faux
/// et crédible, ce qui est la pire espèce. Le document dit donc ce
/// qu'il sait et nomme ce qu'il ne sait pas.
class DeclarationTva {
  final String du;
  final String au;

  final List<LigneTva> lignes;

  /// Le chiffre d'affaires TTC dont le taux n'est pas enregistré.
  ///
  /// Dans le total des ventes, hors de toute base : les lignes
  /// antérieures au figeage du taux ne disent rien de leur TVA, et
  /// « on ne sait pas » n'est pas « exonéré ».
  final Montant ttcSansTaux;
  final int lignesSansTaux;

  /// Les lignes vendues sans prix : hors de tout total.
  final int lignesSansPrix;

  /// Le dernier jour fermé au moment de l'édition, ou nul.
  ///
  /// Imprimé sur la déclaration : une déclaration établie sur une
  /// période encore ouverte peut être démentie par une correction le
  /// lendemain, et le lecteur doit le savoir.
  final String? fermeJusquau;

  const DeclarationTva({
    required this.du,
    required this.au,
    required this.lignes,
    required this.ttcSansTaux,
    required this.lignesSansTaux,
    required this.lignesSansPrix,
    this.fermeJusquau,
  });

  Montant get totalTtc {
    var somme = ttcSansTaux;
    for (final ligne in lignes) {
      somme = somme + ligne.ttc;
    }
    return somme;
  }

  Montant get totalHt {
    var somme = Montant(0, devise: ttcSansTaux.devise);
    for (final ligne in lignes) {
      somme = somme + ligne.baseHt;
    }
    return somme;
  }

  Montant get totalTva {
    var somme = Montant(0, devise: ttcSansTaux.devise);
    for (final ligne in lignes) {
      somme = somme + ligne.tva;
    }
    return somme;
  }

  /// Vrai quand toute la période tombe dans le fermé.
  ///
  /// C'est la seule condition dans laquelle cette déclaration ne peut
  /// plus bouger — et donc la seule dans laquelle on peut la déposer
  /// sans réserve.
  bool get periodeFermee =>
      fermeJusquau != null && au.compareTo(fermeJusquau!) <= 0;

  bool get aDesInconnues => lignesSansPrix > 0 || lignesSansTaux > 0;
}
