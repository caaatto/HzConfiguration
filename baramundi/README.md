# baramundi Integration - Monitor Refresh Rate Manager

Diese Scripts sind fertig für die Integration in baramundi. Alle Dateien werden von baramundi nach `C:\Local` kopiert, die Scripts arbeiten direkt mit diesen festen Pfaden.

---

## Deployment-Struktur

baramundi kopiert alle Dateien nach `C:\Local` in diese Struktur:

```
C:\Local\
├── Files\
│   └── DisplayUtilLive.dll
└── (optional: scripts können hier oder woanders liegen)
```

Die Scripts erwarten die DLL unter: **`C:\Local\Files\DisplayUtilLive.dll`**

---

## Script-Übersicht

### 1. `01_registry.ps1` - DisplayLink Registry Setup

**Was es macht:**
- Setzt Registry-Wert `DisplayFrequency` für alle DisplayLink-Geräte
- Muss VOR `02_gpu_change.ps1` ausgeführt werden
- Harmlos für Systeme ohne DisplayLink (Exit Code 0)

**Aufruf:**
```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\Local\01_registry.ps1" -Hz 60
```

**Parameter:**
- `-Hz` : Zielfrequenz in Hz (Standard: 60)

**Exit Codes:**
- `0` = Erfolg (oder keine DisplayLink-Geräte gefunden)
- `1` = Fehler beim Setzen der Registry

**baramundi-Einstellungen:**
- **Run as:** System
- **Timeout:** 30s
- **Admin:** Ja

---

### 2. `02_gpu_change.ps1` - GPU Refresh Rate Change

**Was es macht:**
- Lädt `DisplayUtilLive.dll` von `C:\Local\Files\`
- Ändert die Bildwiederholrate aller Monitore (Intel, NVIDIA, AMD, DisplayLink)
- **Dies ist das Hauptscript**

**Aufruf:**
```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\Local\02_gpu_change.ps1" -Hz 60
```

**Parameter:**
- `-Hz` : Zielfrequenz in Hz (Standard: 60)

**Exit Codes:**
- `0` = Erfolg
- `1` = DLL nicht gefunden
- `2` = DLL konnte nicht geladen werden
- `3` = Frequenzänderung fehlgeschlagen

**baramundi-Einstellungen:**
- **Run as:** System
- **Timeout:** 120s
- **Admin:** Ja

---

### 3. `03_displaylink_reload.ps1` - DisplayLink Live Reload

**Was es macht:**
- Deaktiviert und aktiviert DisplayLink-Geräte (PnP-Reload)
- Lädt die neuen Registry-Werte
- Muss NACH `01_registry.ps1` und `02_gpu_change.ps1` laufen
- Harmlos für Systeme ohne DisplayLink (Exit Code 0)

**Aufruf:**
```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\Local\03_displaylink_reload.ps1" -Hz 60
```

**Parameter:**
- `-Hz` : Zielfrequenz in Hz (optional, nur für Logging)

**Exit Codes:**
- `0` = Erfolg (oder keine DisplayLink-Geräte gefunden)
- `1` = Fehler beim Neuladen der Geräte

**baramundi-Einstellungen:**
- **Run as:** System
- **Timeout:** 60s
- **Admin:** Ja

---

## baramundi-Konfiguration

### Option A: Drei getrennte Jobs (empfohlen für Flexibilität)

**Job 1: DisplayLink Registry Setup**
```
Befehl: powershell.exe -ExecutionPolicy Bypass -File "C:\Local\01_registry.ps1" -Hz 60
Run as: System
Timeout: 30s
Reihenfolge: 1
```

**Job 2: GPU Change (Hauptjob)**
```
Befehl: powershell.exe -ExecutionPolicy Bypass -File "C:\Local\02_gpu_change.ps1" -Hz 60
Run as: System
Timeout: 120s
Reihenfolge: 2
Abhängigkeit: Job 1 muss erfolgreich sein (Exit Code 0)
```

**Job 3: DisplayLink Reload**
```
Befehl: powershell.exe -ExecutionPolicy Bypass -File "C:\Local\03_displaylink_reload.ps1" -Hz 60
Run as: System
Timeout: 60s
Reihenfolge: 3
Abhängigkeit: Job 2 muss erfolgreich sein (Exit Code 0)
```

### Option B: Ein kombinierter Job

Erstelle ein Wrapper-Script `Run-All.ps1`:

```powershell
param([int]$Hz = 60)

Write-Output "=== Starting HzConfiguration (3 steps) ==="
Write-Output ""

# Step 1
& "C:\Local\01_registry.ps1" -Hz $Hz
if ($LASTEXITCODE -ne 0) {
    Write-Output "Step 1 failed!"
    exit 1
}

# Step 2
& "C:\Local\02_gpu_change.ps1" -Hz $Hz
if ($LASTEXITCODE -ne 0) {
    Write-Output "Step 2 failed!"
    exit 2
}

# Step 3
& "C:\Local\03_displaylink_reload.ps1" -Hz $Hz
if ($LASTEXITCODE -ne 0) {
    Write-Output "Step 3 failed!"
    exit 3
}

