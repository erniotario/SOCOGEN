@echo off
chcp 65001 >nul
title SOCOGEN — Build Installeur NSIS

echo.
echo  ╔══════════════════════════════════════════╗
echo  ║   SOCOGEN — Création de l installeur     ║
echo  ╚══════════════════════════════════════════╝
echo.

:: ── Vérifier que le .exe compilé existe ─────────────────────
if not exist "dist\SOCOGEN\SOCOGEN.exe" (
    echo  ERREUR : dist\SOCOGEN\SOCOGEN.exe introuvable.
    echo  Lancez d abord BUILD_EXE.bat pour compiler l application.
    echo.
    pause
    exit /b 1
)
echo [1/3] Application compilee : OK

:: ── Vérifier NSIS ───────────────────────────────────────────
set NSIS_PATH=C:\Program Files (x86)\NSIS\makensis.exe
if not exist "%NSIS_PATH%" (
    set NSIS_PATH=C:\Program Files\NSIS\makensis.exe
)
if not exist "%NSIS_PATH%" (
    echo  ERREUR : NSIS introuvable.
    echo  Telechargez-le sur : https://nsis.sourceforge.io/Download
    pause
    exit /b 1
)
echo [2/3] NSIS trouve : %NSIS_PATH%

:: ── Compiler l'installeur ────────────────────────────────────
echo [3/3] Compilation de l installeur...
echo.
"%NSIS_PATH%" installer.nsi

if exist "SOCOGEN_Setup_v1.0.0.exe" (
    echo.
    echo  ╔══════════════════════════════════════════╗
    echo  ║   SUCCES !                               ║
    echo  ║   SOCOGEN_Setup_v1.0.0.exe               ║
    echo  ╚══════════════════════════════════════════╝
    echo.
    explorer .
) else (
    echo.
    echo  ECHEC. Verifiez les erreurs ci-dessus.
)
pause
