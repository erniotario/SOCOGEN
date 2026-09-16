/// Clean schema (mirrors scripts/schema.sql, plus the v2 sync
/// columns/tables added for the local Wi-Fi synchronisation feature).
///
/// Used only as a fallback when the seeded asset database
/// (assets/db/socogen_seed.db) is unavailable and the app must
/// create an empty database from scratch.
class AppSchema {
  AppSchema._();

  static const int version = 4;

  static const List<String> createStatements = [
    '''
    CREATE TABLE stores (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      updated_at TEXT
    )
    ''',
    '''
    CREATE TABLE users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT NOT NULL UNIQUE,
      password_hash TEXT NOT NULL,
      password_salt TEXT NOT NULL,
      role TEXT NOT NULL DEFAULT 'magasinier'
    )
    ''',
    '''
    CREATE TABLE products (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      reference TEXT NOT NULL UNIQUE,
      designation TEXT NOT NULL,
      unit TEXT DEFAULT 'unité',
      famille_id INTEGER REFERENCES familles(id) ON DELETE SET NULL,
      tva_id INTEGER REFERENCES taux_tva(id) ON DELETE SET NULL,
      prix_achat INTEGER,
      prix_vente INTEGER,
      code_barre TEXT,
      actif INTEGER NOT NULL DEFAULT 1,
      updated_at TEXT
    )
    ''',
    '''
    CREATE TABLE familles (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      code TEXT NOT NULL UNIQUE,
      nom TEXT NOT NULL,
      parent_id INTEGER REFERENCES familles(id) ON DELETE SET NULL,
      ordre INTEGER DEFAULT 0,
      updated_at TEXT
    )
    ''',
    '''
    CREATE TABLE taux_tva (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      code TEXT NOT NULL UNIQUE,
      libelle TEXT NOT NULL,
      pour_dix_mille INTEGER NOT NULL,
      is_defaut INTEGER DEFAULT 0,
      updated_at TEXT
    )
    ''',
    '''
    CREATE TABLE product_stocks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
      store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
      initial_stock INTEGER DEFAULT 0,
      updated_at TEXT,
      UNIQUE(product_id, store_id)
    )
    ''',
    '''
    CREATE TABLE stock_entries (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT NOT NULL,
      supplier TEXT DEFAULT '',
      reference TEXT NOT NULL,
      designation TEXT NOT NULL,
      store_id INTEGER NOT NULL REFERENCES stores(id),
      quantity INTEGER NOT NULL,
      sync_id TEXT,
      updated_at TEXT
    )
    ''',
    '''
    CREATE TABLE stock_outputs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT NOT NULL,
      reference TEXT NOT NULL,
      designation TEXT NOT NULL,
      invoice_number TEXT DEFAULT '',
      store_id INTEGER NOT NULL REFERENCES stores(id),
      destination TEXT DEFAULT '',
      quantity INTEGER NOT NULL,
      sync_id TEXT,
      updated_at TEXT
    )
    ''',
    '''
    CREATE TABLE company_settings (
      id INTEGER PRIMARY KEY,
      name TEXT DEFAULT '',
      address TEXT DEFAULT '',
      city TEXT DEFAULT 'Yaoundé, Cameroun',
      phone TEXT DEFAULT '',
      email TEXT DEFAULT '',
      website TEXT DEFAULT '',
      tax_id TEXT DEFAULT '',
      rccm TEXT DEFAULT '',
      logo_path TEXT DEFAULT '',
      devise TEXT NOT NULL DEFAULT 'XAF'
    )
    ''',
    '''
    CREATE TABLE sync_tombstones (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      table_name TEXT NOT NULL,
      merge_key TEXT NOT NULL,
      deleted_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE sync_meta (
      key TEXT PRIMARY KEY,
      value TEXT
    )
    ''',
  ];

  /// Applied via `onUpgrade` when an existing v1 database (already
  /// installed on a user's device) is opened. Adds the columns/tables
  /// needed for the local Wi-Fi synchronisation feature without losing
  /// any existing data.
  static const List<String> migrationV1ToV2 = [
    'ALTER TABLE stores ADD COLUMN updated_at TEXT',
    'ALTER TABLE products ADD COLUMN updated_at TEXT',
    'ALTER TABLE product_stocks ADD COLUMN updated_at TEXT',
    'ALTER TABLE stock_entries ADD COLUMN sync_id TEXT',
    'ALTER TABLE stock_entries ADD COLUMN updated_at TEXT',
    'ALTER TABLE stock_outputs ADD COLUMN sync_id TEXT',
    'ALTER TABLE stock_outputs ADD COLUMN updated_at TEXT',
    '''
    CREATE TABLE sync_tombstones (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      table_name TEXT NOT NULL,
      merge_key TEXT NOT NULL,
      deleted_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE sync_meta (
      key TEXT PRIMARY KEY,
      value TEXT
    )
    ''',
  ];

