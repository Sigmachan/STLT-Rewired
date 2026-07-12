using System.Windows;
using System.Windows.Controls;
using RewiredManager.App.Models;
using RewiredManager.App.Services;

namespace RewiredManager.App;

public partial class MainWindow : Window
{
    private readonly RewiredConfigService _configService = new();
    private readonly UnlockBackendService _unlock = new();
    private readonly PluginDiscoveryService _discovery = new();
    private readonly SecretStoreService _secrets = new();
    private readonly SourceHealthService _sourceHealth = new();
    private readonly OpenSteamToolInstallService _ostInstall = new();
    private readonly LuaGameInstallService _gameInstall = new();
    private readonly SteamProcessService _steamProcess = new();
    private readonly PluginDeployService _deploy = new();

    private RewiredSharedConfig _config = new();
    private UnlockBackendStatus? _unlockStatus;
    private PluginDiscoveryResult? _lastDiscovery;

    public MainWindow()
    {
        InitializeComponent();
        BackendCombo.ItemsSource = Enum.GetValues<UnlockBackendKind>();
        LoadConfig();
        RefreshUnlockStatus();
        InspectPlugin();
    }

    private void LoadConfig()
    {
        _config = _configService.Load();
        SteamPathBox.Text = _config.SteamPath ?? "";
        PluginPathBox.Text = _config.PluginPath ?? PluginDiscoveryService.DefaultLivePluginPath;
        RepoRootBox.Text = _config.RepoRoot ?? PluginDiscoveryService.DefaultRepoPath;
        BackendCombo.SelectedItem = _config.BackendKind;
        SharedConfigPathText.Text = "Config: " + RewiredConfigService.ConfigPath;
    }

    private void SaveConfig_Click(object sender, RoutedEventArgs e)
    {
        _config.SteamPath = SteamPathBox.Text.Trim();
        _config.PluginPath = PluginPathBox.Text.Trim();
        _config.RepoRoot = RepoRootBox.Text.Trim();
        if (BackendCombo.SelectedItem is UnlockBackendKind kind)
            _config.BackendKind = kind;
        _configService.Save(_config);
        FooterText.Text = "Configuration saved.";
        RefreshUnlockStatus();
    }

    private void RefreshUnlockStatus()
    {
        try
        {
            _unlockStatus = _unlock.Inspect(_config);
            var s = _unlockStatus;
            UnlockStatusText.Text = string.Join(Environment.NewLine, new[]
            {
                $"Resolved backend: {s.Resolved.DisplayName()}",
                $"Lua directory: {s.LuaScriptDir}",
                $"Depot cache: {s.DepotCacheDir}",
                $"OpenSteamTool.dll: {YesNo(s.OpenSteamToolDll)}",
                $"SteamTools markers: {YesNo(s.SteamToolsMarkers)}",
                $"LumaCore: {YesNo(s.LumaCoreDll)}",
                $"Ready to add games: {YesNo(s.ReadyForAdd)}",
            });
            FooterText.Text = s.ReadyForAdd
                ? "Unlock stack looks ready."
                : "Install OpenSteamTool or SteamTools, then restart Steam.";
        }
        catch (Exception ex)
        {
            UnlockStatusText.Text = "Could not inspect unlock stack: " + ex.Message;
            FooterText.Text = "Unlock inspection failed.";
        }
    }

    private void RefreshUnlock_Click(object sender, RoutedEventArgs e)
    {
        SaveConfigSilently();
        RefreshUnlockStatus();
    }

    private async void InstallOst_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            SaveConfigSilently();
            var steam = _config.SteamPath ?? SteamInstallService.TryDetectSteamPath()
                ?? throw new InvalidOperationException("Set Steam path first.");

            if (_steamProcess.IsSteamRunning())
            {
                FooterText.Text = "Stopping Steam before installing DLLs…";
                await _steamProcess.StopSteamAsync();
            }

