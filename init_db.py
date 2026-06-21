from database import Base, engine, SessionLocal
from models import Store

Base.metadata.create_all(bind=engine)

session = SessionLocal()

stores = ["Hysacam", "Ekie", "Elig-Essono"]

for name in stores:
    if not session.query(Store).filter_by(name=name).first():
        session.add(Store(name=name))

session.commit()
session.close()
print("Base initialisée avec succès.")
