import 'package:intl/intl.dart';

/// L'argent, en entiers.
///
/// Un montant n'est jamais un `double`. 0,1 + 0,2 ne fait pas 0,3 en
/// virgule flottante, et sur une facture de cent lignes l'écart finit
/// par se voir : une facture qui ne tombe pas juste au franc près est
/// une facture qu'un comptable refuse.
///
/// Tout est donc stocké en **unité minimale de la devise**, en `int` :
/// le franc CFA n'a pas de subdivision (exposant 0), un montant XAF est
/// donc un nombre entier de francs. L'euro aurait un exposant 2 et se
/// compterait en centimes. Le type est le même, seule la devise change.

/// Une devise et la façon dont elle se compte.
class Devise {
  /// Code ISO 4217 — XAF, EUR, USD.
  final String code;

  /// Ce que l'utilisateur lit — FCFA, €.
  final String symbole;

  /// Nombre de décimales. 0 pour le franc CFA, 2 pour l'euro.
  ///
  /// C'est aussi la puissance de dix qui sépare l'unité minimale de
  /// l'unité usuelle : 100 centimes font 1 euro, 1 franc fait 1 franc.
  final int exposant;

  const Devise({
    required this.code,
    required this.symbole,
    required this.exposant,
  });

  /// Le franc CFA d'Afrique centrale, monnaie du Cameroun.
  static const xaf = Devise(code: 'XAF', symbole: 'FCFA', exposant: 0);

  static const eur = Devise(code: 'EUR', symbole: '€', exposant: 2);

  /// Combien d'unités minimales font une unité usuelle.
  int get facteur {
    var f = 1;
    for (var i = 0; i < exposant; i++) {
      f *= 10;
    }
    return f;
  }

  @override
  bool operator ==(Object other) => other is Devise && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => code;
}

/// Un taux exprimé en dix-millièmes, pour que 19,25 % reste exact.
///
/// La TVA camerounaise est de 19,25 % — 17,5 % plus 1,75 % de centimes
/// additionnels communaux. Un taux entier en pourcent ne sait pas
/// l'écrire, et un `double` le représente approximativement. En
/// dix-millièmes, 19,25 % vaut exactement 1925.
class Taux {
  /// Le taux en dix-millièmes : 1925 pour 19,25 %.
  final int pourDixMille;

  const Taux(this.pourDixMille);

  /// Depuis un pourcentage écrit comme on le prononce : `Taux.pourCent(19.25)`.
  ///
  /// Le `double` n'existe que le temps de l'appel — il est converti en
  /// entier immédiatement, et c'est l'entier qui est conservé.
  factory Taux.pourCent(num pourcentage) =>
      Taux((pourcentage * 100).round());

  static const zero = Taux(0);

  /// La TVA en vigueur au Cameroun.
  static const tvaCameroun = Taux(1925);

  double get enPourCent => pourDixMille / 100;

  @override
  bool operator ==(Object other) =>
      other is Taux && other.pourDixMille == pourDixMille;

  @override
  int get hashCode => pourDixMille.hashCode;

  @override
  String toString() => '${enPourCent.toStringAsFixed(2)} %';
}

/// Une somme d'argent dans une devise donnée.
class Montant implements Comparable<Montant> {
  /// La valeur, en unités minimales de [devise].
  final int unites;

  final Devise devise;

  const Montant(this.unites, {this.devise = Devise.xaf});

  static const zero = Montant(0);

  /// Depuis l'unité usuelle : `Montant.depuisUnite(1500)` vaut 1 500 FCFA.
  factory Montant.depuisUnite(num valeur, {Devise devise = Devise.xaf}) =>
      Montant((valeur * devise.facteur).round(), devise: devise);

  bool get estZero => unites == 0;
  bool get estNegatif => unites < 0;

  Montant operator +(Montant autre) {
    _memeDevise(autre);
    return Montant(unites + autre.unites, devise: _deviseResultat(autre));
  }

  Montant operator -(Montant autre) {
    _memeDevise(autre);
    return Montant(unites - autre.unites, devise: _deviseResultat(autre));
  }

  Montant operator -() => Montant(-unites, devise: devise);

  /// Multiplication par une quantité entière : trois articles à 500.
  ///
  /// Exacte par construction, aucun arrondi n'intervient.
  Montant operator *(int quantite) =>
      Montant(unites * quantite, devise: devise);

  /// La part de ce montant que représente [taux].
  ///
  /// Arrondi au plus proche, les demis s'éloignant de zéro — la règle
  /// que suit une caisse : 0,5 monte à 1, et -0,5 descend à -1, pour
  /// qu'un remboursement soit l'exact miroir de la vente.
  Montant appliquer(Taux taux) {
    final produit = unites * taux.pourDixMille;
    return Montant(_diviserArrondi(produit, 10000), devise: devise);
  }

  /// Ce montant augmenté de [taux] : un prix HT devient TTC.
  Montant majorerDe(Taux taux) => this + appliquer(taux);

  /// Ce montant diminué de [taux] : appliquer une remise.
  Montant minorerDe(Taux taux) => this - appliquer(taux);

  /// Retrouve le montant hors taxe d'un TTC soumis à [taux].
  ///
  /// Ce n'est pas `minorerDe` : retirer 19,25 % de 1 193 ne redonne pas
  /// le HT, il faut diviser par 1,1925. Confondre les deux est l'erreur
  /// classique sur un ticket saisi TTC.
  Montant horsTaxe(Taux taux) {
    final diviseur = 10000 + taux.pourDixMille;
    return Montant(_diviserArrondi(unites * 10000, diviseur), devise: devise);
  }

  /// Division entière au plus proche, demis éloignés de zéro.
  static int _diviserArrondi(int numerateur, int denominateur) {
    final signe = numerateur.isNegative ? -1 : 1;
    final absolu = numerateur.abs();
    return signe * ((absolu + denominateur ~/ 2) ~/ denominateur);
  }

  /// Zéro n'a pas de devise : additionner des euros à un total parti de
  /// [zero] donne des euros. Sans cela, tout cumul devrait connaître sa
  /// devise avant d'avoir additionné quoi que ce soit.
  Devise _deviseResultat(Montant autre) =>
      estZero ? autre.devise : devise;

  void _memeDevise(Montant autre) {
    // Un zéro se laisse additionner à n'importe quoi : c'est l'élément
    // neutre, il ne prétend rien sur la devise du total.
    if (estZero || autre.estZero) return;
    if (autre.devise != devise) {
      throw ArgumentError(
        'Addition de devises différentes : $devise et ${autre.devise}. '
        'Convertissez avant de calculer.',
      );
    }
  }

  @override
  int compareTo(Montant other) {
    _memeDevise(other);
    return unites.compareTo(other.unites);
  }

  bool operator <(Montant autre) => compareTo(autre) < 0;
  bool operator <=(Montant autre) => compareTo(autre) <= 0;
  bool operator >(Montant autre) => compareTo(autre) > 0;
  bool operator >=(Montant autre) => compareTo(autre) >= 0;

  /// Tel qu'il s'affiche : « 1 500 FCFA ».
  String formate({bool avecSymbole = true}) {
    final format = NumberFormat.decimalPatternDigits(
      locale: 'fr_FR',
      decimalDigits: devise.exposant,
    );
    final texte = format.format(unites / devise.facteur);
    return avecSymbole ? '$texte ${devise.symbole}' : texte;
  }

  @override
  bool operator ==(Object other) =>
      other is Montant && other.unites == unites && other.devise == devise;

  @override
  int get hashCode => Object.hash(unites, devise);

  @override
  String toString() => formate();
}
