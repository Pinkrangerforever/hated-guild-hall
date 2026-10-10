# ============================================
# HATED Guild Hall - Daily Database Backups
# ============================================
# Purpose: Full backup of BOTH Supabase projects (staging + prod)
# Schedule: Windows Task Scheduler (see setup-daily-backups.ps1)
# Created: 2026-10-07  |  Rewritten: 2026-10-10
#
# Each run creates one folder: backups\YYYY-MM-DD_HHmmss\
#   staging_roles.sql   staging_schema.sql   staging_data.sql
#   prod_roles.sql      prod_schema.sql      prod_data.sql
#
# Restore order (into an empty project): roles -> schema -> data
#
# Uses --project-ref (not --linked) so it never depends on, or changes,
# which project this folder is linked to. Auth comes from `supabase login`.
# The Supabase CLI runs pg_dump inside Docker, so Docker must be running.

$ErrorActionPreference = "Continue"

$projectPath   = "C:\Users\Chuck\Documents\hated-guild-hall"
$backupRoot    = Join-Path $projectPath "backups"
$logFile       = Join-Path $backupRoot "backup-log.txt"
$retentionDays = 30
$dockerExe     = "C:\Program Files\Docker\Docker\Docker Desktop.exe"

$projects = [ordered]@{
    staging = "jucmmnmnbjrzmjrugggl"
    prod    = "dymlprrudprwyctjqqer"
}

# Minimum sizes + a string that must appear, so an empty/partial file counts as a failure
$checks = @{
    roles  = @{ minBytes = 100;    marker = "ROLE" }
    schema = @{ minBytes = 50000;  marker = 'CREATE TABLE IF NOT EXISTS "public"."profiles"' }
    data   = @{ minBytes = 100000; marker = 'INSERT INTO "public"."profiles"' }
}

function Write-Log {
    param([string]$message)
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $message"
    Write-Host $entry
    Add-Content -Path $logFile -Value $entry -Encoding utf8
}

function Ensure-Docker {
    docker info *> $null
    if ($LASTEXITCODE -eq 0) { return $true }

    Write-Log "Docker is not running - starting Docker Desktop..."
    if (-not (Test-Path $dockerExe)) {
        Write-Log "[FAIL] Docker Desktop not found at $dockerExe"
        return $false
    }
    Start-Process $dockerExe | Out-Null
    for ($i = 0; $i -lt 36; $i++) {   # wait up to 3 minutes
        Start-Sleep -Seconds 5
        docker info *> $null
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Docker is ready"
            return $true
        }
    }
    Write-Log "[FAIL] Docker did not start within 3 minutes"
    return $false
}

function Invoke-Dump {
    param([string]$envName, [string]$ref, [string]$kind, [string]$outDir)

    $file = Join-Path $outDir "$($envName)_$kind.sql"
    $cliArgs = @("db", "dump", "--project-ref", $ref, "--file", $file)
    if ($kind -eq "data")  { $cliArgs += "--data-only" }
    if ($kind -eq "roles") { $cliArgs += "--role-only" }

    for ($attempt = 1; $attempt -le 2; $attempt++) {
        if (Test-Path $file) { Remove-Item $file -Force }

        $output = & supabase @cliArgs 2>&1 | Out-String
        $exit = $LASTEXITCODE

        $problem = $null
        if ($exit -ne 0) {
            $problem = "supabase exited with code $exit"
        } elseif (-not (Test-Path $file)) {
            $problem = "file not created"
        } else {
            $size = (Get-Item $file).Length
            $rule = $checks[$kind]
            if ($size -lt $rule.minBytes) {
                $problem = "file too small ($size bytes, expected >= $($rule.minBytes))"
            } elseif (-not (Select-String -Path $file -SimpleMatch $rule.marker -Quiet)) {
                $problem = "file is missing expected content '$($rule.marker)'"
            }
        }

        if (-not $problem) {
            $mb = [math]::Round((Get-Item $file).Length / 1MB, 2)
            Write-Log "[OK] $envName $kind OK ($mb MB)"
            return $true
        }

        Write-Log "[WARN] $envName $kind attempt $attempt failed: $problem"
        $tail = ($output -split "`r?`n" | Where-Object { $_ -and $_ -notmatch "new version of Supabase CLI|recommend updating" } | Select-Object -Last 5) -join " | "
        if ($tail) { Write-Log "    CLI output: $tail" }
        if ($attempt -lt 2) { Start-Sleep -Seconds 15 }
    }

    Write-Log "[FAIL] $envName $kind FAILED after 2 attempts"
    return $false
}

# ---------------- Main ----------------
if (-not (Test-Path $backupRoot)) { New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null }

Write-Log "=========================================="
Write-Log "DAILY BACKUP START (staging + prod)"
Write-Log "=========================================="

$results = @()
$outDir = Join-Path $backupRoot (Get-Date -Format "yyyy-MM-dd_HHmmss")

if (Ensure-Docker) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    Push-Location $projectPath
    foreach ($envName in $projects.Keys) {
        foreach ($kind in @("roles", "schema", "data")) {
            $results += Invoke-Dump -envName $envName -ref $projects[$envName] -kind $kind -outDir $outDir
        }
    }
    Pop-Location
} else {
    $results += $false
}

# Clean up old backups: dated folders and any legacy loose .sql files
Write-Log "Cleaning up backups older than $retentionDays days..."
$cutoff = (Get-Date).AddDays(-$retentionDays)
Get-ChildItem -Path $backupRoot -Directory | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}_\d{6}$' -and $_.LastWriteTime -lt $cutoff } | ForEach-Object {
    Remove-Item -Path $_.FullName -Recurse -Force
    Write-Log "Deleted old backup folder: $($_.Name)"
}
Get-ChildItem -Path $backupRoot -Filter "*.sql" -File | Where-Object { $_.LastWriteTime -lt $cutoff } | ForEach-Object {
    Remove-Item -Path $_.FullName -Force
    Write-Log "Deleted old backup: $($_.Name)"
}

$failed = @($results | Where-Object { -not $_ }).Count
Write-Log "=========================================="
if ($failed -eq 0) {
    Write-Log "[OK] DAILY BACKUP COMPLETE - ALL 6 DUMPS SUCCESSFUL -> $outDir"
} else {
    Write-Log "[FAIL] DAILY BACKUP FINISHED WITH $failed FAILURE(S) - check log above"
}
Write-Log "=========================================="

if ($failed -gt 0) { exit 1 } else { exit 0 }
