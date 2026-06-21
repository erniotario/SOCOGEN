"""Builds an empty/clean seed database for distribution.

Unlike build_seed_db.py (which copies the developer's live data), this
creates a fresh database with only the schema, default stores, and a
default company_settings row -- suitable for shipping to other
PCs/companies, where the new admin sets everything up via the
"create admin account" screen and Paramètres.
"""

import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCHEMA_PATH = ROOT / "scripts" / "schema.sql"
OUTPUT_PATH = ROOT / "flutter_app" / "assets" / "db" / "socogen_seed.db"

DEFAULT_STORES = ["Hysacam", "Ekie", "Elig-Essono"]


def main() -> None:
    if OUTPUT_PATH.exists():
        OUTPUT_PATH.unlink()

    schema_sql = SCHEMA_PATH.read_text(encoding="utf-8")

    conn = sqlite3.connect(OUTPUT_PATH)
    try:
        conn.executescript(schema_sql)

        conn.executemany(
            "INSERT INTO stores (name) VALUES (?)",
            [(name,) for name in DEFAULT_STORES],
        )

        conn.execute(
            "INSERT INTO company_settings (id, name) VALUES (1, 'SOCOGEN')"
        )

        conn.execute("PRAGMA user_version = 1")
        conn.commit()
        conn.execute("VACUUM")
    finally:
        conn.close()

    print(f"Wrote clean seed database to {OUTPUT_PATH} ({OUTPUT_PATH.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
