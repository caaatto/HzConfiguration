#Requires -Version 5.1
<#
.SYNOPSIS
    Führt MonitorFix aus und bereinigt danach automatisch

.DESCRIPTION
    1. Führt Run-All.ps1 aus
    2. Schließt die PowerShell-Session
    3. Startet neue Session die aufräumt
    4. Löscht C:\Local\MonitorFix

.PARAMETER Hz
    Zielfrequenz in Hertz (Standard: 60)

.PARAMETER KeepFiles
    Dateien NICHT löschen nach Ausführung

.EXAMPLE
    .\Run-And-Cleanup.ps1 60
    .\Run-And-Cleanup.ps1 -Hz 144
    .\Run-And-Cleanup.ps1 60 -KeepFiles
#>

param(
    [Parameter(Mandatory=$false)]
    [int]$Hz = 60,

    [switch]$KeepFiles = $false
)

$targetPath = "C:\Local\MonitorFix\deploy"
$scriptPath = Join-Path $targetPath "Run-All.ps1"

Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "  MonitorFix: Run & Cleanup" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Zielfrequenz: $Hz Hz" -ForegroundColor White
Write-Host "Aufräumen: $(if ($KeepFiles) { 'NEIN' } else { 'JA' })" -ForegroundColor White
Write-Host ""

# Prüfen ob Script existiert
if (-not (Test-Path $scriptPath)) {
    Write-Host "FEHLER: Script nicht gefunden!" -ForegroundColor Red
    Write-Host "Erwartet: $scriptPath" -ForegroundColor Yellow
    exit 1
}

# Schritt 1: Run-All ausführen
Write-Host "--- Schritt 1: Ausführung ---" -ForegroundColor Cyan
Write-Host ""

try {
    & $scriptPath -Hz $Hz
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        Write-Host ""
        Write-Host "FEHLER: Run-All.ps1 fehlgeschlagen (Exit Code: $exitCode)" -ForegroundColor Red
        Write-Host "Cleanup wird übersprungen." -ForegroundColor Yellow
        exit $exitCode
    }

    Write-Host ""
    Write-Host "✓ Ausführung erfolgreich!" -ForegroundColor Green

} catch {
    Write-Host ""
    Write-Host "FEHLER: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Cleanup wird übersprungen." -ForegroundColor Yellow
    exit 1
}

# Schritt 2: Cleanup
if (-not $KeepFiles) {
    Write-Host ""
    Write-Host "--- Schritt 2: Cleanup ---" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Starte Cleanup in separater Session..." -ForegroundColor Yellow
    Write-Host "(Diese Session wird geschlossen, damit die DLL freigegeben wird)" -ForegroundColor Gray
    Write-Host ""

    # Cleanup-Script als String
    $cleanupScript = @'
Start-Sleep -Seconds 2

$targetPath = "C:\Local\MonitorFix"

Write-Host ""
Write-Host "=== Cleanup ===" -ForegroundColor Cyan
Write-Host "Lösche: $targetPath" -ForegroundColor White
Write-Host ""

try {
    Remove-Item -Path $targetPath -Recurse -Force -ErrorAction Stop
    Write-Host "✓ Erfolgreich gelöscht!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Drücke eine Taste zum Beenden..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

} catch {
    Write-Host "✗ Fehler: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Manuelle Löschung erforderlich:" -ForegroundColor Yellow
    Write-Host "  Remove-Item -Path '$targetPath' -Recurse -Force" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Oder Löschung beim Neustart planen:" -ForegroundColor Yellow
    Write-Host "  .\Cleanup-OnReboot.ps1" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Drücke eine Taste zum Beenden..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
'@

    # Starte Cleanup in neuer PowerShell-Session
    Start-Process powershell -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $cleanupScript

    Write-Host "Cleanup gestartet in neuer Session." -ForegroundColor Green
    Write-Host "Diese Session wird jetzt geschlossen..." -ForegroundColor Gray
    Start-Sleep -Seconds 2

    exit 0
} else {
    Write-Host ""
    Write-Host "Cleanup übersprungen (-KeepFiles)." -ForegroundColor Yellow
    exit 0
}
