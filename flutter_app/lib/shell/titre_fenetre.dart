import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:erp/shared/ui/widgets/identite_societe.dart';

/// Le titre de la fenêtre Windows, tenu à jour avec le nom de
/// l'entreprise.
///
/// `MaterialApp.title` ne descend pas jusqu'à la barre de titre sur le
/// bureau : Windows lit ce que le runner a posé à la création de la
/// fenêtre, et à cet instant la base n'est pas encore ouverte — le nom
/// de l'entreprise n'est donc pas connaissable. Le runner expose
/// `erp/fenetre` pour qu'on le lui dise ensuite.
///
/// C'est du shell et non de `shared/` : une dépendance à `dart:io` et à
/// une plateforme n'a rien à faire dans le vocabulaire partagé.
class TitreFenetre {
  TitreFenetre._();

  static const MethodChannel _canal = MethodChannel('erp/fenetre');

  /// Pose le titre maintenant, puis à chaque fois que le nom change.
  ///
  /// Sans écoute, le titre resterait celui du produit jusqu'au prochain
  /// démarrage après une saisie dans Paramètres.
  static void suivre() {
    if (kIsWeb || !Platform.isWindows) return;
    _poser();
    IdentiteSociete.instance.addListener(_poser);
  }

  static Future<void> _poser() async {
    try {
      await _canal.invokeMethod<void>(
        'titre',
        IdentiteSociete.instance.titreFenetre,
      );
    } on MissingPluginException {
      // Un runner plus ancien que ce canal : la fenêtre garde le titre
      // qu'il lui a donné. Rien à dire à l'utilisateur, et surtout rien
      // qui doive empêcher l'application de démarrer.
    }
  }
}
