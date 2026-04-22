param(
  [string]$TaskName = "AnimalLifecycleBackupHourly",
  [string]$ProjectRoot = "C:\MindTrace - Copia\animal-lifecycle-platform\backend"
)

$ErrorActionPreference = "Stop"

$scriptPath = "C:\MindTrace - Copia\animal-lifecycle-platform\ops\run_backup.ps1"
if (!(Test-Path $scriptPath)) {
  throw "Script de backup não encontrado: $scriptPath"
}

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$scriptPath`" -ProjectRoot `"$ProjectRoot`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration ([TimeSpan]::MaxValue)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Description "Backup horário do banco Animal Lifecycle para pasta sincronizada (Drive)." -Force
Write-Host "Tarefa '$TaskName' registrada com sucesso."
