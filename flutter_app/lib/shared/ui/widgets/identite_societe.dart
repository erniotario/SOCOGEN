import 'package:flutter/foundation.dart';

import 'package:erp/shared/ui/theme/app_branding.dart';

/// Le nom de l'entreprise qui utilise l'application, disponible partout.
///
/// Il est saisi une fois au premier lancement et ne change presque
/// jamais ensuite. Le relire à chaque écran ferait une requête par
/// construction ; le tenir ici le rend immédiat et permet de l'afficher
/// dans la barre latérale, le titre de fenêtre et les documents sans que
/// chacun s'organise pour aller le chercher.
///
/// **Il ne va pas le chercher lui-même** : `shared/` n'a pas le droit
/// d'atteindre un module, et c'est le shell qui lit les paramètres et
/// appelle [definir]. Cette classe ne fait que tenir la valeur et
/// prévenir quand elle change.
///
/// Tant qu'il n'est pas chargé — ou qu'une installation neuve n'a pas
/// encore dit qui elle est — les écrans retombent sur le nom du produit.
/// Emprunter le nom d'une autre entreprise serait exactement le défaut
/// que le renommage du produit a corrigé.
class IdentiteSociete extends ChangeNotifier {
  IdentiteSociete();

  static final IdentiteSociete instance = IdentiteSociete();

  String _nom = '';

  /// Le nom saisi, ou une chaîne vide tant qu'il est inconnu.
  String get nom => _nom;

  bool get estConnu => _nom.isNotEmpty;

  /// Ce qu'un écran affiche : le nom de l'entreprise, ou à défaut celui
  /// du produit.
  String get affichable => estConnu ? _nom : AppBranding.productName;

  /// La lettre que porte la pastille du logo.
  ///
  /// Elle suit le nom affiché : gravée, elle garderait l'initiale du
  /// premier client au-dessus du nom de tous les suivants.
  String get initiale => affichable.substring(0, 1).toUpperCase();

  /// Le titre de fenêtre : l'entreprise d'abord, le produit ensuite.
  ///
  /// Dans cet ordre parce qu'une personne qui cherche sa fenêtre parmi
  /// dix autres reconnaît le nom de sa maison avant celui du logiciel.
  String get titreFenetre =>
      estConnu ? '$_nom — ${AppBranding.productName}' : AppBranding.windowTitle;

  /// Pose le nom. Appelé par le shell au démarrage, et par l'écran des
  /// paramètres qui vient de l'enregistrer — celui-ci le tient déjà, et
  /// un aller-retour en base pour le relire serait du travail pour rien.
  void definir(String nom) {
    final propre = nom.trim();
    if (propre == _nom) return;
    _nom = propre;
    notifyListeners();
  }
}
