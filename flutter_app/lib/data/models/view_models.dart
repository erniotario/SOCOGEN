import 'product.dart';
import 'store.dart';

/// Status thresholds shared by the Dashboard and Reports screens.
enum StockStatus {
  enStock,
  stockFaible,
  rupture;

  static StockStatus fromCurrent(int current) {
    if (current <= 0) return StockStatus.rupture;
    if (current < 10) return StockStatus.stockFaible;
    return StockStatus.enStock;
  }

  String get label {
    switch (this) {
      case StockStatus.enStock:
        return 'En stock';
      case StockStatus.stockFaible:
        return 'Stock faible';
      case StockStatus.rupture:
        return 'Rupture';
    }
  }
}

/// One row of the Dashboard / Produits tables: a product with its
/// aggregated stock figures across all stores.
class ProductOverview {
  final Product product;
  final int initialStock;
  final int entriesTotal;
  final int outputsTotal;

  /// " / "-separated list of store names this product has stock in.
  final String storeNames;

  /// Number of product_stocks rows (stores) this product has.
  final int stockCount;

  /// id of the product's first product_stocks row (lowest id), used as the
  /// target for the Produits screen's edit/delete-one-store actions.
  final int? firstStockId;

  /// store_id of [firstStockId], pre-selected on the edit form.
  final int? firstStoreId;

  /// initial_stock of [firstStockId], pre-filled on the edit form.
  final int firstStoreInitialStock;

  const ProductOverview({
    required this.product,
    required this.initialStock,
    required this.entriesTotal,
    required this.outputsTotal,
    required this.storeNames,
    this.stockCount = 0,
    this.firstStockId,
    this.firstStoreId,
    this.firstStoreInitialStock = 0,
  });

  int get currentStock => initialStock + entriesTotal - outputsTotal;

  StockStatus get status => StockStatus.fromCurrent(currentStock);
}

/// One row of the Magasins table.
class StoreOverview {
  final Store store;
  final int productCount;
  final int totalStock;

  const StoreOverview({
    required this.store,
    required this.productCount,
    required this.totalStock,
  });
}

/// Details panel shown when a store is selected on the Magasins screen.
class StoreDetails {
  final Store store;
  final int productCount;
  final int totalEntries;
  final int totalOutputs;
  final int currentStock;

  const StoreDetails({
    required this.store,
    required this.productCount,
    required this.totalEntries,
    required this.totalOutputs,
    required this.currentStock,
  });
}

/// One row of the Rapports table: a (product x store) combination.
class ReportRow {
  final int productId;
  final String reference;
  final String designation;
  final String unit;
  final int storeId;
  final String storeName;
  final int initialStock;
  final int entries;
  final int outputs;

  const ReportRow({
    required this.productId,
    required this.reference,
    required this.designation,
    required this.unit,
    required this.storeId,
    required this.storeName,
    required this.initialStock,
    required this.entries,
    required this.outputs,
  });

  int get current => initialStock + entries - outputs;

  StockStatus get status => StockStatus.fromCurrent(current);
}

/// A store with its currently available stock for a given product
/// (used by the Sorties screen to filter the destination store list).
class StoreAvailability {
  final int storeId;
  final String storeName;
  final int initialStock;
  final int available;

  const StoreAvailability({
    required this.storeId,
    required this.storeName,
    required this.initialStock,
    required this.available,
  });
}

enum TransactionType { entry, output }

/// One row of the Transactions table, combining stock_entries and
/// stock_outputs into a single chronological feed with a running balance.
class TransactionRow {
  final TransactionType type;
  final int id;
  final String date;
  final String reference;
  final String designation;
  final String storeName;

  /// Supplier for entries, destination for outputs.
  final String partner;

  /// Empty for entries.
  final String invoiceNumber;
  final int inQty;
  final int outQty;
  int balance;

  TransactionRow({
    required this.type,
    required this.id,
    required this.date,
    required this.reference,
    required this.designation,
    required this.storeName,
    required this.partner,
    required this.invoiceNumber,
    required this.inQty,
    required this.outQty,
    this.balance = 0,
  });
}
