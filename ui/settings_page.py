"""
Page Paramètres — informations de la société
imprimées en en-tête des rapports PDF.
UI modernisée : design premium finance dashboard, cohérent avec TransactionsPage.
"""
from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QLabel, QLineEdit,
    QFileDialog, QPushButton, QFrame, QScrollArea, QSizePolicy
)
from PySide6.QtCore import Qt, QPropertyAnimation, QEasingCurve, QTimer
from PySide6.QtGui import QPixmap, QColor

from database import SessionLocal
from models import CompanySettings


# ═══════════════════════════════════════════════════════════════════════════
#  Palette & style  (identique à TransactionsPage)
# ═══════════════════════════════════════════════════════════════════════════
PALETTE = {
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
}

APP_STYLE = f"""
QWidget {{
    background-color: {PALETTE['bg_surface']};
    color: {PALETTE['text_primary']};
    font-family: "Segoe UI", "SF Pro Text", system-ui, sans-serif;
    font-size: 13px;
}}
QScrollArea {{
    border: none;
    background: transparent;
}}
QScrollArea > QWidget > QWidget {{
    background: transparent;
}}
QScrollBar:vertical {{
    background: {PALETTE['bg_base']};
    width: 6px; border-radius: 3px; margin: 0;
}}
QScrollBar::handle:vertical {{
    background: {PALETTE['border']};
    border-radius: 3px; min-height: 30px;
}}
QScrollBar::handle:vertical:hover {{ background: {PALETTE['text_muted']}; }}
QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {{ height: 0; }}

QLineEdit {{
    background-color: {PALETTE['bg_elevated']};
    border: 1px solid {PALETTE['border']};
    border-radius: 6px;
    padding: 9px 12px;
    color: {PALETTE['text_primary']};
    font-size: 13px;
    selection-background-color: {PALETTE['accent_blue']};
}}
QLineEdit:hover {{
    border-color: {PALETTE['text_muted']};
}}
QLineEdit:focus {{
    border-color: {PALETTE['border_focus']};
    background-color: {PALETTE['bg_highlight']};
}}
QLineEdit::placeholder {{
    color: {PALETTE['text_muted']};
}}

QPushButton {{
    background-color: {PALETTE['bg_elevated']};
    color: {PALETTE['text_primary']};
    border: 1px solid {PALETTE['border']};
    border-radius: 6px;
    padding: 8px 18px;
    font-size: 12px;
    font-weight: 500;
    min-width: 80px;
}}
QPushButton:hover {{
    background-color: {PALETTE['bg_hover']};
    border-color: {PALETTE['text_muted']};
}}
QPushButton:pressed {{
    background-color: {PALETTE['bg_base']};
}}
#btn_primary {{
    background-color: {PALETTE['accent_blue']};
    color: white;
    border: 1px solid {PALETTE['accent_blue']};
    font-weight: 600;
    font-size: 13px;
}}
#btn_primary:hover {{
    background-color: {PALETTE['accent_blue_lt']};
    border-color: {PALETTE['accent_blue_lt']};
}}
#btn_danger {{
    color: {PALETTE['accent_red']};
    border-color: {PALETTE['border']};
    background: transparent;
}}
#btn_danger:hover {{
    background-color: #2D1117;
    border-color: {PALETTE['accent_red']};
}}

#section_card {{
    background-color: {PALETTE['bg_elevated']};
    border: 1px solid {PALETTE['border']};
    border-radius: 10px;
}}
#field_label {{
    color: {PALETTE['text_muted']};
    font-size: 10px;
    font-weight: 700;
    letter-spacing: 0.8px;
    background: transparent;
}}
#section_title {{
    color: {PALETTE['text_secondary']};
    font-size: 10px;
    font-weight: 700;
    letter-spacing: 1.2px;
    background: transparent;
}}
#logo_drop_zone {{
    background-color: {PALETTE['bg_base']};
    border: 1px dashed {PALETTE['border']};
    border-radius: 8px;
    color: {PALETTE['text_muted']};
}}
#logo_drop_zone:hover {{
    border-color: {PALETTE['accent_blue']};
    background-color: {PALETTE['bg_highlight']};
}}
#status_ok {{
    color: {PALETTE['accent_green']};
    background: transparent;
    font-size: 12px;
}}
#status_err {{
    color: {PALETTE['accent_red']};
    background: transparent;
    font-size: 12px;
}}
#hint_label {{
    color: {PALETTE['text_muted']};
    font-size: 11px;
    background: transparent;
}}
#required_star {{
    color: {PALETTE['accent_red']};
    background: transparent;
    font-size: 11px;
}}
"""


