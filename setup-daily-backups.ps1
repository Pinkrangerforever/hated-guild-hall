# ============================================
# SETUP: Windows Task Scheduler for Daily Backups
# ============================================
# Run this script ONCE to set up the scheduled task
# After setup, backups will run automatically every day at 2 AM

param(
    [string]$BackupTime = "02:00"  # Default: 2 AM daily
)

$taskName = "HATED-Guild-Hall-Daily-Backup"
$scriptPath = "C:\Users\Chuck\Documents\hated-guild-hall\scheduled-database-backups.ps1"
$logPath = "C:\Users\Chuck\Documents\hated-guild-hall\backups\backup-log.txt"

Write-Host "=========================================="
Write-Host "Setting up Daily Database Backups"
Write-Host "=========================================="
Write-Host ""

# Task uses RunLevel Highest, so registering it requires an elevated PowerShell
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: Run this from PowerShell opened with 'Run as administrator'" -ForegroundColor Red
    exit 1
}

# Check if script exists
if (-not (Test-Path $scriptPath)) {
    Write-Host "❌ ERROR: Backup script not found at $scriptPath" -ForegroundColor Red
    exit 1
}

# Create backup log directory
$backupDir = "C:\Users\Chuck\Documents\hated-guild-hall\backups"
if (-not (Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    Write-Host "✅ Created backups directory" -ForegroundColor Green
}

# Remove existing task if it exists
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Host "Removing existing task..."
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
}

# Create the scheduled task action
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`"" `
    -WorkingDirectory "C:\Users\Chuck\Documents\hated-guild-hall"

# Create the scheduled task trigger (daily at specified time)
$trigger = New-ScheduledTaskTrigger `
    -Daily `
    -At $BackupTime

# Create task settings
$settings = New-ScheduledTaskSettingsSet `
    -MultipleInstances IgnoreNew `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -WakeToRun `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1)

# Register the scheduled task
try {
    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Description "Daily backup of HATED Guild Hall Supabase databases (staging + prod: roles, schema, data)" `
        -RunLevel Highest `
        -Force `
        -ErrorAction Stop | Out-Null

    Write-Host ""
    Write-Host "✅ SUCCESS! Daily backup task created" -ForegroundColor Green
    Write-Host ""
    Write-Host "Task Details:" -ForegroundColor Cyan
    Write-Host "  • Task Name: $taskName"
    Write-Host "  • Runs at: $BackupTime every day"
    Write-Host "  • Script: $scriptPath"
    Write-Host "  • Log file: $logPath"
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Yellow
    Write-Host "  1. Backups will run automatically at $BackupTime"
    Write-Host "  2. Check $logPath for backup history"
    Write-Host "  3. Backups are saved to: $backupDir"
    Write-Host ""
    Write-Host "To change backup time, run:" -ForegroundColor Yellow
    Write-Host "  .\setup-daily-backups.ps1 -BackupTime '03:00'" -ForegroundColor Gray
    Write-Host ""
    Write-Host "To view/manage the task:" -ForegroundColor Yellow
    Write-Host "  taskschd.msc (search in Start menu)" -ForegroundColor Gray

} catch {
    Write-Host "❌ ERROR creating task: $_" -ForegroundColor Red
    exit 1
}
