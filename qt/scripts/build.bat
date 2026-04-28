@echo off
cd /d "%~dp0.."
setlocal

:: ============================================================
:: build.bat — Setup + Compila + Executa MindTrace
:: ============================================================
::
:: Este script faz TUDO automaticamente (primeira vez pode levar 3+ minutos):
::   1. Verifica Qt 6.11.0
::   2. Verifica Visual Studio 2022+
::   3. [AUTOMÁTICO] Baixa ONNX Runtime SDK (se necessário)
::   4. Configura CMake
::   5. Compila
::   6. Copia DLLs necessárias
::   7. Executa MindTrace
::
:: PRÉ-REQUISITOS (instale uma vez — ver SETUP_VSCODE.md):
::   • Qt 6.11.0 em: C:\Qt\6.11.0\msvc2022_64
::   • Visual Studio 2022 ou superior
::   • CMake 3.25+
::
:: CONFIGURAÇÃO — edite apenas esta linha:
set QT_DIR=C:\Qt\6.11.0\msvc2022_64

set MODE=FULL
set GPU_OVERRIDE=

:parse_args
if "%~1"=="" goto args_done
if /i "%~1"=="--deps-only" (
    set MODE=DEPS_ONLY
    shift
    goto parse_args
)
if /i "%~1"=="--gpu" (
    if "%~2"=="" (
        echo [ERRO] Valor ausente para --gpu. Use DML ou CUDA.
        exit /b 1
    )
    set GPU_OVERRIDE=%~2
    shift
    shift
    goto parse_args
)
echo [ERRO] Argumento invalido: %~1
echo Uso: build.bat [--deps-only] [--gpu DML^|CUDA]
exit /b 1
:args_done

:: ── Valida Qt ────────────────────────────────────────────────
if not exist "%QT_DIR%\lib\cmake\Qt6\Qt6Config.cmake" (
    echo.
    echo ============================================================
    echo [ERRO] Qt 6 nao encontrado em: %QT_DIR%
    echo ============================================================
    echo.
    echo 1. Instale Qt 6.11.0 (offline installer):
    echo    https://www.qt.io/offline-installers
    echo.
    echo 2. Selecione: Qt 6.11.0 ^> MSVC 2022 64-bit
    echo.
    echo 3. OU edite QT_DIR neste script se instalou em outro local
    echo.
    echo Para guia completo de setup, leia: ..\SETUP_VSCODE.md
    echo.
    pause & exit /b 1
)

:: ── Detecta o Visual Studio via vswhere ──────────────────────
set VSWHERE="%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"

if not exist %VSWHERE% (
    echo [ERRO] vswhere.exe nao encontrado.
    echo        Instale o Visual Studio 2022.
    pause & exit /b 1
)

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

:: Ativa o ambiente MSVC (define VisualStudioVersion no ambiente)
call %VCVARS%

:: Determina generator pelo VisualStudioVersion definido pelo vcvars
set VS_GENERATOR=Visual Studio 17 2022
if "%VisualStudioVersion:~0,2%"=="18" set VS_GENERATOR=Visual Studio 18 2026

echo [OK] Visual Studio encontrado: %VS_GENERATOR%

:: ── Verifica SDK ONNX (Obrigatório para CMake) ───────────────
for %%i in ("%~dp0..\..\onnxruntime_sdk") do set "ONNX_SDK=%%~fi"

if exist "%ONNX_SDK%\include\onnxruntime_cxx_api.h" goto :SDK_OK

:SDK_MISSING
echo.
echo ============================================================
echo [PRIMEIRA VEZ] ONNX Runtime SDK nao encontrado
echo ============================================================
echo.
echo Este script vai baixar automaticamente. Qual sua GPU?
echo.
echo [1] AMD, Intel ou CPU (DirectML^) — RECOMENDADO
echo [2] NVIDIA ^(CUDA 11.x/12.x^)
echo [3] Cancelar
echo.
if defined GPU_OVERRIDE (
    if /i "%GPU_OVERRIDE%"=="DML" (
        set CHOICE=1
    ) else if /i "%GPU_OVERRIDE%"=="CUDA" (
        set CHOICE=2
    ) else (
        echo [ERRO] --gpu invalido: %GPU_OVERRIDE%. Use DML ou CUDA.
        exit /b 1
    )
    echo [INFO] GPU selecionada por argumento: %GPU_OVERRIDE%
) else (
    set /p CHOICE="Opcao [1-3]: "
)

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