            FooterText.Text = "Downloading OpenSteamTool from GitHub…";
            var result = await _ostInstall.InstallLatestAsync(steam);
            if (!result.Success)
            {
                FooterText.Text = result.Message;
                MessageBox.Show(this, result.Message, "OpenSteamTool", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            _config.BackendKind = UnlockBackendKind.OpenSteamTool;
            _configService.Save(_config);
            BackendCombo.SelectedItem = UnlockBackendKind.OpenSteamTool;
            RefreshUnlockStatus();
            FooterText.Text = result.Message;
            MessageBox.Show(this, result.Message + Environment.NewLine + string.Join(Environment.NewLine, result.InstalledFiles),
                "OpenSteamTool", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            FooterText.Text = "OST install failed: " + ex.Message;
            MessageBox.Show(this, ex.Message, "OpenSteamTool", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private async void RestartSteam_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            SaveConfigSilently();
            var steam = _config.SteamPath ?? SteamInstallService.TryDetectSteamPath()
                ?? throw new InvalidOperationException("Set Steam path first.");
            FooterText.Text = "Restarting Steam…";
            await _steamProcess.RestartSteamAsync(steam);
            FooterText.Text = "Steam restarted.";
        }
        catch (Exception ex)
        {
            FooterText.Text = "Restart failed: " + ex.Message;
        }
    }

    private async void AddGame_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            SaveConfigSilently();
            RefreshUnlockStatus();
            if (_unlockStatus == null)
            {
                AddGameResultText.Text = "Unlock status unavailable.";
                return;
            }

            if (!int.TryParse(AppIdBox.Text.Trim(), out var appId) || appId <= 0)
            {
                AddGameResultText.Text = "Enter a valid numeric AppID.";
                return;
            }

            var pluginPath = PluginPathBox.Text.Trim();
            var cookie = _secrets.ReadRyuuCookieHeader(pluginPath);
            if (string.IsNullOrWhiteSpace(cookie))
            {
                AddGameResultText.Text = "Ryuu session missing. Add ryuuSession to backend/data/secrets.local.json in the live plugin.";
                return;
            }

            FooterText.Text = $"Adding AppID {appId} via Ryuu…";
            AddGameResultText.Text = "Downloading…";
            var result = await _gameInstall.InstallFromRyuuAsync(appId, _unlockStatus, cookie);
            AddGameResultText.Text = result.Message + (result.LuaPath != null ? Environment.NewLine + result.LuaPath : "");
            FooterText.Text = result.Success ? "Game installed. Restart Steam if it was already running." : "Add failed.";
        }
        catch (Exception ex)
        {
            AddGameResultText.Text = ex.Message;
            FooterText.Text = "Add game failed.";
        }
    }

    private void Inspect_Click(object sender, RoutedEventArgs e) => InspectPlugin();

    private async void Probe_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            InspectPlugin();
            var pluginPath = _lastDiscovery?.PluginPath ?? PluginPathBox.Text;
            var cookie = _secrets.ReadRyuuCookieHeader(pluginPath);
            FooterText.Text = "Probing sources…";
            ProbeResultsList.Items.Clear();

            var results = await _sourceHealth.ProbeAsync(cookie);
            foreach (var result in results)
            {
                var marker = result.Success ? "OK" : "FAIL";
                var status = result.StatusCode.HasValue ? result.StatusCode.Value.ToString() : "n/a";
                ProbeResultsList.Items.Add($"[{marker}] {result.Name} — {result.Message} — HTTP {status} — {result.Duration.TotalMilliseconds:0} ms");
            }

            FooterText.Text = "Source probe complete.";
        }
        catch (Exception ex)
        {
            FooterText.Text = "Probe failed.";
            ProbeResultsList.Items.Add("[FAIL] " + ex.Message);
        }
    }

    private async void Deploy_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            SaveConfigSilently();
            var repo = RepoRootBox.Text.Trim();
            var steam = _config.SteamPath ?? SteamInstallService.TryDetectSteamPath()
                ?? throw new InvalidOperationException("Set Steam path first.");

            DeployLogBox.Text = "Running deploy.ps1…";
            FooterText.Text = "Deploying plugin…";
            var (ok, output) = await _deploy.DeployAsync(repo, steam);
            DeployLogBox.Text = output;
            FooterText.Text = ok ? "Deploy finished." : "Deploy failed.";
        }
        catch (Exception ex)
        {
            DeployLogBox.Text = ex.ToString();
            FooterText.Text = "Deploy error.";
        }
    }

    private void InspectPlugin()
    {
        _lastDiscovery = _discovery.Inspect(PluginPathBox.Text);
        var d = _lastDiscovery;
        PluginStatusText.Text = string.Join(Environment.NewLine, new[]
        {
            $"Path: {d.PluginPath}",
            $"Exists: {YesNo(d.Exists)}",
            $"Plugin JSON: {YesNo(d.HasPluginJson)}",
            $"Common name: {d.CommonName}",
            $"Version: {d.Version}",
            $"Backend: {YesNo(d.HasBackend)}",
            $"Webkit bundle: {YesNo(d.HasFrontendBundle)}",
            $"Secrets file: {YesNo(d.HasSecretsFile)}",
            $"Ryuu session: {PresentMissing(d.HasRyuuSession)}",
            $"Morrenus key: {PresentMissing(d.HasMorrenusKey)}",
            $"Usable: {YesNo(d.LooksUsable)}",
            "",
            "Millennium plugin is optional when Manager + OpenSteamTool are used.",
        });
    }

    private void SaveConfigSilently()
    {
        _config.SteamPath = SteamPathBox.Text.Trim();
        _config.PluginPath = PluginPathBox.Text.Trim();
        _config.RepoRoot = RepoRootBox.Text.Trim();
        if (BackendCombo.SelectedItem is UnlockBackendKind kind)
            _config.BackendKind = kind;
        _configService.Save(_config);
    }

    private static string YesNo(bool value) => value ? "yes" : "no";
    private static string PresentMissing(bool value) => value ? "present" : "missing";
}
