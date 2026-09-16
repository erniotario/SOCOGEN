/// Le point où se décide « cette personne a-t-elle le droit ».
///
/// Il existe avant le vrai contrôle d'accès, et c'est volontaire. Le
/// plan place les rôles en phase 4, après le catalogue, les tiers et le
/// stock ; si le point de décision n'existait qu'à ce moment-là, il
/// faudrait repasser dans tous les écrans construits entre-temps pour y
/// insérer des vérifications. Ici, chaque module déclare ses permissions
/// au fur et à mesure qu'il naît, les écrans interrogent [PermissionGate]
/// dès le premier jour, et la phase 4 ne fera que remplacer la règle qui
/// répond — sans toucher aux appelants.
///
/// Ce qu'il ne fait pas, et qu'aucune quantité de code ici ne fera : il
/// n'oppose rien à quelqu'un qui ouvre le fichier SQLite. Tant qu'il n'y
/// a pas de serveur, une permission cache un écran et refuse un bouton ;
/// elle ne protège pas la donnée. C'est écrit ici pour que personne ne
/// se fie à ce contrôle pour autre chose.
library;

/// Un droit nommé, tel qu'un écran le réclame.
class Permission {
  /// Identifiant stable, de la forme `module.action`.
  ///
  /// C'est lui qui sera stocké quand les rôles deviendront des données ;
  /// le libellé, lui, pourra changer sans rien casser.
  final String code;

  /// Ce que lira un administrateur dans l'écran des rôles.
  final String libelle;

  /// Réservé à l'administrateur tant que les rôles sont les deux rôles
  /// en dur d'aujourd'hui — `admin` et `magasinier`.
  ///
  /// Ce drapeau est la règle provisoire, pas la règle définitive : la
  /// phase 4 le remplacera par une table de permissions par rôle. Les
  /// appels aux permissions, eux, ne bougeront pas.
  final bool adminSeul;

  const Permission(this.code, this.libelle, {this.adminSeul = false});

  @override
  bool operator ==(Object other) => other is Permission && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => code;
}

/// Les permissions déclarées à ce jour.
///
/// Chaque module ajoute les siennes en naissant. La liste est volontairement
/// courte : elle décrit ce que l'application sait faire aujourd'hui, pas ce
/// qu'elle saura faire.
class Permissions {
  Permissions._();

  static const gererUtilisateurs = Permission(
    'utilisateurs.gerer',
    'Gérer les comptes et les rôles',
    adminSeul: true,
  );

  static const modifierParametres = Permission(
    'parametres.modifier',
    "Modifier les paramètres de l'entreprise",
    adminSeul: true,
  );

  static const consulterStock = Permission(
    'stock.consulter',
    'Consulter le stock et les mouvements',
  );

  static const saisirMouvement = Permission(
    'stock.saisir',
    'Enregistrer une entrée ou une sortie',
  );

  static const gererCatalogue = Permission(
    'catalogue.gerer',
    'Créer et modifier les articles',
  );

  static const consulterRapports = Permission(
    'rapports.consulter',
    'Consulter les rapports',
  );

  /// Toutes les permissions connues, pour l'écran des rôles à venir.
  static const List<Permission> toutes = [
    gererUtilisateurs,
    modifierParametres,
    consulterStock,
    saisirMouvement,
    gererCatalogue,
    consulterRapports,
  ];
}

/// Répond aux questions de droits pour la personne connectée.
///
/// Prend le rôle plutôt que l'utilisateur : le noyau n'a pas à connaître
/// le modèle d'un module pour répondre « oui » ou « non ».
class PermissionGate {
  /// Le rôle de la personne connectée, ou null si personne ne l'est.
  final String? role;

  const PermissionGate(this.role);

  /// Personne n'est connecté : rien n'est permis.
  static const PermissionGate aucun = PermissionGate(null);

  bool get estConnecte => role != null;

  bool get estAdmin => role == 'admin';

  /// Vrai si la personne connectée a le droit [permission].
  ///
  /// Règle d'aujourd'hui, appelée à être remplacée en phase 4 : un
  /// administrateur peut tout, les autres peuvent tout sauf ce qui est
  /// marqué [Permission.adminSeul]. Elle reproduit exactement le
  /// comportement que l'application avait déjà, pour que l'introduction
  /// de ce point de décision ne change rien pour personne.
  bool autorise(Permission permission) {
    if (!estConnecte) return false;
    if (permission.adminSeul) return estAdmin;
    return true;
  }

  /// L'inverse, quand c'est ce qui se lit le mieux à l'appel.
  bool refuse(Permission permission) => !autorise(permission);
}
