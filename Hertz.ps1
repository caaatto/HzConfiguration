<#
.SYNOPSIS
    Setzt die Bildwiederholrate (Hz) live für alle Monitore.
.DESCRIPTION
    - GPU-Monitore (Intel/NVIDIA/AMD) werden auf den aktuellen Modus mit gewünschter Hz umgestellt (wenn verfügbar).
    - DisplayLink-Monitore: Registry-Eintrag "DisplayFrequency" wird gesetzt und das Gerät wird kurz deaktiviert/aktiviert (Live-Reload).
    - Vermeidet Add-Type Konflikte und C#-String-Interpolation-Probleme.
.EXAMPLE
    .\Hertz.ps1 60
#>

param([int]$refresh = 60)

Write-Host "==============================" -ForegroundColor Cyan
Write-Host "  Erzwinge $refresh Hz auf allen Monitoren (LIVE)" -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan

# -----------------------------
# 0. DLL laden von C:\Local\MonitorFix\deploy\Files
# -----------------------------
$dllPath = "C:\Local\MonitorFix\deploy\Files\DisplayUtilLive.dll"

# Prüfen, ob die DLL existiert
if (-not (Test-Path $dllPath)) {
    Write-Host "FEHLER: DLL nicht gefunden!" -ForegroundColor Red
    Write-Host "Erwartet: $dllPath" -ForegroundColor Yellow
    Write-Host "`nBitte sicherstellen, dass:" -ForegroundColor Yellow
    Write-Host "  1. Die DLL kompiliert wurde (Build-DLL.ps1 oder Build.bat)" -ForegroundColor Gray
    Write-Host "  2. Die DLL nach C:\Local\MonitorFix\deploy\Files kopiert wurde" -ForegroundColor Gray
    exit 1
}

# Prüfen, ob der Typ bereits geladen ist
$needAddType = $true
try {
    $null = [DisplayUtilLive]
    $needAddType = $false
    Write-Host "DLL bereits geladen — Add-Type übersprungen." -ForegroundColor DarkYellow
} catch {
    $needAddType = $true
}

# DLL laden
if ($needAddType) {
    try {
        Write-Host "Lade DLL von: $dllPath" -ForegroundColor Cyan
        Add-Type -Path $dllPath -ErrorAction Stop
        Write-Host "✓ DLL erfolgreich geladen" -ForegroundColor Green
    } catch {
        Write-Host "FEHLER beim Laden der DLL: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

try {
    [DisplayUtilLive]::SetGPUMonitorsTo($refresh)
} catch {
    Write-Host "Fehler beim Setzen der GPU-Monitore: $($_.Exception.Message)" -ForegroundColor Red
}


# Suche DisplayLink über Win32_VideoController
$displaylink = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -like "*DisplayLink*" }

if (!$displaylink -or $displaylink.Count -eq 0) {
    Write-Host "`nKeine DisplayLink-Video-Controller gefunden." -ForegroundColor Yellow
} else {
    Write-Host "`nDisplayLink-Video-Controller gefunden:" -ForegroundColor Cyan
    $displaylink | ForEach-Object { Write-Host " → $($_.Name)  PNP: $($_.PNPDeviceID)" }

    foreach ($dev in $displaylink) {
        # PNPDeviceID kann z.B. "USB\VID_17E9&PID_..." sein
        $pnp = $dev.PNPDeviceID
        # Registry-Pfad zur Device-Parameters für den Enum-Eintrag
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$pnp`\\Device Parameters"

        # Manche Systeme haben andere Pfadstrukturen - versuche robust:
        if (!(Test-Path $regPath)) {
            # versuchen ohne "\Device Parameters" direkt die Enum-Node zu finden und dranhängen
            $enumBase = "HKLM:\SYSTEM\CurrentControlSet\Enum\$pnp"
            if (Test-Path $enumBase) {
                $regPath = Join-Path $enumBase "Device Parameters"
            }
        }

        if (Test-Path $regPath) {
            Write-Host "→ Setze Registry für $($dev.Name) auf $refresh Hz ..."
            try {
                Set-ItemProperty -Path $regPath -Name "DisplayFrequency" -Value $refresh -Type DWord -Force
                Write-Host "Registry aktualisiert."
            } catch {
                Write-Host "Fehler beim Schreiben der Registry: $($_.Exception.Message)" -ForegroundColor Red
            }
        } else {
            Write-Host "Registry-Pfad nicht gefunden für $($dev.Name): $regPath" -ForegroundColor DarkYellow
        }

        # Live reload: Deaktivieren / Aktivieren des PnP-Geräts
        Write-Host "→ Lade DisplayLink neu: $($dev.Name) ..."
        try {
            # Disable/Enable mit PNPDeviceID. Erfordert Admin-Rechte.
            Disable-PnpDevice -InstanceId $pnp -Confirm:$false -ErrorAction Stop
            Start-Sleep -Milliseconds 1000
            Enable-PnpDevice  -InstanceId $pnp -Confirm:$false -ErrorAction Stop
            Start-Sleep -Milliseconds 800
            Write-Host "  Live-Reload erfolgreich." -ForegroundColor Green
        } catch {
            Write-Host "Fehler beim Neu-Laden (Disable/Enable) von $($dev.Name): $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Hinweis: Stelle sicher, dass die PowerShell als Administrator ausgeführt wird."
        }
    }
}

Write-Host "`nAlle erreichbaren Monitore wurden versucht auf $refresh Hz zu setzen." -ForegroundColor Green
Write-Host "Falls einige Monitore noch 70 Hz anzeigen: starte den PC neu." -ForegroundColor Yellow
