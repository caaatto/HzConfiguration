#Requires -Version 5.1
<#
.SYNOPSIS
    Reloads DisplayLink devices to apply new settings (baramundi Step 3)

.DESCRIPTION
    Disables and re-enables all DisplayLink devices to apply the new refresh rate.
    This must run AFTER the registry and GPU change scripts.

    Portable: Works without dependencies, uses only PnP cmdlets.
    Run as: System
    Timeout: 60s

.PARAMETER Hz
    Target refresh rate in Hertz (optional, for logging only)

.EXAMPLE
    .\03_displaylink_reload.ps1 60

.NOTES
    Exit Codes:
    0 = Success (or no DisplayLink devices found)
    1 = Error
#>

param(
    [Parameter(Mandatory=$false)]
    [int]$Hz = 0
)

$ErrorActionPreference = 'Continue'

Write-Output "=== DisplayLink Device Reload (Step 3/3) ==="
if ($Hz -gt 0) {
    Write-Output "Target frequency: $Hz Hz"
}
Write-Output ""

# Find all DisplayLink video controllers
$displayLinkDevices = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like '*DisplayLink*' }

if (-not $displayLinkDevices -or $displayLinkDevices.Count -eq 0) {
    Write-Output "No DisplayLink devices found (normal for Intel/NVIDIA/AMD-only systems)"
    Write-Output "Reload not needed - all changes already applied"
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

    Write-Output "Reloading: $deviceName"
    Write-Output "  PNP ID: $pnpId"

    try {
        # Disable device
        Write-Output "  Disabling..."
        Disable-PnpDevice -InstanceId $pnpId -Confirm:$false -ErrorAction Stop
        Start-Sleep -Milliseconds 1000

        # Enable device
        Write-Output "  Enabling..."
        Enable-PnpDevice -InstanceId $pnpId -Confirm:$false -ErrorAction Stop
        Start-Sleep -Milliseconds 800

        Write-Output "  [OK] Device reloaded successfully"
        $successCount++

    } catch {
        Write-Output "  [ERROR] Failed to reload device: $($_.Exception.Message)"
        $errorCount++
    }

    Write-Output ""
}

Write-Output "=== Summary ==="
Write-Output "Success: $successCount"
Write-Output "Errors: $errorCount"
Write-Output ""

if ($successCount -gt 0) {
    Write-Output "All steps completed! DisplayLink monitors should now use the new refresh rate."
    exit 0
} elseif ($errorCount -eq 0) {
    # No DisplayLink devices found - not an error
    exit 0
} else {
    Write-Output "Device reload failed"
    exit 1
}
