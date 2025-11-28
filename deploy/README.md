# baramundi Integration - Monitor Refresh Rate Manager

These scripts are ready for integration into baramundi. All files are copied by baramundi to `C:\Local`, the scripts work directly with these fixed paths.

---

## Deployment Structure

baramundi copies all files to `C:\Local` in this structure:

```
C:\Local\MonitorFix\deploy\
├── Files\
│   └── DisplayUtilLive.dll
└── (optional: scripts can be located here or elsewhere)
```

The scripts expect the DLL at: **`C:\Local\MonitorFix\deploy\MonitorFix\deploy\Files\DisplayUtilLive.dll`**

---

## Script Overview

### 1. `01_registry.ps1` - DisplayLink Registry Setup

**What it does:**
- Sets registry value `DisplayFrequency` for all DisplayLink devices
- Must be executed BEFORE `02_gpu_change.ps1`
- Harmless for systems without DisplayLink (Exit Code 0)

**Execution:**
```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\Local\MonitorFix\deploy\01_registry.ps1" -Hz 60
```

**Parameters:**
- `-Hz` : Target frequency in Hz (default: 60)

**Exit Codes:**
- `0` = Success (or no DisplayLink devices found)
- `1` = Error setting registry

**baramundi Settings:**
- **Run as:** System
- **Timeout:** 30s
- **Admin:** Yes

---

### 2. `02_gpu_change.ps1` - GPU Refresh Rate Change

**What it does:**
- Loads `DisplayUtilLive.dll` from `C:\Local\MonitorFix\deploy\MonitorFix\deploy\Files\`
- Changes the refresh rate of all monitors (Intel, NVIDIA, AMD, DisplayLink)
- **This is the main script**

**Execution:**
```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\Local\MonitorFix\deploy\02_gpu_change.ps1" -Hz 60
```

**Parameters:**
- `-Hz` : Target frequency in Hz (default: 60)

**Exit Codes:**
- `0` = Success
- `1` = DLL not found
- `2` = DLL could not be loaded
- `3` = Frequency change failed

**baramundi Settings:**
- **Run as:** System
- **Timeout:** 120s
- **Admin:** Yes

---

### 3. `03_displaylink_reload.ps1` - DisplayLink Live Reload

**What it does:**
- Disables and enables DisplayLink devices (PnP reload)
- Loads the new registry values
- Must run AFTER `01_registry.ps1` and `02_gpu_change.ps1`
- Harmless for systems without DisplayLink (Exit Code 0)

**Execution:**
```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\Local\MonitorFix\deploy\03_displaylink_reload.ps1" -Hz 60
```

**Parameters:**
- `-Hz` : Target frequency in Hz (optional, for logging only)

**Exit Codes:**
- `0` = Success (or no DisplayLink devices found)
- `1` = Error reloading devices

**baramundi Settings:**
- **Run as:** System
- **Timeout:** 60s
- **Admin:** Yes

---

## baramundi Configuration

### Option A: Three Separate Jobs (recommended for flexibility)

**Job 1: DisplayLink Registry Setup**
```
Command: powershell.exe -ExecutionPolicy Bypass -File "C:\Local\MonitorFix\deploy\01_registry.ps1" -Hz 60
Run as: System
Timeout: 30s
Order: 1
```

**Job 2: GPU Change (Main Job)**
```
Command: powershell.exe -ExecutionPolicy Bypass -File "C:\Local\MonitorFix\deploy\02_gpu_change.ps1" -Hz 60
Run as: System
Timeout: 120s
Order: 2
Dependency: Job 1 must be successful (Exit Code 0)
```

**Job 3: DisplayLink Reload**
```
Command: powershell.exe -ExecutionPolicy Bypass -File "C:\Local\MonitorFix\deploy\03_displaylink_reload.ps1" -Hz 60
Run as: System
Timeout: 60s
Order: 3
Dependency: Job 2 must be successful (Exit Code 0)
```

### Option B: One Combined Job

Create a wrapper script `Run-All.ps1`:

```powershell
param([int]$Hz = 60)

Write-Output "=== Starting HzConfiguration (3 steps) ==="
Write-Output ""

# Step 1
& "C:\Local\MonitorFix\deploy\01_registry.ps1" -Hz $Hz
if ($LASTEXITCODE -ne 0) {
    Write-Output "Step 1 failed!"
    exit 1
}

# Step 2
& "C:\Local\MonitorFix\deploy\02_gpu_change.ps1" -Hz $Hz
if ($LASTEXITCODE -ne 0) {
    Write-Output "Step 2 failed!"
    exit 2
}

# Step 3
& "C:\Local\MonitorFix\deploy\03_displaylink_reload.ps1" -Hz $Hz
if ($LASTEXITCODE -ne 0) {
    Write-Output "Step 3 failed!"
    exit 3
}

