using System.Windows.Input;
using BetterScreenshot.App.Settings;
using BetterScreenshot.Capture;
using Xunit;

namespace BetterScreenshot.Tests;

public class ShortcutRecorderTests
{
    [Fact]
    public void BuildsValidComboFromKeyAndModifiers()
    {
        var combo = ShortcutRecorder.TryBuildCombo(Key.D4, ModifierKeys.Control | ModifierKeys.Shift);
        Assert.NotNull(combo);
        Assert.Equal(new HotkeyCombo(0x34, HotkeyModifiers.Control | HotkeyModifiers.Shift), combo!.Value);
    }

    [Fact]
    public void RejectsShiftOnly()
    {
        Assert.Null(ShortcutRecorder.TryBuildCombo(Key.D4, ModifierKeys.Shift));
    }

    [Fact]
    public void RejectsBareModifierKey()
    {
        Assert.Null(ShortcutRecorder.TryBuildCombo(Key.LeftCtrl, ModifierKeys.Control));
    }

    [Fact]
    public void BuildsAltCombo()
    {
        var combo = ShortcutRecorder.TryBuildCombo(Key.A, ModifierKeys.Alt);
        Assert.Equal(new HotkeyCombo(0x41, HotkeyModifiers.Alt), combo!.Value);
    }
}
