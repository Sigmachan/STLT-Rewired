using System.Windows;
using RewiredManager.App.Models;
using RewiredManager.App.Services;

namespace RewiredManager.App;

public partial class MainWindow : Window
{
    private readonly PluginDiscoveryService _discovery = new();
    private readonly SecretStoreService _secrets = new();
    private readonly SourceHealthService _sourceHealth = new();
    private PluginDiscoveryResult? _lastDiscovery;

    public MainWindow()
    {
        InitializeComponent();
        PluginPathBox.Text = PluginDiscoveryService.DefaultLivePluginPath;
        InspectPlugin();
    }

    private void Inspect_Click(object sender, RoutedEventArgs e) => InspectPlugin();

    private async void Probe_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            InspectPlugin();
            var pluginPath = _lastDiscovery?.PluginPath ?? PluginPathBox.Text;
            var cookie = _secrets.ReadRyuuCookieHeader(pluginPath);
            FooterText.Text = "Probing sources...";
            ProbeResultsList.Items.Clear();

            IReadOnlyList<SourceProbeResult> results = await _sourceHealth.ProbeAsync(cookie);
            foreach (var result in results)
            {
                var marker = result.Success ? "OK" : "FAIL";
                var status = result.StatusCode.HasValue ? result.StatusCode.Value.ToString() : "n/a";
                ProbeResultsList.Items.Add($"[{marker}] {result.Name} — {result.Message} — HTTP {status} — {result.Duration.TotalMilliseconds:0} ms");
            }

            FooterText.Text = "Source probe complete. Secrets were not printed.";
        }
        catch (Exception ex)
        {
            FooterText.Text = $"Probe failed: {ex.GetType().Name}";
            ProbeResultsList.Items.Add($"[FAIL] Probe exception: {ex.Message}");
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
        });
        FooterText.Text = d.LooksUsable ? "Plugin inspected." : "Plugin path does not look usable yet.";
    }

    private static string YesNo(bool value) => value ? "yes" : "no";
    private static string PresentMissing(bool value) => value ? "present" : "missing";
}
