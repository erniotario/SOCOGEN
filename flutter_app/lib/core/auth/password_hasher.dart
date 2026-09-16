import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Le hachage des mots de passe.
///
/// L'application hachait en un seul tour de SHA-256 — la forme héritée
/// de la version Python. Un seul tour se teste par milliards par seconde
/// sur une carte graphique : le sel empêche les tables précalculées, il
/// n'empêche pas de forcer un mot de passe faible. Tant que la base
/// vivait sur un seul poste tenu par son propriétaire, c'était
/// défendable. Ça ne l'est plus dès qu'un fichier peut être copié, et
/// pas du tout si une base centrale voit le jour.
///
/// Le remplacement est PBKDF2-HMAC-SHA256, écrit avec le paquet `crypto`
/// déjà présent — ni bcrypt ni argon2 n'ont été ajoutés parce qu'aucun
/// n'était nécessaire pour obtenir un coût de calcul réglable.
///
/// Les deux formes coexistent volontairement : personne ne connaît le
/// mot de passe des comptes existants, donc personne ne peut les
/// re-hacher à leur place. Un compte ancien est reconnu, vérifié comme
/// avant, puis remis au format courant lors de sa prochaine connexion
/// réussie — le seul instant où le mot de passe en clair est disponible.
class PasswordHasher {
  PasswordHasher._();

  /// Préfixe qui distingue un condensat courant d'un condensat hérité.
  static const String _prefixe = 'pbkdf2_sha256';

  /// Nombre d'itérations PBKDF2.
  ///
  /// Compromis assumé, et mesuré plutôt que supposé : l'implémentation
  /// est en Dart pur, donc environ cinquante fois plus lente qu'un
  /// PBKDF2 natif. 60 000 tours demandaient 1,5 s sur un poste de
  /// bureau, soit plusieurs secondes sur un téléphone d'entrée de gamme
  /// — un prix que personne n'accepte de payer pour se connecter.
  ///
  /// 12 000 tours tiennent la vérification autour de 300 ms ici, ce qui
  /// laisse de la marge sur un téléphone lent. C'est en deçà des
  /// recommandations écrites pour des implémentations natives, et c'est
  /// douze mille fois plus coûteux que le tour unique d'avant. La vraie
  /// réponse à ce compromis est un hachage natif, pas un réglage : le
  /// jour où il arrivera, le nombre d'itérations est inscrit dans chaque
  /// condensat, donc relevable sans invalider l'existant.
  static const int _iterations = 12000;

  /// Un sel aléatoire, en hexadécimal.
  static String generateSalt({int byteLength = 16}) {
    final random = Random.secure();
    final bytes = List<int>.generate(byteLength, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Le condensat à stocker, au format courant.
  ///
  /// La forme `pbkdf2_sha256$<itérations>$<hex>` porte son propre
  /// paramétrage : relever le coût plus tard n'invalidera pas ce qui a
  /// déjà été écrit.
  static String hash(String password, String salt) {
    final derive = _pbkdf2(
      motDePasse: utf8.encode(password),
      sel: utf8.encode(salt),
      iterations: _iterations,
      longueur: 32,
    );
    final hex = derive.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '$_prefixe\$$_iterations\$$hex';
  }

  /// L'ancienne forme, conservée pour vérifier les comptes non migrés.
  static String _hashHerite(String password, String salt) =>
      sha256.convert(utf8.encode(salt + password)).toString();

  /// Vrai si [password] correspond à [expectedHash], quelle que soit la
  /// forme dans laquelle ce dernier a été écrit.
  static bool verify(String password, String salt, String expectedHash) {
    if (!expectedHash.startsWith('$_prefixe\$')) {
      return _comparaisonConstante(_hashHerite(password, salt), expectedHash);
    }
    final parts = expectedHash.split(r'$');
    if (parts.length != 3) return false;
    final iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations <= 0) return false;

    final derive = _pbkdf2(
      motDePasse: utf8.encode(password),
      sel: utf8.encode(salt),
      iterations: iterations,
      longueur: 32,
    );
    final hex = derive.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return _comparaisonConstante(hex, parts[2]);
  }

  /// Vrai si ce condensat doit être réécrit à la prochaine connexion :
  /// forme héritée, ou coût devenu inférieur au coût courant.
  static bool needsRehash(String storedHash) {
    if (!storedHash.startsWith('$_prefixe\$')) return true;
    final parts = storedHash.split(r'$');
    if (parts.length != 3) return true;
    final iterations = int.tryParse(parts[1]);
    return iterations == null || iterations < _iterations;
  }

  /// Comparaison à durée constante.
  ///
  /// Un `==` sur des chaînes s'arrête au premier caractère différent, ce
  /// qui laisse mesurer combien de caractères étaient bons. Le risque
  /// est théorique pour une application locale ; l'écrire correctement
  /// coûte trois lignes et vaudra pour le jour où un serveur répondra.
  static bool _comparaisonConstante(String a, String b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return difference == 0;
  }

  /// PBKDF2-HMAC-SHA256 (RFC 8018).
  ///
  /// Écrit ici plutôt qu'importé : `crypto` fournit HMAC, et PBKDF2
  /// n'est au-dessus qu'une boucle de XOR. Ajouter une dépendance pour
  /// vingt lignes ne se justifiait pas.
  static Uint8List _pbkdf2({
    required List<int> motDePasse,
    required List<int> sel,
    required int iterations,
    required int longueur,
  }) {
    final hmac = Hmac(sha256, motDePasse);
    const tailleBloc = 32; // sortie de SHA-256
    final nbBlocs = (longueur / tailleBloc).ceil();
    final sortie = Uint8List(nbBlocs * tailleBloc);

    for (var bloc = 1; bloc <= nbBlocs; bloc++) {
      // U1 = HMAC(mot de passe, sel || INT_32_BE(bloc))
      final entree = <int>[
        ...sel,
        (bloc >> 24) & 0xff,
        (bloc >> 16) & 0xff,
        (bloc >> 8) & 0xff,
        bloc & 0xff,
      ];
      var u = Uint8List.fromList(hmac.convert(entree).bytes);
      final accumulateur = Uint8List.fromList(u);

      // Un XOR de tous les Ui : c'est ce chaînage qui rend le calcul
      // impossible à paralléliser et donc coûteux à attaquer.
      for (var i = 1; i < iterations; i++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (var j = 0; j < tailleBloc; j++) {
          accumulateur[j] ^= u[j];
        }
      }
      sortie.setRange((bloc - 1) * tailleBloc, bloc * tailleBloc, accumulateur);
    }
    return Uint8List.sublistView(sortie, 0, longueur);
  }
}
