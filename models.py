from sqlalchemy import Column, Integer, String, ForeignKey, UniqueConstraint
from database import Base


class Store(Base):
    __tablename__ = "stores"
    id   = Column(Integer, primary_key=True)
    name = Column(String, unique=True, nullable=False)


class User(Base):
    __tablename__ = "users"
    id            = Column(Integer, primary_key=True)
    username      = Column(String, unique=True, nullable=False)
    password_hash = Column(String, nullable=False)
    password_salt = Column(String, nullable=False)
    role          = Column(String, nullable=False, default="magasinier")


class Product(Base):
    __tablename__ = "products"
    id            = Column(Integer, primary_key=True)
    reference     = Column(String, unique=True, nullable=False)
    designation   = Column(String, nullable=False)
    unit          = Column(String, default="unité")
    initial_stock = Column(Integer, default=0)
    store_id      = Column(Integer, ForeignKey("stores.id"))
    # Le stock par magasin est dans ProductStock


class ProductStock(Base):
    """Stock initial d'un produit dans un magasin donné."""
    __tablename__ = "product_stocks"
    id            = Column(Integer, primary_key=True)
    product_id    = Column(Integer, ForeignKey("products.id", ondelete="CASCADE"), nullable=False)
    store_id      = Column(Integer, ForeignKey("stores.id",   ondelete="CASCADE"), nullable=False)
    initial_stock = Column(Integer, default=0)

    __table_args__ = (
        UniqueConstraint("product_id", "store_id", name="uq_productstock_product_store"),
    )


class StockEntry(Base):
    __tablename__ = "stock_entries"
    id          = Column(Integer, primary_key=True)
    date        = Column(String, nullable=False)
    supplier    = Column(String, default="")
    reference   = Column(String, nullable=False)
    designation = Column(String, nullable=False)
    store_id    = Column(Integer, ForeignKey("stores.id"), nullable=False)
    quantity    = Column(Integer, nullable=False)


class StockOutput(Base):
    __tablename__ = "stock_outputs"
    id             = Column(Integer, primary_key=True)
    date           = Column(String, nullable=False)
    reference      = Column(String, nullable=False)
    designation    = Column(String, nullable=False)
    invoice_number = Column(String, default="")
    store_id       = Column(Integer, ForeignKey("stores.id"), nullable=False)
    destination    = Column(String, default="")
    quantity       = Column(Integer, nullable=False)


class CompanySettings(Base):
    """Paramètres de la société — une seule ligne (id=1)."""
    __tablename__ = "company_settings"
    id        = Column(Integer, primary_key=True, default=1)
    name      = Column(String, default="SOCOGEN")
    address   = Column(String, default="")
    city      = Column(String, default="Yaoundé, Cameroun")
    phone     = Column(String, default="")
    email     = Column(String, default="")
    website   = Column(String, default="")
    tax_id    = Column(String, default="")
    rccm      = Column(String, default="")
    logo_path = Column(String, default="")