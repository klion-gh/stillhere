; Packages the Flutter Windows release build (stillhere.exe + its required
; DLLs and data/ folder) into a single self-contained installer. The raw
; build\windows\x64\runner\Release\stillhere.exe does NOT run on its own —
; it needs flutter_windows.dll, libwebrtc.dll, plugin DLLs, and data/
; sitting next to it. This installer carries all of that and unpacks it on
; the target machine, so the one file we publish (stillhere.exe, the
; installer itself) is fully self-contained.
;
; Build with: ISCC.exe client\windows\installer\stillhere.iss
; Output: dist\stillhere.exe

#define MyAppName "StillHere"
#define MyAppVersion "0.2.0"
#define MyAppPublisher "StillHere"
#define MyAppExeName "stillhere.exe"
#define SourceDir "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{9E6C9E60-9C7B-4C2C-8A2E-5C6B8E9F1A20}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\..\dist
OutputBaseFilename=stillhere
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
