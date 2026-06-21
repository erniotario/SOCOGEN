"""
ui/stores_page.py — Gestion des magasins
"""
from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QLabel, QLineEdit,
    QPushButton, QTableWidget, QTableWidgetItem, QHeaderView,
    QFrame, QMessageBox
)
from PySide6.QtCore import Qt
from PySide6.QtGui import QColor, QFont

from database import SessionLocal
from models import Store, Product, ProductStock, StockEntry, StockOutput
from ui.utils import hline, page_header

# ─────────────────────────────────────────────────────────────────────────────
_C = {
    "bg":       "#0D1117",
    "surface":  "#161B22",
    "surface2": "#1C2128",
    "border":   "#30363D",
    "border2":  "#21262D",
    "accent":   "#58A6FF",
    "accent2":  "#1F6FEB",
    "green":    "#3FB950",
    "red":      "#F85149",
    "orange":   "#D29922",
    "text":     "#E6EDF3",
    "muted":    "#7D8590",
    "label":    "#8B949E",
}

_TABLE_STYLE = f"""
    QTableWidget {{
        background: {_C['bg']};
        gridline-color: {_C['border2']};
        color: {_C['text']};
        border: 1px solid {_C['border']};
        border-radius: 8px;
        font-size: 13px;
        outline: none;
    }}
    QTableWidget::item {{
        padding: 6px 10px;
        border: none;
    }}
    QTableWidget::item:selected {{
        background: #1C3461;
        color: {_C['text']};
    }}
    QHeaderView::section {{
        background: {_C['surface2']};
        color: {_C['label']};
        font-size: 11px;
        font-weight: 700;
        letter-spacing: 0.8px;
        padding: 8px 10px;
        border: none;
        border-bottom: 2px solid {_C['accent2']};
        border-right: 1px solid {_C['border']};
    }}
    QScrollBar:vertical {{
        background: {_C['surface']};
        width: 8px; border-radius: 4px;
    }}
    QScrollBar::handle:vertical {{
        background: {_C['border']};
        border-radius: 4px; min-height: 30px;
    }}
"""

_BTN_PRIMARY = f"""
    QPushButton {{
        background: {_C['accent2']}; color: white; border: none;
        border-radius: 6px; font-size: 12px; font-weight: 600; padding: 7px 16px;
    }}
    QPushButton:hover {{ background: #388BFD; }}
    QPushButton:pressed {{ background: #1158C7; }}
    QPushButton:disabled {{ background: {_C['border']}; color: {_C['muted']}; }}
"""
_BTN_SECONDARY = f"""
    QPushButton {{
        background: {_C['surface']}; color: {_C['text']};
        border: 1px solid {_C['border']}; border-radius: 6px;
        font-size: 12px; font-weight: 600; padding: 7px 16px;
    }}
    QPushButton:hover {{ background: {_C['surface2']}; border-color: {_C['accent']}; }}
    QPushButton:disabled {{ color: {_C['muted']}; }}
"""
_BTN_DANGER = f"""
    QPushButton {{
        background: transparent; color: {_C['red']};
        border: 1px solid {_C['red']}; border-radius: 6px;
        font-size: 12px; font-weight: 600; padding: 7px 16px;
    }}
    QPushButton:hover {{ background: rgba(248,81,73,0.12); }}
"""
_INPUT_STYLE = f"""
    QLineEdit {{
        background: {_C['bg']}; border: 1px solid {_C['border']};
        border-radius: 6px; color: {_C['text']};
        font-size: 13px; padding: 7px 10px;
    }}
    QLineEdit:focus {{ border-color: {_C['accent']}; }}
    QLineEdit::placeholder {{ color: {_C['muted']}; }}
"""
_FORM_STYLE = f"""
    QWidget#form_card {{
        background: {_C['surface']};
        border: 1px solid {_C['border']};
        border-radius: 10px;
    }}
"""