# ═══════════════════════════════════════════════════════════════════════════
#  Widget helpers
# ═══════════════════════════════════════════════════════════════════════════

def _hline():
    line = QFrame()
    line.setFrameShape(QFrame.HLine)
    line.setFixedHeight(1)
    line.setStyleSheet(f"background: {PALETTE['border']}; border: none;")
    return line


def _field_widget(label_text, widget, hint=None, required=False):
    """Label + input + hint optionnel, dans un bloc vertical."""
    container = QWidget()
    container.setStyleSheet("background: transparent;")
    lay = QVBoxLayout(container)
    lay.setContentsMargins(0, 0, 0, 0)
    lay.setSpacing(5)

    # Label row
    lbl_row = QWidget(); lbl_row.setStyleSheet("background: transparent;")
    lbl_lay = QHBoxLayout(lbl_row)
    lbl_lay.setContentsMargins(0, 0, 0, 0)
    lbl_lay.setSpacing(3)
    lbl = QLabel(label_text.upper())
    lbl.setObjectName("field_label")
    lbl_lay.addWidget(lbl)
    if required:
        star = QLabel("*")
        star.setObjectName("required_star")
        lbl_lay.addWidget(star)
    lbl_lay.addStretch()
    lay.addWidget(lbl_row)

    lay.addWidget(widget)

    if hint:
        h = QLabel(hint)
        h.setObjectName("hint_label")
        lay.addWidget(h)

    return container


def _section_card(title, icon=""):
    """Carte avec titre de section."""
    card = QWidget()
    card.setObjectName("section_card")
    lay = QVBoxLayout(card)
    lay.setContentsMargins(22, 18, 22, 20)
    lay.setSpacing(16)

    # En-tête de section
    hdr = QWidget(); hdr.setStyleSheet("background: transparent;")
    hdr_lay = QHBoxLayout(hdr)
    hdr_lay.setContentsMargins(0, 0, 0, 0)
    hdr_lay.setSpacing(8)

    if icon:
        ic = QLabel(icon)
        ic.setStyleSheet(f"color: {PALETTE['accent_blue']}; font-size: 14px; background: transparent;")
        hdr_lay.addWidget(ic)

    t = QLabel(title)
    t.setObjectName("section_title")
    hdr_lay.addWidget(t)
    hdr_lay.addStretch()
    lay.addWidget(hdr)
    lay.addWidget(_hline())

    return card, lay


