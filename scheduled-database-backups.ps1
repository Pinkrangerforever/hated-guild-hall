# ============================================
# HATED Guild Hall - Daily Database Backups
# ============================================
# Purpose: Automated backup of Supabase staging database
# Schedule: Windows Task Scheduler (runs daily at specified time)
# Created: 2026-10-07

# Log file for backup history
$logFile = "C:\Users\Chuck\Documents\hated-guild-hall\backups\backup-log.txt"

function Write-Log {
    param([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $message"
    Write-Host $logEntry
    Add-Content -Path $logFile -Value $logEntry
}

function New-Backup {
    param(
        [string]$backupType,
        [string]$description
    )

    try {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $projectPath = "C:\Users\Chuck\Documents\hated-guild-hall"

        Write-Log "Starting $backupType backup..."

        switch($backupType) {
            "full" {
                $fileName = "staging_full_with_data_$timestamp.sql"
                $filePath = Join-Path $projectPath "backups\$fileName"
                Push-Location $projectPath
                supabase db dump --linked --role postgres --file "backups\$fileName"
                Pop-Location
            }
            "schema" {
                $fileName = "staging_schema_$timestamp.sql"
                $filePath = Join-Path $projectPath "backups\$fileName"
                Push-Location $projectPath
                supabase db dump --linked --file "backups\$fileName"
                Pop-Location
            }
            "data" {
                $fileName = "staging_data_$timestamp.sql"
                $filePath = Join-Path $projectPath "backups\$fileName"
                Push-Location $projectPath
                supabase db dump --linked --data-only --file "backups\$fileName"
                Pop-Location
            }
        }

        if (Test-Path $filePath) {
            $fileSize = (Get-Item $filePath).Length / 1MB
            Write-Log "✅ $backupType backup complete: $fileName ($([math]::Round($fileSize, 2)) MB)"
            return $true
        } else {
            Write-Log "❌ $backupType backup FAILED: File not created"
            return $false
        }
    }
    catch {
        Write-Log "❌ ERROR during $backupType backup: $_"
        return $false
    }
}

# Main backup routine
Write-Log "=========================================="
Write-Log "DAILY BACKUP START"
Write-Log "=========================================="

$fullSuccess = New-Backup -backupType "full" -description "Full database (schema + data)"
$dataSuccess = New-Backup -backupType "data" -description "Data only (INSERT statements)"

# Clean up old backups (keep last 30 days)
Write-Log "Cleaning up backups older than 30 days..."
$backupPath = "C:\Users\Chuck\Documents\hated-guild-hall\backups"
$cutoffDate = (Get-Date).AddDays(-30)
Get-ChildItem -Path $backupPath -Filter "*.sql" | Where-Object { $_.LastWriteTime -lt $cutoffDate } | ForEach-Object {
    Remove-Item -Path $_.FullName
    Write-Log "Deleted old backup: $($_.Name)"
}

Write-Log "=========================================="
if ($fullSuccess -and $dataSuccess) {
    Write-Log "✅ DAILY BACKUP COMPLETE - ALL BACKUPS SUCCESSFUL"
} else {
    Write-Log "⚠️  DAILY BACKUP COMPLETE - SOME FAILURES (check log above)"
}
Write-Log "=========================================="
