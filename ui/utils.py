from typing import Dict, List, Optional

from PySide6.QtWidgets import QWidget, QVBoxLayout, QHBoxLayout, QLabel, QFrame, QPushButton, QHeaderView, QTableWidget
from PySide6.QtCore import Qt


def hline():
    """Horizontal separator line."""
    line = QFrame()
    line.setFrameShape(QFrame.HLine)
    line.setObjectName("h_line")
    return line


def field(label_text: str, widget) -> QWidget:
    """Label + input stacked vertically."""
    container = QWidget()
    layout = QVBoxLayout(container)
    layout.setContentsMargins(0, 0, 0, 0)
    layout.setSpacing(5)

    lbl = QLabel(label_text.upper())
    lbl.setObjectName("field_label")
    layout.addWidget(lbl)
    layout.addWidget(widget)
    return container


def page_header(title: str, subtitle: str, actions: Optional[List[QWidget]] = None) -> QWidget:
    header = QWidget()
    header.setObjectName("page_header")
    header.setFixedHeight(72)
    layout = QHBoxLayout(header)
    layout.setContentsMargins(28, 0, 28, 0)

    title_col = QVBoxLayout()
    title_col.setSpacing(2)
    title = QLabel(title)
    title.setObjectName("page_title")
    subtitle_widget = QLabel(subtitle)
    subtitle_widget.setObjectName("page_subtitle")
    title_col.addWidget(title)
    title_col.addWidget(subtitle_widget)

    layout.addLayout(title_col)
    layout.addStretch()

    if actions:
        for widget in actions:
            layout.addWidget(widget)
            layout.addSpacing(8)

    return header


def panel(title: Optional[str] = None) -> QWidget:
    panel = QWidget()
    panel.setObjectName("form_panel")
    layout = QVBoxLayout(panel)
    layout.setContentsMargins(20, 16, 20, 16)
    layout.setSpacing(14)
    if title:
        title_lbl = QLabel(title)
        title_lbl.setObjectName("form_panel_title")
        layout.addWidget(title_lbl)
        layout.addWidget(hline())
    return panel


def status_label(text: str = "") -> QLabel:
    label = QLabel(text)
    label.setObjectName("status_ok")
    return label


def set_status(label: QLabel, msg: str, error: bool = False, info: bool = False) -> None:
    if error:
        label.setObjectName("status_err")
        prefix = "⚠ "
    elif info:
        label.setObjectName("status_info")
        prefix = "ℹ "
    else:
        label.setObjectName("status_ok")
        prefix = "✓ "
    label.setStyle(label.style())
    label.setText(prefix + msg)


def configure_table(table: QTableWidget, stretch_columns: Optional[List[int]] = None, widths: Optional[Dict[int, int]] = None, alternating: bool = True) -> None:
    if stretch_columns is None:
        stretch_columns = []
    if widths is None:
        widths = {}

    header = table.horizontalHeader()
    header.setSectionResizeMode(QHeaderView.Interactive)
    for index in stretch_columns:
        header.setSectionResizeMode(index, QHeaderView.Stretch)

    table.verticalHeader().setVisible(False)
    table.setAlternatingRowColors(alternating)
    table.setEditTriggers(QTableWidget.NoEditTriggers)
    table.setSelectionBehavior(QTableWidget.SelectRows)
    table.setShowGrid(False)
    table.verticalHeader().setDefaultSectionSize(44)

    for column, width in widths.items():
        table.setColumnWidth(column, width)


def stat_card(icon: str, value: str, label: str, color: str) -> QWidget:
    """A metric card: icon + big number + label."""
    card = QWidget()
    card.setObjectName("stat_card")
    layout = QHBoxLayout(card)
    layout.setContentsMargins(20, 18, 20, 18)
    layout.setSpacing(16)

    icon_lbl = QLabel(icon)
    icon_lbl.setObjectName("stat_icon")
    icon_lbl.setFixedWidth(36)
    icon_lbl.setAlignment(Qt.AlignCenter)
    layout.addWidget(icon_lbl)

    text_layout = QVBoxLayout()
    text_layout.setSpacing(2)

    val_lbl = QLabel(value)
    val_lbl.setObjectName("stat_value")
    val_lbl.setStyleSheet(f"color: {color}; font-size: 28px; font-weight: bold; background: transparent;")

    lbl_lbl = QLabel(label)
    lbl_lbl.setObjectName("stat_label")

    text_layout.addWidget(val_lbl)
    text_layout.addWidget(lbl_lbl)
    layout.addLayout(text_layout)
    layout.addStretch()

    card._val_lbl = val_lbl  # expose label for callers that need to update it
    return card


def make_btn(text: str, object_name: str = "") -> QPushButton:
    btn = QPushButton(text)
    if object_name:
        btn.setObjectName(object_name)
    btn.setCursor(Qt.PointingHandCursor)
    return btn
