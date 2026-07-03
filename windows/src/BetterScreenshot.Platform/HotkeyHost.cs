using System.Runtime.InteropServices;
using System.Windows.Interop;
using BetterScreenshot.Capture;

namespace BetterScreenshot.Platform;

/// <summary>Pure mapping from a <see cref="HotkeyCombo"/> to RegisterHotKey arguments (MOD_* flags + VK).</summary>
public static class HotkeyInterop
{
    public const uint ModNoRepeat = 0x4000;

    // HotkeyModifiers values already equal the Win32 MOD_* constants; we just add MOD_NOREPEAT.
    public static (uint Modifiers, uint Vk) ToRegisterArgs(HotkeyCombo combo) =>
        ((uint)combo.Modifiers | ModNoRepeat, combo.Vk);
}

/// <summary>
/// Hosts global hotkeys on a hidden message-only window. Registers combos via Win32 RegisterHotKey and raises
/// <see cref="HotkeyPressed"/> when one fires. Must be created on the UI (STA) thread at runtime.
/// </summary>
public sealed class HotkeyHost : IDisposable
{
    private const int WmHotkey = 0x0312;
    private const int HwndMessage = -3;

    private readonly HwndSource _source;
    private readonly Dictionary<int, HotkeyAction> _idToAction = new();
    private readonly Dictionary<HotkeyAction, HotkeyCombo> _current = new();
    private int _nextId = 1;

    public event Action<HotkeyAction>? HotkeyPressed;

    public HotkeyHost()
    {
        var parameters = new HwndSourceParameters("BetterScreenshotHotkeyHost", 0, 0)
        {
            ParentWindow = new IntPtr(HwndMessage), // message-only window
            WindowStyle = 0,
        };
        _source = new HwndSource(parameters);
        _source.AddHook(WndProc);
    }

    /// <summary>
    /// Registers the given bindings, replacing any previous ones. Returns the set of actions whose registration
    /// FAILED (e.g. the combo is already owned by another app).
    /// </summary>
    public IReadOnlySet<HotkeyAction> Apply(IEnumerable<(HotkeyAction Action, HotkeyCombo Combo)> bindings)
    {
        UnregisterAll();
        _current.Clear();
        var failed = new HashSet<HotkeyAction>();
        foreach (var (action, combo) in bindings)
        {
            int id = _nextId++;
            var (mods, vk) = HotkeyInterop.ToRegisterArgs(combo);
            if (RegisterHotKey(_source.Handle, id, mods, vk))
            {
                _idToAction[id] = action;
                _current[action] = combo;
            }
            else
            {
                failed.Add(action);
            }
        }
        return failed;
    }

    /// <summary>Temporarily unregister all hotkeys (used while a shortcut recorder field is active).</summary>
    public void Suspend() => UnregisterAll();

    /// <summary>Re-register the last-applied bindings after <see cref="Suspend"/>.</summary>
    public void Resume() => Apply(_current.Select(kv => (kv.Key, kv.Value)).ToList());

    private void UnregisterAll()
    {
        foreach (int id in _idToAction.Keys) UnregisterHotKey(_source.Handle, id);
        _idToAction.Clear();
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WmHotkey && _idToAction.TryGetValue(wParam.ToInt32(), out var action))
        {
            HotkeyPressed?.Invoke(action);
            handled = true;
        }
        return IntPtr.Zero;
    }

    public void Dispose()
    {
        UnregisterAll();
        _source.RemoveHook(WndProc);
        _source.Dispose();
    }

    [DllImport("user32.dll")] private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")] private static extern bool UnregisterHotKey(IntPtr hWnd, int id);
}
