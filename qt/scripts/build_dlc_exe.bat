@echo off
:: ============================================================
:: build_dlc_exe.bat  [LEGACY — nao usado no pipeline C++ nativo]
:: Recompila dlc_processor.exe usando venv Python 3.12
:: Embute Python 3.12 + TensorFlow + OpenCV sem precisar de
:: Python instalado na maquina alvo. Serve apenas como
:: referencia/gold standard para validar o modelo ONNX.
:: ============================================================
cd /d "%~dp0"

:: Recrie o venv com Python 3.12: python -m venv venv && venv\Scripts\pip install onnxruntime opencv-python numpy pyinstaller tensorflow
set VENV38=venv
set PYINSTALLER=%VENV38%\Scripts\pyinstaller.exe
set SCRIPT=dlc_processor.py

:: Verifica venv38
if not exist "%PYINSTALLER%" (
    echo.
    echo [ERRO] venv nao encontrado.
    echo        Crie venv: python -m venv venv ^&^& venv\Scripts\pip install onnxruntime opencv-python numpy pyinstaller tensorflow
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
echo [INFO] Compilando %SCRIPT% com PyInstaller (Python 3.12)...
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
echo [DEPLOY] Copie dist\dlc_processor.exe para a pasta do MindTrace.exe se necessario.
echo          O MindTrace ira detectar automaticamente e usar esse exe.
echo.
pause
