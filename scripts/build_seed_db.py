"""
Build the Flutter seed database from the live socogen_stock.db.

Reads socogen_stock.db (read-only) and writes a clean copy at
flutter_app/assets/db/socogen_seed.db using scripts/schema.sql,
dropping the legacy products.store_id / products.initial_stock columns.
"""
import os
import sqlite3

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))

SRC_PATH = os.path.join(ROOT, "socogen_stock.db")
SCHEMA_PATH = os.path.join(SCRIPTS_DIR, "schema.sql")
DST_DIR = os.path.join(ROOT, "flutter_app", "assets", "db")
DST_PATH = os.path.join(DST_DIR, "socogen_seed.db")

TABLES = [
    "stores",
    "users",
    "products",
    "product_stocks",
    "stock_entries",
    "stock_outputs",
    "company_settings",
]


def main():
    os.makedirs(DST_DIR, exist_ok=True)
    if os.path.exists(DST_PATH):
        os.remove(DST_PATH)

    src = sqlite3.connect(f"file:{SRC_PATH}?mode=ro", uri=True)
    src.row_factory = sqlite3.Row

    dst = sqlite3.connect(DST_PATH)
    with open(SCHEMA_PATH, "r", encoding="utf-8") as f:
        dst.executescript(f.read())

    for row in src.execute("SELECT id, name FROM stores"):
        dst.execute(
            "INSERT INTO stores (id, name) VALUES (?, ?)",
            (row["id"], row["name"]),
        )

    for row in src.execute(
        "SELECT id, username, password_hash, password_salt, role FROM users"
    ):
        dst.execute(
            "INSERT INTO users (id, username, password_hash, password_salt, role) "
            "VALUES (?, ?, ?, ?, ?)",
            (row["id"], row["username"], row["password_hash"], row["password_salt"], row["role"]),
        )

    for row in src.execute("SELECT id, reference, designation, unit FROM products"):
        dst.execute(
            "INSERT INTO products (id, reference, designation, unit) VALUES (?, ?, ?, ?)",
            (row["id"], row["reference"], row["designation"], row["unit"]),
        )

    # Skip orphan rows whose product_id no longer exists in products
    # (pre-existing data quirk in the source DB, harmless and invisible
    # in the app since every screen joins product_stocks -> products).
    for row in src.execute(
        "SELECT id, product_id, store_id, initial_stock FROM product_stocks "
        "WHERE product_id IN (SELECT id FROM products)"
    ):
        dst.execute(
            "INSERT INTO product_stocks (id, product_id, store_id, initial_stock) "
            "VALUES (?, ?, ?, ?)",
            (row["id"], row["product_id"], row["store_id"], row["initial_stock"] or 0),
        )

    for row in src.execute(
        "SELECT id, date, supplier, reference, designation, store_id, quantity FROM stock_entries"
    ):
        dst.execute(
            "INSERT INTO stock_entries (id, date, supplier, reference, designation, store_id, quantity) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            (
                row["id"],
                row["date"],
                row["supplier"] or "",
                row["reference"],
                row["designation"],
                row["store_id"],
                row["quantity"],
            ),
        )

    for row in src.execute(
        "SELECT id, date, reference, designation, invoice_number, store_id, destination, quantity "
        "FROM stock_outputs"
    ):
        dst.execute(
            "INSERT INTO stock_outputs "
            "(id, date, reference, designation, invoice_number, store_id, destination, quantity) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (
                row["id"],
                row["date"],
                row["reference"],
                row["designation"],
                row["invoice_number"] or "",
                row["store_id"],
                row["destination"] or "",
                row["quantity"],
            ),
        )

    for row in src.execute(
        "SELECT id, name, address, city, phone, email, website, tax_id, rccm, logo_path "
        "FROM company_settings"
    ):
        dst.execute(
            "INSERT INTO company_settings "
            "(id, name, address, city, phone, email, website, tax_id, rccm, logo_path) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                row["id"],
                row["name"],
                row["address"],
                row["city"],
                row["phone"],
                row["email"],
                row["website"],
                row["tax_id"],
                row["rccm"],
                row["logo_path"],
            ),
        )

    dst.commit()
    # Mark schema version so sqflite opens the seeded copy as-is
    # (matches AppSchema.version in lib/data/db/schema.dart) without
    # triggering onCreate/onUpgrade.
    dst.execute("PRAGMA user_version = 1")
    dst.execute("VACUUM")

    print("Row counts (source -> seed):")
    all_ok = True
    for t in TABLES:
        src_count = src.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
        dst_count = dst.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
        if t == "product_stocks":
            orphans = src.execute(
                "SELECT COUNT(*) FROM product_stocks "
                "WHERE product_id NOT IN (SELECT id FROM products)"
            ).fetchone()[0]
            ok = dst_count == src_count - orphans
            note = f"  ({orphans} orphan rows skipped)" if orphans else ""
        else:
            ok = src_count == dst_count
            note = ""
        all_ok = all_ok and ok
        print(f"  {t:18s} {src_count:5d} -> {dst_count:5d}  {'OK' if ok else 'MISMATCH'}{note}")

    fk_violations = dst.execute("PRAGMA foreign_key_check").fetchall()
    print("Remaining FK violations:", len(fk_violations))
    all_ok = all_ok and not fk_violations

    cs = dst.execute("SELECT city FROM company_settings WHERE id = 1").fetchone()
    print("company_settings.city:", cs[0] if cs else None)

    units = dst.execute(
        "SELECT DISTINCT unit FROM products ORDER BY unit"
    ).fetchall()
    print("Distinct units:", [u[0] for u in units])

    user_row = dst.execute(
        "SELECT username, length(password_hash), length(password_salt) FROM users LIMIT 1"
    ).fetchone()
    print("Sample user (username, hash_len, salt_len):", tuple(user_row) if user_row else None)

    src.close()
    dst.close()
    print()
    print("All counts match." if all_ok else "WARNING: count mismatch detected!")
    print("Seed DB written to:", DST_PATH)


if __name__ == "__main__":
    main()
