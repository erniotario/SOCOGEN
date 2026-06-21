-- SOCOGEN clean schema (Flutter rewrite)
-- Drops legacy/unused products.store_id and products.initial_stock columns
-- (data lives in product_stocks instead).

CREATE TABLE stores (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE
);

CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    password_salt TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'magasinier'
);

CREATE TABLE products (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    reference TEXT NOT NULL UNIQUE,
    designation TEXT NOT NULL,
    unit TEXT DEFAULT 'unité'
);

CREATE TABLE product_stocks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
    initial_stock INTEGER DEFAULT 0,
    UNIQUE(product_id, store_id)
);

CREATE TABLE stock_entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    supplier TEXT DEFAULT '',
    reference TEXT NOT NULL,
    designation TEXT NOT NULL,
    store_id INTEGER NOT NULL REFERENCES stores(id),
    quantity INTEGER NOT NULL
);

CREATE TABLE stock_outputs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    reference TEXT NOT NULL,
    designation TEXT NOT NULL,
    invoice_number TEXT DEFAULT '',
    store_id INTEGER NOT NULL REFERENCES stores(id),
    destination TEXT DEFAULT '',
    quantity INTEGER NOT NULL
);

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
);
