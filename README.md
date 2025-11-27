# DisplayUtilLive - Monitor-Hertz-Änderung für baramundi

DLL zur Änderung der Bildwiederholfrequenz aller Monitore (GPU + DisplayLink) unter Windows.

## Übersicht

**DisplayUtilLive.dll** bietet eine einfache API zur Live-Änderung der Monitor-Frequenz:
- Funktioniert mit allen GPU-Typen (Intel, NVIDIA, AMD, DisplayLink)
- Keine Treiber-spezifische Logik erforderlich
- Windows API (EnumDisplaySettings, ChangeDisplaySettingsEx)
- Validierung vor Änderung (CDS_TEST)
- Detaillierte Fehlerbehandlung

---

## Dateien

```
DisplayUtilLive/
├── DisplayUtilLive.cs         # C# Quellcode
├── DisplayUtilLive.csproj     # Visual Studio Projekt
├── DisplayUtilLive.sln        # Visual Studio Solution
├── Build-DLL.ps1              # Automatisches Build-Script
├── Test-DLL.ps1               # Test-Script für die DLL
├── README.md                  # Diese Datei
└── bin/
    └── DisplayUtilLive.dll    # Kompilierte DLL (nach Build)
```

---

## Kompilieren

### Option 1: PowerShell Build-Script (empfohlen)

```powershell
# Kompiliert automatisch die DLL
.\Build-DLL.ps1

# Debug-Build
.\Build-DLL.ps1 -Configuration Debug

# Ausgabe in benutzerdefinierten Ordner
.\Build-DLL.ps1 -OutputPath "C:\Output"
```

**Voraussetzungen:**
- .NET Framework 4.7+ SDK oder
- Visual Studio 2019/2022 (beliebige Edition)

Das Script findet automatisch `csc.exe` in den üblichen Pfaden.

### Option 2: Visual Studio

1. Öffnen Sie `DisplayUtilLive.sln` in Visual Studio
2. Build → Build Solution (Ctrl+Shift+B)
3. DLL befindet sich in `bin\DisplayUtilLive.dll`

### Option 3: Kommandozeile (manuell)

```cmd
# csc.exe finden (z.B. in C:\Windows\Microsoft.NET\Framework64\v4.0.30319\)
csc /target:library /out:bin\DisplayUtilLive.dll DisplayUtilLive.cs
```

---

## Testen

```powershell
# Test 1: Nur Status anzeigen (kein Admin erforderlich)
.\Test-DLL.ps1

# Test 2: Frequenz ändern auf 60 Hz (als Admin ausführen!)
.\Test-DLL.ps1 -TestFrequency 60

# Test 3: Mit ausführlicher Ausgabe
.\Test-DLL.ps1 -TestFrequency 144 -Verbose
```

**Wichtig:** Frequenz-Änderungen erfordern Administrator-Rechte!

---

## API-Dokumentation

### SetGPUMonitorsTo(int hz)

Setzt alle aktiven Monitore auf die angegebene Frequenz.

```csharp
[DisplayUtilLive]::SetGPUMonitorsTo(60)
```

**Parameter:**
- `hz`: Frequenz in Hertz (1-500)

**Verhalten:**
- Iteriert über alle aktiven Displays
- Prüft Unterstützung mit CDS_TEST
- Ändert nur Frequenz, behält Auflösung/Farbtiefe bei
- Wirft Exception bei Fehlern

**Rückgabe:**
- Konsolenausgabe mit Erfolg/Fehler pro Monitor
- Exception wenn mindestens ein Monitor fehlschlägt

### GetCurrentStatus()

Zeigt aktuelle Konfiguration aller Monitore.

```csharp
[DisplayUtilLive]::GetCurrentStatus()
```

**Ausgabe:**
```
=== Aktuelle Monitor-Konfiguration ===

\\.\DISPLAY1:
  Name: Intel(R) UHD Graphics 620
  ID: PCI\VEN_8086&DEV_5917...
  Auflösung: 1920x1080
  Frequenz: 60 Hz
  Farbtiefe: 32 bit

\\.\DISPLAY2:
  Name: DisplayLink USB Device
  ...
```

### ListSupportedModes(string deviceName)

Listet alle verfügbaren Modi für einen Monitor (Debug).

