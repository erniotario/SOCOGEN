/// Un article du catalogue.
///
/// Les prix sont des **entiers d'unités minimales** de la devise de
/// l'entreprise, pas des [Montant] : la devise est un fait de la société,
/// pas de l'article, et la porter ici obligerait chaque lecture en base à
/// connaître les paramètres. La conversion se fait à la frontière des
/// services, qui savent quelle devise l'entreprise utilise.
///
/// Un prix `null` n'est pas un prix à zéro. Les articles importés de Sage
/// n'ont pas de prix : zéro voudrait dire « gratuit », null dit « on ne
/// sait pas ». C'est la même distinction qu'entre un stock nul et un
/// stock négatif, et elle se perd si on la laisse filer une fois.
class Product {
  final int id;
  final String reference;
  final String designation;
  final String unit;

  /// La famille, ou null pour un article non classé.
  final int? familleId;

  /// Le taux de TVA appliqué, ou null si aucun n'a été choisi.
  final int? tvaId;

  /// Dernier prix d'achat connu, en unités minimales. Null si inconnu.
  final int? prixAchatUnites;

  /// Prix de vente, en unités minimales. Null si l'article n'est pas
  /// encore tarifé — il ne peut alors pas être vendu en caisse.
  final int? prixVenteUnites;

  /// EAN13 ou autre code lu par une douchette. Null si l'article n'en a
  /// pas ; plusieurs articles peuvent légitimement n'en avoir aucun.
  final String? codeBarre;

  /// Un article retiré du catalogue reste en base — ses mouvements
  /// passés le référencent — mais ne se propose plus à la vente.
  final bool actif;

  const Product({
    required this.id,
    required this.reference,
    required this.designation,
    required this.unit,
    this.familleId,
    this.tvaId,
    this.prixAchatUnites,
    this.prixVenteUnites,
    this.codeBarre,
    this.actif = true,
  });

  /// Vrai si l'article porte un prix de vente et peut donc être encaissé.
  bool get estTarife => prixVenteUnites != null;

  factory Product.fromMap(Map<String, Object?> map) {
    return Product(
      id: map['id'] as int,
      reference: map['reference'] as String,
      designation: map['designation'] as String,
      unit: (map['unit'] as String?) ?? 'unité',
      familleId: map['famille_id'] as int?,
      tvaId: map['tva_id'] as int?,
      prixAchatUnites: (map['prix_achat'] as num?)?.toInt(),
      prixVenteUnites: (map['prix_vente'] as num?)?.toInt(),
      codeBarre: map['code_barre'] as String?,
      // Une base d'avant la v4 n'a pas la colonne : un article existant
      // est actif, c'est le seul état qu'il ait jamais eu.
      actif: ((map['actif'] as int?) ?? 1) == 1,
    );
  }

  Map<String, Object?> toMap({bool includeId = true}) {
    return {
      if (includeId) 'id': id,
      'reference': reference,
      'designation': designation,
      'unit': unit,
      'famille_id': familleId,
      'tva_id': tvaId,
      'prix_achat': prixAchatUnites,
      'prix_vente': prixVenteUnites,
      'code_barre': codeBarre,
      'actif': actif ? 1 : 0,
    };
  }

  /// Les drapeaux `effacer*` existent parce que null signifie déjà « ne
  /// change rien » : sans eux, on ne pourrait jamais retirer un prix ou
  /// déclasser un article.
  Product copyWith({
    int? id,
    String? reference,
    String? designation,
    String? unit,
    int? familleId,
    bool effacerFamille = false,
    int? tvaId,
    bool effacerTva = false,
    int? prixAchatUnites,
    bool effacerPrixAchat = false,
    int? prixVenteUnites,
    bool effacerPrixVente = false,
    String? codeBarre,
    bool effacerCodeBarre = false,
    bool? actif,
  }) {
    return Product(
      id: id ?? this.id,
      reference: reference ?? this.reference,
      designation: designation ?? this.designation,
      unit: unit ?? this.unit,
      familleId: effacerFamille ? null : (familleId ?? this.familleId),
      tvaId: effacerTva ? null : (tvaId ?? this.tvaId),
      prixAchatUnites: effacerPrixAchat
          ? null
          : (prixAchatUnites ?? this.prixAchatUnites),
      prixVenteUnites: effacerPrixVente
          ? null
          : (prixVenteUnites ?? this.prixVenteUnites),
      codeBarre: effacerCodeBarre ? null : (codeBarre ?? this.codeBarre),
      actif: actif ?? this.actif,
    );
  }
}
