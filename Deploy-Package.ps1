#Requires -Version 5.1
<#
.SYNOPSIS
    Prepares baramundi deployment package

.DESCRIPTION
    Creates a deployment-ready package structure that mirrors the target structure on client machines.
    This package can be uploaded to baramundi for distribution.

    Output structure:
    .\deploy\
    ├── Files\
    │   └── DisplayUtilLive.dll
    ├── 01_registry.ps1
    ├── 02_gpu_change.ps1
    ├── 03_displaylink_reload.ps1
    ├── Run-All.ps1
    └── README.md

.PARAMETER OutputPath
    Output directory for the package (default: .\deploy)

.PARAMETER CleanBuild
    Remove existing deploy directory before creating new one

.EXAMPLE
    .\Deploy-Package.ps1
    .\Deploy-Package.ps1 -OutputPath "C:\baramundi-packages\HzConfig" -CleanBuild

.NOTES
    After running this script, upload the contents of .\deploy\ to baramundi
    and configure file deployment to C:\Local\ on target machines.
#>

[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot 'deploy'),

    [switch]$CleanBuild = $false
)

$ErrorActionPreference = 'Stop'

Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "  baramundi Deployment Package Builder" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host ""

# Source files
$dllSource = Join-Path $PSScriptRoot 'bin\DisplayUtilLive.dll'
$baramundiScripts = Join-Path $PSScriptRoot 'baramundi'
$baramundiReadme = Join-Path $baramundiScripts 'README.md'

# Validate source files
Write-Host "Validating source files..." -ForegroundColor Cyan

if (-not (Test-Path $dllSource)) {
    Write-Error @"
DLL not found: $dllSource

Please build the DLL first:
    .\Build-DLL.ps1
"@
}

if (-not (Test-Path $baramundiScripts)) {
    Write-Error "baramundi scripts directory not found: $baramundiScripts"
}

$requiredScripts = @(
    '01_registry.ps1',
    '02_gpu_change.ps1',
    '03_displaylink_reload.ps1',
    'Run-All.ps1'
)

foreach ($script in $requiredScripts) {
    $scriptPath = Join-Path $baramundiScripts $script
    if (-not (Test-Path $scriptPath)) {
        Write-Error "Required script not found: $scriptPath"
    }
}

Write-Host "[OK] All source files found" -ForegroundColor Green
Write-Host ""

# Clean existing deploy directory
if ($CleanBuild -and (Test-Path $OutputPath)) {
    Write-Host "Cleaning existing deployment directory..." -ForegroundColor Yellow
    Remove-Item $OutputPath -Recurse -Force
    Write-Host "[OK] Old deployment directory removed" -ForegroundColor Green
    Write-Host ""
}

# Create output structure
Write-Host "Creating deployment structure..." -ForegroundColor Cyan

$filesDir = Join-Path $OutputPath 'Files'

if (-not (Test-Path $filesDir)) {
    New-Item -ItemType Directory -Path $filesDir -Force | Out-Null
    Write-Host "[OK] Created: $filesDir" -ForegroundColor Green
}

# Copy DLL
Write-Host ""
Write-Host "Copying DLL..." -ForegroundColor Cyan
$dllTarget = Join-Path $filesDir 'DisplayUtilLive.dll'
Copy-Item -Path $dllSource -Destination $dllTarget -Force
Write-Host "[OK] DLL copied to: $dllTarget" -ForegroundColor Green

$dllInfo = Get-Item $dllTarget
Write-Host "  Size: $([math]::Round($dllInfo.Length / 1KB, 2)) KB" -ForegroundColor Gray
Write-Host "  Modified: $($dllInfo.LastWriteTime)" -ForegroundColor Gray

# Copy scripts
Write-Host ""
Write-Host "Copying scripts..." -ForegroundColor Cyan

foreach ($script in $requiredScripts) {
    $scriptSource = Join-Path $baramundiScripts $script
    $scriptTarget = Join-Path $OutputPath $script
    Copy-Item -Path $scriptSource -Destination $scriptTarget -Force
    Write-Host "[OK] $script" -ForegroundColor Green
}

# Copy README
if (Test-Path $baramundiReadme) {
    $readmeTarget = Join-Path $OutputPath 'README.md'
    Copy-Item -Path $baramundiReadme -Destination $readmeTarget -Force
    Write-Host "[OK] README.md" -ForegroundColor Green
}

