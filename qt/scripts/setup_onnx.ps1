param (
    [Parameter(Mandatory=$false)]
    [ValidateSet('DML', 'CUDA')]
    [string]$GpuType = 'DML'
)

$ErrorActionPreference = 'Stop'

# Define caminhos
$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir = Join-Path $PSScriptRoot '..\..'
$SDKDir = Join-Path $RootDir 'onnxruntime_sdk'

$LibDir = Join-Path $SDKDir 'lib'
$IncDir = Join-Path $SDKDir 'include'

Write-Host '==========================================' -ForegroundColor Cyan
Write-Host '   MindTrace - Setup ONNX Runtime 1.24.4' -ForegroundColor Cyan
Write-Host '==========================================' -ForegroundColor Cyan
Write-Host ('[INFO] Modo selecionado: ' + $GpuType) -ForegroundColor White

# Criar diretorios
if (-not (Test-Path $LibDir)) { New-Item -ItemType Directory -Path $LibDir -Force | Out-Null }
if (-not (Test-Path $IncDir)) { New-Item -ItemType Directory -Path $IncDir -Force | Out-Null }

$TempFolder = Join-Path $PSScriptRoot 'temp_onnx'
if (Test-Path $TempFolder) { Remove-Item -Recurse -Force $TempFolder }
New-Item -ItemType Directory -Path $TempFolder | Out-Null

try {
    if ($GpuType -eq 'DML') {
        # URLs de pacotes NuGet (DML)
        $ORT_DML_URL = 'https://www.nuget.org/api/v2/package/Microsoft.ML.OnnxRuntime.DirectML/1.24.4'
        $DML_BASE_URL = 'https://www.nuget.org/api/v2/package/Microsoft.AI.DirectML/1.15.4'

        $Zip1 = Join-Path $TempFolder 'ort_dml.zip'
        $Zip2 = Join-Path $TempFolder 'dml_base.zip'

        Write-Host '[1/4] Baixando motor DirectML (NuGet)...' -NoNewline
        Invoke-WebRequest -Uri $ORT_DML_URL -OutFile $Zip1
        if (-not (Test-Path $Zip1) -or (Get-Item $Zip1).Length -lt 1000) { throw 'Download do ORT falhou.' }
        Write-Host ' [OK]' -ForegroundColor Green
        
        Write-Host '[2/4] Baixando biblioteca DirectML Base...' -NoNewline
        Invoke-WebRequest -Uri $DML_BASE_URL -OutFile $Zip2
        if (-not (Test-Path $Zip2) -or (Get-Item $Zip2).Length -lt 1000) { throw 'Download do DML falhou.' }
        Write-Host ' [OK]' -ForegroundColor Green

        Write-Host '[3/4] Extraindo motor e headers...' -NoNewline
        Expand-Archive -Path $Zip1 -DestinationPath (Join-Path $TempFolder 'ort_dml_ext') -Force
        Copy-Item -Path (Join-Path $TempFolder 'ort_dml_ext\runtimes\win-x64\native\*.dll') -Destination $LibDir -Force
        Copy-Item -Path (Join-Path $TempFolder 'ort_dml_ext\runtimes\win-x64\native\*.lib') -Destination $LibDir -Force
        Copy-Item -Path (Join-Path $TempFolder 'ort_dml_ext\build\native\include\*') -Destination $IncDir -Recurse -Force
        Write-Host ' [OK]' -ForegroundColor Green

        Write-Host '[4/4] Extraindo DirectML.dll...' -NoNewline
        Expand-Archive -Path $Zip2 -DestinationPath (Join-Path $TempFolder 'dml_base_ext') -Force
        Copy-Item -Path (Join-Path $TempFolder 'dml_base_ext\bin\x64-win\DirectML.dll') -Destination $LibDir -Force
        Write-Host ' [OK]' -ForegroundColor Green

        Write-Host ('      Arquivos prontos em: ' + $LibDir) -ForegroundColor Gray

    } else {
        # URL do pacote oficial no GitHub Release (CUDA)
        $CUDA_URL = 'https://github.com/microsoft/onnxruntime/releases/download/v1.24.4/onnxruntime-win-x64-gpu-1.24.4.zip'
        $ZipCUDA = Join-Path $TempFolder 'ort_cuda.zip'

        Write-Host '[1/2] Baixando pacote CUDA (NVIDIA)...' -NoNewline
        Invoke-WebRequest -Uri $CUDA_URL -OutFile $ZipCUDA
        if (-not (Test-Path $ZipCUDA) -or (Get-Item $ZipCUDA).Length -lt 1000) { throw 'Download do ORT CUDA falhou.' }
        Write-Host ' [OK]' -ForegroundColor Green

        Write-Host '[2/2] Extraindo e organizando...' -NoNewline
        Expand-Archive -Path $ZipCUDA -DestinationPath (Join-Path $TempFolder 'ort_cuda_ext') -Force
        $ExtractedFolder = Get-ChildItem -Path (Join-Path $TempFolder 'ort_cuda_ext') -Directory | Select-Object -First 1
        Copy-Item -Path (Join-Path $ExtractedFolder.FullName 'lib\*') -Destination $LibDir -Force
        Copy-Item -Path (Join-Path $ExtractedFolder.FullName 'include\*') -Destination $IncDir -Recurse -Force
        Write-Host ' [OK]' -ForegroundColor Green
    }

    Write-Host '------------------------------------------'
    Write-Host '[SUCCESS] Setup finalizado!' -ForegroundColor Green
    Write-Host ('[INFO] Local: ' + $SDKDir)
}
catch {
    Write-Host ''
    Write-Host ('[ERROR] Falha no setup: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
finally {
    # Limpeza (silenciosa para evitar erros se algum arquivo estiver bloqueado por antivirus)
    if (Test-Path $TempFolder) { Remove-Item -Recurse -Force $TempFolder -ErrorAction SilentlyContinue }
}
