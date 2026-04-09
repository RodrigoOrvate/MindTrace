@echo off
cd /d "%~dp0.."

:: ── Limpeza Automática da pasta build ────────────────────────
echo [INFO] Limpando a pasta build antiga...
if exist "build" rmdir /s /q "build"

:: ============================================================
:: build.bat — Compila e executa o MindTrace (Qt 6.11 + CMake)
:: ============================================================
::
:: PRÉ-REQUISITOS (instale uma vez):
::   1. Qt 6.11.0  — https://www.qt.io/offline-installers
::      Componente: "Qt 6.11.0 > MSVC 2022 64-bit"
::      (QtQuick.Effects está incluso — qt5compat NÃO é necessário)
::   2. CMake 3.25+  — https://cmake.org/download/
::   3. Visual Studio 2022 ou superior (qualquer edição)
::
:: GPU — coloque o SDK na raiz como onnxruntime_sdk/ (ver README.md Seção 2):
::   NVIDIA CUDA  → onnxruntime-win-x64-gpu-1.24.4  renomeado para onnxruntime_sdk/
::   AMD/Intel    → onnxruntime-win-x64-1.24.4       renomeado para onnxruntime_sdk/
::
:: CONFIGURAÇÃO — edite apenas esta linha:
set QT_DIR=C:\Qt\6.11.0\msvc2022_64

:: ── Valida Qt ────────────────────────────────────────────────
if not exist "%QT_DIR%\lib\cmake\Qt6\Qt6Config.cmake" (
    echo.
    echo [ERRO] Qt 6 nao encontrado em: %QT_DIR%
    echo        Edite a variavel QT_DIR neste script.
    echo        Instale Qt 6.11.0 pelo instalador oficial: https://www.qt.io/offline-installers
    echo.
    pause & exit /b 1
)

:: ── Detecta o Visual Studio via vswhere ──────────────────────
::    vswhere.exe fica sempre no mesmo lugar desde o VS 2019.
::    Funciona com VS 2019, 2022 e versoes futuras.
set VSWHERE="%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"

if not exist %VSWHERE% (
    echo [ERRO] vswhere.exe nao encontrado.
    echo        Instale o Visual Studio 2022.
    pause & exit /b 1
)

:: Pega o caminho de instalacao do VS mais recente disponivel
for /f "usebackq tokens=*" %%i in (
    `%VSWHERE% -latest -property installationPath`
) do set VS_PATH=%%i

if "%VS_PATH%"=="" (
    echo [ERRO] Nenhuma instalacao do Visual Studio encontrada.
    pause & exit /b 1
)

set VCVARS="%VS_PATH%\VC\Auxiliary\Build\vcvars64.bat"
if not exist %VCVARS% (
    echo [ERRO] vcvars64.bat nao encontrado em: %VS_PATH%
    pause & exit /b 1
)

echo [OK] Visual Studio encontrado em: %VS_PATH%

:: Ativa o ambiente MSVC (VS 2022, toolset 14.4+)
call %VCVARS%

:: ── Cria a pasta de build ─────────────────────────────────────
if not exist build mkdir build

:: ── Configura com CMake ───────────────────────────────────────
echo.
echo [1/3] Configurando CMake...
cmake -S . -B build ^
    -G "NMake Makefiles" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_PREFIX_PATH="%QT_DIR%"

if errorlevel 1 (
    echo [ERRO] Falha na configuracao do CMake.
    pause & exit /b 1
)

:: ── Compila ───────────────────────────────────────────────────
echo.
echo [2/3] Compilando...
cmake --build build --config Release --parallel

if errorlevel 1 (
    echo [ERRO] Falha na compilacao.
    pause & exit /b 1
)

:: ── Copia DLLs do Qt ─────────────────────────────────────────
echo.
echo [3/3] Copiando DLLs do Qt...
set EXE=build\MindTrace.exe

"%QT_DIR%\bin\windeployqt.exe" --qmldir qml --release "%EXE%"

:: ── Copia ONNX Runtime DLLs (motor nativo C++) ───────────────
echo.
set ONNX_SDK=..\onnxruntime_sdk
if not exist "%ONNX_SDK%\lib\onnxruntime.dll" (
    echo [ERRO] ONNX Runtime SDK nao encontrado em: %ONNX_SDK%\lib\
    echo        Baixe o pacote adequado para sua GPU (ver README.md Secao 2^)
    echo        e renomeie a pasta extraida para 'onnxruntime_sdk' na raiz do projeto.
    pause & exit /b 1
)
for %%D in (onnxruntime.dll onnxruntime_providers_shared.dll onnxruntime_providers_cuda.dll onnxruntime_providers_tensorrt.dll) do (
    if exist "%ONNX_SDK%\lib\%%D" (
        copy /y "%ONNX_SDK%\lib\%%D" "build\" >nul
        echo [OK] ONNX DLL copiada: %%D
    )
)
echo [INFO] Prioridade GPU: CUDA (NVIDIA) -^> DirectML (AMD/Intel) -^> CPU

:: Copia modelo ONNX para build\
for %%M in (Network-MemoryLab-v2.onnx pose_cfg.yaml) do (
    if exist "%%M" (
        copy /y "%%M" "build\" >nul
        echo [OK] Modelo copiado: %%M
    )
)

:: ── Executa ───────────────────────────────────────────────────
echo.
echo Iniciando MindTrace...
"%EXE%"
