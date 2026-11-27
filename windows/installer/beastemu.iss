; Build with tool/build_windows_installer.ps1 and Inno Setup 7.
#ifndef PayloadList
  #error Use tool/build_windows_installer.ps1 to validate the portable release first.
#endif

[Setup]
AppId={{04248C8D-1988-4CC3-A2EC-83D97B4A7A35}
AppName={#AppTitle}
AppPublisher=BeastEmu
AppCopyright=Copyright (c) 2026 Beast
AppVersion={#AppVersionText}
VersionInfoVersion={#NumericVersion}
VersionInfoTextVersion={#AppVersionText}
VersionInfoProductVersion={#NumericVersion}
VersionInfoProductTextVersion={#AppVersionText}
DefaultDirName={localappdata}\Programs\BeastEmu GBA Dev
DisableDirPage=yes
UsePreviousAppDir=no
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
SetupArchitecture=x64
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
MinVersion=10.0
SetupIconFile=..\runner\resources\setup_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
OutputDir={#Artifacts}
OutputBaseFilename={#AppTitle}-{#AppVersionText}-Windows-x64-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "ptbr"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "Criar atalho na Área de Trabalho"; Flags: unchecked

[Files]
#include PayloadList

[Icons]
Name: "{userprograms}\{#AppTitle}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; IconFilename: "{app}\icons\beastemu-dragon.ico"; IconIndex: 0
Name: "{userdesktop}\{#AppTitle}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; IconFilename: "{app}\icons\beastemu-dragon.ico"; IconIndex: 0; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; Description: "Abrir {#AppTitle}"; Flags: postinstall nowait skipifsilent

[Code]
function HasRuntime(Root: Integer): Boolean;
var
  Installed, Major, Minor, Build: Cardinal;
  Key: String;
begin
  Key := 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64';
  Result := RegQueryDWordValue(Root, Key, 'Installed', Installed) and (Installed = 1)
    and RegQueryDWordValue(Root, Key, 'Major', Major)
    and RegQueryDWordValue(Root, Key, 'Minor', Minor)
    and RegQueryDWordValue(Root, Key, 'Bld', Build)
    and ((Major > {#VcMajor}) or ((Major = {#VcMajor}) and
      ((Minor > {#VcMinor}) or ((Minor = {#VcMinor}) and (Build >= {#VcBuild})))));
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if CompareText(ExpandFileName(ExpandConstant('{app}')),
                 ExpandFileName(ExpandConstant('{localappdata}\Programs\BeastEmu GBA Dev'))) <> 0 then
    Result := 'Use a pasta de programas da sua conta para instalar o BeastEmu.'
  else if not (HasRuntime(HKLM64) or HasRuntime(HKLM32)) then
    Result := 'Instale o Microsoft Visual C++ v14 Redistributable x64, versão ' +
      '{#VcMajor}.{#VcMinor}.{#VcBuild} ou mais recente, e abra este instalador novamente.'
      + #13#10#13#10 + 'Download oficial da Microsoft: https://aka.ms/vc14/vc_redist.x64.exe';
end;
