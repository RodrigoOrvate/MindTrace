@echo off
cd /d "%~dp0.."

:: ============================================================
:: build_installer.bat — Gera MindTrace_Setup.exe com Inno Setup
:: Pré-requisito: executar build.bat antes para ter build\Release\
:: ============================================================

set ISCC="%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"

:: ── Verifica se o Inno Setup está instalado ──────────────────
if not exist %ISCC% (
    echo.
    echo [ERRO] Inno Setup 6 nao encontrado.
    echo.
    echo Baixe e instale gratuitamente em:
    echo   https://jrsoftware.org/isdl.php
    echo.
    echo Apos instalar, execute este script novamente.
    echo.
    pause & exit /b 1
)

:: ── Verifica se o build existe ────────────────────────────────
if not exist "..\build\Release\MindTrace.exe" (
    echo.
    echo [ERRO] MindTrace.exe nao encontrado em build\Release\.
    echo        Execute build.bat primeiro para compilar o projeto.
    echo.
    pause & exit /b 1
)

:: ── Cria pasta de saída ───────────────────────────────────────
if not exist "..\installer" mkdir "..\installer"

:: ── Gera o instalador ─────────────────────────────────────────
echo.
echo [INFO] Gerando instalador...
%ISCC% "scripts\installer.iss"

if errorlevel 1 (
    echo.
    echo [ERRO] Falha ao gerar o instalador.
    pause & exit /b 1
)

echo.
echo ==========================================
echo [SUCESSO] Instalador gerado com sucesso!
echo Local: installer\MindTrace_Setup_1.0.0.exe
echo ==========================================
echo.
pause
