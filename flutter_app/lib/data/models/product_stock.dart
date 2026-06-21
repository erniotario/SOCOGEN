class ProductStock {
  final int id;
  final int productId;
  final int storeId;
  final int initialStock;

  const ProductStock({
    required this.id,
    required this.productId,
    required this.storeId,
    required this.initialStock,
  });

  factory ProductStock.fromMap(Map<String, Object?> map) {
    return ProductStock(
      id: map['id'] as int,
      productId: map['product_id'] as int,
      storeId: map['store_id'] as int,
      initialStock: (map['initial_stock'] as int?) ?? 0,
    );
  }

  Map<String, Object?> toMap({bool includeId = true}) {
    return {
      if (includeId) 'id': id,
      'product_id': productId,
      'store_id': storeId,
      'initial_stock': initialStock,
    };
  }
}
