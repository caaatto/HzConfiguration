# DisplayUtilLive - baramundi Integration

Schnellanleitung zur Integration in baramundi Management Suite.

## 1. Paket-Struktur vorbereiten

```
Set-Hertz-AllDisplays/
├── Files/
│   ├── bin/
│   │   └── DisplayUtilLive.dll       ← Kompilierte DLL hier ablegen
│   └── scripts/
│       ├── 01_registry.ps1
│       ├── 02_gpu_change.ps1
│       └── 03_displaylink_reload.ps1
```

## 2. PowerShell-Scripts für baramundi

### Script 1: Registry (DisplayLink)

**Datei:** `01_registry.ps1`

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

**baramundi Settings:**
- Run as: System
- Timeout: 30s
- Exit 0 = Success

---

### Script 2: GPU-Änderung (DLL)

**Datei:** `02_gpu_change.ps1`

```powershell
param([int]$Hz = 60)

# Pfad zur DLL (baramundi-Paketordner)
$dllPath = "$env:ProgramData\baramundi\Files\Set-Hertz-AllDisplays\bin\DisplayUtilLive.dll"

# Fallback: lokaler Pfad
if (-not (Test-Path $dllPath)) {
    $dllPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..\bin\DisplayUtilLive.dll"
}

try {
    # DLL laden
    Add-Type -Path $dllPath -ErrorAction Stop

    # Frequenz ändern
    [DisplayUtilLive]::SetGPUMonitorsTo($Hz)

    Write-Output "GPU: Alle Monitore auf $Hz Hz gesetzt"
    exit 0

} catch {
    Write-Error "Fehler: $($_.Exception.Message)"
    exit 1
}
```

**baramundi Settings:**
- Run as: System (oder Administrator)
- Timeout: 120s
- Exit 0 = Success, Exit 1 = Failed

---

### Script 3: DisplayLink Live-Reload

**Datei:** `03_displaylink_reload.ps1`

```powershell
param([int]$Hz = 60)

$displayLink = Get-CimInstance Win32_VideoController |
               Where-Object { $_.Name -like '*DisplayLink*' }

if (-not $displayLink) {
    Write-Output "Keine DisplayLink-Controller gefunden (normal bei Intel/NVIDIA/AMD-only)"
    exit 0
}

foreach ($dev in $displayLink) {
    $id = $dev.PNPDeviceID

    try {
        # Disable
        Disable-PnpDevice -InstanceId $id -Confirm:$false -ErrorAction Stop
        Start-Sleep -Seconds 1

        # Enable
        Enable-PnpDevice -InstanceId $id -Confirm:$false -ErrorAction Stop
        Start-Sleep -Milliseconds 800

        Write-Output "Live-Reload: $($dev.Name) erfolgreich"

    } catch {
        Write-Warning "Live-Reload fehlgeschlagen: $($_.Exception.Message)"
        # Kein harter Fehler, da nicht-kritisch
    }
}

exit 0
```

**baramundi Settings:**
- Run as: System
- Timeout: 60s
- Exit 0 = Success (auch bei Warnings)

---

## 3. baramundi Automation Studio Setup

### Package erstellen

1. **Automation Studio** öffnen
2. **New Distribution Package** → Name: `Set-Hertz-AllDisplays`
3. **Files Tab:** DLL und Scripts hochladen
4. **Steps Tab:** PowerShell-Steps hinzufügen

### Steps konfigurieren

#### Step 1: Registry
- **Type:** PowerShell Script
- **Script:** `01_registry.ps1`
- **Parameters:** `-Hz 60`
- **Execution Account:** System
- **Timeout:** 30s
- **On Failure:** Continue (non-critical für Systeme ohne DisplayLink)

#### Step 2: GPU Change
- **Type:** PowerShell Script
- **Script:** `02_gpu_change.ps1`
- **Parameters:** `-Hz 60`
- **Execution Account:** System
- **Timeout:** 120s
- **On Failure:** Mark Package Failed

#### Step 3: DisplayLink Reload
- **Type:** PowerShell Script
- **Script:** `03_displaylink_reload.ps1`
- **Parameters:** `-Hz 60`
- **Execution Account:** System
- **Timeout:** 60s
- **On Failure:** Continue (non-critical)

### Parameter-Variablen (optional)

Für dynamische Hz-Werte:

```
Variable Name: TARGET_HZ
Default Value: 60
Type: Integer
```

In Steps verwenden: `-Hz $(TARGET_HZ)`

---

## 4. Deployment

### Zielgruppen

Erstellen Sie Device-Gruppen nach Monitor-Setup:

