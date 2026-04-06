# setup_python38.ps1
# =============================================================
# Instala Python 3.8.10 (última 3.8 com suporte Win 7 64-bit)
# e cria venv_lab38 com TF 2.10 + OpenCV + PyInstaller.
# Execute: powershell -ExecutionPolicy Bypass -File setup_python38.ps1
# =============================================================

$ErrorActionPreference = "Stop"
$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$py38Install = "C:\Python38"
$py38Exe     = "$py38Install\python.exe"
$venvDir     = "$scriptDir\venv_lab38"
$installer   = "$env:TEMP\python-3.8.10-amd64.exe"
$installerUrl = "https://www.python.org/ftp/python/3.8.10/python-3.8.10-amd64.exe"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " MindTrace — Setup Python 3.8 para Win7 (dlc_processor)" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

# ── 1. Verifica se Python 3.8 já está instalado ───────────────
if (Test-Path $py38Exe) {
    Write-Host "[OK] Python 3.8 já instalado em $py38Install" -ForegroundColor Green
} else {
    Write-Host "[1/4] Baixando Python 3.8.10 (64-bit)..." -ForegroundColor Yellow
    Write-Host "      De: $installerUrl"
    
    try {
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($installerUrl, $installer)
        Write-Host "[OK] Download concluído." -ForegroundColor Green
    } catch {
        Write-Host "[ERRO] Falha no download: $_" -ForegroundColor Red
        Write-Host "       Baixe manualmente de: $installerUrl" -ForegroundColor Yellow
        Write-Host "       E instale em: $py38Install"
        exit 1
    }
    
    Write-Host "[2/4] Instalando Python 3.8.10 silenciosamente em $py38Install ..." -ForegroundColor Yellow
    $proc = Start-Process -FilePath $installer -ArgumentList @(
        "/quiet",
        "InstallAllUsers=0",
        "TargetDir=$py38Install",
        "PrependPath=0",         # NÃO modifica o PATH global (preserva o 3.11)
        "Include_pip=1",
        "Include_launcher=0"
    ) -Wait -PassThru
    
    if ($proc.ExitCode -ne 0) {
        Write-Host "[ERRO] Instalador saiu com código $($proc.ExitCode)" -ForegroundColor Red
        exit 1
    }
    Write-Host "[OK] Python 3.8.10 instalado em $py38Install" -ForegroundColor Green
}

# ── 3. Cria venv_lab38 ────────────────────────────────────────
Write-Host ""
Write-Host "[3/4] Criando ambiente virtual venv_lab38 com Python 3.8..." -ForegroundColor Yellow

if (Test-Path $venvDir) {
    Write-Host "      venv_lab38 já existe — recriando..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $venvDir
}

& $py38Exe -m venv $venvDir
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERRO] Falha ao criar o venv." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] venv_lab38 criado." -ForegroundColor Green

# ── 4. Instala dependências ───────────────────────────────────
Write-Host ""
Write-Host "[4/4] Instalando dependências (TF 2.10, OpenCV, PyInstaller)..." -ForegroundColor Yellow
Write-Host "      Isso pode demorar alguns minutos..."

$pip = "$venvDir\Scripts\pip.exe"

# Atualiza pip primeiro
& $pip install --upgrade pip | Out-Null

# Instala pacotes compatíveis com Windows 7 + Python 3.8
$packages = @(
    "tensorflow==2.10.1",          # Última versão TF com suporte Win nativo (não-WSL)
    "opencv-python==4.8.1.78",     # OpenCV estável para Py3.8
    "numpy==1.23.5",               # Versão exigida pelo TF 2.10
    "pyinstaller==5.13.2"          # Última versão estável para Py3.8 → gera exe Win7-compat
)

foreach ($pkg in $packages) {
    Write-Host "      Instalando: $pkg" -ForegroundColor Gray
    & $pip install $pkg
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERRO] Falha ao instalar $pkg" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "======================================================" -ForegroundColor Green
Write-Host " [SUCESSO] Ambiente pronto!" -ForegroundColor Green
Write-Host "======================================================" -ForegroundColor Green
Write-Host ""
Write-Host " Próximo passo: execute" -ForegroundColor White
Write-Host "   .\build_dlc_exe.bat" -ForegroundColor Cyan
Write-Host " para gerar dlc_processor.exe compatível com Windows 7."
Write-Host ""
