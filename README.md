# HzConfiguration - Monitor Refresh Rate Manager

Portable DLL for changing monitor refresh rates on Windows (Intel, NVIDIA, AMD, DisplayLink).

## Features

- **Portable:** No installation required, works on any Windows 10/11
- **Universal:** Supports all GPU types (Intel, NVIDIA, AMD, DisplayLink)
- **Simple API:** Single method call to change all monitors
- **Safe:** Validates modes before applying changes
- **No Dependencies:** Uses built-in Windows API only

---

## Quick Start

### Option 1: Use Hertz.ps1 (Easiest)

The `Hertz.ps1` script automatically loads the DLL from `C:\Local\Files` and sets the refresh rate:

```powershell
# Set all monitors to 60 Hz
.\Hertz.ps1 60

# Set all monitors to 144 Hz
.\Hertz.ps1 144
```

**Note:** The DLL must be in `C:\Local\Files\DisplayUtilLive.dll` (see Build section below).

### Option 2: Use DLL Directly

```powershell
# Load DLL from C:\Local\Files
Add-Type -Path "C:\Local\Files\DisplayUtilLive.dll"

# View current configuration
[DisplayUtilLive]::GetCurrentStatus()

# Change all monitors to 60 Hz
[DisplayUtilLive]::SetAllMonitorsTo(60)
```

### Option 3: Build from Source

**PowerShell (no VS required):**
```powershell
.\Build-DLL.ps1
```

**Batch:**
```cmd
Build.bat
```

**Visual Studio:**
1. Open `DisplayUtilLive.sln`
2. Build → Build Solution (Ctrl+Shift+B)

**Note:** All build methods automatically copy the DLL to:
- `.\bin\DisplayUtilLive.dll` (local build output)
- `C:\Local\Files\DisplayUtilLive.dll` (portable deployment location)

---

## Files

```
HzConfiguration/
├── bin/
│   └── DisplayUtilLive.dll    # Compiled DLL (build output)
├── DisplayUtilLive.cs          # C# source code
├── Build-DLL.ps1               # PowerShell build script
├── Build.bat                   # Batch build script (alternative)
├── Test-DLL.ps1                # Test script
├── Hertz.ps1                   # Main script for setting refresh rates
├── DisplayUtilLive.csproj      # Visual Studio project
├── DisplayUtilLive.sln         # Visual Studio solution
└── README.md                   # This file
```

**Deployment Location:**
```
C:\Local\Files\
└── DisplayUtilLive.dll         # DLL for portable use (auto-copied during build)
```

---

## API Documentation

### SetAllMonitorsTo(int hz)

Sets all active monitors to the specified refresh rate.

```csharp
[DisplayUtilLive]::SetAllMonitorsTo(60)  // Set to 60 Hz
[DisplayUtilLive]::SetAllMonitorsTo(144) // Set to 144 Hz
```

**Parameters:**
- `hz`: Frequency in Hertz (1-500)

**Behavior:**
- Validates mode support before changing
- Keeps resolution and color depth unchanged
- Throws exception if any monitor fails

**Output:**
```
=== SetAllMonitorsTo(60 Hz) ===
Successful changes: 2
✓ \\.\DISPLAY1 (Intel(R) UHD Graphics): 60 Hz → 60 Hz already at 60 Hz
✓ \\.\DISPLAY2 (DisplayLink USB Device): 75 Hz → 60 Hz successful
```

### GetCurrentStatus()

Displays current configuration of all monitors.

```csharp
[DisplayUtilLive]::GetCurrentStatus()
```

**Output:**
```
=== Current Monitor Configuration ===

\\.\DISPLAY1:
  Name: Intel(R) Iris(R) Xe Graphics
  ID: PCI\VEN_8086&DEV_9A49...
  Resolution: 1920x1080
  Frequency: 60 Hz
  Color depth: 32 bit
```

### ListSupportedModes(string deviceName)

Lists all available modes for a specific monitor (debug).

```csharp
[DisplayUtilLive]::ListSupportedModes("\\\\.\\DISPLAY1")
```

**Output:**
```
Available modes for \\.\DISPLAY1:
  - 1920x1080 @ 60 Hz (32 bit)
  - 1920x1080 @ 75 Hz (32 bit)
  - 1920x1080 @ 120 Hz (32 bit)
```

