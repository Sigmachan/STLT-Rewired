namespace RewiredManager.App.Models;

public enum UnlockBackendKind
{
    Auto,
    OpenSteamTool,
    SteamTools,
    LumaCore,
    Millennium,
    None
}

public static class UnlockBackendKindExtensions
{
    public static string ToConfigValue(this UnlockBackendKind kind) => kind switch
    {
        UnlockBackendKind.OpenSteamTool => "opensteamtool",
        UnlockBackendKind.SteamTools => "steamtools",
        UnlockBackendKind.LumaCore => "lumacore",
        UnlockBackendKind.Millennium => "millennium",
        UnlockBackendKind.None => "none",
        _ => "auto"
    };

    public static UnlockBackendKind FromConfigValue(string? value) => (value ?? "auto").Trim().ToLowerInvariant() switch
    {
        "opensteamtool" or "ost" => UnlockBackendKind.OpenSteamTool,
        "steamtools" => UnlockBackendKind.SteamTools,
        "lumacore" => UnlockBackendKind.LumaCore,
        "millennium" => UnlockBackendKind.Millennium,
        "none" => UnlockBackendKind.None,
        _ => UnlockBackendKind.Auto
    };

    public static string DisplayName(this UnlockBackendKind kind) => kind switch
    {
        UnlockBackendKind.OpenSteamTool => "OpenSteamTool",
        UnlockBackendKind.SteamTools => "SteamTools",
        UnlockBackendKind.LumaCore => "LumaCore",
        UnlockBackendKind.Millennium => "Millennium (UI only)",
        UnlockBackendKind.None => "Not detected",
        _ => "Auto-detect"
    };
}
