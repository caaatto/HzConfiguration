#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Plant Löschung von C:\Local\MonitorFix beim nächsten Neustart

.DESCRIPTION
    Verwendet die Windows PendingFileRenameOperations Registry-Funktion
    um das Verzeichnis beim nächsten Neustart zu löschen.
    Erfordert Administrator-Rechte.

.EXAMPLE
    .\Cleanup-OnReboot.ps1
#>

$targetPath = "C:\Local\MonitorFix"

Write-Host "=== MonitorFix Cleanup (beim Neustart) ===" -ForegroundColor Cyan
Write-Host ""

# Prüfen ob Verzeichnis existiert
if (-not (Test-Path $targetPath)) {
    Write-Host "Verzeichnis existiert nicht: $targetPath" -ForegroundColor Yellow
    exit 0
}

Write-Host "Plant Löschung beim nächsten Neustart:" -ForegroundColor Yellow
Write-Host "  $targetPath" -ForegroundColor White
Write-Host ""

try {
    # Alle Dateien im Verzeichnis finden
    $files = Get-ChildItem -Path $targetPath -Recurse -File -Force

    Write-Host "Markiere $($files.Count) Dateien für Löschung..." -ForegroundColor Cyan

    # MoveFileEx API verwenden via .NET
    Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    public class FileOps {
        [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Auto)]
        public static extern bool MoveFileEx(
            string lpExistingFileName,
            string lpNewFileName,
            int dwFlags
        );
        public const int MOVEFILE_DELAY_UNTIL_REBOOT = 0x4;
    }
"@

    foreach ($file in $files) {
        $result = [FileOps]::MoveFileEx($file.FullName, $null, [FileOps]::MOVEFILE_DELAY_UNTIL_REBOOT)
        if (-not $result) {
            Write-Host "  Warnung: Konnte $($file.Name) nicht markieren" -ForegroundColor Yellow
        }
    }

    # Verzeichnisse markieren (von innen nach außen)
    $dirs = Get-ChildItem -Path $targetPath -Recurse -Directory -Force | Sort-Object -Property FullName -Descending
    $dirs += Get-Item -Path $targetPath

    foreach ($dir in $dirs) {
        $result = [FileOps]::MoveFileEx($dir.FullName, $null, [FileOps]::MOVEFILE_DELAY_UNTIL_REBOOT)
    }

    Write-Host ""
    Write-Host "✓ Löschung geplant!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Das Verzeichnis wird beim nächsten Neustart gelöscht:" -ForegroundColor Cyan
    Write-Host "  $targetPath" -ForegroundColor White
    Write-Host ""
    Write-Host "Neustart jetzt durchführen? (j/n): " -ForegroundColor Yellow -NoNewline

    $answer = Read-Host
    if ($answer -eq "j" -or $answer -eq "J" -or $answer -eq "y" -or $answer -eq "Y") {
        Write-Host "Starte Neustart in 10 Sekunden..." -ForegroundColor Cyan
        Start-Sleep -Seconds 2
        Restart-Computer -Force
    } else {
        Write-Host "Neustart später manuell durchführen." -ForegroundColor Gray
    }

    exit 0

} catch {
    Write-Host "✗ Fehler: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
