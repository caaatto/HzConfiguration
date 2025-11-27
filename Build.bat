@echo off
REM Build-Script (Batch) für DisplayUtilLive.dll
REM Alternativ zu PowerShell Build-DLL.ps1

echo === DisplayUtilLive.dll Build (Batch) ===
echo.

REM Ausgabeverzeichnis erstellen
if not exist "bin" mkdir bin
if exist "bin\DisplayUtilLive.dll" del /f /q "bin\DisplayUtilLive.dll"

REM csc.exe finden
set CSC_PATH=%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe

if not exist "%CSC_PATH%" (
    echo Fehler: csc.exe nicht gefunden!
    echo Pfad: %CSC_PATH%
    echo.
    echo Bitte installieren Sie .NET Framework 4.7+ SDK
    echo Download: https://dotnet.microsoft.com/download/dotnet-framework
    pause
    exit /b 1
)

echo C# Compiler gefunden: %CSC_PATH%
echo.

REM Kompilieren
echo Kompiliere DisplayUtilLive.cs...
"%CSC_PATH%" /target:library /platform:anycpu /optimize+ /out:"bin\DisplayUtilLive.dll" "DisplayUtilLive.cs" /debug:pdbonly

if errorlevel 1 (
    echo.
    echo Kompilierung fehlgeschlagen!
    pause
    exit /b 1
)

echo.
echo === Kompilierung erfolgreich! ===
echo DLL: %~dp0bin\DisplayUtilLive.dll
echo.

REM Dateigröße anzeigen (optional)
for %%F in ("bin\DisplayUtilLive.dll") do echo Groesse: %%~zF Bytes

REM Kopiere nach C:\Local\Files für portable Deployment
echo.
echo Kopiere DLL nach C:\Local\Files...
if not exist "C:\Local\Files\" mkdir "C:\Local\Files\"
copy /Y "bin\DisplayUtilLive.dll" "C:\Local\Files\"
if errorlevel 1 (
    echo FEHLER beim Kopieren nach C:\Local\Files (Admin-Rechte erforderlich?)
) else (
    echo ✓ DLL kopiert nach: C:\Local\Files\DisplayUtilLive.dll
)

echo.
echo Naechste Schritte:
echo   1. DLL testen: powershell -ExecutionPolicy Bypass -File Test-DLL.ps1
echo   2. Hertz-Skript ausfuehren: powershell -ExecutionPolicy Bypass -File Hertz.ps1 60
echo   3. In baramundi-Paket kopieren (falls benoetigt)
echo.
pause
