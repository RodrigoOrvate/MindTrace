# setup_onnx.ps1
# This script downloads and sets up ONNX Runtime and DirectML dependencies for MindTrace.

$ErrorActionPreference = "Stop"

$Version = "1.24.4"
$BaseUrl = "https://github.com/microsoft/onnxruntime/releases/download/v$Version"

$Dependencies = @(
    @{ 
        Name = "onnxruntime-win-x64-$Version"; 
        Zip = "onnxruntime-win-x64-$Version.zip"; 
        Url = "$BaseUrl/onnxruntime-win-x64-$Version.zip" 
    },
    @{ 
        Name = "onnxruntime-win-x64-gpu-$Version"; 
        Zip = "onnxruntime-win-x64-gpu-$Version.zip"; 
        Url = "$BaseUrl/onnxruntime-win-x64-gpu-$Version.zip" 
    },
    @{ 
        Name = "onnxruntime-win-x64-directml-$Version"; # Intermediate name
        Zip = "onnxruntime-win-x64-directml-$Version.zip"; 
        Url = "$BaseUrl/onnxruntime-win-x64-directml-$Version.zip";
        Target = "directml_x64" # Final target name
    }
)

Write-Host "--- Inciando Configuração de Dependências ONNX/DirectML ---" -ForegroundColor Cyan

foreach ($dep in $Dependencies) {
    if ($dep.Target) {
        $destFolder = $dep.Target
    } else {
        $destFolder = $dep.Name
    }

    if (Test-Path $destFolder) {
        Write-Host "[INFO] A pasta '$destFolder' já existe. Pulando download." -ForegroundColor Yellow
        continue
    }

    Write-Host "[1/3] Baixando $($dep.Zip)..." -ForegroundColor Green
    Invoke-WebRequest -Uri $dep.Url -OutFile $dep.Zip

    Write-Host "[2/3] Extraindo $($dep.Zip)..." -ForegroundColor Green
    Expand-Archive -Path $dep.Zip -DestinationPath "temp_extract"

    # Handle the structure
    $extractedFolder = Get-ChildItem -Path "temp_extract" | Select-Object -First 1

    if ($dep.Target) {
        # Special case for directml_x64: flatten the structure (headers and lib in root)
        Write-Host "[3/3] Organizando para '$($dep.Target)'..." -ForegroundColor Green
        New-Item -ItemType Directory -Path $dep.Target -Force | Out-Null
        
        # Move DLLs from bin or lib
        Get-ChildItem -Path "$($extractedFolder.FullName)\lib\*.dll" -ErrorAction SilentlyContinue | Move-Item -Destination $dep.Target -Force
        Get-ChildItem -Path "$($extractedFolder.FullName)\bin\*.dll" -ErrorAction SilentlyContinue | Move-Item -Destination $dep.Target -Force
        
        # Move LIBs
        Get-ChildItem -Path "$($extractedFolder.FullName)\lib\*.lib" -ErrorAction SilentlyContinue | Move-Item -Destination $dep.Target -Force
        
        # Move Headers from include
        Get-ChildItem -Path "$($extractedFolder.FullName)\include\*.h" -ErrorAction SilentlyContinue | Move-Item -Destination $dep.Target -Force
    } else {
        # Standard case: move the whole extracted folder to the target name
        Write-Host "[3/3] Movendo para '$($dep.Name)'..." -ForegroundColor Green
        Move-Item -Path $extractedFolder.FullName -Destination $dep.Name -Force
    }

    # Cleanup
    Write-Host "Limpando arquivos temporários..." -ForegroundColor Gray
    Remove-Item -Path $dep.Zip -Force
    if (Test-Path "temp_extract") {
        Remove-Item -Path "temp_extract" -Recurse -Force
    }
}

# Cleanup extra loose files if they exist in root
foreach ($file in @("onnxruntime.zip", "onnxruntime.lib")) {
    if (Test-Path $file) {
        Write-Host "Removendo arquivo legário root: $file" -ForegroundColor Gray
        Remove-Item -Path $file -Force
    }
}

Write-Host "`n--- Configuração concluída com sucesso! ---" -ForegroundColor Cyan
Write-Host "Você pode agora rodar o script de build em 'qt/scripts/build.bat'."
