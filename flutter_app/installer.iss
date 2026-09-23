#define AppName "ERP"
#define AppVersion "1.0.0"
#define AppPublisher "SHEMAB"
#define AppExeName "ERP.exe"
#define ReleaseDir "build\windows\x64\runner\Release"

[Setup]
; AppId is identity, not branding: Inno upgrades an existing install
; in place only while it matches. Renaming the product must not change
; it, or the next installer drops a second copy beside the first.
AppId={{B3A7C2D4-1F5E-4A8B-9C6D-2E0F3A4B5C6D}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppPublisher}\{#AppName}
DefaultGroupName={#AppName}
OutputDir=dist
OutputBaseFilename=ERP_Setup
SetupIconFile=windows\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
; Without this an upgrade keeps the group name the previous install
; recorded, so renaming the product leaves a Start Menu folder still
; named after the old one.
UsePreviousGroup=no
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "Créer une icône sur le bureau"; GroupDescription: "Icônes supplémentaires:"

[Files]
Source: "{#ReleaseDir}\ERP.exe";                         DestDir: "{app}"; Flags: ignoreversion
Source: "{#ReleaseDir}\flutter_windows.dll";            DestDir: "{app}"; Flags: ignoreversion
Source: "{#ReleaseDir}\sqlite3.dll";                    DestDir: "{app}"; Flags: ignoreversion
Source: "{#ReleaseDir}\pdfium.dll";                     DestDir: "{app}"; Flags: ignoreversion
Source: "{#ReleaseDir}\printing_plugin.dll";            DestDir: "{app}"; Flags: ignoreversion
; Emitted by some Flutter versions and not others. The payload is
; listed file by file, so one that stops being generated fails the
; whole compile unless it is marked optional.
Source: "{#ReleaseDir}\native_assets.json";             DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "{#ReleaseDir}\data\*";                         DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "windows\runner\resources\app_icon.ico";        DestDir: "{app}"; DestName: "sm.ico"; Flags: ignoreversion

[InstallDelete]
; Upgrading an install made under the old name. The AppId is unchanged,
; so this lands in the folder that install already uses -- which on
; Windows is also where its database lives, and why the database
; filename was left alone. Only the old shell is swept up.
Type: files; Name: "{app}\socogen.exe"
Type: files; Name: "{app}\SM.exe"
Type: files; Name: "{app}\socogen.ico"
; Left behind by installs made when Flutter still emitted it. It
; records an absolute path from the build machine, so it is stale
; the moment it is copied to anyone else.
Type: files; Name: "{app}\native_assets.json"
Type: filesandordirs; Name: "{autoprograms}\SOCOGEN"
Type: filesandordirs; Name: "{autoprograms}\SM"
Type: files; Name: "{autodesktop}\SOCOGEN.lnk"
Type: files; Name: "{autodesktop}\SM.lnk"

[Icons]
Name: "{group}\{#AppName}";              Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\sm.ico"
Name: "{group}\Désinstaller {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}";        Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\sm.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Lancer {#AppName}"; Flags: nowait postinstall skipifsilent
