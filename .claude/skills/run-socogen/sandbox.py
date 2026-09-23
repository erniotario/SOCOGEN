"""Stand up a throwaway, fully isolated copy of a built SM runner.

Why this exists
---------------
Two facts about this app make driving it awkward, and this script is the
answer to both.

1. **It gates on a login and keeps no session.** `AuthProvider` has no
   persistence, so every launch lands on the login screen, and the only
   account in a developer's database belongs to a real person whose
   password you do not have. This adds a throwaway account rather than
   resetting or guessing anybody's.

2. **The database lives beside the executable on Windows.**
   `DatabaseService._resolveDatabasePath()` uses the directory of
   `Platform.resolvedExecutable`, so `build/windows/x64/runner/Debug/
   socogen_stock.db` *is* the developer's working data, not build junk.
   (That filename survived the rename to SM on purpose: changing it
   would read as a brand-new install with no stock in it.)
   Driving the app in place would write real movements into it. Copying
   the whole runner folder gives an instance whose writes -- including a
   validated inventory -- cannot reach it.

The copy is disposable: delete the directory when finished.

Usage:
    python .claude/skills/run-socogen/sandbox.py <runner-dir> <dest-dir>

Stdlib only, so any Python 3 on the machine will do.
"""

import hashlib
import os
import shutil
import secrets
import sqlite3
import sys

USER = "verif"
PASSWORD = "verif1234"


def build(src: str, dest: str) -> None:
    if not os.path.isfile(os.path.join(src, "ERP.exe")):
        sys.exit(f"no ERP.exe in {src} -- build the app first")

    if os.path.exists(dest):
        shutil.rmtree(dest)
    shutil.copytree(src, dest)
    print(f"copied runner -> {dest}")

    db_path = os.path.join(dest, "socogen_stock.db")
    if not os.path.exists(db_path):
        print("no database beside the exe; the app will seed one on first launch")
        print(f"\nlogin: first launch will ask you to create the admin account")
        return

    # A copied -wal/-shm pair describes the *original* file. Dropping
    # them makes the copy open on exactly what was committed.
    for suffix in ("-wal", "-shm"):
        stray = db_path + suffix
        if os.path.exists(stray):
            os.remove(stray)

    db = sqlite3.connect(db_path)

    # Mirrors lib/auth/password_hasher.dart:
    #   sha256(salt + password), salt = 16 random bytes as hex.
    salt = secrets.token_hex(16)
    digest = hashlib.sha256((salt + PASSWORD).encode()).hexdigest()

    # Every real account is removed from the copy, leaving only the
    # throwaway. Keeping them invites two failures: the automation can
    # authenticate as a real person if a stray keystroke lands, and --
    # worse for anyone reading the screenshots -- a session that is
    # actually the throwaway can be mistaken for theirs. The copy is
    # disposable, so nothing is lost by emptying the table.
    db.execute("DELETE FROM users")
    db.execute(
        "INSERT INTO users (username, password_hash, password_salt, role) "
        "VALUES (?, ?, ?, 'admin')",
        (USER, digest, salt),
    )
    db.commit()

    accounts = [r[0] for r in db.execute("SELECT username FROM users")]
    products = db.execute("SELECT COUNT(*) FROM products").fetchone()[0]
    print(f"accounts: {accounts}")
    print(f"products: {products}")

    # Current stock is derived, never stored: opening + entrées - sorties.
    balances = db.execute(
        """
        SELECT p.reference, s.name,
               ps.initial_stock + COALESCE(e.total, 0) - COALESCE(o.total, 0)
        FROM product_stocks ps
        JOIN products p ON p.id = ps.product_id
        JOIN stores s ON s.id = ps.store_id
        LEFT JOIN (SELECT reference, store_id, SUM(quantity) total
                   FROM stock_entries GROUP BY reference, store_id) e
          ON e.reference = p.reference AND e.store_id = ps.store_id
        LEFT JOIN (SELECT reference, store_id, SUM(quantity) total
                   FROM stock_outputs GROUP BY reference, store_id) o
          ON o.reference = p.reference AND o.store_id = ps.store_id
        """
    ).fetchall()
    negatives = sorted((r for r in balances if r[2] < 0), key=lambda r: r[2])
    print(f"(product, magasin) pairs: {len(balances)}  negative: {len(negatives)}")
    for row in negatives[:5]:
        print(f"    {row[0]} / {row[1]}: {row[2]}")
    db.close()

    print(f"\nlogin: {USER} / {PASSWORD}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    build(sys.argv[1], sys.argv[2])
