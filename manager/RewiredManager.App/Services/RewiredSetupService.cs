using RewiredManager.App.Models;

namespace RewiredManager.App.Services;

public sealed class RewiredSetupService
{
    private readonly SteamInstallService _steamPaths = new();
    private readonly MillenniumInstallService _millennium = new();
    private readonly OpenSteamToolInstallService _ost = new();
    private readonly ManagerUpdateService _updates = new();
    private readonly UnlockBackendService _unlock = new();
    private readonly PluginDiscoveryService _discovery = new();
    private readonly RewiredConfigService _config = new();

    public SetupReadiness Assess(string? steamPathOverride = null)
    {
        string? steam = null;
        try
        {
            steam = _steamPaths.ResolveSteamPath(steamPathOverride);
        }
        catch
        {
            steam = SteamInstallService.TryDetectSteamPath();
        }

        if (string.IsNullOrWhiteSpace(steam))
        {
            return new SetupReadiness(false, null, false, false, false, false);
        }

        steam = Path.GetFullPath(steam);
        var cfg = new RewiredSharedConfig { SteamPath = steam };
        var unlock = _unlock.Inspect(cfg);
        var plugin = _discovery.Inspect(Path.Combine(steam, "millennium", "plugins", "luatools"));

        return new SetupReadiness(
            SteamFound: true,
            SteamPath: steam,
            MillenniumPresent: _millennium.IsInstalled(steam),
            OpenSteamToolPresent: unlock.OpenSteamToolDll,
            PluginPresent: plugin.LooksUsable,
            CanAddGames: unlock.OpenSteamToolDll || unlock.SteamToolsMarkers || unlock.LumaCoreDll);
    }

    public async Task<SetupResult> RunAsync(
        SetupOptions options,
        IProgress<string>? progress = null,
        CancellationToken ct = default)
    {
        var log = new List<string>();
        void Report(string line)
        {
            log.Add(line);
            progress?.Report(line);
        }

        try
        {
            var steam = _steamPaths.ResolveSteamPath(options.SteamPath);
            Report($"Steam: {steam}");

            if (options.InstallInSteamUi)
            {
                Report("Installing in-Steam UI (Millennium + Rewired plugin)…");
                var mill = await _millennium.InstallAsync(steam, ct);
                Report(mill.Message);
                if (!mill.Success) return Fail(log, mill.Message);

                var plug = await _updates.ApplyPluginUpdateAsync(steam, ct);
                Report(plug.Message);
                if (!plug.Success) return Fail(log, plug.Message);
            }

            if (options.InstallOpenSteamTool)
            {
                Report("Installing OpenSteamTool…");
                var ost = await _ost.InstallLatestAsync(steam, ct);
                Report(ost.Message);
                if (!ost.Success) return Fail(log, ost.Message);
            }

            var pluginPath = Path.Combine(steam, "millennium", "plugins", "luatools");
            var cfg = _config.Load();
            cfg.SteamPath = steam;
            cfg.PluginPath = pluginPath;
            cfg.UnlockBackend = options.InstallOpenSteamTool
                ? UnlockBackendKind.OpenSteamTool.ToConfigValue()
                : cfg.UnlockBackend;
            cfg.MillenniumOptional = !options.InstallInSteamUi;
            _config.Save(cfg);
            Report("Saved shared config.");

            if (options.CreateDesktopShortcut)
            {
                var exe = Environment.ProcessPath;
                if (!string.IsNullOrEmpty(exe) && File.Exists(exe))
                {
                    RewiredShortcutService.CreateOrUpdateDesktopShortcut(exe);
                    Report("Desktop shortcut: Rewired");
                }
            }

            var summary = "Setup complete. Restart Steam, then use Add game or open Steam for in-Steam UI.";
            Report(summary);
            return new SetupResult(true, summary, log);
        }
        catch (Exception ex)
        {
            Report("Error: " + ex.Message);
            return Fail(log, ex.Message);
        }
    }

    private static SetupResult Fail(List<string> log, string message) =>
        new(false, message, log);
}
