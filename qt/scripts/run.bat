@echo off
:: Executa o MindTrace ja compilado, sem recompilar.

set EXE=build\Release\MindTrace.exe
if not exist "%EXE%" set EXE=build\MindTrace.exe

if not exist "%EXE%" (
    echo [ERRO] Executavel nao encontrado. Execute build.bat primeiro.
    pause & exit /b 1
)

"%EXE%"
