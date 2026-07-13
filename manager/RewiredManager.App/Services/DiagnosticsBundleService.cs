using System.Diagnostics;
using System.Text;
using System.Text.RegularExpressions;
using RewiredManager.App.Models;

namespace RewiredManager.App.Services;

public sealed class DiagnosticsBundleService
{
    private readonly UnlockBackendService _unlock = new();
    private readonly PluginDiscoveryService _discovery = new();
    private readonly SourceHealthService _sourceHealth = new();
    private readonly MillenniumInfoService _millennium = new();
    private readonly SecretStoreService _secrets = new();

    public async Task<(bool Success, string Message, string? Path)> ExportAsync(
        RewiredSharedConfig config,
        string? pluginPath,
        string? ryuuCookie,
        int appId = 0,
        CancellationToken ct = default)
    {
        try
        {
            var lines = new List<string>();
            Append(lines, "=== Rewired Redacted Support Bundle ===");
            Append(lines, "Generated UTC: " + DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"));
            Append(lines, "Manager version: " + typeof(DiagnosticsBundleService).Assembly.GetName().Version);
            Append(lines, "Config path: " + RewiredConfigService.ConfigPath);

            var unlock = _unlock.Inspect(config);
            Append(lines, "");
            Append(lines, "[Unlock stack]");
            Append(lines, "steamPath=" + unlock.SteamPath);
            Append(lines, "resolvedBackend=" + unlock.Resolved);
            Append(lines, "luaDir=" + unlock.LuaScriptDir);
            Append(lines, "depotCache=" + unlock.DepotCacheDir);
            Append(lines, "openSteamTool=" + unlock.OpenSteamToolDll);
            Append(lines, "steamTools=" + unlock.SteamToolsMarkers);
            Append(lines, "readyForAdd=" + unlock.ReadyForAdd);

            var mil = _millennium.Inspect(unlock.SteamPath);
            Append(lines, "");
            Append(lines, "[Millennium]");
            Append(lines, "installed=" + mil.Installed);
            Append(lines, "version=" + mil.Version);
            Append(lines, "target=" + mil.TargetVersion);
            Append(lines, "compatible=" + mil.VersionCompatible);

            var plugin = _discovery.Inspect(pluginPath);
            Append(lines, "");
            Append(lines, "[Plugin]");
            Append(lines, "path=" + plugin.PluginPath);
            Append(lines, "exists=" + plugin.Exists);
            Append(lines, "version=" + plugin.Version);
            Append(lines, "commonName=" + plugin.CommonName);
            Append(lines, "usable=" + plugin.LooksUsable);
            Append(lines, "ryuuSession=" + PresentMissing(plugin.HasRyuuSession));
            Append(lines, "manifestHubKey=" + PresentMissing(plugin.HasMorrenusKey));

            Append(lines, "");
            Append(lines, "[Secrets shape — values redacted]");
            var secretPath = SecretStoreService.GetSecretsPath(plugin.PluginPath);
            Append(lines, "secretsFile=" + secretPath);
            Append(lines, "secretsExists=" + File.Exists(secretPath));
            if (File.Exists(secretPath))
            {
                var redacted = RedactText(await File.ReadAllTextAsync(secretPath, ct));
                foreach (var line in redacted.Split('\n').Take(40))
                    Append(lines, line.TrimEnd('\r'));
            }

            Append(lines, "");
            Append(lines, "[Source health probe]");
            var probes = await _sourceHealth.ProbeAsync(ryuuCookie, null, ct);
            foreach (var probe in probes)
            {
                var code = probe.StatusCode?.ToString() ?? "n/a";
                Append(lines, $"- {(probe.Success ? "ok" : "fail")} {probe.Name} http={code} {probe.Message} ({probe.Duration.TotalMilliseconds:0}ms)");
            }

            if (appId > 0)
            {
                Append(lines, "");
                Append(lines, "[App context " + appId + "]");
                var lua = Path.Combine(unlock.LuaScriptDir, appId + ".lua");
                Append(lines, "luaInstalled=" + File.Exists(lua));
                if (File.Exists(lua))
                {
                    var luaText = RedactText(await File.ReadAllTextAsync(lua, ct));
                    Append(lines, "luaHead:");
                    foreach (var line in luaText.Split('\n').Take(20))
                        Append(lines, "  " + line.TrimEnd('\r'));
                }
            }

            Append(lines, "");
            Append(lines, "[Recent plugin log tail]");
            var logPath = Path.Combine(plugin.PluginPath, "backend", "debug.log");
            if (File.Exists(logPath))
            {
                foreach (var line in TailFile(logPath, 120))
                    Append(lines, RedactText(line));
            }
            else
            {
                Append(lines, "(no debug.log at " + logPath + ")");
            }

            var outDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Rewired",
                "diagnostics");
            Directory.CreateDirectory(outDir);
            var stamp = DateTime.UtcNow.ToString("yyyyMMdd-HHmmss");
            var suffix = appId > 0 ? "-" + appId : "";
            var outPath = Path.Combine(outDir, "rewired-support-" + stamp + suffix + ".txt");
            await File.WriteAllTextAsync(outPath, string.Join(Environment.NewLine, lines), Encoding.UTF8, ct);

            return (true, "Support bundle written.", outPath);
        }
        catch (Exception ex)
        {
            return (false, ex.Message, null);
        }
    }

    private static void Append(List<string> lines, string line) => lines.Add(line);

    private static string PresentMissing(bool value) => value ? "present" : "missing";

    private static string RedactText(string text)
    {
        if (string.IsNullOrEmpty(text)) return text;
        text = Regex.Replace(text, @"(ryuuSession|morrenusApiKey|manifestHubApiKey|api_key|cookie)\s*[:=]\s*[^\s""']+", "$1=[REDACTED]", RegexOptions.IgnoreCase);
        text = Regex.Replace(text, @"smm_[0-9a-f]{96}", "smm_[REDACTED]", RegexOptions.IgnoreCase);
        return text;
    }

    private static IEnumerable<string> TailFile(string path, int maxLines)
    {
        var queue = new Queue<string>();
        foreach (var line in File.ReadLines(path))
        {
            queue.Enqueue(line);
            while (queue.Count > maxLines)
                queue.Dequeue();
        }
        return queue;
    }
}
