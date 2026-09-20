import 'package:socogen/modules/catalogue/models/product.dart';
import 'package:socogen/modules/stock/models/store.dart';

/// Status thresholds shared by the Dashboard and Reports screens.
///
/// [stockNegatif] is not a threshold but an impossibility: goods cannot
/// be less than absent. It means a sortie was recorded that never
/// happened, or an entrée that was never entered -- something to settle,
/// not a state to live in. It is kept apart from [rupture] because the
/// two used to render identically, and a store with hundreds of
/// legitimately empty articles hides a negative one completely.
enum StockStatus {
  enStock,
  stockFaible,
  rupture,
  stockNegatif;

  static StockStatus fromCurrent(int current) {
    if (current < 0) return StockStatus.stockNegatif;
    if (current == 0) return StockStatus.rupture;
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
      case StockStatus.stockNegatif:
        return 'Stock négatif';
    }
  }

  /// Nothing left to take out: an empty article ([rupture]) or a ledger
  /// that says less than nothing ([stockNegatif]). The tables accent
  /// both; which of the two it is, the badge says.
  bool get isDepleted =>
      this == StockStatus.rupture || this == StockStatus.stockNegatif;
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

  /// La fiche du partenaire, quand le mouvement en a une.
  ///
  /// Portée jusqu'ici parce que Transactions peut réécrire le
  /// mouvement : sans elle, chaque modification effacerait le
  /// rattachement en silence, et une fusion déjà faite serait défaite
  /// par la première correction de quantité venue.
  final int? tiersId;

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
    this.tiersId,
    required this.invoiceNumber,
    required this.inQty,
    required this.outQty,
    this.balance = 0,
  });
}