if not exist "%ONNX_SDK%\include\onnxruntime_cxx_api.h" (
    echo [ERRO] O setup falhou ou nao foi concluido corretamente (arquivos ausentes^).
    pause & exit /b 1
)

:SDK_OK
if /i "%MODE%"=="DEPS_ONLY" (
    echo.
    echo ==========================================
    echo [SUCESSO] Dependencias ONNX prontas.
    echo Agora voce pode abrir o VSCode e usar CMake normalmente.
    echo ==========================================
    echo.
    exit /b 0
)
:: ── Configura com CMake ───────────────────────────────────────
echo.
if not exist "..\build\CMakeCache.txt" (
    echo [AVISO] Primeira compilacao detectada. Isso pode demorar alguns minutos.
    echo         Nas proximas vezes sera muito mais rapido.
    echo.
)
echo [1/3] Configurando CMake...
cmake -S . -B ..\build ^
    -G "%VS_GENERATOR%" -A x64 ^
    -DCMAKE_PREFIX_PATH="%QT_DIR%"

if errorlevel 1 (
    echo [ERRO] Falha na configuracao do CMake.
    pause & exit /b 1
)

:: ── Compila ───────────────────────────────────────────────────
echo.
echo [2/3] Compilando...
cmake --build ..\build --config Release --parallel

if errorlevel 1 (
    echo [ERRO] Falha na compilacao.
    pause & exit /b 1
)

:: ── Copia DLLs do Qt (apenas se ainda não existem) ──────────
echo.
set EXE=..\build\Release\MindTrace.exe

if not exist "..\build\Release\Qt6Core.dll" (
    echo [3/3] Copiando DLLs do Qt...
    "%QT_DIR%\bin\windeployqt.exe" --qmldir qml --release "%EXE%"
) else (
    echo [3/3] DLLs Qt ja presentes, pulando windeployqt.
)

:: ── Copia ONNX Runtime DLLs (apenas se ainda não existem) ───
echo.
if not exist "..\build\Release\onnxruntime.dll" (
    echo [INFO] Copiando binarios do ORT...
    for %%D in (onnxruntime.dll onnxruntime_providers_shared.dll DirectML.dll onnxruntime_providers_cuda.dll onnxruntime_providers_tensorrt.dll) do (
        if exist "%ONNX_SDK%\lib\%%D" (
            copy /y "%ONNX_SDK%\lib\%%D" "..\build\Release\" >nul
            echo [OK] DLL copiada: %%D
        )
    )
    echo [INFO] Prioridade GPU: CUDA ^(NVIDIA^) ^> DirectML ^(AMD/Intel^) ^> CPU
) else (
    echo [INFO] DLLs ORT ja presentes, pulando copia.
)

:: ── Copia script Python de exportação Excel ─────────────────
if exist "formatar_mindtrace.py" (
    copy /y "formatar_mindtrace.py" "..\build\Release\" >nul
    echo [OK] formatar_mindtrace.py copiado.
)

:: ── Copia modelo ONNX de pose ────────────────────────────────
echo [INFO] Coletando modelos...
if exist "Network-MemoryLab-v2.onnx" (
    copy /y "Network-MemoryLab-v2.onnx" "..\build\Release\" >nul
    if errorlevel 1 (
        echo [ERRO] Falha ao copiar Network-MemoryLab-v2.onnx.
    ) else (
        echo [OK] Modelo copiado: Network-MemoryLab-v2.onnx
    )
) else (
    echo [AVISO] Network-MemoryLab-v2.onnx nao encontrado na pasta qt/.
)

echo [4/4] Finalizando build...
if not exist "%EXE%" (
    echo [ERRO] Falha na geracao do executavel.
    pause & exit /b 1
)

echo.
echo ==========================================
echo [SUCESSO] Build concluido com sucesso!
echo Local: build\Release\MindTrace.exe
echo ==========================================
echo.
pause
"%EXE%"