  /// Applied via `onUpgrade` on a database created before the catalogue
  /// carried prices.
  ///
  /// Les prix arrivent **nullables** et c'est délibéré : les 723 articles
  /// déjà en base n'ont pas de prix, et zéro voudrait dire « gratuit ».
  /// La même distinction que celle entre un stock nul et un stock
  /// négatif — quand la valeur est inconnue, on le dit au lieu d'en
  /// inventer une.
  ///
  /// `ALTER TABLE ... ADD COLUMN` ne retourne aucune ligne, donc passe
  /// par `execute` sans tomber sur la règle Android qui interdit les
  /// requêtes répondantes.
  static const List<String> migrationV3ToV4 = [
    '''
    CREATE TABLE IF NOT EXISTS familles (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      code TEXT NOT NULL UNIQUE,
      nom TEXT NOT NULL,
      parent_id INTEGER REFERENCES familles(id) ON DELETE SET NULL,
      ordre INTEGER DEFAULT 0,
      updated_at TEXT
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS taux_tva (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      code TEXT NOT NULL UNIQUE,
      libelle TEXT NOT NULL,
      pour_dix_mille INTEGER NOT NULL,
      is_defaut INTEGER DEFAULT 0,
      updated_at TEXT
    )
    ''',
    'ALTER TABLE products ADD COLUMN famille_id INTEGER REFERENCES familles(id)',
    'ALTER TABLE products ADD COLUMN tva_id INTEGER REFERENCES taux_tva(id)',
    'ALTER TABLE products ADD COLUMN prix_achat INTEGER',
    'ALTER TABLE products ADD COLUMN prix_vente INTEGER',
    'ALTER TABLE products ADD COLUMN code_barre TEXT',
    'ALTER TABLE products ADD COLUMN actif INTEGER NOT NULL DEFAULT 1',
    "ALTER TABLE company_settings ADD COLUMN devise TEXT NOT NULL DEFAULT 'XAF'",
  ];

  /// Les taux servis à une base neuve comme à une base migrée.
  ///
  /// Ceux du Cameroun, parce que c'est le marché de cette application :
  /// 19,25 % est le taux normal — 17,5 % plus 1,75 % de centimes
  /// additionnels communaux — et l'exonération existe pour les produits
  /// de première nécessité, qui sont le quotidien d'un grossiste
  /// alimentaire. Tous deux sont modifiables ; ce sont des valeurs de
  /// départ, pas une règle figée.
  static const List<String> tauxTvaParDefaut = [
    "INSERT OR IGNORE INTO taux_tva (code, libelle, pour_dix_mille, is_defaut) "
        "VALUES ('NORMAL', 'TVA 19,25 %', 1925, 1)",
    "INSERT OR IGNORE INTO taux_tva (code, libelle, pour_dix_mille, is_defaut) "
        "VALUES ('EXONERE', 'Exonéré', 0, 0)",
  ];

  /// Movements are matched to products by `reference`, not by id, and the
  /// Rapports screen sums them per (reference, store). Without these the
  /// report scans both movement tables once per product/store pair, which
  /// on a real catalogue means minutes of work and an unresponsive app.
  ///
  /// Applied on create, on upgrade, and to the seeded asset database,
  /// which ships without them.
  static const List<String> createIndexStatements = [
    'CREATE INDEX IF NOT EXISTS idx_stock_entries_ref_store '
        'ON stock_entries(reference, store_id)',
    'CREATE INDEX IF NOT EXISTS idx_stock_outputs_ref_store '
        'ON stock_outputs(reference, store_id)',
    'CREATE INDEX IF NOT EXISTS idx_stock_entries_date ON stock_entries(date)',
    'CREATE INDEX IF NOT EXISTS idx_stock_outputs_date ON stock_outputs(date)',
    'CREATE INDEX IF NOT EXISTS idx_product_stocks_store '
        'ON product_stocks(store_id)',
    'CREATE INDEX IF NOT EXISTS idx_products_famille ON products(famille_id)',
    'CREATE INDEX IF NOT EXISTS idx_products_code_barre '
        'ON products(code_barre)',
    'CREATE INDEX IF NOT EXISTS idx_familles_parent ON familles(parent_id)',
  ];

  /// Deliberately empty. A database starts with no magasins: a business
  /// names its own at first run, and shipping one customer's warehouses
  /// as everyone's default meant the next business opened the app to a
  /// stranger's premises. Every screen that picks a default store already
  /// guards for an empty list; `StockImportService` refuses an import
  /// until at least one exists.
  static const List<String> defaultStores = [];
}
