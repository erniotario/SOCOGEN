import 'package:socogen/shared/models/view_models.dart';

class CompanySettings {
  final int id;
  final String name;
  final String address;
  final String city;
  final String phone;
  final String email;
  final String website;
  final String taxId;
  final String rccm;
  final String logoPath;

  /// Code ISO de la devise dans laquelle l'entreprise compte — XAF par
  /// défaut. Elle décide de la façon dont les montants se comptent et
  /// s'affichent ; voir `core/money`.
  final String devise;

  /// Le seuil d'alerte appliqué aux articles qui n'en déclarent pas.
  ///
  /// Dix : ce que le code appliquait en dur à tout le catalogue avant
  /// que le seuil devienne une propriété de l'article.
  final int seuilStockParDefaut;

  const CompanySettings({
    this.id = 1,
    this.name = '',
    this.address = '',
    this.city = '',
    this.phone = '',
    this.email = '',
    this.website = '',
    this.taxId = '',
    this.rccm = '',
    this.logoPath = '',
    this.devise = 'XAF',
    this.seuilStockParDefaut = StockStatus.seuilParDefaut,
  });

  factory CompanySettings.fromMap(Map<String, Object?> map) {
    return CompanySettings(
      id: map['id'] as int? ?? 1,
      name: (map['name'] as String?) ?? '',
      address: (map['address'] as String?) ?? '',
      city: (map['city'] as String?) ?? '',
      phone: (map['phone'] as String?) ?? '',
      email: (map['email'] as String?) ?? '',
      website: (map['website'] as String?) ?? '',
      taxId: (map['tax_id'] as String?) ?? '',
      rccm: (map['rccm'] as String?) ?? '',
      logoPath: (map['logo_path'] as String?) ?? '',
      // Une base d'avant la v4 n'a pas la colonne.
      devise: (map['devise'] as String?) ?? 'XAF',
      // Ni une base d'avant la v6 celle-ci.
      seuilStockParDefaut: (map['stock_min_defaut'] as num?)?.toInt() ??
          StockStatus.seuilParDefaut,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'city': city,
      'phone': phone,
      'email': email,
      'website': website,
      'tax_id': taxId,
      'rccm': rccm,
      'logo_path': logoPath,
      'devise': devise,
      'stock_min_defaut': seuilStockParDefaut,
    };
  }

  CompanySettings copyWith({
    String? name,
    String? address,
    String? city,
    String? phone,
    String? email,
    String? website,
    String? taxId,
    String? rccm,
    String? logoPath,
    String? devise,
    int? seuilStockParDefaut,
  }) {
    return CompanySettings(
      id: id,
      name: name ?? this.name,
      address: address ?? this.address,
      city: city ?? this.city,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      website: website ?? this.website,
      taxId: taxId ?? this.taxId,
      rccm: rccm ?? this.rccm,
      logoPath: logoPath ?? this.logoPath,
      devise: devise ?? this.devise,
      seuilStockParDefaut:
          seuilStockParDefaut ?? this.seuilStockParDefaut,
    );
  }
}
