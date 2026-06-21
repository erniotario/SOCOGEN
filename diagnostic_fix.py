"""
Diagnostic + correction de la contrainte UNIQUE sur la table products.
Exécuter depuis le dossier socogen_v2 :
    py diagnostic_fix.py
"""
import sqlite3
import shutil
import sys
from datetime import datetime
from pathlib import Path


def find_db() -> Path:
    if len(sys.argv) > 1:
        p = Path(sys.argv[1])
        if not p.exists():
            sys.exit(f"[ERREUR] Fichier introuvable : {p}")
        return p
    candidates = [c for c in Path(".").glob("*.db") if "backup" not in c.name]
    if not candidates:
        sys.exit("[ERREUR] Aucun fichier .db trouvé.")
    if len(candidates) > 1:
        print("[INFO] Plusieurs bases trouvées :")
        for i, c in enumerate(candidates):
            print(f"  {i}) {c}")
        idx = int(input("Choisissez le numéro : "))
        return candidates[idx]
    return candidates[0]


def main():
    db_path = find_db()
    print(f"\n{'='*60}")
    print(f"  BASE DE DONNÉES : {db_path}")
    print(f"{'='*60}\n")

    con = sqlite3.connect(db_path)
    cur = con.cursor()

    # ── 1. Afficher la structure réelle de la table products ──────────────
    print("── STRUCTURE ACTUELLE DE LA TABLE products ──")
    cur.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='products'")
    row = cur.fetchone()
    if row:
        print(row[0])
    else:
        print("[ERREUR] Table 'products' introuvable !")
        con.close()
        return

    print()

    # ── 2. Afficher les index existants ───────────────────────────────────
    print("── INDEX SUR products ──")
    cur.execute("PRAGMA index_list(products)")
    indexes = cur.fetchall()
    if indexes:
        for idx in indexes:
            print(f"  {idx}")
            cur.execute(f"PRAGMA index_info('{idx[1]}')")
            for col in cur.fetchall():
                print(f"    colonne : {col[2]}")
    else:
        print("  (aucun index externe)")

    print()

    # ── 3. Diagnostic ─────────────────────────────────────────────────────
    create_sql = row[0].upper()
    has_composite = "UQ_PRODUCT_REFERENCE_STORE" in create_sql or \
                    ("UNIQUE" in create_sql and "STORE_ID" in create_sql)
    has_old_unique = 'REFERENCE" TEXT    NOT NULL UNIQUE' in row[0] or \
                     "reference TEXT NOT NULL UNIQUE" in row[0].lower() or \
                     ("unique" in row[0].lower() and "store_id" not in row[0].lower()
                      and "reference" in row[0].lower())

    print("── DIAGNOSTIC ──")
    if has_composite:
        print("  ✅ Contrainte UNIQUE(reference, store_id) en place.")
        print("  Le problème vient du code Python, pas de la base.")
        print("  → Vérifiez que vous utilisez bien le products_page.py corrigé.")
    else:
        print("  ❌ Ancienne contrainte UNIQUE(reference) encore active !")
        print("  → Lancement de la correction automatique…\n")
        fix(db_path, con, cur)

    con.close()


def fix(db_path: Path, con, cur):
    # Sauvegarde
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup = db_path.with_name(f"{db_path.stem}_backup_{ts}.db")
    shutil.copy2(db_path, backup)
    print(f"  [OK] Sauvegarde : {backup}")

    con.execute("PRAGMA foreign_keys = OFF")

    try:
        # Lire toutes les colonnes disponibles
        cur.execute("PRAGMA table_info(products)")
        cols_info = cur.fetchall()
        col_names = [c[1] for c in cols_info]
        print(f"  [INFO] Colonnes : {col_names}")

        # Construire le SELECT selon les colonnes présentes
        select_parts = []
        for c in ["id", "reference", "designation", "unit"]:
            select_parts.append(c if c in col_names else f"NULL AS {c}")
        select_parts.append("initial_stock" if "initial_stock" in col_names else "0 AS initial_stock")
        select_parts.append("store_id" if "store_id" in col_names else "NULL AS store_id")

        cur.execute(f"SELECT {', '.join(select_parts)} FROM products")
        raw_rows = cur.fetchall()
        print(f"  [INFO] {len(raw_rows)} produit(s) lu(s).")

        # Dédupliquer sur (reference, store_id)
        seen = {}
        duplicates = 0
        for row in raw_rows:
            key = (row[1], row[5])  # (reference, store_id)
            if key not in seen:
                seen[key] = row
            else:
                duplicates += 1
                print(f"  [DOUBLON] id={row[0]} ref={row[1]} store_id={row[5]} → ignoré")

        deduped = list(seen.values())
        if duplicates:
            print(f"  [INFO] {duplicates} doublon(s) éliminé(s).")

        # Recréer la table
        print("  [...] Recréation de la table avec UNIQUE(reference, store_id)…")
        cur.executescript("""
            DROP TABLE IF EXISTS products_old;
            ALTER TABLE products RENAME TO products_old;

            CREATE TABLE products (
                id            INTEGER PRIMARY KEY,
                reference     TEXT    NOT NULL,
                designation   TEXT    NOT NULL,
                unit          TEXT    DEFAULT 'unité',
                initial_stock INTEGER DEFAULT 0,
                store_id      INTEGER REFERENCES stores(id),
                CONSTRAINT uq_product_reference_store
                    UNIQUE (reference, store_id)
            );
        """)

        cur.executemany(
            "INSERT INTO products (id, reference, designation, unit, initial_stock, store_id) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            deduped
        )
        cur.execute("DROP TABLE products_old")
        con.commit()

        print(f"\n  ✅ Correction réussie — {len(deduped)} produit(s) conservé(s).")
        print("  Relancez votre application : py main.py\n")

    except Exception as e:
        con.rollback()
        print(f"\n  ❌ ERREUR : {e}")
        raise
    finally:
        con.execute("PRAGMA foreign_keys = ON")


if __name__ == "__main__":
    main()
