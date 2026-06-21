"""
Migration : introduit la table product_stocks et migre initial_stock + store_id
depuis products vers product_stocks. La colonne store_id est ensuite supprimée
de products (via recréation de la table).

Usage :
    python migrate_products.py
    python migrate_products.py chemin/vers/ma_base.db
"""

import sys
import sqlite3
import shutil
from datetime import datetime
from pathlib import Path


def find_db() -> Path:
    if len(sys.argv) > 1:
        p = Path(sys.argv[1])
        if not p.exists():
            sys.exit(f"[ERREUR] Fichier introuvable : {p}")
        return p
    candidates = [c for c in Path(".").glob("**/*.db") if "backup" not in c.name]
    if not candidates:
        sys.exit("[ERREUR] Aucun fichier .db trouvé. Passez le chemin en argument.")
    if len(candidates) > 1:
        print("[INFO] Plusieurs bases trouvées :")
        for i, c in enumerate(candidates):
            print(f"  {i}) {c}")
        idx = int(input("Choisissez le numéro : "))
        return candidates[idx]
    return candidates[0]


def migrate(db_path: Path):
    # Sauvegarde
    ts     = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup = db_path.with_name(f"{db_path.stem}_backup_{ts}.db")
    shutil.copy2(db_path, backup)
    print(f"[OK] Sauvegarde : {backup}")

    con = sqlite3.connect(db_path)
    con.execute("PRAGMA foreign_keys = OFF")
    cur = con.cursor()

    try:
        # Vérifier si déjà migré
        cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='product_stocks'")
        if cur.fetchone():
            print("[INFO] Migration déjà appliquée. Rien à faire.")
            return

        print("[...] Lecture des produits existants…")
        cur.execute("SELECT id, reference, designation, unit, initial_stock, store_id FROM products")
        produits = cur.fetchall()
        print(f"[INFO] {len(produits)} produit(s) trouvé(s).")

        # 1. Créer la table product_stocks
        print("[...] Création de la table product_stocks…")
        cur.execute("""
            CREATE TABLE product_stocks (
                id            INTEGER PRIMARY KEY,
                product_id    INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
                store_id      INTEGER NOT NULL REFERENCES stores(id)  ON DELETE CASCADE,
                initial_stock INTEGER DEFAULT 0,
                CONSTRAINT uq_productstock_product_store UNIQUE (product_id, store_id)
            )
        """)

        # 2. Migrer initial_stock + store_id vers product_stocks
        print("[...] Migration des stocks…")
        migres = 0
        for p_id, ref, des, unit, initial_stock, store_id in produits:
            if store_id is not None:
                cur.execute(
                    "INSERT OR IGNORE INTO product_stocks (product_id, store_id, initial_stock) VALUES (?, ?, ?)",
                    (p_id, store_id, initial_stock or 0)
                )
                migres += 1
        print(f"[OK] {migres} ligne(s) insérée(s) dans product_stocks.")

        # 3. Recréer products SANS store_id ni initial_stock
        print("[...] Recréation de la table products sans store_id…")
        cur.executescript("""
            ALTER TABLE products RENAME TO products_old;

            CREATE TABLE products (
                id          INTEGER PRIMARY KEY,
                reference   TEXT    NOT NULL UNIQUE,
                designation TEXT    NOT NULL,
                unit        TEXT    DEFAULT 'unité'
            );
        """)

        cur.executemany(
            "INSERT INTO products (id, reference, designation, unit) VALUES (?, ?, ?, ?)",
            [(p[0], p[1], p[2], p[3]) for p in produits]
        )
        cur.execute("DROP TABLE products_old")

        con.commit()
        print("[OK] Migration terminée avec succès.")
        print()
        print("Résumé :")
        print(f"  - {len(produits)} produit(s) conservé(s) dans 'products'")
        print(f"  - {migres} stock(s) migré(s) dans 'product_stocks'")
        print()
        print("Remplacez maintenant models.py et products_page.py puis relancez l'application.")

    except Exception as e:
        con.rollback()
        print(f"[ERREUR] {e}")
        print(f"[INFO] Restaurez la sauvegarde si nécessaire : {backup}")
        raise
    finally:
        con.execute("PRAGMA foreign_keys = ON")
        con.close()


if __name__ == "__main__":
    db_path = find_db()
    print(f"[INFO] Base : {db_path}")
    migrate(db_path)