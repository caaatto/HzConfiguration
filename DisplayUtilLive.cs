using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;

/// <summary>
/// DisplayUtilLive: Setzt die Bildwiederholfrequenz für alle aktiven Monitore
/// Kompilieren als DLL: csc /target:library /out:DisplayUtilLive.dll DisplayUtilLive.cs
/// oder in Visual Studio als Class Library (.NET Framework 4.7+)
/// </summary>
public static class DisplayUtilLive
{
    #region Windows API Imports

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private struct DEVMODE
    {
        private const int CCHDEVICENAME = 32;
        private const int CCHFORMNAME = 32;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = CCHDEVICENAME)]
        public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int dmFields;

        public int dmPositionX;
        public int dmPositionY;
        public int dmDisplayOrientation;
        public int dmDisplayFixedOutput;

        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = CCHFORMNAME)]
        public string dmFormName;

        public short dmLogPixels;
        public int dmBitsPerPel;
        public int dmPelsWidth;
        public int dmPelsHeight;
        public int dmDisplayFlags;
        public int dmDisplayFrequency;

        public int dmICMMethod;
        public int dmICMIntent;
        public int dmMediaType;
        public int dmDitherType;
        public int dmReserved1;
        public int dmReserved2;
        public int dmPanningWidth;
        public int dmPanningHeight;
    }

    private const int ENUM_CURRENT_SETTINGS = -1;
    private const int CDS_UPDATEREGISTRY = 0x01;
    private const int CDS_TEST = 0x02;
    private const int DISP_CHANGE_SUCCESSFUL = 0;
    private const int DISP_CHANGE_RESTART = 1;
    private const int DISP_CHANGE_BADMODE = -2;

    private const int DM_DISPLAYFREQUENCY = 0x00400000;
    private const int DM_PELSWIDTH = 0x00080000;
    private const int DM_PELSHEIGHT = 0x00100000;
    private const int DM_BITSPERPEL = 0x00040000;

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    private static extern bool EnumDisplayDevices(
        string lpDevice,
        uint iDevNum,
        ref DISPLAY_DEVICE lpDisplayDevice,
        uint dwFlags);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    private static extern bool EnumDisplaySettings(
        string lpszDeviceName,
        int iModeNum,
        ref DEVMODE lpDevMode);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    private static extern int ChangeDisplaySettingsEx(
        string lpszDeviceName,
        ref DEVMODE lpDevMode,
        IntPtr hwnd,
        uint dwflags,
        IntPtr lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private struct DISPLAY_DEVICE
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

    private const int DISPLAY_DEVICE_ACTIVE = 0x00000001;
    private const int DISPLAY_DEVICE_ATTACHED_TO_DESKTOP = 0x00000001;

    #endregion

    /// <summary>
    /// Setzt die Bildwiederholfrequenz für alle aktiven Monitore auf den angegebenen Wert
    /// </summary>
    /// <param name="hz">Gewünschte Frequenz in Hertz (z.B. 60, 120, 144)</param>
    public static void SetGPUMonitorsTo(int hz)
    {
        if (hz <= 0 || hz > 500)
        {
            throw new ArgumentException(string.Format("Ungültige Frequenz: {0} Hz. Erlaubt: 1-500 Hz.", hz));
        }

        List<string> results = new List<string>();
        List<string> errors = new List<string>();

        // Alle Display-Devices durchlaufen
        uint deviceIndex = 0;
        DISPLAY_DEVICE device = new DISPLAY_DEVICE();
        device.cb = Marshal.SizeOf(device);

        while (EnumDisplayDevices(null, deviceIndex, ref device, 0))
        {
            // Nur aktive, angeschlossene Displays
            if ((device.StateFlags & DISPLAY_DEVICE_ACTIVE) != 0 &&
                (device.StateFlags & DISPLAY_DEVICE_ATTACHED_TO_DESKTOP) != 0)
            {
                try
                {
                    string message;
                    bool success = SetMonitorRefreshRate(device.DeviceName, hz, out message);
                    if (success)
                    {
                        results.Add(string.Format("✓ {0} ({1}): {2}", device.DeviceName, device.DeviceString, message));
                    }
                    else
                    {
                        errors.Add(string.Format("✗ {0} ({1}): {2}", device.DeviceName, device.DeviceString, message));
                    }
                }
                catch (Exception ex)
                {
                    errors.Add(string.Format("✗ {0}: Exception - {1}", device.DeviceName, ex.Message));
                }
            }

            deviceIndex++;
            device = new DISPLAY_DEVICE();
            device.cb = Marshal.SizeOf(device);
        }

        // Ausgabe
        Console.WriteLine(string.Format("\n=== SetGPUMonitorsTo({0} Hz) ===", hz));
        Console.WriteLine(string.Format("Erfolgreiche Änderungen: {0}", results.Count));
        foreach (var r in results)
        {
            Console.WriteLine(r);
        }

        if (errors.Count > 0)
        {
            Console.WriteLine(string.Format("\nFehler: {0}", errors.Count));
            foreach (var e in errors)
            {
                Console.WriteLine(e);
            }
            throw new InvalidOperationException(string.Format("{0} Monitor(e) konnten nicht geändert werden.", errors.Count));
        }
    }

    /// <summary>
    /// Setzt die Bildwiederholfrequenz für einen spezifischen Monitor
    /// </summary>
    private static bool SetMonitorRefreshRate(string deviceName, int hz, out string message)
    {
        DEVMODE currentMode = new DEVMODE();
        currentMode.dmSize = (short)Marshal.SizeOf(currentMode);

        // Aktuelle Einstellungen abrufen
        if (!EnumDisplaySettings(deviceName, ENUM_CURRENT_SETTINGS, ref currentMode))
        {
            message = "EnumDisplaySettings fehlgeschlagen";
            return false;
        }

        // Prüfen ob die gewünschte Frequenz bereits gesetzt ist
        if (currentMode.dmDisplayFrequency == hz)
        {
            message = string.Format("bereits auf {0} Hz (keine Änderung nötig)", hz);
            return true;
        }

        // Neue Frequenz setzen
        int originalFreq = currentMode.dmDisplayFrequency;
        currentMode.dmDisplayFrequency = hz;
        currentMode.dmFields = DM_DISPLAYFREQUENCY | DM_PELSWIDTH | DM_PELSHEIGHT | DM_BITSPERPEL;

        // Erst testen ob der Modus unterstützt wird
        int testResult = ChangeDisplaySettingsEx(
            deviceName,
            ref currentMode,
            IntPtr.Zero,
            CDS_TEST,
            IntPtr.Zero);

        if (testResult != DISP_CHANGE_SUCCESSFUL)
        {
            message = string.Format("{0} Hz → {1} Hz NICHT unterstützt (CDS_TEST failed)", originalFreq, hz);
            return false;
        }

        // Nun tatsächlich ändern
        int changeResult = ChangeDisplaySettingsEx(
            deviceName,
            ref currentMode,
            IntPtr.Zero,
            CDS_UPDATEREGISTRY,
            IntPtr.Zero);

        switch (changeResult)
        {
            case DISP_CHANGE_SUCCESSFUL:
                message = string.Format("{0} Hz → {1} Hz erfolgreich", originalFreq, hz);
                return true;

            case DISP_CHANGE_RESTART:
                message = string.Format("{0} Hz → {1} Hz erfordert Neustart", originalFreq, hz);
                return true; // Als Erfolg werten, aber Hinweis

            case DISP_CHANGE_BADMODE:
                message = string.Format("{0} Hz → {1} Hz ungültiger Modus", originalFreq, hz);
                return false;

            default:
                message = string.Format("{0} Hz → {1} Hz Fehler (Code: {2})", originalFreq, hz, changeResult);
                return false;
        }
    }

    /// <summary>
    /// Gibt alle verfügbaren Display-Modi für einen Monitor aus (Debug-Methode)
    /// </summary>
    public static void ListSupportedModes(string deviceName)
    {
        Console.WriteLine(string.Format("\nVerfügbare Modi für {0}:", deviceName));
        DEVMODE mode = new DEVMODE();
        mode.dmSize = (short)Marshal.SizeOf(mode);
        int modeIndex = 0;

        HashSet<string> uniqueModes = new HashSet<string>();

        while (EnumDisplaySettings(deviceName, modeIndex, ref mode))
        {
            string modeStr = string.Format("{0}x{1} @ {2} Hz ({3} bit)", mode.dmPelsWidth, mode.dmPelsHeight, mode.dmDisplayFrequency, mode.dmBitsPerPel);
            uniqueModes.Add(modeStr);
            modeIndex++;
        }

        foreach (var m in uniqueModes)
        {
            Console.WriteLine(string.Format("  - {0}", m));
        }
    }

    /// <summary>
    /// Gibt den aktuellen Status aller Monitore aus (Debug-Methode)
    /// </summary>
    public static void GetCurrentStatus()
    {
        Console.WriteLine("\n=== Aktuelle Monitor-Konfiguration ===");

        uint deviceIndex = 0;
        DISPLAY_DEVICE device = new DISPLAY_DEVICE();
        device.cb = Marshal.SizeOf(device);

        while (EnumDisplayDevices(null, deviceIndex, ref device, 0))
        {
            if ((device.StateFlags & DISPLAY_DEVICE_ACTIVE) != 0)
            {
                DEVMODE currentMode = new DEVMODE();
                currentMode.dmSize = (short)Marshal.SizeOf(currentMode);

                if (EnumDisplaySettings(device.DeviceName, ENUM_CURRENT_SETTINGS, ref currentMode))
                {
                    Console.WriteLine(string.Format("\n{0}:", device.DeviceName));
                    Console.WriteLine(string.Format("  Name: {0}", device.DeviceString));
                    Console.WriteLine(string.Format("  ID: {0}", device.DeviceID));
                    Console.WriteLine(string.Format("  Auflösung: {0}x{1}", currentMode.dmPelsWidth, currentMode.dmPelsHeight));
                    Console.WriteLine(string.Format("  Frequenz: {0} Hz", currentMode.dmDisplayFrequency));
                    Console.WriteLine(string.Format("  Farbtiefe: {0} bit", currentMode.dmBitsPerPel));
                }
            }

            deviceIndex++;
            device = new DISPLAY_DEVICE();
            device.cb = Marshal.SizeOf(device);
        }
    }
}
