using BetterScreenshot.Platform;
using Microsoft.Win32;
using Xunit;

namespace BetterScreenshot.Tests;

/// <summary>
/// Drives <see cref="StartupRegistration"/>'s registry seam against a throwaway HKCU subkey
/// (<c>Software\BetterScreenshot.Tests\…</c>) so it never touches the real
/// <c>…\CurrentVersion\Run</c> key. Each test cleans up the whole scratch tree in a finally block.
/// </summary>
public class StartupRegistrationTests
{
    private const string ScratchRoot = @"Software\BetterScreenshot.Tests";
    private const string ValueName = "BetterScreenshot";

    private static string ScratchKey() => ScratchRoot + "\\" + Guid.NewGuid().ToString("N");

    private static string? Read(string subKey)
    {
        using var key = Registry.CurrentUser.OpenSubKey(subKey);
        return key?.GetValue(ValueName) as string;
    }

    private static void Cleanup()
    {
        try { Registry.CurrentUser.DeleteSubKeyTree(ScratchRoot, throwOnMissingSubKey: false); }
        catch { /* best-effort */ }
    }

    [Fact]
    public void SetEnabled_WritesQuotedCommand_ThenRemovesIt()
    {
        string sub = ScratchKey();
        try
        {
            const string cmd = "\"C:\\Apps\\BetterScreenshot\\BetterScreenshot.App.exe\"";
            StartupRegistration.SetEnabledIn(sub, ValueName, enabled: true, command: cmd);
            Assert.Equal(cmd, Read(sub));

            StartupRegistration.SetEnabledIn(sub, ValueName, enabled: false, command: null);
            Assert.Null(Read(sub));
        }
        finally { Cleanup(); }
    }

    [Fact]
    public void SetEnabled_WithUnresolvableExe_WritesNothing()
    {
        string sub = ScratchKey();
        try
        {
            StartupRegistration.SetEnabledIn(sub, ValueName, enabled: true, command: null);
            Assert.Null(Read(sub)); // never write a broken (empty) Run entry
        }
        finally { Cleanup(); }
    }

    [Fact]
    public void SetEnabled_Disable_OnMissingValue_DoesNotThrow()
    {
        string sub = ScratchKey();
        try
        {
            StartupRegistration.SetEnabledIn(sub, ValueName, enabled: false, command: null); // no prior entry
            Assert.Null(Read(sub));
        }
        finally { Cleanup(); }
    }

    [Fact]
    public void Reconcile_Enabled_RefreshesStalePath()
    {
        string sub = ScratchKey();
        try
        {
            StartupRegistration.SetEnabledIn(sub, ValueName, enabled: true, command: "\"C:\\Old\\path.exe\"");
            StartupRegistration.ReconcileIn(sub, ValueName, desired: true, command: "\"C:\\New\\path.exe\"");
            Assert.Equal("\"C:\\New\\path.exe\"", Read(sub));
        }
        finally { Cleanup(); }
    }

    [Fact]
    public void Reconcile_Disabled_ClearsExistingEntry()
    {
        string sub = ScratchKey();
        try
        {
            StartupRegistration.SetEnabledIn(sub, ValueName, enabled: true, command: "\"C:\\Some\\path.exe\"");
            StartupRegistration.ReconcileIn(sub, ValueName, desired: false, command: "\"C:\\Some\\path.exe\"");
            Assert.Null(Read(sub));
        }
        finally { Cleanup(); }
    }

    [Fact]
    public void Reconcile_Disabled_WithNoEntry_IsNoOp()
    {
        string sub = ScratchKey();
        try
        {
            StartupRegistration.ReconcileIn(sub, ValueName, desired: false, command: null);
            Assert.Null(Read(sub));
            using var key = Registry.CurrentUser.OpenSubKey(sub);
            Assert.Null(key); // reconcile-off must not even create the subkey
        }
        finally { Cleanup(); }
    }

    [Fact]
    public void CurrentCommand_QuotesTheRunningExecutablePath()
    {
        string? cmd = StartupRegistration.CurrentCommand();
        Assert.NotNull(cmd);
        Assert.StartsWith("\"", cmd);
        Assert.EndsWith("\"", cmd);
        Assert.True(cmd!.Length > 2); // more than just the two quotes
    }
}
