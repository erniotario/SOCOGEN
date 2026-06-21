QSS = """
/* ========================================
   GLOBAL
======================================== */
* {
    font-family: "Segoe UI", "SF Pro Display", sans-serif;
    font-size: 13px;
    color: #E6EDF3;
    outline: none;
}

QMainWindow, QWidget {
    background-color: #0D1117;
    color: #E6EDF3;
}

QLabel {
    background-color: transparent;
}

/* ========================================
   SIDEBAR
======================================== */
#sidebar {
    background-color: #010409;
    border-right: 1px solid #21262D;
}

#brand_name {
    font-size: 15px;
    font-weight: bold;
    color: #58A6FF;
    letter-spacing: 2px;
    background-color: transparent;
}

#brand_sub {
    font-size: 10px;
    color: #484F58;
    letter-spacing: 1px;
    text-transform: uppercase;
    background-color: transparent;
}

#nav_btn {
    background-color: transparent;
    border: none;
    border-radius: 6px;
    padding: 10px 14px;
    text-align: left;
    color: #9BA8B5;
    font-size: 13px;
    margin: 1px 8px;
}

#nav_btn:hover {
    background-color: #161B22;
    color: #C9D1D9;
}

#nav_btn:checked {
    background-color: #161B22;
    color: #58A6FF;
    font-weight: bold;
    border-left: 2px solid #58A6FF;
    padding-left: 12px;
}

#sidebar_version {
    font-size: 11px;
    color: #5F7B93;
    background-color: transparent;
    padding: 16px 20px;
}

/* ========================================
   PAGE HEADER
======================================== */
#page_header {
    background: qlineargradient(spread:pad, x1:0, y1:0, x2:1, y2:0, stop:0 #0D1117, stop:1 #111827);
    border-bottom: 1px solid rgba(255, 255, 255, 0.05);
}

#page_title {
    font-size: 20px;
    font-weight: 700;
    color: #F0F6FC;
    background-color: transparent;
}

#page_subtitle {
    font-size: 12px;
    color: #A8B5C4;
    background-color: transparent;
    margin-top: 3px;
}

/* ========================================
   STAT CARDS
======================================== */
#stat_card {
    background: qlineargradient(spread:pad, x1:0, y1:0, x2:1, y2:1, stop:0 rgba(23, 29, 38, 0.95), stop:1 rgba(15, 18, 25, 0.95));
    border: 1px solid rgba(96, 165, 250, 0.15);
    border-radius: 16px;
}

#stat_value {
    font-size: 28px;
    font-weight: 700;
    color: #E6EDF3;
    background-color: transparent;
}

#stat_label {
    font-size: 11px;
    color: #A8B5C4;
    letter-spacing: 0.4px;
    background-color: transparent;
}

#stat_icon {
    font-size: 24px;
    background-color: transparent;
}

/* ========================================
   FORM PANEL
======================================== */
#form_panel {
    background: rgba(14, 18, 25, 0.92);
    border: 1px solid rgba(148, 163, 184, 0.12);
    border-radius: 16px;
}

#form_panel_title {
    font-size: 13px;
    font-weight: 700;
    color: #A8B5C4;
    letter-spacing: 0.5px;
    background-color: transparent;
}

#field_label {
    font-size: 11px;
    font-weight: 700;
    color: #A8B5C4;
    letter-spacing: 0.4px;
    text-transform: uppercase;
    background-color: transparent;
    margin-bottom: 4px;
}

#search_container {
    background-color: #010409;
    border: 1px solid rgba(148, 163, 184, 0.15);
    border-radius: 12px;
}

#search_container:focus-within {
    border-color: #58A6FF;
}

/* ========================================
   INPUTS
======================================== */
QLineEdit, QSpinBox, QComboBox, QDateEdit {
    background-color: #010409;
    border: 1px solid rgba(148, 163, 184, 0.16);
    border-radius: 12px;
    padding: 10px 14px;
    color: #E6EDF3;
    font-size: 13px;
    min-height: 40px;
    selection-background-color: #1F6FEB;
}

QLineEdit:focus, QSpinBox:focus, QComboBox:focus, QDateEdit:focus {
    border: 1px solid #58A6FF;
    background-color: #010409;
}

QLineEdit:hover, QSpinBox:hover, QComboBox:hover, QDateEdit:hover {
    border: 1px solid rgba(148, 163, 184, 0.4);
}

QLineEdit[readOnly="true"] {
    color: #484F58;
    border-color: #21262D;
    background-color: #0D1117;
}

QLineEdit::placeholder {
    color: #484F58;
}

QSpinBox::up-button, QSpinBox::down-button,
QDateEdit::up-button, QDateEdit::down-button {
    background-color: #21262D;
    border: none;
    width: 20px;
    border-radius: 2px;
}

QSpinBox::up-button:hover, QSpinBox::down-button:hover,
QDateEdit::up-button:hover, QDateEdit::down-button:hover {
    background-color: #30363D;
}

QSpinBox::up-arrow { border-left: 4px solid transparent; border-right: 4px solid transparent; border-bottom: 5px solid #7D8590; width:0; height:0; }
QSpinBox::down-arrow { border-left: 4px solid transparent; border-right: 4px solid transparent; border-top: 5px solid #7D8590; width:0; height:0; }
QDateEdit::up-arrow { border-left: 4px solid transparent; border-right: 4px solid transparent; border-bottom: 5px solid #7D8590; width:0; height:0; }
QDateEdit::down-arrow { border-left: 4px solid transparent; border-right: 4px solid transparent; border-top: 5px solid #7D8590; width:0; height:0; }

QComboBox {
    padding-right: 30px;
}

QComboBox::drop-down {
    border: none;
    background-color: #21262D;
    border-radius: 0 5px 5px 0;
    width: 28px;
}

QComboBox::down-arrow {
    border-left: 4px solid transparent;
    border-right: 4px solid transparent;
    border-top: 5px solid #7D8590;
    width: 0;
    height: 0;
}

QComboBox QAbstractItemView {
    background-color: #161B22;
    border: 1px solid #30363D;
    border-radius: 6px;
    selection-background-color: #1F6FEB;
    color: #E6EDF3;
    padding: 4px;
    outline: none;
}

QComboBox QAbstractItemView::item {
    padding: 6px 12px;
    min-height: 28px;
    border-radius: 4px;
}

QComboBox QAbstractItemView::item:hover {
    background-color: #21262D;
}

/* ========================================
   BUTTONS
======================================== */
QPushButton {
    background-color: #238636;
    color: white;
    border: none;
    border-radius: 10px;
    padding: 8px 16px;
    font-size: 12px;
    font-weight: 700;
    min-height: 34px;
    letter-spacing: 0.08px;
}

QPushButton:hover {
    background-color: #2EA043;
}

QPushButton:pressed {
    background-color: #196C2E;
}

QPushButton#btn_primary {
    background-color: #1F6FEB;
}

QPushButton#btn_primary:hover {
    background-color: #388BFD;
}

QPushButton#btn_primary:pressed {
    background-color: #1158C7;
}

QPushButton#btn_danger {
    background-color: transparent;
    border: 1px solid #F85149;
    color: #F85149;
}

QPushButton#btn_danger:hover {
    background-color: #F85149;
    color: white;
}

QPushButton#btn_secondary {
    background-color: #21262D;
    color: #C9D1D9;
    border: 1px solid #30363D;
}

QPushButton#btn_secondary:hover {
    background-color: #30363D;
    border-color: #484F58;
}

/* ========================================
   TABLE
======================================== */
QTableWidget {
    background-color: #0B111A;
    alternate-background-color: #0D111A;
    gridline-color: transparent;
    border: 1px solid rgba(148, 163, 184, 0.12);
    border-radius: 16px;
    selection-background-color: rgba(56, 139, 253, 0.18);
    selection-color: #E6EDF3;
    outline: none;
}

QTableWidget::item {
    padding: 0 16px;
    border-bottom: 1px solid rgba(148, 163, 184, 0.08);
}

QTableWidget::item:selected {
    background-color: rgba(56, 139, 253, 0.18);
}

QTableWidget::item:hover {
    background-color: rgba(255, 255, 255, 0.04);
}

QHeaderView {
    background-color: transparent;
}

QHeaderView::section {
    background-color: #111827;
    color: #94A3B8;
    font-size: 11px;
    font-weight: 700;
    letter-spacing: 0.75px;
    padding: 12px 16px;
    border: none;
    border-bottom: 1px solid rgba(148, 163, 184, 0.12);
    border-right: 1px solid rgba(148, 163, 184, 0.08);
    text-transform: uppercase;
}

QHeaderView::section:last {
    border-right: none;
}

QHeaderView::section:checked {
    background-color: #1C2E4A;
}

/* ========================================
   SCROLLBAR
======================================== */
QScrollBar:vertical {
    background: #0D1117;
    width: 8px;
    margin: 0;
    border-radius: 4px;
}

QScrollBar::handle:vertical {
    background: #30363D;
    border-radius: 4px;
    min-height: 30px;
}

QScrollBar::handle:vertical:hover {
    background: #484F58;
}

QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height: 0; }
QScrollBar::add-page:vertical, QScrollBar::sub-page:vertical { background: none; }

QScrollBar:horizontal {
    background: #0D1117;
    height: 8px;
    margin: 0;
    border-radius: 4px;
}

QScrollBar::handle:horizontal {
    background: #30363D;
    border-radius: 4px;
    min-width: 30px;
}

QScrollBar::handle:horizontal:hover {
    background: #484F58;
}

QScrollBar::add-line:horizontal, QScrollBar::sub-line:horizontal { width: 0; }

/* ========================================
   STATUS BAR
======================================== */
#status_bar {
    background-color: #161B22;
    border-top: 1px solid #21262D;
    padding: 0 16px;
}

#status_ok  { color: #3FB950; font-size: 12px; background-color: transparent; }
#status_err { color: #F85149; font-size: 12px; background-color: transparent; }
#status_info{ color: #58A6FF; font-size: 12px; background-color: transparent; }

/* ========================================
   BADGES
======================================== */
#badge_ok {
    background-color: #1B4332;
    color: #3FB950;
    border-radius: 10px;
    padding: 2px 10px;
    font-size: 11px;
    font-weight: bold;
}

#badge_warn {
    background-color: #3D2B0A;
    color: #D29922;
    border-radius: 10px;
    padding: 2px 10px;
    font-size: 11px;
    font-weight: bold;
}

#badge_danger {
    background-color: #3D0D0A;
    color: #F85149;
    border-radius: 10px;
    padding: 2px 10px;
    font-size: 11px;
    font-weight: bold;
}

/* ========================================
   DIVIDER
======================================== */
#h_line {
    background-color: #21262D;
    max-height: 1px;
    border: none;
}

/* ========================================
   MESSAGE BOX
======================================== */
QMessageBox {
    background-color: #161B22;
}

QMessageBox QPushButton {
    min-width: 80px;
    min-height: 32px;
}
"""
