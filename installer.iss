; ─────────────────────────────────────────────────────────────
;  Script Inno Setup — Installeur professionnel SOCOGEN
;  Télécharger Inno Setup : https://jrsoftware.org/isinfo.php
;  Compiler ce fichier avec Inno Setup Compiler
; ─────────────────────────────────────────────────────────────

#define AppName      "SOCOGEN Gestion de Stock"
#define AppVersion   "1.0.0"
#define AppPublisher "SHEMAB"
#define AppExeName   "SOCOGEN.exe"
#define AppIcon      "assets\icon.ico"

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL=https://shemab.cm
DefaultDirName={autopf}\SOCOGEN
DefaultGroupName={#AppName}
AllowNoIcons=yes
OutputDir=installer_output
OutputBaseFilename=SOCOGEN_Setup_v{#AppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes
; Icône de l'installeur (décommentez si vous avez assets\icon.ico)
; SetupIconFile={#AppIcon}
UninstallDisplayName={#AppName}
; UninstallDisplayIcon={app}\{#AppExeName}
PrivilegesRequired=lowest   ; Pas besoin d'admin
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "Créer une icône sur le Bureau"; GroupDescription: "Icônes supplémentaires :"; Flags: unchecked

[Files]
; Tous les fichiers de l'application compilée
Source: "dist\SOCOGEN\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Base de données initiale (vide) — sera copiée uniquement si absente
Source: "socogen_stock.db"; DestDir: "{userappdata}\SOCOGEN"; Flags: onlyifdoesntexist uninsneveruninstall

[Icons]
Name: "{group}\{#AppName}";      Filename: "{app}\{#AppExeName}"
Name: "{group}\Désinstaller";    Filename: "{uninstallexe}"
Name: "{commondesktop}\SOCOGEN"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Registry]
; Stocker le chemin de la base de données dans le registre
Root: HKCU; Subkey: "Software\SHEMAB\SOCOGEN"; ValueType: string; ValueName: "DataPath"; ValueData: "{userappdata}\SOCOGEN"

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Lancer SOCOGEN"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
// Message de bienvenue personnalisé
function InitializeSetup(): Boolean;
begin
  Result := True;
end;
