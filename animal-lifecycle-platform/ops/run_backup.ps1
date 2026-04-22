param(
  [string]$ProjectRoot = "C:\MindTrace - Copia\animal-lifecycle-platform\backend"
)

$ErrorActionPreference = "Stop"

$python = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
if (!(Test-Path $python)) {
  throw "Python da venv não encontrado em $python"
}

if (-not $env:ANIMAL_DB_PATH) {
  $env:ANIMAL_DB_PATH = (Join-Path $ProjectRoot "animal_lifecycle.db")
}

if (-not $env:ANIMAL_BACKUP_DIR) {
  $env:ANIMAL_BACKUP_DIR = "$env:USERPROFILE\Google Drive\AnimalLifecycleBackups"
}

if (-not $env:ANIMAL_BACKUP_RETENTION_DAYS) {
  $env:ANIMAL_BACKUP_RETENTION_DAYS = "30"
}

& $python (Join-Path $ProjectRoot "scripts\backup_db.py")
