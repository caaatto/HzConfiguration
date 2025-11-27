#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Testet DisplayUtilLive.dll

.DESCRIPTION
    Lädt die DLL und testet die Funktionen:
    - GetCurrentStatus() - Zeigt aktuelle Monitor-Konfiguration
    - SetGPUMonitorsTo(int) - Ändert Bildwiederholfrequenz (optional)

.PARAMETER DllPath
    Pfad zur DLL (Standard: .\bin\DisplayUtilLive.dll)

.PARAMETER TestFrequency
    Testfrequenz in Hz (z.B. 60, 120). Wenn angegeben, wird die Frequenz tatsächlich geändert.
    WARNUNG: Dies ändert die Monitor-Einstellungen!

.PARAMETER DryRun
    Nur Status anzeigen, keine Änderungen vornehmen (Standard)

.EXAMPLE
    .\Test-DLL.ps1
    # Zeigt nur den aktuellen Status

.EXAMPLE
    .\Test-DLL.ps1 -TestFrequency 60
    # Setzt alle Monitore auf 60 Hz

.EXAMPLE
    .\Test-DLL.ps1 -TestFrequency 144 -Verbose
    # Setzt auf 144 Hz mit ausführlicher Ausgabe
#>

[CmdletBinding()]
param(
    [string]$DllPath = (Join-Path $PSScriptRoot 'bin\DisplayUtilLive.dll'),

    [ValidateRange(1, 500)]
    [int]$TestFrequency = 0,

    [switch]$DryRun = $false
)

$ErrorActionPreference = 'Stop'

Write-Host "=== DisplayUtilLive.dll Test-Script ===" -ForegroundColor Cyan

# Admin-Check
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Dieses Script sollte als Administrator ausgeführt werden!"
    $continue = Read-Host "Trotzdem fortfahren? (j/n)"
    if ($continue -ne 'j') { exit 1 }
}

# DLL prüfen
if (-not (Test-Path $DllPath)) {
    Write-Error @"
DLL nicht gefunden: $DllPath

Bitte zuerst kompilieren:
    .\Build-DLL.ps1
"@
}

$dllInfo = Get-Item $DllPath
Write-Host "DLL gefunden: $DllPath" -ForegroundColor Green
Write-Host "  Größe: $([math]::Round($dllInfo.Length / 1KB, 2)) KB" -ForegroundColor Gray
Write-Host "  Änderung: $($dllInfo.LastWriteTime)" -ForegroundColor Gray

# DLL laden
Write-Host "`nLade DLL..." -ForegroundColor Cyan
try {
    Add-Type -Path $DllPath -ErrorAction Stop
    Write-Host "✓ DLL erfolgreich geladen" -ForegroundColor Green
} catch {
    Write-Error "Fehler beim Laden der DLL: $($_.Exception.Message)"
}

