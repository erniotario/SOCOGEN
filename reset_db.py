import os
import sys

from database import BASE_DIR

DB_PATH = os.path.join(BASE_DIR, "socogen_stock.db")

if __name__ == "__main__":
    if os.path.exists(DB_PATH):
        print(f"Suppression de la base existante : {DB_PATH}")
        os.remove(DB_PATH)
    else:
        print(f"Aucune base existante trouvée à : {DB_PATH}")

    print("Réinitialisation de la base de données...")
    try:
        import init_db  # noqa: F401
        print("Base de données réinitialisée avec succès.")
    except Exception as e:
        print("Échec de l'initialisation de la base de données :", e)
        sys.exit(1)
