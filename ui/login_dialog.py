import hashlib
import secrets

from PySide6.QtWidgets import (
    QDialog, QVBoxLayout, QLabel, QLineEdit, QPushButton
)
from PySide6.QtCore import Qt

from database import SessionLocal
from models import User


def _hash_password(password: str, salt: str) -> str:
    return hashlib.sha256((salt + password).encode()).hexdigest()


_DIALOG_STYLE = """
QDialog {
    background-color: #0D1117;
}
QLabel {
    color: #E6EDF3;
    background: transparent;
}
QLineEdit {
    background-color: #010409;
    border: 1px solid rgba(148, 163, 184, 0.2);
    border-radius: 8px;
    padding: 10px 14px;
    color: #E6EDF3;
    font-family: "Segoe UI", system-ui, sans-serif;
    font-size: 13px;
    min-height: 20px;
}
QLineEdit:focus {
    border: 1px solid #58A6FF;
}
QLineEdit::placeholder {
    color: #484F58;
}
QPushButton#btn_login {
    background-color: #1F6FEB;
    color: white;
    border: none;
    border-radius: 8px;
    font-family: "Segoe UI", system-ui, sans-serif;
    font-size: 13px;
    font-weight: 600;
    padding: 10px;
    min-height: 38px;
}
QPushButton#btn_login:hover { background-color: #388BFD; }
QPushButton#btn_login:pressed { background-color: #1158C7; }
QPushButton#btn_login:disabled { background-color: #21262D; color: #484F58; }
"""


class LoginDialog(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("SOCOGEN — Connexion")
        self.setFixedSize(400, 380)
        self.setWindowFlags(Qt.Dialog | Qt.WindowTitleHint | Qt.CustomizeWindowHint)
        self.setStyleSheet(_DIALOG_STYLE)
        self._session = SessionLocal()
        self._setup_mode = self._session.query(User).count() == 0
        self._build_ui()

    def _build_ui(self):
        root = QVBoxLayout(self)
        root.setContentsMargins(48, 44, 48, 44)
        root.setSpacing(0)

        logo = QLabel("SOCOGEN")
        logo.setAlignment(Qt.AlignCenter)
        logo.setStyleSheet(
            "color: #58A6FF; font-size: 28px; font-weight: 800; "
            "letter-spacing: 3px; font-family: 'Segoe UI', system-ui;"
        )

        sub_text = "Configuration initiale" if self._setup_mode else "Gestion de Stock"
        sub = QLabel(sub_text)
        sub.setAlignment(Qt.AlignCenter)
        sub.setStyleSheet(
            "color: #484F58; font-size: 11px; letter-spacing: 1px; "
            "font-family: 'Segoe UI', system-ui;"
        )

        root.addWidget(logo)
        root.addSpacing(4)
        root.addWidget(sub)
        root.addSpacing(32)

        if self._setup_mode:
            notice = QLabel("Créez le compte administrateur pour commencer :")
            notice.setStyleSheet(
                "color: #8B949E; font-size: 12px; font-family: 'Segoe UI', system-ui;"
            )
            root.addWidget(notice)
            root.addSpacing(12)

        self.f_username = QLineEdit()
        self.f_username.setPlaceholderText("Nom d'utilisateur")
        root.addWidget(self.f_username)
        root.addSpacing(10)

        self.f_password = QLineEdit()
        self.f_password.setPlaceholderText("Mot de passe")
        self.f_password.setEchoMode(QLineEdit.Password)
        self.f_password.returnPressed.connect(self._on_login)
        root.addWidget(self.f_password)
        root.addSpacing(8)

        self.status_lbl = QLabel("")
        self.status_lbl.setAlignment(Qt.AlignCenter)
        self.status_lbl.setStyleSheet(
            "color: #F85149; font-size: 12px; font-family: 'Segoe UI', system-ui; min-height: 18px;"
        )
        root.addWidget(self.status_lbl)
        root.addSpacing(16)

        btn_text = "Créer le compte" if self._setup_mode else "Se connecter"
        self.btn_login = QPushButton(btn_text)
        self.btn_login.setObjectName("btn_login")
        self.btn_login.clicked.connect(self._on_login)
        root.addWidget(self.btn_login)

        root.addStretch()
        self.f_username.setFocus()

    def _on_login(self):
        username = self.f_username.text().strip()
        password = self.f_password.text()

        if not username:
            self._error("Entrez un nom d'utilisateur.")
            return
        if not password:
            self._error("Entrez un mot de passe.")
            return

        if self._setup_mode:
            self._create_admin(username, password)
        else:
            self._authenticate(username, password)

    def _create_admin(self, username: str, password: str):
        try:
            salt = secrets.token_hex(16)
            user = User(
                username=username,
                password_hash=_hash_password(password, salt),
                password_salt=salt,
                role="admin",
            )
            self._session.add(user)
            self._session.commit()
            self.accept()
        except Exception as e:
            self._session.rollback()
            self._error(f"Erreur : {e}")

    def _authenticate(self, username: str, password: str):
        user = self._session.query(User).filter_by(username=username).first()
        if not user:
            self._error("Identifiants incorrects.")
            return
        if _hash_password(password, user.password_salt) != user.password_hash:
            self._error("Identifiants incorrects.")
            return
        self.accept()

    def _error(self, msg: str):
        self.status_lbl.setText(msg)

    def closeEvent(self, event):
        self._session.close()
        super().closeEvent(event)
