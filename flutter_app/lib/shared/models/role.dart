/// Un rôle, et ce qu'il autorise.
///
/// Les rôles étaient deux chaînes en dur — `admin` et `magasinier` —
/// et la règle des droits vivait dans le code. Ce sont maintenant des
/// données : un commerce peut créer « caissier » ou « responsable » et
/// décider de ce que chacun voit.
///
/// Le **code** reste la clé, parce que c'est lui que `users.role` porte
/// déjà : le garder évite de réécrire tous les comptes existants, et il
/// survit à un changement de libellé.
library;

class Role {
  /// Identifiant stable, tel que stocké sur les comptes.
  final String code;

  /// Ce que lit un administrateur dans l'écran des rôles.
  final String libelle;

  /// Un rôle intégré ne se supprime pas.
  ///
  /// `admin` parce que sans lui personne ne peut plus rendre de droits,
  /// `magasinier` parce que c'est le rôle par défaut de la table `users`
  /// et qu'un compte pointant un rôle disparu n'aurait plus rien.
  final bool integre;

  const Role({
    required this.code,
    required this.libelle,
    this.integre = false,
  });

  factory Role.fromMap(Map<String, Object?> map) {
    return Role(
      code: map['code'] as String,
      libelle: map['libelle'] as String,
      integre: ((map['integre'] as int?) ?? 0) == 1,
    );
  }

  Map<String, Object?> toMap() => {
        'code': code,
        'libelle': libelle,
        'integre': integre ? 1 : 0,
      };
}