```csharp
[DisplayUtilLive]::ListSupportedModes("\\\\.\\DISPLAY1")
```

---

## Verwendung in PowerShell

### Beispiel 1: DLL laden und verwenden

```powershell
# DLL laden
Add-Type -Path "C:\baramundi\Files\bin\DisplayUtilLive.dll"

# Aktuellen Status anzeigen
[DisplayUtilLive]::GetCurrentStatus()

# Frequenz ändern
try {
    [DisplayUtilLive]::SetGPUMonitorsTo(60)
    Write-Host "Erfolg: Alle Monitore auf 60 Hz gesetzt"
} catch {
    Write-Error "Fehler: $($_.Exception.Message)"
}
```

### Beispiel 2: Mit Fehlerbehandlung

```powershell
param([int]$Hz = 60)

$dllPath = "$env:ProgramData\baramundi\Files\DisplayUtilLive.dll"

try {
    Add-Type -Path $dllPath -ErrorAction Stop
    [DisplayUtilLive]::SetGPUMonitorsTo($Hz)
    exit 0
} catch {
    Write-Error "Fehler: $($_.Exception.Message)"
    exit 1
}
```

---

## Integration in baramundi

### Paketstruktur

```
Set-Hertz-AllDisplays (Package)/
├── Files/
│   ├── bin/
│   │   └── DisplayUtilLive.dll
│   └── scripts/
│       ├── 01_set_registry_displaylink.ps1
│       ├── 02_gpu_change.ps1
│       └── 03_displaylink_reload.ps1
```

### Step 1: Registry (DisplayLink)

**Datei:** `01_set_registry_displaylink.ps1`

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
            Write-Output "Registry: $regPath\DisplayFrequency = $Hz"
        }
    }
exit 0
```

**baramundi Settings:**
- Execution: System
- Timeout: 30s
- ExitCode 0 = Success

### Step 2: GPU-Änderung

**Datei:** `02_gpu_change.ps1`

```powershell
param([int]$Hz = 60)

$dllPath = "$env:ProgramData\baramundi\Files\Set-Hertz-AllDisplays\bin\DisplayUtilLive.dll"

try {
    Add-Type -Path $dllPath -ErrorAction Stop
    [DisplayUtilLive]::SetGPUMonitorsTo($Hz)
    Write-Output "GPU: Frequenz auf $Hz Hz gesetzt"
    exit 0
} catch {
    Write-Error "Fehler: $($_.Exception.Message)"
    exit 1
}
```

**baramundi Settings:**
- Execution: System (oder Administrator)
- Timeout: 120s
- ExitCode 0 = Success, 1 = Failed

### Step 3: DisplayLink Live-Reload

**Datei:** `03_displaylink_reload.ps1`

```powershell
param([int]$Hz = 60)

$dl = Get-CimInstance Win32_VideoController |
      Where-Object { $_.Name -like '*DisplayLink*' }

if (-not $dl) {
    Write-Output "Keine DisplayLink-Controller gefunden"
    exit 0
}

