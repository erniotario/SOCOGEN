from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QLabel, QLineEdit,
    QSpinBox, QComboBox, QTableWidget, QTableWidgetItem,
    QHeaderView, QDateEdit, QDialog, QPushButton, QMessageBox, QCompleter,
    QFrame, QGraphicsDropShadowEffect
)
from PySide6.QtCore import Qt, QDate, QStringListModel
from PySide6.QtGui import QColor
from sqlalchemy import func

from database import SessionLocal
from models import Product, ProductStock, StockEntry, StockOutput, Store
from ui.utils import configure_table, set_status

# ─────────────────────────────────────────────────────────
# Design tokens – dark industrial (mirrors EntriesPage)
# ─────────────────────────────────────────────────────────
STYLE = """
QWidget {
    background-color: #0F1117;
    color: #E2E8F0;
    font-family: "Segoe UI", system-ui, sans-serif;
    font-size: 13px;
}

#page_header {
    background: qlineargradient(x1:0, y1:0, x2:1, y2:0,
        stop:0 #151820, stop:1 #0F1117);
    border-bottom: 1px solid #1E2433;
}
#page_title {
    font-family: "Segoe UI", system-ui, sans-serif;
    font-size: 22px;
    font-weight: 700;
    color: #F0F4FF;
    letter-spacing: 1px;
}
#page_subtitle {
    font-size: 12px;
    color: #64748B;
    letter-spacing: 0.5px;
}
#header_accent {
    background: #EF4444;
    border-radius: 2px;
}

#form_card {
    background: #141822;
    border: 1px solid #1E2433;
    border-radius: 12px;
}
#card_header {
    background: transparent;
    border-bottom: 1px solid #1E2433;
    padding: 12px 20px;
}
#card_title {
    font-family: "Segoe UI", system-ui, sans-serif;
    font-size: 10px;
    font-weight: 600;
    color: #EF4444;
    letter-spacing: 2px;
}

#field_label {
    font-size: 10px;
    font-weight: 600;
    color: #64748B;
    letter-spacing: 1.5px;
    background: transparent;
    margin-bottom: 4px;
}

QLineEdit, QSpinBox, QDateEdit, QComboBox {
    background: #0A0D14;
    border: 1px solid #1E2433;
    border-radius: 8px;
    padding: 8px 12px;
    color: #E2E8F0;
    font-size: 13px;
    selection-background-color: #EF4444;
    min-height: 18px;
}
QLineEdit:focus, QSpinBox:focus, QDateEdit:focus, QComboBox:focus {
    border: 1px solid #EF4444;
    background: #0D1018;
}
QLineEdit:read-only {
    color: #64748B;
    background: #0D1018;
    border-color: #151A24;
}
QSpinBox::up-button, QSpinBox::down-button {
    background: #1E2433;
    border: none;
    border-radius: 4px;
    width: 18px;
}
QSpinBox::up-button:hover, QSpinBox::down-button:hover { background: #2D3748; }
QDateEdit::drop-down, QComboBox::drop-down {
    border: none;
    padding-right: 8px;
    width: 20px;
}
QDateEdit::down-arrow, QComboBox::down-arrow {
    image: none;
    border-left: 4px solid transparent;
    border-right: 4px solid transparent;
    border-top: 5px solid #4B5563;
    width: 0px;
    height: 0px;
}
QComboBox QAbstractItemView {
    background: #141822;
    border: 1px solid #1E2433;
    border-radius: 8px;
    color: #E2E8F0;
    selection-background-color: #3D1515;
    padding: 4px;
}
QComboBox:disabled {
    color: #4B5563;
    background: #0D1018;
}
QAbstractItemView {
    background: #141822;
    border: 1px solid #EF4444;
    border-radius: 8px;
    color: #E2E8F0;
    selection-background-color: #3D1515;
    selection-color: #FCA5A5;
    padding: 4px;
    outline: none;
}

#store_hint_label {
    color: #EF4444;
    background: transparent;
    font-size: 11px;
    padding-left: 4px;
}

QPushButton {
    border-radius: 8px;
    padding: 9px 18px;
    font-size: 12px;
    font-weight: 600;
    letter-spacing: 0.5px;
    border: none;
}
#btn_primary_red {
    background: #EF4444;
    color: #FFFFFF;
    padding: 9px 22px;
}
#btn_primary_red:hover   { background: #DC2626; }
#btn_primary_red:pressed { background: #B91C1C; }
#btn_secondary {
    background: #1E2433;
    color: #94A3B8;
    border: 1px solid #2D3748;
}
#btn_secondary:hover   { background: #2D3748; color: #E2E8F0; }
#btn_secondary:pressed { background: #374151; }
#btn_secondary:disabled { color: #2D3748; border-color: #1E2433; }
#btn_danger {
    background: transparent;
    color: #F87171;
    border: 1px solid #2D1B1B;
}
#btn_danger:hover   { background: #2D1B1B; }
#btn_danger:pressed { background: #3D2020; }
#btn_danger:disabled { color: #3D2020; border-color: #1A1212; }

#section_title {
    font-family: "Segoe UI", system-ui, sans-serif;
    font-size: 10px;
    font-weight: 600;
    color: #4B5563;
    letter-spacing: 2px;
    background: transparent;
    padding: 0px 0px 8px 0px;
}

QTableWidget {
    background: #0A0D14;
    border: 1px solid #1E2433;
    border-radius: 10px;
    gridline-color: #141822;
    outline: none;
    alternate-background-color: #0D1018;
    selection-background-color: #3D1515;
    selection-color: #E2E8F0;
}
QTableWidget::item {
    padding: 10px 12px;
    border-bottom: 1px solid #141822;
    color: #CBD5E1;
}
QTableWidget::item:selected {
    background: #3D1515;
    color: #E2E8F0;
}
QHeaderView::section {
    background: #0F1117;
    color: #4B5563;
    font-family: "Segoe UI", system-ui, sans-serif;
    font-size: 10px;
    font-weight: 600;
    letter-spacing: 1.5px;
    padding: 10px 12px;
    border: none;
    border-bottom: 1px solid #1E2433;
    border-right: 1px solid #1A1F2E;
}
QHeaderView::section:first { border-radius: 10px 0 0 0; }
QHeaderView::section:last  { border-radius: 0 10px 0 0; border-right: none; }
QScrollBar:vertical {
    background: #0A0D14;
    width: 8px;
    border-radius: 4px;
    margin: 0;
}
QScrollBar::handle:vertical {
    background: #1E2433;
    border-radius: 4px;
    min-height: 30px;
}
QScrollBar::handle:vertical:hover { background: #2D3748; }
QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height: 0; }
QScrollBar:horizontal {
    background: #0A0D14;
    height: 8px;
    border-radius: 4px;
}
QScrollBar::handle:horizontal { background: #1E2433; border-radius: 4px; }

#status_ok {
    background: #0A1F0A;
    border: 1px solid #14532D;
    border-radius: 6px;
    color: #4ADE80;
    padding: 7px 14px;
    font-size: 12px;
}
#status_err {
    background: #1A0A0A;
    border: 1px solid #7F1D1D;
    border-radius: 6px;
    color: #F87171;
    padding: 7px 14px;
    font-size: 12px;
}

#stock_info_label {
    background: transparent;
    font-size: 12px;
    font-weight: 600;
    padding: 4px 10px;
    border-radius: 6px;
}

#divider {
    background: #1E2433;
    max-height: 1px;
    min-height: 1px;
    border: none;
}

QDialog {
    background: #141822;
    border: 1px solid #1E2433;
    border-radius: 12px;
}
QDialog QLabel { background: transparent; }
"""


