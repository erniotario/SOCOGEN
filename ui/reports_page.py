"""
Page Rapport des Produits
─────────────────────────
Affiche un tableau récapitulatif par produit avec :
  - Stock initial, entrées totales, sorties totales, stock actuel
  - Filtres : magasin, statut de stock, recherche texte
  - Export CSV
"""
import csv
import os
from datetime import date

from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QLabel, QLineEdit,
    QComboBox, QTableWidget, QTableWidgetItem,
    QHeaderView, QFileDialog, QPushButton, QFrame, QGraphicsDropShadowEffect,
    QMessageBox
)
from PySide6.QtCore import Qt, QSize
from PySide6.QtGui import QColor, QFont, QPainter, QLinearGradient
from sqlalchemy import func

from database import SessionLocal
from models import Product, ProductStock, StockEntry, StockOutput, Store
from ui.utils import hline, make_btn, page_header, configure_table


# ═══════════════════════════════════════════════════════════════════════════
#  Palette
# ═══════════════════════════════════════════════════════════════════════════
P = {
    "bg_base":        "#080C10",
    "bg_surface":     "#0D1117",
    "bg_elevated":    "#161B22",
    "bg_highlight":   "#1C2128",
    "bg_hover":       "#21262D",

    "border":         "#21262D",
    "border_subtle":  "#161B22",
    "border_focus":   "#388BFD",

    "text_primary":   "#E6EDF3",
    "text_secondary": "#8B949E",
    "text_muted":     "#484F58",
    "text_disabled":  "#30363D",

    "accent_blue":    "#388BFD",
    "accent_blue_lt": "#58A6FF",
    "accent_green":   "#3FB950",
    "accent_red":     "#F85149",
    "accent_orange":  "#D29922",
    "accent_purple":  "#BC8CFF",
}

APP_STYLE = f"""
QWidget {{
    background-color: {P['bg_surface']};
    color: {P['text_primary']};
    font-family: "Segoe UI", "SF Pro Text", system-ui, sans-serif;
    font-size: 13px;
}}

/* ── Buttons ── */
QPushButton {{
    background-color: {P['bg_elevated']};
    color: {P['text_primary']};
    border: 1px solid {P['border']};
    border-radius: 6px;
    padding: 7px 16px;
    font-size: 12px;
    font-weight: 500;
    min-width: 80px;
}}
QPushButton:hover {{
    background-color: {P['bg_hover']};
    border-color: {P['text_muted']};
}}
QPushButton:pressed {{
    background-color: {P['bg_base']};
}}
#btn_primary {{
    background-color: {P['accent_blue']};
    color: white;
    border: 1px solid {P['accent_blue']};
    font-weight: 600;
}}
#btn_primary:hover {{
    background-color: {P['accent_blue_lt']};
    border-color: {P['accent_blue_lt']};
}}

/* ── Inputs ── */
QLineEdit {{
    background: transparent;
    border: none;
    color: {P['text_primary']};
    font-size: 13px;
    padding: 8px 0;
    selection-background-color: {P['accent_blue']};
}}
QLineEdit::placeholder {{
    color: {P['text_muted']};
}}

/* ── ComboBox ── */
QComboBox {{
    background-color: {P['bg_elevated']};
    border: 1px solid {P['border']};
    border-radius: 6px;
    padding: 7px 10px;
    color: {P['text_primary']};
    font-size: 12px;
    min-width: 100px;
}}
QComboBox:hover {{ border-color: {P['text_muted']}; }}
QComboBox:focus {{ border-color: {P['border_focus']}; }}
QComboBox::drop-down {{ border: none; width: 24px; }}
QComboBox::down-arrow {{
    image: none;
    border-left: 4px solid transparent;
    border-right: 4px solid transparent;
    border-top: 5px solid {P['text_secondary']};
    width: 0; height: 0; margin-right: 6px;
}}
QComboBox QAbstractItemView {{
    background-color: {P['bg_elevated']};
    border: 1px solid {P['border']};
    selection-background-color: {P['bg_hover']};
    color: {P['text_primary']};
    padding: 4px; outline: none;
}}

/* ── Table ── */
QTableWidget {{
    background-color: {P['bg_surface']};
    alternate-background-color: {P['bg_elevated']};
    gridline-color: {P['border_subtle']};
    border: 1px solid {P['border']};
    border-radius: 8px;
    selection-background-color: {P['bg_hover']};
    outline: none;
}}
QTableWidget::item {{
    padding: 0px 10px;
    border-bottom: 1px solid {P['border_subtle']};
    min-height: 38px;
}}
QTableWidget::item:selected {{
    background-color: {P['bg_hover']};
    color: {P['text_primary']};
}}
QHeaderView::section {{
    background-color: {P['bg_elevated']};
    color: {P['text_muted']};
    border: none;
    border-bottom: 1px solid {P['border']};
    border-right: 1px solid {P['border_subtle']};
    padding: 9px 10px;
    font-size: 10px;
    font-weight: 700;
    letter-spacing: 0.8px;
    text-transform: uppercase;
}}
QHeaderView::section:first {{ border-top-left-radius: 8px; }}
QHeaderView::section:last  {{ border-top-right-radius: 8px; border-right: none; }}

QScrollBar:vertical {{
    background: {P['bg_base']}; width: 8px; border-radius: 4px; margin: 0;
}}
QScrollBar::handle:vertical {{
    background: {P['border']}; border-radius: 4px; min-height: 30px;
}}
QScrollBar::handle:vertical:hover {{ background: {P['text_muted']}; }}
QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {{ height: 0; }}
QScrollBar:horizontal {{
    background: {P['bg_base']}; height: 8px; border-radius: 4px; margin: 0;
}}
QScrollBar::handle:horizontal {{
    background: {P['border']}; border-radius: 4px; min-width: 30px;
}}
QScrollBar::handle:horizontal:hover {{ background: {P['text_muted']}; }}
QScrollBar::add-line:horizontal, QScrollBar::sub-line:horizontal {{ width: 0; }}

/* ── Labels ── */
#field_label {{
    color: {P['text_muted']};
    font-size: 10px; font-weight: 700;
    letter-spacing: 0.8px; text-transform: uppercase;
    background: transparent;
}}
#page_title {{
    color: {P['text_primary']};
    font-size: 15px; font-weight: 700; background: transparent;
}}
#page_sub {{
    color: {P['text_muted']};
    font-size: 11px; background: transparent;
}}

/* ── Panels ── */
#filter_panel {{
    background-color: {P['bg_elevated']};
    border: 1px solid {P['border']};
    border-radius: 8px;
}}
#search_box {{
    background-color: {P['bg_surface']};
    border: 1px solid {P['border']};
    border-radius: 6px;
}}
#search_box:focus-within {{
    border-color: {P['border_focus']};
    background-color: {P['bg_highlight']};
}}
#kpi_card {{
    background-color: {P['bg_elevated']};
    border: 1px solid {P['border']};
    border-radius: 10px;
}}
#stat_chip {{
    background-color: {P['bg_elevated']};
    border: 1px solid {P['border']};
    border-radius: 20px;
}}

/* ── Separator ── */
QFrame[frameShape="4"], QFrame[frameShape="5"] {{
    color: {P['border']}; background-color: {P['border']};
    border: none; max-height: 1px;
}}
"""