class StoresPage(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.session = SessionLocal()
        self._editing_id = None
        self._build_ui()

    # ── UI ────────────────────────────────────────────────────────────────
    def _build_ui(self):
        root = QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)
        self.setStyleSheet(f"QWidget {{ background: {_C['bg']}; }}")

        root.addWidget(page_header("Magasins", "Gérer les points de stockage"))
        root.addWidget(hline())

        content = QWidget()
        cl = QVBoxLayout(content)
        cl.setContentsMargins(28, 16, 28, 16)
        cl.setSpacing(12)
        root.addWidget(content)

        # ── Barre d'actions ──────────────────────────────────────────────
        bar = QHBoxLayout(); bar.setSpacing(10)
        title = QLabel("LISTE DES MAGASINS")
        title.setStyleSheet(f"color:{_C['label']};font-size:11px;font-weight:700;"
                            f"letter-spacing:1px;background:transparent;")
        bar.addWidget(title, alignment=Qt.AlignVCenter)
        bar.addStretch()

        self.btn_new    = QPushButton("＋  Nouveau magasin")
        self.btn_edit   = QPushButton("✎  Modifier")
        self.btn_delete = QPushButton("🗑  Supprimer")
        self.btn_new.setStyleSheet(_BTN_PRIMARY)
        self.btn_edit.setStyleSheet(_BTN_SECONDARY)
        self.btn_delete.setStyleSheet(_BTN_DANGER)
        self.btn_new.clicked.connect(self._show_form_new)
        self.btn_edit.clicked.connect(self._show_form_edit)
        self.btn_delete.clicked.connect(self._delete_store)
        bar.addWidget(self.btn_new)
        bar.addWidget(self.btn_edit)
        bar.addWidget(self.btn_delete)
        cl.addLayout(bar)

        # ── Layout principal : tableau + stats côte à côte ───────────────
        main_row = QHBoxLayout(); main_row.setSpacing(16)

        # ── Tableau ──────────────────────────────────────────────────────
        self.table = QTableWidget()
        self.table.setColumnCount(4)
        self.table.setHorizontalHeaderLabels(["ID", "NOM DU MAGASIN", "PRODUITS", "STOCK TOTAL"])
        self.table.setStyleSheet(_TABLE_STYLE)
        self.table.setSelectionBehavior(QTableWidget.SelectRows)
        self.table.setSelectionMode(QTableWidget.SingleSelection)
        self.table.setEditTriggers(QTableWidget.NoEditTriggers)
        self.table.verticalHeader().setVisible(False)
        self.table.horizontalHeader().setSectionResizeMode(1, QHeaderView.Stretch)
        self.table.setColumnWidth(0, 50)
        self.table.setColumnWidth(2, 100)
        self.table.setColumnWidth(3, 130)
        self.table.itemSelectionChanged.connect(self._on_selection_changed)
        main_row.addWidget(self.table, stretch=3)

        # ── Panneau stats ─────────────────────────────────────────────────
        self.stats_panel = QWidget()
        self.stats_panel.setFixedWidth(220)
        self.stats_panel.setStyleSheet(f"""
            QWidget {{
                background: {_C['surface']};
                border: 1px solid {_C['border']};
                border-radius: 10px;
            }}
        """)
        sp_lay = QVBoxLayout(self.stats_panel)
        sp_lay.setContentsMargins(16, 16, 16, 16)
        sp_lay.setSpacing(14)

        lbl_stats_title = QLabel("DÉTAILS")
        lbl_stats_title.setStyleSheet(
            f"color:{_C['accent']};font-size:11px;font-weight:700;"
            f"letter-spacing:1px;background:transparent;border:none;"
        )
        sp_lay.addWidget(lbl_stats_title)

        sep = QFrame(); sep.setFrameShape(QFrame.HLine)
        sep.setStyleSheet(f"color:{_C['border2']};border:none;background:{_C['border2']};max-height:1px;")
        sp_lay.addWidget(sep)

        self._stat_widgets = {}
        for key, label in [
            ("name",    "Magasin"),
            ("prods",   "Produits"),
            ("entries", "Total entrées"),
            ("outputs", "Total sorties"),
            ("stock",   "Stock actuel"),
        ]:
            row_w = QWidget(); row_w.setStyleSheet("background:transparent;border:none;")
            row_l = QVBoxLayout(row_w); row_l.setContentsMargins(0,0,0,0); row_l.setSpacing(2)
            lbl_k = QLabel(label.upper())
            lbl_k.setStyleSheet(f"color:{_C['muted']};font-size:10px;background:transparent;border:none;")
            lbl_v = QLabel("—")
            lbl_v.setStyleSheet(f"color:{_C['text']};font-size:14px;font-weight:700;background:transparent;border:none;")
            lbl_v.setWordWrap(True)
            row_l.addWidget(lbl_k); row_l.addWidget(lbl_v)
            sp_lay.addWidget(row_w)
            self._stat_widgets[key] = lbl_v

        sp_lay.addStretch()
        main_row.addWidget(self.stats_panel, stretch=0)
        cl.addLayout(main_row, stretch=1)

        # ── Statut ────────────────────────────────────────────────────────
        self.status = QLabel("")
        self.status.setStyleSheet(f"color:{_C['muted']};font-size:12px;padding:4px 2px;background:transparent;")
        cl.addWidget(self.status)

        # ── Formulaire ────────────────────────────────────────────────────
        self.form_card = QWidget()
        self.form_card.setObjectName("form_card")
        self.form_card.setStyleSheet(_FORM_STYLE)
        self.form_card.setVisible(False)

        fc = QVBoxLayout(self.form_card)
        fc.setContentsMargins(20, 16, 20, 16)
        fc.setSpacing(12)

        self.form_title = QLabel("NOUVEAU MAGASIN")
        self.form_title.setStyleSheet(
            f"color:{_C['accent']};font-size:11px;font-weight:700;letter-spacing:1px;background:transparent;"
        )
        fc.addWidget(self.form_title)

        sep2 = QFrame(); sep2.setFrameShape(QFrame.HLine)
        sep2.setStyleSheet(f"color:{_C['border2']};")
        fc.addWidget(sep2)

        input_row = QHBoxLayout(); input_row.setSpacing(12)
        lbl_name = QLabel("Nom du magasin *")
        lbl_name.setStyleSheet(f"color:{_C['label']};font-size:11px;font-weight:600;background:transparent;")

        self.f_name = QLineEdit()
        self.f_name.setPlaceholderText("Ex : Magasin Central, Entrepôt Nord…")
        self.f_name.setStyleSheet(_INPUT_STYLE)
        self.f_name.setMinimumWidth(300)

        name_w = QWidget(); name_w.setStyleSheet("background:transparent;")
        name_l = QVBoxLayout(name_w); name_l.setContentsMargins(0,0,0,0); name_l.setSpacing(4)
        name_l.addWidget(lbl_name); name_l.addWidget(self.f_name)
        input_row.addWidget(name_w)
        input_row.addStretch()

        self.btn_save   = QPushButton("＋  Ajouter")
        self.btn_cancel = QPushButton("✕  Annuler")
        self.btn_save.setStyleSheet(_BTN_PRIMARY)
        self.btn_cancel.setStyleSheet(_BTN_DANGER)
        self.btn_save.clicked.connect(self._save_store)
        self.btn_cancel.clicked.connect(self._hide_form)
        input_row.addWidget(self.btn_save)
        input_row.addWidget(self.btn_cancel)
        fc.addLayout(input_row)

        cl.addWidget(self.form_card)
        self.refresh()

    # ── Formulaire ────────────────────────────────────────────────────────
    def _show_form_new(self):
        self._editing_id = None
        self.f_name.clear()
        self.form_title.setText("NOUVEAU MAGASIN")
        self.btn_save.setText("＋  Ajouter")
        self.btn_save.setStyleSheet(_BTN_PRIMARY)
        self.form_card.setVisible(True)
        self.f_name.setFocus()

    def _show_form_edit(self):
        rows = self.table.selectionModel().selectedRows()
        if not rows:
            self._set_status("Sélectionnez un magasin à modifier.", error=True); return
        store_id = int(self.table.item(rows[0].row(), 0).text())
        store    = self.session.get(Store, store_id)
        if not store:
            return
        self._editing_id = store_id
        self.f_name.setText(store.name)
        self.form_title.setText("MODIFIER LE MAGASIN")
        self.btn_save.setText("💾  Enregistrer")
        self.btn_save.setStyleSheet(_BTN_PRIMARY.replace(_C["accent2"], "#1E8449"))
        self.form_card.setVisible(True)
        self.f_name.setFocus()

    def _hide_form(self):
        self.form_card.setVisible(False)
        self._editing_id = None
        self.f_name.clear()

    # ── CRUD ──────────────────────────────────────────────────────────────
    def _save_store(self):
        name = self.f_name.text().strip()
        if not name:
            self._set_status("Le nom du magasin est obligatoire.", error=True); return

        try:
            # Vérifier doublon
            existing = self.session.query(Store).filter_by(name=name).first()
            if existing and existing.id != self._editing_id:
                self._set_status(f"Le magasin « {name} » existe déjà.", error=True); return

            if self._editing_id:
                store = self.session.get(Store, self._editing_id)
                store.name = name
                msg = f"Magasin « {name} » mis à jour."
            else:
                store = Store(name=name)
                self.session.add(store)
                msg = f"Magasin « {name} » ajouté."

            self.session.commit()
            self._hide_form()
            self._set_status(msg)
            self.refresh()
        except Exception as e:
            self.session.rollback()
            self._set_status(f"Erreur : {e}", error=True)

    def _delete_store(self):
        rows = self.table.selectionModel().selectedRows()
        if not rows:
            self._set_status("Sélectionnez un magasin à supprimer.", error=True); return

        store_id   = int(self.table.item(rows[0].row(), 0).text())
        store_name = self.table.item(rows[0].row(), 1).text()

        # Vérifier s'il y a des mouvements liés
        has_entries = self.session.query(StockEntry).filter_by(store_id=store_id).first()
        has_outputs = self.session.query(StockOutput).filter_by(store_id=store_id).first()
        has_stocks  = self.session.query(ProductStock).filter_by(store_id=store_id).first()

        if has_entries or has_outputs or has_stocks:
            reply = QMessageBox.question(
                self, "Confirmation",
                f"Le magasin « {store_name} » contient des données de stock.\n"
                f"Supprimer quand même ?",
                QMessageBox.Yes | QMessageBox.No
            )
            if reply != QMessageBox.Yes:
                return

        try:
            store = self.session.get(Store, store_id)
            if store:
                self.session.delete(store)
                self.session.commit()
                self._set_status(f"Magasin « {store_name} » supprimé.")
                self.refresh()
        except Exception as e:
            self.session.rollback()
            self._set_status(f"Erreur : {e}", error=True)

    # ── Sélection → stats ─────────────────────────────────────────────────
    def _on_selection_changed(self):
        rows = self.table.selectionModel().selectedRows()
        if not rows:
            for v in self._stat_widgets.values():
                v.setText("—")
                v.setStyleSheet(f"color:{_C['text']};font-size:14px;font-weight:700;background:transparent;border:none;")
            return

        store_id   = int(self.table.item(rows[0].row(), 0).text())
        store_name = self.table.item(rows[0].row(), 1).text()
        store      = self.session.get(Store, store_id)
        if not store:
            return

        from sqlalchemy import func

        # Nombre de produits dans ce magasin
        nb_prods = self.session.query(ProductStock).filter_by(store_id=store_id).count()

        # Total entrées
        total_in = self.session.query(func.sum(StockEntry.quantity)).filter_by(
            store_id=store_id).scalar() or 0

        # Total sorties
        total_out = self.session.query(func.sum(StockOutput.quantity)).filter_by(
            store_id=store_id).scalar() or 0

        # Stock actuel = stock initial + entrées - sorties
        init = self.session.query(func.sum(ProductStock.initial_stock)).filter_by(
            store_id=store_id).scalar() or 0
        stock_actuel = init + total_in - total_out

        color_stock = _C["green"] if stock_actuel > 0 else (_C["red"] if stock_actuel < 0 else _C["muted"])

        self._stat_widgets["name"].setText(store_name)
        self._stat_widgets["prods"].setText(str(nb_prods))
        self._stat_widgets["entries"].setText(f"+{total_in}")
        self._stat_widgets["outputs"].setText(f"-{total_out}")
        self._stat_widgets["stock"].setText(str(stock_actuel))
        self._stat_widgets["stock"].setStyleSheet(
            f"color:{color_stock};font-size:14px;font-weight:700;background:transparent;border:none;"
        )

    # ── Refresh ───────────────────────────────────────────────────────────
    def refresh(self):
        try:
            self.session.expire_all()
            from sqlalchemy import func

            stores = self.session.query(Store).order_by(Store.name).all()
            self.table.setRowCount(len(stores))

            for i, store in enumerate(stores):
                nb_prods = self.session.query(ProductStock).filter_by(store_id=store.id).count()

                init = self.session.query(func.sum(ProductStock.initial_stock)).filter_by(
                    store_id=store.id).scalar() or 0
                total_in  = self.session.query(func.sum(StockEntry.quantity)).filter_by(
                    store_id=store.id).scalar() or 0
                total_out = self.session.query(func.sum(StockOutput.quantity)).filter_by(
                    store_id=store.id).scalar() or 0
                stock_total = init + total_in - total_out

                bg = QColor("#0D1F2D") if i % 2 == 0 else QColor(_C["bg"])
                color_stock = _C["green"] if stock_total > 0 else (_C["red"] if stock_total < 0 else _C["muted"])

                data = [
                    (str(store.id),    _C["muted"],   False, Qt.AlignVCenter | Qt.AlignHCenter),
                    (store.name,       _C["accent"],  True,  Qt.AlignVCenter | Qt.AlignLeft),
                    (str(nb_prods),    _C["text"],    False, Qt.AlignVCenter | Qt.AlignHCenter),
                    (str(stock_total), color_stock,   True,  Qt.AlignVCenter | Qt.AlignRight),
                ]
                for col, (text, color, bold, align) in enumerate(data):
                    item = QTableWidgetItem(text)
                    item.setBackground(bg)
                    item.setForeground(QColor(color))
                    item.setTextAlignment(align)
                    if bold:
                        from PySide6.QtGui import QFont
                        item.setFont(QFont("Segoe UI", 9, QFont.Bold))
                    self.table.setItem(i, col, item)
                self.table.setRowHeight(i, 40)

            self.status.setText(f"  {len(stores)} magasin(s)")
        except Exception as e:
            print(f"[Stores] refresh: {e}")

    # ── Statut ────────────────────────────────────────────────────────────
    def _set_status(self, msg, error=False):
        color = _C["red"] if error else _C["green"]
        icon  = "✕  " if error else "✓  "
        self.status.setText(icon + msg)
        self.status.setStyleSheet(
            f"color:{color};font-size:12px;font-weight:600;padding:4px 2px;background:transparent;"
        )
