using Microsoft.Win32;

namespace BetterScreenshot.Platform;

/// <summary>
/// Registers or removes BetterScreenshot in the per-user "run at sign-in" list so the tray agent starts
/// automatically when the user logs into Windows. Implemented via the HKCU
/// <c>Software\Microsoft\Windows\CurrentVersion\Run</c> key: per-user (no admin needed), fully reversible
/// (delete the value), and surfaced in Task Manager → Startup so the user can also disable it there. This is
/// the Windows equivalent of the macOS app's "Launch at login" login item, driven by
/// <see cref="SettingsStore.LaunchAtLogin"/>.
///
/// All operations are best-effort and never throw — under a locked-down group policy the registry write can
/// fail, but the persisted flag still records the user's intent.
/// </summary>
public static class StartupRegistration
{
    private const string RunSubKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "BetterScreenshot";

    /// <summary>Turn launch-at-login on or off. Enabling (re)writes the Run value to the <em>current</em>
    /// executable path — so a moved or republished build stays valid; disabling removes the entry.</summary>
    public static void SetEnabled(bool enabled) => SetEnabledIn(RunSubKey, ValueName, enabled, CurrentCommand());

    /// <summary>Bring the OS registration in line with <paramref name="desired"/>, refreshing the stored path
    /// when it's on. Call once at startup: it repairs a stale path (e.g. after the app is republished to a new
    /// folder) and clears a leftover entry if the flag was turned off out-of-band. It reads first and only
    /// writes when something actually differs, so calling it repeatedly (e.g. on every settings change) is
    /// cheap and idempotent.</summary>
    public static void Reconcile(bool desired) => ReconcileIn(RunSubKey, ValueName, desired, CurrentCommand());

    /// <summary>The command string stored in the Run value: the quoted path to the running executable, or
    /// <c>null</c> if it can't be determined (in which case enabling is a no-op rather than writing a broken
    /// entry). Quoting guards against spaces in the install path.</summary>
    internal static string? CurrentCommand()
    {
        string? exe = Environment.ProcessPath;
        return string.IsNullOrWhiteSpace(exe) ? null : $"\"{exe}\"";
    }

    internal static string? ReadCommand(string subKey, string valueName)
    {
        try
        {
            using RegistryKey? key = Registry.CurrentUser.OpenSubKey(subKey);
            return key?.GetValue(valueName) as string;
        }
        catch
        {
            return null;
        }
    }

    internal static void SetEnabledIn(string subKey, string valueName, bool enabled, string? command)
    {
        try
        {
            using RegistryKey key = Registry.CurrentUser.CreateSubKey(subKey);
            if (enabled)
            {
                if (string.IsNullOrWhiteSpace(command)) return; // unresolved exe → don't write a broken entry
                key.SetValue(valueName, command, RegistryValueKind.String);
            }
            else
            {
                key.DeleteValue(valueName, throwOnMissingValue: false);
            }
        }
        catch
        {
            // Locked-down policy or transient failure: leave things as-is; the persisted flag records intent.
        }
    }

    internal static void ReconcileIn(string subKey, string valueName, bool desired, string? command)
    {
        string? current = ReadCommand(subKey, valueName);
        if (desired)
        {
            if (!string.IsNullOrWhiteSpace(command) &&
                !string.Equals(current, command, StringComparison.OrdinalIgnoreCase))
                SetEnabledIn(subKey, valueName, true, command);
        }
        else if (current is not null)
        {
            SetEnabledIn(subKey, valueName, false, command);
        }
    }
}
