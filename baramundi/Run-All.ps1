#Requires -Version 5.1
<#
.SYNOPSIS
    Wrapper script that runs all three steps sequentially (baramundi Option B)

.DESCRIPTION
    Executes all three scripts in the correct order:
    1. 01_registry.ps1 - Set DisplayLink registry
    2. 02_gpu_change.ps1 - Change GPU refresh rates
    3. 03_displaylink_reload.ps1 - Reload DisplayLink devices

    All scripts are expected to be in C:\Local\MonitorFix\deploy\.
    DLL is expected at C:\Local\MonitorFix\deploy\Files\DisplayUtilLive.dll.

    Run as: System
    Timeout: 180s

.PARAMETER Hz
    Target refresh rate in Hertz (default: 60)

.EXAMPLE
    .\Run-All.ps1 60

.NOTES
    Exit Codes:
    0 = All steps completed successfully
    1 = Step 1 (registry) failed
    2 = Step 2 (gpu_change) failed
    3 = Step 3 (displaylink_reload) failed
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateRange(1, 500)]
    [int]$Hz = 60
)

$ErrorActionPreference = 'Continue'

Write-Output "======================================="
Write-Output "  HzConfiguration - Full Deployment"
Write-Output "======================================="
Write-Output "Target frequency: $Hz Hz"
Write-Output ""
Write-Output "Running 3 steps sequentially..."
Write-Output ""

# Step 1: Registry setup
Write-Output "--- STEP 1/3: DisplayLink Registry Setup ---"
Write-Output ""

$step1Path = "C:\Local\MonitorFix\deploy\01_registry.ps1"
if (-not (Test-Path $step1Path)) {
    Write-Output "[ERROR] Step 1 script not found: $step1Path"
    exit 1
}

try {
    & $step1Path -Hz $Hz
    $step1ExitCode = $LASTEXITCODE

    if ($step1ExitCode -ne 0) {
        Write-Output ""
        Write-Output "[ERROR] Step 1 failed with exit code: $step1ExitCode"
        exit 1
    }

    Write-Output ""
    Write-Output "[OK] Step 1 completed successfully"
    Write-Output ""

} catch {
    Write-Output "[ERROR] Step 1 exception: $($_.Exception.Message)"
    exit 1
}

# Step 2: GPU change
Write-Output "--- STEP 2/3: GPU Refresh Rate Change ---"
Write-Output ""

$step2Path = "C:\Local\MonitorFix\deploy\02_gpu_change.ps1"
if (-not (Test-Path $step2Path)) {
    Write-Output "[ERROR] Step 2 script not found: $step2Path"
    exit 2
}

try {
    & $step2Path -Hz $Hz
    $step2ExitCode = $LASTEXITCODE

    if ($step2ExitCode -ne 0) {
        Write-Output ""
        Write-Output "[ERROR] Step 2 failed with exit code: $step2ExitCode"
        exit 2
    }

    Write-Output ""
    Write-Output "[OK] Step 2 completed successfully"
    Write-Output ""

} catch {
    Write-Output "[ERROR] Step 2 exception: $($_.Exception.Message)"
    exit 2
}

# Step 3: DisplayLink reload
Write-Output "--- STEP 3/3: DisplayLink Device Reload ---"
Write-Output ""

$step3Path = "C:\Local\MonitorFix\deploy\03_displaylink_reload.ps1"
if (-not (Test-Path $step3Path)) {
    Write-Output "[ERROR] Step 3 script not found: $step3Path"
    exit 3
}

try {
    & $step3Path -Hz $Hz
    $step3ExitCode = $LASTEXITCODE

    if ($step3ExitCode -ne 0) {
        Write-Output ""
        Write-Output "[ERROR] Step 3 failed with exit code: $step3ExitCode"
        exit 3
    }

    Write-Output ""
    Write-Output "[OK] Step 3 completed successfully"
    Write-Output ""

} catch {
    Write-Output "[ERROR] Step 3 exception: $($_.Exception.Message)"
    exit 3
}

# Success
Write-Output "======================================="
Write-Output "  ALL STEPS COMPLETED SUCCESSFULLY"
Write-Output "======================================="
Write-Output ""
Write-Output "All monitors should now be set to $Hz Hz."
Write-Output ""

exit 0