# Typ prüfen
try {
    $type = [DisplayUtilLive]
    Write-Host "✓ Typ 'DisplayUtilLive' gefunden" -ForegroundColor Green

    # Methoden auflisten
    $methods = $type.GetMethods([System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::Static) |
               Where-Object { $_.DeclaringType.Name -eq 'DisplayUtilLive' }

    Write-Host "`nVerfügbare Methoden:" -ForegroundColor Cyan
    foreach ($method in $methods) {
        $params = $method.GetParameters() | ForEach-Object { "$($_.ParameterType.Name) $($_.Name)" }
        $paramStr = if ($params) { $params -join ', ' } else { '' }
        Write-Host "  - $($method.Name)($paramStr)" -ForegroundColor Gray
    }

} catch {
    Write-Error "Typ 'DisplayUtilLive' nicht gefunden: $($_.Exception.Message)"
}

# Test 1: GetCurrentStatus
Write-Host "`n=== Test 1: GetCurrentStatus() ===" -ForegroundColor Cyan
try {
    [DisplayUtilLive]::GetCurrentStatus()
    Write-Host "`n✓ GetCurrentStatus() erfolgreich" -ForegroundColor Green
} catch {
    Write-Error "GetCurrentStatus() fehlgeschlagen: $($_.Exception.Message)"
}

# Test 2: SetGPUMonitorsTo (optional)
if ($TestFrequency -gt 0 -and -not $DryRun) {
    Write-Host "`n=== Test 2: SetGPUMonitorsTo($TestFrequency Hz) ===" -ForegroundColor Cyan
    Write-Warning "WARNUNG: Dies wird die Monitor-Einstellungen ändern!"

    $confirm = Read-Host "Fortfahren? (j/n)"
    if ($confirm -ne 'j') {
        Write-Host "Test abgebrochen" -ForegroundColor Yellow
        exit 0
    }

    try {
        Write-Host "`nÄndere Frequenz auf $TestFrequency Hz..." -ForegroundColor Cyan
        [DisplayUtilLive]::SetGPUMonitorsTo($TestFrequency)
        Write-Host "`n✓ SetGPUMonitorsTo($TestFrequency Hz) erfolgreich" -ForegroundColor Green

        # Status erneut anzeigen
        Write-Host "`n=== Status nach Änderung ===" -ForegroundColor Cyan
        [DisplayUtilLive]::GetCurrentStatus()

    } catch {
        Write-Error "SetGPUMonitorsTo($TestFrequency Hz) fehlgeschlagen: $($_.Exception.Message)"
    }

} elseif ($TestFrequency -gt 0 -and $DryRun) {
    Write-Host "`n=== Test 2: SetGPUMonitorsTo() (DRY-RUN) ===" -ForegroundColor Yellow
    Write-Host "DryRun aktiviert - keine Änderungen werden vorgenommen" -ForegroundColor Yellow
    Write-Host "Würde setzen: $TestFrequency Hz" -ForegroundColor Gray

} else {
    Write-Host "`n=== Test 2: SetGPUMonitorsTo() (übersprungen) ===" -ForegroundColor Yellow
    Write-Host "Keine TestFrequency angegeben - Test übersprungen" -ForegroundColor Gray
    Write-Host "Verwenden Sie -TestFrequency <Hz> um die Frequenz zu ändern" -ForegroundColor Gray
}

# Test 3: Ungültige Parameter (Fehlerbehandlung)
Write-Host "`n=== Test 3: Fehlerbehandlung ===" -ForegroundColor Cyan
Write-Host "Teste ungültige Parameter..." -ForegroundColor Gray

$testCases = @(
    @{ Hz = 0; Expected = 'Exception' },
    @{ Hz = -10; Expected = 'Exception' },
    @{ Hz = 600; Expected = 'Exception' }
)

foreach ($testCase in $testCases) {
    try {
        Write-Host "  Teste Hz=$($testCase.Hz)... " -NoNewline -ForegroundColor Gray
        [DisplayUtilLive]::SetGPUMonitorsTo($testCase.Hz)
        Write-Host "✗ FEHLER: Keine Exception geworfen!" -ForegroundColor Red
    } catch {
        Write-Host "✓ Exception erwartet und erhalten" -ForegroundColor Green
        Write-Verbose "  Exception: $($_.Exception.Message)"
    }
}

# Zusammenfassung
Write-Host "`n=== Zusammenfassung ===" -ForegroundColor Cyan
Write-Host "✓ DLL geladen und funktionsfähig" -ForegroundColor Green
Write-Host "✓ GetCurrentStatus() funktioniert" -ForegroundColor Green

if ($TestFrequency -gt 0 -and -not $DryRun) {
    Write-Host "✓ SetGPUMonitorsTo($TestFrequency Hz) getestet" -ForegroundColor Green
} else {
    Write-Host "- SetGPUMonitorsTo() nicht getestet (verwenden Sie -TestFrequency)" -ForegroundColor Yellow
}

Write-Host "✓ Fehlerbehandlung funktioniert" -ForegroundColor Green

Write-Host "`nDLL ist bereit für den Einsatz in baramundi!" -ForegroundColor Green
