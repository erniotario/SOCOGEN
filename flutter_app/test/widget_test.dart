import 'package:flutter_test/flutter_test.dart';

import 'package:erp/main.dart';
import 'package:erp/shared/ui/theme/app_branding.dart';
import 'package:erp/shared/ui/widgets/identite_societe.dart';

void main() {
  testWidgets('App boots and shows a name', (WidgetTester tester) async {
    await tester.pumpWidget(const StockApp());

    expect(find.text(IdentiteSociete.instance.affichable), findsOneWidget);
  });

  group('le nom du produit', () {
    test('ne porte le nom d\'aucun client', () {
      // L'application a d'abord porté le nom de SOCOGEN, qui est
      // maintenant un client parmi ceux qui l'installent. Un grossiste
      // de Douala ne doit pas faire tourner un logiciel qui arbore le
      // nom d'un concurrent.
      for (final interdit in ['SOCOGEN', 'SHEMAB']) {
        expect(AppBranding.productName.toUpperCase(),
            isNot(contains(interdit)));
        expect(AppBranding.windowTitle.toUpperCase(),
            isNot(contains(interdit)));
      }
    });

    test('est générique', () {
      expect(AppBranding.productName, 'ERP');
      expect(AppBranding.windowTitle, contains('ERP'));
    });
  });

  group('ce que les écrans affichent', () {
    tearDown(() => IdentiteSociete.instance.definir(''));

    test('le nom de la société dès qu\'il est connu', () {
      IdentiteSociete.instance.definir('Maison Kamdem');

      expect(IdentiteSociete.instance.affichable, 'Maison Kamdem');
      expect(IdentiteSociete.instance.estConnu, isTrue);
    });

    test('celui du produit tant qu\'il ne l\'est pas', () {
      // Une installation neuve n'a pas encore dit qui elle est.
      // Emprunter le nom d'une autre entreprise serait le défaut que ce
      // renommage a corrigé.
      IdentiteSociete.instance.definir('');

      expect(IdentiteSociete.instance.affichable, AppBranding.productName);
      expect(IdentiteSociete.instance.estConnu, isFalse);
    });

    test('la société avant le produit dans le titre de fenêtre', () {
      // Une personne qui cherche sa fenêtre parmi dix autres reconnaît
      // le nom de sa maison avant celui du logiciel.
      IdentiteSociete.instance.definir('Maison Kamdem');

      expect(IdentiteSociete.instance.titreFenetre,
          startsWith('Maison Kamdem'));
      expect(IdentiteSociete.instance.titreFenetre,
          contains(AppBranding.productName));
    });

    test('un nom d\'espaces n\'est pas un nom', () {
      IdentiteSociete.instance.definir('   ');

      expect(IdentiteSociete.instance.estConnu, isFalse);
    });

    test('un changement prévient ceux qui écoutent', () {
      // La barre latérale et l'écran de connexion en dépendent : sans
      // cela ils garderaient l'ancien nom jusqu'au prochain démarrage.
      var appels = 0;
      void ecouter() => appels++;
      IdentiteSociete.instance.addListener(ecouter);
      addTearDown(() => IdentiteSociete.instance.removeListener(ecouter));

      IdentiteSociete.instance.definir('Maison Kamdem');
      expect(appels, 1);

      // Le même nom ne redéclenche rien : une notification par frappe
      // ferait reconstruire l'écran pour rien.
      IdentiteSociete.instance.definir('Maison Kamdem');
      expect(appels, 1);
    });
  });
}