def _shadow(radius=24, color="#000000", opacity=100, offset=(0, 4)):
    effect = QGraphicsDropShadowEffect()
    effect.setBlurRadius(radius)
    c = QColor(color)
    c.setAlpha(opacity)
    effect.setColor(c)
    effect.setOffset(*offset)
    return effect


def _accent_bar(color="#EF4444"):
    bar = QFrame()
    bar.setObjectName("header_accent")
    bar.setFixedSize(3, 28)
    bar.setStyleSheet(f"background: {color}; border-radius: 2px;")
    return bar


class OutputsPage(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.session = SessionLocal()
        self._outputs = []
        self._selected_output = None
        self.setStyleSheet(STYLE)
        self._build_ui()

    # ──────────────────────────────────────────────────────────
    def _build_ui(self):
        root = QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        # ── Header ──────────────────────────────────────────
        header = QFrame()
        header.setObjectName("page_header")
        header.setFixedHeight(72)
        hl = QHBoxLayout(header)
        hl.setContentsMargins(28, 0, 28, 0)
        hl.setSpacing(14)
        hl.addWidget(_accent_bar())

        title_col = QVBoxLayout()
        title_col.setSpacing(3)
        title_lbl = QLabel("SORTIES DE STOCK")
        title_lbl.setObjectName("page_title")
        sub_lbl = QLabel("Enregistrer les cessions et distributions")
        sub_lbl.setObjectName("page_subtitle")
        title_col.addWidget(title_lbl)
        title_col.addWidget(sub_lbl)
        hl.addLayout(title_col)
        hl.addStretch()
        root.addWidget(header)

        div = QFrame(); div.setObjectName("divider")
        root.addWidget(div)

        # ── Content ──────────────────────────────────────────
        content = QWidget()
        cl = QVBoxLayout(content)
        cl.setContentsMargins(28, 24, 28, 24)
        cl.setSpacing(20)
        root.addWidget(content)

        # ── Form card ────────────────────────────────────────
        form_card = QFrame()
        form_card.setObjectName("form_card")
        form_card.setGraphicsEffect(_shadow(32, "#000000", 100, (0, 6)))
        fc_layout = QVBoxLayout(form_card)
        fc_layout.setContentsMargins(0, 0, 0, 0)
        fc_layout.setSpacing(0)

        card_hdr = QFrame()
        card_hdr.setObjectName("card_header")
        card_hdr.setFixedHeight(44)
        chl = QHBoxLayout(card_hdr)
        chl.setContentsMargins(20, 0, 20, 0)
        card_title = QLabel("NOUVELLE SORTIE")
        card_title.setObjectName("card_title")
        chl.addWidget(card_title)
        chl.addStretch()
        fc_layout.addWidget(card_hdr)

        card_body = QWidget()
        cbl = QVBoxLayout(card_body)
        cbl.setContentsMargins(20, 18, 20, 18)
        cbl.setSpacing(16)

        # Row 1
        row1 = QHBoxLayout(); row1.setSpacing(14)

        self.f_date = QDateEdit(QDate.currentDate())
        self.f_date.setCalendarPopup(True)
        self.f_date.setDisplayFormat("dd/MM/yyyy")

        self.f_reference = QLineEdit()
        self.f_reference.setPlaceholderText("Chercher produit...")
        self.f_reference.textChanged.connect(self._on_ref_changed)
        self._products_map = {}

        self.f_designation = QLineEdit()
        self.f_designation.setReadOnly(True)
        self.f_designation.setPlaceholderText("Auto-rempli")

        self.f_invoice = QLineEdit()
        self.f_invoice.setPlaceholderText("Ex: FAC-2025-001")

        row1.addLayout(self._field("DATE *",        self.f_date),        1)
        row1.addLayout(self._field("RÉFÉRENCE *",   self.f_reference),   2)
        row1.addLayout(self._field("DÉSIGNATION",   self.f_designation), 3)
        row1.addLayout(self._field("N° FACTURE",    self.f_invoice),     2)
        cbl.addLayout(row1)

        # Row 2
        row2 = QHBoxLayout(); row2.setSpacing(14)

        self.f_store = QComboBox()
        self.f_destination = QLineEdit()
        self.f_destination.setPlaceholderText("Ex: Chantier Bastos")
        self.f_quantity = QSpinBox()
        self.f_quantity.setMinimum(1)
        self.f_quantity.setMaximum(9999999)

        row2.addLayout(self._field("MAGASIN *",     self.f_store),       2)
        row2.addLayout(self._field("DESTINATION",   self.f_destination), 4)
        row2.addLayout(self._field("QUANTITÉ *",    self.f_quantity),    1)
        cbl.addLayout(row2)

        # Store hint
        self.store_hint = QLabel("")
        self.store_hint.setObjectName("store_hint_label")
        cbl.addWidget(self.store_hint)

        # Button row
        btn_row = QHBoxLayout()
        btn_row.setSpacing(10)

        self.stock_info = QLabel("")
        self.stock_info.setObjectName("stock_info_label")
        btn_row.addWidget(self.stock_info)
        btn_row.addStretch()

        self.btn_edit = QPushButton("✎  Modifier")
        self.btn_edit.setObjectName("btn_secondary")
        self.btn_edit.clicked.connect(self._edit_output)
        self.btn_edit.setEnabled(False)
        self.btn_edit.setCursor(Qt.PointingHandCursor)

        self.btn_delete = QPushButton("🗑  Supprimer")
        self.btn_delete.setObjectName("btn_danger")
        self.btn_delete.clicked.connect(self._delete_output)
        self.btn_delete.setEnabled(False)
        self.btn_delete.setCursor(Qt.PointingHandCursor)

        self.btn_save = QPushButton("−  Enregistrer la sortie")
        self.btn_save.setObjectName("btn_primary_red")
        self.btn_save.clicked.connect(self._save_output)
        self.btn_save.setCursor(Qt.PointingHandCursor)

        btn_row.addWidget(self.btn_edit)
        btn_row.addWidget(self.btn_delete)
        btn_row.addWidget(self.btn_save)
        cbl.addLayout(btn_row)

        fc_layout.addWidget(card_body)
        cl.addWidget(form_card)

        # ── History section ─────────────────────────────────
        tbl_title = QLabel("HISTORIQUE DES SORTIES")
        tbl_title.setObjectName("section_title")
        cl.addWidget(tbl_title)

        self.table = QTableWidget()
        self.table.setColumnCount(8)
        self.table.setHorizontalHeaderLabels([
            "ID", "DATE", "RÉFÉRENCE", "DÉSIGNATION",
            "N° FACTURE", "MAGASIN", "DESTINATION", "QUANTITÉ"
        ])
        self.table.setAlternatingRowColors(True)
        self.table.setShowGrid(False)
        self.table.verticalHeader().setVisible(False)
        self.table.setSelectionBehavior(QTableWidget.SelectRows)
        self.table.setSelectionMode(QTableWidget.SingleSelection)
        self.table.setFocusPolicy(Qt.NoFocus)
        self.table.horizontalHeader().setHighlightSections(False)
        configure_table(
            self.table,
            stretch_columns=[3],
            widths={0: 55, 1: 110}
        )
        self.table.setGraphicsEffect(_shadow(20, "#000000", 80, (0, 4)))
        self.table.itemSelectionChanged.connect(self._on_table_selection_changed)
        self.table.doubleClicked.connect(self._edit_output)
        cl.addWidget(self.table)

        self.status = QLabel("")
        self.status.setObjectName("status_ok")
        self.status.hide()
        cl.addWidget(self.status)

        self._load_combos()
        self.refresh()

    # ──────────────────────────────────────────────────────────
    @staticmethod
    def _field(label_text: str, widget) -> QVBoxLayout:
        layout = QVBoxLayout()
        layout.setSpacing(5)
        layout.setContentsMargins(0, 0, 0, 0)
        lbl = QLabel(label_text)
        lbl.setObjectName("field_label")
        layout.addWidget(lbl)
        layout.addWidget(widget)
        return layout

    # ──────────────────────────────────────────────────────────
    def _load_combos(self):
        try:
            self.session.expire_all()
            self.f_reference.blockSignals(True)

            self._products_map = {}
            products_list = []
            for p in self.session.query(Product).order_by(Product.reference).all():
                display_text = f"{p.reference} — {p.designation}"
                self._products_map[display_text] = p.reference
                products_list.append(display_text)

            self._setup_product_completer(products_list)
            self.f_reference.clear()
            self.f_reference.blockSignals(False)
            self._reload_stores(product_ref=None)
        except Exception as e:
            print(f"[Outputs] _load_combos: {e}")

    def _setup_product_completer(self, products_list):
        model = QStringListModel(products_list)
        completer = QCompleter(model)
        completer.setCaseSensitivity(Qt.CaseInsensitive)
        completer.setCompletionMode(QCompleter.PopupCompletion)
        self.f_reference.setCompleter(completer)

    def _reload_stores(self, product_ref=None):
        """
        Si product_ref fourni : affiche uniquement les magasins où
        le stock disponible (initial + entrées - sorties) est > 0,
        avec la quantité entre parenthèses.
        Sinon : affiche tous les magasins.
        """
        self.f_store.blockSignals(True)
        self.f_store.clear()

        if product_ref:
            p = self.session.query(Product).filter_by(reference=product_ref).first()
            if p:
                ps_list = self.session.query(ProductStock).filter_by(product_id=p.id).all()
                available = []
                for ps in ps_list:
                    store = self.session.get(Store, ps.store_id)
                    if not store:
                        continue
                    entries = self.session.query(
                        func.sum(StockEntry.quantity)
                    ).filter(
                        StockEntry.reference == product_ref,
                        StockEntry.store_id  == ps.store_id
                    ).scalar() or 0
                    outputs = self.session.query(
                        func.sum(StockOutput.quantity)
                    ).filter(
                        StockOutput.reference == product_ref,
                        StockOutput.store_id  == ps.store_id
                    ).scalar() or 0
                    qty_dispo = ps.initial_stock + entries - outputs
                    if qty_dispo > 0:
                        available.append((store, qty_dispo))

                if available:
                    for store, qty_dispo in sorted(available, key=lambda x: x[0].name):
                        self.f_store.addItem(
                            f"{store.name}  ({qty_dispo} disponible{'s' if qty_dispo > 1 else ''})",
                            store.id
                        )
                    self.f_store.setEnabled(True)
                    self.store_hint.setText(
                        f"ℹ  {len(available)} magasin(s) avec stock disponible"
                    )
                else:
                    # Aucun stock disponible — on liste quand même tous les magasins
                    for st in self.session.query(Store).order_by(Store.name).all():
                        self.f_store.addItem(st.name, st.id)
                    self.f_store.setEnabled(True)
                    self.store_hint.setText("⚠  Aucun stock disponible dans aucun magasin")
            else:
                for st in self.session.query(Store).order_by(Store.name).all():
                    self.f_store.addItem(st.name, st.id)
                self.f_store.setEnabled(True)
                self.store_hint.setText("")
        else:
            for st in self.session.query(Store).order_by(Store.name).all():
                self.f_store.addItem(st.name, st.id)
            self.f_store.setEnabled(True)
            self.store_hint.setText("")

        self.f_store.blockSignals(False)

    # ──────────────────────────────────────────────────────────
    def _on_ref_changed(self, text):
        text = text.strip()
        ref = self._products_map.get(text)
        if not ref and text:
            for display_text, product_ref in self._products_map.items():
                if display_text.startswith(text) or product_ref.lower() == text.lower():
                    ref = product_ref
                    break

        if ref:
            p = self.session.query(Product).filter_by(reference=ref).first()
            if p:
                self.f_designation.setText(p.designation)
                # Charger les magasins avec stock > 0
                self._reload_stores(product_ref=ref)
                # Stock total toutes magasins confondus
                initial_stock = self.session.query(
                    func.sum(ProductStock.initial_stock)
                ).filter(ProductStock.product_id == p.id).scalar() or 0
                entries = self.session.query(
                    func.sum(StockEntry.quantity)
                ).filter(StockEntry.reference == ref).scalar() or 0
                outputs = self.session.query(
                    func.sum(StockOutput.quantity)
                ).filter(StockOutput.reference == ref).scalar() or 0
                current = initial_stock + entries - outputs
                if current > 10:
                    color, bg = "#4ADE80", "#0A1F0A"
                elif current > 0:
                    color, bg = "#FBBF24", "#1F1A0A"
                else:
                    color, bg = "#F87171", "#1A0A0A"
                self.stock_info.setStyleSheet(
                    f"color:{color}; background:{bg}; border-radius:6px; "
                    f"padding:4px 10px; font-size:12px; font-weight:600;"
                )
                self.stock_info.setText(f"Stock total : {current} {p.unit}")
        else:
            self.f_designation.clear()
            self.stock_info.clear()
            self.stock_info.setStyleSheet("")
            self._reload_stores(product_ref=None)

    # ──────────────────────────────────────────────────────────
    def _save_output(self):
        text = self.f_reference.text().strip()
        ref = self._products_map.get(text)
        if not ref and text:
            for display_text, product_ref in self._products_map.items():
                if display_text.startswith(text) or product_ref.lower() == text.lower():
                    ref = product_ref
                    break

        store_id = self.f_store.currentData()
        qty      = self.f_quantity.value()
        date_str = self.f_date.date().toString("yyyy-MM-dd")

        if not ref:
            self._set_status("Sélectionnez une référence produit.", error=True); return
        if not store_id:
            self._set_status("Sélectionnez un magasin.", error=True); return

        p = self.session.query(Product).filter_by(reference=ref).first()
        if p:
            initial_stock = self.session.query(
                func.sum(ProductStock.initial_stock)
            ).filter(ProductStock.product_id == p.id).scalar() or 0
            entries = self.session.query(
                func.sum(StockEntry.quantity)
            ).filter(StockEntry.reference == ref).scalar() or 0
            outputs = self.session.query(
                func.sum(StockOutput.quantity)
            ).filter(StockOutput.reference == ref).scalar() or 0
            current = initial_stock + entries - outputs
            if qty > current:
                reply = QMessageBox.warning(
                    self, "Stock insuffisant",
                    f"Stock disponible : {current}. Quantité demandée : {qty}.\n"
                    "Continuer quand même ?",
                    QMessageBox.Yes | QMessageBox.No
                )
                if reply == QMessageBox.No:
                    return

        try:
            output = StockOutput(
                date=date_str,
                reference=ref,
                designation=p.designation if p else ref,
                invoice_number=self.f_invoice.text().strip(),
                store_id=store_id,
                destination=self.f_destination.text().strip(),
                quantity=qty,
            )
            self.session.add(output)
            self.session.commit()

            self.f_invoice.clear()
            self.f_destination.clear()
            self.f_reference.clear()
            self.f_designation.clear()
            self.f_quantity.setValue(1)
            self.stock_info.clear()
            self.stock_info.setStyleSheet("")
            self._set_status(f"Sortie enregistrée : {qty} × {ref}.")
            self.refresh()
        except Exception as e:
            self.session.rollback()
            self._set_status(f"Erreur : {e}", error=True)

    # ──────────────────────────────────────────────────────────
    def refresh(self):
        self._load_combos()
        try:
            self.session.expire_all()
            outputs = (
                self.session.query(StockOutput, Store.name)
                .join(Store, StockOutput.store_id == Store.id)
                .order_by(StockOutput.date.desc(), StockOutput.id.desc())
                .all()
            )
            self._outputs = outputs
            self._selected_output = None
            self.btn_edit.setEnabled(False)
            self.btn_delete.setEnabled(False)
            self.table.setRowCount(len(outputs))
            for row, (o, store_name) in enumerate(outputs):
                for col, text in enumerate([
                    str(o.id), o.date, o.reference, o.designation,
                    o.invoice_number, store_name, o.destination, str(o.quantity)
                ]):
                    item = QTableWidgetItem(text)
                    item.setTextAlignment(Qt.AlignVCenter | Qt.AlignLeft)
                    if col == 7:
                        item.setForeground(QColor("#F87171"))
                        item.setTextAlignment(Qt.AlignVCenter | Qt.AlignRight)
                        item.setText(f"− {text}")
                    elif col == 0:
                        item.setForeground(QColor("#374151"))
                    self.table.setItem(row, col, item)
        except Exception as e:
            print(f"[Outputs] refresh: {e}")

    # ──────────────────────────────────────────────────────────
    def _set_status(self, msg: str, error: bool = False):
        self.status.setText(msg)
        self.status.setObjectName("status_err" if error else "status_ok")
        self.status.setStyleSheet("")
        self.status.style().unpolish(self.status)
        self.status.style().polish(self.status)
        self.status.show()

    def _on_table_selection_changed(self):
        selected = self.table.selectedItems()
        if not selected:
            self._selected_output = None
            self.btn_edit.setEnabled(False)
            self.btn_delete.setEnabled(False)
            return
        row = self.table.currentRow()
        if row < 0 or row >= len(self._outputs):
            self._selected_output = None
            self.btn_edit.setEnabled(False)
            self.btn_delete.setEnabled(False)
            return
        self._selected_output = self._outputs[row][0]
        self.btn_edit.setEnabled(True)
        self.btn_delete.setEnabled(True)

    def _delete_output(self):
        if not self._selected_output:
            return
        reply = QMessageBox.question(
            self, "Confirmer la suppression",
            "Voulez-vous supprimer cette sortie ?",
            QMessageBox.Yes | QMessageBox.No
        )
        if reply != QMessageBox.Yes:
            return
        try:
            self.session.delete(self._selected_output)
            self.session.commit()
            self.refresh()
            self._set_status("Sortie supprimée.")
        except Exception as e:
            self.session.rollback()
            self._set_status(f"Erreur suppression : {e}", error=True)

    def _edit_output(self):
        if not self._selected_output:
            return
        output = self.session.get(StockOutput, self._selected_output.id)
        if not output:
            self._set_status("Sortie introuvable.", error=True)
            return

        dlg = QDialog(self)
        dlg.setWindowTitle("Modifier la sortie")
        dlg.setMinimumWidth(480)
        dlg.setStyleSheet(STYLE)
        dlg_layout = QVBoxLayout(dlg)
        dlg_layout.setContentsMargins(24, 24, 24, 24)
        dlg_layout.setSpacing(14)

        # Dialog header
        dlg_hdr = QHBoxLayout()
        dlg_hdr.setSpacing(10)
        dlg_hdr.addWidget(_accent_bar())
        dlg_title = QLabel("MODIFIER LA SORTIE")
        dlg_title.setObjectName("card_title")
        dlg_hdr.addWidget(dlg_title)
        dlg_hdr.addStretch()
        dlg_layout.addLayout(dlg_hdr)

        divider = QFrame(); divider.setObjectName("divider")
        dlg_layout.addWidget(divider)

        date_edit = QDateEdit()
        date_edit.setCalendarPopup(True)
        date_edit.setDisplayFormat("dd/MM/yyyy")
        try:
            year, month, day = map(int, output.date.split("-"))
            date_edit.setDate(QDate(year, month, day))
        except Exception:
            date_edit.setDate(QDate.currentDate())
        dlg_layout.addLayout(self._field("DATE", date_edit))

        ref_edit = QComboBox()
        ref_edit.addItem("— Sélectionner —", None)
        for p in self.session.query(Product).order_by(Product.reference).all():
            ref_edit.addItem(f"{p.reference} — {p.designation}", p.reference)
            if p.reference == output.reference:
                ref_edit.setCurrentText(f"{p.reference} — {p.designation}")
        dlg_layout.addLayout(self._field("RÉFÉRENCE", ref_edit))

        desig_edit = QLineEdit(output.designation)
        desig_edit.setReadOnly(True)
        dlg_layout.addLayout(self._field("DÉSIGNATION", desig_edit))

        invoice_edit = QLineEdit(output.invoice_number)
        dlg_layout.addLayout(self._field("N° FACTURE", invoice_edit))

        store_edit = QComboBox()
        for s in self.session.query(Store).order_by(Store.name).all():
            store_edit.addItem(s.name, s.id)
            if s.id == output.store_id:
                store_edit.setCurrentText(s.name)
        dlg_layout.addLayout(self._field("MAGASIN", store_edit))

        destination_edit = QLineEdit(output.destination)
        dlg_layout.addLayout(self._field("DESTINATION", destination_edit))

        qty_edit = QSpinBox()
        qty_edit.setMinimum(1)
        qty_edit.setMaximum(9999999)
        qty_edit.setValue(output.quantity)
        dlg_layout.addLayout(self._field("QUANTITÉ", qty_edit))

        btn_box_layout = QHBoxLayout()
        btn_box_layout.setSpacing(10)
        btn_cancel = QPushButton("Annuler")
        btn_cancel.setObjectName("btn_secondary")
        btn_cancel.setCursor(Qt.PointingHandCursor)
        btn_save_dlg = QPushButton("Enregistrer")
        btn_save_dlg.setObjectName("btn_primary_red")
        btn_save_dlg.setCursor(Qt.PointingHandCursor)
        btn_box_layout.addStretch()
        btn_box_layout.addWidget(btn_cancel)
        btn_box_layout.addWidget(btn_save_dlg)
        dlg_layout.addLayout(btn_box_layout)

        def on_save():
            ref_val = ref_edit.currentData()
            if not ref_val:
                QMessageBox.warning(dlg, "Référence requise", "Sélectionnez une référence produit.")
                return
            product = self.session.query(Product).filter_by(reference=ref_val).first()
            output.date = date_edit.date().toString("yyyy-MM-dd")
            output.reference = ref_val
            output.designation = product.designation if product else output.designation
            output.invoice_number = invoice_edit.text().strip()
            output.store_id = store_edit.currentData()
            output.destination = destination_edit.text().strip()
            output.quantity = qty_edit.value()
            try:
                self.session.commit()
                dlg.accept()
                self.refresh()
                self._set_status("Sortie mise à jour.")
            except Exception as e:
                self.session.rollback()
                QMessageBox.critical(dlg, "Erreur", str(e))

        def on_ref_change(index):
            ref_value = ref_edit.currentData()
            product = self.session.query(Product).filter_by(reference=ref_value).first()
            if product:
                desig_edit.setText(product.designation)
            else:
                desig_edit.clear()

        ref_edit.currentIndexChanged.connect(on_ref_change)
        btn_cancel.clicked.connect(dlg.reject)
        btn_save_dlg.clicked.connect(on_save)
        dlg.exec()