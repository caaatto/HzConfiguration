#Requires -Version 5.1
<#
.SYNOPSIS
    Sets DisplayLink registry frequency (baramundi Step 1)

.DESCRIPTION
    Sets the DisplayFrequency registry value for all DisplayLink devices.
    This must run BEFORE the GPU change script.

    Portable: Works without dependencies, uses only WMI/CIM.
    Run as: System
    Timeout: 30s

.PARAMETER Hz
    Target refresh rate in Hertz (default: 60)

.EXAMPLE
    .\01_registry.ps1 60

.NOTES
    Exit Codes:
    0 = Success (or no DisplayLink devices found)
    1 = Error
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateRange(1, 500)]
    [int]$Hz = 60
)

$ErrorActionPreference = 'Continue'

Write-Output "=== DisplayLink Registry Setup (Step 1/3) ==="
Write-Output "Target frequency: $Hz Hz"
Write-Output ""

# Find all DisplayLink video controllers
$displayLinkDevices = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like '*DisplayLink*' }

if (-not $displayLinkDevices -or $displayLinkDevices.Count -eq 0) {
    Write-Output "No DisplayLink devices found (normal for Intel/NVIDIA/AMD-only systems)"
    Write-Output "Skipping registry setup"
    exit 0
}

Write-Output "Found $($displayLinkDevices.Count) DisplayLink device(s):"
$displayLinkDevices | ForEach-Object {
    Write-Output "  - $($_.Name)"
}
Write-Output ""

$successCount = 0
$errorCount = 0

foreach ($device in $displayLinkDevices) {
    $pnpId = $device.PNPDeviceID
    $deviceName = $device.Name

    # Construct registry path
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$pnpId\Device Parameters"

    Write-Output "Processing: $deviceName"
    Write-Output "  PNP ID: $pnpId"

    # Check if registry path exists
    if (-not (Test-Path $regPath)) {
        Write-Output "  Registry path not found: $regPath"
        $errorCount++
        continue
    }

    # Set DisplayFrequency value
    try {
        Set-ItemProperty -Path $regPath `
                         -Name "DisplayFrequency" `
                         -Value $Hz `
                         -Type DWord `
                         -Force `
                         -ErrorAction Stop

        Write-Output "  [OK] Registry set to $Hz Hz"
        $successCount++

    } catch {
        Write-Output "  [ERROR] Failed to set registry: $($_.Exception.Message)"
        $errorCount++
    }
}

Write-Output ""
Write-Output "=== Summary ==="
Write-Output "Success: $successCount"
Write-Output "Errors: $errorCount"
Write-Output ""

if ($successCount -gt 0) {
    Write-Output "Next step: Run 02_gpu_change.ps1"
    exit 0
} elseif ($errorCount -eq 0) {
    # No DisplayLink devices found - not an error
    exit 0
} else {
    Write-Output "Registry setup failed"
    exit 1
}