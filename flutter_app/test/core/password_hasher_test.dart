import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:erp/core/auth/password_hasher.dart';

/// Le hachage, et la migration silencieuse des comptes déjà créés.
///
/// Le point délicat n'est pas l'algorithme : c'est que personne ne
/// connaît le mot de passe des comptes existants. Ils ne peuvent donc
/// être remis au format courant qu'au moment où leur propriétaire se
/// connecte, et jusque-là ils doivent continuer à fonctionner.
void main() {
  /// L'ancienne forme, telle qu'elle existe dans les bases installées.
  String hashHerite(String motDePasse, String sel) =>
      sha256.convert(utf8.encode(sel + motDePasse)).toString();

  group('format courant', () {
    test('un condensat porte son algorithme et son coût', () {
      final sel = PasswordHasher.generateSalt();
      final condensat = PasswordHasher.hash('motdepasse', sel);

      expect(condensat, startsWith('pbkdf2_sha256\$'));
      expect(condensat.split(r'$'), hasLength(3));
      // Le coût est écrit dans le condensat : le relever plus tard
      // n'invalidera pas ce qui a déjà été enregistré.
      expect(int.parse(condensat.split(r'$')[1]), greaterThanOrEqualTo(12000));
    });

    test('le bon mot de passe est accepté, un autre est refusé', () {
      final sel = PasswordHasher.generateSalt();
      final condensat = PasswordHasher.hash('correct', sel);

      expect(PasswordHasher.verify('correct', sel, condensat), isTrue);
      expect(PasswordHasher.verify('incorrect', sel, condensat), isFalse);
      expect(PasswordHasher.verify('', sel, condensat), isFalse);
    });

    test('deux sels différents donnent deux condensats différents', () {
      final a = PasswordHasher.hash('identique', PasswordHasher.generateSalt());
      final b = PasswordHasher.hash('identique', PasswordHasher.generateSalt());

      expect(a, isNot(b));
    });

    test('le sel est assez long pour ne pas se répéter', () {
      final sels = List.generate(50, (_) => PasswordHasher.generateSalt());

      expect(sels.toSet(), hasLength(50));
      expect(sels.first.length, 32); // 16 octets en hexadécimal
    });
  });

  group('comptes hérités', () {
    test('un condensat SHA-256 à un tour reste vérifiable', () {
      // Sans cela, la mise à jour enfermerait dehors tous les comptes
      // existants — y compris le seul administrateur.
      const sel = 'abcdef0123456789abcdef0123456789';
      final ancien = hashHerite('motdepasse', sel);

      expect(PasswordHasher.verify('motdepasse', sel, ancien), isTrue);
      expect(PasswordHasher.verify('autre', sel, ancien), isFalse);
    });

    test('il est signalé comme devant être réécrit', () {
      const sel = 'abcdef0123456789abcdef0123456789';

      expect(PasswordHasher.needsRehash(hashHerite('x', sel)), isTrue);
      expect(PasswordHasher.needsRehash(PasswordHasher.hash('x', sel)), isFalse);
    });

    test('un condensat au coût devenu insuffisant est aussi réécrit', () {
      // Le jour où le nombre d'itérations sera relevé, les condensats
      // écrits au coût précédent doivent repasser par la case migration.
      expect(
        PasswordHasher.needsRehash('pbkdf2_sha256\$1000\$deadbeef'),
        isTrue,
      );
    });

    test('un condensat illisible est traité comme à réécrire, pas comme valide', () {
      for (final abime in ['pbkdf2_sha256\$', 'pbkdf2_sha256\$abc\$def', '']) {
        expect(PasswordHasher.needsRehash(abime), isTrue, reason: abime);
        expect(PasswordHasher.verify('x', 'sel', abime), isFalse, reason: abime);
      }
    });
  });

  group('coût', () {
    test('le nouveau format est nettement plus lent que l\'ancien', () {
      // Toute la valeur de ce changement tient dans cet écart : ce qui
      // coûte cher à vérifier une fois coûte cher à forcer un milliard
      // de fois.
      const sel = 'abcdef0123456789abcdef0123456789';

      final debutHerite = DateTime.now();
      for (var i = 0; i < 100; i++) {
        hashHerite('motdepasse', sel);
      }
      final dureeHerite = DateTime.now().difference(debutHerite);

      final debutCourant = DateTime.now();
      PasswordHasher.hash('motdepasse', sel);
      final dureeCourant = DateTime.now().difference(debutCourant);

      expect(
        dureeCourant,
        greaterThan(dureeHerite),
        reason: 'un seul hachage courant doit coûter plus que cent anciens',
      );
    });

    test('une connexion reste rapide sur un poste de bureau', () {
      // Le coût est payé une fois, à la connexion. Le seuil est fixé bas
      // exprès : un téléphone d'entrée de gamme est plusieurs fois plus
      // lent que cette machine, et c'est lui qui décide du confort réel.
      // Ce test a déjà servi une fois — il a rejeté 60 000 itérations,
      // qui demandaient 1,5 s ici.
      final sel = PasswordHasher.generateSalt();
      final condensat = PasswordHasher.hash('motdepasse', sel);

      final debut = DateTime.now();
      PasswordHasher.verify('motdepasse', sel, condensat);
      final duree = DateTime.now().difference(debut);

      expect(duree.inMilliseconds, lessThan(600), reason: 'vérification trop lente');
    });
  });
}
