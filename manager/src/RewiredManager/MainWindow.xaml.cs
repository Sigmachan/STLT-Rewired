using System.Windows;
using RewiredManager.Core;
using RewiredManager.Services;

namespace RewiredManager;

public partial class MainWindow : Window
{
    private readonly PluginLocator _locator = new();
    private SecretsStore? _secrets;

    public MainWindow()
    {
        InitializeComponent();
        RefreshStatus();
    }

    private void RefreshStatus()
    {
        if (!_locator.TryLocate())
        {
            StatusText.Text = "Steam or the Rewired plugin was not found.\n\nExpected:\n  …\\Steam\\millennium\\plugins\\luatools";
            PluginVersionText.Text = "";
            SecretsText.Text = "";
            return;
        }

        var info = _locator.ReadPluginInfo();
        StatusText.Text = $"Steam: {_locator.SteamPath}\nPlugin: {_locator.PluginPath}";
        PluginVersionText.Text = info is null
            ? "plugin.json: unreadable"
            : $"{info.CommonName ?? info.Name} v{info.Version ?? "?"}";

        _secrets = new SecretsStore(_locator.SecretsPath!);
        var snap = _secrets.Load();
        SecretsText.Text =
            $"Ryuu session: {(snap.HasRyuuSession ? "configured" : "not set")}\n" +
            $"ManifestHub key: {(snap.HasManifestHubKey ? "configured" : "not set")}";
    }

    private async void TestManifestHub_Click(object sender, RoutedEventArgs e)
    {
        var key = ManifestHubKeyBox.Password.Trim();
        if (string.IsNullOrEmpty(key))
        {
            HubResultText.Text = "Enter a ManifestHub API key first.";
            return;
        }

        HubResultText.Text = "Testing…";
        var client = new ManifestHubClient();
        var result = await client.ValidateKeyAsync(key);
        HubResultText.Text = result.Success
            ? $"OK — user: {result.Username ?? "?"}, used: {result.Used ?? "?"} / {result.Limit ?? "?"}"
            : $"Failed — {result.Error ?? "unknown error"}";
    }

    private void SaveManifestHub_Click(object sender, RoutedEventArgs e)
    {
        if (_secrets is null || _locator.SecretsPath is null)
        {
            HubResultText.Text = "Plugin not located; cannot save.";
            return;
        }

        _secrets.Save(manifestHubKey: ManifestHubKeyBox.Password.Trim());
        RefreshStatus();
        HubResultText.Text = "Saved to secrets.local.json (values never logged).";
    }

    private void Refresh_Click(object sender, RoutedEventArgs e) => RefreshStatus();
}
