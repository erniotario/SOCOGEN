; installer.nsi — SOCOGEN Stock Manager
; Étape 1 : pyinstaller --noconfirm --onedir --windowed --icon=logo.ico --name SOCOGEN main.py
; Étape 2 : copy socogen_stock.db dist\SOCOGEN\socogen_stock.db
; Étape 3 : copy logo.ico dist\SOCOGEN\logo.ico
; Étape 4 : makensis installer.nsi

Unicode True

!define APP_NAME      "SOCOGEN"
!define APP_VERSION   "1.0"
!define APP_PUBLISHER "SOCOGEN"
!define APP_EXE       "SOCOGEN.exe"
!define DIST_DIR      "dist\SOCOGEN"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}"

; ── Icônes installateur ───────────────────────────────────────────────
!define MUI_ICON   "logo.ico"
!define MUI_UNICON "logo.ico"

Name "${APP_NAME} ${APP_VERSION}"
OutFile "SOCOGEN_Setup.exe"
InstallDir "$LOCALAPPDATA\${APP_NAME}"
InstallDirRegKey HKCU "${UNINSTALL_KEY}" "InstallLocation"
RequestExecutionLevel user
SetCompressor /SOLID lzma
BrandingText "${APP_NAME} ${APP_VERSION} — Gestion de Stock"

!include "MUI2.nsh"

!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TITLE "Installation de ${APP_NAME} ${APP_VERSION}"
!define MUI_WELCOMEPAGE_TEXT  "Bienvenue dans l'assistant d'installation de ${APP_NAME}.$\r$\n$\r$\nGestion de Stock — Yaoundé, Cameroun$\r$\n$\r$\nCliquez sur Suivant pour continuer."
!define MUI_FINISHPAGE_RUN      "$INSTDIR\${APP_EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Lancer ${APP_NAME} maintenant"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "French"

; ── Installation ──────────────────────────────────────────────────────
Section "Application" SecApp
    SectionIn RO
    SetOutPath "$INSTDIR"

    ; Copier tous les fichiers du build SAUF la base de données
    File /r /x "socogen_stock.db" "${DIST_DIR}\*.*"

    ; Copier la base seulement si elle n'existe pas déjà
    ; (protège les données lors d'une mise à jour)
    IfFileExists "$INSTDIR\socogen_stock.db" +2 0
        File "${DIST_DIR}\socogen_stock.db"

    ; Raccourci Bureau avec logo
    CreateShortcut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\logo.ico" 0

    ; Raccourci Menu Démarrer avec logo
    CreateDirectory "$SMPROGRAMS\${APP_NAME}"
    CreateShortcut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"  "$INSTDIR\${APP_EXE}" "" "$INSTDIR\logo.ico" 0
    CreateShortcut "$SMPROGRAMS\${APP_NAME}\Désinstaller.lnk" "$INSTDIR\Uninstall.exe"

    WriteUninstaller "$INSTDIR\Uninstall.exe"

    ; Icône dans Programmes et fonctionnalités
    WriteRegStr   HKCU "${UNINSTALL_KEY}" "DisplayName"     "${APP_NAME}"
    WriteRegStr   HKCU "${UNINSTALL_KEY}" "DisplayVersion"  "${APP_VERSION}"
    WriteRegStr   HKCU "${UNINSTALL_KEY}" "Publisher"       "${APP_PUBLISHER}"
    WriteRegStr   HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
    WriteRegStr   HKCU "${UNINSTALL_KEY}" "UninstallString" "$INSTDIR\Uninstall.exe"
    WriteRegStr   HKCU "${UNINSTALL_KEY}" "DisplayIcon"     "$INSTDIR\logo.ico"
    WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify"        1
    WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair"        1
SectionEnd

; ── Désinstallation ───────────────────────────────────────────────────
Section "Uninstall"
    RMDir /r "$INSTDIR"

    Delete "$DESKTOP\${APP_NAME}.lnk"
    Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
    Delete "$SMPROGRAMS\${APP_NAME}\Désinstaller.lnk"
    RMDir  "$SMPROGRAMS\${APP_NAME}"

    DeleteRegKey HKCU "${UNINSTALL_KEY}"

    MessageBox MB_OK "$(^Name) a été désinstallé.$\r$\nVos données ont été conservées dans :$\r$\n$LOCALAPPDATA\SOCOGEN"
SectionEnd
