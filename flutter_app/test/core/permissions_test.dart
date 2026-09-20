import 'package:flutter_test/flutter_test.dart';

import 'package:socogen/core/auth/permissions.dart';

/// Le point de décision des droits, maintenant qu'il répond par des
/// données.
///
/// Deux règles opposées à tenir. L'administrateur répond oui à tout
/// **sans rien consulter** : si ses droits étaient des données, il
/// pourrait se retirer celui de gérer les droits et plus personne ne
/// rattraperait rien. Tous les autres rôles répondent par ce qui leur
/// est accordé, **et rien d'autre** — l'absence de droits n'est pas une
/// permission par défaut.
///
/// Que les droits servis à l'installation reproduisent l'ancienne règle
/// est une question de données, et se vérifie dans
/// `roles_test.dart` sur une base réelle.
void main() {
  const admin = PermissionGate('admin');
  // Un magasinier tel que la base le sert : tout sauf l'administration.
  final magasinier = PermissionGate('magasinier', accordees: {
    for (final p in Permissions.toutes)
      if (!p.adminSeul) p.code,
  });

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

    test('un rôle sans droits accordés ne peut rien', () {
      // Un rôle créé et pas encore réglé. Il entre — la session existe —
      // mais rien ne s'ouvre à lui. L'absence de droits ne vaut pas
      // permission : c'est le sens d'erreur qui se rattrape.
      const neuf = PermissionGate('comptable');

      expect(neuf.estConnecte, isTrue);
      expect(neuf.estAdmin, isFalse);
      for (final p in Permissions.toutes) {
        expect(neuf.autorise(p), isFalse, reason: p.code);
      }
    });

    test('un droit inconnu du programme est sans effet', () {
      // Une base écrite par une version plus récente peut accorder un
      // code que celle-ci ne connaît pas. Il ne doit rien ouvrir, et
      // surtout rien faire échouer.
      const venuDAilleurs = PermissionGate(
        'comptable',
        accordees: {'comptabilite.cloturer'},
      );

      for (final p in Permissions.toutes) {
        expect(venuDAilleurs.autorise(p), isFalse, reason: p.code);
      }
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
