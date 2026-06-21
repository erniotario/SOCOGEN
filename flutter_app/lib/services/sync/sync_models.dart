/// A row deleted on one device, propagated to a peer so it can delete its
/// own copy too. [mergeKey] identifies the row on both sides (a store name,
/// a product reference, a "productReference|storeName" pair, or a
/// `stock_entries`/`stock_outputs` `sync_id`).
class Tombstone {
  final String table;
  final String mergeKey;
  final String deletedAt;

  const Tombstone({
    required this.table,
    required this.mergeKey,
    required this.deletedAt,
  });

  Map<String, Object?> toJson() => {
        'table': table,
        'mergeKey': mergeKey,
        'deletedAt': deletedAt,
      };

  factory Tombstone.fromJson(Map<String, Object?> json) => Tombstone(
        table: json['table'] as String,
        mergeKey: json['mergeKey'] as String,
        deletedAt: json['deletedAt'] as String,
      );
}

/// Everything that changed (or was deleted) on a device since a given
/// timestamp. Exchanged verbatim, in both directions, during a manual sync.
class ChangeSet {
  final List<Map<String, Object?>> stores;
  final List<Map<String, Object?>> products;
  final List<Map<String, Object?>> productStocks;
  final List<Map<String, Object?>> stockEntries;
  final List<Map<String, Object?>> stockOutputs;
  final List<Tombstone> tombstones;

  const ChangeSet({
    this.stores = const [],
    this.products = const [],
    this.productStocks = const [],
    this.stockEntries = const [],
    this.stockOutputs = const [],
    this.tombstones = const [],
  });

  bool get isEmpty =>
      stores.isEmpty &&
      products.isEmpty &&
      productStocks.isEmpty &&
      stockEntries.isEmpty &&
      stockOutputs.isEmpty &&
      tombstones.isEmpty;

  /// Total number of individual records carried by this change set, used
  /// to report a summary count to the user after a sync.
  int get recordCount =>
      stores.length +
      products.length +
      productStocks.length +
      stockEntries.length +
      stockOutputs.length +
      tombstones.length;

  Map<String, Object?> toJson() => {
        'stores': stores,
        'products': products,
        'productStocks': productStocks,
        'stockEntries': stockEntries,
        'stockOutputs': stockOutputs,
        'tombstones': tombstones.map((t) => t.toJson()).toList(),
      };

  factory ChangeSet.fromJson(Map<String, Object?> json) {
    return ChangeSet(
      stores: _rows(json['stores']),
      products: _rows(json['products']),
      productStocks: _rows(json['productStocks']),
      stockEntries: _rows(json['stockEntries']),
      stockOutputs: _rows(json['stockOutputs']),
      tombstones: ((json['tombstones'] as List?) ?? const [])
          .map((e) => Tombstone.fromJson(Map<String, Object?>.from(e as Map)))
          .toList(),
    );
  }

  static List<Map<String, Object?>> _rows(Object? value) {
    return ((value as List?) ?? const [])
        .map((e) => Map<String, Object?>.from(e as Map))
        .toList();
  }
}
