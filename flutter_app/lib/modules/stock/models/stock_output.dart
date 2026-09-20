class StockOutput {
  final int id;
  final String date;
  final String reference;
  final String designation;
  final String invoiceNumber;
  final int storeId;
  final String destination;
  final int quantity;

  /// Le partenaire de ce mouvement, quand il est connu.
  ///
  /// Nul est une valeur normale : un mouvement peut n'avoir jamais été
  /// rattaché, et le nom en clair ci-dessus reste alors la seule trace.
  /// Ce nom ne bouge jamais, même après un renommage ou une fusion —
  /// une ligne passée doit continuer de dire ce qui a été saisi ce
  /// jour-là.
  final int? tiersId;

  const StockOutput({
    required this.id,
    required this.date,
    required this.reference,
    required this.designation,
    required this.invoiceNumber,
    required this.storeId,
    required this.destination,
    required this.quantity,
    this.tiersId,
  });

  factory StockOutput.fromMap(Map<String, Object?> map) {
    return StockOutput(
      id: map['id'] as int,
      date: map['date'] as String,
      reference: map['reference'] as String,
      designation: map['designation'] as String,
      invoiceNumber: (map['invoice_number'] as String?) ?? '',
      storeId: map['store_id'] as int,
      destination: (map['destination'] as String?) ?? '',
      quantity: map['quantity'] as int,
      tiersId: map['tiers_id'] as int?,
    );
  }

  Map<String, Object?> toMap({bool includeId = true}) {
    return {
      if (includeId) 'id': id,
      'date': date,
      'reference': reference,
      'designation': designation,
      'invoice_number': invoiceNumber,
      'store_id': storeId,
      'destination': destination,
      'quantity': quantity,
      'tiers_id': tiersId,
    };
  }
}