Write-Output ""
Write-Output "=== All steps completed successfully ==="
exit 0
```

**Execution:**
```
powershell.exe -ExecutionPolicy Bypass -File "C:\Local\MonitorFix\deploy\Run-All.ps1" -Hz 60
Run as: System
Timeout: 180s
```

---

## File Deployment in baramundi

### Module Configuration

**1. File-Deploy Module:**

| Source | Destination |
|--------|------|
| `bin\DisplayUtilLive.dll` | `C:\Local\MonitorFix\deploy\MonitorFix\deploy\Files\DisplayUtilLive.dll` |
| `baramundi\01_registry.ps1` | `C:\Local\MonitorFix\deploy\01_registry.ps1` |
| `baramundi\02_gpu_change.ps1` | `C:\Local\MonitorFix\deploy\02_gpu_change.ps1` |
| `baramundi\03_displaylink_reload.ps1` | `C:\Local\MonitorFix\deploy\03_displaylink_reload.ps1` |

**2. Execute Module:**

See "baramundi Configuration" above.

---

## Common Scenarios

### Scenario 1: Set All Monitors to 60 Hz

```
Job: 01_registry.ps1 -Hz 60
Job: 02_gpu_change.ps1 -Hz 60
Job: 03_displaylink_reload.ps1 -Hz 60
```

### Scenario 2: Intel/NVIDIA/AMD Only (no DisplayLink)

```
Job: 02_gpu_change.ps1 -Hz 60
```

Scripts `01_registry.ps1` and `03_displaylink_reload.ps1` return Exit Code 0 if no DisplayLink devices are found, so you can always run all three jobs.

### Scenario 3: Different Frequencies for Different Computer Groups

Create multiple jobs with different `-Hz` parameters:

- **Office PCs:** `-Hz 60`
- **Gaming PCs:** `-Hz 144`
- **Designer PCs:** `-Hz 75`

---

## Testing

### Manual Test on a Client

1. Copy files to `C:\Local` (simulates baramundi):
```powershell
# From your build directory
Copy-Item ".\bin\DisplayUtilLive.dll" "C:\Local\MonitorFix\deploy\MonitorFix\deploy\Files\DisplayUtilLive.dll" -Force
Copy-Item ".\baramundi\*.ps1" "C:\Local\MonitorFix\deploy\" -Force
```

2. Execute scripts (as Admin):
```powershell
cd C:\Local
.\01_registry.ps1 -Hz 60
.\02_gpu_change.ps1 -Hz 60
.\03_displaylink_reload.ps1 -Hz 60
```

3. Check result:
```powershell
# Display current monitor configuration
Add-Type -Path "C:\Local\MonitorFix\deploy\MonitorFix\deploy\Files\DisplayUtilLive.dll"
[DisplayUtilLive]::GetCurrentStatus()
```

---

## Troubleshooting

### Problem: "DLL not found"

**Solution:**
- Check if baramundi copied the DLL to `C:\Local\MonitorFix\deploy\MonitorFix\deploy\Files\DisplayUtilLive.dll`
- Execute on the client: `Test-Path "C:\Local\MonitorFix\deploy\MonitorFix\deploy\Files\DisplayUtilLive.dll"`

### Problem: "Access denied" or "ChangeDisplaySettingsEx failed"

**Solution:**
- Scripts must be executed as **System** or **Administrator**
- Check baramundi job settings: "Run as: System"

### Problem: DisplayLink Remains at Old Frequency

**Solution:**
- Order is important: Registry → GPU → Reload
- All three scripts must complete successfully (Exit Code 0)
- For job dependencies in baramundi, ensure that jobs run sequentially

### Problem: Exit Code Not Equal to 0

**Check exit codes:**

| Exit Code | Script | Meaning |
|-----------|--------|-----------|
| 0 | All | Success |
| 1 | 01, 03 | General error |
| 1 | 02 | DLL not found |
| 2 | 02 | DLL could not be loaded |
| 3 | 02 | Frequency change failed |

**Check logs:**
- baramundi displays the script output in the job log
- All scripts provide meaningful messages

---

## Advantages of This Solution

✅ **No search logic:** Scripts use fixed paths under `C:\Local`
✅ **No copy functions:** baramundi handles file deployment
✅ **Portable:** Works on any Windows 10/11 without installation
✅ **Robust:** Clear exit codes for baramundi monitoring
✅ **Flexible:** Scripts can be executed individually or combined
✅ **Safe:** Validation and error handling in every script
✅ **Universal:** Supports Intel, NVIDIA, AMD, DisplayLink

---

## Support

**Problems?**
- Check baramundi job logs for script outputs
- Test scripts manually on a client
- Ensure all files exist under `C:\Local`
- Check admin rights (Run as: System)

**More Information:**
- See main README.md for technical details
- GitHub: https://github.com/caaatto/HzConfiguration

---

**Ready for Deployment!** 🚀