foreach ($dev in $dl) {
    $id = $dev.PNPDeviceID
    try {
        Disable-PnpDevice -InstanceId $id -Confirm:$false -ErrorAction Stop
        Start-Sleep -Seconds 1
        Enable-PnpDevice  -InstanceId $id -Confirm:$false -ErrorAction Stop
        Start-Sleep -Milliseconds 800
        Write-Output "Live-Reload: $($dev.Name)"
    } catch {
        Write-Warning "Fehler bei Live-Reload: $($_.Exception.Message)"
    }
}
exit 0
```

**baramundi Settings:**
- Execution: System
- Timeout: 60s
- ExitCode 0 = Success (auch bei Warnings)

### Step-Reihenfolge in bMS

1. **Registry** (DisplayLink DisplayFrequency setzen)
2. **GPU-Change** (DLL: SetGPUMonitorsTo)
3. **DisplayLink Reload** (PnP Disable/Enable)
4. **Optional: Reboot** (falls erforderlich)

---

## Fehlerbehebung

### DLL kann nicht geladen werden

**Fehler:**
```
Add-Type: Datei oder Assembly ... konnte nicht geladen werden
```

**Lösung:**
1. Prüfen ob DLL existiert: `Test-Path $dllPath`
2. Prüfen ob .NET Framework 4.7+ installiert ist
3. DLL entsperren: `Unblock-File -Path $dllPath`

### csc.exe nicht gefunden

**Fehler:**
```
C# Compiler (csc.exe) nicht gefunden!
```

**Lösung:**
Installieren Sie eine der folgenden Komponenten:
- .NET Framework 4.7+ SDK: https://dotnet.microsoft.com/download/dotnet-framework
- Visual Studio 2022: https://visualstudio.microsoft.com/downloads/

### SetGPUMonitorsTo wirft Exception

**Fehler:**
```
X Monitor(e) konnten nicht geändert werden
```

**Mögliche Ursachen:**
1. Monitor unterstützt gewünschte Frequenz nicht
   - Lösung: Prüfen mit `ListSupportedModes()`
2. Keine Admin-Rechte
   - Lösung: Script als Administrator/System ausführen
3. Monitor ist DisplayLink (erfordert zusätzlich Registry + Reload)
   - Lösung: Alle 3 Steps ausführen

### DisplayLink-Frequenz bleibt bei alter Rate

**Ursache:** DisplayLink liest Frequenz aus Registry, nicht aus DEVMODE

**Lösung:**
1. Step 1 (Registry) MUSS ausgeführt werden
2. Step 3 (Reload) MUSS nach Registry-Änderung ausgeführt werden
3. Reihenfolge: Registry → GPU → Reload

---

## Technische Details

### Windows API Aufrufe

Die DLL verwendet folgende Win32-APIs:

1. **EnumDisplayDevices:** Listet alle Display-Geräte
2. **EnumDisplaySettings:** Liest aktuelle/verfügbare Modi
3. **ChangeDisplaySettingsEx:** Ändert Display-Einstellungen

### DEVMODE-Struktur

Wichtige Felder für Frequenz-Änderung:
```csharp
dmFields = DM_DISPLAYFREQUENCY | DM_PELSWIDTH | DM_PELSHEIGHT | DM_BITSPERPEL
dmDisplayFrequency = 60  // Neue Frequenz
dmPelsWidth = 1920       // Beibehaltene Auflösung
dmPelsHeight = 1080
dmBitsPerPel = 32
```

### CDS_TEST-Validierung

Vor jeder Änderung wird geprüft ob der Modus unterstützt wird:
```csharp
ChangeDisplaySettingsEx(deviceName, ref devMode, IntPtr.Zero, CDS_TEST, IntPtr.Zero)
```

Nur bei `DISP_CHANGE_SUCCESSFUL` wird tatsächlich geändert.

### Besonderheiten DisplayLink

DisplayLink speichert Frequenz in Registry:
```
HKLM\SYSTEM\CurrentControlSet\Enum\{PNPDeviceID}\Device Parameters\DisplayFrequency
```

Daher:
1. Registry-Wert setzen
2. GPU-Änderung (setzt DEVMODE)
3. PnP-Reload (lädt neue Einstellungen)

---

## Systemanforderungen

- Windows 10/11 (oder Server 2016+)
- .NET Framework 4.7.2+ (für DLL)
- PowerShell 5.1+ (für Scripts)
- Administrator-Rechte (für Frequenz-Änderungen)

---

## Lizenz

Dieses Projekt ist für den internen Gebrauch mit baramundi Management Suite bestimmt.

---

## Support & Debugging

### Logging aktivieren

```powershell
$VerbosePreference = 'Continue'
.\Test-DLL.ps1 -TestFrequency 60 -Verbose
```

### Diagnose-Befehle

```powershell
# Alle Displays anzeigen
Get-CimInstance Win32_VideoController | Select-Object Name, VideoProcessor, PNPDeviceID

# DisplayLink-Geräte finden
Get-CimInstance Win32_VideoController | Where-Object { $_.Name -like '*DisplayLink*' }

# Registry prüfen (DisplayLink)
Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Enum\{PNPDeviceID}\Device Parameters"
```

---

## Weiterführende Dokumentation

- Windows Display Settings API: https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-changedisplaysettingsexa
- baramundi Automation Studio: https://www.baramundi.com/de/support/
- DisplayLink SDK: https://www.synaptics.com/products/displaylink-graphics

---

**Version:** 1.0
**Erstellt:** 2025-01-26
**Autor:** DisplayUtilLive Team
