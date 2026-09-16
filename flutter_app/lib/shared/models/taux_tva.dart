import 'package:socogen/core/money/montant.dart';

/// Un taux de TVA tel que l'entreprise l'applique.
///
/// Le module paramètres en est **propriétaire** — c'est lui qui les lit,
/// les écrit et décide lequel s'applique par défaut. Mais leur *forme*
/// est du vocabulaire partagé : le catalogue en affiche la liste, les
/// ventes ventileront une facture dessus, la comptabilité y accrochera
/// un compte. D'où ce fichier ici plutôt que dans le module : la
/// possession reste à `parametres`, la définition est commune.
///
/// C'est le test d'architecture qui a imposé ce découpage, en refusant
/// que l'écran Produits atteigne l'intérieur des paramètres.
///
/// Le taux est stocké en dix-millièmes, comme [Taux], pour que 19,25 %
/// reste exact — voir `core/money` pour la raison.
class TauxTva {
  final int id;

  /// Code stable — NORMAL, EXONERE. C'est lui qui sera repris dans les
  /// exports et, le jour venu, dans le plan comptable.
  final String code;

  /// Ce que lit l'utilisateur : « TVA 19,25 % ».
  final String libelle;

  /// Le taux en dix-millièmes : 1925 pour 19,25 %.
  final int pourDixMille;

  /// Le taux proposé par défaut à la création d'un article.
  final bool estDefaut;

  const TauxTva({
    required this.id,
    required this.code,
    required this.libelle,
    required this.pourDixMille,
    this.estDefaut = false,
  });

  /// Le taux sous la forme que manipule `core/money`.
  Taux get taux => Taux(pourDixMille);

  /// Un taux à zéro n'est pas l'absence de taux : un produit exonéré est
  /// taxé à 0 %, ce qui doit apparaître sur la facture.
  bool get estExonere => pourDixMille == 0;

  factory TauxTva.fromMap(Map<String, Object?> map) {
    return TauxTva(
      id: map['id'] as int,
      code: map['code'] as String,
      libelle: map['libelle'] as String,
      pourDixMille: (map['pour_dix_mille'] as num).toInt(),
      estDefaut: ((map['is_defaut'] as int?) ?? 0) == 1,
    );
  }

  Map<String, Object?> toMap({bool includeId = true}) {
    return {
      if (includeId) 'id': id,
      'code': code,
      'libelle': libelle,
      'pour_dix_mille': pourDixMille,
      'is_defaut': estDefaut ? 1 : 0,
    };
  }

  TauxTva copyWith({
    int? id,
    String? code,
    String? libelle,
    int? pourDixMille,
    bool? estDefaut,
  }) {
    return TauxTva(
      id: id ?? this.id,
      code: code ?? this.code,
      libelle: libelle ?? this.libelle,
      pourDixMille: pourDixMille ?? this.pourDixMille,
      estDefaut: estDefaut ?? this.estDefaut,
    );
  }
}
