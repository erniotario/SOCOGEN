import 'package:flutter_test/flutter_test.dart';

import 'package:socogen/core/auth/permissions.dart';

/// Le point de décision des droits, introduit avant les rôles.
///
/// Sa valeur aujourd'hui tient en une phrase : il ne change rien. Les
/// deux rôles en dur continuent de voir exactement ce qu'ils voyaient.
/// Ce que ces tests protègent, c'est cette équivalence — le jour où la
/// phase 4 remplacera la règle, ils diront si le remplacement a dérivé.
void main() {
  const admin = PermissionGate('admin');
  const magasinier = PermissionGate('magasinier');

  group('comportement reproduit à l\'identique', () {
    test('un administrateur garde accès à tout', () {
      for (final p in Permissions.toutes) {
        expect(admin.autorise(p), isTrue, reason: p.code);
      }
    });

    test('un magasinier garde le stock, le catalogue et les rapports', () {
      expect(magasinier.autorise(Permissions.consulterStock), isTrue);
      expect(magasinier.autorise(Permissions.saisirMouvement), isTrue);
      expect(magasinier.autorise(Permissions.gererCatalogue), isTrue);
      expect(magasinier.autorise(Permissions.consulterRapports), isTrue);
    });

    test('un magasinier reste hors de Sécurité et Paramètres', () {
      // Exactement les deux écrans que le shell retirait déjà.
      expect(magasinier.autorise(Permissions.gererUtilisateurs), isFalse);
      expect(magasinier.autorise(Permissions.modifierParametres), isFalse);
      expect(magasinier.refuse(Permissions.gererUtilisateurs), isTrue);
    });
  });

  group('absence de session', () {
    test('personne de connecté ne peut rien', () {
      for (final p in Permissions.toutes) {
        expect(PermissionGate.aucun.autorise(p), isFalse, reason: p.code);
      }
    });

    test('un rôle inconnu est traité comme un rôle sans privilège', () {
      // Un rôle ajouté en base à la main, ou lu depuis une version plus
      // récente : il entre, mais rien de réservé ne s'ouvre à lui.
      const inconnu = PermissionGate('comptable');

      expect(inconnu.estConnecte, isTrue);
      expect(inconnu.estAdmin, isFalse);
      expect(inconnu.autorise(Permissions.gererUtilisateurs), isFalse);
      expect(inconnu.autorise(Permissions.consulterStock), isTrue);
    });
  });

  group('les permissions elles-mêmes', () {
    test('chaque code est unique', () {
      final codes = Permissions.toutes.map((p) => p.code).toList();

      expect(codes.toSet(), hasLength(codes.length));
    });

    test('chaque code suit la forme module.action', () {
      // C'est ce code qui sera stocké quand les rôles deviendront des
      // données ; une forme stable évite une migration pour un renommage.
      for (final p in Permissions.toutes) {
        expect(
          p.code,
          matches(RegExp(r'^[a-z]+\.[a-z]+$')),
          reason: '${p.code} ne suit pas module.action',
        );
      }
    });

    test('chaque permission a un libellé lisible', () {
      for (final p in Permissions.toutes) {
        expect(p.libelle, isNotEmpty, reason: p.code);
        expect(p.libelle[0], p.libelle[0].toUpperCase(), reason: p.code);
      }
    });

    test('deux permissions de même code sont la même permission', () {
      expect(
        const Permission('stock.consulter', 'Autre libellé'),
        Permissions.consulterStock,
      );
    });
  });
}
