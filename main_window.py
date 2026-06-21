"""
main_window.py — Fenêtre principale SOCOGEN
Contient la sidebar de navigation et charge toutes les pages.
"""
import sys
from PySide6.QtWidgets import (
    QMainWindow, QWidget, QHBoxLayout, QVBoxLayout,
    QPushButton, QLabel, QStackedWidget, QFrame, QSizePolicy, QMessageBox
)
from PySide6.QtCore import Qt, QSize
from PySide6.QtGui import QFont, QColor, QIcon

# ─────────────────────────────────────────────────────────────────────────────
#  Palette
# ─────────────────────────────────────────────────────────────────────────────
_C = {
    "bg":        "#0D1117",
    "sidebar":   "#080C10",
    "surface":   "#161B22",
    "border":    "#21262D",
    "accent":    "#1F6FEB",
    "accent_lt": "#58A6FF",
    "text":      "#E6EDF3",
    "muted":     "#7D8590",
    "green":     "#3FB950",
    "red":       "#F85149",
    "hover":     "#161B22",
    "selected":  "#1C2D4A",
}

# ─────────────────────────────────────────────────────────────────────────────
#  Bouton de navigation sidebar
# ─────────────────────────────────────────────────────────────────────────────
class NavButton(QPushButton):
    def __init__(self, icon: str, label: str, parent=None):
        super().__init__(parent)
        self._icon_txt = icon
        self._label    = label
        self._active   = False
        self.setFixedHeight(44)
        self.setCheckable(False)
        self.setCursor(Qt.PointingHandCursor)
        self._refresh_style()

    def set_active(self, active: bool):
        self._active = active
        self._refresh_style()

    def _refresh_style(self):
        if self._active:
            bg      = _C["selected"]
            color   = _C["accent_lt"]
            border  = f"border-left: 3px solid {_C['accent_lt']};"
            weight  = "700"
        else:
            bg      = "transparent"
            color   = _C["muted"]
            border  = "border-left: 3px solid transparent;"
            weight  = "500"

        self.setStyleSheet(f"""
            QPushButton {{
                background: {bg};
                color: {color};
                {border}
                border-right: none;
                border-top: none;
                border-bottom: none;
                border-radius: 0;
                text-align: left;
                padding: 0 0 0 18px;
                font-size: 13px;
                font-weight: {weight};
                font-family: "Segoe UI", system-ui, sans-serif;
            }}
            QPushButton:hover {{
                background: {_C['hover']};
                color: {_C['text']};
            }}
        """)
        self.setText(f"  {self._icon_txt}   {self._label}")


