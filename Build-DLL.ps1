#Requires -Version 5.1
<#
.SYNOPSIS
    Compiles DisplayUtilLive.cs to DisplayUtilLive.dll

.DESCRIPTION
    Automatically finds csc.exe (.NET Framework Compiler) and compiles the DLL.
    Supports multiple .NET Framework versions (4.7+).

.PARAMETER Configuration
    Debug or Release (default: Release)

.PARAMETER OutputPath
    Output path for the DLL (default: .\bin\)

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

Write-Host "=== DisplayUtilLive.dll Build Script ===" -ForegroundColor Cyan
Write-Host "Configuration: $Configuration" -ForegroundColor Gray

# Source and target files
$sourceFile = Join-Path $PSScriptRoot 'DisplayUtilLive.cs'
$outputDll = Join-Path $OutputPath 'DisplayUtilLive.dll'
$outputPdb = Join-Path $OutputPath 'DisplayUtilLive.pdb'

# Validation
if (-not (Test-Path $sourceFile)) {
    Write-Error "Source file not found: $sourceFile"
}

# Create output directory
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    Write-Host "Output directory created: $OutputPath" -ForegroundColor Green
}

# Find csc.exe (C# Compiler)
function Find-CSC {
    # Possible paths for csc.exe (prioritized by .NET Framework version)
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

    # Fallback: search via PATH
    $cscInPath = Get-Command csc.exe -ErrorAction SilentlyContinue
    if ($cscInPath) {
        return $cscInPath.Source
    }

    return $null
}

$cscPath = Find-CSC

if (-not $cscPath) {
    Write-Error @"
C# Compiler (csc.exe) not found!

Please install one of the following components:
1. .NET Framework 4.7+ SDK (recommended)
2. Visual Studio 2019/2022 (Community, Professional, or Enterprise)
3. Visual Studio Build Tools 2019/2022

Download: https://visualstudio.microsoft.com/downloads/
"@
}

Write-Host "C# Compiler found: $cscPath" -ForegroundColor Green

# Compiler parameters
$compilerArgs = @(
    '/target:library',              # Create DLL
    '/platform:anycpu',             # Any CPU architecture
    '/optimize+',                   # Enable optimizations
    "/out:`"$outputDll`"",          # Output file
    "`"$sourceFile`""               # Source file
)

# Debug-specific parameters
if ($Configuration -eq 'Debug') {
    $compilerArgs += '/debug:full'
    $compilerArgs += '/define:DEBUG'
} else {
    $compilerArgs += '/debug:pdbonly'
}

# Delete old files
if (Test-Path $outputDll) {
    Remove-Item $outputDll -Force
    Write-Host "Old DLL deleted" -ForegroundColor Yellow
}
if (Test-Path $outputPdb) {
    Remove-Item $outputPdb -Force
}

# Compile
Write-Host "`nCompiling..." -ForegroundColor Cyan
Write-Host "Command: csc $($compilerArgs -join ' ')" -ForegroundColor Gray

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
        Write-Host "`nCompiler output:" -ForegroundColor Red
        if ($stdout) { Write-Host $stdout }
        if ($stderr) { Write-Host $stderr -ForegroundColor Red }
        Write-Error "Compilation failed (ExitCode: $($process.ExitCode))"
    }

    # Show warnings
    if ($stdout -and $stdout.Trim()) {
        Write-Host "`nCompiler warnings:" -ForegroundColor Yellow
        Write-Host $stdout
    }

} catch {
    Write-Error "Error during compilation: $($_.Exception.Message)"
}

# Success message
if (Test-Path $outputDll) {
    $dllInfo = Get-Item $outputDll
    Write-Host "`n✓ Compilation successful!" -ForegroundColor Green
    Write-Host "  File: $outputDll" -ForegroundColor Gray
    Write-Host "  Size: $([math]::Round($dllInfo.Length / 1KB, 2)) KB" -ForegroundColor Gray
    Write-Host "  Created: $($dllInfo.LastWriteTime)" -ForegroundColor Gray

    # Load assembly info
    try {
        Add-Type -Path $outputDll -ErrorAction SilentlyContinue
        Write-Host "`n✓ DLL loaded successfully (test)" -ForegroundColor Green
    } catch {
        Write-Warning "Could not load DLL: $($_.Exception.Message)"
    }

    # Copy to C:\Local\MonitorFix\deploy\Files for portable deployment
    Write-Host "`nCopying DLL to C:\Local\MonitorFix\deploy\Files..." -ForegroundColor Cyan
    $deployPath = "C:\Local\MonitorFix\deploy\Files"
    $deployDll = Join-Path $deployPath "DisplayUtilLive.dll"

    try {
        if (-not (Test-Path $deployPath)) {
            New-Item -ItemType Directory -Path $deployPath -Force | Out-Null
            Write-Host "Directory created: $deployPath" -ForegroundColor Green
        }

        Copy-Item -Path $outputDll -Destination $deployDll -Force -ErrorAction Stop
        Write-Host "✓ DLL copied to: $deployDll" -ForegroundColor Green

        # Also copy PDB (if present)
        if (Test-Path $outputPdb) {
            Copy-Item -Path $outputPdb -Destination (Join-Path $deployPath "DisplayUtilLive.pdb") -Force -ErrorAction SilentlyContinue
        }

    } catch {
        Write-Warning "Error copying to C:\Local\MonitorFix\deploy\Files: $($_.Exception.Message)"
        Write-Warning "Administrator rights may be required."
    }

    Write-Host "`nNext steps:" -ForegroundColor Cyan
    Write-Host "  1. Test DLL: .\Test-DLL.ps1" -ForegroundColor Gray
    Write-Host "  2. Run Hertz script: .\Hertz.ps1 60" -ForegroundColor Gray
    Write-Host "  3. Copy to baramundi package (if needed)" -ForegroundColor Gray

} else {
    Write-Error "DLL was not created: $outputDll"
}
