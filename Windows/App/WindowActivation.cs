using System;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Win32.SafeHandles;

namespace ScreenSpan
{
    internal static class WindowActivation
    {
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool GetNamedPipeServerProcessId(SafePipeHandle pipe, out uint processId);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool AllowSetForegroundWindow(uint processId);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool ShowWindow(IntPtr window, int command);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool SetForegroundWindow(IntPtr window);

        // Transfer the launcher's foreground permission to this user's existing
        // instance before asking it to show its window. Do not grant every process.
        internal static void AllowExistingInstance(NamedPipeClientStream client)
        {
            if (GetNamedPipeServerProcessId(client.SafePipeHandle, out uint processId))
                AllowSetForegroundWindow(processId);
        }

        internal static void Show(Form window)
        {
            if (!window.Visible)
                window.Show();
            if (window.WindowState == FormWindowState.Minimized)
                ShowWindow(window.Handle, 9); // SW_RESTORE preserves the previous maximized state.
            window.BringToFront();
            window.Activate();
            SetForegroundWindow(window.Handle);
        }
    }
}
