/// Clean SOCOGEN schema (mirrors scripts/schema.sql, plus the v2 sync
/// columns/tables added for the local Wi-Fi synchronisation feature).
///
/// Used only as a fallback when the seeded asset database
/// (assets/db/socogen_seed.db) is unavailable and the app must
/// create an empty database from scratch.
class AppSchema {
  AppSchema._();

  static const int version = 2;

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
      name TEXT DEFAULT 'SOCOGEN',
      address TEXT DEFAULT '',
      city TEXT DEFAULT 'Yaoundé, Cameroun',
      phone TEXT DEFAULT '',
      email TEXT DEFAULT '',
      website TEXT DEFAULT '',
      tax_id TEXT DEFAULT '',
      rccm TEXT DEFAULT '',
      logo_path TEXT DEFAULT ''
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

  static const List<String> defaultStores = [
    'Hysacam',
    'Ekie',
    'Elig-Essono',
  ];
}
