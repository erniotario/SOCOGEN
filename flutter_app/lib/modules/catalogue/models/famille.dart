/// Une famille d'articles : « Boissons », puis « Boissons / Sodas ».
///
/// L'arborescence est volontairement plate en base — un `parent_id` qui
/// pointe vers une autre famille — plutôt qu'un chemin matérialisé. Un
/// grossiste renomme et déplace ses familles ; un chemin stocké obligerait
/// à réécrire tous les descendants à chaque déplacement.
class Famille {
  final int id;

  /// Code court et stable, saisi une fois. C'est lui qu'on retrouve sur
  /// un export ou un inventaire papier, pas l'identifiant technique.
  final String code;

  final String nom;

  /// La famille parente, ou null pour une racine.
  final int? parentId;

  /// Ordre d'affichage entre familles de même niveau. Deux familles de
  /// même ordre se départagent par leur nom.
  final int ordre;

  const Famille({
    required this.id,
    required this.code,
    required this.nom,
    this.parentId,
    this.ordre = 0,
  });

  bool get estRacine => parentId == null;

  factory Famille.fromMap(Map<String, Object?> map) {
    return Famille(
      id: map['id'] as int,
      code: map['code'] as String,
      nom: map['nom'] as String,
      parentId: map['parent_id'] as int?,
      ordre: (map['ordre'] as int?) ?? 0,
    );
  }

  Map<String, Object?> toMap({bool includeId = true}) {
    return {
      if (includeId) 'id': id,
      'code': code,
      'nom': nom,
      'parent_id': parentId,
      'ordre': ordre,
    };
  }

  Famille copyWith({
    int? id,
    String? code,
    String? nom,
    int? parentId,
    bool effacerParent = false,
    int? ordre,
  }) {
    return Famille(
      id: id ?? this.id,
      code: code ?? this.code,
      nom: nom ?? this.nom,
      // Sans ce drapeau, `copyWith(parentId: null)` ne saurait pas dire
      // « remonter à la racine » : null y signifie « ne change rien ».
      parentId: effacerParent ? null : (parentId ?? this.parentId),
      ordre: ordre ?? this.ordre,
    );
  }
}
