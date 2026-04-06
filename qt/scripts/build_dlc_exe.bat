@echo off
:: ============================================================
:: build_dlc_exe.bat
:: Recompila dlc_processor.exe usando venv_lab38 (Python 3.8)
:: O exe gerado e compativel com Windows 7 (64-bit) e embute
:: Python 3.8 + TensorFlow 2.10 + OpenCV sem precisar de
:: Python instalado na maquina alvo.
:: ============================================================
cd /d "%~dp0"

set VENV38=venv_lab38
set PYINSTALLER=%VENV38%\Scripts\pyinstaller.exe
set SCRIPT=dlc_processor.py

:: Verifica venv38
if not exist "%PYINSTALLER%" (
    echo.
    echo [ERRO] venv_lab38 nao encontrado.
    echo        Execute primeiro: setup_python38.bat
    pause & exit /b 1
)

:: Verifica script
if not exist "%SCRIPT%" (
    echo [ERRO] %SCRIPT% nao encontrado nesta pasta.
    pause & exit /b 1
)

:: Limpeza
if exist "dist\dlc_processor.exe" del /q "dist\dlc_processor.exe"
if exist "build\dlc_processor" rmdir /s /q "build\dlc_processor"

echo.
echo [INFO] Compilando %SCRIPT% com PyInstaller 5.13 (Python 3.8)...
echo        Isso demora alguns minutos.
echo.

"%PYINSTALLER%" ^
    --onefile ^
    --console ^
    --name dlc_processor ^
    --hidden-import=onnxruntime ^
    --hidden-import=cv2 ^
    --hidden-import=numpy ^
    --noupx ^
    "%SCRIPT%"

if errorlevel 1 (
    echo.
    echo [ERRO] Falha na compilacao.
    pause & exit /b 1
)

echo.
echo [OK] Gerado: dist\dlc_processor.exe
for %%f in ("dist\dlc_processor.exe") do echo     Tamanho: %%~zf bytes

echo.
echo [DEPLOY] Copie dist\dlc_processor.exe para a pasta do MindTrace.exe no Windows 7.
echo          O MindTrace ira detectar automaticamente e usar esse exe.
echo.
pause
