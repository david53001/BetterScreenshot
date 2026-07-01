using System.Windows.Input;
using BetterScreenshot.Capture;

namespace BetterScreenshot.App.Settings;

/// <summary>Pure logic for the shortcut-recorder field: turn a WPF key + modifiers into a valid <see cref="HotkeyCombo"/>.</summary>
public static class ShortcutRecorder
{
    public static bool IsModifierKey(Key key) => key is
        Key.LeftCtrl or Key.RightCtrl or Key.LeftShift or Key.RightShift or
        Key.LeftAlt or Key.RightAlt or Key.LWin or Key.RWin or Key.System;

    /// <summary>Builds a combo from a pressed key + held modifiers, or null if it's a bare modifier or not a valid hotkey.</summary>
    public static HotkeyCombo? TryBuildCombo(Key key, ModifierKeys modifiers)
    {
        if (IsModifierKey(key)) return null;

        var mods = HotkeyModifiers.None;
        if (modifiers.HasFlag(ModifierKeys.Control)) mods |= HotkeyModifiers.Control;
        if (modifiers.HasFlag(ModifierKeys.Alt)) mods |= HotkeyModifiers.Alt;
        if (modifiers.HasFlag(ModifierKeys.Shift)) mods |= HotkeyModifiers.Shift;
        if (modifiers.HasFlag(ModifierKeys.Windows)) mods |= HotkeyModifiers.Win;

        uint vk = (uint)KeyInterop.VirtualKeyFromKey(key);
        if (vk == 0) return null;

        var combo = new HotkeyCombo(vk, mods);
        return combo.IsValid ? combo : null;
    }
}
