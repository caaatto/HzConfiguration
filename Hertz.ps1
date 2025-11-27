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
# 0. Sicherstellen, dass Add-Type nicht zweimal versucht wird
# -----------------------------
$needAddType = $true
try {
    # Testen, ob der Typ bereits geladen ist
    $null = [DisplayUtilLive]
    $needAddType = $false
} catch {
    $needAddType = $true
}

if ($needAddType) {
    Add-Type -Language CSharp @"
using System;
using System.Runtime.InteropServices;

public class DisplayUtilLive
{
    private const int ENUM_CURRENT_SETTINGS = -1;
    private const int CDS_UPDATEREGISTRY = 0x01;
    private const int CDS_GLOBAL = 0x08;
    private const int DISP_CHANGE_SUCCESSFUL = 0;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DEVMODE
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmDeviceName;
        public short  dmSpecVersion;
        public short  dmDriverVersion;
        public short  dmSize;
        public short  dmDriverExtra;
        public int    dmFields;
        public int    dmPositionX;
        public int    dmPositionY;
        public int    dmPelsWidth;
        public int    dmPelsHeight;
        public int    dmDisplayOrientation;
        public int    dmDisplayFixedOutput;
        public short  dmColor;
        public short  dmDuplex;
        public short  dmYResolution;
        public short  dmTTOption;
        public short  dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmFormName;
        public short  dmLogPixels;
        public int    dmBitsPerPel;
        public int    dmPelsWidth2;
        public int    dmPelsHeight2;
        public int    dmDisplayFlags;
        public int    dmDisplayFrequency;
    }

    [DllImport("user32.dll")]
    private static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);

    [DllImport("user32.dll")]
    private static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);

    [DllImport("user32.dll")]
    private static extern int ChangeDisplaySettingsEx(string deviceName, ref DEVMODE devMode, IntPtr hwnd, uint flags, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DISPLAY_DEVICE
    {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceKey;
    }

    public static void SetGPUMonitorsTo(int refresh)
    {
        DISPLAY_DEVICE d = new DISPLAY_DEVICE();
        d.cb = Marshal.SizeOf(d);
        uint devNum = 0;

        while (EnumDisplayDevices(null, devNum, ref d, 0))
        {
            bool isActive = (d.StateFlags & 0x00000001) != 0;
            bool isDisplayLink = d.DeviceString != null && d.DeviceString.IndexOf("DisplayLink", StringComparison.OrdinalIgnoreCase) >= 0;

            if (isActive && !isDisplayLink)
            {
                // hole aktuellen Modus (Auflösung / BPP)
                DEVMODE cur = new DEVMODE();
                cur.dmSize = (short)Marshal.SizeOf(cur);
                if (!EnumDisplaySettings(d.DeviceName, ENUM_CURRENT_SETTINGS, ref cur))
                {
                    Console.WriteLine(String.Format("→ GPU {0} ({1}) - aktueller Modus konnte nicht gelesen werden.", d.DeviceName, d.DeviceString));
                    devNum++;
                    d.cb = Marshal.SizeOf(d);
                    continue;
                }

                Console.WriteLine(String.Format("→ GPU {0} ({1}) auf {2} Hz ...", d.DeviceName, d.DeviceString, refresh));

                // suche einen Modus mit gleicher Auflösung + BPP + gewünschter Hz
                DEVMODE candidate = new DEVMODE();
                candidate.dmSize = (short)Marshal.SizeOf(candidate);
                int modeIndex = 0;
                bool found = false;

                while (EnumDisplaySettings(d.DeviceName, modeIndex, ref candidate))
                {
                    if (candidate.dmPelsWidth == cur.dmPelsWidth
                        && candidate.dmPelsHeight == cur.dmPelsHeight
                        && candidate.dmBitsPerPel == cur.dmBitsPerPel
                        && candidate.dmDisplayFrequency == refresh)
                    {
                        found = true;
                        break;
                    }
                    modeIndex++;
                }

                if (found)
                {
                    int res = ChangeDisplaySettingsEx(d.DeviceName, ref candidate, IntPtr.Zero,
                        CDS_UPDATEREGISTRY | CDS_GLOBAL, IntPtr.Zero);
                    if (res == DISP_CHANGE_SUCCESSFUL)
                        Console.WriteLine("   ✓ Erfolgreich geändert.");
                    else
                        Console.WriteLine(String.Format("Fehlercode: {0}", res));
                }
                else
                {
                    Console.WriteLine(String.Format("   ⚠ {0} Hz nicht verfügbar für {1} (bei aktueller Auflösung).", refresh, d.DeviceName));
                }
            }

            devNum++;
            d.cb = Marshal.SizeOf(d);
        }
    }
}
"@  # Ende Add-Type
}
else {
    Write-Host "C#-Typ [DisplayUtilLive] bereits geladen — Add-Type übersprungen." -ForegroundColor DarkYellow
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
