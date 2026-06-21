import sys
from database import Base, engine, SessionLocal
from models import Store, CompanySettings

# Ensure tables exist and default stores are seeded
Base.metadata.create_all(bind=engine)
_s = SessionLocal()
for name in ["Hysacam", "Ekie", "Elig-Essono"]:
    if not _s.query(Store).filter_by(name=name).first():
        _s.add(Store(name=name))
if not _s.get(CompanySettings, 1):
    _s.add(CompanySettings(id=1, name="SOCOGEN", city="Yaoundé, Cameroun"))
_s.commit()
_s.close()

# Migrations
try:
    from sqlalchemy import text
    with engine.connect() as conn:
        cols = [row[1] for row in conn.execute(text("PRAGMA table_info(products)"))]
        if "store_id" not in cols:
            conn.execute(text("ALTER TABLE products ADD COLUMN store_id INTEGER REFERENCES stores(id)"))
            conn.commit()
        if "initial_stock" not in cols:
            conn.execute(text("ALTER TABLE products ADD COLUMN initial_stock INTEGER DEFAULT 0"))
            conn.commit()
except Exception as e:
    print(f"[Migration] {e}")

try:
    from qt_main import run_qt_app
    qt_available = True
except ImportError:
    qt_available = False

from customtkinter_main import run_customtk_app

if __name__ == "__main__":
    try:
        if qt_available:
            run_qt_app()
        else:
            print("PySide6 n'est pas disponible. Démarrage avec CustomTkinter...")
            run_customtk_app()
    except Exception as e:
        import traceback
        error_msg = f"Erreur application: {str(e)}\n\nTraceback:\n{traceback.format_exc()}"
        print(error_msg)
        import logging
        logging.basicConfig(filename='app_errors.log', level=logging.ERROR)
        logging.error(error_msg)
