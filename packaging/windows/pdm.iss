; Inno Setup 6 script for Ponta Download Manager (Windows EXE installer).
; Built by .github/workflows/release.yml (job build-windows).
;
; Local build (after `flutter build windows --release`, from the repo root):
;   iscc packaging/windows/pdm.iss
; The workflow overrides the version and the source dir:
;   iscc packaging/windows/pdm.iss /DAppVersion=0.1.0 /DSourceDir=<absolute path>
; All relative paths below resolve against this script's directory
; (packaging/windows/), so ../../ is the repo root.

#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\apps\desktop\build\windows\x64\runner\Release"
#endif

[Setup]
; Same GUID as the WiX UpgradeCode (packaging/windows/pdm.wxs): one app,
; one identity across both installers.
AppId={{6DF68F12-0032-4D3A-BB94-5CD8200181D2}
AppName=Ponta Download Manager
AppVersion={#AppVersion}
AppPublisher=Ponta
AppPublisherURL=https://github.com/ngotuananh101/ponta-download-manager
AppSupportURL=https://github.com/ngotuananh101/ponta-download-manager/issues
DefaultDirName={autopf}\Ponta Download Manager
DefaultGroupName=Ponta Download Manager
DisableProgramGroupPage=yes
; Per-machine install into Program Files, matching the MSI.
PrivilegesRequired=admin
OutputDir=..\..\dist
OutputBaseFilename=pdm-{#AppVersion}-windows-x64-setup
SetupIconFile=..\..\apps\desktop\assets\images\icon.ico
UninstallDisplayIcon={app}\pdm.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The whole Release bundle: pdm.exe, data/, lib/, bin/ (ffmpeg + yt-dlp,
; installed by the Windows CMakeLists bundle/bin rule), icudtl.dat.
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; pdm.exe already embeds its icon (windows/runner/resources/app_icon.ico
; via Runner.rc), so the shortcuts point at the exe directly.
Name: "{group}\Ponta Download Manager"; Filename: "{app}\pdm.exe"
Name: "{group}\{cm:UninstallProgram,Ponta Download Manager}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Ponta Download Manager"; Filename: "{app}\pdm.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\pdm.exe"; Description: "{cm:LaunchProgram,Ponta Download Manager}"; Flags: nowait postinstall skipifsilent
