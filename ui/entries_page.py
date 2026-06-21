from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QLabel, QLineEdit,
    QSpinBox, QComboBox, QTableWidget, QTableWidgetItem,
    QHeaderView, QDateEdit, QDialog, QPushButton, QMessageBox, QCompleter,
    QFrame, QGraphicsDropShadowEffect, QSizePolicy
)
from PySide6.QtCore import Qt, QDate, QStringListModel, QPropertyAnimation, QEasingCurve
from PySide6.QtGui import QColor, QFont, QPalette

from database import SessionLocal
from models import Product, ProductStock, StockEntry, Store
from ui.utils import hline, field, make_btn, page_header, panel, configure_table, status_label, set_status

# ─────────────────────────────────────────────────────────
# Design tokens (dark industrial palette)
# ─────────────────────────────────────────────────────────
STYLE = """
/* ── Global ────────────────────────────────────────── */
QWidget {
    background-color: #0F1117;
    color: #E2E8F0;
    font-family: "Segoe UI", system-ui, sans-serif;
    font-size: 13px;
}

/* ── Page header ────────────────────────────────────── */
#page_header {
    background: qlineargradient(x1:0, y1:0, x2:1, y2:0,
        stop:0 #151820, stop:1 #0F1117);
    border-bottom: 1px solid #1E2433;
    padding: 0px;
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
    background: #3B82F6;
    border-radius: 2px;
}

/* ── Panel card ─────────────────────────────────────── */
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
    color: #3B82F6;
    letter-spacing: 2px;
}

/* ── Field labels ───────────────────────────────────── */
#field_label {
    font-size: 10px;
    font-weight: 600;
    color: #64748B;
    letter-spacing: 1.5px;
    text-transform: uppercase;
    background: transparent;
    margin-bottom: 4px;
}

/* ── Inputs ─────────────────────────────────────────── */
QLineEdit, QSpinBox, QDateEdit, QComboBox {
    background: #0A0D14;
    border: 1px solid #1E2433;
    border-radius: 8px;
    padding: 8px 12px;
    color: #E2E8F0;
    font-size: 13px;
    selection-background-color: #3B82F6;
    min-height: 18px;
}
QLineEdit:focus, QSpinBox:focus, QDateEdit:focus, QComboBox:focus {
    border: 1px solid #3B82F6;
    background: #0D1018;
    outline: none;
}
QLineEdit:read-only {
    color: #64748B;
    background: #0D1018;
    border-color: #151A24;
}
QLineEdit::placeholder {
    color: #334155;
}
QSpinBox::up-button, QSpinBox::down-button {
    background: #1E2433;
    border: none;
    border-radius: 4px;
    width: 18px;
}
QSpinBox::up-button:hover, QSpinBox::down-button:hover {
    background: #2D3748;
}
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
    selection-background-color: #1D2D4F;
    padding: 4px;
}
QComboBox:disabled {
    color: #4B5563;
    background: #0D1018;
}

/* ── Completer popup ────────────────────────────────── */
QAbstractItemView {
    background: #141822;
    border: 1px solid #3B82F6;
    border-radius: 8px;
    color: #E2E8F0;
    selection-background-color: #1D2D4F;
    selection-color: #93C5FD;
    padding: 4px;
    outline: none;
}

/* ── Store hint ─────────────────────────────────────── */
#store_hint_label {
    color: #3B82F6;
    background: transparent;
    font-size: 11px;
    padding-left: 4px;
}

/* ── Buttons ─────────────────────────────────────────── */
QPushButton {
    border-radius: 8px;
    padding: 9px 18px;
    font-size: 12px;
    font-weight: 600;
    letter-spacing: 0.5px;
    border: none;
}
#btn_primary {
    background: #3B82F6;
    color: #FFFFFF;
    padding: 9px 22px;
}
#btn_primary:hover   { background: #2563EB; }
#btn_primary:pressed { background: #1D4ED8; }
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

/* ── Section title ───────────────────────────────────── */
#section_title {
    font-family: "Segoe UI", system-ui, sans-serif;
    font-size: 10px;
    font-weight: 600;
    color: #4B5563;
    letter-spacing: 2px;
    background: transparent;
    padding: 0px 0px 8px 0px;
}

/* ── Table ───────────────────────────────────────────── */
QTableWidget {
    background: #0A0D14;
    border: 1px solid #1E2433;
    border-radius: 10px;
    gridline-color: #141822;
    outline: none;
    alternate-background-color: #0D1018;
    selection-background-color: #1D2D4F;
    selection-color: #E2E8F0;
}
QTableWidget::item {
    padding: 10px 12px;
    border-bottom: 1px solid #141822;
    color: #CBD5E1;
}
QTableWidget::item:selected {
    background: #1D2D4F;
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
QScrollBar::handle:horizontal {
    background: #1E2433;
    border-radius: 4px;
}

/* ── Status bar ──────────────────────────────────────── */
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

/* ── Divider ─────────────────────────────────────────── */
#divider {
    background: #1E2433;
    max-height: 1px;
    min-height: 1px;
    border: none;
}

/* ── Dialog ─────────────────────────────────────────── */
QDialog {
    background: #141822;
    border: 1px solid #1E2433;
    border-radius: 12px;
}
QDialog QLabel { background: transparent; }
"""


