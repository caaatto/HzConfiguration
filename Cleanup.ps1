#Requires -Version 5.1
<#
.SYNOPSIS
    Bereinigt MonitorFix-Installation nach erfolgreicher Ausführung

.DESCRIPTION
    Löscht das komplette Verzeichnis C:\Local\MonitorFix nach einer Wartezeit.
    Kann auch sofort löschen wenn keine PowerShell-Prozesse die DLL verwenden.

.PARAMETER WaitSeconds
    Wartezeit in Sekunden bevor gelöscht wird (Standard: 5)

.PARAMETER Force
    Sofort löschen ohne Warnung

.EXAMPLE
    .\Cleanup.ps1
    .\Cleanup.ps1 -Force
    .\Cleanup.ps1 -WaitSeconds 10
#>

param(
    [int]$WaitSeconds = 5,
    [switch]$Force = $false
)

$targetPath = "C:\Local\MonitorFix"

Write-Host "=== MonitorFix Cleanup ===" -ForegroundColor Cyan
Write-Host ""

# Prüfen ob Verzeichnis existiert
if (-not (Test-Path $targetPath)) {
    Write-Host "Verzeichnis existiert nicht: $targetPath" -ForegroundColor Yellow
    exit 0
}

# Warnung anzeigen
if (-not $Force) {
    Write-Host "ACHTUNG: Folgendes Verzeichnis wird gelöscht:" -ForegroundColor Yellow
    Write-Host "  $targetPath" -ForegroundColor White
    Write-Host ""

    $size = (Get-ChildItem -Path $targetPath -Recurse -File | Measure-Object -Property Length -Sum).Sum
    $sizeKB = [math]::Round($size / 1KB, 2)
    Write-Host "Größe: $sizeKB KB" -ForegroundColor Gray
    Write-Host ""

    Write-Host "Warte $WaitSeconds Sekunden... (Strg+C zum Abbrechen)" -ForegroundColor Yellow
    Start-Sleep -Seconds $WaitSeconds
}

# Versuche zu löschen
Write-Host "Lösche $targetPath..." -ForegroundColor Cyan

try {
    Remove-Item -Path $targetPath -Recurse -Force -ErrorAction Stop
    Write-Host "✓ Erfolgreich gelöscht!" -ForegroundColor Green
    exit 0

} catch {
    Write-Host "✗ Fehler beim Löschen: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Mögliche Ursachen:" -ForegroundColor Yellow
    Write-Host "  - DLL ist noch in einer PowerShell-Session geladen" -ForegroundColor Gray
    Write-Host "  - Ein anderer Prozess verwendet die Dateien" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Lösungen:" -ForegroundColor Cyan
    Write-Host "  1. Schließe alle PowerShell-Fenster und führe Cleanup erneut aus" -ForegroundColor Gray
    Write-Host "  2. Verwende: .\Cleanup.ps1 -ScheduleOnReboot" -ForegroundColor Gray
    Write-Host "  3. Starte den PC neu, dann manuell löschen" -ForegroundColor Gray
    exit 1
}
