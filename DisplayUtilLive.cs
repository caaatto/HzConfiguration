using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;

/// <summary>
/// DisplayUtilLive: Sets the refresh rate for all active monitors
/// Compile as DLL: csc /target:library /out:DisplayUtilLive.dll DisplayUtilLive.cs
/// or in Visual Studio as Class Library (.NET Framework 4.0+)
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
    /// Sets the refresh rate for all active monitors to the specified value
    /// </summary>
    /// <param name="hz">Desired frequency in Hertz (e.g. 60, 120, 144)</param>
    public static void SetAllMonitorsTo(int hz)
    {
        if (hz <= 0 || hz > 500)
        {
            throw new ArgumentException(string.Format("Invalid frequency: {0} Hz. Allowed: 1-500 Hz.", hz));
        }

        List<string> results = new List<string>();
        List<string> errors = new List<string>();

        // Enumerate all display devices
        uint deviceIndex = 0;
        DISPLAY_DEVICE device = new DISPLAY_DEVICE();
        device.cb = Marshal.SizeOf(device);

        while (EnumDisplayDevices(null, deviceIndex, ref device, 0))
        {
            // Only active, attached displays
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

        // Output
        Console.WriteLine(string.Format("\n=== SetAllMonitorsTo({0} Hz) ===", hz));
        Console.WriteLine(string.Format("Successful changes: {0}", results.Count));
        foreach (var r in results)
        {
            Console.WriteLine(r);
        }

        if (errors.Count > 0)
        {
            Console.WriteLine(string.Format("\nErrors: {0}", errors.Count));
            foreach (var e in errors)
            {
                Console.WriteLine(e);
            }
            throw new InvalidOperationException(string.Format("{0} monitor(s) could not be changed.", errors.Count));
        }
    }

    /// <summary>
    /// Sets the refresh rate for a specific monitor
    /// </summary>
    private static bool SetMonitorRefreshRate(string deviceName, int hz, out string message)
    {
        DEVMODE currentMode = new DEVMODE();
        currentMode.dmSize = (short)Marshal.SizeOf(currentMode);

        // Get current settings
        if (!EnumDisplaySettings(deviceName, ENUM_CURRENT_SETTINGS, ref currentMode))
        {
            message = "EnumDisplaySettings failed";
            return false;
        }

        // Check if desired frequency is already set
        if (currentMode.dmDisplayFrequency == hz)
        {
            message = string.Format("already at {0} Hz (no change needed)", hz);
            return true;
        }

        // Set new frequency
        int originalFreq = currentMode.dmDisplayFrequency;
        currentMode.dmDisplayFrequency = hz;
        currentMode.dmFields = DM_DISPLAYFREQUENCY | DM_PELSWIDTH | DM_PELSHEIGHT | DM_BITSPERPEL;

        // First test if the mode is supported
        int testResult = ChangeDisplaySettingsEx(
            deviceName,
            ref currentMode,
            IntPtr.Zero,
            CDS_TEST,
            IntPtr.Zero);

        if (testResult != DISP_CHANGE_SUCCESSFUL)
        {
            message = string.Format("{0} Hz → {1} Hz NOT supported (CDS_TEST failed)", originalFreq, hz);
            return false;
        }

        // Now actually change
        int changeResult = ChangeDisplaySettingsEx(
            deviceName,
            ref currentMode,
            IntPtr.Zero,
            CDS_UPDATEREGISTRY,
            IntPtr.Zero);

        switch (changeResult)
        {
            case DISP_CHANGE_SUCCESSFUL:
                message = string.Format("{0} Hz → {1} Hz successful", originalFreq, hz);
                return true;

            case DISP_CHANGE_RESTART:
                message = string.Format("{0} Hz → {1} Hz requires restart", originalFreq, hz);
                return true; // Consider as success, but note

            case DISP_CHANGE_BADMODE:
                message = string.Format("{0} Hz → {1} Hz invalid mode", originalFreq, hz);
                return false;

            default:
                message = string.Format("{0} Hz → {1} Hz error (code: {2})", originalFreq, hz, changeResult);
                return false;
        }
    }

    /// <summary>
    /// Lists all available display modes for a monitor (debug method)
    /// </summary>
    public static void ListSupportedModes(string deviceName)
    {
        Console.WriteLine(string.Format("\nAvailable modes for {0}:", deviceName));
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
    /// Displays the current status of all monitors (debug method)
    /// </summary>
    public static void GetCurrentStatus()
    {
        Console.WriteLine("\n=== Current Monitor Configuration ===");

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
                    Console.WriteLine(string.Format("  Resolution: {0}x{1}", currentMode.dmPelsWidth, currentMode.dmPelsHeight));
                    Console.WriteLine(string.Format("  Frequency: {0} Hz", currentMode.dmDisplayFrequency));
                    Console.WriteLine(string.Format("  Color depth: {0} bit", currentMode.dmBitsPerPel));
                }
            }

            deviceIndex++;
            device = new DISPLAY_DEVICE();
            device.cb = Marshal.SizeOf(device);
        }
    }

    // Backward compatibility alias
    public static void SetGPUMonitorsTo(int hz)
    {
        SetAllMonitorsTo(hz);
    }
}
