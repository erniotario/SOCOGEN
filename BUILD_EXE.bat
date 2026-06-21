@echo off
chcp 65001 >nul
title SOCOGEN — Build EXE

echo.
echo  ╔══════════════════════════════════════════╗
echo  ║     SOCOGEN — Génération du .exe         ║
echo  ╚══════════════════════════════════════════╝
echo.

:: ── 1. Vérifier PyInstaller ─────────────────────────────────
python -m pyinstaller --version >nul 2>&1
if errorlevel 1 (
    echo [1/5] Installation de PyInstaller...
    pip install pyinstaller
) else (
    echo [1/5] PyInstaller OK
)

:: ── 2. Vérifier les dépendances du projet ───────────────────
echo [2/5] Vérification des dépendances...
pip install PySide6 sqlalchemy openpyxl reportlab --quiet
echo       OK

:: ── 3. Nettoyer les anciens builds ──────────────────────────
echo [3/5] Nettoyage...
if exist "dist"  rmdir /s /q "dist"
if exist "build" rmdir /s /q "build"
if exist "SOCOGEN.spec" del /q "SOCOGEN.spec"
echo       OK

:: ── 4. Compiler ─────────────────────────────────────────────
echo [4/5] Compilation en cours (2-4 minutes)...
echo.

python -m pyinstaller ^
  --name "SOCOGEN" ^
  --windowed ^
  --onedir ^
  --noconfirm ^
  --clean ^
  --add-data "ui;ui" ^
  --hidden-import PySide6.QtCore ^
  --hidden-import PySide6.QtGui ^
  --hidden-import PySide6.QtWidgets ^
  --hidden-import PySide6.QtSvg ^
  --hidden-import sqlalchemy.dialects.sqlite ^
  --hidden-import sqlalchemy.orm ^
  --hidden-import openpyxl ^
  --hidden-import openpyxl.styles ^
  --hidden-import reportlab ^
  --hidden-import reportlab.lib ^
  --hidden-import reportlab.platypus ^
  --hidden-import reportlab.pdfgen ^
  --exclude-module tkinter ^
  --exclude-module matplotlib ^
  --exclude-module numpy ^
  --exclude-module pandas ^
  --exclude-module jupyter ^
  main.py

echo.

:: ── 5. Vérifier et finaliser ─────────────────────────────────
if exist "dist\SOCOGEN\SOCOGEN.exe" (
    echo [5/5] Finalisation...

    :: Copier la base de données si elle existe
    if exist "socogen_stock.db" (
        copy /Y "socogen_stock.db" "dist\SOCOGEN\" >nul
        echo       Base de données copiée.
    )

    :: Copier le logo si disponible
    if exist "logo.png"  copy /Y "logo.png"  "dist\SOCOGEN\" >nul
    if exist "logo.ico"  copy /Y "logo.ico"  "dist\SOCOGEN\" >nul
    if exist "assets"    xcopy /E /I /Y "assets" "dist\SOCOGEN\assets\" >nul

    echo.
    echo  ╔══════════════════════════════════════════╗
    echo  ║   BUILD RÉUSSI !                         ║
    echo  ║   dist\SOCOGEN\SOCOGEN.exe               ║
    echo  ╚══════════════════════════════════════════╝
    echo.
    echo  Pour distribuer :
    echo    → Zippez le dossier dist\SOCOGEN\
    echo    → Ou créez un installeur avec installer.iss
    echo.
    :: Ouvrir le dossier dist automatiquement
    explorer "dist\SOCOGEN"
) else (
    echo.
    echo  ╔══════════════════════════════════════════╗
    echo  ║   ERREUR : Compilation échouée.          ║
    echo  ║   Vérifiez les messages ci-dessus.       ║
    echo  ╚══════════════════════════════════════════╝
)

pause
