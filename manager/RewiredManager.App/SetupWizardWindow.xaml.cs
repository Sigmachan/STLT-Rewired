using System.Windows;
using System.Windows.Controls;
using RewiredManager.App.Models;
using RewiredManager.App.Services;

namespace RewiredManager.App;

public partial class SetupWizardWindow : Window
{
    private readonly RewiredSetupService _setup = new();
    private readonly SteamProcessService _steamProcess = new();
    private bool _running;

    public bool SetupSucceeded { get; private set; }

    public SetupWizardWindow()
    {
        InitializeComponent();
        Loaded += (_, _) => RefreshReadiness();
    }

    private void RefreshReadiness()
    {
        var readiness = _setup.Assess(SteamPathBox.Text.Trim());
        if (!string.IsNullOrWhiteSpace(readiness.SteamPath))
            SteamPathBox.Text = readiness.SteamPath;

        if (!readiness.SteamFound)
        {
            ReadinessText.Text = "Steam not found — set path or install Steam first.";
            return;
        }

        ReadinessText.Text =
            $"Millennium: {(readiness.MillenniumPresent ? "yes" : "no")} · " +
            $"OpenSteamTool: {(readiness.OpenSteamToolPresent ? "yes" : "no")} · " +
            $"Plugin: {(readiness.PluginPresent ? "yes" : "no")}";
    }

    private void DetectSteam_Click(object sender, RoutedEventArgs e)
    {
        var path = SteamInstallService.TryDetectSteamPath();
        if (path is not null)
            SteamPathBox.Text = path;
        RefreshReadiness();
    }

    private async void RunSetup_Click(object sender, RoutedEventArgs e)
    {
        if (_running) return;

        if (InstallUiCheck.IsChecked == true && _steamProcess.IsSteamRunning())
        {
            var close = MessageBox.Show(this,
                "Steam is running. Exit Steam fully before installing the in-Steam UI runtime.\n\nClose Steam now?",
                "Rewired setup",
                MessageBoxButton.YesNo,
                MessageBoxImage.Question);
            if (close != MessageBoxResult.Yes) return;

            try
            {
                RunButton.IsEnabled = false;
                AppendLog("Closing Steam…");
                await _steamProcess.StopSteamAsync();
                AppendLog("Steam closed.");
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, ex.Message, "Rewired setup", MessageBoxButton.OK, MessageBoxImage.Error);
                RunButton.IsEnabled = true;
                return;
            }
        }

        _running = true;
        RunButton.IsEnabled = false;
        LogText.Text = "";

        var options = new SetupOptions
        {
            SteamPath = SteamPathBox.Text.Trim(),
            InstallInSteamUi = InstallUiCheck.IsChecked == true,
            InstallOpenSteamTool = InstallOstCheck.IsChecked == true,
            CreateDesktopShortcut = ShortcutCheck.IsChecked == true
        };

        var progress = new Progress<string>(AppendLog);
        var result = await _setup.RunAsync(options, progress);

        _running = false;
        RunButton.IsEnabled = true;
        SetupSucceeded = result.Success;
        RefreshReadiness();

        if (result.Success)
        {
            MessageBox.Show(this, result.Summary, "Rewired", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        else
        {
            MessageBox.Show(this, result.Summary, "Rewired setup failed", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private void AppendLog(string line)
    {
        LogText.Text += line + Environment.NewLine;
        LogScroll.ScrollToEnd();
    }

    private void Close_Click(object sender, RoutedEventArgs e) => Close();
}
