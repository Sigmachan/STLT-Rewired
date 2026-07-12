using RewiredManager.App.Models;

namespace RewiredManager.App.Services;

public sealed class UnlockBackendService
{
    private readonly SteamInstallService _steam = new();

    public UnlockBackendStatus Inspect(RewiredSharedConfig config)
    {
        var steam = _steam.ResolveSteamPath(config.SteamPath);
        var preference = config.BackendKind;

        var ost = File.Exists(Path.Combine(steam, "OpenSteamTool.dll"));
        var steamTools = File.Exists(Path.Combine(steam, "config", "stplug-in", "Steamtools.lua"))
            || File.Exists(Path.Combine(steam, "Steamtools.exe"))
            || Directory.Exists(Path.Combine(steam, "config", "stUI"));
        var luma = File.Exists(Path.Combine(steam, "LumaCore.dll"));

        var resolved = ResolveBackend(preference, ost, steamTools, luma);
        var luaDir = resolved == UnlockBackendKind.OpenSteamTool
            ? Path.Combine(steam, "config", "lua")
            : Path.Combine(steam, "config", "stplug-in");
        var depot = Path.Combine(steam, "depotcache");

        var ready = resolved != UnlockBackendKind.None && resolved != UnlockBackendKind.Millennium
            || (resolved == UnlockBackendKind.Millennium && Directory.Exists(luaDir));

        return new UnlockBackendStatus(
            steam,
            preference,
            resolved,
            luaDir,
            depot,
            ost,
            steamTools,
            luma,
            ready);
    }

    public static UnlockBackendKind ResolveBackend(
        UnlockBackendKind preference,
        bool openSteamTool,
        bool steamTools,
        bool lumaCore)
    {
        return preference switch
        {
            UnlockBackendKind.OpenSteamTool => UnlockBackendKind.OpenSteamTool,
            UnlockBackendKind.SteamTools => UnlockBackendKind.SteamTools,
            UnlockBackendKind.LumaCore => UnlockBackendKind.LumaCore,
            UnlockBackendKind.Millennium => UnlockBackendKind.Millennium,
            UnlockBackendKind.None => UnlockBackendKind.None,
            _ when openSteamTool => UnlockBackendKind.OpenSteamTool,
            _ when lumaCore => UnlockBackendKind.LumaCore,
            _ when steamTools => UnlockBackendKind.SteamTools,
            _ => UnlockBackendKind.None
        };
    }

    public void EnsureDirectories(UnlockBackendStatus status)
    {
        Directory.CreateDirectory(status.LuaScriptDir);
        Directory.CreateDirectory(status.DepotCacheDir);
    }
}
