"""
Page Transactions — journal complet par produit.
Nouveautés :
  - Sidebar supprimée : tableau prioritaire, filtre Produit intégré dans la barre de filtres
  - Recherche dans le tableau (ref, désignation, fournisseur, destination)
  - Export PDF professionnel avec en-tête société complète (logo, infos, n° contribuable, RCCM)
  - UI modernisée : design premium finance dashboard
"""
import csv
import hashlib
import logging
import os
import traceback
from datetime import date, datetime
from typing import Optional

# Patch hashlib.md5 to ignore 'usedforsecurity' parameter for ReportLab compatibility
original_md5 = hashlib.md5
def patched_md5(*args, **kwargs):
    kwargs.pop('usedforsecurity', None)
    return original_md5(*args, **kwargs)
hashlib.md5 = patched_md5

from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QLabel, QLineEdit,
    QComboBox, QTableWidget, QTableWidgetItem,
    QHeaderView, QFileDialog, QDateEdit, QDialog,
    QPushButton, QListWidget, QListWidgetItem, QAbstractItemView, QMessageBox,
    QFrame, QGraphicsDropShadowEffect, QSizePolicy
)
from PySide6.QtCore import Qt, QDate, QSize, QRect
from PySide6.QtGui import QColor, QFont, QPalette, QPainter, QFontMetrics
from PySide6.QtWidgets import QStyledItemDelegate, QStyle
from sqlalchemy import func

from database import SessionLocal
from models import Product, ProductStock, StockEntry, StockOutput, Store, CompanySettings
from ui.utils import hline, make_btn, page_header, configure_table


# ═══════════════════════════════════════════════════════════════════════════
#  Palette & style constants
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
    "accent_purple":  "#BC8CFF",

    "entry_bg":       "#0D1F14",
    "exit_bg":        "#1F0D0D",

    "sidebar_bg":     "#080C10",
    "sidebar_width":  "340",
}

# ── Stylesheet global ──────────────────────────────────────────────────────
APP_STYLE = f"""
/* ── Base ── */
QWidget {{
    background-color: {PALETTE['bg_surface']};
    color: {PALETTE['text_primary']};
    font-family: "Segoe UI", "SF Pro Text", system-ui, sans-serif;
    font-size: 13px;
}}

/* ── Search inputs ── */
#search_box {{
    background-color: {PALETTE['bg_elevated']};
    border: 1px solid {PALETTE['border']};
    border-radius: 6px;
    padding: 0 10px;
}}
#search_box:focus-within {{
    border-color: {PALETTE['border_focus']};
    background-color: {PALETTE['bg_highlight']};
}}
QLineEdit {{
    background: transparent;
    border: none;
    color: {PALETTE['text_primary']};
    font-size: 13px;
    padding: 8px 0;
    selection-background-color: {PALETTE['accent_blue']};
}}
QLineEdit::placeholder {{
    color: {PALETTE['text_muted']};
}}

/* ── Buttons ── */
QPushButton {{
    background-color: {PALETTE['bg_elevated']};
    color: {PALETTE['text_primary']};
    border: 1px solid {PALETTE['border']};
    border-radius: 6px;
    padding: 7px 16px;
    font-size: 12px;
    font-weight: 500;
    min-width: 80px;
}}
QPushButton:hover {{
    background-color: {PALETTE['bg_hover']};
    border-color: {PALETTE['text_muted']};
    color: {PALETTE['text_primary']};
}}
QPushButton:pressed {{
    background-color: {PALETTE['bg_base']};
}}
QPushButton:disabled {{
    color: {PALETTE['text_disabled']};
    border-color: {PALETTE['border_subtle']};
    background-color: {PALETTE['bg_elevated']};
}}

#btn_primary {{
    background-color: {PALETTE['accent_blue']};
    color: white;
    border: 1px solid {PALETTE['accent_blue']};
    font-weight: 600;
}}
#btn_primary:hover {{
    background-color: {PALETTE['accent_blue_lt']};
    border-color: {PALETTE['accent_blue_lt']};
}}
#btn_primary:disabled {{
    background-color: {PALETTE['bg_highlight']};
    color: {PALETTE['text_muted']};
    border-color: {PALETTE['border']};
}}

#btn_danger {{
    color: {PALETTE['accent_red']};
    border-color: {PALETTE['border']};
}}
#btn_danger:hover {{
    background-color: #2D1117;
    border-color: {PALETTE['accent_red']};
    color: {PALETTE['accent_red']};
}}
#btn_danger:disabled {{
    color: {PALETTE['text_disabled']};
    border-color: {PALETTE['border_subtle']};
    background-color: {PALETTE['bg_elevated']};
}}

#btn_secondary {{
    color: {PALETTE['text_secondary']};
}}
#btn_secondary:hover {{
    color: {PALETTE['text_primary']};
}}
#btn_secondary:disabled {{
    color: {PALETTE['text_disabled']};
}}

/* ── ComboBox ── */
QComboBox {{
    background-color: {PALETTE['bg_elevated']};
    border: 1px solid {PALETTE['border']};
    border-radius: 6px;
    padding: 7px 10px;
    color: {PALETTE['text_primary']};
    font-size: 12px;
    min-width: 100px;
    selection-background-color: {PALETTE['accent_blue']};
}}
QComboBox:hover {{
    border-color: {PALETTE['text_muted']};
}}
QComboBox:focus {{
    border-color: {PALETTE['border_focus']};
}}
QComboBox::drop-down {{
    border: none;
    width: 24px;
}}
QComboBox::down-arrow {{
    image: none;
    border-left: 4px solid transparent;
    border-right: 4px solid transparent;
    border-top: 5px solid {PALETTE['text_secondary']};
    width: 0; height: 0;
    margin-right: 6px;
}}
QComboBox QAbstractItemView {{
    background-color: {PALETTE['bg_elevated']};
    border: 1px solid {PALETTE['border']};
    selection-background-color: {PALETTE['bg_hover']};
    color: {PALETTE['text_primary']};
    padding: 4px;
    outline: none;
}}

/* ── DateEdit ── */
QDateEdit {{
    background-color: {PALETTE['bg_elevated']};
    border: 1px solid {PALETTE['border']};
    border-radius: 6px;
    padding: 7px 10px;
    color: {PALETTE['text_primary']};
    font-size: 12px;
    min-width: 110px;
}}
QDateEdit:hover {{
    border-color: {PALETTE['text_muted']};
}}
QDateEdit:focus {{
    border-color: {PALETTE['border_focus']};
}}
QDateEdit::drop-down {{
    border: none;
    width: 24px;
}}
QDateEdit::down-arrow {{
    image: none;
    border-left: 4px solid transparent;
    border-right: 4px solid transparent;
    border-top: 5px solid {PALETTE['text_secondary']};
    width: 0; height: 0;
    margin-right: 6px;
}}

/* ── Table ── */
QTableWidget {{
    background-color: {PALETTE['bg_surface']};
    alternate-background-color: {PALETTE['bg_elevated']};
    gridline-color: {PALETTE['border_subtle']};
    border: 1px solid {PALETTE['border']};
    border-radius: 8px;
    selection-background-color: {PALETTE['bg_hover']};
    outline: none;
}}
QTableWidget::item {{
    padding: 0px 10px;
    border-bottom: 1px solid {PALETTE['border_subtle']};
    min-height: 36px;
}}
QTableWidget::item:selected {{
    background-color: {PALETTE['bg_hover']};
    color: {PALETTE['text_primary']};
}}
QHeaderView::section {{
    background-color: {PALETTE['bg_elevated']};
    color: {PALETTE['text_secondary']};
    border: none;
    border-bottom: 1px solid {PALETTE['border']};
    border-right: 1px solid {PALETTE['border_subtle']};
    padding: 8px 10px;
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.5px;
    text-transform: uppercase;
}}
QHeaderView::section:first {{
    border-top-left-radius: 8px;
}}
QHeaderView::section:last {{
    border-top-right-radius: 8px;
    border-right: none;
}}
QScrollBar:vertical {{
    background: {PALETTE['bg_base']};
    width: 8px;
    border-radius: 4px;
    margin: 0;
}}
QScrollBar::handle:vertical {{
    background: {PALETTE['border']};
    border-radius: 4px;
    min-height: 30px;
}}
QScrollBar::handle:vertical:hover {{
    background: {PALETTE['text_muted']};
}}
QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {{
    height: 0;
}}
QScrollBar:horizontal {{
    background: {PALETTE['bg_base']};
    height: 8px;
    border-radius: 4px;
    margin: 0;
}}
QScrollBar::handle:horizontal {{
    background: {PALETTE['border']};
    border-radius: 4px;
    min-width: 30px;
}}
QScrollBar::handle:horizontal:hover {{
    background: {PALETTE['text_muted']};
}}
QScrollBar::add-line:horizontal, QScrollBar::sub-line:horizontal {{
    width: 0;
}}

/* ── Labels ── */
#field_label {{
    color: {PALETTE['text_muted']};
    font-size: 10px;
    font-weight: 700;
    letter-spacing: 0.8px;
    text-transform: uppercase;
    background: transparent;
}}
#section_title {{
    color: {PALETTE['text_secondary']};
    font-size: 10px;
    font-weight: 700;
    letter-spacing: 1.2px;
    text-transform: uppercase;
    background: transparent;
}}

/* ── Cards ── */
#info_card {{
    background-color: {PALETTE['bg_elevated']};
    border: 1px solid {PALETTE['border']};
    border-radius: 10px;
}}
#metric_card {{
    background-color: {PALETTE['bg_elevated']};
    border: 1px solid {PALETTE['border']};
    border-radius: 8px;
}}
#filter_panel {{
    background-color: {PALETTE['bg_elevated']};
    border: 1px solid {PALETTE['border']};
    border-radius: 8px;
}}
#stat_chip {{
    background-color: {PALETTE['bg_elevated']};
    border: 1px solid {PALETTE['border']};
    border-radius: 20px;
}}

/* ── Dialog ── */
QDialog {{
    background-color: {PALETTE['bg_surface']};
    border: 1px solid {PALETTE['border']};
    border-radius: 12px;
}}

/* ── Separators ── */
QFrame[frameShape="4"], QFrame[frameShape="5"] {{
    color: {PALETTE['border']};
    background-color: {PALETTE['border']};
    border: none;
    max-height: 1px;
}}
"""