---

## Portable Usage

### No Installation Required

The DLL works on any Windows system without installing .NET Framework (it's built-in on Windows 10/11).

**Recommended portable location:**
```powershell
# DLL is automatically deployed to C:\Local\Files during build
# Use Hertz.ps1 which loads from this location:
.\Hertz.ps1 60
```

**Manual deployment:**
```powershell
# 1. Copy bin/DisplayUtilLive.dll to C:\Local\Files on target machine
# 2. Run from any location
Add-Type -Path "C:\Local\Files\DisplayUtilLive.dll"
[DisplayUtilLive]::SetAllMonitorsTo(60)
```

### Portable Build System

Build without Visual Studio using Windows built-in `csc.exe`:

```powershell
# Finds csc.exe automatically
.\Build-DLL.ps1
```

```cmd
# Batch alternative
Build.bat
```

---

## baramundi Integration

### Package Structure

```
HzConfig-Package/
├── bin/
│   └── DisplayUtilLive.dll
└── scripts/
    ├── 01_registry.ps1        # DisplayLink registry setup
    ├── 02_gpu_change.ps1      # Change refresh rate
    └── 03_displaylink_reload.ps1  # DisplayLink live reload
```

### Script 1: Registry (DisplayLink)

```powershell
param([int]$Hz = 60)

Get-CimInstance Win32_VideoController |
    Where-Object { $_.Name -like '*DisplayLink*' } |
    ForEach-Object {
        $pnp = $_.PNPDeviceID
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$pnp\Device Parameters"

        if (Test-Path $regPath) {
            New-ItemProperty -Path $regPath -Name "DisplayFrequency" `
                             -Value $Hz -PropertyType DWord -Force | Out-Null
            Write-Output "Registry: $regPath = $Hz Hz"
        }
    }
exit 0
```

**Settings:**
- Run as: System
- Timeout: 30s

### Script 2: GPU Change (DLL)

```powershell
param([int]$Hz = 60)

$dllPath = "$env:ProgramData\baramundi\Files\HzConfig\bin\DisplayUtilLive.dll"

if (-not (Test-Path $dllPath)) {
    $dllPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..\bin\DisplayUtilLive.dll"
}

try {
    Add-Type -Path $dllPath -ErrorAction Stop
    [DisplayUtilLive]::SetAllMonitorsTo($Hz)
    Write-Output "All monitors set to $Hz Hz"
    exit 0
} catch {
    Write-Error "Error: $($_.Exception.Message)"
    exit 1
}
```

**Settings:**
- Run as: System
- Timeout: 120s

### Script 3: DisplayLink Reload

```powershell
param([int]$Hz = 60)

$displayLink = Get-CimInstance Win32_VideoController |
               Where-Object { $_.Name -like '*DisplayLink*' }

if (-not $displayLink) {
    Write-Output "No DisplayLink controllers found (normal for Intel/NVIDIA/AMD-only)"
    exit 0
}

foreach ($dev in $displayLink) {
    $id = $dev.PNPDeviceID

    try {
        Disable-PnpDevice -InstanceId $id -Confirm:$false -ErrorAction Stop
        Start-Sleep -Seconds 1
        Enable-PnpDevice -InstanceId $id -Confirm:$false -ErrorAction Stop
        Start-Sleep -Milliseconds 800

        Write-Output "Live-reload: $($dev.Name) successful"
    } catch {
        Write-Warning "Live-reload failed: $($_.Exception.Message)"
    }
}
exit 0
```

**Settings:**
- Run as: System
- Timeout: 60s

---

## Testing

```powershell
# Test 1: View current status (no admin required)
.\Test-DLL.ps1

# Test 2: Change frequency (requires admin)
.\Test-DLL.ps1 -TestFrequency 60

