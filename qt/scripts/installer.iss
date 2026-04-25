; ============================================================
; MindTrace — Script de Instalador (Inno Setup 6)
; Para gerar o instalador: execute build_installer.bat
; ============================================================

#define AppName      "MindTrace"
#define AppVersion   "1.0.0"
#define AppPublisher "MemoryLab / UFRN"
#define AppExeName   "MindTrace.exe"
#define SourceDir    "..\..\build\Release"

[Setup]
AppId={{B3F2A1C4-7E8D-4F5A-9B2C-1D6E3A4F7C8B}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL=https://github.com/RodrigoOrvate/MindTrace
AppSupportURL=https://github.com/RodrigoOrvate/MindTrace/issues
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
AllowNoIcons=no
OutputDir=..\..\installer
OutputBaseFilename=MindTrace_Setup_{#AppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}
ShowLanguageDialog=no

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "english";             MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Criar atalho na {cm:DesktopFolder}"; GroupDescription: "Atalhos adicionais:"

[Files]
; Executável principal
Source: "{#SourceDir}\{#AppExeName}"; DestDir: "{app}"; Flags: ignoreversion

; Modelo ONNX de pose (obrigatório para tracking)
Source: "{#SourceDir}\Network-MemoryLab-v2.onnx"; DestDir: "{app}"; Flags: ignoreversion

; ONNX Runtime (motor de inferência)
Source: "{#SourceDir}\onnxruntime.dll";                  DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\onnxruntime_providers_shared.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\DirectML.dll";                     DestDir: "{app}"; Flags: ignoreversion

; Qt 6 — bibliotecas principais
Source: "{#SourceDir}\Qt6Core.dll";                       DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6Gui.dll";                        DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6Widgets.dll";                    DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6Network.dll";                    DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6OpenGL.dll";                     DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6Qml.dll";                        DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6QmlCore.dll";                    DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6QmlMeta.dll";                    DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6QmlModels.dll";                  DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6QmlWorkerScript.dll";            DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6Quick.dll";                      DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6Quick3DUtils.dll";               DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6QuickControls2.dll";             DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6QuickControls2Basic.dll";        DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6QuickControls2BasicStyleImpl.dll";        DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6QuickControls2FluentWinUI3StyleImpl.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6QuickControls2Fusion.dll";                DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6QuickControls2FusionStyleImpl.dll";       DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6QuickControls2Imagine.dll";               DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6QuickControls2ImagineStyleImpl.dll";      DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6QuickControls2Impl.dll";                  DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6QuickControls2Material.dll";              DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6QuickControls2MaterialStyleImpl.dll";     DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6QuickControls2Universal.dll";             DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6QuickControls2UniversalStyleImpl.dll";    DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6QuickControls2WindowsStyleImpl.dll";      DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6QuickDialogs2.dll";              DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6QuickDialogs2QuickImpl.dll";     DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6QuickDialogs2Utils.dll";         DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6QuickEffects.dll";               DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6QuickLayouts.dll";               DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6QuickShapes.dll";                DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6QuickTemplates2.dll";            DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6Multimedia.dll";                 DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6MultimediaQuick.dll";            DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6Svg.dll";                        DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\Qt6LabsFolderListModel.dll";        DestDir: "{app}"; Flags: ignoreversion

; FFmpeg (para exportação de clips B-SOiD)
Source: "{#SourceDir}\avcodec-61.dll";  DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\avformat-61.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\avutil-59.dll";   DestDir: "{app}"; Flags: ignoreversion

; DirectX / compiladores de shader
Source: "{#SourceDir}\d3dcompiler_47.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\dxcompiler.dll";     DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\dxil.dll";           DestDir: "{app}"; Flags: ignoreversion

; ICU (internacionalização Qt)
Source: "{#SourceDir}\icuuc.dll"; DestDir: "{app}"; Flags: ignoreversion

; OpenGL software renderer (fallback sem GPU dedicada)
Source: "{#SourceDir}\opengl32sw.dll"; DestDir: "{app}"; Flags: ignoreversion

; Subpastas Qt (plugins e QML)
Source: "{#SourceDir}\platforms\*";          DestDir: "{app}\platforms";          Flags: ignoreversion recursesubdirs
Source: "{#SourceDir}\imageformats\*";       DestDir: "{app}\imageformats";       Flags: ignoreversion recursesubdirs
Source: "{#SourceDir}\iconengines\*";        DestDir: "{app}\iconengines";        Flags: ignoreversion recursesubdirs
Source: "{#SourceDir}\multimedia\*";         DestDir: "{app}\multimedia";         Flags: ignoreversion recursesubdirs
Source: "{#SourceDir}\networkinformation\*"; DestDir: "{app}\networkinformation"; Flags: ignoreversion recursesubdirs
Source: "{#SourceDir}\styles\*";             DestDir: "{app}\styles";             Flags: ignoreversion recursesubdirs
Source: "{#SourceDir}\generic\*";            DestDir: "{app}\generic";            Flags: ignoreversion recursesubdirs
Source: "{#SourceDir}\qmltooling\*";         DestDir: "{app}\qmltooling";         Flags: ignoreversion recursesubdirs
Source: "{#SourceDir}\qml\*";               DestDir: "{app}\qml";               Flags: ignoreversion recursesubdirs

[Icons]
; Menu Iniciar
Name: "{group}\{#AppName}";           Filename: "{app}\{#AppExeName}"
Name: "{group}\Desinstalar MindTrace"; Filename: "{uninstallexe}"

; Área de trabalho (opcional)
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; \
    Description: "Iniciar {#AppName} agora"; \
    Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Remove o log gerado pelo app ao desinstalar
Type: files; Name: "{app}\mindtrace.log"
; Remove pasta de configuração do app se estiver vazia
Type: dirifempty; Name: "{app}"
