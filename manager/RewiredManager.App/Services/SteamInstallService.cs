using Microsoft.Win32;

namespace RewiredManager.App.Services;

public sealed class SteamInstallService
{
    public static string? TryDetectSteamPath()
    {
        foreach (var view in new[] { RegistryView.Default, RegistryView.Registry32 })
        {
            try
            {
                using var baseKey = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, view);
                using var steamKey = baseKey.OpenSubKey(@"Software\Valve\Steam");
                var path = steamKey?.GetValue("SteamPath") as string;
                if (!string.IsNullOrWhiteSpace(path) && Directory.Exists(path))
                    return Path.GetFullPath(path);
            }
            catch
            {
                // try next view
            }
        }

        var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
        var fallback = Path.Combine(programFiles, "Steam");
        return Directory.Exists(fallback) ? fallback : null;
    }

    public string ResolveSteamPath(string? overridePath)
    {
        if (!string.IsNullOrWhiteSpace(overridePath) && Directory.Exists(overridePath))
            return Path.GetFullPath(overridePath.Trim());

        return TryDetectSteamPath()
            ?? throw new InvalidOperationException("Steam installation not found. Set Steam path manually.");
    }
}