# ═══════════════════════════════════════════════════════════════════════════
#  Helper : normalise une valeur date/datetime/str en "YYYY-MM-DD"
# ═══════════════════════════════════════════════════════════════════════════
def _date_to_str(d) -> str:
    """Convertit un objet date, datetime ou une chaîne en 'YYYY-MM-DD'."""
    if isinstance(d, datetime):
        return d.strftime("%Y-%m-%d")
    if isinstance(d, date):
        return d.strftime("%Y-%m-%d")
    return str(d)[:10]


def _date_to_display(d) -> str:
    """Convertit un objet date, datetime ou une chaîne en 'DD/MM/YYYY'."""
    try:
        if isinstance(d, (date, datetime)):
            return d.strftime("%d/%m/%Y")
        return datetime.strptime(str(d)[:10], "%Y-%m-%d").strftime("%d/%m/%Y")
    except Exception:
        return str(d)


# ═══════════════════════════════════════════════════════════════════════════
#  PDF generation
# ═══════════════════════════════════════════════════════════════════════════
def _build_pdf(path: str, product_ref: Optional[str], transactions: list, session):
    from reportlab.lib.pagesizes import A4, landscape
    from reportlab.lib import colors
    from reportlab.lib.units import mm
    from reportlab.lib.enums import TA_LEFT, TA_CENTER, TA_RIGHT
    from reportlab.lib.styles import ParagraphStyle
    from reportlab.platypus import (
        SimpleDocTemplate, Paragraph, Spacer, Table,
        TableStyle, HRFlowable, Image, KeepTogether, PageBreak
    )

    cs = session.get(CompanySettings, 1)
    company_name    = (cs.name        if cs else None) or "SOCOGEN"
    company_address = (cs.address     if cs else None) or ""
    company_city    = (cs.city        if cs else None) or ""
    company_phone   = (cs.phone       if cs else None) or ""
    company_email   = (cs.email       if cs else None) or ""
    company_website = (cs.website     if cs else None) or ""
    company_tax_id  = (cs.tax_id      if cs else None) or ""
    company_rccm    = (cs.rccm        if cs else None) or ""
    logo_path       = (cs.logo_path   if cs else None) or ""

    PAGE_W, PAGE_H = landscape(A4)
    MARGIN = 15 * mm
    doc = SimpleDocTemplate(
        path,
        pagesize=landscape(A4),
        leftMargin=MARGIN, rightMargin=MARGIN,
        topMargin=MARGIN,  bottomMargin=MARGIN,
        title=f"Transactions – {product_ref or 'Tous'}",
    )

    C_WHITE      = colors.white
    C_BLACK      = colors.HexColor("#0D1117")
    C_PRIMARY    = colors.HexColor("#1A5276")
    C_PRIMARY_LT = colors.HexColor("#2E86C1")
    C_ACCENT     = colors.HexColor("#2874A6")
    C_HDR_BG     = colors.HexColor("#1A5276")
    C_HDR_TXT    = colors.white
    C_ROW_ODD    = colors.HexColor("#EBF5FB")
    C_ROW_EVEN   = colors.white
    C_ROW_IN     = colors.HexColor("#D5F5E3")
    C_ROW_OUT    = colors.HexColor("#FADBD8")
    C_GREEN      = colors.HexColor("#1E8449")
    C_RED        = colors.HexColor("#C0392B")
    C_ORANGE     = colors.HexColor("#D68910")
    C_GREY_TXT   = colors.HexColor("#555555")
    C_LIGHT_GREY = colors.HexColor("#F2F3F4")
    C_BORDER     = colors.HexColor("#AEB6BF")
    C_BORDER_LT  = colors.HexColor("#D5D8DC")
    C_BAND_BG    = colors.HexColor("#EAF2F8")

    def ps(name, **kw):
        return ParagraphStyle(name, **kw)

    s_co_name   = ps("co_name",   fontSize=20, fontName="Helvetica-Bold",
                     textColor=C_PRIMARY,    leading=24, spaceAfter=2)
    s_co_info   = ps("co_info",   fontSize=8,  fontName="Helvetica",
                     textColor=C_GREY_TXT,   leading=12)
    s_co_legal  = ps("co_legal",  fontSize=7.5,fontName="Helvetica-Bold",
                     textColor=C_PRIMARY,    leading=11, spaceBefore=4)
    s_doc_title = ps("doc_ttl",   fontSize=22, fontName="Helvetica-Bold",
                     textColor=C_PRIMARY,    alignment=TA_RIGHT, leading=26)
    s_doc_sub   = ps("doc_sub",   fontSize=9,  fontName="Helvetica",
                     textColor=C_GREY_TXT,   alignment=TA_RIGHT, leading=13)
    s_doc_date  = ps("doc_date",  fontSize=8,  fontName="Helvetica",
                     textColor=C_GREY_TXT,   alignment=TA_RIGHT, leading=11)
    s_section   = ps("section",   fontSize=11, fontName="Helvetica-Bold",
                     textColor=C_PRIMARY,    spaceBefore=8, spaceAfter=5)
    s_kpi_lbl   = ps("kpi_lbl",   fontSize=7.5,fontName="Helvetica",
                     textColor=C_GREY_TXT,   leading=10, spaceAfter=2)
    s_kpi_val   = ps("kpi_val",   fontSize=14, fontName="Helvetica-Bold",
                     textColor=C_BLACK,      leading=16)
    s_kpi_grn   = ps("kpi_grn",   fontSize=14, fontName="Helvetica-Bold",
                     textColor=C_GREEN,      leading=16)
    s_kpi_red   = ps("kpi_red",   fontSize=14, fontName="Helvetica-Bold",
                     textColor=C_RED,        leading=16)
    s_th        = ps("th",  fontSize=8.5, fontName="Helvetica-Bold",
                     textColor=C_WHITE,      alignment=TA_CENTER, leading=11)
    s_th_l      = ps("thl", fontSize=8.5, fontName="Helvetica-Bold",
                     textColor=C_WHITE,      alignment=TA_LEFT,   leading=11)
    s_td        = ps("td",  fontSize=8,   fontName="Helvetica",
                     textColor=C_BLACK,      alignment=TA_LEFT,   leading=11)
    s_td_c      = ps("tdc", fontSize=8,   fontName="Helvetica",
                     textColor=C_BLACK,      alignment=TA_CENTER, leading=11)
    s_td_r      = ps("tdr", fontSize=8,   fontName="Helvetica",
                     textColor=C_BLACK,      alignment=TA_RIGHT,  leading=11)
    s_td_in     = ps("tdi", fontSize=8,   fontName="Helvetica-Bold",
                     textColor=C_GREEN,      alignment=TA_RIGHT,  leading=11)
    s_td_out    = ps("tdo", fontSize=8,   fontName="Helvetica-Bold",
                     textColor=C_RED,        alignment=TA_RIGHT,  leading=11)
    s_td_e_typ  = ps("tte", fontSize=8,   fontName="Helvetica-Bold",
                     textColor=C_GREEN,      alignment=TA_CENTER, leading=11)
    s_td_o_typ  = ps("tto", fontSize=8,   fontName="Helvetica-Bold",
                     textColor=C_RED,        alignment=TA_CENTER, leading=11)
    s_footer    = ps("ft",  fontSize=7.5, fontName="Helvetica",
                     textColor=C_GREY_TXT,   alignment=TA_CENTER, leading=10)
    s_footer_b  = ps("ftb", fontSize=7.5, fontName="Helvetica-Bold",
                     textColor=C_PRIMARY,    alignment=TA_CENTER, leading=10)

    def bal_style(val):
        try:
            v = int(val)
            c = C_GREEN if v > 10 else (C_ORANGE if v > 0 else C_RED)
        except Exception:
            c = C_GREY_TXT
        return ps("bs", fontSize=8, fontName="Helvetica-Bold",
                  textColor=c, alignment=TA_RIGHT, leading=11)

    story = []

    left_col = []
    if logo_path and os.path.exists(logo_path):
        try:
            left_col.append(Image(logo_path, width=45*mm, height=16*mm, kind="proportional"))
            left_col.append(Spacer(1, 3*mm))
        except Exception:
            pass

    left_col.append(Paragraph(company_name, s_co_name))
    info_parts = []
    if company_address: info_parts.append(company_address)
    if company_city:    info_parts.append(company_city)
    if info_parts:
        left_col.append(Paragraph("  |  ".join(info_parts), s_co_info))
    contact_parts = []
    if company_phone:   contact_parts.append(f"Tél : {company_phone}")
    if company_email:   contact_parts.append(f"Email : {company_email}")
    if company_website: contact_parts.append(company_website)
    if contact_parts:
        left_col.append(Paragraph("  |  ".join(contact_parts), s_co_info))
    legal_parts = []
    if company_tax_id:  legal_parts.append(f"N° Contribuable : {company_tax_id}")
    if company_rccm:    legal_parts.append(f"RCCM : {company_rccm}")
    if legal_parts:
        left_col.append(Spacer(1, 1*mm))
        left_col.append(Paragraph("    ".join(legal_parts), s_co_legal))

    right_col = [
        Paragraph(
            "RAPPORT PRODUIT" if product_ref else "RAPPORT DE TRANSACTIONS",
            s_doc_title
        ),
        Spacer(1, 2*mm),
        Paragraph(f"Date d'édition : {datetime.now().strftime('%d/%m/%Y')}", s_doc_date),
        Paragraph(f"Heure : {datetime.now().strftime('%H:%M')}", s_doc_date),
    ]
    if product_ref:
        right_col.append(Spacer(1, 2*mm))
        right_col.append(Paragraph(f"Produit : <b>{product_ref}</b>", s_doc_sub))

    hdr_tbl = Table([[left_col, right_col]], colWidths=[120*mm, None])
    hdr_tbl.setStyle(TableStyle([
        ("BACKGROUND",    (0, 0), (-1, -1), C_WHITE),
        ("TOPPADDING",    (0, 0), (-1, -1), 10),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 10),
        ("LEFTPADDING",   (0, 0), (0, -1),  0),
        ("RIGHTPADDING",  (-1, 0), (-1, -1), 0),
        ("VALIGN",        (0, 0), (-1, -1), "MIDDLE"),
        ("LINEABOVE",     (0, 0), (-1, 0),  5,  C_PRIMARY),
        ("LINEBELOW",     (0, 0), (-1, -1), 1.5, C_PRIMARY),
    ]))
    story.append(hdr_tbl)
    story.append(Spacer(1, 5*mm))

    total_in  = sum(t["in_qty"]  for t in transactions)
    total_out = sum(t["out_qty"] for t in transactions)

    def kpi_cell(label, value, val_style):
        return [Paragraph(label.upper(), s_kpi_lbl), Paragraph(str(value), val_style)]

    if product_ref:
        p = session.query(Product).filter_by(reference=product_ref).first()
        # Magasins du produit via ProductStock
        store_names = []
        if p:
            ps_list = session.query(ProductStock).filter_by(product_id=p.id).all()
            for ps_item in ps_list:
                st = session.get(Store, ps_item.store_id)
                if st:
                    store_names.append(st.name)
        store_name = ", ".join(store_names) if store_names else "—"
        # Stock initial = somme sur tous les magasins
        init_stock = session.query(
            func.sum(ProductStock.initial_stock)
        ).filter(ProductStock.product_id == p.id).scalar() or 0 if p else 0
        current    = init_stock + total_in - total_out

        if current > 10:
            s_current = ps("sc", fontSize=14, fontName="Helvetica-Bold", textColor=C_GREEN, leading=16)
        elif current > 0:
            s_current = ps("sc", fontSize=14, fontName="Helvetica-Bold", textColor=C_ORANGE, leading=16)
        else:
            s_current = ps("sc", fontSize=14, fontName="Helvetica-Bold", textColor=C_RED, leading=16)

        prod_header = Table([[
            Paragraph(f"{product_ref}", ps("prh", fontSize=13, fontName="Helvetica-Bold",
                                           textColor=C_PRIMARY, leading=16)),
            Paragraph(p.designation if p else "", ps("prd", fontSize=9, fontName="Helvetica",
                                                       textColor=C_GREY_TXT, leading=12)),
        ]], colWidths=[40*mm, None])
        prod_header.setStyle(TableStyle([
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("LEFTPADDING", (0, 0), (-1, -1), 0),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ]))
        story.append(prod_header)

        kpi_data = [[
            kpi_cell("Magasin",       store_name,               ps("kpim", fontSize=14, fontName="Helvetica-Bold", textColor=C_ACCENT, leading=16)),
            kpi_cell("Unité",         p.unit if p else "—",     s_kpi_val),
            kpi_cell("Stock initial", str(init_stock),           s_kpi_val),
            kpi_cell("Entrées",       f"+ {total_in}",           s_kpi_grn),
            kpi_cell("Sorties",       f"- {total_out}",          s_kpi_red),
            kpi_cell("Stock actuel",  str(current),              s_current),
            kpi_cell("Mouvements",    str(len(transactions)),    s_kpi_val),
        ]]
        kpi_col_w = [38*mm, 22*mm, 28*mm, 26*mm, 26*mm, 28*mm, 30*mm]
    else:
        kpi_data = [[
            kpi_cell("Tous les produits", "—",                   s_kpi_val),
            kpi_cell("Entrées totales",   f"+ {total_in}",       s_kpi_grn),
            kpi_cell("Sorties totales",   f"- {total_out}",      s_kpi_red),
            kpi_cell("Mouvements",        str(len(transactions)), s_kpi_val),
        ]]
        kpi_col_w = [55*mm, 50*mm, 50*mm, 50*mm]

    kpi_tbl = Table(kpi_data, colWidths=kpi_col_w)
    kpi_tbl.setStyle(TableStyle([
        ("BACKGROUND",    (0, 0), (-1, -1), C_BAND_BG),
        ("BOX",           (0, 0), (-1, -1), 1,   C_BORDER),
        ("LINEAFTER",     (0, 0), (-2, -1), 0.5, C_BORDER_LT),
        ("TOPPADDING",    (0, 0), (-1, -1), 10),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 10),
        ("LEFTPADDING",   (0, 0), (-1, -1), 14),
        ("RIGHTPADDING",  (0, 0), (-1, -1), 14),
        ("VALIGN",        (0, 0), (-1, -1), "MIDDLE"),
        ("LINEBELOW",     (0, 0), (-1, -1), 3, C_PRIMARY_LT),
    ]))
    story.append(kpi_tbl)
    story.append(Spacer(1, 6*mm))

    story.append(Paragraph("DÉTAIL DES MOUVEMENTS", s_section))
    story.append(Spacer(1, 2*mm))

    col_labels = [
        "DATE", "TYPE", "RÉFÉRENCE", "DÉSIGNATION",
        "MAGASIN", "FOURNISSEUR / DESTINATION",
        "N° FACTURE", "ENTRÉE (+)", "SORTIE (-)", "SOLDE"
    ]
    col_widths = [22*mm, 17*mm, 26*mm, 38*mm, 26*mm, 42*mm, 24*mm, 18*mm, 18*mm, 17*mm]

    header_row = []
    for i, h in enumerate(col_labels):
        style = s_th if i not in (2, 3, 5) else s_th_l
        header_row.append(Paragraph(h, style))
    tbl_data = [header_row]

    for t in transactions:
        # ── CORRECTION : utiliser _date_to_display pour gérer date/datetime/str ──
        d = _date_to_display(t["date"])

        is_entry = t["type"] == "Entrée"
        in_txt   = f"+ {t['in_qty']}"  if t["in_qty"]  > 0 else "—"
        out_txt  = f"- {t['out_qty']}" if t["out_qty"] > 0 else "—"
        bal_val  = str(t.get("balance", "—"))

        tbl_data.append([
            Paragraph(d,                                   s_td_c),
            Paragraph(t["type"],                           s_td_e_typ if is_entry else s_td_o_typ),
            Paragraph(t["reference"],                      s_td),
            Paragraph((t["designation"] or "")[:36],       s_td),
            Paragraph(t["store"] or "—",                   s_td),
            Paragraph((t["counterpart"] or "—")[:40],      s_td),
            Paragraph(t["invoice"] or "—",                 s_td_c),
            Paragraph(in_txt,                              s_td_in),
            Paragraph(out_txt,                             s_td_out),
            Paragraph(bal_val,                             bal_style(bal_val)),
        ])

    txn_tbl = Table(tbl_data, colWidths=col_widths, repeatRows=1)
    tbl_style = [
        ("BACKGROUND",    (0, 0), (-1, 0),  C_HDR_BG),
        ("TEXTCOLOR",     (0, 0), (-1, 0),  C_WHITE),
        ("FONTNAME",      (0, 0), (-1, 0),  "Helvetica-Bold"),
        ("FONTSIZE",      (0, 0), (-1, 0),  8.5),
        ("TOPPADDING",    (0, 0), (-1, 0),  8),
        ("BOTTOMPADDING", (0, 0), (-1, 0),  8),
        ("FONTSIZE",      (0, 1), (-1, -1), 8),
        ("TOPPADDING",    (0, 1), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 1), (-1, -1), 5),
        ("LEFTPADDING",   (0, 0), (-1, -1), 5),
        ("RIGHTPADDING",  (0, 0), (-1, -1), 5),
        ("VALIGN",        (0, 0), (-1, -1), "MIDDLE"),
        ("BOX",           (0, 0), (-1, -1), 1,    C_BORDER),
        ("INNERGRID",     (0, 0), (-1, -1), 0.3,  C_BORDER_LT),
        ("LINEBELOW",     (0, 0), (-1, 0),  1.5,  C_PRIMARY_LT),
    ]
    for i, t in enumerate(transactions, start=1):
        if t["type"] == "Entrée":
            tbl_style.append(("BACKGROUND", (0, i), (-1, i), C_ROW_IN))
        else:
            tbl_style.append(("BACKGROUND", (0, i), (-1, i), C_ROW_OUT))

    txn_tbl.setStyle(TableStyle(tbl_style))
    story.append(txn_tbl)

    story.append(Spacer(1, 4*mm))
    legend_data = [[
        Paragraph("", ps("l0", fontSize=8)),
        Table([[""]], colWidths=[8*mm], rowHeights=[4*mm],
              style=[("BACKGROUND", (0,0),(-1,-1), C_ROW_IN),
                     ("BOX", (0,0),(-1,-1), 0.5, C_BORDER_LT)]),
        Paragraph(" Entrée de stock", ps("l1", fontSize=8, fontName="Helvetica",
                                          textColor=C_GREY_TXT, leading=10)),
        Spacer(4*mm, 1),
        Table([[""]], colWidths=[8*mm], rowHeights=[4*mm],
              style=[("BACKGROUND", (0,0),(-1,-1), C_ROW_OUT),
                     ("BOX", (0,0),(-1,-1), 0.5, C_BORDER_LT)]),
        Paragraph(" Sortie de stock", ps("l2", fontSize=8, fontName="Helvetica",
                                          textColor=C_GREY_TXT, leading=10)),
    ]]
    legend_tbl = Table(legend_data, colWidths=[None, 10*mm, 36*mm, 6*mm, 10*mm, 36*mm])
    legend_tbl.setStyle(TableStyle([
        ("VALIGN",      (0,0),(-1,-1), "MIDDLE"),
        ("LEFTPADDING", (0,0),(-1,-1), 0),
    ]))
    story.append(legend_tbl)

    story.append(Spacer(1, 6*mm))
    story.append(HRFlowable(width="100%", thickness=1, color=C_PRIMARY, spaceAfter=3*mm))
    footer_data = [[
        Paragraph(company_name, s_footer_b),
        Paragraph(
            f"Document généré le {datetime.now().strftime('%d/%m/%Y à %H:%M')}",
            s_footer
        ),
        Paragraph(f"{len(transactions)} transaction(s)", s_footer),
    ]]
    footer_tbl = Table(footer_data, colWidths=[None, None, 50*mm])
    footer_tbl.setStyle(TableStyle([
        ("VALIGN",        (0,0),(-1,-1), "MIDDLE"),
        ("LEFTPADDING",   (0,0),(-1,-1), 0),
        ("RIGHTPADDING",  (0,0),(-1,-1), 0),
    ]))
    story.append(footer_tbl)
    doc.build(story)


