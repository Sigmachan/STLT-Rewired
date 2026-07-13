using System.Diagnostics;

namespace RewiredManager.App.Services;

public sealed class SteamProcessService
{
    public bool IsSteamRunning() => IsSteamRunningStatic();

    public static bool IsSteamRunningStatic() =>
        Process.GetProcessesByName("steam").Length > 0
        || Process.GetProcessesByName("steamwebhelper").Length > 0;

    public bool IsSteamRunningInstance() => IsSteamRunningStatic();

    public async Task StopSteamAsync(CancellationToken ct = default)
    {
        foreach (var name in new[] { "steamwebhelper", "steam" })
        {
            foreach (var proc in Process.GetProcessesByName(name))
            {
                try
                {
                    if (!proc.HasExited)
                    {
                        proc.CloseMainWindow();
                        if (!proc.WaitForExit(4000))
                            proc.Kill(entireProcessTree: true);
                    }
                }
                catch
                {
                    // best effort
                }
                finally
                {
                    proc.Dispose();
                }
            }
        }

        for (var i = 0; i < 20; i++)
        {
            ct.ThrowIfCancellationRequested();
            if (!IsSteamRunningStatic()) return;
            await Task.Delay(250, ct);
        }
    }

    public void StartSteam(string steamPath)
    {
        var exe = Path.Combine(steamPath, "steam.exe");
        if (!File.Exists(exe))
            throw new FileNotFoundException("steam.exe not found", exe);

        Process.Start(new ProcessStartInfo
        {
            FileName = exe,
            WorkingDirectory = steamPath,
            UseShellExecute = true
        });
    }

    public async Task RestartSteamAsync(string steamPath, CancellationToken ct = default)
    {
        await StopSteamAsync(ct);
        await Task.Delay(1500, ct);
        StartSteam(steamPath);
    }
}