# Create deployment manifest
Write-Host ""
Write-Host "Creating deployment manifest..." -ForegroundColor Cyan

$manifest = @"
# HzConfiguration - baramundi Deployment Package
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

## Package Contents

Files/
  DisplayUtilLive.dll     - Main DLL for monitor control

Scripts:
  01_registry.ps1         - DisplayLink registry setup (Step 1)
  02_gpu_change.ps1       - GPU refresh rate change (Step 2)
  03_displaylink_reload.ps1 - DisplayLink reload (Step 3)
  Run-All.ps1            - Combined wrapper script

Documentation:
  README.md              - Full deployment instructions
  MANIFEST.txt           - This file

## baramundi Configuration

### File Deployment (Baustein: File-Deploy)

Deploy all files from this package to target path C:\Local\

Source -> Target mapping:
  Files\DisplayUtilLive.dll -> C:\Local\Files\DisplayUtilLive.dll
  01_registry.ps1 -> C:\Local\01_registry.ps1
  02_gpu_change.ps1 -> C:\Local\02_gpu_change.ps1
  03_displaylink_reload.ps1 -> C:\Local\03_displaylink_reload.ps1
  Run-All.ps1 -> C:\Local\Run-All.ps1

### Script Execution (Baustein: Execute)

Option A - Three separate jobs:
  Job 1: powershell.exe -ExecutionPolicy Bypass -File "C:\Local\01_registry.ps1" -Hz 60
  Job 2: powershell.exe -ExecutionPolicy Bypass -File "C:\Local\02_gpu_change.ps1" -Hz 60
  Job 3: powershell.exe -ExecutionPolicy Bypass -File "C:\Local\03_displaylink_reload.ps1" -Hz 60

Option B - Single combined job:
  Job: powershell.exe -ExecutionPolicy Bypass -File "C:\Local\Run-All.ps1" -Hz 60

All jobs:
  - Run as: System
  - Admin: Yes
  - ExecutionPolicy: Bypass

## Quick Test

After deployment to C:\Local, test on a client:

``````powershell
# Check files
Test-Path "C:\Local\Files\DisplayUtilLive.dll"
Test-Path "C:\Local\02_gpu_change.ps1"

# Run (requires admin)
C:\Local\Run-All.ps1 -Hz 60

# Verify
Add-Type -Path "C:\Local\Files\DisplayUtilLive.dll"
[DisplayUtilLive]::GetCurrentStatus()
``````

## Support

For detailed instructions, see README.md in this package.
"@

$manifestPath = Join-Path $OutputPath 'MANIFEST.txt'
Set-Content -Path $manifestPath -Value $manifest -Encoding UTF8
Write-Host "[OK] MANIFEST.txt created" -ForegroundColor Green

# Summary
Write-Host ""
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "  Package Build Complete" -ForegroundColor Green
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Output directory: $OutputPath" -ForegroundColor White
Write-Host ""

# List package contents
Write-Host "Package contents:" -ForegroundColor Cyan
Get-ChildItem -Path $OutputPath -Recurse -File | ForEach-Object {
    $relativePath = $_.FullName.Substring($OutputPath.Length + 1)
    $size = [math]::Round($_.Length / 1KB, 2)
    Write-Host "  $relativePath" -ForegroundColor Gray -NoNewline
    Write-Host " ($size KB)" -ForegroundColor DarkGray
}

# Calculate total size
$totalSize = (Get-ChildItem -Path $OutputPath -Recurse -File | Measure-Object -Property Length -Sum).Sum
$totalSizeMB = [math]::Round($totalSize / 1MB, 2)

Write-Host ""
Write-Host "Total package size: $totalSizeMB MB" -ForegroundColor White

# Next steps
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Review contents in: $OutputPath" -ForegroundColor Gray
Write-Host "  2. Upload to baramundi server" -ForegroundColor Gray
Write-Host "  3. Configure file deployment: Source -> C:\Local\" -ForegroundColor Gray
Write-Host "  4. Create execution job (see README.md in package)" -ForegroundColor Gray
Write-Host "  5. Test on a client machine" -ForegroundColor Gray
Write-Host ""
Write-Host "For detailed instructions, see: $OutputPath\README.md" -ForegroundColor Yellow
Write-Host ""
Write-Host "[READY FOR DEPLOYMENT]" -ForegroundColor Green -BackgroundColor DarkGreen
Write-Host ""
