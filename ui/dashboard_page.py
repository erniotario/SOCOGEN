from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QLabel,
    QTableWidget, QTableWidgetItem, QHeaderView, QFrame
)
from PySide6.QtCore import Qt
from PySide6.QtGui import QColor, QFont
from sqlalchemy import func

from database import SessionLocal
from models import Product, ProductStock, StockEntry, StockOutput, Store
from ui.utils import hline, page_header, configure_table


P = {
    "bg_base":        "#080C10",
    "bg_surface":     "#0D1117",
    "bg_elevated":    "#161B22",
    "bg_highlight":   "#1C2128",
    "bg_hover":       "#21262D",
    "border":         "#21262D",
    "border_subtle":  "#161B22",
    "text_primary":   "#E6EDF3",
    "text_secondary": "#8B949E",
    "text_muted":     "#484F58",
    "accent_blue":    "#388BFD",
    "accent_blue_lt": "#58A6FF",
    "accent_green":   "#3FB950",
    "accent_red":     "#F85149",
    "accent_orange":  "#D29922",
}

APP_STYLE = f"""
QWidget {{
    background-color: {P['bg_surface']};
    color: {P['text_primary']};
    font-family: "Segoe UI", "SF Pro Text", system-ui, sans-serif;
    font-size: 13px;
}}
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
#field_label {{
    color: {P['text_muted']};
    font-size: 10px; font-weight: 700;
    letter-spacing: 0.8px;
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
#kpi_card {{
    background-color: {P['bg_elevated']};
    border: 1px solid {P['border']};
    border-radius: 10px;
}}
QFrame[frameShape="4"], QFrame[frameShape="5"] {{
    color: {P['border']}; background-color: {P['border']};
    border: none; max-height: 1px;
}}
"""


def _sep_h():
    line = QFrame()
    line.setFrameShape(QFrame.HLine)
    line.setFrameShadow(QFrame.Plain)
    line.setFixedHeight(1)
    line.setStyleSheet(f"background: {P['border']}; border: none;")
    return line


def _get_initial_stock(session, product_id):
    """Retourne le stock initial total d'un produit (somme sur tous les magasins)."""
    result = session.query(
        func.sum(ProductStock.initial_stock)
    ).filter(ProductStock.product_id == product_id).scalar()
    return result or 0


