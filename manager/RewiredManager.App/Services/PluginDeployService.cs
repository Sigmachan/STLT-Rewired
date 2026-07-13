using System.Diagnostics;

namespace RewiredManager.App.Services;

public sealed class PluginDeployService
{
    public async Task<(bool Success, string Output)> DeployAsync(string repoRoot, string steamPath, CancellationToken ct = default)
    {
        var script = Path.Combine(repoRoot, "deploy.ps1");
        if (!File.Exists(script))
            return (false, $"deploy.ps1 not found at {script}");

        var psi = new ProcessStartInfo
        {
            FileName = "pwsh",
            ArgumentList =
            {
                "-NoProfile",
                "-File",
                script,
                "-SteamPath",
                steamPath
            },
            WorkingDirectory = repoRoot,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        using var proc = Process.Start(psi);
        if (proc == null)
            return (false, "Failed to start pwsh.");

        var stdout = await proc.StandardOutput.ReadToEndAsync(ct);
        var stderr = await proc.StandardError.ReadToEndAsync(ct);
        await proc.WaitForExitAsync(ct);

        var combined = (stdout + Environment.NewLine + stderr).Trim();
        return (proc.ExitCode == 0, combined.Length > 0 ? combined : $"Exit code {proc.ExitCode}");
    }

    public async Task<(bool Success, string Output)> RestoreAsync(string repoRoot, string steamPath, CancellationToken ct = default)
    {
        var script = Path.Combine(repoRoot, "deploy.ps1");
        if (!File.Exists(script))
            return (false, $"deploy.ps1 not found at {script}");

        var psi = new ProcessStartInfo
        {
            FileName = "pwsh",
            ArgumentList =
            {
                "-NoProfile",
                "-File",
                script,
                "-Restore",
                "-SteamPath",
                steamPath
            },
            WorkingDirectory = repoRoot,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        using var proc = Process.Start(psi);
        if (proc == null)
            return (false, "Failed to start pwsh.");

        var stdout = await proc.StandardOutput.ReadToEndAsync(ct);
        var stderr = await proc.StandardError.ReadToEndAsync(ct);
        await proc.WaitForExitAsync(ct);

        var combined = (stdout + Environment.NewLine + stderr).Trim();
        return (proc.ExitCode == 0, combined.Length > 0 ? combined : $"Exit code {proc.ExitCode}");
    }
}
