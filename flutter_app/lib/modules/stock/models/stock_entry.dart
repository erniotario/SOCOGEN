class StockEntry {
  final int id;
  final String date;
  final String supplier;
  final String reference;
  final String designation;
  final int storeId;
  final int quantity;

  /// Le partenaire de ce mouvement, quand il est connu.
  ///
  /// Nul est une valeur normale : un mouvement peut n'avoir jamais été
  /// rattaché, et le nom en clair ci-dessus reste alors la seule trace.
  /// Ce nom ne bouge jamais, même après un renommage ou une fusion —
  /// une ligne passée doit continuer de dire ce qui a été saisi ce
  /// jour-là.
  final int? tiersId;

  /// Le transfert dont ce mouvement fait partie, s'il y en a un.
  ///
  /// C'est ce lien qui distingue un déplacement entre magasins d'une
  /// vente ou d'un achat : sans lui, la même caisse se lit comme une
  /// perte ici et une aubaine là.
  final int? transfertId;

  const StockEntry({
    required this.id,
    required this.date,
    required this.supplier,
    required this.reference,
    required this.designation,
    required this.storeId,
    required this.quantity,
    this.tiersId,
    this.transfertId,
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
      tiersId: map['tiers_id'] as int?,
      transfertId: map['transfert_id'] as int?,
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
      'tiers_id': tiersId,
      'transfert_id': transfertId,
    };
  }
}
