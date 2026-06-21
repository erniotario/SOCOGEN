@echo off
chcp 65001 >nul
title Build SOCOGEN — EXE

echo.
echo ================================================
echo   BUILD SOCOGEN — Generation du fichier .exe
echo ================================================
echo.

:: ── Vérifier que PyInstaller est installé ───────────────────
python -m pyinstaller --version >nul 2>&1
if errorlevel 1 (
    echo [INSTALL] PyInstaller non trouve. Installation en cours...
    pip install pyinstaller
    echo.
)

:: ── Vérifier que UPX est disponible (compression optionnelle) ─
where upx >nul 2>&1
if errorlevel 1 (
    echo [INFO] UPX non trouve ^(compression desactivee^). Telechargeable sur https://upx.github.io
    echo.
)

:: ── Nettoyer les anciens builds ──────────────────────────────
echo [1/3] Nettoyage des anciens builds...
if exist "dist\SOCOGEN" rmdir /s /q "dist\SOCOGEN"
if exist "build\SOCOGEN" rmdir /s /q "build\SOCOGEN"
echo       OK
echo.

:: ── Lancer PyInstaller ───────────────────────────────────────
echo [2/3] Compilation en cours (peut prendre 1-3 minutes)...
echo.
python -m pyinstaller build.spec --noconfirm --clean
echo.

:: ── Vérifier le résultat ─────────────────────────────────────
if exist "dist\SOCOGEN\SOCOGEN.exe" (
    echo [3/3] Copie de la base de données dans le dossier dist...
    if exist "socogen_stock.db" (
        copy "socogen_stock.db" "dist\SOCOGEN\" >nul
        echo       Base de donnees copiee.
    )
    echo.
    echo ================================================
    echo   BUILD REUSSI !
    echo   Dossier : dist\SOCOGEN\
    echo   Executable : dist\SOCOGEN\SOCOGEN.exe
    echo ================================================
    echo.
    echo Pour distribuer l'application :
    echo   - Compressez le dossier dist\SOCOGEN\ en ZIP
    echo   - Ou utilisez Inno Setup pour un vrai installeur
    echo.
) else (
    echo.
    echo ================================================
    echo   ERREUR : La compilation a echoue.
    echo   Verifiez les messages d'erreur ci-dessus.
    echo ================================================
)
pause
