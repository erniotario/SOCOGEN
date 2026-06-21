import os
import sys
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base

# ── Chemin de la base de données ──────────────────────────────────────
# En mode .exe (installé)   : AppData\Roaming\SHEMAB\SOCOGEN\
# En mode développement     : sous-dossier dev_data\ dans le projet
if getattr(sys, 'frozen', False):
    BASE_DIR = os.path.join(os.environ.get('APPDATA', os.path.expanduser('~')), 'SHEMAB', 'SOCOGEN')
else:
    BASE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'dev_data')

os.makedirs(BASE_DIR, exist_ok=True)

DATABASE_URL = f"sqlite:///{os.path.join(BASE_DIR, 'socogen_stock.db')}"

engine = create_engine(DATABASE_URL, echo=False)
SessionLocal = sessionmaker(bind=engine)
Base = declarative_base()