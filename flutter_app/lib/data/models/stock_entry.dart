class StockEntry {
  final int id;
  final String date;
  final String supplier;
  final String reference;
  final String designation;
  final int storeId;
  final int quantity;

  const StockEntry({
    required this.id,
    required this.date,
    required this.supplier,
    required this.reference,
    required this.designation,
    required this.storeId,
    required this.quantity,
  });

  factory StockEntry.fromMap(Map<String, Object?> map) {
    return StockEntry(
      id: map['id'] as int,
      date: map['date'] as String,
      supplier: (map['supplier'] as String?) ?? '',
      reference: map['reference'] as String,
      designation: map['designation'] as String,
      storeId: map['store_id'] as int,
      quantity: map['quantity'] as int,
    );
  }

  Map<String, Object?> toMap({bool includeId = true}) {
    return {
      if (includeId) 'id': id,
      'date': date,
      'supplier': supplier,
      'reference': reference,
      'designation': designation,
      'store_id': storeId,
      'quantity': quantity,
    };
  }
}