def _shadow(radius=24, color="#000000", opacity=120, offset=(0, 4)):
    effect = QGraphicsDropShadowEffect()
    effect.setBlurRadius(radius)
    c = QColor(color)
    c.setAlpha(opacity)
    effect.setColor(c)
    effect.setOffset(*offset)
    return effect


def _accent_bar():
    bar = QFrame()
    bar.setObjectName("header_accent")
    bar.setFixedSize(3, 28)
    return bar


class EntriesPage(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.session = SessionLocal()
        self._entries = []
        self._selected_entry = None
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
        title_lbl = QLabel("ENTRÉES DE STOCK")
        title_lbl.setObjectName("page_title")
        sub_lbl = QLabel("Enregistrer les réceptions et approvisionnements")
        sub_lbl.setObjectName("page_subtitle")
        title_col.addWidget(title_lbl)
        title_col.addWidget(sub_lbl)
        hl.addLayout(title_col)
        hl.addStretch()
        root.addWidget(header)

        # Thin divider
        div = QFrame(); div.setObjectName("divider")
        root.addWidget(div)

        # ── Scrollable content ───────────────────────────────
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

        # Card header
        card_hdr = QFrame()
        card_hdr.setObjectName("card_header")
        card_hdr.setFixedHeight(44)
        chl = QHBoxLayout(card_hdr)
        chl.setContentsMargins(20, 0, 20, 0)
        card_title = QLabel("NOUVELLE ENTRÉE")
        card_title.setObjectName("card_title")
        chl.addWidget(card_title)
        chl.addStretch()
        fc_layout.addWidget(card_hdr)

        # Card body
        card_body = QWidget()
        cbl = QVBoxLayout(card_body)
        cbl.setContentsMargins(20, 18, 20, 18)
        cbl.setSpacing(16)

        # Row 1 – form fields
        row1 = QHBoxLayout(); row1.setSpacing(14)

        self.f_date = QDateEdit(QDate.currentDate())
        self.f_date.setCalendarPopup(True)
        self.f_date.setDisplayFormat("dd/MM/yyyy")

        self.f_supplier = QLineEdit()
        self.f_supplier.setPlaceholderText("Ex: CIMENCAM")

        self.f_reference = QLineEdit()
        self.f_reference.setPlaceholderText("Chercher produit...")
        self.f_reference.textChanged.connect(self._on_ref_changed)
        self._products_map = {}

        self.f_designation = QLineEdit()
        self.f_designation.setReadOnly(True)
        self.f_designation.setPlaceholderText("Auto-rempli")

        self.f_store = QComboBox()

        self.f_quantity = QSpinBox()
        self.f_quantity.setMinimum(1)
        self.f_quantity.setMaximum(9999999)

        row1.addLayout(self._field("DATE *",        self.f_date),        1)
        row1.addLayout(self._field("FOURNISSEUR",   self.f_supplier),    2)
        row1.addLayout(self._field("RÉFÉRENCE *",   self.f_reference),   2)
        row1.addLayout(self._field("DÉSIGNATION",   self.f_designation), 3)
        row1.addLayout(self._field("MAGASIN *",     self.f_store),       2)
        row1.addLayout(self._field("QUANTITÉ *",    self.f_quantity),    1)
        cbl.addLayout(row1)

        # Store hint
        self.store_hint = QLabel("")
        self.store_hint.setObjectName("store_hint_label")
        cbl.addWidget(self.store_hint)

        # Button row
        btn_row = QHBoxLayout()
        btn_row.setSpacing(10)
        btn_row.addStretch()

        self.btn_edit = QPushButton("✎  Modifier")
        self.btn_edit.setObjectName("btn_secondary")
        self.btn_edit.clicked.connect(self._edit_entry)
        self.btn_edit.setEnabled(False)
        self.btn_edit.setCursor(Qt.PointingHandCursor)

        self.btn_delete = QPushButton("🗑  Supprimer")
        self.btn_delete.setObjectName("btn_danger")
        self.btn_delete.clicked.connect(self._delete_entry)
        self.btn_delete.setEnabled(False)
        self.btn_delete.setCursor(Qt.PointingHandCursor)

        self.btn_save = QPushButton("＋  Enregistrer l'entrée")
        self.btn_save.setObjectName("btn_primary")
        self.btn_save.clicked.connect(self._save_entry)
        self.btn_save.setCursor(Qt.PointingHandCursor)

        btn_row.addWidget(self.btn_edit)
        btn_row.addWidget(self.btn_delete)
        btn_row.addWidget(self.btn_save)
        cbl.addLayout(btn_row)

        fc_layout.addWidget(card_body)
        cl.addWidget(form_card)

        # ── History section ─────────────────────────────────
        tbl_title = QLabel("HISTORIQUE DES ENTRÉES")
        tbl_title.setObjectName("section_title")
        cl.addWidget(tbl_title)

        self.table = QTableWidget()
        self.table.setObjectName("entries_table")
        self.table.setColumnCount(7)
        self.table.setHorizontalHeaderLabels([
            "ID", "DATE", "FOURNISSEUR", "RÉFÉRENCE", "DÉSIGNATION", "MAGASIN", "QUANTITÉ"
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
            stretch_columns=[4],
            widths={0: 55, 1: 110}
        )
        self.table.setGraphicsEffect(_shadow(20, "#000000", 80, (0, 4)))
        self.table.itemSelectionChanged.connect(self._on_table_selection_changed)
        self.table.doubleClicked.connect(self._edit_entry)
        cl.addWidget(self.table)

        # Status bar
        self.status = QLabel("")
        self.status.setObjectName("status_ok")
        self.status.hide()
        cl.addWidget(self.status)

        self._load_combos()
        self.refresh()

    # ──────────────────────────────────────────────────────────
    @staticmethod
    def _field(label_text: str, widget: QWidget) -> QVBoxLayout:
        """Styled field with uppercase label above widget."""
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
            self._reload_stores()
        except Exception as e:
            print(f"[Entries] _load_combos: {e}")

    def _setup_product_completer(self, products_list):
        model = QStringListModel(products_list)
        completer = QCompleter(model)
        completer.setCaseSensitivity(Qt.CaseInsensitive)
        completer.setCompletionMode(QCompleter.PopupCompletion)
        self.f_reference.setCompleter(completer)

    def _reload_stores(self, product_store_id=None):
        """
        Recharge la liste des magasins.
        Le magasin assigné au produit est placé en premier pour faciliter
        la saisie, mais tous les magasins restent sélectionnables.
        """
        self.f_store.blockSignals(True)
        self.f_store.clear()

        stores = self.session.query(Store).order_by(Store.name).all()

        if product_store_id is not None:
            # Magasin assigné en premier, puis les autres
            assigned = [s for s in stores if s.id == product_store_id]
            others   = [s for s in stores if s.id != product_store_id]
            for s in assigned + others:
                self.f_store.addItem(s.name, s.id)
            self.f_store.setEnabled(True)
            if assigned:
                self.store_hint.setText(f"ℹ  Magasin habituel : {assigned[0].name} — vous pouvez en choisir un autre")
            else:
                self.store_hint.setText("")
        else:
            for s in stores:
                self.f_store.addItem(s.name, s.id)
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
                # Récupérer les magasins où ce produit a un stock défini
                ps_list = self.session.query(ProductStock).filter_by(product_id=p.id).all()
                first_store_id = ps_list[0].store_id if ps_list else None
                self._reload_stores(product_store_id=first_store_id)
            else:
                self.f_designation.clear()
                self._reload_stores(product_store_id=None)
        else:
            self.f_designation.clear()
            self._reload_stores(product_store_id=None)

    # ──────────────────────────────────────────────────────────
    def _save_entry(self):
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

        try:
            p = self.session.query(Product).filter_by(reference=ref).first()
            entry = StockEntry(
                date=date_str,
                supplier=self.f_supplier.text().strip(),
                reference=ref,
                designation=p.designation if p else ref,
                store_id=store_id,
                quantity=qty,
            )
            self.session.add(entry)
            self.session.commit()

            self.f_supplier.clear()
            self.f_reference.clear()
            self.f_designation.clear()
            self.f_quantity.setValue(1)
            self._set_status(f"Entrée enregistrée : {qty} × {ref}.")
            self.refresh()
        except Exception as e:
            self.session.rollback()
            self._set_status(f"Erreur : {e}", error=True)

    # ──────────────────────────────────────────────────────────
    def refresh(self):
        self._load_combos()
        try:
            self.session.expire_all()
            entries = (
                self.session.query(StockEntry, Store.name)
                .join(Store, StockEntry.store_id == Store.id)
                .order_by(StockEntry.date.desc(), StockEntry.id.desc())
                .all()
            )
            self._entries = entries
            self._selected_entry = None
            self.btn_edit.setEnabled(False)
            self.btn_delete.setEnabled(False)
            self.table.setRowCount(len(entries))
            for row, (e, store_name) in enumerate(entries):
                for col, text in enumerate([
                    str(e.id), e.date, e.supplier, e.reference,
                    e.designation, store_name, str(e.quantity)
                ]):
                    item = QTableWidgetItem(text)
                    item.setTextAlignment(Qt.AlignVCenter | Qt.AlignLeft)
                    if col == 6:
                        item.setForeground(QColor("#4ADE80"))
                        item.setTextAlignment(Qt.AlignVCenter | Qt.AlignRight)
                        item.setText(f"+ {text}")
                    elif col == 0:
                        item.setForeground(QColor("#374151"))
                    self.table.setItem(row, col, item)
        except Exception as e:
            print(f"[Entries] refresh: {e}")

    # ──────────────────────────────────────────────────────────
    def _set_status(self, msg: str, error: bool = False):
        self.status.setText(msg)
        self.status.setObjectName("status_err" if error else "status_ok")
        self.status.setStyleSheet("")          # force style refresh
        self.status.style().unpolish(self.status)
        self.status.style().polish(self.status)
        self.status.show()

    def _on_table_selection_changed(self):
        selected = self.table.selectedItems()
        if not selected:
            self._selected_entry = None
            self.btn_edit.setEnabled(False)
            self.btn_delete.setEnabled(False)
            return
        row = self.table.currentRow()
        if row < 0 or row >= len(self._entries):
            self._selected_entry = None
            self.btn_edit.setEnabled(False)
            self.btn_delete.setEnabled(False)
            return
        self._selected_entry = self._entries[row][0]
        self.btn_edit.setEnabled(True)
        self.btn_delete.setEnabled(True)

    def _delete_entry(self):
        if not self._selected_entry:
            return
        reply = QMessageBox.question(
            self, "Confirmer la suppression",
            "Voulez-vous supprimer cette entrée ?",
            QMessageBox.Yes | QMessageBox.No
        )
        if reply != QMessageBox.Yes:
            return
        try:
            self.session.delete(self._selected_entry)
            self.session.commit()
            self.refresh()
            self._set_status("Entrée supprimée.")
        except Exception as e:
            self.session.rollback()
            self._set_status(f"Erreur suppression : {e}", error=True)

    def _edit_entry(self):
        if not self._selected_entry:
            return
        entry = self.session.get(StockEntry, self._selected_entry.id)
        if not entry:
            self._set_status("Entrée introuvable.", error=True)
            return

        dlg = QDialog(self)
        dlg.setWindowTitle("Modifier l'entrée")
        dlg.setMinimumWidth(480)
        dlg.setStyleSheet(STYLE)
        dlg_layout = QVBoxLayout(dlg)
        dlg_layout.setContentsMargins(24, 24, 24, 24)
        dlg_layout.setSpacing(14)

        # Dialog header
        dlg_hdr = QHBoxLayout()
        dlg_hdr.setSpacing(10)
        dlg_hdr.addWidget(_accent_bar())
        dlg_title = QLabel("MODIFIER L'ENTRÉE")
        dlg_title.setObjectName("card_title")
        dlg_hdr.addWidget(dlg_title)
        dlg_hdr.addStretch()
        dlg_layout.addLayout(dlg_hdr)

        divider = QFrame(); divider.setObjectName("divider")
        dlg_layout.addWidget(divider)

        # Fields
        date_edit = QDateEdit()
        date_edit.setCalendarPopup(True)
        date_edit.setDisplayFormat("dd/MM/yyyy")
        try:
            year, month, day = map(int, entry.date.split("-"))
            date_edit.setDate(QDate(year, month, day))
        except Exception:
            date_edit.setDate(QDate.currentDate())
        dlg_layout.addLayout(self._field("DATE", date_edit))

        supplier_edit = QLineEdit(entry.supplier)
        dlg_layout.addLayout(self._field("FOURNISSEUR", supplier_edit))

        ref_edit = QComboBox()
        ref_edit.addItem("— Sélectionner —", None)
        for p in self.session.query(Product).order_by(Product.reference).all():
            ref_edit.addItem(f"{p.reference} — {p.designation}", p.reference)
            if p.reference == entry.reference:
                ref_edit.setCurrentText(f"{p.reference} — {p.designation}")
        dlg_layout.addLayout(self._field("RÉFÉRENCE", ref_edit))

        desig_edit = QLineEdit(entry.designation)
        desig_edit.setReadOnly(True)
        dlg_layout.addLayout(self._field("DÉSIGNATION", desig_edit))

        # Magasin : tous les magasins disponibles, aucun verrouillage
        store_edit = QComboBox()
        for s in self.session.query(Store).order_by(Store.name).all():
            store_edit.addItem(s.name, s.id)
            if s.id == entry.store_id:
                store_edit.setCurrentText(s.name)
        dlg_layout.addLayout(self._field("MAGASIN", store_edit))

        qty_edit = QSpinBox()
        qty_edit.setMinimum(1)
        qty_edit.setMaximum(9999999)
        qty_edit.setValue(entry.quantity)
        dlg_layout.addLayout(self._field("QUANTITÉ", qty_edit))

        # Buttons
        btn_box_layout = QHBoxLayout()
        btn_box_layout.setSpacing(10)
        btn_cancel = QPushButton("Annuler")
        btn_cancel.setObjectName("btn_secondary")
        btn_cancel.setCursor(Qt.PointingHandCursor)
        btn_save_dlg = QPushButton("Enregistrer")
        btn_save_dlg.setObjectName("btn_primary")
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
            entry.date = date_edit.date().toString("yyyy-MM-dd")
            entry.supplier = supplier_edit.text().strip()
            entry.reference = ref_val
            entry.designation = product.designation if product else entry.designation
            entry.store_id = store_edit.currentData()
            entry.quantity = qty_edit.value()
            try:
                self.session.commit()
                dlg.accept()
                self.refresh()
                self._set_status("Entrée mise à jour.")
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