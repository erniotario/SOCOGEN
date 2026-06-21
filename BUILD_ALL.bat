@echo off
chcp 65001 >nul
title SOCOGEN — Build complet

echo.
echo  ╔══════════════════════════════════════════════╗
echo  ║   SOCOGEN — Build EXE + Installeur NSIS      ║
echo  ╚══════════════════════════════════════════════╝
echo.

:: ════════════════════════════════════════════════
::  ÉTAPE 1 — Dépendances Python
:: ════════════════════════════════════════════════
echo [ETAPE 1/4] Installation des dépendances...
pip install pyinstaller PySide6 sqlalchemy openpyxl reportlab --quiet
echo  OK
echo.

:: ════════════════════════════════════════════════
::  ÉTAPE 2 — Nettoyage
:: ════════════════════════════════════════════════
echo [ETAPE 2/4] Nettoyage des anciens builds...
if exist "dist"  rmdir /s /q "dist"
if exist "build" rmdir /s /q "build"
echo  OK
echo.

:: ════════════════════════════════════════════════
::  ÉTAPE 3 — PyInstaller
:: ════════════════════════════════════════════════
echo [ETAPE 3/4] Compilation PyInstaller (2-4 min)...
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
  --hidden-import reportlab ^
  --hidden-import reportlab.lib ^
  --hidden-import reportlab.platypus ^
  --exclude-module tkinter ^
  --exclude-module matplotlib ^
  --exclude-module numpy ^
  main.py

:: Vérifier que le .exe a bien été créé
if not exist "dist\SOCOGEN\SOCOGEN.exe" (
    echo.
    echo  ERREUR PyInstaller : dist\SOCOGEN\SOCOGEN.exe non créé.
    echo  Vérifiez les messages d erreur ci-dessus.
    pause
    exit /b 1
)

:: Copier la base de données dans dist
if exist "socogen_stock.db" (
    copy /Y "socogen_stock.db" "dist\SOCOGEN\" >nul
    echo  Base de données copiée dans dist\SOCOGEN\
)
if exist "assets" xcopy /E /I /Y "assets" "dist\SOCOGEN\assets\" >nul

echo.
echo  PyInstaller OK : dist\SOCOGEN\SOCOGEN.exe
echo.

:: ════════════════════════════════════════════════
::  ÉTAPE 4 — NSIS
:: ════════════════════════════════════════════════
echo [ETAPE 4/4] Création de l installeur NSIS...

:: Trouver makensis.exe
set NSIS=
if exist "C:\Program Files (x86)\NSIS\makensis.exe" set NSIS=C:\Program Files (x86)\NSIS\makensis.exe
if exist "C:\Program Files\NSIS\makensis.exe"       set NSIS=C:\Program Files\NSIS\makensis.exe

if "%NSIS%"=="" (
    echo  NSIS non trouve. Telechargez : https://nsis.sourceforge.io/Download
    echo  Le .exe est disponible dans dist\SOCOGEN\SOCOGEN.exe
    explorer "dist\SOCOGEN"
    pause
    exit /b 0
)

"%NSIS%" installer.nsi

if exist "SOCOGEN_Setup_v1.0.0.exe" (
    echo.
    echo  ╔══════════════════════════════════════════════╗
    echo  ║   TOUT EST PRÊT !                            ║
    echo  ║                                              ║
    echo  ║   .exe brut   : dist\SOCOGEN\SOCOGEN.exe     ║
    echo  ║   Installeur  : SOCOGEN_Setup_v1.0.0.exe     ║
    echo  ╚══════════════════════════════════════════════╝
    explorer .
) else (
    echo.
    echo  NSIS a échoué. Le .exe brut reste disponible :
    echo  dist\SOCOGEN\SOCOGEN.exe
    explorer "dist\SOCOGEN"
)

pause
