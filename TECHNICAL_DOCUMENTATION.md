# MonitorFix - Technical Documentation

**Version:** 1.0
**Date:** 2025-01-28
**Author:** catto

---

## Table of Contents

1. [System Architecture](#system-architecture)
2. [Windows API Integration](#windows-api-integration)
3. [DisplayLink Special Handling](#displaylink-special-handling)
4. [Build Process](#build-process)
5. [Deployment Architecture](#deployment-architecture)
6. [baramundi Integration](#baramundi-integration)
7. [Registry Structure](#registry-structure)
8. [Permissions and Security](#permissions-and-security)
9. [Troubleshooting](#troubleshooting)
10. [Advanced Configuration](#advanced-configuration)

---

## 1. System Architecture

### Component Overview

```
┌────────────────────────────────────────────────────────────┐
│                    MonitorFix System                       │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  ┌──────────────────┐         ┌─────────────────────────┐  │
│  │  PowerShell      │         │  DisplayUtilLive │      │  │
│  │  Scripts         │────────▶│  DLL (C#)        │     │  │
│  │                  │         │                  │      │  │ 
│  │  - Hertz.ps1     │         │  - SetAllMonitorsTo()   │  │ 
│  │  - 01_registry   │         │  - GetCurrentStatus()   │  │ 
│  │  - 02_gpu_change │         │  - ListSupportedModes() │  │ 
│  │  - 03_reload     │         │                         │  │
│  └──────────────────┘         └────────┬────────────────┘  │
│                                        │                   │
│                                        ▼                   │
│                        ┌───────────────────────────┐       │
│                        │   Windows API Layer       │       │
│                        ├───────────────────────────┤       │
│                        │ - EnumDisplayDevices      │       │
│                        │ - EnumDisplaySettings     │       │
│                        │ - ChangeDisplaySettingsEx │       │
│                        └───────────────────────────┘       │
│                                        │                   │
│                                        ▼                   │
│                        ┌───────────────────────────┐       │
│                        │   Hardware Layer          │       │
│                        ├───────────────────────────┤       │
│                        │ - Intel GPU               │       │
│                        │ - NVIDIA GPU              │       │
│                        │ - AMD GPU                 │       │
│                        │ - DisplayLink USB         │       │
│                        └───────────────────────────┘       │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

### File Structure

```
C:\Local\MonitorFix\deploy\
├── Files\
│   └── DisplayUtilLive.dll          # Compiled .NET Assembly
├── 01_registry.ps1                  # DisplayLink Registry Setup
├── 02_gpu_change.ps1                # Main script for frequency change
├── 03_displaylink_reload.ps1        # PnP-Reload for DisplayLink
└── Run-All.ps1                      # Wrapper for all 3 steps
```

---

## 2. Windows API Integration

### 2.1 User32.dll Functions

#### EnumDisplayDevices

**Purpose:** Enumerate all display devices in the system

**P/Invoke Signature:**
```csharp
[DllImport("user32.dll")]
static extern bool EnumDisplayDevices(
    string lpDevice,
    uint iDevNum,
    ref DISPLAY_DEVICE lpDisplayDevice,
    uint dwFlags
);
```

**DISPLAY_DEVICE Structure:**
```csharp
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
struct DISPLAY_DEVICE
{
    public int cb;                    // Size of structure
    [MarshalAs(UnmanagedType.ByValTString, SizeConst = 32)]
    public string DeviceName;         // e.g. "\\.\DISPLAY1"
    [MarshalAs(UnmanagedType.ByValTString, SizeConst = 128)]
    public string DeviceString;       // e.g. "Intel(R) UHD Graphics"
    public uint StateFlags;           // DISPLAY_DEVICE_ACTIVE, etc.
    [MarshalAs(UnmanagedType.ByValTString, SizeConst = 128)]
    public string DeviceID;           // PCI\VEN_8086&DEV_...
    [MarshalAs(UnmanagedType.ByValTString, SizeConst = 128)]
    public string DeviceKey;          // Registry path
}
```

**Usage:**
- Determines all active displays
- Filters for DISPLAY_DEVICE_ACTIVE (0x00000001)
- Provides device names for further API calls

---

#### EnumDisplaySettings

**Purpose:** Reads current or available display modes

**P/Invoke Signature:**
```csharp
[DllImport("user32.dll")]
static extern bool EnumDisplaySettings(
    string deviceName,
    int modeNum,
    ref DEVMODE devMode
);
```

**DEVMODE Structure (simplified):**
```csharp
[StructLayout(LayoutKind.Sequential)]
struct DEVMODE
{
    [MarshalAs(UnmanagedType.ByValTString, SizeConst = 32)]
    public string dmDeviceName;

    public ushort dmSpecVersion;
    public ushort dmDriverVersion;
    public ushort dmSize;
    public ushort dmDriverExtra;
    public uint dmFields;              // DM_* Flags

    // Position and size
    public int dmPositionX;
    public int dmPositionY;
    public uint dmDisplayOrientation;
    public uint dmDisplayFixedOutput;

    // Color depth
    public short dmColor;
    public short dmDuplex;
    public short dmYResolution;
    public short dmTTOption;
    public short dmCollate;

    [MarshalAs(UnmanagedType.ByValTString, SizeConst = 32)]
    public string dmFormName;

    public ushort dmLogPixels;
    public uint dmBitsPerPel;          // Color depth (32 bit)
    public uint dmPelsWidth;           // Width (1920)
    public uint dmPelsHeight;          // Height (1080)
    public uint dmDisplayFlags;
    public uint dmDisplayFrequency;    // Frequency (60 Hz)

    // ... additional fields
}
```

**Mode Parameters:**
- `ENUM_CURRENT_SETTINGS (-1)`: Current mode
- `ENUM_REGISTRY_SETTINGS (-2)`: Registry-stored mode
- `0, 1, 2, ...`: Iterate through available modes

---

#### ChangeDisplaySettingsEx

**Purpose:** Changes display settings

**P/Invoke Signature:**
```csharp
[DllImport("user32.dll")]
static extern int ChangeDisplaySettingsEx(
    string lpszDeviceName,
    ref DEVMODE lpDevMode,
    IntPtr hwnd,
    uint dwflags,
    IntPtr lParam
);
```

**Flags:**
```csharp
const uint CDS_TEST = 0x00000002;           // Test without applying
const uint CDS_UPDATEREGISTRY = 0x00000001; // Save to registry
const uint CDS_NORESET = 0x10000000;        // Don't apply immediately
```

**Return Values:**
```csharp
const int DISP_CHANGE_SUCCESSFUL = 0;
const int DISP_CHANGE_RESTART = 1;          // Restart required
const int DISP_CHANGE_FAILED = -1;
const int DISP_CHANGE_BADMODE = -2;         // Mode not supported
const int DISP_CHANGE_NOTUPDATED = -3;
const int DISP_CHANGE_BADFLAGS = -4;
const int DISP_CHANGE_BADPARAM = -5;
```

**Process:**
1. **Test:** `CDS_TEST` flag → Validation without change
2. **Apply:** `CDS_UPDATEREGISTRY` → Apply and save change

---

### 2.2 Algorithm: SetAllMonitorsTo()

```csharp
public static void SetAllMonitorsTo(int hz)
{
    1. EnumDisplayDevices() for all displays
       ↓
    2. Filter: Only DISPLAY_DEVICE_ACTIVE
       ↓
    3. For each display:
       ├─→ EnumDisplaySettings(ENUM_CURRENT_SETTINGS)
       │   └─→ Read current resolution/color depth
       │
       ├─→ Prepare DEVMODE:
       │   ├─ dmPelsWidth = current (e.g. 1920)
       │   ├─ dmPelsHeight = current (e.g. 1080)
       │   ├─ dmBitsPerPel = current (e.g. 32)
       │   ├─ dmDisplayFrequency = hz (new!)
       │   └─ dmFields = DM_DISPLAYFREQUENCY | DM_PELSWIDTH |
       │                  DM_PELSHEIGHT | DM_BITSPERPEL
       │
       ├─→ ChangeDisplaySettingsEx(CDS_TEST)
       │   ├─ SUCCESSFUL → Continue
       │   └─ Error → Exception
       │
       └─→ ChangeDisplaySettingsEx(CDS_UPDATEREGISTRY)
           ├─ SUCCESSFUL → OK
           └─ Error → Exception
}
```

---

### 2.3 Special Considerations

#### Multi-Monitor Support

```csharp
// Each display is changed INDIVIDUALLY
foreach (var display in displays)
{
    ChangeDisplaySettingsEx(
        display.DeviceName,  // e.g. "\\.\DISPLAY1"
        ref devMode,
        IntPtr.Zero,
        CDS_UPDATEREGISTRY,
        IntPtr.Zero
    );
}
```

**Important:** Do not use `ChangeDisplaySettings()` (without "Ex") - this would reset all displays!

#### Validation Before Change

```csharp
// 1. Test call
int result = ChangeDisplaySettingsEx(
    deviceName,
    ref devMode,
    IntPtr.Zero,
    CDS_TEST,  // ← Test only!
    IntPtr.Zero
);

if (result == DISP_CHANGE_SUCCESSFUL)
{
    // 2. Only now actually change
    ChangeDisplaySettingsEx(
        deviceName,
        ref devMode,
        IntPtr.Zero,
        CDS_UPDATEREGISTRY,  // ← Apply now
        IntPtr.Zero
    );
}
```

---

## 3. DisplayLink Special Handling

### 3.1 Problem: DisplayLink Ignores DEVMODE

**Cause:**
DisplayLink drivers do NOT read the frequency from `DEVMODE.dmDisplayFrequency`, but from the **Registry**.

**Registry Path:**
```
HKLM\SYSTEM\CurrentControlSet\Enum\{PNPDeviceID}\Device Parameters\DisplayFrequency
```

Example:
```
HKLM\SYSTEM\CurrentControlSet\Enum\USB\VID_17E9&PID_430C&MI_00\6&2a6d7a0&0&0000\Device Parameters
  DisplayFrequency (DWORD) = 60
```

---

### 3.2 Three-Step Process

#### Step 1: Set Registry (`01_registry.ps1`)

```powershell
# Find DisplayLink devices
$displayLinkDevices = Get-CimInstance Win32_VideoController |
    Where-Object { $_.Name -like '*DisplayLink*' }

foreach ($device in $displayLinkDevices) {
    $pnpId = $device.PNPDeviceID
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$pnpId\Device Parameters"

    # Set registry value
    Set-ItemProperty -Path $regPath `
                     -Name "DisplayFrequency" `
                     -Value $Hz `
                     -Type DWord `
                     -Force
}
```

**Important:** Requires **Admin rights** for HKLM write access!

---

#### Step 2: GPU Change (`02_gpu_change.ps1`)

```powershell
Add-Type -Path "C:\Local\MonitorFix\deploy\Files\DisplayUtilLive.dll"
[DisplayUtilLive]::SetAllMonitorsTo($Hz)
```

This changes:
- Intel/NVIDIA/AMD monitors → **takes effect immediately**
- DisplayLink monitors → **DEVMODE set, but not yet active**

---

#### Step 3: PnP-Reload (`03_displaylink_reload.ps1`)

```powershell
$displaylink = Get-CimInstance Win32_VideoController |
    Where-Object { $_.Name -like '*DisplayLink*' }

foreach ($dev in $displaylink) {
    $pnp = $dev.PNPDeviceID

    # Disable device → enable
    Disable-PnpDevice -InstanceId $pnp -Confirm:$false
    Start-Sleep -Milliseconds 1000
    Enable-PnpDevice -InstanceId $pnp -Confirm:$false
    Start-Sleep -Milliseconds 800
}
```

**Effect:**
1. DisplayLink driver is reloaded
2. Reads registry value `DisplayFrequency`
3. Applies new frequency

---

### 3.3 Why Three Steps?

```
┌─────────────────────────────────────────────────────────────┐
│  Intel/NVIDIA/AMD GPU          DisplayLink USB              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Step 1: Registry                                           │
│  ✗ Not used                   ✓ DisplayFrequency = 60       │
│                                                              │
│  Step 2: GPU Change (DEVMODE)                               │
│  ✓ Takes effect immediately   ~ DEVMODE set, but            │
│                                  driver reads registry       │
│                                                              │
│  Step 3: PnP Reload                                         │
│  - Not needed                 ✓ Reload driver               │
│                                 → Read registry              │
│                                 → Apply frequency            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 4. Build Process

### 4.1 Compiler Paths

**Build-DLL.ps1** searches for `csc.exe` in this order:

```powershell
1. .NET Framework 4.8 (primary)
   C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe

2. Visual Studio 2022 Build Tools
   C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\Roslyn\csc.exe

3. Visual Studio 2022 Community/Professional/Enterprise
   C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\Roslyn\csc.exe

4. PATH search
   Get-Command csc.exe
```

---

### 4.2 Compilation Parameters

```powershell
csc.exe `
    /target:library                    # Create DLL
    /platform:anycpu                   # x86 + x64
    /optimize+                         # Release optimization
    /out:"bin\DisplayUtilLive.dll"     # Output
    /debug:pdbonly                     # PDB for debugging
    "DisplayUtilLive.cs"               # Source
```

**Result:**
- `bin\DisplayUtilLive.dll` (approx. 8-10 KB)
- `bin\DisplayUtilLive.pdb` (Debug symbols)

---

### 4.3 Automatic Deployment

After successful compilation:

```powershell
Copy-Item -Path "bin\DisplayUtilLive.dll" `
          -Destination "C:\Local\MonitorFix\deploy\Files\DisplayUtilLive.dll" `
          -Force
```

**Directory Creation:**
```powershell
if (-not (Test-Path "C:\Local\MonitorFix\deploy\Files")) {
    New-Item -ItemType Directory -Path "C:\Local\MonitorFix\deploy\Files" -Force
}
```

---

## 5. Deployment Architecture

### 5.1 Target Structure on Client Machines

```
C:\Local\MonitorFix\deploy\
├── Files\
│   ├── DisplayUtilLive.dll          # .NET Assembly (8-10 KB)
│   └── DisplayUtilLive.pdb          # Debug symbols (optional)
├── 01_registry.ps1                  # ~2 KB
├── 02_gpu_change.ps1                # ~3 KB
├── 03_displaylink_reload.ps1        # ~2 KB
├── Run-All.ps1                      # ~3 KB
├── README.md                        # Documentation
└── MANIFEST.txt                     # Deployment info
```

**Total Size:** ~20-30 KB

---

### 5.2 Create Deployment Package

```powershell
.\Deploy-Package.ps1 -OutputPath ".\deploy" -CleanBuild
```

**Process:**
1. Validates `bin\DisplayUtilLive.dll` (must exist)
2. Creates `deploy\Files\` directory
3. Copies DLL → `deploy\Files\DisplayUtilLive.dll`
4. Copies scripts from `baramundi\` → `deploy\`
5. Creates `MANIFEST.txt` with baramundi instructions

**Output:**
```
deploy/
├── Files/
│   └── DisplayUtilLive.dll
├── 01_registry.ps1
├── 02_gpu_change.ps1
├── 03_displaylink_reload.ps1
├── Run-All.ps1
├── README.md
└── MANIFEST.txt
```

---

## 6. baramundi Integration

### 6.1 Job Configuration

#### Option A: Three Separate Jobs

**Job 1: Registry Setup**
```
Module: Execute
Command: C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe
Arguments: -ExecutionPolicy Bypass -File "C:\Local\MonitorFix\deploy\01_registry.ps1" -Hz 60
Run as: System
Timeout: 30s
Error handling: Continue on error (Exit Code 0 if no DisplayLink)
```

**Job 2: GPU Change**
```
Module: Execute
Command: C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe
Arguments: -ExecutionPolicy Bypass -File "C:\Local\MonitorFix\deploy\02_gpu_change.ps1" -Hz 60
Run as: System
Timeout: 120s
Dependencies: Job 1 must succeed (or be skipped)
Error handling: Abort on error
```

**Job 3: DisplayLink Reload**
```
Module: Execute
Command: C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe
Arguments: -ExecutionPolicy Bypass -File "C:\Local\MonitorFix\deploy\03_displaylink_reload.ps1" -Hz 60
Run as: System
Timeout: 60s
Dependencies: Job 2 must succeed
Error handling: Continue on error (Exit Code 0 if no DisplayLink)
```

---

#### Option B: One Combined Job

**Job: Run-All**
```
Module: Execute
Command: C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe
Arguments: -ExecutionPolicy Bypass -File "C:\Local\MonitorFix\deploy\Run-All.ps1" -Hz 60
Run as: System
Timeout: 180s
Error handling: Abort on error
```

**Advantages of Option B:**
- Simpler configuration
- Sequential execution guaranteed
- Single logging stream

**Advantages of Option A:**
- Granular error handling
- Individual jobs can be skipped
- Better monitoring per step

---

### 6.2 File Deployment

**Module:** File Deploy

| Source | Target | Overwrite |
|--------|--------|-----------|
| `deploy\Files\DisplayUtilLive.dll` | `C:\Local\MonitorFix\deploy\Files\DisplayUtilLive.dll` | Yes |
| `deploy\01_registry.ps1` | `C:\Local\MonitorFix\deploy\01_registry.ps1` | Yes |
| `deploy\02_gpu_change.ps1` | `C:\Local\MonitorFix\deploy\02_gpu_change.ps1` | Yes |
| `deploy\03_displaylink_reload.ps1` | `C:\Local\MonitorFix\deploy\03_displaylink_reload.ps1` | Yes |
| `deploy\Run-All.ps1` | `C:\Local\MonitorFix\deploy\Run-All.ps1` | Yes |

**Permissions:** System (Full access)

---

### 6.3 Exit Codes

**Script: 01_registry.ps1**
| Code | Meaning |
|------|-----------|
| 0 | Success or no DisplayLink devices |
| 1 | Registry access failed |

**Script: 02_gpu_change.ps1**
| Code | Meaning |
|------|-----------|
| 0 | Success |
| 1 | DLL not found |
| 2 | DLL could not be loaded |
| 3 | Frequency change failed |

**Script: 03_displaylink_reload.ps1**
| Code | Meaning |
|------|-----------|
| 0 | Success or no DisplayLink devices |
| 1 | PnP reload failed |

**Script: Run-All.ps1**
| Code | Meaning |
|------|-----------|
| 0 | All steps successful |
| 1 | Step 1 failed |
| 2 | Step 2 failed |
| 3 | Step 3 failed |

---

### 6.4 Logging

All scripts use `Write-Output` (not `Write-Host`), so baramundi can capture the output.

**Log Format:**
```
=== DisplayLink Registry Setup (Step 1/3) ===
Target frequency: 60 Hz

Found 2 DisplayLink device(s):
  - DisplayLink USB Device

Processing: DisplayLink USB Device
  PNP ID: USB\VID_17E9&PID_430C&MI_00\6&2a6d7a0&0&0000
  [OK] Registry set to 60 Hz

=== Summary ===
Success: 2
Errors: 0

Next step: Run 02_gpu_change.ps1
```

---

## 7. Registry Structure

### 7.1 DisplayLink Registry Values

**Path:**
```
HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\{PNPDeviceID}\Device Parameters
```

**Important Values:**

| Name | Type | Example | Description |
|------|-----|----------|--------------|
| `DisplayFrequency` | REG_DWORD | `0x0000003C` (60) | Target frequency in Hz |
| `DeviceDesc` | REG_SZ | "DisplayLink USB Device" | Device description |
| `EDID` | REG_BINARY | ... | Monitor EDID data |

---

### 7.2 PNPDeviceID Structure

**Example:**
```
USB\VID_17E9&PID_430C&MI_00\6&2a6d7a0&0&0000
│   │        │        │      │
│   │        │        │      └─ Unique Instance ID
│   │        │        └─ Interface Number
│   │        └─ Product ID (DisplayLink-specific)
│   └─ Vendor ID (17E9 = DisplayLink)
└─ Bus Type (USB)
```

**Vendor ID 17E9:** All DisplayLink devices

**Common Product IDs:**
- `430C` - DisplayLink DL-3900
- `4331` - DisplayLink DL-5500
- `436C` - DisplayLink DL-6950

---

### 7.3 Registry Access Requires Admin

**PowerShell Permissions:**

```powershell
# READ (no admin needed)
Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Enum\..."

# WRITE (admin required!)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Enum\..." `
                 -Name "DisplayFrequency" `
                 -Value 60 `
                 -Type DWord
```

**Error Without Admin:**
```
Set-ItemProperty: The requested registry access is not allowed.
```

---

## 8. Permissions and Security

### 8.1 Required Permissions

| Action | Permission | Reason |
|--------|--------------|-------|
| Load DLL | User | Add-Type loads assembly in process |
| EnumDisplayDevices | User | Read access to display info |
| ChangeDisplaySettingsEx | Administrator | System-wide change |
| Registry (HKLM) write | Administrator | HKLM write access |
| PnP Device Disable/Enable | Administrator | Device management |

---

### 8.2 SYSTEM vs. Administrator

**SYSTEM Account (baramundi):**
- Usually has full registry access
- Can manage PnP devices
- **Problem:** Some USB device registry keys may lack permissions

**Workaround for baramundi Registry Problems:**

Option 1: Set registry permissions (beforehand)
```powershell
$acl = Get-Acl "HKLM:\SYSTEM\CurrentControlSet\Enum\USB\..."
$rule = New-Object System.Security.AccessControl.RegistryAccessRule(
    "NT AUTHORITY\SYSTEM",
    "FullControl",
    "Allow"
)
$acl.SetAccessRule($rule)
Set-Acl -Path "HKLM:\..." -AclObject $acl
```

Option 2: Force 64-bit PowerShell
```
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe
```

---

### 8.3 Execution Policy

**Problem:** PowerShell scripts are not signed

**Solutions:**

```powershell
# Option 1: Bypass for single execution
powershell.exe -ExecutionPolicy Bypass -File "script.ps1"

# Option 2: RemoteSigned for the user
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser

# Option 3: Unblock files
Unblock-File -Path "*.ps1"
```

**baramundi:** Always use `-ExecutionPolicy Bypass`!

---

## 9. Troubleshooting

### 9.1 DLL Loading Problems

#### Problem: "Could not load file or assembly"

**Causes:**
1. DLL path incorrect
2. DLL is blocked (Download Protection)
3. .NET Framework missing
4. 32-bit vs 64-bit conflict

**Diagnosis:**
```powershell
# Does DLL exist?
Test-Path "C:\Local\MonitorFix\deploy\Files\DisplayUtilLive.dll"

# Is DLL blocked?
Get-Item "C:\Local\MonitorFix\deploy\Files\DisplayUtilLive.dll" |
    Select-Object -ExpandProperty Attributes

# Unblock
Unblock-File -Path "C:\Local\MonitorFix\deploy\Files\DisplayUtilLive.dll"
```

---

#### Problem: "Bad IL format"

**Cause:** 32-bit PowerShell trying to load 64-bit DLL

**Solution:**
```powershell
# Force 64-bit PowerShell
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -File "script.ps1"

# Don't use (32-bit):
C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe
```

**Check:**
```powershell
# Is this 64-bit PowerShell?
[Environment]::Is64BitProcess
# True = 64-bit, False = 32-bit
```

---

### 9.2 Registry Problems

#### Problem: "Registry access denied"

**Cause:** No admin rights

**Diagnosis:**
```powershell
# Admin check
([Security.Principal.WindowsPrincipal] `
  [Security.Principal.WindowsIdentity]::GetCurrent() `
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
```

**Solution:**
```powershell
# Start PowerShell as admin
Start-Process powershell -Verb RunAs
```

---

#### Problem: Registry path not found

**Cause:** PNPDeviceID contains special characters or spaces

**Example:**
```
USB\VID_17E9&PID_430C&MI_00\6&2a6d7a0&0&0000
```

**Correct:**
```powershell
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$pnpId\Device Parameters"
# NOT:
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\" + $pnpId + "\Device Parameters"
```

**Test:**
```powershell
Test-Path "HKLM:\SYSTEM\CurrentControlSet\Enum\USB\VID_17E9&PID_430C&MI_00\6&2a6d7a0&0&0000\Device Parameters"
```

---

### 9.3 DisplayLink Stays at Old Frequency

**Possible Causes:**

1. **Registry not set**
   ```powershell
   # Check:
   Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Enum\{PNPDeviceID}\Device Parameters" -Name DisplayFrequency
   ```

2. **PnP reload not executed**
   ```powershell
   # Manually reload:
   $pnp = "USB\VID_17E9&PID_430C&MI_00\6&2a6d7a0&0&0000"
   Disable-PnpDevice -InstanceId $pnp -Confirm:$false
   Start-Sleep -Seconds 2
   Enable-PnpDevice -InstanceId $pnp -Confirm:$false
   ```

3. **Incorrect order**
   - **Correct:** Registry → GPU → Reload
   - **Wrong:** GPU → Registry → Reload

4. **DisplayLink driver too old**
   - Update to current version (https://displaylink.com/downloads)

---

### 9.4 baramundi-Specific Problems

#### Problem: "Script not found"

**Cause:** Wrong path or file deploy failed

**Diagnosis (baramundi test job):**
```powershell
Test-Path "C:\Local\MonitorFix\deploy\01_registry.ps1"
Test-Path "C:\Local\MonitorFix\deploy\Files\DisplayUtilLive.dll"
Get-ChildItem "C:\Local\MonitorFix\deploy\" -Recurse
```

---

#### Problem: 32-bit PowerShell

**Symptom:** Registry paths not found or "Bad IL format"

**Solution:** Full path to 64-bit PowerShell

**baramundi Command:**
```
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -File "C:\Local\MonitorFix\deploy\Run-All.ps1" -Hz 60
```

**NOT:**
```
powershell.exe ...
```

---

#### Problem: SYSTEM Account Registry Access

**Symptom:** Works as admin, but not via baramundi

**Diagnostic Script (baramundi job):**
```powershell
Write-Output "User: $env:USERNAME"
Write-Output "Is Admin: $((New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"

try {
    $pnp = "USB\VID_17E9&PID_430C&MI_00\6&2a6d7a0&0&0000"
    $path = "HKLM:\SYSTEM\CurrentControlSet\Enum\$pnp\Device Parameters"

    # Read attempt
    Get-ItemProperty -Path $path -ErrorAction Stop
    Write-Output "READ: OK"

    # Write attempt
    Set-ItemProperty -Path $path -Name "TestValue" -Value 1 -Type DWord -Force -ErrorAction Stop
    Write-Output "WRITE: OK"

    # Cleanup
    Remove-ItemProperty -Path $path -Name "TestValue" -ErrorAction SilentlyContinue

} catch {
    Write-Output "ERROR: $($_.Exception.Message)"
}
```

---

## 10. Advanced Configuration

### 10.1 Different Frequencies per Monitor

Currently: `SetAllMonitorsTo()` sets ALL to same frequency

**Extension:** Individual frequencies

```csharp
public static void SetMonitorFrequency(string deviceName, int hz)
{
    DEVMODE devMode = new DEVMODE();
    devMode.dmSize = (ushort)Marshal.SizeOf(devMode);

    // Read current mode
    if (!EnumDisplaySettings(deviceName, ENUM_CURRENT_SETTINGS, ref devMode))
        throw new Exception($"Cannot read settings for {deviceName}");

    // Change only frequency
    devMode.dmDisplayFrequency = (uint)hz;
    devMode.dmFields = DM_DISPLAYFREQUENCY | DM_PELSWIDTH | DM_PELSHEIGHT | DM_BITSPERPEL;

    // Test
    int testResult = ChangeDisplaySettingsEx(deviceName, ref devMode, IntPtr.Zero, CDS_TEST, IntPtr.Zero);
    if (testResult != DISP_CHANGE_SUCCESSFUL)
        throw new Exception($"{deviceName}: Mode {hz} Hz not supported");

    // Apply
    int result = ChangeDisplaySettingsEx(deviceName, ref devMode, IntPtr.Zero, CDS_UPDATEREGISTRY, IntPtr.Zero);
    if (result != DISP_CHANGE_SUCCESSFUL)
        throw new Exception($"{deviceName}: ChangeDisplaySettingsEx failed");
}
```

**Usage:**
```powershell
[DisplayUtilLive]::SetMonitorFrequency("\\.\DISPLAY1", 144)
[DisplayUtilLive]::SetMonitorFrequency("\\.\DISPLAY2", 60)
```

---

### 10.2 Conditional Deployment (baramundi)

**Scenario:** Execute only on clients with DisplayLink

**WMI Query (baramundi Condition):**
```sql
SELECT * FROM Win32_VideoController WHERE Name LIKE '%DisplayLink%'
```

**Or in script:**
```powershell
$hasDisplayLink = Get-CimInstance Win32_VideoController |
    Where-Object { $_.Name -like '*DisplayLink*' }

if (-not $hasDisplayLink) {
    Write-Output "No DisplayLink devices - skipping"
    exit 0
}
```

---

### 10.3 Rollback Function

**Idea:** Save current state before change

```powershell
# Before change: Save status
Add-Type -Path "C:\Local\MonitorFix\deploy\Files\DisplayUtilLive.dll"
$status = [DisplayUtilLive]::GetCurrentStatus()
$status | Out-File "C:\Local\MonitorFix\backup.txt"

# Perform change
[DisplayUtilLive]::SetAllMonitorsTo(60)

# In case of problems: Rollback
# (Manually read old frequencies from backup.txt and restore)
```

---

### 10.4 Monitoring & Reporting

**baramundi Custom Inventory:**

```powershell
# Read current monitor frequencies
Add-Type -Path "C:\Local\MonitorFix\deploy\Files\DisplayUtilLive.dll"

$displays = [DisplayUtilLive]::GetDisplayDevices()
foreach ($display in $displays) {
    $devMode = New-Object DEVMODE
    $devMode.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf($devMode)

    if ([DisplayUtilLive]::EnumDisplaySettings($display.DeviceName, -1, [ref]$devMode)) {
        Write-Output "$($display.DeviceName): $($devMode.dmDisplayFrequency) Hz"
    }
}
```

**Output for baramundi Inventory:**
```
\\.\DISPLAY1: 60 Hz
\\.\DISPLAY2: 60 Hz
\\.\DISPLAY3: 144 Hz
```

---

## Appendix

### A. References

**Windows API:**
- [EnumDisplayDevices](https://docs.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-enumdisplaydevicesa)
- [EnumDisplaySettings](https://docs.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-enumdisplaysettingsa)
- [ChangeDisplaySettingsEx](https://docs.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-changedisplaysettingsexa)
- [DEVMODE Structure](https://docs.microsoft.com/en-us/windows/win32/api/wingdi/ns-wingdi-devmodea)

**DisplayLink:**
- [DisplayLink Website](https://www.displaylink.com/)
- [DisplayLink Downloads](https://www.displaylink.com/downloads)

**PowerShell:**
- [Get-CimInstance](https://docs.microsoft.com/en-us/powershell/module/cimcmdlets/get-ciminstance)
- [Set-ItemProperty](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.management/set-itemproperty)
- [Disable-PnpDevice](https://docs.microsoft.com/en-us/powershell/module/pnpdevice/disable-pnpdevice)

---

### B. Version History

| Version | Date | Changes |
|---------|-------|------------|
| 1.0 | 2025-01-28 | Initial version |
| | | - Path adjustment to C:\Local\MonitorFix\deploy\ |
| | | - Complete technical documentation |
| | | - baramundi integration documented |

---

### C. Support

**GitHub:** https://github.com/caaatto/HzConfiguration
**Issues:** https://github.com/caaatto/HzConfiguration/issues
**Author:** catto

---

**End of technical documentation**
