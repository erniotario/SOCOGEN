# -*- mode: python ; coding: utf-8 -*-
# ─────────────────────────────────────────────────────────────
#  Fichier de configuration PyInstaller — SOCOGEN
#  Commande : pyinstaller build.spec
# ─────────────────────────────────────────────────────────────

import sys
from pathlib import Path

block_cipher = None

a = Analysis(
    ['main.py'],
    pathex=['.'],
    binaries=[],
    datas=[
        # Inclure tous les fichiers de l'interface
        ('ui',            'ui'),
        # Inclure les assets si vous en avez (logo, icônes, etc.)
        # ('assets',     'assets'),
    ],
    hiddenimports=[
        # PySide6
        'PySide6.QtCore',
        'PySide6.QtGui',
        'PySide6.QtWidgets',
        'PySide6.QtSvg',
        'PySide6.QtXml',
        # SQLAlchemy
        'sqlalchemy',
        'sqlalchemy.dialects.sqlite',
        'sqlalchemy.orm',
        'sqlalchemy.pool',
        # ReportLab
        'reportlab',
        'reportlab.lib',
        'reportlab.platypus',
        'reportlab.pdfgen',
        # openpyxl
        'openpyxl',
        'openpyxl.styles',
        'openpyxl.utils',
        # Autres
        'hashlib',
        'csv',
        'logging',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        # Exclure ce qui n'est pas nécessaire pour réduire la taille
        'tkinter',
        'matplotlib',
        'numpy',
        'pandas',
        'scipy',
        'pytest',
        'IPython',
        'jupyter',
        'notebook',
    ],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='SOCOGEN',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,               # Compresse les binaires (réduit la taille)
    console=False,          # Pas de fenêtre console noire
    disable_windowed_traceback=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    # ── Icône de l'application ──────────────────────────────
    # icon='assets/icon.ico',   # Décommentez si vous avez une icône .ico
    version='version_info.txt', # Informations de version Windows
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='SOCOGEN',
)
