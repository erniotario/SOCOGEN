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

  const CompanySettings({
    this.id = 1,
    this.name = 'SOCOGEN',
    this.address = '',
    this.city = '',
    this.phone = '',
    this.email = '',
    this.website = '',
    this.taxId = '',
    this.rccm = '',
    this.logoPath = '',
  });

  factory CompanySettings.fromMap(Map<String, Object?> map) {
    return CompanySettings(
      id: map['id'] as int? ?? 1,
      name: (map['name'] as String?) ?? 'SOCOGEN',
      address: (map['address'] as String?) ?? '',
      city: (map['city'] as String?) ?? '',
      phone: (map['phone'] as String?) ?? '',
      email: (map['email'] as String?) ?? '',
      website: (map['website'] as String?) ?? '',
      taxId: (map['tax_id'] as String?) ?? '',
      rccm: (map['rccm'] as String?) ?? '',
      logoPath: (map['logo_path'] as String?) ?? '',
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
    );
  }
}
