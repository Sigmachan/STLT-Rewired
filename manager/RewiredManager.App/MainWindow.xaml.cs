using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Microsoft.Win32;
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
    private readonly SecretValidationService _secretValidation = new();
    private readonly ManagerUpdateService _managerUpdate = new();
    private readonly RewiredSetupService _setup = new();
    private readonly CloudRedirectAssistantService _cloudRedirect = new();
    private readonly InstalledInventoryService _inventory = new();
    private readonly RyuuCatalogService _catalog = new();
    private readonly HubcapStatsService _hubcapStats = new();
    private readonly DiagnosticsBundleService _diagnostics = new();
    private readonly PluginBackupService _pluginBackups = new();
    private readonly LocalFileInstallService _localInstall = new();
    private readonly MillenniumInfoService _millenniumInfo = new();

    private RewiredSharedConfig _config = new();
    private UnlockBackendStatus? _unlockStatus;
    private PluginDiscoveryResult? _lastDiscovery;
    private IReadOnlyList<RyuuCatalogEntry> _catalogResults = Array.Empty<RyuuCatalogEntry>();

    private bool _navReady;

    public MainWindow()
    {
        InitializeComponent();
        BackendCombo.ItemsSource = Enum.GetValues<UnlockBackendKind>();
        LoadConfig();
        RefreshUnlockStatus();
        InspectPlugin();
        LoadSecretsFields();
        _ = RefreshUpdateStatusAsync();
        Loaded += MainWindow_Loaded;
        _navReady = true;
        FooterVersionText.Text = "Rewired " + typeof(MainWindow).Assembly.GetName().Version?.ToString(3);
        RefreshMillenniumFooter();
        NavList.SelectedIndex = 0;
        ShowPage("home");
    }

    private void NavList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_navReady) return;
        if (NavList.SelectedItem is ListBoxItem item && item.Tag is string tag)
            ShowPage(tag);
    }

    private void ShowPage(string tag)
    {
        if (PageHome == null) return;
        PageHome.Visibility = tag == "home" ? Visibility.Visible : Visibility.Collapsed;
        PageAdd.Visibility = tag == "add" ? Visibility.Visible : Visibility.Collapsed;
        PageManage.Visibility = tag == "manage" ? Visibility.Visible : Visibility.Collapsed;
        PageMode.Visibility = tag == "mode" ? Visibility.Visible : Visibility.Collapsed;
        PageFixes.Visibility = tag == "fixes" ? Visibility.Visible : Visibility.Collapsed;
        PagePlugin.Visibility = tag == "plugin" ? Visibility.Visible : Visibility.Collapsed;
        PageSettings.Visibility = tag == "settings" ? Visibility.Visible : Visibility.Collapsed;
        ContentScroll.ScrollToVerticalOffset(0);
        if (tag == "manage")
            RefreshManageList();
        if (tag == "plugin")
            RefreshBackupList();
    }

    private void MainWindow_Loaded(object sender, RoutedEventArgs e)
    {
        try
        {
            var readiness = _setup.Assess(_config.SteamPath);
            if (readiness.NeedsSetup)
            {
                var wizard = new SetupWizardWindow { Owner = this };
                wizard.ShowDialog();
                if (wizard.SetupSucceeded)
                {
                    LoadConfig();
                    RefreshUnlockStatus();
                    InspectPlugin();
                }
            }
        }
        catch
        {
            // non-fatal on startup
        }
    }

    private void SetupWizard_Click(object sender, RoutedEventArgs e)
    {
        var wizard = new SetupWizardWindow { Owner = this };
        wizard.ShowDialog();
        if (wizard.SetupSucceeded)
        {
            LoadConfig();
            RefreshUnlockStatus();
            InspectPlugin();
            FooterText.Text = "Setup finished.";
        }
    }

    private async Task RefreshUpdateStatusAsync()
    {
        try
        {
            var status = await _managerUpdate.CheckAsync();
            UpdateStatusText.Text = $"Manager {status.CurrentVersion} | Latest {status.LatestVersion}" +
                (status.UpdateAvailable ? " (update available)" : " (up to date)");
        }
        catch (Exception ex)
        {
            UpdateStatusText.Text = "Update check failed: " + ex.Message;
        }
    }

    private async void CheckUpdates_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            SaveConfigSilently();
            FooterText.Text = "Checking GitHub releases…";
            var status = await _managerUpdate.CheckAsync();
            await RefreshUpdateStatusAsync();

            if (!status.UpdateAvailable)
            {
                FooterText.Text = "Already up to date.";
                MessageBox.Show(this, $"Rewired {status.LatestVersion} is current.", "Updates", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }

            var steam = _config.SteamPath ?? SteamInstallService.TryDetectSteamPath() ?? "";
            var msg = $"Update to {status.LatestVersion}?\n\nApplies Manager + live plugin (preserves secrets). Restart Steam after.";
            if (MessageBox.Show(this, msg, "Rewired update", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes)
            {
                FooterText.Text = "Update cancelled.";
                return;
            }

            var mgr = await _managerUpdate.ApplyManagerUpdateAsync();
            if (!string.IsNullOrEmpty(steam))
            {
                var plug = await _managerUpdate.ApplyPluginUpdateAsync(steam);
                FooterText.Text = mgr.Message + " " + plug.Message;
                MessageBox.Show(this, mgr.Message + Environment.NewLine + plug.Message, "Updates", MessageBoxButton.OK, MessageBoxImage.Information);
            }
            else
            {
                FooterText.Text = mgr.Message;
                MessageBox.Show(this, mgr.Message, "Updates", MessageBoxButton.OK, MessageBoxImage.Information);
            }
        }
        catch (Exception ex)
        {
            FooterText.Text = "Update failed.";
            MessageBox.Show(this, ex.Message, "Updates", MessageBoxButton.OK, MessageBoxImage.Error);
        }
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
            RefreshCloudRedirectStatus(s.SteamPath);
            RefreshModeCards(s);
            RefreshHomeBadges();
            RefreshMillenniumFooter();
            SidebarStatusText.Text = s.ReadyForAdd ? "Stack ready" : "Setup needed";
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

    private void RefreshManage_Click(object sender, RoutedEventArgs e)
    {
        SaveConfigSilently();
        RefreshUnlockStatus();
        RefreshManageList();
    }

    private void RefreshCloudRedirectStatus(string? steamPath)
    {
        var detect = _cloudRedirect.Detect(steamPath);
        var text = detect.Detected
            ? "Detected on disk:\n" + string.Join(Environment.NewLine, detect.Paths)
            : "Not detected. Launch downloads to %LOCALAPPDATA%\\Rewired\\cloudredirect\\.";
        ModeCloudRedirectStatusText.Text = text;
    }

    private void RefreshModeCards(UnlockBackendStatus s)
    {
        var ostActive = s.Resolved == UnlockBackendKind.OpenSteamTool;
        ModeOstStatusText.Text = s.OpenSteamToolDll
            ? (ostActive ? "Active — OpenSteamTool.dll present." : "Installed — switch preference to OpenSteamTool to use it.")
            : "Not installed — use Install OpenSteamTool below.";

        var stActive = s.Resolved == UnlockBackendKind.SteamTools;
        ModeSteamToolsStatusText.Text = s.SteamToolsMarkers
            ? (stActive ? "Active — SteamTools markers found." : "Detected — set preference to SteamTools if intentional.")
            : "Not detected — install SteamTools manually if you need that stack.";
    }

    private void RefreshManageList()
    {
        InstalledScriptsList.Items.Clear();
        if (_unlockStatus == null)
        {
            ManageLuaCountText.Text = "—";
            ManageManifestCountText.Text = "—";
            ManagePathsText.Text = "";
            InstalledScriptsList.Items.Add("Refresh status on Home first.");
            return;
        }

        var summary = _inventory.Scan(_unlockStatus);
        ManageLuaCountText.Text = summary.LuaScripts.Count.ToString();
        ManageManifestCountText.Text = summary.Manifests.Count.ToString();
        ManagePathsText.Text = $"Lua: {summary.LuaDirectory}{Environment.NewLine}Depot: {summary.DepotCacheDirectory}";

        if (summary.LuaScripts.Count == 0)
        {
            InstalledScriptsList.Items.Add("No .lua scripts installed yet.");
            return;
        }

        foreach (var file in summary.LuaScripts)
            InstalledScriptsList.Items.Add(file);
    }

    private void RefreshMillenniumFooter()
    {
        var steam = _config.SteamPath ?? SteamInstallService.TryDetectSteamPath() ?? "";
        var mil = _millenniumInfo.Inspect(steam);
        FooterMillenniumText.Text = mil.Installed
            ? $"Millennium {mil.Version}" + (mil.VersionCompatible ? "" : " (update recommended)")
            : "Millennium not detected";
    }

    private void RefreshBackupList()
    {
        PluginBackupsList.Items.Clear();
        var steam = _config.SteamPath ?? SteamInstallService.TryDetectSteamPath();
        if (string.IsNullOrWhiteSpace(steam))
        {
            PluginBackupsList.Items.Add("Set Steam path first.");
            return;
        }

        var backups = _pluginBackups.ListBackups(steam);
        if (backups.Count == 0)
        {
            PluginBackupsList.Items.Add("No plugin backups yet (deploy creates one).");
            return;
        }

        foreach (var backup in backups)
            PluginBackupsList.Items.Add($"{backup.Name} ({backup.CreatedUtc:yyyy-MM-dd HH:mm} UTC)");
    }

    private async void SearchCatalog_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            CatalogSearchStatusText.Text = "Searching…";
            CatalogResultsList.Items.Clear();
            _catalogResults = Array.Empty<RyuuCatalogEntry>();

            var query = CatalogSearchBox.Text.Trim();
            var pluginPath = PluginPathBox.Text.Trim();
            var cookie = _secrets.ReadRyuuCookieHeader(pluginPath);
            if (string.IsNullOrWhiteSpace(cookie))
                cookie = RyuuSessionBox.Text;

            var result = await _catalog.SearchAsync(query, cookie);
            _catalogResults = result.Results;
            CatalogSearchStatusText.Text = result.Message;

            foreach (var entry in result.Results)
                CatalogResultsList.Items.Add($"{entry.AppId} — {entry.Name} ({entry.Source})");

            if (result.Results.Count == 0 && !result.Success)
                CatalogSearchStatusText.Text = result.Message;
        }
        catch (Exception ex)
        {
            CatalogSearchStatusText.Text = ex.Message;
        }
    }

    private async void WarmCatalog_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            CatalogSearchStatusText.Text = "Downloading Ryuu catalog (~40 MB, first run may take a minute)…";
            var pluginPath = PluginPathBox.Text.Trim();
            var cookie = _secrets.ReadRyuuCookieHeader(pluginPath);
            if (string.IsNullOrWhiteSpace(cookie))
                cookie = RyuuSessionBox.Text;

            var warm = await _catalog.WarmCacheAsync(cookie);
            CatalogSearchStatusText.Text = warm.Message;
            FooterText.Text = warm.Success ? "Catalog cache ready." : "Catalog cache failed.";
        }
        catch (Exception ex)
        {
            CatalogSearchStatusText.Text = ex.Message;
        }
    }

    private void CatalogResultsList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (CatalogResultsList.SelectedIndex < 0 || CatalogResultsList.SelectedIndex >= _catalogResults.Count)
            return;
        AppIdBox.Text = _catalogResults[CatalogResultsList.SelectedIndex].AppId.ToString();
    }

    private void InstallSelectedCatalog_Click(object sender, RoutedEventArgs e)
    {
        if (CatalogResultsList.SelectedIndex < 0 || CatalogResultsList.SelectedIndex >= _catalogResults.Count)
        {
            AddGameResultText.Text = "Select a game from the catalog first.";
            return;
        }

        AppIdBox.Text = _catalogResults[CatalogResultsList.SelectedIndex].AppId.ToString();
        AddGame_Click(sender, e);
    }

    private async void InstallLocalFile_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            SaveConfigSilently();
            RefreshUnlockStatus();
            if (_unlockStatus == null)
            {
                LocalFileResultText.Text = "Unlock status unavailable.";
                return;
            }

            var dialog = new OpenFileDialog
            {
                Filter = "Unlock files|*.lua;*.manifest;*.zip|All files|*.*",
                Title = "Select unlock file"
            };
            if (dialog.ShowDialog(this) != true)
                return;

            FooterText.Text = "Installing local file…";
            LocalFileResultText.Text = "Installing…";
            var result = await _localInstall.InstallFromFileAsync(dialog.FileName, _unlockStatus);
            LocalFileResultText.Text = result.Message;
            FooterText.Text = result.Success ? "Local file installed." : "Local install failed.";
            if (result.Success)
                RefreshManageList();
        }
        catch (Exception ex)
        {
            LocalFileResultText.Text = ex.Message;
            FooterText.Text = "Local install failed.";
        }
    }

    private void OpenLuaFolder_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            if (_unlockStatus == null) throw new InvalidOperationException("Refresh unlock status first.");
            InstalledInventoryService.OpenFolder(_unlockStatus.LuaScriptDir);
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "Open folder", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private void OpenDepotFolder_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            if (_unlockStatus == null) throw new InvalidOperationException("Refresh unlock status first.");
            InstalledInventoryService.OpenFolder(_unlockStatus.DepotCacheDir);
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "Open folder", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private void RemoveScript_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            if (_unlockStatus == null)
            {
                MessageBox.Show(this, "Refresh unlock status first.", "Remove script", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            if (InstalledScriptsList.SelectedItem is not string fileName)
            {
                MessageBox.Show(this, "Select a script to remove.", "Remove script", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }

            if (MessageBox.Show(this, $"Remove {fileName}?", "Remove script", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes)
                return;

            var result = _inventory.RemoveLuaScript(_unlockStatus, fileName);
            FooterText.Text = result.Message;
            if (!result.Success)
                MessageBox.Show(this, result.Message, "Remove script", MessageBoxButton.OK, MessageBoxImage.Warning);
            RefreshManageList();
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "Remove script", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private async void LoadHubcapStats_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            HubcapStatsText.Text = "Loading ManifestHub stats…";
            var stats = await _hubcapStats.FetchAsync(ManifestHubKeyBox.Text);
            HubcapStatsText.Text = stats.Message;
        }
        catch (Exception ex)
        {
            HubcapStatsText.Text = ex.Message;
        }
    }

    private async void ExportDiagnostics_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            SaveConfigSilently();
            DiagnosticsResultText.Text = "Building support bundle…";
            var pluginPath = PluginPathBox.Text.Trim();
            var cookie = _secrets.ReadRyuuCookieHeader(pluginPath);
            if (string.IsNullOrWhiteSpace(cookie))
                cookie = RyuuSessionBox.Text;

            _ = int.TryParse(DiagnosticsAppIdBox.Text.Trim(), out var appId);

            var result = await _diagnostics.ExportAsync(_config, pluginPath, cookie, appId);
            DiagnosticsResultText.Text = result.Success
                ? result.Message + Environment.NewLine + result.Path
                : result.Message;
            FooterText.Text = result.Success ? "Diagnostics exported." : "Diagnostics export failed.";

            if (result.Success && !string.IsNullOrWhiteSpace(result.Path))
            {
                var open = MessageBox.Show(this, "Open the diagnostics folder?", "Diagnostics",
                    MessageBoxButton.YesNo, MessageBoxImage.Question);
                if (open == MessageBoxResult.Yes)
                    InstalledInventoryService.OpenFolder(Path.GetDirectoryName(result.Path)!);
            }
        }
        catch (Exception ex)
        {
            DiagnosticsResultText.Text = ex.Message;
        }
    }

    private void RefreshBackups_Click(object sender, RoutedEventArgs e) => RefreshBackupList();

    private async void RestorePlugin_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            SaveConfigSilently();
            var repo = RepoRootBox.Text.Trim();
            var steam = _config.SteamPath ?? SteamInstallService.TryDetectSteamPath()
                ?? throw new InvalidOperationException("Set Steam path first.");

            if (MessageBox.Show(this,
                    "Restore the latest plugin backup? Close Steam first if Millennium is running.",
                    "Restore plugin",
                    MessageBoxButton.YesNo,
                    MessageBoxImage.Question) != MessageBoxResult.Yes)
                return;

            DeployLogBox.Text = "Running deploy.ps1 -Restore…";
            FooterText.Text = "Restoring plugin backup…";
            var (ok, output) = await _deploy.RestoreAsync(repo, steam);
            DeployLogBox.Text = output;
            FooterText.Text = ok ? "Plugin restored." : "Restore failed.";
            InspectPlugin();
            RefreshBackupList();
        }
        catch (Exception ex)
        {
            DeployLogBox.Text = ex.ToString();
            FooterText.Text = "Restore error.";
        }
    }

    private void RefreshHomeBadges()
    {
        var unlockOk = _unlockStatus?.ReadyForAdd == true;
        SetBadge(HomeUnlockBadge, unlockOk ? "Ready" : "Setup", unlockOk);

        var pluginOk = _lastDiscovery?.LooksUsable == true;
        SetBadge(HomePluginBadge, pluginOk ? "OK" : "Missing", pluginOk);

        var pluginPath = PluginPathBox.Text.Trim();
        var hasRyuu = !string.IsNullOrWhiteSpace(_secrets.Load(pluginPath).RyuuSession);
        SetBadge(HomeRyuuBadge, hasRyuu ? "Set" : "Empty", hasRyuu);
    }

    private void SetBadge(TextBlock block, string text, bool ok)
    {
        block.Text = text;
        block.Foreground = ok
            ? (Brush)FindResource("SteamSuccess")
            : (Brush)FindResource("SteamWarn");
    }

    private async void TestRyuuFixes_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            FixesResultText.Text = "Testing Ryuu fixes endpoint…";
            var pluginPath = PluginPathBox.Text.Trim();
            var cookie = _secrets.ReadRyuuCookieHeader(pluginPath);
            if (string.IsNullOrWhiteSpace(cookie))
                cookie = RyuuSessionBox.Text;

            var result = await _secretValidation.ValidateRyuuFixesAsync(cookie);
            FixesResultText.Text = result.Message;
        }
        catch (Exception ex)
        {
            FixesResultText.Text = ex.Message;
        }
    }

    private async void LaunchCloudRedirect_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            SaveConfigSilently();
            FooterText.Text = "Preparing CloudRedirect…";
            var result = await _cloudRedirect.LaunchAsync();
            RefreshCloudRedirectStatus(_config.SteamPath);
            FooterText.Text = result.Success ? "CloudRedirect launched." : "CloudRedirect failed.";
            if (!result.Success)
                MessageBox.Show(this, result.Message, "CloudRedirect", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
        catch (Exception ex)
        {
            FooterText.Text = "CloudRedirect error.";
            MessageBox.Show(this, ex.Message, "CloudRedirect", MessageBoxButton.OK, MessageBoxImage.Error);
        }
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

    private async void LaunchSteam_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            SaveConfigSilently();
            var steam = _config.SteamPath ?? SteamInstallService.TryDetectSteamPath()
                ?? throw new InvalidOperationException("Set Steam path first.");

            if (_steamProcess.IsSteamRunning())
            {
                var restart = MessageBox.Show(this,
                    "Steam is already running. Restart it so OpenSteamTool and the in-Steam UI load?",
                    "Launch Steam",
                    MessageBoxButton.YesNo,
                    MessageBoxImage.Question);
                if (restart != MessageBoxResult.Yes)
                {
                    FooterText.Text = "Steam left running.";
                    return;
                }
                FooterText.Text = "Restarting Steam…";
                await _steamProcess.RestartSteamAsync(steam);
                FooterText.Text = "Steam restarted with Rewired stack.";
            }
            else
            {
                FooterText.Text = "Launching Steam…";
                _steamProcess.StartSteam(steam);
                FooterText.Text = "Steam launched — use this app to start Steam (ACCELA-style).";
            }
        }
        catch (Exception ex)
        {
            FooterText.Text = "Launch failed: " + ex.Message;
            MessageBox.Show(this, ex.Message, "Launch Steam", MessageBoxButton.OK, MessageBoxImage.Error);
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
                AddGameResultText.Text = "Ryuu session missing. Open the Secrets tab and save ryuuSession first.";
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

    private void LoadSecretsFields()
    {
        var pluginPath = PluginPathBox.Text.Trim();
        var secrets = _secrets.Load(pluginPath);
        SecretsPathText.Text = secrets.SecretsPath;
        RyuuSessionBox.Text = secrets.RyuuSession;
        ManifestHubKeyBox.Text = secrets.ManifestHubKey;
    }

    private void LoadSecrets_Click(object sender, RoutedEventArgs e)
    {
        LoadSecretsFields();
        SecretsResultText.Text = "Secrets loaded from disk.";
        InspectPlugin();
    }

    private void SaveSecrets_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var pluginPath = PluginPathBox.Text.Trim();
            _secrets.Save(pluginPath, RyuuSessionBox.Text, ManifestHubKeyBox.Text);
            SecretsResultText.Text = "Secrets saved.";
            FooterText.Text = "Secrets saved to plugin data directory.";
            InspectPlugin();
            RefreshHomeBadges();
        }
        catch (Exception ex)
        {
            SecretsResultText.Text = "Save failed: " + ex.Message;
        }
    }

    private async void TestRyuu_Click(object sender, RoutedEventArgs e)
    {
        SecretsResultText.Text = "Testing Ryuu session…";
        var result = await _secretValidation.ValidateRyuuAsync(RyuuSessionBox.Text);
        SecretsResultText.Text = result.Message;
    }

    private async void TestManifestHub_Click(object sender, RoutedEventArgs e)
    {
        SecretsResultText.Text = "Testing ManifestHub key…";
        var result = await _secretValidation.ValidateManifestHubAsync(ManifestHubKeyBox.Text);
        SecretsResultText.Text = result.Message;
        if (result.Success)
        {
            var stats = await _hubcapStats.FetchAsync(ManifestHubKeyBox.Text);
            HubcapStatsText.Text = stats.Message;
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
            var hubKey = _secrets.Load(pluginPath).ManifestHubKey;
            if (string.IsNullOrWhiteSpace(hubKey))
                hubKey = ManifestHubKeyBox.Text;

            FooterText.Text = "Probing sources…";
            ProbeResultsList.Items.Clear();

            var results = await _sourceHealth.ProbeAsync(cookie, hubKey);
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

            if (_steamProcess.IsSteamRunning())
            {
                var proceed = MessageBox.Show(this,
                    "Steam всё ещё запущен. Для обновления Millennium runtime лучше полностью закрыть Steam.\n\nПродолжить deploy?",
                    "Deploy plugin",
                    MessageBoxButton.YesNo,
                    MessageBoxImage.Warning);
                if (proceed != MessageBoxResult.Yes)
                {
                    FooterText.Text = "Deploy отменён — закройте Steam и повторите.";
                    return;
                }
            }

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
        RefreshHomeBadges();
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
