using BetterScreenshot.Platform;
using Xunit;

namespace BetterScreenshot.Tests;

public class GlobalHooksTests
{
    [Fact]
    public void FormatsModifiersPlusKey()
    {
        Assert.Equal("Ctrl+Shift+4", KeystrokeGlyphs.Format(0x34, ctrl: true, alt: false, shift: true, win: false));
        Assert.Equal("A", KeystrokeGlyphs.Format(0x41, false, false, false, false));
        Assert.Equal("Alt+Win+F1", KeystrokeGlyphs.Format(0x70, ctrl: false, alt: true, shift: false, win: true));
    }

    [Fact]
    public void ModifierKeyAloneShowsOnlyModifiers()
    {
        // VK_CONTROL as the key while Ctrl is held → just "Ctrl", no duplicated key token.
        Assert.Equal("Ctrl", KeystrokeGlyphs.Format(0x11, ctrl: true, alt: false, shift: false, win: false));
    }

    [Fact]
    [Trait("category", "hardware")]
    public void KeyboardHookInstallsAndUninstalls()
    {
        using var hook = new KeyboardHook();
        Assert.True(hook.IsInstalled);
    }

    [Fact]
    [Trait("category", "hardware")]
    public void MouseHookInstallsAndUninstalls()
    {
        using var hook = new MouseHook();
        Assert.True(hook.IsInstalled);
    }
}
