using System.Runtime.InteropServices;
using BetterScreenshot.Capture;
using BetterScreenshot.Core;

namespace BetterScreenshot.Platform;

/// <summary>Pure formatter for the keystroke overlay: modifier names + key, e.g. "Ctrl+Shift+4".</summary>
public static class KeystrokeGlyphs
{
    public static string Format(uint vk, bool ctrl, bool alt, bool shift, bool win)
    {
        var parts = new List<string>(5);
        if (ctrl) parts.Add("Ctrl");
        if (alt) parts.Add("Alt");
        if (shift) parts.Add("Shift");
        if (win) parts.Add("Win");
        if (!IsModifier(vk)) parts.Add(HotkeyCombo.KeyName(vk));
        return string.Join("+", parts);
    }

    private static bool IsModifier(uint vk) =>
        vk is 0x10 or 0x11 or 0x12       // SHIFT, CONTROL, MENU(Alt)
           or 0xA0 or 0xA1 or 0xA2 or 0xA3 or 0xA4 or 0xA5 // L/R shift/ctrl/alt
           or 0x5B or 0x5C;              // L/R Win
}

/// <summary>Low-level global mouse hook (WH_MOUSE_LL). Raises <see cref="MouseDown"/> at each click point.</summary>
public sealed class MouseHook : IDisposable
{
    private const int WhMouseLl = 14;
    private const int WmLButtonDown = 0x0201, WmRButtonDown = 0x0204, WmMButtonDown = 0x0207;

    private readonly NativeHooks.HookProc _proc;
    private IntPtr _hook;

    public event Action<PxPoint>? MouseDown;

    public MouseHook()
    {
        _proc = Callback;
        _hook = NativeHooks.SetWindowsHookEx(WhMouseLl, _proc, NativeHooks.GetModuleHandle(null), 0);
    }

    public bool IsInstalled => _hook != IntPtr.Zero;

    private IntPtr Callback(int code, IntPtr wParam, IntPtr lParam)
    {
        if (code >= 0)
        {
            int msg = wParam.ToInt32();
            if (msg is WmLButtonDown or WmRButtonDown or WmMButtonDown)
            {
                var data = Marshal.PtrToStructure<NativeHooks.MsllHookStruct>(lParam);
                MouseDown?.Invoke(new PxPoint(data.pt.x, data.pt.y));
            }
        }
        return NativeHooks.CallNextHookEx(_hook, code, wParam, lParam);
    }

    public void Dispose()
    {
        if (_hook != IntPtr.Zero)
        {
            NativeHooks.UnhookWindowsHookEx(_hook);
            _hook = IntPtr.Zero;
        }
    }
}

/// <summary>Low-level global keyboard hook (WH_KEYBOARD_LL). Raises <see cref="KeyDown"/> with a formatted glyph string.</summary>
public sealed class KeyboardHook : IDisposable
{
    private const int WhKeyboardLl = 13;
    private const int WmKeyDown = 0x0100, WmSysKeyDown = 0x0104;

    private readonly NativeHooks.HookProc _proc;
    private IntPtr _hook;

    public event Action<string>? KeyDown;

    public KeyboardHook()
    {
        _proc = Callback;
        _hook = NativeHooks.SetWindowsHookEx(WhKeyboardLl, _proc, NativeHooks.GetModuleHandle(null), 0);
    }

    public bool IsInstalled => _hook != IntPtr.Zero;

    private IntPtr Callback(int code, IntPtr wParam, IntPtr lParam)
    {
        if (code >= 0)
        {
            int msg = wParam.ToInt32();
            if (msg is WmKeyDown or WmSysKeyDown)
            {
                var data = Marshal.PtrToStructure<NativeHooks.KbdllHookStruct>(lParam);
                bool ctrl = IsDown(0x11), alt = IsDown(0x12), shift = IsDown(0x10), win = IsDown(0x5B) || IsDown(0x5C);
                KeyDown?.Invoke(KeystrokeGlyphs.Format(data.vkCode, ctrl, alt, shift, win));
            }
        }
        return NativeHooks.CallNextHookEx(_hook, code, wParam, lParam);
    }

    private static bool IsDown(int vk) => (NativeHooks.GetAsyncKeyState(vk) & 0x8000) != 0;

    public void Dispose()
    {
        if (_hook != IntPtr.Zero)
        {
            NativeHooks.UnhookWindowsHookEx(_hook);
            _hook = IntPtr.Zero;
        }
    }
}

internal static class NativeHooks
{
    public delegate IntPtr HookProc(int code, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr SetWindowsHookEx(int idHook, HookProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll")] public static extern bool UnhookWindowsHookEx(IntPtr hhk);
    [DllImport("user32.dll")] public static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr GetModuleHandle(string? lpModuleName);

    [StructLayout(LayoutKind.Sequential)]
    public struct Point { public int x, y; }

    [StructLayout(LayoutKind.Sequential)]
    public struct MsllHookStruct { public Point pt; public uint mouseData, flags, time; public IntPtr dwExtraInfo; }

    [StructLayout(LayoutKind.Sequential)]
    public struct KbdllHookStruct { public uint vkCode, scanCode, flags, time; public IntPtr dwExtraInfo; }
}
