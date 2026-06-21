# Ce fichier remplace qt_main.py — ajoute le splash screen professionnel
# Renomme ton qt_main.py existant en qt_main_old.py et utilise celui-ci

import sys
import os
from PySide6.QtWidgets import QApplication, QSplashScreen
from PySide6.QtGui import QPixmap, QPainter, QColor, QFont, QLinearGradient
from PySide6.QtCore import Qt, QRect


def _make_splash_pixmap(width=520, height=300):
    """Génère un splash screen élégant même sans fichier logo."""
    pix = QPixmap(width, height)
    pix.fill(QColor("#0D1117"))

    painter = QPainter(pix)
    painter.setRenderHint(QPainter.Antialiasing)

    # Fond dégradé
    grad = QLinearGradient(0, 0, width, height)
    grad.setColorAt(0.0, QColor("#0D1117"))
    grad.setColorAt(1.0, QColor("#161B22"))
    painter.fillRect(0, 0, width, height, grad)

    # Barre de couleur en haut
    painter.fillRect(0, 0, width, 5, QColor("#1F6FEB"))

    # Logo texte — SOCOGEN
    painter.setPen(QColor("#58A6FF"))
    f = QFont("Segoe UI", 42, QFont.Bold)
    painter.setFont(f)
    painter.drawText(QRect(0, 60, width, 80), Qt.AlignCenter, "SOCOGEN")

    # Sous-titre
    painter.setPen(QColor("#8B949E"))
    f2 = QFont("Segoe UI", 13)
    painter.setFont(f2)
    painter.drawText(QRect(0, 145, width, 30), Qt.AlignCenter, "Gestion de Stock")

    # Version
    painter.setPen(QColor("#484F58"))
    f3 = QFont("Segoe UI", 9)
    painter.setFont(f3)
    painter.drawText(QRect(0, 185, width, 20), Qt.AlignCenter, "Version 1.0  •  Yaoundé, Cameroun")

    # Barre de chargement (décorative)
    bar_x, bar_y, bar_w, bar_h = 100, 230, 320, 4
    painter.fillRect(bar_x, bar_y, bar_w, bar_h, QColor("#21262D"))
    painter.fillRect(bar_x, bar_y, int(bar_w * 0.75), bar_h, QColor("#1F6FEB"))

    # Message de chargement
    painter.setPen(QColor("#484F58"))
    f4 = QFont("Segoe UI", 9)
    painter.setFont(f4)
    painter.drawText(QRect(0, 245, width, 20), Qt.AlignCenter, "Chargement en cours…")

    # Barre basse
    painter.fillRect(0, height - 5, width, 5, QColor("#1F6FEB"))

    painter.end()
    return pix


def run_qt_app():
    app = QApplication.instance() or QApplication(sys.argv)
    app.setApplicationName("SOCOGEN")
    app.setApplicationVersion("1.0")
    app.setOrganizationName("SOCOGEN")

    # Apply global stylesheet
    from styles import QSS
    app.setStyleSheet(QSS)

    # Splash screen — shown while the main window loads
    base = os.path.dirname(sys.executable) if getattr(sys, 'frozen', False) else os.path.dirname(os.path.abspath(__file__))
    pix = None
    for name in ("logo.png", "logo.ico", "splash.png"):
        candidate = os.path.join(base, name)
        if os.path.exists(candidate):
            pix = QPixmap(candidate).scaled(520, 300, Qt.KeepAspectRatio, Qt.SmoothTransformation)
            break
    if pix is None:
        pix = _make_splash_pixmap()

    splash = QSplashScreen(pix, Qt.WindowStaysOnTopHint)
    splash.show()
    app.processEvents()

    from main_window import MainWindow
    window = MainWindow()
    window.show()
    splash.finish(window)

    sys.exit(app.exec())