# ═══════════════════════════════════════════════════════════════════════════
#  SettingsPage
# ═══════════════════════════════════════════════════════════════════════════
class SettingsPage(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.session = SessionLocal()
        self._logo_path = ""
        self.setStyleSheet(APP_STYLE)
        self._build_ui()

    # ──────────────────────────────────────────────────────────────────────
    def _build_ui(self):
        root = QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        # ── En-tête de page ────────────────────────────────────────────
        root.addWidget(self._build_header())
        root.addWidget(_hline())

        # ── Zone scrollable ────────────────────────────────────────────
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)

        scroll_content = QWidget()
        scroll_content.setStyleSheet(f"background: {PALETTE['bg_base']};")
        sc_lay = QVBoxLayout(scroll_content)
        sc_lay.setContentsMargins(28, 24, 28, 28)
        sc_lay.setSpacing(16)

        # ── Carte 1 : Identité ─────────────────────────────────────────
        sc_lay.addWidget(self._build_identity_card())

        # ── Carte 2 : Contact ──────────────────────────────────────────
        sc_lay.addWidget(self._build_contact_card())

        # ── Carte 3 : Logo ─────────────────────────────────────────────
        sc_lay.addWidget(self._build_logo_card())

        # ── Barre d'actions ────────────────────────────────────────────
        sc_lay.addWidget(self._build_action_bar())

        sc_lay.addStretch()
        scroll.setWidget(scroll_content)
        root.addWidget(scroll, 1)

        self.refresh()

    # ── En-tête ────────────────────────────────────────────────────────────
    def _build_header(self):
        w = QWidget()
        w.setFixedHeight(56)
        w.setStyleSheet(f"background: {PALETTE['bg_surface']};")
        lay = QHBoxLayout(w)
        lay.setContentsMargins(24, 0, 24, 0)
        lay.setSpacing(8)

        title_grp = QWidget(); title_grp.setStyleSheet("background: transparent;")
        tgl = QVBoxLayout(title_grp); tgl.setContentsMargins(0, 0, 0, 0); tgl.setSpacing(1)

        lbl_title = QLabel("Paramètres")
        lbl_title.setStyleSheet(
            f"color: {PALETTE['text_primary']}; font-size: 15px; font-weight: 700; background: transparent;"
        )
        lbl_sub = QLabel("Informations affichées dans les en-têtes des rapports PDF")
        lbl_sub.setStyleSheet(
            f"color: {PALETTE['text_muted']}; font-size: 11px; background: transparent;"
        )
        tgl.addWidget(lbl_title)
        tgl.addWidget(lbl_sub)
        lay.addWidget(title_grp)
        lay.addStretch()
        return w

    # ── Carte Identité ─────────────────────────────────────────────────────
    def _build_identity_card(self):
        card, lay = _section_card("IDENTITÉ DE LA SOCIÉTÉ", "◈")

        # Ligne 1 : nom / contribuable / RCCM
        row1 = QHBoxLayout(); row1.setSpacing(14)
        self.f_name   = QLineEdit(); self.f_name.setPlaceholderText("Ex : SOCOGEN SARL")
        self.f_name.setFixedHeight(38)
        self.f_tax_id = QLineEdit(); self.f_tax_id.setPlaceholderText("Ex : M123456789")
        self.f_tax_id.setFixedHeight(38)
        self.f_rccm   = QLineEdit(); self.f_rccm.setPlaceholderText("Ex : RC/YAO/2020/B/1234")
        self.f_rccm.setFixedHeight(38)
        row1.addWidget(_field_widget("Nom de la société", self.f_name, required=True), 3)
        row1.addWidget(_field_widget("N° Contribuable", self.f_tax_id), 2)
        row1.addWidget(_field_widget("RCCM", self.f_rccm), 2)
        lay.addLayout(row1)

        # Ligne 2 : adresse / ville
        row2 = QHBoxLayout(); row2.setSpacing(14)
        self.f_address = QLineEdit(); self.f_address.setPlaceholderText("Ex : BP 1234, Rue des Palmiers")
        self.f_address.setFixedHeight(38)
        self.f_city    = QLineEdit(); self.f_city.setPlaceholderText("Ex : Yaoundé, Cameroun")
        self.f_city.setFixedHeight(38)
        row2.addWidget(_field_widget("Adresse", self.f_address), 3)
        row2.addWidget(_field_widget("Ville / Pays", self.f_city), 2)
        lay.addLayout(row2)

        return card

    # ── Carte Contact ──────────────────────────────────────────────────────
    def _build_contact_card(self):
        card, lay = _section_card("COORDONNÉES", "◉")

        row = QHBoxLayout(); row.setSpacing(14)
        self.f_phone   = QLineEdit(); self.f_phone.setPlaceholderText("Ex : +237 6XX XXX XXX")
        self.f_phone.setFixedHeight(38)
        self.f_email   = QLineEdit(); self.f_email.setPlaceholderText("Ex : contact@socogen.cm")
        self.f_email.setFixedHeight(38)
        self.f_website = QLineEdit(); self.f_website.setPlaceholderText("Ex : www.socogen.cm")
        self.f_website.setFixedHeight(38)
        row.addWidget(_field_widget("Téléphone", self.f_phone), 2)
        row.addWidget(_field_widget("Email", self.f_email), 2)
        row.addWidget(_field_widget("Site web", self.f_website), 2)
        lay.addLayout(row)

        return card

    # ── Carte Logo ─────────────────────────────────────────────────────────
    def _build_logo_card(self):
        card, lay = _section_card("LOGO DE LA SOCIÉTÉ", "⬡")

        logo_row = QHBoxLayout(); logo_row.setSpacing(20)
        logo_row.setAlignment(Qt.AlignLeft)

        # Zone de prévisualisation
        self.logo_preview = QLabel()
        self.logo_preview.setObjectName("logo_drop_zone")
        self.logo_preview.setFixedSize(140, 88)
        self.logo_preview.setAlignment(Qt.AlignCenter)
        self.logo_preview.setStyleSheet(
            f"background: {PALETTE['bg_base']}; border: 1px dashed {PALETTE['border']};"
            f"border-radius: 8px; color: {PALETTE['text_muted']}; font-size: 11px;"
        )
        self.logo_preview.setText("Aucun logo")

        # Boutons logo
        btn_col = QVBoxLayout(); btn_col.setSpacing(8); btn_col.setAlignment(Qt.AlignTop)

        btn_choose = QPushButton("  Choisir un fichier")
        btn_choose.setFixedHeight(34)
        btn_choose.setFixedWidth(180)
        btn_choose.clicked.connect(self._choose_logo)

        btn_clear = QPushButton("  Supprimer")
        btn_clear.setObjectName("btn_danger")
        btn_clear.setFixedHeight(34)
        btn_clear.setFixedWidth(180)
        btn_clear.clicked.connect(self._clear_logo)

        btn_col.addWidget(btn_choose)
        btn_col.addWidget(btn_clear)

        # Indications
        hint_col = QVBoxLayout(); hint_col.setSpacing(4); hint_col.setAlignment(Qt.AlignTop)
        for txt in [
            "Formats acceptés : PNG, JPG, BMP",
            "Taille recommandée : 200 × 80 px",
            "Fond transparent recommandé",
        ]:
            h = QLabel(f"· {txt}")
            h.setObjectName("hint_label")
            hint_col.addWidget(h)

        logo_row.addWidget(self.logo_preview)
        logo_row.addLayout(btn_col)
        logo_row.addLayout(hint_col)
        logo_row.addStretch()
        lay.addLayout(logo_row)

        return card

    # ── Barre d'actions ────────────────────────────────────────────────────
    def _build_action_bar(self):
        bar = QWidget()
        bar.setStyleSheet(
            f"background: {PALETTE['bg_elevated']}; border: 1px solid {PALETTE['border']};"
            f"border-radius: 10px;"
        )
        bar_lay = QHBoxLayout(bar)
        bar_lay.setContentsMargins(20, 14, 20, 14)
        bar_lay.setSpacing(12)

        self.status_lbl = QLabel("")
        self.status_lbl.setObjectName("status_ok")
        self.status_lbl.setStyleSheet("background: transparent; font-size: 12px;")
        bar_lay.addWidget(self.status_lbl)
        bar_lay.addStretch()

        btn_reset = QPushButton("Réinitialiser")
        btn_reset.setFixedHeight(38)
        btn_reset.setFixedWidth(120)
        btn_reset.clicked.connect(self.refresh)
        bar_lay.addWidget(btn_reset)

        self.btn_save = QPushButton("  Enregistrer les paramètres")
        self.btn_save.setObjectName("btn_primary")
        self.btn_save.setFixedHeight(38)
        self.btn_save.setMinimumWidth(220)
        self.btn_save.clicked.connect(self._save)
        bar_lay.addWidget(self.btn_save)

        return bar

    # ── Logo handlers ──────────────────────────────────────────────────────
    def _choose_logo(self):
        path, _ = QFileDialog.getOpenFileName(
            self, "Choisir un logo", "",
            "Images (*.png *.jpg *.jpeg *.bmp *.svg)"
        )
        if path:
            self._logo_path = path
            px = QPixmap(path).scaled(
                140, 88, Qt.KeepAspectRatio, Qt.SmoothTransformation
            )
            if not px.isNull():
                self.logo_preview.setPixmap(px)
                self.logo_preview.setText("")
            self.logo_preview.setStyleSheet(
                f"background: {PALETTE['bg_base']}; border: 1px solid {PALETTE['accent_blue']}44;"
                f"border-radius: 8px;"
            )

    def _clear_logo(self):
        self._logo_path = ""
        self.logo_preview.clear()
        self.logo_preview.setText("Aucun logo")
        self.logo_preview.setStyleSheet(
            f"background: {PALETTE['bg_base']}; border: 1px dashed {PALETTE['border']};"
            f"border-radius: 8px; color: {PALETTE['text_muted']}; font-size: 11px;"
        )

    # ── Sauvegarde ─────────────────────────────────────────────────────────
    def _save(self):
        try:
            cs = self.session.get(CompanySettings, 1)
            if not cs:
                cs = CompanySettings(id=1)
                self.session.add(cs)

            cs.name      = self.f_name.text().strip()    or "SOCOGEN"
            cs.address   = self.f_address.text().strip()
            cs.city      = self.f_city.text().strip()
            cs.phone     = self.f_phone.text().strip()
            cs.email     = self.f_email.text().strip()
            cs.website   = self.f_website.text().strip()
            cs.tax_id    = self.f_tax_id.text().strip()
            cs.rccm      = self.f_rccm.text().strip()
            cs.logo_path = getattr(self, "_logo_path", cs.logo_path or "")
            self.session.commit()

            self._set_status("✓  Paramètres enregistrés avec succès.", ok=True)
        except Exception as e:
            self.session.rollback()
            self._set_status(f"⚠  Erreur : {e}", ok=False)

    def _set_status(self, msg, ok=True):
        color = PALETTE["accent_green"] if ok else PALETTE["accent_red"]
        self.status_lbl.setStyleSheet(f"background: transparent; font-size: 12px; color: {color};")
        self.status_lbl.setText(msg)
        # Effacer le message après 4 secondes si succès
        if ok:
            QTimer.singleShot(4000, lambda: self.status_lbl.setText(""))

    # ── Chargement ─────────────────────────────────────────────────────────
    def refresh(self):
        try:
            self.session.expire_all()
            cs = self.session.get(CompanySettings, 1)
            if cs:
                self.f_name.setText(cs.name or "")
                self.f_address.setText(cs.address or "")
                self.f_city.setText(cs.city or "")
                self.f_phone.setText(cs.phone or "")
                self.f_email.setText(cs.email or "")
                self.f_website.setText(cs.website or "")
                self.f_tax_id.setText(cs.tax_id or "")
                self.f_rccm.setText(cs.rccm or "")
                self._logo_path = cs.logo_path or ""
                if cs.logo_path:
                    px = QPixmap(cs.logo_path).scaled(
                        140, 88, Qt.KeepAspectRatio, Qt.SmoothTransformation
                    )
                    if not px.isNull():
                        self.logo_preview.setPixmap(px)
                        self.logo_preview.setText("")
                        self.logo_preview.setStyleSheet(
                            f"background: {PALETTE['bg_base']}; border: 1px solid {PALETTE['accent_blue']}44;"
                            f"border-radius: 8px;"
                        )
        except Exception as e:
            print(f"[Settings] refresh: {e}")