Write-Output ""
Write-Output "=== All steps completed successfully ==="
exit 0
```

**Aufruf:**
```
powershell.exe -ExecutionPolicy Bypass -File "C:\Local\Run-All.ps1" -Hz 60
Run as: System
Timeout: 180s
```

---

## File Deployment in baramundi

### Baustein-Konfiguration

**1. File-Deploy Baustein:**

| Quelle | Ziel |
|--------|------|
| `bin\DisplayUtilLive.dll` | `C:\Local\Files\DisplayUtilLive.dll` |
| `baramundi\01_registry.ps1` | `C:\Local\01_registry.ps1` |
| `baramundi\02_gpu_change.ps1` | `C:\Local\02_gpu_change.ps1` |
| `baramundi\03_displaylink_reload.ps1` | `C:\Local\03_displaylink_reload.ps1` |

**2. Execute Baustein:**

Siehe "baramundi-Konfiguration" oben.

---

## Häufige Szenarien

### Szenario 1: Alle Monitore auf 60 Hz setzen

```
Job: 01_registry.ps1 -Hz 60
Job: 02_gpu_change.ps1 -Hz 60
Job: 03_displaylink_reload.ps1 -Hz 60
```

### Szenario 2: Nur Intel/NVIDIA/AMD (kein DisplayLink)

```
Job: 02_gpu_change.ps1 -Hz 60
```

Script `01_registry.ps1` und `03_displaylink_reload.ps1` geben Exit Code 0 zurück wenn keine DisplayLink-Geräte gefunden werden, daher kannst du alle drei Jobs immer ausführen.

### Szenario 3: Unterschiedliche Frequenzen für verschiedene Computer-Gruppen

Erstelle mehrere Jobs mit unterschiedlichen `-Hz` Parametern:

- **Büro-PCs:** `-Hz 60`
- **Gaming-PCs:** `-Hz 144`
- **Designer-PCs:** `-Hz 75`

---

## Testing

### Manueller Test auf einem Client

1. Dateien nach `C:\Local` kopieren (simuliert baramundi):
```powershell
# Von deinem Build-Verzeichnis
Copy-Item ".\bin\DisplayUtilLive.dll" "C:\Local\Files\DisplayUtilLive.dll" -Force
Copy-Item ".\baramundi\*.ps1" "C:\Local\" -Force
```

2. Scripts ausführen (als Admin):
```powershell
cd C:\Local
.\01_registry.ps1 -Hz 60
.\02_gpu_change.ps1 -Hz 60
.\03_displaylink_reload.ps1 -Hz 60
```

3. Ergebnis prüfen:
```powershell
# Aktuelle Monitor-Konfiguration anzeigen
Add-Type -Path "C:\Local\Files\DisplayUtilLive.dll"
[DisplayUtilLive]::GetCurrentStatus()
```

---

## Troubleshooting

### Problem: "DLL not found"

**Lösung:**
- Prüfe ob baramundi die DLL nach `C:\Local\Files\DisplayUtilLive.dll` kopiert hat
- Führe auf dem Client aus: `Test-Path "C:\Local\Files\DisplayUtilLive.dll"`

### Problem: "Access denied" oder "ChangeDisplaySettingsEx failed"

**Lösung:**
- Scripts müssen als **System** oder **Administrator** ausgeführt werden
- Prüfe baramundi Job-Einstellungen: "Run as: System"

### Problem: DisplayLink bleibt bei alter Frequenz

**Lösung:**
- Reihenfolge ist wichtig: Registry → GPU → Reload
- Alle drei Scripts müssen erfolgreich durchlaufen (Exit Code 0)
- Bei Job-Abhängigkeiten in baramundi sicherstellen, dass Jobs sequenziell laufen

### Problem: Exit Code ungleich 0

**Exit Codes prüfen:**

| Exit Code | Script | Bedeutung |
|-----------|--------|-----------|
| 0 | Alle | Erfolg |
| 1 | 01, 03 | Allgemeiner Fehler |
| 1 | 02 | DLL nicht gefunden |
| 2 | 02 | DLL konnte nicht geladen werden |
| 3 | 02 | Frequenzänderung fehlgeschlagen |

**Logs prüfen:**
- baramundi zeigt die Script-Ausgabe im Job-Log
- Alle Scripts geben aussagekräftige Meldungen aus

---

## Vorteile dieser Lösung

✅ **Keine Suchlogik:** Scripts verwenden feste Pfade unter `C:\Local`
✅ **Keine Kopierfunktionen:** baramundi übernimmt File-Deploy
✅ **Portable:** Funktioniert auf jedem Windows 10/11 ohne Installation
✅ **Robust:** Klare Exit Codes für baramundi-Monitoring
✅ **Flexibel:** Scripts können einzeln oder kombiniert ausgeführt werden
✅ **Sicher:** Validierung und Error-Handling in jedem Script
✅ **Universal:** Unterstützt Intel, NVIDIA, AMD, DisplayLink

---

## Support

**Probleme?**
- Prüfe baramundi Job-Logs für Script-Ausgaben
- Teste Scripts manuell auf einem Client
- Stelle sicher, dass alle Dateien unter `C:\Local` existieren
- Prüfe Admin-Rechte (Run as: System)

**Weitere Informationen:**
- Siehe Haupt-README.md für technische Details
- GitHub: https://github.com/caaatto/HzConfiguration

---

**Bereit für Deployment!** 🚀