- **Group 1:** Standard (60 Hz)
- **Group 2:** Gaming (144 Hz)
- **Group 3:** DisplayLink-Docks (60 Hz mit Live-Reload)

### Job erstellen

1. **New Job** → Type: Software Distribution
2. **Package:** Set-Hertz-AllDisplays
3. **Targets:** Device Group auswählen
4. **Parameters:** `-Hz 60` (oder 144, etc.)
5. **Schedule:** Sofort oder Wartungsfenster

---

## 5. Troubleshooting

### DLL nicht gefunden

**Fehler:**
```
Add-Type: Datei oder Assembly konnte nicht geladen werden
```

**Lösung:**
- Prüfen: `Test-Path $dllPath`
- DLL entsperren: `Unblock-File -Path $dllPath`
- Pfad korrigieren (baramundi-spezifischer Deployment-Pfad)

### Keine Admin-Rechte

**Fehler:**
```
ChangeDisplaySettingsEx failed
```

**Lösung:**
- Step-Execution auf "System" oder "Administrator" setzen
- baramundi-Agent läuft als System (normalerweise OK)

### DisplayLink-Frequenz bleibt alt

**Ursache:** DisplayLink liest Registry, nicht DEVMODE

**Lösung:**
- Step 1 (Registry) MUSS ausgeführt werden
- Step 3 (Reload) MUSS nach Registry erfolgen
- Reihenfolge: Registry → GPU → Reload

---

## 6. Logging & Monitoring

### baramundi-Logs

```
C:\ProgramData\baramundi\Logs\SoftwareAgent\
```

### Custom Logging (optional)

Fügen Sie in Scripts hinzu:

```powershell
$logPath = "C:\ProgramData\SetHertz\logs\$(hostname).log"
$logDir = Split-Path $logPath -Parent

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Starting Hz change to $Hz" | Out-File $logPath -Append
```

### Validierung (Post-Script)

```powershell
# Nach GPU-Änderung: Status ausgeben
[DisplayUtilLive]::GetCurrentStatus()
```

---

## 7. Erweiterte Szenarien

### Szenario A: Nur bestimmte Monitore

```powershell
# In 02_gpu_change.ps1: Vor [DisplayUtilLive]::SetGPUMonitorsTo()
$monitors = Get-CimInstance Win32_VideoController |
            Where-Object { $_.Name -like '*NVIDIA*' -or $_.Name -like '*DisplayLink*' }

if ($monitors.Count -eq 0) {
    Write-Output "Keine relevanten Monitore gefunden"
    exit 0
}

# Dann: SetGPUMonitorsTo aufrufen
```

### Szenario B: Rollback bei Fehler

```powershell
# Aktuelle Hz speichern VOR Änderung
$currentHz = (Get-CimInstance Win32_VideoController | Select-Object -First 1).CurrentRefreshRate

try {
    [DisplayUtilLive]::SetGPUMonitorsTo($Hz)
} catch {
    Write-Warning "Rollback auf $currentHz Hz"
    [DisplayUtilLive]::SetGPUMonitorsTo($currentHz)
    exit 1
}
```

### Szenario C: Conditional Reboot

```powershell
# Nach GPU-Änderung: Prüfen ob Neustart nötig
$output = [DisplayUtilLive]::SetGPUMonitorsTo($Hz) 2>&1
if ($output -match 'erfordert Neustart') {
    Write-Output "Neustart erforderlich - bitte in baramundi konfigurieren"
    exit 2  # Custom Exit-Code für Reboot
}
```

---

## 8. Best Practices

1. **Testing:**
   - Testen Sie auf einem Testgerät BEVOR Sie auf Produktion deployen
   - Verwenden Sie verschiedene Monitor-Setups (Intel, NVIDIA, DisplayLink)

2. **Wartungsfenster:**
   - Planen Sie Deployments außerhalb der Geschäftszeiten
   - Nutzen Sie baramundi-Wartungsfenster

3. **Rollback-Plan:**
   - Dokumentieren Sie die Original-Hz-Werte
   - Erstellen Sie ein "Restore 60 Hz"-Paket als Fallback

4. **Monitoring:**
   - Überwachen Sie Job-Status in baramundi
   - Sammeln Sie Logs für Fehleranalyse

5. **Dokumentation:**
   - Dokumentieren Sie welche Device-Groups welche Hz-Werte bekommen
   - Informieren Sie Benutzer über geplante Änderungen

---

## Support

Bei Problemen:

1. **baramundi-Logs prüfen:** `C:\ProgramData\baramundi\Logs\`
2. **DLL manuell testen:** `.\Test-DLL.ps1 -TestFrequency 60`
3. **Windows Event Log:** `eventvwr.msc` → Application

**Kontakt:** Siehe README.md für weitere Informationen