# Test 3: Verbose output
.\Test-DLL.ps1 -TestFrequency 144 -Verbose
```

---

## Troubleshooting

### DLL cannot be loaded

**Error:**
```
Add-Type: Could not load file or assembly...
```

**Solution:**
1. Check if DLL exists: `Test-Path $dllPath`
2. Unblock DLL: `Unblock-File -Path $dllPath`
3. Check .NET Framework 4.0+ is installed (built-in on Windows 10/11)

### Access denied / No admin rights

**Error:**
```
ChangeDisplaySettingsEx failed
```

**Solution:**
- Run PowerShell as Administrator
- Or: Run from baramundi with System account

### DisplayLink frequency stays unchanged

**Cause:** DisplayLink reads frequency from registry, not from DEVMODE

**Solution:**
1. Run Script 1 (Registry) FIRST
2. Run Script 2 (GPU Change)
3. Run Script 3 (Reload) LAST
4. Order matters: Registry → GPU → Reload

---

## Technical Details

### Windows API

Uses native Windows APIs:
- **EnumDisplayDevices:** Lists all display devices
- **EnumDisplaySettings:** Reads current/available modes
- **ChangeDisplaySettingsEx:** Changes display settings

### DEVMODE Structure

```csharp
dmFields = DM_DISPLAYFREQUENCY | DM_PELSWIDTH | DM_PELSHEIGHT | DM_BITSPERPEL
dmDisplayFrequency = 60  // New frequency
dmPelsWidth = 1920       // Preserved resolution
dmPelsHeight = 1080
dmBitsPerPel = 32
```

### CDS_TEST Validation

Before applying changes:
```csharp
ChangeDisplaySettingsEx(deviceName, ref devMode, IntPtr.Zero, CDS_TEST, IntPtr.Zero)
```

Only if `DISP_CHANGE_SUCCESSFUL` → apply with `CDS_UPDATEREGISTRY`.

### DisplayLink Special Handling

DisplayLink stores frequency in registry:
```
HKLM\SYSTEM\CurrentControlSet\Enum\{PNPDeviceID}\Device Parameters\DisplayFrequency
```

Therefore:
1. Set registry value
2. Apply GPU change (sets DEVMODE)
3. PnP reload (loads new settings)

---

## System Requirements

- Windows 10/11 (or Server 2016+)
- .NET Framework 4.0+ (built-in)
- PowerShell 5.1+ (built-in)
- Administrator rights (for changing refresh rates)

---

## Build Requirements

**Runtime (using pre-compiled DLL):**
- None! Just copy `bin/DisplayUtilLive.dll` and use

**Building from source:**
- Windows built-in `csc.exe` (no VS required)
- OR Visual Studio 2019/2022 (any edition)

---

## License

MIT License - Free to use and modify

---

## Credits

**Created by:** catto
**Repository:** https://github.com/caaatto/HzConfiguration
**Version:** 1.0
**Last Updated:** 2025-01-27

---

## Support

**Issues:** https://github.com/caaatto/HzConfiguration/issues

**Common Commands:**
```powershell
# View all displays
Get-CimInstance Win32_VideoController | Select-Object Name, VideoProcessor, PNPDeviceID

# Find DisplayLink devices
Get-CimInstance Win32_VideoController | Where-Object { $_.Name -like '*DisplayLink*' }

# Check registry (DisplayLink)
Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Enum\{PNPDeviceID}\Device Parameters"
```

---

## Examples

### Example 1: Simple Usage

```powershell
Add-Type -Path ".\bin\DisplayUtilLive.dll"
[DisplayUtilLive]::SetAllMonitorsTo(60)
```

### Example 2: Error Handling

```powershell
param([int]$Hz = 60)

try {
    Add-Type -Path ".\bin\DisplayUtilLive.dll" -ErrorAction Stop
    [DisplayUtilLive]::SetAllMonitorsTo($Hz)
    Write-Host "Success: All monitors set to $Hz Hz" -ForegroundColor Green
    exit 0
} catch {
    Write-Error "Error: $($_.Exception.Message)"
    exit 1
}
```

### Example 3: Check Before Change

```powershell
Add-Type -Path ".\bin\DisplayUtilLive.dll"

# Show current
Write-Host "Current configuration:" -ForegroundColor Cyan
[DisplayUtilLive]::GetCurrentStatus()

# Change
Write-Host "`nChanging to 60 Hz..." -ForegroundColor Cyan
[DisplayUtilLive]::SetAllMonitorsTo(60)

# Verify
Write-Host "`nNew configuration:" -ForegroundColor Cyan
[DisplayUtilLive]::GetCurrentStatus()
```

---

**Enjoy your perfectly configured monitors!** 🖥️