# ═══════════════════════════════════════════════════════════════════════════
#  UI Helpers
# ═══════════════════════════════════════════════════════════════════════════

def _sep_h():
    line = QFrame()
    line.setFrameShape(QFrame.HLine)
    line.setFrameShadow(QFrame.Plain)
    line.setFixedHeight(1)
    line.setStyleSheet(f"background: {P['border']}; border: none;")
    return line


def _sep_v():
    sep = QFrame()
    sep.setFrameShape(QFrame.VLine)
    sep.setFixedWidth(1)
    sep.setFixedHeight(20)
    sep.setStyleSheet(f"background: {P['border']}; border: none;")
    return sep


def _action_btn(text, obj_name=None, tooltip=None):
    btn = QPushButton(text)
    if obj_name:
        btn.setObjectName(obj_name)
    if tooltip:
        btn.setToolTip(tooltip)
    btn.setFixedHeight(32)
    return btn


# ═══════════════════════════════════════════════════════════════════════════
#  ReportsPage
# ═══════════════════════════════════════════════════════════════════════════
class ReportsPage(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.session = SessionLocal()
        self._full_data = []
        self.setStyleSheet(APP_STYLE)
        self._build_ui()

    # ── Build UI ──────────────────────────────────────────────────────────
    def _build_ui(self):
        root = QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        # ── Action buttons ─────────────────────────────────────────────
        self.btn_export  = _action_btn("⬇  Exporter CSV", "btn_primary", "Exporter le rapport en CSV")
        self.btn_refresh = _action_btn("↺  Actualiser",   None,          "Rafraîchir les données")
        self.btn_export.clicked.connect(self._export_csv)
        self.btn_refresh.clicked.connect(self.refresh)

        root.addWidget(self._build_header())
        root.addWidget(_sep_h())

        # ── Content ────────────────────────────────────────────────────
        content = QWidget()
        content.setStyleSheet(f"background: {P['bg_base']};")
        cl = QVBoxLayout(content)
        cl.setContentsMargins(24, 18, 24, 22)
        cl.setSpacing(14)
        root.addWidget(content, 1)

        cl.addWidget(self._build_filters())
        cl.addLayout(self._build_kpi_row())
        cl.addLayout(self._build_table_header())
        cl.addWidget(self._build_table(), 1)

        self._load_store_filter()
        self.refresh()

    # ── Header ────────────────────────────────────────────────────────────
    def _build_header(self):
        w = QWidget()
        w.setFixedHeight(56)
        w.setStyleSheet(
            f"background: {P['bg_surface']}; border-bottom: 1px solid {P['border']};"
        )
        lay = QHBoxLayout(w)
        lay.setContentsMargins(24, 0, 20, 0)
        lay.setSpacing(12)

        title_grp = QWidget(); title_grp.setStyleSheet("background: transparent;")
        tgl = QVBoxLayout(title_grp); tgl.setContentsMargins(0,0,0,0); tgl.setSpacing(1)
        t = QLabel("Rapport des Produits"); t.setObjectName("page_title")
        s = QLabel("État des stocks par produit et par magasin"); s.setObjectName("page_sub")
        tgl.addWidget(t); tgl.addWidget(s)

        lay.addWidget(title_grp)
        lay.addStretch()
        for btn in [self.btn_refresh, self.btn_export]:
            lay.addWidget(btn)
        return w

    # ── Filters ───────────────────────────────────────────────────────────
    def _build_filters(self):
        panel = QWidget(); panel.setObjectName("filter_panel")
        fl = QHBoxLayout(panel)
        fl.setContentsMargins(14, 10, 14, 10)
        fl.setSpacing(10)

        # Search
        sb = QWidget(); sb.setObjectName("search_box")
        sbl = QHBoxLayout(sb); sbl.setContentsMargins(10, 0, 10, 0); sbl.setSpacing(6)
        icon = QLabel("⌕")
        icon.setStyleSheet(f"background:transparent; font-size:15px; color:{P['text_muted']};")
        self.f_search = QLineEdit()
        self.f_search.setPlaceholderText("Rechercher ref, désignation…")
        self.f_search.setMinimumWidth(220)
        self.f_search.textChanged.connect(self._apply_filters)
        sbl.addWidget(icon); sbl.addWidget(self.f_search)
        fl.addWidget(sb, 3)

        fl.addWidget(_sep_v())

        lbl_store = QLabel("MAGASIN"); lbl_store.setObjectName("field_label")
        self.f_store_filter = QComboBox()
        self.f_store_filter.setMinimumWidth(150)
        self.f_store_filter.currentIndexChanged.connect(self._apply_filters)
        fl.addWidget(lbl_store); fl.addWidget(self.f_store_filter)

        fl.addWidget(_sep_v())

        lbl_status = QLabel("STATUT"); lbl_status.setObjectName("field_label")
        self.f_status_filter = QComboBox()
        self.f_status_filter.addItems(["Tous", "En stock", "Stock faible", "Rupture"])
        self.f_status_filter.setMinimumWidth(140)
        self.f_status_filter.currentIndexChanged.connect(self._apply_filters)
        fl.addWidget(lbl_status); fl.addWidget(self.f_status_filter)

        fl.addStretch()
        return panel

    # ── KPI row ───────────────────────────────────────────────────────────
    def _build_kpi_row(self):
        row = QHBoxLayout(); row.setSpacing(10)
        self._card_total   = self._kpi_card("Produits total",  "0",  P["accent_blue_lt"],   "▣")
        self._card_ok      = self._kpi_card("En stock",        "0",  P["accent_green"],     "●")
        self._card_low     = self._kpi_card("Stock faible",    "0",  P["accent_orange"],    "◐")
        self._card_rupture = self._kpi_card("Rupture de stock","0",  P["accent_red"],       "○")
        for w, _ in [self._card_total, self._card_ok, self._card_low, self._card_rupture]:
            row.addWidget(w)
        return row

    def _kpi_card(self, label, value, color, symbol):
        card = QWidget(); card.setObjectName("kpi_card")
        lay = QHBoxLayout(card); lay.setContentsMargins(18, 14, 18, 14); lay.setSpacing(14)

        # Symbol
        sym = QLabel(symbol)
        sym.setFixedSize(36, 36)
        sym.setAlignment(Qt.AlignCenter)
        sym.setStyleSheet(
            f"color: {color}; font-size: 18px; background: transparent;"
        )
        lay.addWidget(sym)

        # Text
        col = QWidget(); col.setStyleSheet("background: transparent;")
        cl  = QVBoxLayout(col); cl.setContentsMargins(0,0,0,0); cl.setSpacing(2)
        lbl = QLabel(label.upper())
        lbl.setObjectName("field_label")
        val = QLabel(value)
        val.setStyleSheet(f"color:{color}; font-size:22px; font-weight:700; background:transparent;")
        cl.addWidget(lbl); cl.addWidget(val)
        lay.addWidget(col); lay.addStretch()
        return card, val

    # ── Table header row ──────────────────────────────────────────────────
    def _build_table_header(self):
        row = QHBoxLayout(); row.setSpacing(0)

        lbl = QLabel("DÉTAIL PAR PRODUIT"); lbl.setObjectName("field_label")
        self.result_count = QLabel("")
        self.result_count.setStyleSheet(
            f"color: {P['text_muted']}; background: transparent; font-size:11px;"
        )
        row.addWidget(lbl); row.addStretch(); row.addWidget(self.result_count)
        return row

    # ── Table ─────────────────────────────────────────────────────────────
    def _build_table(self):
        self.table = QTableWidget()
        self.table.setColumnCount(9)
        self.table.setHorizontalHeaderLabels([
            "RÉFÉRENCE", "DÉSIGNATION", "UNITÉ", "MAGASIN",
            "STOCK INITIAL", "ENTRÉES", "SORTIES", "STOCK ACTUEL", "STATUT"
        ])
        self.table.setShowGrid(False)
        self.table.setAlternatingRowColors(True)
        self.table.setSelectionBehavior(QTableWidget.SelectRows)
        self.table.setEditTriggers(QTableWidget.NoEditTriggers)
        self.table.verticalHeader().setVisible(False)
        self.table.verticalHeader().setDefaultSectionSize(40)
        hh = self.table.horizontalHeader()
        hh.setStretchLastSection(False)
        hh.setSectionResizeMode(QHeaderView.Interactive)
        hh.setSectionResizeMode(1, QHeaderView.Stretch)
        for col, w in {0:120, 2:70, 3:130, 4:105, 5:80, 6:80, 7:105, 8:115}.items():
            self.table.setColumnWidth(col, w)
        return self.table

    # ──────────────────────────────────────────────
    def _load_store_filter(self):
        try:
            self.session.expire_all()
            self.f_store_filter.blockSignals(True)
            self.f_store_filter.clear()
            self.f_store_filter.addItem("Tous les magasins", None)
            for s in self.session.query(Store).order_by(Store.name).all():
                self.f_store_filter.addItem(s.name, s.id)
            self.f_store_filter.blockSignals(False)
        except Exception as e:
            print(f"[Reports] _load_store_filter: {e}")

    # ──────────────────────────────────────────────
    def refresh(self):
        self._load_store_filter()
        try:
            self.session.expire_all()
            # Une ligne par (produit × magasin) via ProductStock
            rows = (
                self.session.query(Product, ProductStock, Store)
                .outerjoin(ProductStock, ProductStock.product_id == Product.id)
                .outerjoin(Store, Store.id == ProductStock.store_id)
                .order_by(Product.reference, Store.name)
                .all()
            )

            self._full_data = []
            for p, ps, store in rows:
                initial_stock = ps.initial_stock if ps else 0
                store_name    = store.name if store else "—"
                store_id      = store.id   if store else None

                entries = self.session.query(
                    func.sum(StockEntry.quantity)
                ).filter(
                    StockEntry.reference == p.reference,
                    StockEntry.store_id  == store_id
                ).scalar() or 0 if store_id else 0

                outputs = self.session.query(
                    func.sum(StockOutput.quantity)
                ).filter(
                    StockOutput.reference == p.reference,
                    StockOutput.store_id  == store_id
                ).scalar() or 0 if store_id else 0

                current = initial_stock + entries - outputs
                if current <= 0:
                    status = "Rupture"
                elif current < 10:
                    status = "Stock faible"
                else:
                    status = "En stock"

                self._full_data.append({
                    "ref":      p.reference,
                    "des":      p.designation,
                    "unit":     p.unit,
                    "store":    store_name,
                    "store_id": store_id,
                    "initial":  initial_stock,
                    "entries":  entries,
                    "outputs":  outputs,
                    "current":  current,
                    "status":   status,
                })

            self._apply_filters()

        except Exception as e:
            print(f"[Reports] refresh: {e}")

    # ──────────────────────────────────────────────
    def _apply_filters(self):
        query      = self.f_search.text().strip().lower()
        store_id   = self.f_store_filter.currentData()
        status_txt = self.f_status_filter.currentText()

        filtered = self._full_data
        if query:
            filtered = [r for r in filtered
                        if query in r["ref"].lower() or query in r["des"].lower()]
        if store_id:
            filtered = [r for r in filtered if r["store_id"] == store_id]
        if status_txt != "Tous":
            filtered = [r for r in filtered if r["status"] == status_txt]

        # Update summary cards
        nb_ok      = sum(1 for r in self._full_data if r["status"] == "En stock")
        nb_low     = sum(1 for r in self._full_data if r["status"] == "Stock faible")
        nb_rupture = sum(1 for r in self._full_data if r["status"] == "Rupture")
        self._card_total[1].setText(str(len(self._full_data)))
        self._card_ok[1].setText(str(nb_ok))
        self._card_low[1].setText(str(nb_low))
        self._card_rupture[1].setText(str(nb_rupture))

        self.result_count.setText(f"{len(filtered)} produit(s) affiché(s)")
        self._render_table(filtered)

    # ──────────────────────────────────────────────
    def _render_table(self, rows):
        STATUS_COLOR = {
            "En stock":     P["accent_green"],
            "Stock faible": P["accent_orange"],
            "Rupture":      P["accent_red"],
        }
        STATUS_BG = {
            "En stock":     "#0D2210",
            "Stock faible": "#221A00",
            "Rupture":      "#220D0D",
        }

        self.table.setRowCount(len(rows))
        for row_idx, r in enumerate(rows):
            cols = [
                r["ref"], r["des"], r["unit"], r["store"],
                str(r["initial"]), str(r["entries"]), str(r["outputs"]),
                str(r["current"]), r["status"]
            ]
            for col, text in enumerate(cols):
                item = QTableWidgetItem(text)
                item.setTextAlignment(Qt.AlignVCenter | Qt.AlignLeft)
                item.setForeground(QColor(P["text_primary"]))

                if col == 0:
                    item.setForeground(QColor(P["accent_blue_lt"]))
                    item.setFont(QFont("Segoe UI", 9, QFont.Bold))

                elif col == 4:
                    item.setForeground(QColor(P["text_secondary"]))
                    item.setTextAlignment(Qt.AlignVCenter | Qt.AlignRight)

                elif col == 5:
                    item.setForeground(QColor(P["accent_green"]))
                    item.setFont(QFont("Segoe UI", 9, QFont.Bold))
                    item.setTextAlignment(Qt.AlignVCenter | Qt.AlignRight)
                    item.setText(f"+ {text}")

                elif col == 6:
                    item.setForeground(QColor(P["accent_red"]))
                    item.setFont(QFont("Segoe UI", 9, QFont.Bold))
                    item.setTextAlignment(Qt.AlignVCenter | Qt.AlignRight)
                    item.setText(f"− {text}")

                elif col == 7:
                    color = STATUS_COLOR.get(r["status"], P["text_primary"])
                    item.setForeground(QColor(color))
                    item.setFont(QFont("Segoe UI", 10, QFont.Bold))
                    item.setTextAlignment(Qt.AlignVCenter | Qt.AlignRight)

                elif col == 8:
                    color = STATUS_COLOR.get(text, P["text_primary"])
                    bg    = STATUS_BG.get(text, P["bg_elevated"])
                    item.setForeground(QColor(color))
                    item.setBackground(QColor(bg))
                    item.setFont(QFont("Segoe UI", 9, QFont.Bold))
                    item.setTextAlignment(Qt.AlignVCenter | Qt.AlignCenter)
                    item.setData(Qt.UserRole, "badge")

                self.table.setItem(row_idx, col, item)

    # ──────────────────────────────────────────────
    def _export_csv(self):
        path, _ = QFileDialog.getSaveFileName(
            self, "Exporter le rapport",
            f"rapport_produits_{date.today().strftime('%Y%m%d')}.csv",
            "CSV Files (*.csv)"
        )
        if not path:
            return
        try:
            with open(path, "w", newline="", encoding="utf-8-sig") as f:
                writer = csv.writer(f, delimiter=";")
                writer.writerow([
                    "RÉFÉRENCE", "DÉSIGNATION", "UNITÉ", "MAGASIN",
                    "STOCK INITIAL", "ENTRÉES", "SORTIES", "STOCK ACTUEL", "STATUT"
                ])
                for r in self._full_data:
                    writer.writerow([
                        r["ref"], r["des"], r["unit"], r["store"],
                        r["initial"], r["entries"], r["outputs"], r["current"], r["status"]
                    ])
            QMessageBox.information(
                self, "Export réussi",
                f"Rapport exporté avec succès :\n{path}"
            )
        except Exception as e:
            QMessageBox.critical(self, "Erreur export", str(e))