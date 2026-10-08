; Mconnect Windows Installer - Inno Setup 6 Script
; Build with: "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\mconnect.iss

#define MyAppName "Mconnect"
#define MyAppVersion "1.5.0"
#define MyAppPublisher "Mconnect"
#define MyAppURL "https://github.com/Hjdd14/Mconnect-Music_connect"
#define MyAppExeName "mconnect.exe"
#define MyAppSourceDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{E7A2C4B1-5F8D-4A3E-9C6B-1D2F0E8A7B5C}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
; LicenseFile=..\LICENSE
OutputDir=..\build\windows\x64
OutputBaseFilename=Mconnect-Setup-{#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
SetupIconFile=app_icon.ico

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
; 简体中文：Inno Setup **不自带**中文翻译（官方只附带二十来种语言，中文是社区的非
; 官方翻译），所以硬引用 `ChineseSimplified.isl` 会让没放该文件的机器**编译直接
; 失败**。这里用 `#if FileExists(...)` 包住：放了就是双语向导，没放照样能编译。
;   下载：https://jrsoftware.org/files/istrans/  → ChineseSimplified.isl
;   放到：<Inno Setup 6 安装目录>\Languages\
#if FileExists(AddBackslash(CompilerPath) + "Languages\ChineseSimplified.isl")
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
#endif

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; 只保留这一条：`*` 已经包含 exe，再单列一次 exe 等于重复打包。
Source: "{#MyAppSourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
const
  { 官方「最新受支持的 Visual C++ 下载」页。用它而不是 aka.ms 的直链：直链文件会
    随 VS 版本更名，而这一页长期有效，并且让人能自己选 x64/x86。 }
  VCRedistPageUrl = 'https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist';

{ Flutter 的 Windows 产物链接 msvcp140.dll / vcruntime140.dll：缺运行库时 exe 会
  "双击没反应 / 立刻闪退"，用户完全看不出原因，只会以为软件坏了。

  只检查这两个 DLL 在不在，**不查注册表版本号**：版本号判断容易把"装了更新的运行
  库"误判成缺失，而 DLL 存在与否才是产物真正的依赖。

  The installer declares ArchitecturesInstallIn64BitMode=x64compatible, so it runs
  as a 64-bit process and the sys constant resolves to C:\Windows\System32, which is
  where the 64-bit DLLs live. Write it as "the sys constant" here rather than as a
  brace-enclosed literal: Inno's preprocessor scans braces even inside Pascal
  comments and rejects the script with "Syntax error" on that line. }
function VCRuntimeMissing(): Boolean;
begin
  Result := (not FileExists(ExpandConstant('{sys}\msvcp140.dll')))
         or (not FileExists(ExpandConstant('{sys}\vcruntime140.dll')));
end;

{ 打开运行库下载页。

  `ShellExec('open', Url, ...)` 是"交给系统默认处理器打开这个 URL"，等价于在资源
  管理器里双击链接；**不自己拼 `cmd /c start ...` 之类的命令行**，那样会踩空格、
  引号、中文路径的坑，也更容易被安全软件拦下来。

  为什么只给链接、不代装：VC++ 运行库本身需要管理员权限，而本安装程序是
  PrivilegesRequired=lowest，没有权限替用户装。 }
procedure OpenVCRedistPage();
var
  ErrorCode: Integer;
begin
  ShellExec('open', VCRedistPageUrl, '', '', SW_SHOWNORMAL, ewNoWait, ErrorCode);
end;

function InitializeSetup(): Boolean;
begin
  Result := True;
  if not VCRuntimeMissing() then
    exit;

  { 明确停一下、给可操作的下一步，而不是静默装完一个注定闪退的程序：用户看到
    "装完了但打不开"时，是无法自己找到原因的。 }
  if MsgBox('Mconnect 需要「Microsoft Visual C++ 2015-2022 可再发行组件 (x64)」，'
            + '当前系统没有检测到它。' + #13#10#13#10
            + '缺少它时程序启动后会立刻退出，而且没有任何提示。' + #13#10#13#10
            + '点「是」打开官方下载页；装好运行库后再运行本安装程序即可。'
            + #13#10#13#10
            + '点「否」继续安装（如果你确定运行库已装在别处）。',
            mbConfirmation, MB_YESNO) = IDYES then
    OpenVCRedistPage();
end;
