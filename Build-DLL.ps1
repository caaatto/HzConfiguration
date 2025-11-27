#Requires -Version 5.1
<#
.SYNOPSIS
    Kompiliert DisplayUtilLive.cs zu DisplayUtilLive.dll

.DESCRIPTION
    Findet automatisch csc.exe (.NET Framework Compiler) und kompiliert die DLL.
    Unterstützt mehrere .NET Framework-Versionen (4.7+).

.PARAMETER Configuration
    Debug oder Release (Standard: Release)

.PARAMETER OutputPath
    Ausgabepfad für die DLL (Standard: .\bin\)

.EXAMPLE
    .\Build-DLL.ps1
    .\Build-DLL.ps1 -Configuration Debug
#>

[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',

    [string]$OutputPath = (Join-Path $PSScriptRoot 'bin')
)

$ErrorActionPreference = 'Stop'

Write-Host "=== DisplayUtilLive.dll Build-Script ===" -ForegroundColor Cyan
Write-Host "Konfiguration: $Configuration" -ForegroundColor Gray

# Quell- und Zieldateien
$sourceFile = Join-Path $PSScriptRoot 'DisplayUtilLive.cs'
$outputDll = Join-Path $OutputPath 'DisplayUtilLive.dll'
$outputPdb = Join-Path $OutputPath 'DisplayUtilLive.pdb'

# Validierung
if (-not (Test-Path $sourceFile)) {
    Write-Error "Quelldatei nicht gefunden: $sourceFile"
}

# Ausgabeverzeichnis erstellen
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    Write-Host "Ausgabeverzeichnis erstellt: $OutputPath" -ForegroundColor Green
}

# csc.exe finden (C# Compiler)
function Find-CSC {
    # Mögliche Pfade für csc.exe (priorisiert nach .NET Framework Version)
    $possiblePaths = @(
        # .NET Framework 4.8
        "$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
        "$env:SystemRoot\Microsoft.NET\Framework\v4.0.30319\csc.exe",

        # Visual Studio Build Tools
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\Roslyn\csc.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin\Roslyn\csc.exe",

        # Visual Studio Community/Professional/Enterprise
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\Roslyn\csc.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\Roslyn\csc.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\Roslyn\csc.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\Roslyn\csc.exe"
    )

    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            return $path
        }
    }

    # Fallback: über PATH suchen
    $cscInPath = Get-Command csc.exe -ErrorAction SilentlyContinue
    if ($cscInPath) {
        return $cscInPath.Source
    }

    return $null
}

$cscPath = Find-CSC

if (-not $cscPath) {
    Write-Error @"
C# Compiler (csc.exe) nicht gefunden!

Bitte installieren Sie eine der folgenden Komponenten:
1. .NET Framework 4.7+ SDK (empfohlen)
2. Visual Studio 2019/2022 (Community, Professional, oder Enterprise)
3. Visual Studio Build Tools 2019/2022

Download: https://visualstudio.microsoft.com/downloads/
"@
}

Write-Host "C# Compiler gefunden: $cscPath" -ForegroundColor Green

# Compiler-Parameter
$compilerArgs = @(
    '/target:library',              # DLL erstellen
    '/platform:anycpu',             # Beliebige CPU-Architektur
    '/optimize+',                   # Optimierungen aktivieren
    "/out:`"$outputDll`"",          # Ausgabedatei
    "`"$sourceFile`""               # Quelldatei
)

# Debug-spezifische Parameter
if ($Configuration -eq 'Debug') {
    $compilerArgs += '/debug:full'
    $compilerArgs += '/define:DEBUG'
} else {
    $compilerArgs += '/debug:pdbonly'
}

# Alte Dateien löschen
if (Test-Path $outputDll) {
    Remove-Item $outputDll -Force
    Write-Host "Alte DLL gelöscht" -ForegroundColor Yellow
}
if (Test-Path $outputPdb) {
    Remove-Item $outputPdb -Force
}

# Kompilieren
Write-Host "`nKompiliere..." -ForegroundColor Cyan
Write-Host "Befehl: csc $($compilerArgs -join ' ')" -ForegroundColor Gray

try {
    $process = Start-Process -FilePath $cscPath `
                              -ArgumentList $compilerArgs `
                              -NoNewWindow `
                              -Wait `
                              -PassThru `
                              -RedirectStandardOutput (Join-Path $env:TEMP 'csc_stdout.txt') `
                              -RedirectStandardError (Join-Path $env:TEMP 'csc_stderr.txt')

    $stdout = Get-Content (Join-Path $env:TEMP 'csc_stdout.txt') -Raw -ErrorAction SilentlyContinue
    $stderr = Get-Content (Join-Path $env:TEMP 'csc_stderr.txt') -Raw -ErrorAction SilentlyContinue

    if ($process.ExitCode -ne 0) {
        Write-Host "`nCompiler-Ausgabe:" -ForegroundColor Red
        if ($stdout) { Write-Host $stdout }
        if ($stderr) { Write-Host $stderr -ForegroundColor Red }
        Write-Error "Kompilierung fehlgeschlagen (ExitCode: $($process.ExitCode))"
    }

    # Warnungen anzeigen
    if ($stdout -and $stdout.Trim()) {
        Write-Host "`nCompiler-Warnungen:" -ForegroundColor Yellow
        Write-Host $stdout
    }

} catch {
    Write-Error "Fehler beim Kompilieren: $($_.Exception.Message)"
}

# Erfolgsmeldung
if (Test-Path $outputDll) {
    $dllInfo = Get-Item $outputDll
    Write-Host "`n✓ Kompilierung erfolgreich!" -ForegroundColor Green
    Write-Host "  Datei: $outputDll" -ForegroundColor Gray
    Write-Host "  Größe: $([math]::Round($dllInfo.Length / 1KB, 2)) KB" -ForegroundColor Gray
    Write-Host "  Erstellt: $($dllInfo.LastWriteTime)" -ForegroundColor Gray

    # Assembly-Info auslesen
    try {
        Add-Type -Path $outputDll -ErrorAction SilentlyContinue
        Write-Host "`n✓ DLL erfolgreich geladen (Test)" -ForegroundColor Green
    } catch {
        Write-Warning "DLL konnte nicht geladen werden: $($_.Exception.Message)"
    }

    Write-Host "`nNächste Schritte:" -ForegroundColor Cyan
    Write-Host "  1. DLL testen: .\Test-DLL.ps1" -ForegroundColor Gray
    Write-Host "  2. In baramundi-Paket kopieren: Copy-Item '$outputDll' '...\baramundi\Files\bin\'" -ForegroundColor Gray

} else {
    Write-Error "DLL wurde nicht erstellt: $outputDll"
}
