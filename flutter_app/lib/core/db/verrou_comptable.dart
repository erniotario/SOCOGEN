import 'package:erp/core/errors/messages.dart';

/// Jusqu'où les livres sont fermés.
///
/// Le contrôle qui manquait le plus à ce logiciel. Sans lui, un
/// mouvement de mars peut être corrigé ou supprimé en décembre : toute
/// déclaration établie entre-temps devient invalidable après coup, et
/// une déclaration qu'on peut réécrire ne vaut rien. Ce n'est pas une
/// question de confiance envers l'opérateur — c'est qu'un registre dont
/// le passé bouge n'est pas un registre.
///
/// **Ambiant, comme [SessionCourante], et pour la même raison.** Faire
/// passer la date de clôture en argument à chaque écriture, c'est
/// autoriser chaque appelant à en fournir une autre, et il suffit d'un
/// formulaire distrait pour percer le verrou. Ici personne ne peut
/// l'oublier ni le contourner : les dépôts interrogent l'instance.
///
/// **Il ne va pas chercher sa valeur lui-même.** `core/` n'a pas le
/// droit d'atteindre un module ; c'est `ComptabiliteService` qui lit la
/// table et appelle [definir], exactement comme `UtilisateursService`
/// charge les droits que `PermissionGate` applique.
///
/// La limite est celle des permissions : cela protège ce que
/// l'application écrit, et n'oppose rien à quelqu'un qui édite le
/// fichier SQLite. Un verrou applicatif n'est pas un coffre.
class VerrouComptable {
  VerrouComptable();

  static final VerrouComptable instance = VerrouComptable();

  String? _fermeJusquau;

  /// Le dernier jour fermé, en `AAAA-MM-JJ`, ou nul si rien ne l'est.
  ///
  /// Nul n'est pas « fermé jusqu'à l'an zéro » : une base neuve, ou une
  /// entreprise qui n'a jamais clôturé, doit pouvoir tout écrire.
  String? get fermeJusquau => _fermeJusquau;

  bool get estActif => _fermeJusquau != null;

  /// Pose la limite. Appelé par le module comptable, au démarrage et
  /// après chaque clôture ou réouverture.
  void definir(String? jour) {
    final propre = jour?.trim();
    _fermeJusquau = (propre == null || propre.isEmpty) ? null : propre;
  }

  /// Vrai si une écriture datée de [jour] tombe dans la période fermée.
  ///
  /// La comparaison est textuelle : les dates sont stockées en
  /// `AAAA-MM-JJ`, un format qui se trie comme il se lit. Une date
  /// illisible n'est **pas** considérée comme fermée — refuser une
  /// saisie à cause d'un format qu'on n'a pas su lire punirait
  /// l'opérateur pour un défaut qui n'est pas le sien, et la validation
  /// de date est le travail du formulaire.
  bool estFerme(String? jour) {
    final limite = _fermeJusquau;
    if (limite == null || jour == null) return false;
    final propre = jour.length >= 10 ? jour.substring(0, 10) : jour;
    if (propre.length != 10) return false;
    return propre.compareTo(limite) <= 0;
  }

  /// Lève si [jour] est dans la période fermée.
  ///
  /// Le message nomme la limite et dit quoi faire : une écriture
  /// refusée sans indiquer la sortie laisse un magasinier bloqué devant
  /// sa marchandise. La sortie est la pratique comptable elle-même —
  /// un mouvement correctif daté d'aujourd'hui, qui laisse l'original
  /// debout et la piste lisible.
  void verifier(String? jour, {String operation = 'cette écriture'}) {
    if (!estFerme(jour)) return;
    throw ErreurUtilisateur(
      'La période est clôturée jusqu\'au $_fermeJusquau : $operation ne '
      'peut plus être enregistrée à cette date. Passez par un mouvement '
      'daté d\'aujourd\'hui, ou faites rouvrir la période dans '
      'Comptabilité.',
    );
  }

  /// Oublie la limite. Pour les tests, et pour une base qu'on referme.
  void oublier() => _fermeJusquau = null;
}