# ─────────────────────────────────────────────────────────────────────────────
#  Fenêtre principale
# ─────────────────────────────────────────────────────────────────────────────
class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("SOCOGEN — Gestion de Stock")
        self.setMinimumSize(1200, 700)
        self.resize(1400, 820)
        self.setStyleSheet(f"QMainWindow {{ background: {_C['bg']}; }}")

        self._nav_buttons = []
        self._pages       = {}   # index -> widget

        self._build_ui()
        self._navigate(0)   # Ouvrir le Dashboard par défaut

    # ── Construction UI ───────────────────────────────────────────────────
    def _build_ui(self):
        central = QWidget()
        central.setStyleSheet(f"background: {_C['bg']};")
        self.setCentralWidget(central)

        root = QHBoxLayout(central)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        # ── Sidebar ──────────────────────────────────────────────────────
        sidebar = QWidget()
        sidebar.setFixedWidth(220)
        sidebar.setStyleSheet(f"""
            QWidget {{
                background: {_C['sidebar']};
                border-right: 1px solid {_C['border']};
            }}
        """)
        sb_lay = QVBoxLayout(sidebar)
        sb_lay.setContentsMargins(0, 0, 0, 0)
        sb_lay.setSpacing(0)

        # Logo / Titre
        logo_w = QWidget()
        logo_w.setFixedHeight(70)
        logo_w.setStyleSheet(f"background: {_C['sidebar']}; border-bottom: 1px solid {_C['border']};")
        logo_lay = QVBoxLayout(logo_w)
        logo_lay.setContentsMargins(20, 0, 10, 0)
        logo_lay.setSpacing(2)
        lbl_app = QLabel("SOCOGEN")
        lbl_app.setStyleSheet(f"""
            color: {_C['accent_lt']};
            font-size: 20px;
            font-weight: 800;
            font-family: "Segoe UI", system-ui;
            background: transparent;
            border: none;
        """)
        lbl_sub = QLabel("Gestion de Stock")
        lbl_sub.setStyleSheet(f"""
            color: {_C['muted']};
            font-size: 10px;
            background: transparent;
            border: none;
            letter-spacing: 1px;
        """)
        logo_lay.addStretch()
        logo_lay.addWidget(lbl_app)
        logo_lay.addWidget(lbl_sub)
        logo_lay.addStretch()
        sb_lay.addWidget(logo_w)

        # Section label
        def section_label(text):
            lbl = QLabel(text)
            lbl.setFixedHeight(32)
            lbl.setStyleSheet(f"""
                color: {_C['muted']};
                font-size: 10px;
                font-weight: 700;
                letter-spacing: 1.2px;
                padding-left: 20px;
                background: transparent;
                border: none;
            """)
            return lbl

        sb_lay.addSpacing(8)

        # ── Navigation items ──────────────────────────────────────────────
        nav_items = [
            ("📊", "Tableau de bord",  "dashboard"),
            ("📦", "Produits",         "products"),
            ("📥", "Entrées",          "entries"),
            ("📤", "Sorties",          "outputs"),
            ("🔄", "Transactions",     "transactions"),
            ("📈", "Rapports",         "reports"),
            ("🏪", "Magasins",         "stores"),
            ("⚙️",  "Paramètres",      "settings"),
        ]

        for idx, (icon, label, key) in enumerate(nav_items):
            if idx == 5:
                sb_lay.addSpacing(8)
                sb_lay.addWidget(section_label("ANALYSES"))
            elif idx == 6:
                sb_lay.addSpacing(8)
                sb_lay.addWidget(section_label("CONFIGURATION"))

            btn = NavButton(icon, label)
            btn.clicked.connect(lambda checked=False, i=idx: self._navigate(i))
            self._nav_buttons.append(btn)
            sb_lay.addWidget(btn)

        sb_lay.addStretch()

        # Version en bas
        ver_lbl = QLabel("v1.0.0  •  SHEMAB")
        ver_lbl.setFixedHeight(36)
        ver_lbl.setAlignment(Qt.AlignCenter)
        ver_lbl.setStyleSheet(f"""
            color: {_C['muted']};
            font-size: 10px;
            background: transparent;
            border-top: 1px solid {_C['border']};
            border-right: none;
            border-left: none;
            border-bottom: none;
        """)
        sb_lay.addWidget(ver_lbl)

        root.addWidget(sidebar)

        # ── Zone de contenu ───────────────────────────────────────────────
        self.stack = QStackedWidget()
        self.stack.setStyleSheet(f"background: {_C['bg']}; border: none;")
        root.addWidget(self.stack, stretch=1)

        # Charger toutes les pages
        self._load_pages(nav_items)

    # ── Chargement des pages ──────────────────────────────────────────────
    def _load_pages(self, nav_items):
        page_map = {
            "dashboard":    self._load_dashboard,
            "products":     self._load_products,
            "entries":      self._load_entries,
            "outputs":      self._load_outputs,
            "transactions": self._load_transactions,
            "reports":      self._load_reports,
            "stores":       self._load_stores,
            "settings":     self._load_settings,
        }
        for idx, (icon, label, key) in enumerate(nav_items):
            loader = page_map.get(key)
            try:
                page = loader() if loader else self._placeholder(icon, label)
            except Exception as e:
                print(f"[MainWindow] Erreur chargement page '{key}': {e}")
                page = self._error_page(label, str(e))
            self._pages[idx] = page
            self.stack.addWidget(page)

    # ── Loaders individuels ───────────────────────────────────────────────
    def _load_dashboard(self):
        try:
            from ui.dashboard_page import DashboardPage
            return DashboardPage()
        except ImportError:
            return self._placeholder("📊", "Tableau de bord")

    def _load_products(self):
        from ui.products_page import ProductsPage
        return ProductsPage()

    def _load_entries(self):
        try:
            from ui.entries_page import EntriesPage
            return EntriesPage()
        except ImportError:
            return self._placeholder("📥", "Entrées de stock")

    def _load_outputs(self):
        try:
            from ui.outputs_page import OutputsPage
            return OutputsPage()
        except ImportError:
            return self._placeholder("📤", "Sorties de stock")

    def _load_transactions(self):
        try:
            from ui.transactions_page import TransactionsPage
            return TransactionsPage()
        except ImportError:
            return self._placeholder("🔄", "Transactions")

    def _load_reports(self):
        try:
            from ui.reports_page import ReportsPage
            return ReportsPage()
        except ImportError:
            return self._placeholder("📈", "Rapports")

    def _load_stores(self):
        try:
            from ui.stores_page import StoresPage
            return StoresPage()
        except ImportError:
            return self._placeholder("🏪", "Magasins")

    def _load_settings(self):
        try:
            from ui.settings_page import SettingsPage
            return SettingsPage()
        except ImportError:
            return self._placeholder("⚙️", "Paramètres")

    # ── Navigation ────────────────────────────────────────────────────────
    def _navigate(self, index: int):
        # Mettre à jour les boutons
        for i, btn in enumerate(self._nav_buttons):
            btn.set_active(i == index)

        # Afficher la page correspondante
        if index in self._pages:
            self.stack.setCurrentWidget(self._pages[index])
            # Rafraîchir si la page a une méthode refresh()
            page = self._pages[index]
            if hasattr(page, "refresh"):
                try:
                    page.refresh()
                except Exception as e:
                    print(f"[MainWindow] refresh() erreur: {e}")

    # ── Nettoyage ─────────────────────────────────────────────────────────
    def closeEvent(self, event):
        for page in self._pages.values():
            if hasattr(page, "session") and page.session:
                try:
                    page.session.close()
                except Exception:
                    pass
        super().closeEvent(event)

    # ── Pages de remplacement ─────────────────────────────────────────────
    def _placeholder(self, icon: str, label: str) -> QWidget:
        """Page temporaire pour les modules non encore créés."""
        w = QWidget()
        w.setStyleSheet(f"background: {_C['bg']};")
        lay = QVBoxLayout(w)
        lay.setAlignment(Qt.AlignCenter)

        lbl_icon = QLabel(icon)
        lbl_icon.setAlignment(Qt.AlignCenter)
        lbl_icon.setStyleSheet("font-size: 48px; background: transparent;")

        lbl_title = QLabel(label)
        lbl_title.setAlignment(Qt.AlignCenter)
        lbl_title.setStyleSheet(f"""
            color: {_C['muted']};
            font-size: 20px;
            font-weight: 600;
            background: transparent;
        """)

        lbl_sub = QLabel("Cette page n'est pas encore disponible.")
        lbl_sub.setAlignment(Qt.AlignCenter)
        lbl_sub.setStyleSheet(f"color: {_C['muted']}; font-size: 13px; background: transparent;")

        lay.addWidget(lbl_icon)
        lay.addSpacing(10)
        lay.addWidget(lbl_title)
        lay.addSpacing(6)
        lay.addWidget(lbl_sub)
        return w

    def _error_page(self, label: str, error: str) -> QWidget:
        """Page d'erreur si une page plante au chargement."""
        w = QWidget()
        w.setStyleSheet(f"background: {_C['bg']};")
        lay = QVBoxLayout(w)
        lay.setAlignment(Qt.AlignCenter)

        lbl_icon = QLabel("⚠️")
        lbl_icon.setAlignment(Qt.AlignCenter)
        lbl_icon.setStyleSheet("font-size: 40px; background: transparent;")

        lbl_title = QLabel(f"Erreur de chargement : {label}")
        lbl_title.setAlignment(Qt.AlignCenter)
        lbl_title.setStyleSheet(f"""
            color: {_C['red']};
            font-size: 16px;
            font-weight: 600;
            background: transparent;
        """)

        lbl_err = QLabel(error)
        lbl_err.setAlignment(Qt.AlignCenter)
        lbl_err.setWordWrap(True)
        lbl_err.setMaximumWidth(600)
        lbl_err.setStyleSheet(f"color: {_C['muted']}; font-size: 12px; background: transparent;")

        lay.addWidget(lbl_icon)
        lay.addSpacing(10)
        lay.addWidget(lbl_title)
        lay.addSpacing(6)
        lay.addWidget(lbl_err)
        return w
