@echo off
cd /d "%~dp0.."

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

:: ── Verifica SDK ONNX (Obrigatório para CMake) ───────────────
for %%i in ("%~dp0..\..\onnxruntime_sdk") do set "ONNX_SDK=%%~fi"

if exist "%ONNX_SDK%\include\onnxruntime_cxx_api.h" goto :SDK_OK

:SDK_MISSING
echo.
echo [AVISO] ONNX Runtime SDK nao encontrado em: %ONNX_SDK%
echo.
echo Gostaria de baixar e configurar as dependencias automaticamente agora?
echo [1] Sim, para GPU AMD ou Intel (DirectML^)
echo [2] Sim, para GPU NVIDIA ^(CUDA^)
echo [3] Nao, sair
echo.
set /p CHOICE="Opcao [1-3]: "

if "%CHOICE%"=="1" (
    powershell -ExecutionPolicy Bypass -File "%~dp0setup_onnx.ps1" -GpuType DML
) else if "%CHOICE%"=="2" (
    powershell -ExecutionPolicy Bypass -File "%~dp0setup_onnx.ps1" -GpuType CUDA
) else (
    echo [INFO] Por favor, instale o SDK manualmente conforme o README.md e tente novamente.
    pause & exit /b 1
)

if errorlevel 1 (
    echo.
    echo [ERRO] Ocorreu uma falha critica durante o setup das dependencias.
    echo        Verifique sua conexao com a internet e tente novamente.
    pause & exit /b 1
)

rem Verifica se funcionou apos o script
if not exist "%ONNX_SDK%\include\onnxruntime_cxx_api.h" (
    echo [ERRO] O setup falhou ou nao foi concluido corretamente (arquivos ausentes^).
    pause & exit /b 1
)

:SDK_OK
:: ── Configura com CMake ───────────────────────────────────────
echo.
if not exist "build\CMakeCache.txt" (
    echo [AVISO] Primeira compilacao detectada. Isso pode demorar alguns minutos.
    echo         Nas proximas vezes sera muito mais rapido.
    echo.
)
echo [1/3] Configurando CMake...
cmake -S . -B build ^
    -G "Ninja" ^
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

:: Copia DLLs necessárias para a pasta build
echo [INFO] Copiando binarios do ORT...
for %%D in (onnxruntime.dll onnxruntime_providers_shared.dll DirectML.dll onnxruntime_providers_cuda.dll onnxruntime_providers_tensorrt.dll) do (
    if exist "%ONNX_SDK%\lib\%%D" (
        copy /y "%ONNX_SDK%\lib\%%D" "build\" >nul
        echo [OK] DLL copiada: %%D
    )
)
echo [INFO] Prioridade GPU: CUDA (NVIDIA) -> DirectML (AMD/Intel) -> CPU

:: Copia modelo ONNX de pose para build\
echo [INFO] Coletando modelos...
if exist "Network-MemoryLab-v2.onnx" (
    echo [INFO] Copiando Network-MemoryLab-v2.onnx para a pasta build...
    copy /y "Network-MemoryLab-v2.onnx" "build\" >nul
    if errorlevel 1 (
        echo [ERRO] Falha ao copiar Network-MemoryLab-v2.onnx. Verifique permissoes ou espaco em disco.
    ) else (
        echo [OK] Modelo copiado: Network-MemoryLab-v2.onnx
    )
) else (
    echo [AVISO] Network-MemoryLab-v2.onnx nao encontrado na pasta qt/.
)
:: Nota: Behavior.onnx e carregado em runtime pelo usuario — nao e necessario no build.

echo [4/4] Finalizando build...
if not exist "build\MindTrace.exe" (
    echo [ERRO] Falha na geracao do executavel.
    pause & exit /b 1
)

echo.
echo ==========================================
echo [SUCESSO] Build concluido com sucesso!
echo Local: qt\build\MindTrace.exe
echo ==========================================
echo.
pause
"%EXE%"
