<#
.SYNOPSIS
    Sets the refresh rate (Hz) live for all monitors.
.DESCRIPTION
    - GPU monitors (Intel/NVIDIA/AMD) are switched to current mode with desired Hz (if available).
    - DisplayLink monitors: Registry entry "DisplayFrequency" is set and device is briefly disabled/enabled (live reload).
    - Avoids Add-Type conflicts and C# string interpolation issues.
.EXAMPLE
    .\Hertz.ps1 60
#>

param([int]$refresh = 60)

Write-Host "==============================" -ForegroundColor Cyan
Write-Host "  Forcing $refresh Hz on all monitors (LIVE)" -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan

# -----------------------------
# 0. Load DLL from C:\Local\MonitorFix\deploy\Files
# -----------------------------
$dllPath = "C:\Local\MonitorFix\deploy\Files\DisplayUtilLive.dll"

# Check if DLL exists
if (-not (Test-Path $dllPath)) {
    Write-Host "ERROR: DLL not found!" -ForegroundColor Red
    Write-Host "Expected: $dllPath" -ForegroundColor Yellow
    Write-Host "`nPlease ensure that:" -ForegroundColor Yellow
    Write-Host "  1. The DLL was compiled (Build-DLL.ps1 or Build.bat)" -ForegroundColor Gray
    Write-Host "  2. The DLL was copied to C:\Local\MonitorFix\deploy\Files" -ForegroundColor Gray
    exit 1
}

# Check if type is already loaded
$needAddType = $true
try {
    $null = [DisplayUtilLive]
    $needAddType = $false
    Write-Host "DLL already loaded — Add-Type skipped." -ForegroundColor DarkYellow
} catch {
    $needAddType = $true
}

# Load DLL
if ($needAddType) {
    try {
        Write-Host "Loading DLL from: $dllPath" -ForegroundColor Cyan
        Add-Type -Path $dllPath -ErrorAction Stop
        Write-Host "✓ DLL loaded successfully" -ForegroundColor Green
    } catch {
        Write-Host "ERROR loading DLL: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

try {
    [DisplayUtilLive]::SetGPUMonitorsTo($refresh)
} catch {
    Write-Host "Error setting GPU monitors: $($_.Exception.Message)" -ForegroundColor Red
}


# Search for DisplayLink via Win32_VideoController
$displaylink = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -like "*DisplayLink*" }

if (!$displaylink -or $displaylink.Count -eq 0) {
    Write-Host "`nNo DisplayLink video controllers found." -ForegroundColor Yellow
} else {
    Write-Host "`nDisplayLink video controllers found:" -ForegroundColor Cyan
    $displaylink | ForEach-Object { Write-Host " → $($_.Name)  PNP: $($_.PNPDeviceID)" }

    foreach ($dev in $displaylink) {
        # PNPDeviceID can be e.g. "USB\VID_17E9&PID_..."
        $pnp = $dev.PNPDeviceID
        # Registry path to Device Parameters for the Enum entry
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$pnp`\\Device Parameters"

        # Some systems have different path structures - try robustly:
        if (!(Test-Path $regPath)) {
            # Try to find the Enum node directly and append "\Device Parameters"
            $enumBase = "HKLM:\SYSTEM\CurrentControlSet\Enum\$pnp"
            if (Test-Path $enumBase) {
                $regPath = Join-Path $enumBase "Device Parameters"
            }
        }

        if (Test-Path $regPath) {
            Write-Host "→ Setting registry for $($dev.Name) to $refresh Hz ..."
            try {
                Set-ItemProperty -Path $regPath -Name "DisplayFrequency" -Value $refresh -Type DWord -Force
                Write-Host "Registry updated."
            } catch {
                Write-Host "Error writing to registry: $($_.Exception.Message)" -ForegroundColor Red
            }
        } else {
            Write-Host "Registry path not found for $($dev.Name): $regPath" -ForegroundColor DarkYellow
        }

        # Live reload: Disable / Enable the PnP device
        Write-Host "→ Reloading DisplayLink: $($dev.Name) ..."
        try {
            # Disable/Enable with PNPDeviceID. Requires admin rights.
            Disable-PnpDevice -InstanceId $pnp -Confirm:$false -ErrorAction Stop
            Start-Sleep -Milliseconds 1000
            Enable-PnpDevice  -InstanceId $pnp -Confirm:$false -ErrorAction Stop
            Start-Sleep -Milliseconds 800
            Write-Host "  Live reload successful." -ForegroundColor Green
        } catch {
            Write-Host "Error reloading (Disable/Enable) $($dev.Name): $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Note: Ensure that PowerShell is running as Administrator."
        }
    }
}

Write-Host "`nAll reachable monitors have been attempted to be set to $refresh Hz." -ForegroundColor Green
Write-Host "If some monitors still show 70 Hz: restart the PC." -ForegroundColor Yellow
