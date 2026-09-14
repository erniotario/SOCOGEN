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

/// Raised when two databases claimed by different businesses try to
/// sync.
///
/// Carries its own French message because a storekeeper reads it, not a
/// log: it says which device is wrong and that nothing was exchanged.
class TenantMismatch implements Exception {
  const TenantMismatch();

  String get message =>
      'Cet appareil appartient à une autre entreprise. '
      'Synchronisation annulée : aucune donnée '
      "n'a été échangée.";

  @override
  String toString() => message;
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

  /// Which business this change set belongs to. Null from a device that has
  /// not been claimed yet; the peer settles it on first contact.
  final String? tenantId;

  const ChangeSet({
    this.stores = const [],
    this.products = const [],
    this.productStocks = const [],
    this.stockEntries = const [],
    this.stockOutputs = const [],
    this.tombstones = const [],
    this.tenantId,
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

  /// The same changes, stamped with the identity of the business sending
  /// them.
  ChangeSet withTenant(String? id) => ChangeSet(
        stores: stores,
        products: products,
        productStocks: productStocks,
        stockEntries: stockEntries,
        stockOutputs: stockOutputs,
        tombstones: tombstones,
        tenantId: id,
      );

  Map<String, Object?> toJson() => {
        'stores': stores,
        'products': products,
        'productStocks': productStocks,
        'stockEntries': stockEntries,
        'stockOutputs': stockOutputs,
        'tombstones': tombstones.map((t) => t.toJson()).toList(),
        'tenantId': tenantId,
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
      // Absent from a peer running a build older than the tenant check.
      tenantId: json['tenantId'] as String?,
    );
  }

  static List<Map<String, Object?>> _rows(Object? value) {
    return ((value as List?) ?? const [])
        .map((e) => Map<String, Object?>.from(e as Map))
        .toList();
  }
}