class DashboardPage(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.session = SessionLocal()
        self.setStyleSheet(APP_STYLE)
        self._build_ui()

    def _build_ui(self):
        root = QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        root.addWidget(self._build_header())
        root.addWidget(_sep_h())

        content = QWidget()
        content.setStyleSheet(f"background: {P['bg_base']};")
        cl = QVBoxLayout(content)
        cl.setContentsMargins(24, 20, 24, 24)
        cl.setSpacing(16)
        root.addWidget(content, 1)

        cl.addLayout(self._build_kpi_row())
        cl.addLayout(self._build_table_header())
        cl.addWidget(self._build_table(), 1)

        self.refresh()

    def _build_header(self):
        w = QWidget()
        w.setFixedHeight(56)
        w.setStyleSheet(
            f"background: {P['bg_surface']}; border-bottom: 1px solid {P['border']};"
        )
        lay = QHBoxLayout(w)
        lay.setContentsMargins(24, 0, 20, 0)
        lay.setSpacing(0)

        grp = QWidget(); grp.setStyleSheet("background: transparent;")
        gl  = QVBoxLayout(grp); gl.setContentsMargins(0, 0, 0, 0); gl.setSpacing(1)
        t = QLabel("Tableau de bord"); t.setObjectName("page_title")
        s = QLabel("Vue d'ensemble du stock"); s.setObjectName("page_subtitle")
        gl.addWidget(t); gl.addWidget(s)

        lay.addWidget(grp)
        lay.addStretch()
        return w

    def _build_kpi_row(self):
        row = QHBoxLayout(); row.setSpacing(10)
        self._card_products = self._kpi_card("Produits",        "0", P["accent_blue_lt"], "▣")
        self._card_entries  = self._kpi_card("Entrées totales", "0", P["accent_green"],   "↓")
        self._card_outputs  = self._kpi_card("Sorties totales", "0", P["accent_red"],     "↑")
        self._card_stores   = self._kpi_card("Magasins",        "0", P["accent_orange"],  "◈")
        for w, _ in [self._card_products, self._card_entries,
                     self._card_outputs, self._card_stores]:
            row.addWidget(w)
        return row

    def _kpi_card(self, label, value, color, symbol):
        card = QWidget(); card.setObjectName("kpi_card")
        lay  = QHBoxLayout(card)
        lay.setContentsMargins(20, 16, 20, 16)
        lay.setSpacing(14)

        sym = QLabel(symbol)
        sym.setFixedSize(36, 36)
        sym.setAlignment(Qt.AlignCenter)
        sym.setStyleSheet(f"color:{color}; font-size:20px; background:transparent;")
        lay.addWidget(sym)

        col = QWidget(); col.setStyleSheet("background:transparent;")
        cl  = QVBoxLayout(col); cl.setContentsMargins(0, 0, 0, 0); cl.setSpacing(3)

        lbl = QLabel(label.upper()); lbl.setObjectName("field_label")
        val = QLabel(value)
        val.setStyleSheet(
            f"color:{color}; font-size:24px; font-weight:700; background:transparent;"
        )
        cl.addWidget(lbl); cl.addWidget(val)
        lay.addWidget(col); lay.addStretch()
        return card, val

    def _build_table_header(self):
        row = QHBoxLayout(); row.setSpacing(0)
        lbl = QLabel("STOCK ACTUEL PAR PRODUIT"); lbl.setObjectName("field_label")
        row.addWidget(lbl); row.addStretch()
        return row

    def _build_table(self):
        self.table = QTableWidget()
        self.table.setColumnCount(7)
        self.table.setHorizontalHeaderLabels([
            "RÉFÉRENCE", "DÉSIGNATION", "UNITÉ",
            "STOCK INITIAL", "ENTRÉES", "SORTIES", "STOCK ACTUEL"
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
        for col, w in {0: 120, 2: 70, 3: 110, 4: 100, 5: 100, 6: 110}.items():
            self.table.setColumnWidth(col, w)
        return self.table

    def refresh(self):
        try:
            self.session.expire_all()
            products = self.session.query(Product).all()
            stores   = self.session.query(Store).count()

            total_entries = self.session.query(
                func.sum(StockEntry.quantity)
            ).scalar() or 0

            total_outputs = self.session.query(
                func.sum(StockOutput.quantity)
            ).scalar() or 0

            self._card_products[1].setText(str(len(products)))
            self._card_entries[1].setText(str(total_entries))
            self._card_outputs[1].setText(str(total_outputs))
            self._card_stores[1].setText(str(stores))

            self.table.setRowCount(len(products))
            for row, p in enumerate(products):
                # Stock initial = somme des stocks initiaux dans tous les magasins
                initial_stock = _get_initial_stock(self.session, p.id)

                entries = self.session.query(
                    func.sum(StockEntry.quantity)
                ).filter(StockEntry.reference == p.reference).scalar() or 0

                outputs = self.session.query(
                    func.sum(StockOutput.quantity)
                ).filter(StockOutput.reference == p.reference).scalar() or 0

                current = initial_stock + entries - outputs

                cols = [
                    p.reference, p.designation, p.unit,
                    str(initial_stock), str(entries), str(outputs), str(current)
                ]

                for col, text in enumerate(cols):
                    item = QTableWidgetItem(text)
                    item.setForeground(QColor(P["text_primary"]))

                    if col == 0:
                        item.setForeground(QColor(P["accent_blue_lt"]))
                        item.setFont(QFont("Segoe UI", 9, QFont.Bold))
                        item.setTextAlignment(Qt.AlignVCenter | Qt.AlignLeft)
                    elif col == 3:
                        item.setForeground(QColor(P["text_secondary"]))
                        item.setTextAlignment(Qt.AlignVCenter | Qt.AlignRight)
                    elif col == 4:
                        item.setForeground(QColor(P["accent_green"]))
                        item.setFont(QFont("Segoe UI", 9, QFont.Bold))
                        item.setText(f"+ {text}")
                        item.setTextAlignment(Qt.AlignVCenter | Qt.AlignRight)
                    elif col == 5:
                        item.setForeground(QColor(P["accent_red"]))
                        item.setFont(QFont("Segoe UI", 9, QFont.Bold))
                        item.setText(f"− {text}")
                        item.setTextAlignment(Qt.AlignVCenter | Qt.AlignRight)
                    elif col == 6:
                        if current <= 0:
                            c = P["accent_red"]
                        elif current < 10:
                            c = P["accent_orange"]
                        else:
                            c = P["accent_green"]
                        item.setForeground(QColor(c))
                        item.setFont(QFont("Segoe UI", 10, QFont.Bold))
                        item.setTextAlignment(Qt.AlignVCenter | Qt.AlignRight)
                    else:
                        item.setTextAlignment(Qt.AlignVCenter | Qt.AlignLeft)

                    self.table.setItem(row, col, item)

        except Exception as e:
            print(f"[Dashboard] Erreur: {e}")