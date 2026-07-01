using System.IO;
using BetterScreenshot.App.Capture;
using BetterScreenshot.Capture;
using BetterScreenshot.Platform;
using Xunit;

namespace BetterScreenshot.Tests;

public class CaptureFlowTests
{
    [Fact]
    public void RouterDecidesPerBehavior()
    {
        Assert.Equal((true, false, false), CaptureRouter.Decide(AfterCaptureBehavior.CopyOnly));
        Assert.Equal((false, true, false), CaptureRouter.Decide(AfterCaptureBehavior.SaveOnly));
        Assert.Equal((true, true, false), CaptureRouter.Decide(AfterCaptureBehavior.CopyAndSave));
        Assert.Equal((false, false, true), CaptureRouter.Decide(AfterCaptureBehavior.ShowOverlay));
    }

    [Fact]
    [Trait("category", "hardware")]
    public void FullscreenCaptureSavesAPngEndToEnd()
    {
        var dir = Path.Combine(Path.GetTempPath(), "bs-cap-" + Guid.NewGuid().ToString("N"));
        var settings = new SettingsStore
        {
            SaveDirectory = dir,
            Capture = CaptureSettings.Default with { AfterCapture = AfterCaptureBehavior.SaveOnly, Format = SettingsImageFormat.Png },
        };
        var coordinator = new CaptureCoordinator(settings, () => { });
        try
        {
            coordinator.CaptureFullscreen();
            Assert.NotEmpty(Directory.GetFiles(dir, "*.png"));
        }
        finally
        {
            if (Directory.Exists(dir)) Directory.Delete(dir, true);
        }
    }
}
