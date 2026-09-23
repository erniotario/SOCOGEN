/// Comment l'argent est entré.
///
/// Le **crédit n'y figure pas**, et c'est le point de ce modèle : le
/// crédit n'est pas une façon de payer, c'est le fait de ne pas payer.
/// Ce qui reste dû sur un ticket est la différence entre son total et
/// la somme de ses règlements — une soustraction, pas une ligne.
library;

import 'package:erp/core/money/montant.dart';

enum ModePaiement {
  especes('especes', 'Espèces'),

  /// MTN Mobile Money, Orange Money. Le quotidien d'un commerce
  /// camerounais, souvent en complément des espèces sur le même ticket.
  mobileMoney('mobile_money', 'Mobile Money'),

  virement('virement', 'Virement'),
  cheque('cheque', 'Chèque');

  const ModePaiement(this.code, this.libelle);

  /// Valeur stockée, distincte du nom Dart pour que renommer l'un
  /// n'oblige pas à migrer l'autre.
  final String code;

  final String libelle;

  /// Un mode dont la trace se retrouve chez un tiers : c'est ce qui
  /// permet de répondre à un client qui conteste.
  bool get aUneReference => this != especes;

  /// Lit la valeur stockée. Un mode inconnu — base écrite par une
  /// version plus récente — est lu comme espèces plutôt que de faire
  /// échouer le chargement d'un écran de caisse.
  static ModePaiement depuisCode(String? code) => values.firstWhere(
        (m) => m.code == code,
        orElse: () => especes,
      );
}

class Paiement {
  final int id;

  /// Le numéro de ticket réglé.
  final String ticket;

  final ModePaiement mode;
  final Montant montant;

  /// Numéro de transaction Mobile Money, de chèque, de virement.
  final String? reference;

  final String date;

  const Paiement({
    required this.id,
    required this.ticket,
    required this.mode,
    required this.montant,
    required this.date,
    this.reference,
  });

  factory Paiement.fromMap(Map<String, Object?> map, {Devise? devise}) {
    return Paiement(
      id: map['id'] as int,
      ticket: map['ticket'] as String,
      mode: ModePaiement.depuisCode(map['mode'] as String?),
      montant: Montant(
        (map['montant'] as num).toInt(),
        devise: devise ?? Devise.xaf,
      ),
      reference: map['reference'] as String?,
      date: map['date'] as String,
    );
  }
}

/// L'état d'un ticket vis-à-vis de l'argent.
class SoldeTicket {
  final Montant total;
  final Montant regle;

  const SoldeTicket({required this.total, required this.regle});

  /// Ce qui reste dû. Jamais négatif : un trop-perçu est de la monnaie
  /// à rendre, pas une dette de l'entreprise envers le client.
  Montant get reste {
    final difference = total - regle;
    return difference.estNegatif ? Montant(0, devise: total.devise) : difference;
  }

  /// La monnaie à rendre, quand le client a donné plus que le dû.
  Montant get rendu {
    final difference = regle - total;
    return difference.estNegatif ? Montant(0, devise: total.devise) : difference;
  }

  bool get estRegle => !reste.estPositif;
}
