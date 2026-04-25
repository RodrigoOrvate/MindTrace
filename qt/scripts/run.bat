@echo off
:: Executa o MindTrace ja compilado, sem recompilar.

set SCRIPT_DIR=%~dp0
pushd "%SCRIPT_DIR%\.."

set EXE=..\build\Release\MindTrace.exe

if not exist "%EXE%" (
    echo [ERRO] Executavel nao encontrado. Execute build.bat primeiro.
    popd
    pause & exit /b 1
)

"%EXE%"
popd