# ═══════════════════════════════════════════════════════════════════════════
#  UI helpers
# ═══════════════════════════════════════════════════════════════════════════

def _make_separator():
    line = QFrame()
    line.setFrameShape(QFrame.HLine)
    line.setFrameShadow(QFrame.Plain)
    line.setFixedHeight(1)
    line.setStyleSheet(f"background-color: {PALETTE['border']}; border: none;")
    return line


def _action_button(text, obj_name=None, tooltip=None, enabled=True):
    btn = QPushButton(text)
    if obj_name:
        btn.setObjectName(obj_name)
    if tooltip:
        btn.setToolTip(tooltip)
    btn.setEnabled(enabled)
    btn.setFixedHeight(32)
    return btn


# ═══════════════════════════════════════════════════════════════════════════
#  TransactionsPage — tableau prioritaire, sans sidebar produits
# ═══════════════════════════════════════════════════════════════════════════
class TransactionsPage(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        logging.basicConfig(filename='app_errors.log', level=logging.ERROR,
                            format='%(asctime)s - %(levelname)s - %(message)s')
        self.session       = SessionLocal()
        self._transactions = []
        self._filtered     = []
        self._selected_ref = None
        self._selected_txn = None
        self.setStyleSheet(APP_STYLE)
        self._build_ui()

    # ─────────────────────────────────────────────────────────────────────
    def _build_ui(self):
        root = QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        # ── Action buttons ─────────────────────────────────────────────
        self.btn_pdf     = _action_button("⬡  Rapport PDF",        "btn_primary",   "Exporter le rapport PDF du produit sélectionné", enabled=False)
        self.btn_pdf_all = _action_button("⬡  Rapport PDF (tout)", None,            "Exporter le rapport PDF de toutes les transactions")
        self.btn_edit    = _action_button("✎  Modifier",            "btn_secondary", "Modifier la transaction sélectionnée", enabled=False)
        self.btn_delete  = _action_button("⊘  Supprimer",           "btn_danger",    "Supprimer la transaction sélectionnée", enabled=False)

        self.btn_pdf.clicked.connect(self._export_pdf)
        self.btn_pdf_all.clicked.connect(self._export_pdf_all)
        self.btn_edit.clicked.connect(self._edit_transaction)
        self.btn_delete.clicked.connect(self._delete_transaction)

        # ── Page header ────────────────────────────────────────────────
        header = self._build_header()
        root.addWidget(header)
        root.addWidget(_make_separator())

        # ── Content (pleine largeur) ───────────────────────────────────
        root.addWidget(self._build_content(), 1)

        self._load_combos()
        self.refresh()

    # ── Header ────────────────────────────────────────────────────────────
    def _build_header(self):
        w = QWidget()
        w.setFixedHeight(56)
        w.setStyleSheet(f"background: {PALETTE['bg_surface']}; border-bottom: 1px solid {PALETTE['border']};")
        lay = QHBoxLayout(w)
        lay.setContentsMargins(24, 0, 20, 0)
        lay.setSpacing(12)

        title_grp = QWidget(); title_grp.setStyleSheet("background: transparent;")
        tgl = QVBoxLayout(title_grp); tgl.setContentsMargins(0,0,0,0); tgl.setSpacing(1)
        lbl_title = QLabel("Transactions")
        lbl_title.setStyleSheet(f"color: {PALETTE['text_primary']}; font-size: 15px; font-weight: 700; background: transparent;")
        lbl_sub = QLabel("Historique des entrées et sorties")
        lbl_sub.setStyleSheet(f"color: {PALETTE['text_muted']}; font-size: 11px; background: transparent;")
        tgl.addWidget(lbl_title)
        tgl.addWidget(lbl_sub)

        lay.addWidget(title_grp)
        lay.addStretch()

        for btn in [self.btn_pdf_all, self.btn_delete, self.btn_edit, self.btn_pdf]:
            lay.addWidget(btn)

        return w

    # ── Content area (pleine largeur) ─────────────────────────────────────
    def _build_content(self):
        right = QWidget()
        right.setStyleSheet(f"background: {PALETTE['bg_base']};")
        rl = QVBoxLayout(right)
        rl.setContentsMargins(20, 16, 20, 20)
        rl.setSpacing(12)

        # Info card
        rl.addWidget(self._build_info_card())

        # Filters (inclut désormais le filtre produit)
        rl.addWidget(self._build_filters())

        # Mini stats row
        rl.addLayout(self._build_stats_row())

        # Table
        self.table = QTableWidget()
        self.table.setColumnCount(10)
        self.table.setHorizontalHeaderLabels([
            "DATE", "TYPE", "RÉFÉRENCE", "DÉSIGNATION",
            "MAGASIN", "FOURNISSEUR / DESTINATION",
            "N° FACTURE", "ENTRÉE (+)", "SORTIE (−)", "SOLDE"
        ])
        self.table.setShowGrid(False)
        self.table.setAlternatingRowColors(True)
        self.table.setSelectionBehavior(QTableWidget.SelectRows)
        self.table.setEditTriggers(QTableWidget.NoEditTriggers)
        self.table.verticalHeader().setVisible(False)
        self.table.verticalHeader().setDefaultSectionSize(38)
        hh = self.table.horizontalHeader()
        hh.setStretchLastSection(False)
        hh.setSectionResizeMode(QHeaderView.Interactive)
        hh.setSectionResizeMode(3, QHeaderView.Stretch)
        hh.setSectionResizeMode(5, QHeaderView.Stretch)
        for col, w in {0: 100, 1: 82, 2: 110, 4: 120, 6: 110, 7: 90, 8: 90, 9: 90}.items():
            self.table.setColumnWidth(col, w)
        self.table.itemSelectionChanged.connect(self._on_table_selection_changed)
        self.table.doubleClicked.connect(self._edit_transaction)
        rl.addWidget(self.table, 1)

        return right

    def _build_info_card(self):
        card = QWidget()
        card.setObjectName("info_card")
        card.setFixedHeight(76)
        lay = QHBoxLayout(card)
        lay.setContentsMargins(20, 14, 20, 14)
        lay.setSpacing(0)

        name_col = QWidget(); name_col.setStyleSheet("background: transparent;")
        ncl = QVBoxLayout(name_col); ncl.setContentsMargins(0, 0, 0, 0); ncl.setSpacing(2)
        lbl_cat = QLabel("PRODUIT SÉLECTIONNÉ"); lbl_cat.setObjectName("field_label")
        self.lbl_product_name = QLabel("Toutes les transactions")
        self.lbl_product_name.setStyleSheet(
            f"color: {PALETTE['accent_blue_lt']}; font-size: 15px; font-weight: 700; background: transparent;"
        )
        ncl.addWidget(lbl_cat)
        ncl.addWidget(self.lbl_product_name)
        lay.addWidget(name_col, 2)

        lay.addWidget(self._v_separator())

        self._ic_initial = self._info_metric("Stock Initial",   "—", PALETTE["text_secondary"])
        self._ic_entries = self._info_metric("Entrées totales", "—", PALETTE["accent_green"])
        self._ic_outputs = self._info_metric("Sorties totales", "—", PALETTE["accent_red"])
        self._ic_current = self._info_metric("Stock actuel",    "—", PALETTE["accent_blue_lt"])

        for i, (w, _) in enumerate([self._ic_initial, self._ic_entries, self._ic_outputs, self._ic_current]):
            lay.addWidget(w, 1)
            if i < 3:
                lay.addWidget(self._v_separator())

        return card

    def _build_filters(self):
        panel = QWidget()
        panel.setObjectName("filter_panel")
        fl = QHBoxLayout(panel)
        fl.setContentsMargins(14, 10, 14, 10)
        fl.setSpacing(10)

        # ── Produit ──────────────────────────────────────────────────────
        lbl_pr = QLabel("Produit"); lbl_pr.setObjectName("field_label")
        self.f_product = QComboBox()
        self.f_product.setMinimumWidth(160)
        self.f_product.setMaximumWidth(220)
        self.f_product.currentIndexChanged.connect(self._on_product_combo_changed)
        fl.addWidget(lbl_pr)
        fl.addWidget(self.f_product)

        fl.addWidget(self._v_separator_thin())

        # ── Recherche texte ───────────────────────────────────────────────
        ts_wrap = QWidget()
        ts_wrap.setObjectName("search_box")
        tsl = QHBoxLayout(ts_wrap)
        tsl.setContentsMargins(10, 0, 10, 0)
        tsl.setSpacing(6)
        lbl_ts = QLabel("⌕")
        lbl_ts.setStyleSheet(f"background:transparent; font-size: 14px; color: {PALETTE['text_muted']};")
        self.table_search = QLineEdit()
        self.table_search.setPlaceholderText("Rechercher ref, désignation, fournisseur…")
        self.table_search.setMinimumWidth(200)
        self.table_search.textChanged.connect(self._apply_filters)
        tsl.addWidget(lbl_ts)
        tsl.addWidget(self.table_search)
        fl.addWidget(ts_wrap, 3)

        fl.addWidget(self._v_separator_thin())

        # ── Magasin ───────────────────────────────────────────────────────
        lbl_st = QLabel("Magasin"); lbl_st.setObjectName("field_label")
        self.f_store = QComboBox()
        self.f_store.setMinimumWidth(130)
        self.f_store.currentIndexChanged.connect(self._apply_filters)
        fl.addWidget(lbl_st)
        fl.addWidget(self.f_store)

        # ── Type ──────────────────────────────────────────────────────────
        lbl_ty = QLabel("Type"); lbl_ty.setObjectName("field_label")
        self.f_type = QComboBox()
        self.f_type.addItems(["Tous", "Entrée", "Sortie"])
        self.f_type.setMinimumWidth(90)
        self.f_type.currentIndexChanged.connect(self._apply_filters)
        fl.addWidget(lbl_ty)
        fl.addWidget(self.f_type)

        fl.addWidget(self._v_separator_thin())

        # ── Dates ─────────────────────────────────────────────────────────
        lbl_fr = QLabel("Du"); lbl_fr.setObjectName("field_label")
        self.f_date_from = QDateEdit()
        self.f_date_from.setCalendarPopup(True)
        self.f_date_from.setDisplayFormat("dd/MM/yyyy")
        self.f_date_from.setDate(QDate(QDate.currentDate().year(), 1, 1))
        self.f_date_from.dateChanged.connect(self._apply_filters)

        lbl_to = QLabel("Au"); lbl_to.setObjectName("field_label")
        self.f_date_to = QDateEdit()
        self.f_date_to.setCalendarPopup(True)
        self.f_date_to.setDisplayFormat("dd/MM/yyyy")
        self.f_date_to.setDate(QDate.currentDate())
        self.f_date_to.dateChanged.connect(self._apply_filters)

        fl.addWidget(lbl_fr); fl.addWidget(self.f_date_from)
        fl.addWidget(lbl_to); fl.addWidget(self.f_date_to)
        fl.addStretch()

        btn_reset = QPushButton("↺  Réinit.")
        btn_reset.setFixedHeight(32)
        btn_reset.setFixedWidth(90)
        btn_reset.clicked.connect(self._reset_filters)
        fl.addWidget(btn_reset)

        return panel

    def _build_stats_row(self):
        sr = QHBoxLayout()
        sr.setSpacing(8)
        self._st_count   = self._make_mini_stat("0", "transactions",    PALETTE["text_secondary"])
        self._st_entries = self._make_mini_stat("0", "total entrées",   PALETTE["accent_green"])
        self._st_outputs = self._make_mini_stat("0", "total sorties",   PALETTE["accent_red"])
        for w, _ in [self._st_count, self._st_entries, self._st_outputs]:
            sr.addWidget(w)
        sr.addStretch()
        return sr

    # ── Widget helpers ─────────────────────────────────────────────────────
    def _v_separator(self):
        sep = QFrame()
        sep.setFrameShape(QFrame.VLine)
        sep.setFixedWidth(1)
        sep.setStyleSheet(f"background: {PALETTE['border']}; border: none;")
        sep.setContentsMargins(8, 8, 8, 8)
        w = QWidget(); w.setFixedWidth(17)
        w.setStyleSheet("background: transparent;")
        lay = QHBoxLayout(w); lay.setContentsMargins(8,0,8,0)
        lay.addWidget(sep)
        return w

    def _v_separator_thin(self):
        sep = QFrame()
        sep.setFrameShape(QFrame.VLine)
        sep.setFixedWidth(1)
        sep.setFixedHeight(20)
        sep.setStyleSheet(f"background: {PALETTE['border']}; border: none;")
        return sep

    def _info_metric(self, label, value, color):
        w = QWidget(); w.setStyleSheet("background: transparent;")
        lay = QVBoxLayout(w); lay.setContentsMargins(12, 0, 12, 0); lay.setSpacing(2)
        lbl = QLabel(label.upper()); lbl.setObjectName("field_label")
        val = QLabel(value)
        val.setStyleSheet(f"color: {color}; font-size: 17px; font-weight: 700; background: transparent;")
        lay.addWidget(lbl); lay.addWidget(val)
        return w, val

    def _make_mini_stat(self, value, label, color):
        w = QWidget(); w.setObjectName("stat_chip")
        lay = QHBoxLayout(w); lay.setContentsMargins(12, 6, 14, 6); lay.setSpacing(6)
        val = QLabel(value)
        val.setStyleSheet(f"color: {color}; font-size: 15px; font-weight: 700; background: transparent;")
        lbl = QLabel(label)
        lbl.setStyleSheet(f"color: {PALETTE['text_muted']}; font-size: 11px; background: transparent;")
        lay.addWidget(val); lay.addWidget(lbl)
        return w, val

    # ── Data loading ──────────────────────────────────────────────────────
    def _load_combos(self):
        try:
            self.session.expire_all()

            # ── Produits ──
            self.f_product.blockSignals(True)
            self.f_product.clear()
            self.f_product.addItem("Tous les produits", None)
            for p in self.session.query(Product).order_by(Product.reference).all():
                label = f"{p.reference}  –  {p.designation}" if p.designation else p.reference
                self.f_product.addItem(label, p.reference)
            self.f_product.blockSignals(False)

            # ── Magasins ──
            self.f_store.blockSignals(True)
            self.f_store.clear()
            self.f_store.addItem("Tous les magasins", None)
            for s in self.session.query(Store).order_by(Store.name).all():
                self.f_store.addItem(s.name, s.id)
            self.f_store.blockSignals(False)
        except Exception as e:
            print(f"[Transactions] _load_combos: {e}")

    def _on_product_combo_changed(self):
        """Appelé quand l'utilisateur change le combo Produit."""
        ref = self.f_product.currentData()
        self._select_product(ref)

    def _select_product(self, ref):
        self._selected_ref = ref
        if ref is None:
            self.lbl_product_name.setText("Toutes les transactions")
            self.btn_pdf.setEnabled(False)
        else:
            self.lbl_product_name.setText(ref)
            self.btn_pdf.setEnabled(True)
        self._load_transactions()
        self._apply_filters()

    def _load_transactions(self):
        try:
            self.session.expire_all()
            ref  = self._selected_ref
            txns = []

            q_e = self.session.query(StockEntry, Store.name).outerjoin(Store, StockEntry.store_id == Store.id)
            if ref:
                q_e = q_e.filter(StockEntry.reference == ref)
            for e, sn in q_e.all():
                txns.append({
                    "id": e.id, "record_type": "entry",
                    "date": e.date, "type": "Entrée",
                    "reference": e.reference, "designation": e.designation,
                    "store": sn or "—", "store_id": e.store_id,
                    "counterpart": e.supplier or "—", "invoice": "",
                    "in_qty": e.quantity, "out_qty": 0,
                })

            q_o = self.session.query(StockOutput, Store.name).outerjoin(Store, StockOutput.store_id == Store.id)
            if ref:
                q_o = q_o.filter(StockOutput.reference == ref)
            for o, sn in q_o.all():
                txns.append({
                    "id": o.id, "record_type": "output",
                    "date": o.date, "type": "Sortie",
                    "reference": o.reference, "designation": o.designation,
                    "store": sn or "—", "store_id": o.store_id,
                    "counterpart": o.destination or "—", "invoice": o.invoice_number or "",
                    "in_qty": 0, "out_qty": o.quantity,
                })

            txns.sort(key=lambda r: (r["date"], r["type"]))

            if ref:
                p       = self.session.query(Product).filter_by(reference=ref).first()
                balance = self.session.query(
                    func.sum(ProductStock.initial_stock)
                ).filter(ProductStock.product_id == p.id).scalar() or 0 if p else 0
            else:
                balance = 0
            for t in txns:
                balance += t["in_qty"] - t["out_qty"]
                t["balance"] = balance

            self._transactions = txns

            total_in  = sum(t["in_qty"]  for t in txns)
            total_out = sum(t["out_qty"] for t in txns)
            if ref:
                p       = self.session.query(Product).filter_by(reference=ref).first()
                _init = self.session.query(
                    func.sum(ProductStock.initial_stock)
                ).filter(ProductStock.product_id == p.id).scalar() or 0 if p else 0
                current = _init + total_in - total_out
                self._ic_initial[1].setText(str(_init))
                c = PALETTE["accent_green"] if current > 10 else (PALETTE["accent_orange"] if current > 0 else PALETTE["accent_red"])
                self._ic_current[1].setText(str(current))
                self._ic_current[1].setStyleSheet(
                    f"color: {c}; font-size: 17px; font-weight: 700; background: transparent;"
                )
            else:
                self._ic_initial[1].setText("—")
                self._ic_current[1].setText("—")
            self._ic_entries[1].setText(f"+{total_in}")
            self._ic_outputs[1].setText(f"-{total_out}")

        except Exception as e:
            error_msg = f"Erreur chargement transactions: {str(e)}\n\nTraceback:\n{traceback.format_exc()}"
            logging.error(error_msg)
            print(error_msg)

    # ── Filtres ───────────────────────────────────────────────────────────
    def _apply_filters(self):
        store_id  = self.f_store.currentData()
        type_txt  = self.f_type.currentText()
        date_from = self.f_date_from.date().toString("yyyy-MM-dd")
        date_to   = self.f_date_to.date().toString("yyyy-MM-dd")
        search_q  = self.table_search.text().strip().lower()

        filtered = self._transactions
        if store_id:
            filtered = [t for t in filtered if t["store_id"] == store_id]
        if type_txt != "Tous":
            filtered = [t for t in filtered if t["type"] == type_txt]

        # ── CORRECTION : normaliser t["date"] en string avant de comparer ──
        filtered = [t for t in filtered if date_from <= _date_to_str(t["date"]) <= date_to]

        if search_q:
            filtered = [
                t for t in filtered
                if search_q in t["reference"].lower()
                or search_q in t["designation"].lower()
                or search_q in t["counterpart"].lower()
                or search_q in (t["invoice"] or "").lower()
                or search_q in t["store"].lower()
            ]

        self._filtered = filtered
        total_in  = sum(t["in_qty"]  for t in filtered)
        total_out = sum(t["out_qty"] for t in filtered)
        self._st_count[1].setText(str(len(filtered)))
        self._st_entries[1].setText(f"+{total_in}")
        self._st_outputs[1].setText(f"-{total_out}")
        self._render_table(filtered)

    def _render_table(self, rows):
        self._selected_txn = None
        self.btn_edit.setEnabled(False)
        self.btn_delete.setEnabled(False)
        self.table.setRowCount(len(rows))

        for ri, t in enumerate(rows):
            is_e   = t["type"] == "Entrée"
            row_bg = QColor(PALETTE["entry_bg"]) if is_e else QColor(PALETTE["exit_bg"])

            # ── CORRECTION : utiliser _date_to_display pour gérer date/datetime/str ──
            d = _date_to_display(t["date"])

            cells = [
                d, t["type"], t["reference"], t["designation"],
                t["store"], t["counterpart"], t["invoice"],
                f"+{t['in_qty']}"  if t["in_qty"]  > 0 else "—",
                f"−{t['out_qty']}" if t["out_qty"] > 0 else "—",
                str(t.get("balance", "—")),
            ]
            for col, text in enumerate(cells):
                item = QTableWidgetItem(text)
                item.setBackground(row_bg)

                if col == 1:
                    c = PALETTE["accent_green"] if is_e else PALETTE["accent_red"]
                    item.setForeground(QColor(c))
                    item.setFont(QFont("Segoe UI", 9, QFont.Bold))
                    item.setTextAlignment(Qt.AlignVCenter | Qt.AlignHCenter)
                elif col == 7:
                    item.setForeground(QColor(PALETTE["accent_green"]))
                    item.setFont(QFont("Segoe UI", 10, QFont.Bold))
                    item.setTextAlignment(Qt.AlignVCenter | Qt.AlignRight)
                elif col == 8:
                    item.setForeground(QColor(PALETTE["accent_red"]))
                    item.setFont(QFont("Segoe UI", 10, QFont.Bold))
                    item.setTextAlignment(Qt.AlignVCenter | Qt.AlignRight)
                elif col == 9:
                    try:
                        b = int(text)
                        bc = PALETTE["accent_green"] if b > 10 else (PALETTE["accent_orange"] if b > 0 else PALETTE["accent_red"])
                    except Exception:
                        bc = PALETTE["text_muted"]
                    item.setForeground(QColor(bc))
                    item.setFont(QFont("Segoe UI", 10, QFont.Bold))
                    item.setTextAlignment(Qt.AlignVCenter | Qt.AlignRight)
                elif col == 0:
                    item.setForeground(QColor(PALETTE["text_secondary"]))
                    item.setTextAlignment(Qt.AlignVCenter | Qt.AlignHCenter)
                else:
                    item.setForeground(QColor(PALETTE["text_primary"]))
                    item.setTextAlignment(Qt.AlignVCenter | Qt.AlignLeft)

                self.table.setItem(ri, col, item)

    # ── Sélection / actions ───────────────────────────────────────────────
    def _on_table_selection_changed(self):
        items = self.table.selectedItems()
        if not items:
            self._selected_txn = None
            self.btn_edit.setEnabled(False)
            self.btn_delete.setEnabled(False)
            return

        row = self.table.currentRow()
        if row < 0 or row >= len(self._filtered):
            self._selected_txn = None
            self.btn_edit.setEnabled(False)
            self.btn_delete.setEnabled(False)
            return

        self._selected_txn = self._filtered[row]
        self.btn_edit.setEnabled(True)
        self.btn_delete.setEnabled(True)

    def _delete_transaction(self):
        if not self._selected_txn:
            return
        reply = QMessageBox.question(
            self, "Confirmer la suppression",
            "Voulez-vous supprimer cette transaction ?",
            QMessageBox.Yes | QMessageBox.No
        )
        if reply != QMessageBox.Yes:
            return
        try:
            txn = self._selected_txn
            if txn["record_type"] == "entry":
                record = self.session.get(StockEntry, txn["id"])
            else:
                record = self.session.get(StockOutput, txn["id"])
            if record:
                self.session.delete(record)
                self.session.commit()
            self._load_transactions()
            self._apply_filters()
            QMessageBox.information(self, "Suppression réussie",
                "La transaction a été supprimée.")
        except Exception as e:
            QMessageBox.critical(self, "Erreur suppression", str(e))

    def _edit_transaction(self):
        if not self._selected_txn:
            return

        txn = self._selected_txn
        is_entry = txn["type"] == "Entrée"

        dlg = QDialog(self)
        dlg.setWindowTitle("Modifier la transaction")
        dlg.setMinimumWidth(860)
        dlg.setMinimumHeight(300)
        dlg.setStyleSheet(APP_STYLE + f"""
            QDialog {{
                background: {PALETTE['bg_surface']};
            }}
            #dlg_card {{
                background: {PALETTE['bg_elevated']};
                border: 1px solid {PALETTE['border']};
                border-radius: 10px;
            }}
            #type_badge_entry {{
                background: {PALETTE['entry_bg']};
                color: {PALETTE['accent_green']};
                border: 1px solid {PALETTE['accent_green']}44;
                border-radius: 5px;
                padding: 3px 10px;
                font-size: 11px;
                font-weight: 700;
            }}
            #type_badge_exit {{
                background: {PALETTE['exit_bg']};
                color: {PALETTE['accent_red']};
                border: 1px solid {PALETTE['accent_red']}44;
                border-radius: 5px;
                padding: 3px 10px;
                font-size: 11px;
                font-weight: 700;
            }}
        """)

        # ── Racine du dialog ────────────────────────────────────────────
        root_layout = QVBoxLayout(dlg)
        root_layout.setContentsMargins(20, 20, 20, 20)
        root_layout.setSpacing(14)

        # ── En-tête ─────────────────────────────────────────────────────
        hdr_w = QWidget(); hdr_w.setStyleSheet("background: transparent;")
        hdr_lay = QHBoxLayout(hdr_w)
        hdr_lay.setContentsMargins(0, 0, 0, 0)
        hdr_lay.setSpacing(10)

        lbl_title = QLabel(f"Modifier la transaction  ·  {txn['reference']}")
        lbl_title.setStyleSheet(
            f"color: {PALETTE['text_primary']}; font-size: 14px; font-weight: 700; background: transparent;"
        )
        badge = QLabel("▲  Entrée" if is_entry else "▼  Sortie")
        badge.setObjectName("type_badge_entry" if is_entry else "type_badge_exit")
        lbl_desig = QLabel(txn["designation"])
        lbl_desig.setStyleSheet(
            f"color: {PALETTE['text_muted']}; font-size: 12px; background: transparent;"
        )

        hdr_lay.addWidget(badge)
        hdr_lay.addWidget(lbl_title)
        hdr_lay.addWidget(lbl_desig)
        hdr_lay.addStretch()
        root_layout.addWidget(hdr_w)
        root_layout.addWidget(_make_separator())

        # ── Corps : 2 colonnes ──────────────────────────────────────────
        body_w = QWidget(); body_w.setStyleSheet("background: transparent;")
        body_lay = QHBoxLayout(body_w)
        body_lay.setContentsMargins(0, 0, 0, 0)
        body_lay.setSpacing(20)

        # ── Colonne gauche ──────────────────────────────────────────────
        left_w = QWidget(); left_w.setObjectName("dlg_card")
        left_lay = QVBoxLayout(left_w)
        left_lay.setContentsMargins(16, 14, 16, 14)
        left_lay.setSpacing(12)

        sec_l = QLabel("IDENTIFICATION")
        sec_l.setObjectName("section_title")
        left_lay.addWidget(sec_l)
        left_lay.addWidget(_make_separator())

        ref_edit = QLineEdit(txn["reference"])
        left_lay.addWidget(self._field_widget("Référence", ref_edit))

        desig_edit = QLineEdit(txn["designation"])
        left_lay.addWidget(self._field_widget("Désignation", desig_edit))

        store_edit = QComboBox()
        store_edit.addItem("Sélectionner un magasin", None)
        stores = self.session.query(Store).order_by(Store.name).all()
        for s in stores:
            store_edit.addItem(s.name, s.id)
            if s.id == txn["store_id"]:
                store_edit.setCurrentText(s.name)
        left_lay.addWidget(self._field_widget("Magasin", store_edit))

        left_lay.addStretch()
        body_lay.addWidget(left_w, 1)

        # ── Séparateur vertical ─────────────────────────────────────────
        vsep = QFrame()
        vsep.setFrameShape(QFrame.VLine)
        vsep.setFixedWidth(1)
        vsep.setStyleSheet(f"background: {PALETTE['border']}; border: none;")
        body_lay.addWidget(vsep)

        # ── Colonne droite ──────────────────────────────────────────────
        right_w = QWidget(); right_w.setObjectName("dlg_card")
        right_lay = QVBoxLayout(right_w)
        right_lay.setContentsMargins(16, 14, 16, 14)
        right_lay.setSpacing(12)

        sec_r = QLabel("MOUVEMENT")
        sec_r.setObjectName("section_title")
        right_lay.addWidget(sec_r)
        right_lay.addWidget(_make_separator())

        date_edit = QDateEdit()
        date_edit.setCalendarPopup(True)
        date_edit.setDisplayFormat("dd/MM/yyyy")
        try:
            date_str = _date_to_str(txn["date"])
            year, month, day = map(int, date_str.split("-"))
            date_edit.setDate(QDate(year, month, day))
        except Exception:
            date_edit.setDate(QDate.currentDate())
        right_lay.addWidget(self._field_widget("Date", date_edit))

        label_counterpart = "Fournisseur" if is_entry else "Destination"
        counterpart_edit = QLineEdit(txn["counterpart"] if txn["counterpart"] != "—" else "")
        right_lay.addWidget(self._field_widget(label_counterpart, counterpart_edit))

        invoice_edit = QLineEdit(txn["invoice"])
        right_lay.addWidget(self._field_widget("N° facture", invoice_edit))

        qty_edit = QLineEdit(str(txn["in_qty"] if txn["in_qty"] else txn["out_qty"]))
        right_lay.addWidget(self._field_widget("Quantité", qty_edit))

        right_lay.addStretch()
        body_lay.addWidget(right_w, 1)

        root_layout.addWidget(body_w, 1)

        # ── Pied : boutons ──────────────────────────────────────────────
        root_layout.addWidget(_make_separator())

        btn_box = QWidget(); btn_box.setStyleSheet("background: transparent;")
        btn_layout = QHBoxLayout(btn_box)
        btn_layout.setContentsMargins(0, 0, 0, 0)
        btn_layout.setSpacing(8)
        btn_cancel = QPushButton("Annuler")
        btn_cancel.setFixedHeight(34)
        btn_cancel.setMinimumWidth(100)
        btn_save = QPushButton("✔  Enregistrer")
        btn_save.setObjectName("btn_primary")
        btn_save.setFixedHeight(34)
        btn_save.setMinimumWidth(130)
        btn_layout.addStretch()
        btn_layout.addWidget(btn_cancel)
        btn_layout.addWidget(btn_save)
        root_layout.addWidget(btn_box)

        # ── Logique de sauvegarde (inchangée) ───────────────────────────
        def on_save():
            if not ref_edit.text().strip() or not desig_edit.text().strip():
                QMessageBox.warning(dlg, "Champs requis",
                    "Référence et désignation sont obligatoires.")
                return
            if store_edit.currentData() is None:
                QMessageBox.warning(dlg, "Magasin requis",
                    "Sélectionnez un magasin pour la transaction.")
                return
            try:
                qty = int(qty_edit.text().strip())
                if qty <= 0:
                    raise ValueError
            except Exception:
                QMessageBox.warning(dlg, "Quantité invalide",
                    "Entrez une quantité positive.")
                return
            try:
                selected_date = date_edit.date().toString("yyyy-MM-dd")
                if txn["record_type"] == "entry":
                    record = self.session.get(StockEntry, txn["id"])
                    record.supplier       = counterpart_edit.text().strip()
                    record.invoice_number = invoice_edit.text().strip()
                    record.quantity       = qty
                else:
                    record = self.session.get(StockOutput, txn["id"])
                    record.destination    = counterpart_edit.text().strip()
                    record.invoice_number = invoice_edit.text().strip()
                    record.quantity       = qty
                record.date        = selected_date
                record.reference   = ref_edit.text().strip()
                record.designation = desig_edit.text().strip()
                record.store_id    = store_edit.currentData()
                self.session.commit()
                dlg.accept()
                self._load_transactions()
                self._apply_filters()
                QMessageBox.information(self, "Modification réussie",
                    "La transaction a été mise à jour.")
            except Exception as e:
                QMessageBox.critical(dlg, "Erreur modification", str(e))

        btn_cancel.clicked.connect(dlg.reject)
        btn_save.clicked.connect(on_save)
        dlg.exec()

    def _field_widget(self, label, widget):
        container = QWidget(); container.setStyleSheet("background: transparent;")
        layout = QVBoxLayout(container)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(4)
        lbl = QLabel(label); lbl.setObjectName("field_label")
        layout.addWidget(lbl)
        layout.addWidget(widget)
        return container

    def _reset_filters(self):
        self.f_product.blockSignals(True)
        self.f_product.setCurrentIndex(0)
        self.f_product.blockSignals(False)
        self._selected_ref = None
        self.lbl_product_name.setText("Toutes les transactions")
        self.btn_pdf.setEnabled(False)

        self.f_store.setCurrentIndex(0)
        self.f_type.setCurrentIndex(0)
        self.f_date_from.setDate(QDate(QDate.currentDate().year(), 1, 1))
        self.f_date_to.setDate(QDate.currentDate())
        self.table_search.clear()

        self._load_transactions()
        self._apply_filters()

    def _export_pdf(self):
        ref = self._selected_ref
        if ref is None:
            QMessageBox.information(self, "Sélection requise",
                "Sélectionnez un produit dans le filtre avant d'exporter le rapport PDF.")
            return
        if not self._filtered:
            QMessageBox.information(self, "Aucune donnée",
                "Aucune transaction à exporter pour le produit sélectionné.")
            return

        default = f"transactions_{ref}_{date.today().strftime('%Y%m%d')}.pdf"
        path, _ = QFileDialog.getSaveFileName(
            self, "Enregistrer le rapport PDF", default, "PDF Files (*.pdf)"
        )
        if not path:
            return
        try:
            _build_pdf(path, ref, self._filtered, self.session)
            QMessageBox.information(self, "Export réussi",
                f"Rapport PDF enregistré :\n{path}")
        except Exception as e:
            error_msg = f"Erreur export PDF: {str(e)}\n\nTraceback:\n{traceback.format_exc()}"
            logging.error(error_msg)
            print(error_msg)
            QMessageBox.critical(self, "Erreur export PDF", error_msg)

    def _export_pdf_all(self):
        if not self._filtered:
            QMessageBox.information(self, "Aucune donnée",
                "Aucune transaction à exporter.")
            return

        default = f"transactions_tous_{date.today().strftime('%Y%m%d')}.pdf"
        path, _ = QFileDialog.getSaveFileName(
            self, "Enregistrer le rapport PDF", default, "PDF Files (*.pdf)"
        )
        if not path:
            return
        try:
            _build_pdf(path, self._selected_ref, self._filtered, self.session)
            QMessageBox.information(self, "Export réussi",
                f"Rapport PDF enregistré :\n{path}")
        except Exception as e:
            error_msg = f"Erreur export PDF: {str(e)}\n\nTraceback:\n{traceback.format_exc()}"
            logging.error(error_msg)
            print(error_msg)
            QMessageBox.critical(self, "Erreur export PDF", error_msg)

    def refresh(self):
        self._load_combos()
        self._load_transactions()
        self._apply_filters()
