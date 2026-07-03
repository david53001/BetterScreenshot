using System.Threading;
using BetterScreenshot.Capture;
using BetterScreenshot.Platform;
using Xunit;

namespace BetterScreenshot.Tests;

public class HotkeyHostTests
{
    [Fact]
    public void ToRegisterArgsMapsModifiersAndAddsNoRepeat()
    {
        var (mods, vk) = HotkeyInterop.ToRegisterArgs(new HotkeyCombo(0x34, HotkeyModifiers.Control | HotkeyModifiers.Shift));
        Assert.Equal(0x34u, vk);
        Assert.True((mods & 0x0002) != 0);           // MOD_CONTROL
        Assert.True((mods & 0x0004) != 0);           // MOD_SHIFT
        Assert.True((mods & HotkeyInterop.ModNoRepeat) != 0); // MOD_NOREPEAT
    }

    [Fact]
    [Trait("category", "hardware")]
    public void RegistersAnUnusualComboWithoutFailure()
    {
        Exception? error = null;
        IReadOnlySet<HotkeyAction>? failed = null;

        var thread = new Thread(() =>
        {
            try
            {
                using var host = new HotkeyHost();
                // Ctrl+Alt+F24 is essentially always free.
                failed = host.Apply(new[] { (HotkeyAction.CaptureArea, new HotkeyCombo(0x87, HotkeyModifiers.Control | HotkeyModifiers.Alt)) });
            }
            catch (Exception e)
            {
                error = e;
            }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join(TimeSpan.FromSeconds(10));

        Assert.Null(error);
        Assert.NotNull(failed);
        Assert.Empty(failed!);
    }
}
