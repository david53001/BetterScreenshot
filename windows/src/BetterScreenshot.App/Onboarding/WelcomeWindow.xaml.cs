using System.Windows;

namespace BetterScreenshot.App.Onboarding;

/// <summary>One-time first-run welcome: branding, a one-line blurb, and the hotkey cheat sheet.</summary>
public partial class WelcomeWindow : Window
{
    public WelcomeWindow()
    {
        InitializeComponent();
    }

    private void Start_Click(object sender, RoutedEventArgs e) => Close();
}
