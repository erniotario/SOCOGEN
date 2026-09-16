import 'dart:io';

import 'package:flutter/foundation.dart';

/// Traduit une erreur technique en phrase qu'un magasinier peut suivre.
///
/// Les écrans affichaient jusqu'ici l'exception brute — `Erreur : $e` —
/// ce qui donne « DatabaseException(UNIQUE constraint failed:
/// products.reference) » à quelqu'un qui voulait juste enregistrer un
/// article. La règle de ce projet est qu'un message dit quoi faire, pas
/// ce qui a levé.
///
/// Le détail technique n'est pas perdu : [journaliser] l'écrit dans la
/// console de développement. Il n'est simplement jamais montré.

/// Erreur dont le message est déjà destiné à l'utilisateur.
///
/// À lever depuis les services quand la cause est métier et connue — un
/// stock insuffisant, un magasin inconnu — plutôt que de laisser
/// remonter une exception technique que l'écran devra deviner.
class ErreurUtilisateur implements Exception {
  /// Phrase française, actionnable, affichable telle quelle.
  final String message;

  /// Ce qui a réellement échoué. Journalisé, jamais affiché.
  final Object? cause;

  const ErreurUtilisateur(this.message, {this.cause});

  @override
  String toString() => message;
}

/// Écrit le détail technique là où un développeur le verra.
///
/// Il n'y a pas de collecte d'erreurs dans cette application : en
/// production ce journal ne va nulle part. C'est un choix assumé tant
/// qu'il n'y a pas de serveur pour le recevoir, pas un oubli.
void journaliser(Object erreur, [StackTrace? trace]) {
  if (kDebugMode) {
    debugPrint('[erreur] $erreur');
    if (trace != null) debugPrint('$trace');
  }
}

/// Le message à montrer pour [erreur].
///
/// [operation] nomme ce que l'utilisateur tentait, au format « l'import »
/// ou « la synchronisation ». Il n'apparaît que dans la phrase de repli :
/// quand la cause est reconnue, elle est plus précise à elle seule.
///
/// Journalise systématiquement avant de répondre, pour que le détail
/// existe quelque part même quand l'écran n'en montre rien.
String messagePour(Object erreur, {String? operation, StackTrace? trace}) {
  journaliser(erreur, trace);

  if (erreur is ErreurUtilisateur) return erreur.message;

  final texte = erreur.toString().toLowerCase();

  // --- base de données -------------------------------------------------
  if (texte.contains('unique constraint')) {
    return 'Cette valeur existe déjà. Vérifiez la référence ou le nom saisi.';
  }
  if (texte.contains('foreign key constraint')) {
    return 'Cet élément est utilisé ailleurs et ne peut pas être supprimé '
        'tant que les lignes qui le référencent existent.';
  }
  if (texte.contains('database is locked') || texte.contains('busy')) {
    return 'La base est occupée par une autre opération. '
        'Réessayez dans quelques secondes.';
  }
  if (texte.contains('readonly') || texte.contains('disk i/o') ||
      texte.contains('disk full')) {
    return "Impossible d'écrire sur le disque. Vérifiez l'espace libre et "
        "les droits du dossier de l'application.";
  }

  // --- réseau (synchronisation Wi-Fi, serveur local) --------------------
  if (erreur is SocketException ||
      texte.contains('connection refused') ||
      texte.contains('connection failed') ||
      texte.contains('network is unreachable')) {
    return 'Appareil injoignable. Vérifiez que les deux appareils sont sur '
        'le même réseau Wi-Fi et que le serveur est démarré sur l\'autre.';
  }
  if (texte.contains('timeout') || texte.contains('timed out')) {
    return "L'autre appareil n'a pas répondu à temps. Vérifiez qu'il est "
        'allumé et toujours sur le même réseau.';
  }
  if (texte.contains('address already in use')) {
    return 'Le port est déjà utilisé, probablement par une autre copie de '
        "l'application. Fermez-la puis réessayez.";
  }

  // --- fichiers (import Excel, export PDF) ------------------------------
  if (erreur is FileSystemException || texte.contains('cannot open file')) {
    return "Le fichier n'a pas pu être ouvert. Vérifiez qu'il existe "
        "toujours et qu'il n'est pas ouvert dans un autre logiciel.";
  }
  if (erreur is FormatException || texte.contains('format')) {
    return "Le fichier n'a pas le format attendu et n'a pas pu être lu.";
  }

  // --- repli ------------------------------------------------------------
  // Aucune cause reconnue : dire ce qui n'a pas eu lieu, et surtout que
  // rien n'a été enregistré à moitié.
  final quoi = operation == null ? "L'opération" : _capitaliser(operation);
  return "$quoi n'a pas pu être menée à bien. Aucune modification n'a été "
      'enregistrée. Réessayez, et prévenez votre responsable si cela '
      'se reproduit.';
}

String _capitaliser(String texte) =>
    texte.isEmpty ? texte : texte[0].toUpperCase() + texte.substring(1);
