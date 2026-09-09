; Inno Setup script — turns the built app into a single WebScripts-Setup.exe
;
;   ISCC.exe packaging\installer.iss /DAppVersion=0.1.0 /DSourceDir=dist\app
;
; SourceDir must contain the Flutter release output plus webscripts-backend.exe.

#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\dist\app"
#endif
#ifndef OutputDir
  #define OutputDir "..\dist"
#endif

#define AppName "WebScripts"
#define AppExeName "web_scripts.exe"
#define AppPublisher "WebScripts"

[Setup]
AppId={{7F1C1B90-3C4E-4E7B-9E4F-2A1D6C5B8A11}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=WebScripts-Setup-{#AppVersion}-x64
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; The app and its bundled backend are 64-bit only. "x64compatible" only
; exists from Inno Setup 6.3 on, so keep the old spelling for older ones.
#if VER >= EncodeVer(6,3,0)
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#else
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
#endif
PrivilegesRequiredOverridesAllowed=dialog
UninstallDisplayIcon={app}\{#AppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Scripts and the browser profile live in %LOCALAPPDATA%\WebScripts and are
; deliberately left in place, so a reinstall keeps the user's work.
Type: filesandordirs; Name: "{app}\data"
