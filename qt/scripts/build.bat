@echo off
setlocal
cd /d "%~dp0.."
set "SCRIPT_DIR=%~dp0"

rem ============================================================
rem build.bat - Setup + Build + Run MindTrace
rem ============================================================

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
        echo [ERROR] Missing value for --gpu. Use DML or CUDA.
        exit /b 1
    )
    set GPU_OVERRIDE=%~2
    shift
    shift
    goto parse_args
)
echo [ERROR] Invalid argument: %~1
echo Usage: build.bat [--deps-only] [--gpu DML^|CUDA]
exit /b 1
:args_done

if not exist "%QT_DIR%\lib\cmake\Qt6\Qt6Config.cmake" (
    echo.
    echo ============================================================
    echo [ERROR] Qt 6 not found at: %QT_DIR%
    echo ============================================================
    echo Install Qt 6.11.0 MSVC 2022 64-bit or edit QT_DIR in this file.
    exit /b 1
)

for %%i in ("%~dp0..\..\onnxruntime_sdk") do set "ONNX_SDK=%%~fi"
if /i "%MODE%"=="DEPS_ONLY" goto ensure_sdk

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
    echo [ERROR] vswhere.exe not found. Install Visual Studio 2022.
    exit /b 1
)

set "VS_PATH="
for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -property installationPath`) do set "VS_PATH=%%i"

if "%VS_PATH%"=="" (
    echo [ERROR] No Visual Studio installation found.
    exit /b 1
)

set "VCVARS=%VS_PATH%\VC\Auxiliary\Build\vcvars64.bat"
if not exist "%VCVARS%" (
    echo [ERROR] vcvars64.bat not found at: %VS_PATH%
    exit /b 1
)

call "%VCVARS%"
set "VS_GENERATOR=Visual Studio 17 2022"
if "%VisualStudioVersion:~0,2%"=="18" set "VS_GENERATOR=Visual Studio 18 2026"

echo [OK] Visual Studio detected: %VS_GENERATOR%

:ensure_sdk
if exist "%ONNX_SDK%\include\onnxruntime_cxx_api.h" goto sdk_ok

echo.
echo ============================================================
echo [FIRST RUN] ONNX Runtime SDK not found
echo ============================================================
echo.
echo [1] DML (AMD/Intel/CPU) - recommended
echo [2] CUDA (NVIDIA)
echo [3] Cancel
echo.

if defined GPU_OVERRIDE (
    set CHOICE=
    if /i "%GPU_OVERRIDE%"=="DML" set CHOICE=1
    if /i "%GPU_OVERRIDE%"=="CUDA" set CHOICE=2
    if not defined CHOICE (
        echo [ERROR] Invalid --gpu value: %GPU_OVERRIDE%
        exit /b 1
    )
    echo [INFO] GPU selected by arg: %GPU_OVERRIDE%
) else (
    set /p CHOICE="Option [1-3]: "
)

if "%CHOICE%"=="1" (
    powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%setup_onnx.ps1" -GpuType DML
) else if "%CHOICE%"=="2" (
    powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%setup_onnx.ps1" -GpuType CUDA
) else (
    echo [INFO] Cancelled by user.
    exit /b 1
)

if errorlevel 1 (
    echo [ERROR] ONNX SDK setup failed. Check internet and try again.
    exit /b 1
)

if not exist "%ONNX_SDK%\include\onnxruntime_cxx_api.h" (
    echo [ERROR] ONNX SDK files are still missing after setup.
    exit /b 1
)

:sdk_ok
if /i "%MODE%"=="DEPS_ONLY" (
    echo.
    echo ==========================================
    echo [SUCCESS] ONNX dependencies are ready.
    echo ==========================================
    exit /b 0
)

echo.
if not exist "..\build\CMakeCache.txt" (
    echo [INFO] First build detected. This may take a few minutes.
    echo.
)

echo [1/4] Configuring CMake...
cmake -S . -B ..\build -G "%VS_GENERATOR%" -A x64 -DCMAKE_PREFIX_PATH="%QT_DIR%"
if errorlevel 1 (
    echo [ERROR] CMake configure failed.
    exit /b 1
)

echo [2/4] Building...
cmake --build ..\build --config Release --parallel
if errorlevel 1 (
    echo [ERROR] Build failed.
    exit /b 1
)

set "EXE=..\build\Release\MindTrace.exe"

echo [3/4] Deploying Qt runtime...
if not exist "..\build\Release\Qt6Core.dll" (
    "%QT_DIR%\bin\windeployqt.exe" --qmldir qml --release "%EXE%"
) else (
    echo [INFO] Qt DLLs already present. Skipping windeployqt.
)

echo [4/4] Copying ONNX runtime DLLs...
for %%D in (onnxruntime.dll onnxruntime_providers_shared.dll DirectML.dll onnxruntime_providers_cuda.dll onnxruntime_providers_tensorrt.dll) do (
    if exist "%ONNX_SDK%\lib\%%D" copy /y "%ONNX_SDK%\lib\%%D" "..\build\Release\" >nul
)

if exist "formatar_mindtrace.py" copy /y "formatar_mindtrace.py" "..\build\Release\" >nul
if exist "Network-MemoryLab-v2.onnx" copy /y "Network-MemoryLab-v2.onnx" "..\build\Release\" >nul

if not exist "%EXE%" (
    echo [ERROR] Executable not generated.
    exit /b 1
)

echo.
echo ==========================================
echo [SUCCESS] Build completed.
echo %EXE%
echo ==========================================
"%EXE%"
exit /b 0
