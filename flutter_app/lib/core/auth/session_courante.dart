/// Qui est connecté, pour les écritures qui doivent porter un auteur.
///
/// Pourquoi un état ambiant plutôt qu'un paramètre passé de main en
/// main. L'auteur d'une écriture n'est pas une donnée que l'appelant
/// choisit : c'est un fait sur la session en cours. Le passer en
/// argument obligerait chaque formulaire à le fournir — donc à pouvoir
/// en fournir un autre — et il suffirait d'un écran distrait pour
/// qu'une ligne soit signée du mauvais nom. Ici, le dépôt le lit
/// lui-même au moment d'écrire, et aucun appelant n'a la main dessus.
///
/// Ce que cela ne fait pas, et qu'aucune quantité de code ici ne fera :
/// cela n'oppose rien à quelqu'un qui ouvre le fichier SQLite et change
/// un `created_by`. Tant qu'il n'y a pas de serveur, l'attribution dit
/// ce que l'application a enregistré, pas ce qu'un tiers ne peut pas
/// réécrire. La même limite que les permissions.
library;

class SessionCourante {
  SessionCourante._();

  static final SessionCourante instance = SessionCourante._();

  int? _utilisateurId;
  String? _nomUtilisateur;

  /// L'identifiant de la personne connectée, ou null si personne ne
  /// l'est — auquel cas les écritures restent sans auteur plutôt que
  /// d'en inventer un.
  int? get utilisateurId => _utilisateurId;

  String? get nomUtilisateur => _nomUtilisateur;

  bool get estOuverte => _utilisateurId != null;

  /// Appelé à la connexion réussie, et à la création du premier compte.
  void ouvrir({required int utilisateurId, required String nom}) {
    _utilisateurId = utilisateurId;
    _nomUtilisateur = nom;
  }

  /// Appelé à la déconnexion. Une écriture qui suivrait n'aura pas
  /// d'auteur, ce qui est exact.
  void fermer() {
    _utilisateurId = null;
    _nomUtilisateur = null;
  }
}
