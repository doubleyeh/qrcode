using System;
using System.Runtime.InteropServices;

namespace QrCodeApp
{
    static class Native
    {
        [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
        [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
        [DllImport("user32.dll")] public static extern uint SendInput(uint n, INPUT[] inputs, int size);
        [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
        [DllImport("user32.dll")] public static extern uint GetClipboardSequenceNumber();

        [StructLayout(LayoutKind.Sequential)]
        public struct INPUT { public uint type; public InputUnion U; }

        [StructLayout(LayoutKind.Explicit)]
        public struct InputUnion
        {
            [FieldOffset(0)] public MOUSEINPUT mi;
            [FieldOffset(0)] public KEYBDINPUT ki;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo; }

        [StructLayout(LayoutKind.Sequential)]
        public struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr dwExtraInfo; }

        public static INPUT Key(ushort vk, bool up)
        {
            var i = new INPUT { type = 1 };
            i.U.ki = new KEYBDINPUT { wVk = vk, dwFlags = up ? 2u : 0u };
            return i;
        }

        public static void Send(params INPUT[] inputs)
        {
            SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT)));
        }

        public static bool IsDown(int vk) { return (GetAsyncKeyState(vk) & 0x8000) != 0; }
    }
}
