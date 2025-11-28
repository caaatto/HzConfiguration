#Requires -Version 5.1
<#
.SYNOPSIS
    Changes monitor refresh rates using DisplayUtilLive.dll (baramundi Step 2)

.DESCRIPTION
    Loads DisplayUtilLive.dll and sets all monitors to the specified refresh rate.
    This is the main script that changes GPU settings.

    Portable: Uses relative paths to find DLL in multiple locations.
    Run as: System
    Timeout: 120s

.PARAMETER Hz
    Target refresh rate in Hertz (default: 60)

.EXAMPLE
    .\02_gpu_change.ps1 60

.NOTES
    DLL Search Paths (in order):
    1. $PSScriptRoot\..\bin\DisplayUtilLive.dll (relative to script)
    2. C:\Local\MonitorFix\deploy\Files\DisplayUtilLive.dll (portable deployment location)
    3. $env:ProgramData\baramundi\Files\HzConfig\bin\DisplayUtilLive.dll

    Exit Codes:
    0 = Success
    1 = DLL not found
    2 = DLL load failed
    3 = Frequency change failed
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateRange(1, 500)]
    [int]$Hz = 60
)

$ErrorActionPreference = 'Stop'

Write-Output "=== GPU Refresh Rate Change (Step 2/3) ==="
Write-Output "Target frequency: $Hz Hz"
Write-Output ""

# DLL path (deployed by baramundi to C:\Local\MonitorFix\deploy\Files)
$dllPath = "C:\Local\MonitorFix\deploy\Files\DisplayUtilLive.dll"

Write-Output "DLL path: $dllPath"

if (-not (Test-Path $dllPath)) {
    Write-Output ""
    Write-Output "[ERROR] DisplayUtilLive.dll not found at: $dllPath"
    Write-Output "Please ensure baramundi deployed the DLL to C:\Local\MonitorFix\deploy\Files\"
    exit 1
}

Write-Output "[OK] DLL found"

Write-Output ""

# Check if type is already loaded
$typeLoaded = $false
try {
    $null = [DisplayUtilLive]
    $typeLoaded = $true
    Write-Output "DLL type already loaded (skipping Add-Type)"
} catch {
    $typeLoaded = $false
}

# Load DLL if not already loaded
if (-not $typeLoaded) {
    try {
        Write-Output "Loading DLL..."
        Add-Type -Path $dllPath -ErrorAction Stop
        Write-Output "[OK] DLL loaded successfully"
    } catch {
        Write-Output "[ERROR] Failed to load DLL: $($_.Exception.Message)"
        exit 2
    }
}

Write-Output ""

# Change refresh rate
try {
    Write-Output "Changing all monitors to $Hz Hz..."
    Write-Output ""

    [DisplayUtilLive]::SetAllMonitorsTo($Hz)

    Write-Output ""
    Write-Output "[OK] Refresh rate changed successfully"
    Write-Output ""
    Write-Output "Next step: Run 03_displaylink_reload.ps1 (if DisplayLink is present)"
    exit 0

} catch {
    Write-Output ""
    Write-Output "[ERROR] Failed to change refresh rate: $($_.Exception.Message)"
    exit 3
}
