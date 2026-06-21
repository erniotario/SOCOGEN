class Product {
  final int id;
  final String reference;
  final String designation;
  final String unit;

  const Product({
    required this.id,
    required this.reference,
    required this.designation,
    required this.unit,
  });

  factory Product.fromMap(Map<String, Object?> map) {
    return Product(
      id: map['id'] as int,
      reference: map['reference'] as String,
      designation: map['designation'] as String,
      unit: (map['unit'] as String?) ?? 'unité',
    );
  }

  Map<String, Object?> toMap({bool includeId = true}) {
    return {
      if (includeId) 'id': id,
      'reference': reference,
      'designation': designation,
      'unit': unit,
    };
  }

  Product copyWith({
    int? id,
    String? reference,
    String? designation,
    String? unit,
  }) {
    return Product(
      id: id ?? this.id,
      reference: reference ?? this.reference,
      designation: designation ?? this.designation,
      unit: unit ?? this.unit,
    );
  }
}
