; Script for ClipOCR-Pro (PL Suite App03)
; Standard Per-User installer for PL Suite applications (App01 ~ App10).

#ifndef MyAppVersion
#define MyAppVersion "1.6.0"
#endif

#define MyAppName "ClipOCR-Pro"
#define MyAppPublisher "KwangBeomPark"
#define MyAppURL "https://github.com/KwangBeomPark/01_ClipOCR-Pro"
#define MyAppExeName "ClipOCR-Pro.exe"

[Setup]
AppId={{5C88B084-2578-4D4B-A63E-C246990C05DC}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={localappdata}\Programs\ClipOCR
DefaultGroupName=ClipOCR
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=ClipOCR-Setup.v{#MyAppVersion}
SetupIconFile=..\assets\ClipOCR-Pro.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
CloseApplicationsFilter=ClipOCR-Pro.exe

[Languages]
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "startupicon"; Description: "Windows 시작 시 자동 실행 (Run at Windows startup)"; GroupDescription: "시작 옵션 (Startup):"

[Files]
; Main application executable
Source: "..\dist\ClipOCR-Pro.v{#MyAppVersion}.exe"; DestDir: "{app}"; DestName: "{#MyAppExeName}"; Flags: ignoreversion
; Optional OCR engine (included when full package is built)
Source: "..\dist\ocr\*"; DestDir: "{app}\ocr"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist

[Dirs]
; UserSetting directory preservation (never deleted on uninstall)
Name: "{app}\UserSetting"; Flags: uninsneveruninstall

[InstallDelete]
; Clean up legacy shortcuts from older portable runs before installing new shortcuts
Type: files; Name: "{userstartup}\ClipOCR-Pro.lnk"
Type: files; Name: "{userstartup}\ScreenClipTool.lnk"
Type: files; Name: "{userstartup}\App03_ClipOCR-Pro.lnk"
Type: files; Name: "{userdesktop}\ScreenClipTool.lnk"
Type: files; Name: "{userdesktop}\App03_ClipOCR-Pro.lnk"
Type: files; Name: "{userprograms}\ScreenClipTool.lnk"
Type: files; Name: "{userprograms}\ClipOCR-Pro.lnk"

[Registry]
; Clean up legacy Run registry keys
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "ScreenClipTool"; Flags: deletevalue uninsdeletevalue
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "ClipOCR-Pro"; Flags: deletevalue uninsdeletevalue
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "ClipOCR"; Flags: deletevalue uninsdeletevalue

[Icons]
Name: "{userprograms}\ClipOCR\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{userdesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{userstartup}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: startupicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
