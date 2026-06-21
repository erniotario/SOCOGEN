#define AppName "SOCOGEN"
#define AppVersion "1.0.0"
#define AppPublisher "SHEMAB"
#define AppExeName "socogen.exe"
#define ReleaseDir "build\windows\x64\runner\Release"

[Setup]
AppId={{B3A7C2D4-1F5E-4A8B-9C6D-2E0F3A4B5C6D}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppPublisher}\{#AppName}
DefaultGroupName={#AppName}
OutputDir=dist
OutputBaseFilename=SOCOGEN_Setup
SetupIconFile=windows\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "Créer une icône sur le bureau"; GroupDescription: "Icônes supplémentaires:"

[Files]
Source: "{#ReleaseDir}\socogen.exe";                    DestDir: "{app}"; Flags: ignoreversion
Source: "{#ReleaseDir}\flutter_windows.dll";            DestDir: "{app}"; Flags: ignoreversion
Source: "{#ReleaseDir}\sqlite3.dll";                    DestDir: "{app}"; Flags: ignoreversion
Source: "{#ReleaseDir}\pdfium.dll";                     DestDir: "{app}"; Flags: ignoreversion
Source: "{#ReleaseDir}\printing_plugin.dll";            DestDir: "{app}"; Flags: ignoreversion
Source: "{#ReleaseDir}\native_assets.json";             DestDir: "{app}"; Flags: ignoreversion
Source: "{#ReleaseDir}\data\*";                         DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "windows\runner\resources\app_icon.ico";        DestDir: "{app}"; DestName: "socogen.ico"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}";              Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\socogen.ico"
Name: "{group}\Désinstaller {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}";        Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\socogen.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Lancer {#AppName}"; Flags: nowait postinstall skipifsilent
