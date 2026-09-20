/// Un client, un fournisseur, ou les deux.
///
/// Avant cette fiche, un partenaire commercial n'était qu'une chaîne
/// tapée sur chaque ligne de mouvement. Chez le premier client cela
/// donnait 129 fournisseurs distincts — et « BMC » à côté de « BCM »,
/// deux lettres interverties sur cinq mouvements. Une liste où l'on
/// choisit au lieu de retaper ne supprime pas les doublons existants,
/// mais elle arrête d'en fabriquer.
library;

/// Ce qu'un tiers est pour l'entreprise.
///
/// Un même partenaire peut être les deux : un grossiste achète parfois
/// à qui il vend. Le distinguer évite d'avoir deux fiches pour une
/// seule relation commerciale.
enum TypeTiers {
  client('client', 'Client'),
  fournisseur('fournisseur', 'Fournisseur'),
  lesDeux('les_deux', 'Client et fournisseur');

  const TypeTiers(this.code, this.libelle);

  /// Valeur stockée en base. Distincte du nom Dart pour que renommer
  /// l'un n'oblige pas à migrer l'autre.
  final String code;

  final String libelle;

  bool get estClient => this == client || this == lesDeux;
  bool get estFournisseur => this == fournisseur || this == lesDeux;

  /// Lit la valeur stockée. Une valeur inconnue — base écrite par une
  /// version plus récente, ou modifiée à la main — est lue comme client
  /// plutôt que de faire échouer le chargement de l'écran.
  static TypeTiers depuisCode(String? code) => values.firstWhere(
        (t) => t.code == code,
        orElse: () => client,
      );
}

class Tiers {
  final int id;

  /// Code court et stable — C0130, F0028. C'est lui qu'on retrouve sur
  /// un document ou un export, pas l'identifiant technique.
  final String code;

  /// Raison sociale ou nom. C'est aussi la clé par laquelle les
  /// mouvements déjà saisis ont été rattachés lors de la reprise.
  final String nom;

  final TypeTiers type;

  /// Numéro d'Identifiant Unique — l'identifiant fiscal camerounais.
  final String? niu;

  /// Registre du Commerce et du Crédit Mobilier.
  final String? rccm;

  final String? telephone;
  final String? email;
  final String? ville;
  final String? adresse;

  /// Encours maximum autorisé, en unités minimales de la devise.
  ///
  /// Null veut dire « pas de plafond », pas « plafond à zéro » : la
  /// même distinction que pour un prix. Un plafond à zéro interdirait
  /// toute vente à crédit, ce qui est une décision, pas un défaut.
  final int? plafondCreditUnites;

  /// Un tiers retiré reste en base — ses mouvements le référencent —
  /// mais ne se propose plus à la saisie.
  final bool actif;

  final String? notes;

  const Tiers({
    required this.id,
    required this.code,
    required this.nom,
    this.type = TypeTiers.client,
    this.niu,
    this.rccm,
    this.telephone,
    this.email,
    this.ville,
    this.adresse,
    this.plafondCreditUnites,
    this.actif = true,
    this.notes,
  });

  bool get aUnPlafond => plafondCreditUnites != null;

  factory Tiers.fromMap(Map<String, Object?> map) {
    return Tiers(
      id: map['id'] as int,
      code: map['code'] as String,
      nom: map['nom'] as String,
      type: TypeTiers.depuisCode(map['type'] as String?),
      niu: map['niu'] as String?,
      rccm: map['rccm'] as String?,
      telephone: map['telephone'] as String?,
      email: map['email'] as String?,
      ville: map['ville'] as String?,
      adresse: map['adresse'] as String?,
      plafondCreditUnites: (map['plafond_credit'] as num?)?.toInt(),
      actif: ((map['actif'] as int?) ?? 1) == 1,
      notes: map['notes'] as String?,
    );
  }

  Map<String, Object?> toMap({bool includeId = true}) {
    return {
      if (includeId) 'id': id,
      'code': code,
      'nom': nom,
      'type': type.code,
      'niu': niu,
      'rccm': rccm,
      'telephone': telephone,
      'email': email,
      'ville': ville,
      'adresse': adresse,
      'plafond_credit': plafondCreditUnites,
      'actif': actif ? 1 : 0,
      'notes': notes,
    };
  }

  /// Les drapeaux `effacer*` existent parce que null signifie déjà « ne
  /// change rien » : sans eux, on ne pourrait jamais retirer un plafond
  /// ou vider un numéro fiscal.
  Tiers copyWith({
    int? id,
    String? code,
    String? nom,
    TypeTiers? type,
    String? niu,
    String? rccm,
    String? telephone,
    String? email,
    String? ville,
    String? adresse,
    int? plafondCreditUnites,
    bool effacerPlafond = false,
    bool? actif,
    String? notes,
  }) {
    return Tiers(
      id: id ?? this.id,
      code: code ?? this.code,
      nom: nom ?? this.nom,
      type: type ?? this.type,
      niu: niu ?? this.niu,
      rccm: rccm ?? this.rccm,
      telephone: telephone ?? this.telephone,
      email: email ?? this.email,
      ville: ville ?? this.ville,
      adresse: adresse ?? this.adresse,
      plafondCreditUnites: effacerPlafond
          ? null
          : (plafondCreditUnites ?? this.plafondCreditUnites),
      actif: actif ?? this.actif,
      notes: notes ?? this.notes,
    );
  }
}
