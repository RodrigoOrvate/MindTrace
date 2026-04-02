@echo off
cd /d "%~dp0"
:: ============================================================
:: build.bat — Compila e executa o MindTrace (Qt 5.12 + CMake)
:: ============================================================
::
:: PRÉ-REQUISITOS (instale uma vez):
::   1. Qt 5.12 LTS  — https://www.qt.io/offline-installers
::      Componente: "Qt 5.12.x > MSVC 2017 64-bit"
::   2. CMake 3.12+  — https://cmake.org/download/
::   3. Visual Studio 2017 ou superior (qualquer edição)
::
:: CONFIGURAÇÃO — edite apenas esta linha:
set QT_DIR=C:\Qt\Qt5.12.12\5.12.12\msvc2017_64

:: ── Valida Qt ────────────────────────────────────────────────
if not exist "%QT_DIR%\lib\cmake\Qt5\Qt5Config.cmake" (
    echo.
    echo [ERRO] Qt 5.12 nao encontrado em: %QT_DIR%
    echo        Edite a variavel QT_DIR neste script.
    echo.
    pause & exit /b 1
)

:: ── Detecta o Visual Studio via vswhere ──────────────────────
::    vswhere.exe fica sempre no mesmo lugar desde o VS 2017.
::    Funciona com VS 2017, 2019, 2022 e versoes futuras.
set VSWHERE="%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"

if not exist %VSWHERE% (
    echo [ERRO] vswhere.exe nao encontrado.
    echo        Instale o Visual Studio 2017 ou superior.
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

:: Ativa o ambiente MSVC (coloca cl.exe, nmake, etc. no PATH)
call %VCVARS% -vcvars_ver=14.1

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

:: ── Executa ───────────────────────────────────────────────────
echo.
echo Iniciando MindTrace...
"%EXE%"
