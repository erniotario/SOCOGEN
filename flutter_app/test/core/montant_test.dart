import 'package:flutter_test/flutter_test.dart';

import 'package:socogen/core/money/montant.dart';

/// intl sépare les milliers par une espace fine insécable (U+202F), pas
/// par une espace ordinaire : c'est la typographie française correcte.
/// Les attentes ci-dessous s'écrivent avec une espace normale, plus
/// lisible dans le source, et passent par ici pour être comparées.
String _espacesNormales(String texte) =>
    texte.replaceAll('\u202f', ' ').replaceAll('\u00a0', ' ');

/// Les règles de calcul d'une facture, épinglées avant qu'une facture
/// existe. Ce qui se joue ici, ce sont les écarts au franc près : ils ne
/// se voient pas sur une ligne et se voient sur un relevé de fin de mois.
void main() {
  group('la devise décide de la façon de compter', () {
    test('le franc CFA n\'a pas de subdivision', () {
      expect(Devise.xaf.exposant, 0);
      expect(Devise.xaf.facteur, 1);
      expect(Montant.depuisUnite(1500).unites, 1500);
    });

    test("l'euro se compte en centimes", () {
      expect(Devise.eur.facteur, 100);
      expect(Montant.depuisUnite(15.50, devise: Devise.eur).unites, 1550);
    });

    test("zéro se laisse additionner à n'importe quelle devise", () {
      // Un cumul part de Montant.zero sans savoir encore ce qu'il
      // cumulera ; exiger la devise d'avance rendrait tout total
      // impossible à écrire simplement.
      const euro = Montant(1550, devise: Devise.eur);

      expect(Montant.zero + euro, euro);
      expect((euro - euro).estZero, isTrue);
      expect(Montant.zero + euro, isNot(const Montant(1550)));
    });

    test('additionner deux devises est refusé plutôt que deviné', () {
      expect(
        () => const Montant(100) + const Montant(100, devise: Devise.eur),
        throwsArgumentError,
      );
    });
  });

  group('le taux reste exact', () {
    test('19,25 % est représentable sans approximation', () {
      expect(Taux.tvaCameroun.pourDixMille, 1925);
      expect(Taux.pourCent(19.25), Taux.tvaCameroun);
      expect(Taux.tvaCameroun.enPourCent, 19.25);
    });

    test('la TVA camerounaise appliquée à un prix rond', () {
      // 10 000 × 19,25 % = 1 925, sans arrondi à faire.
      expect(
        Montant.depuisUnite(10000).appliquer(Taux.tvaCameroun),
        Montant.depuisUnite(1925),
      );
    });

    test('un prix qui ne tombe pas juste est arrondi au franc', () {
      // 1 500 × 19,25 % = 288,75 → 289
      expect(
        Montant.depuisUnite(1500).appliquer(Taux.tvaCameroun),
        Montant.depuisUnite(289),
      );
    });
  });

  group('arrondi', () {
    test('les demis s\'éloignent de zéro', () {
      // 10 × 5 % = 0,5 → 1
      expect(const Montant(10).appliquer(Taux.pourCent(5)), const Montant(1));
      // et le miroir, pour qu'un remboursement rende exactement ce qui
      // a été encaissé
      expect(const Montant(-10).appliquer(Taux.pourCent(5)), const Montant(-1));
    });

    test('un remboursement annule exactement la vente', () {
      const vente = Montant(1500);
      final tva = vente.appliquer(Taux.tvaCameroun);
      final remboursement = (-vente).appliquer(Taux.tvaCameroun);

      expect(tva + remboursement, Montant.zero);
    });
  });

  group('HT et TTC', () {
    test('majorer puis retrouver le HT revient au point de départ', () {
      const ht = Montant(1500);
      final ttc = ht.majorerDe(Taux.tvaCameroun);

      expect(ttc, const Montant(1789)); // 1500 + 289
      expect(ttc.horsTaxe(Taux.tvaCameroun), ht);
    });

    test('retirer le taux n\'est pas la même chose que retrouver le HT', () {
      const ttc = Montant(11925);

      // L'erreur classique sur un ticket saisi TTC : soustraire 19,25 %
      // du TTC au lieu de diviser par 1,1925.
      expect(ttc.minorerDe(Taux.tvaCameroun), const Montant(9629));
      expect(ttc.horsTaxe(Taux.tvaCameroun), const Montant(10000));
    });
  });

  group('opérations de panier', () {
    test('une quantité multiplie sans jamais arrondir', () {
      expect(const Montant(333) * 3, const Montant(999));
    });

    test('une remise se retire du prix', () {
      expect(
        Montant.depuisUnite(10000).minorerDe(Taux.pourCent(10)),
        Montant.depuisUnite(9000),
      );
    });

    test('cent lignes à 0,1 ne dérivent pas', () {
      // Le calcul qui justifie tout ce fichier : en virgule flottante,
      // additionner 0.1 cent fois donne 9.99999999999998.
      var total = Montant.zero;
      for (var i = 0; i < 100; i++) {
        total = total + const Montant(10, devise: Devise.eur);
      }
      expect(total, const Montant(1000, devise: Devise.eur));
      expect(_espacesNormales(total.formate()), '10,00 €');
    });

    test('comparer sert à détecter un stock ou un solde négatif', () {
      expect(const Montant(-1).estNegatif, isTrue);
      expect(const Montant(500) > const Montant(400), isTrue);
      expect(Montant.zero.estZero, isTrue);
    });
  });

  group('affichage', () {
    test('un montant en francs CFA se lit sans décimales', () {
      expect(_espacesNormales(Montant.depuisUnite(1500).formate()), '1 500 FCFA');
      expect(
        _espacesNormales(Montant.depuisUnite(1234567).formate()),
        '1 234 567 FCFA',
      );
    });

    test('un montant en euros garde ses deux décimales', () {
      expect(
        _espacesNormales(Montant.depuisUnite(15.5, devise: Devise.eur).formate()),
        '15,50 €',
      );
    });

    test('le symbole peut être omis pour une colonne de tableau', () {
      expect(
        _espacesNormales(Montant.depuisUnite(1500).formate(avecSymbole: false)),
        '1 500',
      );
    });
  });
}
