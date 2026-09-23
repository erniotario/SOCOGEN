import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:erp/core/errors/messages.dart';

/// Un message d'erreur s'adresse à un magasinier debout dans une allée,
/// pas au développeur. Ces tests tiennent les deux bouts : ce qui est dit
/// doit être utile, et ce qui est technique ne doit jamais fuir.
void main() {
  group('causes reconnues', () {
    test('une référence en double parle de référence, pas de contrainte', () {
      final m = messagePour(
        Exception('DatabaseException(UNIQUE constraint failed: '
            'products.reference (code 2067))'),
      );

      expect(m, contains('existe déjà'));
      expect(m.toLowerCase(), isNot(contains('constraint')));
      expect(m.toLowerCase(), isNot(contains('databaseexception')));
    });

    test('une suppression bloquée dit pourquoi elle est bloquée', () {
      final m = messagePour(Exception('FOREIGN KEY constraint failed'));

      expect(m, contains('utilisé ailleurs'));
    });

    test('un appareil injoignable dit quoi vérifier', () {
      final m = messagePour(const SocketException('Connection refused'));

      expect(m, contains('Wi-Fi'));
      expect(m.toLowerCase(), isNot(contains('socketexception')));
    });

    test('un disque plein oriente vers le disque', () {
      final m = messagePour(Exception('disk I/O error'));

      expect(m, contains('disque'));
    });

    test('un port occupé désigne la cause la plus probable', () {
      final m = messagePour(Exception('Address already in use'));

      expect(m, contains('autre copie'));
    });
  });

  group('erreurs métier', () {
    test('un message déjà rédigé pour l\'utilisateur passe intact', () {
      const attendu = 'Stock insuffisant dans ce magasin.';

      expect(messagePour(const ErreurUtilisateur(attendu)), attendu);
    });

    test('la cause technique reste attachée mais hors du message', () {
      final erreur = ErreurUtilisateur(
        'Magasin inconnu.',
        cause: Exception('no rows returned'),
      );

      expect(messagePour(erreur), 'Magasin inconnu.');
      expect(messagePour(erreur), isNot(contains('no rows')));
    });
  });

  group('cause inconnue', () {
    test('ne laisse jamais filtrer le texte technique', () {
      final m = messagePour(
        Exception('NoSuchMethodError: The getter _internal was called on null'),
      );

      // La régression que ce module existe pour empêcher.
      expect(m, isNot(contains('NoSuchMethodError')));
      expect(m, isNot(contains('_internal')));
      expect(m, isNot(contains('null')));
    });

    test('rassure sur le fait que rien n\'a été enregistré à moitié', () {
      final m = messagePour(Exception('boom'));

      expect(m, contains('Aucune modification'));
    });

    test('nomme ce que la personne tentait de faire', () {
      final m = messagePour(Exception('boom'), operation: "l'import");

      expect(m, startsWith("L'import"));
    });

    test('reste lisible quand aucune opération n\'est nommée', () {
      final m = messagePour(Exception('boom'));

      expect(m, startsWith("L'opération"));
    });
  });

  test('aucun message ne se termine sans ponctuation', () {
    // Détail, mais ces phrases sont lues telles quelles dans un encart
    // rouge : une phrase tronquée donne l'impression d'un bug de plus.
    final echantillons = [
      messagePour(Exception('UNIQUE constraint failed')),
      messagePour(const SocketException('refused')),
      messagePour(Exception('inconnu'), operation: 'la sauvegarde'),
      messagePour(const ErreurUtilisateur('Stock insuffisant.')),
    ];

    for (final m in echantillons) {
      expect(m, endsWith('.'), reason: 'phrase inachevée : "$m"');
    }
  });
}
