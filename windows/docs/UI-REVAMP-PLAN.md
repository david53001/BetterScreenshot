# Windows UI Revamp Implementation Plan

> **✅ STATUS: SHIPPED (2026-07-03).** All 7 tasks are implemented and committed on `windows-port`
> (`c488288` key names → `ebde85c` theme → `22cc341` settings → `e57a074` Quick Access → `e0cf9a3` editor →
> `286324c` remaining surfaces → `6cf645f` `--ui-preview`), followed by two owner-reported polish fixes
> (`0a65b0d` Capture-Text/selection-overlay, `e9704df` Quick Access hover-bleed + editor image-hug) and a
> deploy on 2026-07-03 16:42 (`dist/` republished + tray relaunched). Build clean 0/0; 241 tests green.
> The step checkboxes below are marked done for history — see `PROGRESS.md` for the running ledger.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the Windows port a coherent dark, macOS-like UI (rounded themed controls everywhere, icon
toolbars) and fix three behaviors: settings apply instantly (no Save/Cancel trap), hotkeys render as
readable key names (`Alt+.` not `Alt+(vk 190)`), and dragging the Quick Access thumbnail out dismisses
the card.

**Architecture:** One app-wide `Theme.xaml` ResourceDictionary (palette + implicit ControlTemplates)
merged in `App.xaml` restyles every control by default; a `WindowThemer` P/Invoke helper darkens DWM
title bars; per-window edits then only touch colors/structure, not control chrome. Settings becomes
instant-apply. A flag-gated `--ui-preview` path opens any single window with sample data for screenshot
verification.

**Tech Stack:** .NET 9, WPF (net9.0-windows10.0.19041.0), xUnit, WinForms interop (tray), dwmapi.

**Spec:** `windows/docs/UI-REVAMP-SPEC.md` (root-cause findings + design tokens live there).

## Global Constraints

- Repo root: `C:\Users\david_v0a3rlc\Sorted\Coding\Apps\BetterScreenshot`; all paths below are repo-relative. Branch: `windows-port`. Commit locally after every task; **never push**.
- Build: `dotnet build windows/BetterScreenshot.sln` → 0 errors. Tests: `dotnet test windows/tests/BetterScreenshot.Tests` → all green (baseline 214).
- The App project references both WPF and WinForms — ambiguous types (`Button`, `Color`, `Brushes`, …) need explicit `using X = System.Windows.…` aliases; follow each file's existing alias block.
- Palette/token names are fixed by the spec (`Theme.WindowBrush` = `#232326`, `Theme.ChromeBrush` = `#1C1C1F`, `Theme.CardBrush` = `#2C2C30`, `Theme.ControlBrush` = `#3A3A3F`, hover `#47474D`, pressed `#525259`, subtle hover `#1AFFFFFF`, border `#26FFFFFF`, text `#F2F2F5`, secondary `#9A9AA2`, accent `#0A84FF`, danger `#FF453A`).
- No cloud/telemetry; local-only behavior unchanged.

---

### Task 1: Readable hotkey key names (pure logic, TDD)

**Files:**
- Modify: `windows/src/BetterScreenshot.Capture/Hotkeys.cs` (the `KeyName` switch, ~line 94)
- Test: `windows/tests/BetterScreenshot.Tests/HotkeyTests.cs`

**Interfaces:**
- Consumes: `HotkeyCombo.KeyName(uint vk)` (existing static), `HotkeyCombo.DisplayString`.
- Produces: `KeyName` handles OEM + navigation + numpad VKs; everything downstream (settings chips, tray menu) just works.

- [x] **Step 1: Write the failing tests** — append to the existing test class in `HotkeyTests.cs`:

```csharp
    [Theory]
    [InlineData(0xBAu, ";")]
    [InlineData(0xBBu, "=")]
    [InlineData(0xBCu, ",")]
    [InlineData(0xBDu, "-")]
    [InlineData(0xBEu, ".")]
    [InlineData(0xBFu, "/")]
    [InlineData(0xC0u, "`")]
    [InlineData(0xDBu, "[")]
    [InlineData(0xDCu, "\\")]
    [InlineData(0xDDu, "]")]
    [InlineData(0xDEu, "'")]
    [InlineData(0x2Cu, "PrtSc")]
    [InlineData(0x2Du, "Ins")]
    [InlineData(0x2Eu, "Del")]
    [InlineData(0x21u, "PgUp")]
    [InlineData(0x22u, "PgDn")]
    [InlineData(0x23u, "End")]
    [InlineData(0x24u, "Home")]
    [InlineData(0x13u, "Pause")]
    [InlineData(0x60u, "Num0")]
    [InlineData(0x69u, "Num9")]
    [InlineData(0x6Au, "Num*")]
    [InlineData(0x6Bu, "Num+")]
    [InlineData(0x6Du, "Num-")]
    [InlineData(0x6Eu, "Num.")]
    [InlineData(0x6Fu, "Num/")]
    public void KeyName_maps_oem_navigation_and_numpad_keys(uint vk, string expected)
        => Assert.Equal(expected, HotkeyCombo.KeyName(vk));

    [Fact]
    public void DisplayString_renders_the_users_alt_period_binding()
        => Assert.Equal("Alt+.", new HotkeyCombo(0xBE, HotkeyModifiers.Alt).DisplayString);
```

- [x] **Step 2: Run to verify failure** — `dotnet test windows/tests/BetterScreenshot.Tests --filter KeyName` → the new theory FAILS (`(vk 186)` ≠ `;`).

- [x] **Step 3: Implement** — in `Hotkeys.cs`, extend the `KeyName` switch. US-layout labels for OEM keys (documented assumption; recorder stores raw VKs). Insert the new arms before the final `_ =>` arm:

```csharp
    public static string KeyName(uint vk) => vk switch
    {
        >= 0x30 and <= 0x39 => ((char)vk).ToString(),  // 0-9
        >= 0x41 and <= 0x5A => ((char)vk).ToString(),  // A-Z
        >= 0x70 and <= 0x7B => $"F{vk - 0x6F}",         // F1-F12
        >= 0x60 and <= 0x69 => $"Num{vk - 0x60}",       // numpad digits
        0x20 => "Space",
        0x0D => "Enter",
        0x1B => "Esc",
        0x08 => "Backspace",
        0x09 => "Tab",
        0x25 => "←", // left
        0x26 => "↑", // up
        0x27 => "→", // right
        0x28 => "↓", // down
        0x21 => "PgUp",
        0x22 => "PgDn",
        0x23 => "End",
        0x24 => "Home",
        0x2C => "PrtSc",
        0x2D => "Ins",
        0x2E => "Del",
        0x13 => "Pause",
        0x6A => "Num*",
        0x6B => "Num+",
        0x6D => "Num-",
        0x6E => "Num.",
        0x6F => "Num/",
        // OEM punctuation — US-layout labels (VK_OEM_1..VK_OEM_7); good enough for display.
        0xBA => ";",
        0xBB => "=",
        0xBC => ",",
        0xBD => "-",
        0xBE => ".",
        0xBF => "/",
        0xC0 => "`",
        0xDB => "[",
        0xDC => "\\",
        0xDD => "]",
        0xDE => "'",
        _ => $"(vk {vk})",
    };
```

- [x] **Step 4: Run all tests** — `dotnet test windows/tests/BetterScreenshot.Tests` → PASS (baseline + new).

- [x] **Step 5: Commit**

```bash
git add windows/src/BetterScreenshot.Capture/Hotkeys.cs windows/tests/BetterScreenshot.Tests/HotkeyTests.cs
git commit -m "fix(win): human-readable key names for OEM/navigation/numpad hotkeys"
```

---

### Task 2: Theme foundation — `Theme.xaml`, `WindowThemer`, App merge

**Files:**
- Create: `windows/src/BetterScreenshot.App/Resources/Theme.xaml`
- Create: `windows/src/BetterScreenshot.App/Controls/WindowThemer.cs`
- Modify: `windows/src/BetterScreenshot.App/App.xaml` (merge Theme.xaml)

**Interfaces:**
- Produces (used by every later task): brush keys listed in Global Constraints; keyed styles
  `Theme.AccentButton` (Button), `Theme.DangerButton` (Button), `Theme.SubtleButton` (Button),
  `Theme.ToolButton` (ToggleButton — transparent, subtle hover, accent when checked),
  `Theme.SwatchButton` (ToggleButton — round color swatch with selection ring);
  implicit styles for Button, ToggleButton, ComboBox, ComboBoxItem, CheckBox, TextBox, TabControl,
  TabItem, ScrollBar, ToolTip; `WindowThemer.ApplyDark(Window)` static method.

- [x] **Step 1: Create `Theme.xaml`** with exactly this content:

```xml
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <!-- App-wide dark theme (macOS dark HIG mapped onto WPF). Tokens + implicit control styles.
         See docs/UI-REVAMP-SPEC.md for the palette rationale. -->

    <!-- ===== Palette ===== -->
    <SolidColorBrush x:Key="Theme.WindowBrush" Color="#232326"/>
    <SolidColorBrush x:Key="Theme.ChromeBrush" Color="#1C1C1F"/>
    <SolidColorBrush x:Key="Theme.CardBrush" Color="#2C2C30"/>
    <SolidColorBrush x:Key="Theme.ControlBrush" Color="#3A3A3F"/>
    <SolidColorBrush x:Key="Theme.ControlHoverBrush" Color="#47474D"/>
    <SolidColorBrush x:Key="Theme.ControlPressedBrush" Color="#525259"/>
    <SolidColorBrush x:Key="Theme.SubtleHoverBrush" Color="#1AFFFFFF"/>
    <SolidColorBrush x:Key="Theme.SubtlePressedBrush" Color="#2BFFFFFF"/>
    <SolidColorBrush x:Key="Theme.BorderBrush" Color="#26FFFFFF"/>
    <SolidColorBrush x:Key="Theme.TextBrush" Color="#F2F2F5"/>
    <SolidColorBrush x:Key="Theme.SecondaryTextBrush" Color="#9A9AA2"/>
    <SolidColorBrush x:Key="Theme.AccentBrush" Color="#0A84FF"/>
    <SolidColorBrush x:Key="Theme.AccentHoverBrush" Color="#2B94FF"/>
    <SolidColorBrush x:Key="Theme.AccentPressedBrush" Color="#0870DB"/>
    <SolidColorBrush x:Key="Theme.DangerBrush" Color="#FF453A"/>
    <SolidColorBrush x:Key="Theme.ScrollThumbBrush" Color="#33FFFFFF"/>
    <SolidColorBrush x:Key="Theme.SegmentTrackBrush" Color="#1AFFFFFF"/>

    <!-- ===== Button (implicit) ===== -->
    <Style TargetType="Button">
        <Setter Property="Background" Value="{StaticResource Theme.ControlBrush}"/>
        <Setter Property="Foreground" Value="{StaticResource Theme.TextBrush}"/>
        <Setter Property="BorderBrush" Value="{StaticResource Theme.BorderBrush}"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="Padding" Value="12,5"/>
        <Setter Property="FontSize" Value="13"/>
        <Setter Property="SnapsToDevicePixels" Value="True"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="Button">
                    <Border x:Name="Bd" Background="{TemplateBinding Background}"
                            BorderBrush="{TemplateBinding BorderBrush}"
                            BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6">
                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                          Margin="{TemplateBinding Padding}" RecognizesAccessKey="True"/>
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Setter TargetName="Bd" Property="Background" Value="{StaticResource Theme.ControlHoverBrush}"/>
                        </Trigger>
                        <Trigger Property="IsPressed" Value="True">
                            <Setter TargetName="Bd" Property="Background" Value="{StaticResource Theme.ControlPressedBrush}"/>
                        </Trigger>
                        <Trigger Property="IsEnabled" Value="False">
                            <Setter Property="Opacity" Value="0.4"/>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <!-- Accent (primary) button -->
    <Style x:Key="Theme.AccentButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
        <Setter Property="Background" Value="{StaticResource Theme.AccentBrush}"/>
        <Setter Property="Foreground" Value="White"/>
        <Setter Property="BorderThickness" Value="0"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="Button">
                    <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="6">
                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                          Margin="{TemplateBinding Padding}" RecognizesAccessKey="True"/>
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Setter TargetName="Bd" Property="Background" Value="{StaticResource Theme.AccentHoverBrush}"/>
                        </Trigger>
                        <Trigger Property="IsPressed" Value="True">
                            <Setter TargetName="Bd" Property="Background" Value="{StaticResource Theme.AccentPressedBrush}"/>
                        </Trigger>
                        <Trigger Property="IsEnabled" Value="False">
                            <Setter Property="Opacity" Value="0.4"/>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <!-- Destructive button: normal fill, red text (macOS convention) -->
    <Style x:Key="Theme.DangerButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
        <Setter Property="Foreground" Value="{StaticResource Theme.DangerBrush}"/>
    </Style>

    <!-- Icon button: transparent until hovered, rounded hover pill -->
    <Style x:Key="Theme.SubtleButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
        <Setter Property="Background" Value="Transparent"/>
        <Setter Property="BorderThickness" Value="0"/>
        <Setter Property="Padding" Value="0"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="Button">
                    <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="6">
                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                          Margin="{TemplateBinding Padding}"/>
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Setter TargetName="Bd" Property="Background" Value="{StaticResource Theme.SubtleHoverBrush}"/>
                        </Trigger>
                        <Trigger Property="IsPressed" Value="True">
                            <Setter TargetName="Bd" Property="Background" Value="{StaticResource Theme.SubtlePressedBrush}"/>
                        </Trigger>
                        <Trigger Property="IsEnabled" Value="False">
                            <Setter Property="Opacity" Value="0.4"/>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <!-- ===== ToggleButton (implicit) — like Button, accent when checked ===== -->
    <Style TargetType="ToggleButton">
        <Setter Property="Background" Value="{StaticResource Theme.ControlBrush}"/>
        <Setter Property="Foreground" Value="{StaticResource Theme.TextBrush}"/>
        <Setter Property="Padding" Value="12,5"/>
        <Setter Property="FontSize" Value="13"/>
        <Setter Property="SnapsToDevicePixels" Value="True"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="ToggleButton">
                    <Border x:Name="Bd" Background="{TemplateBinding Background}"
                            BorderBrush="{StaticResource Theme.BorderBrush}" BorderThickness="1" CornerRadius="6">
                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                          Margin="{TemplateBinding Padding}"/>
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Setter TargetName="Bd" Property="Background" Value="{StaticResource Theme.ControlHoverBrush}"/>
                        </Trigger>
                        <Trigger Property="IsChecked" Value="True">
                            <Setter TargetName="Bd" Property="Background" Value="{StaticResource Theme.AccentBrush}"/>
                            <Setter TargetName="Bd" Property="BorderThickness" Value="0"/>
                            <Setter Property="Foreground" Value="White"/>
                        </Trigger>
                        <Trigger Property="IsEnabled" Value="False">
                            <Setter Property="Opacity" Value="0.4"/>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <!-- Toolbar tool/toggle: transparent, subtle hover, accent when checked -->
    <Style x:Key="Theme.ToolButton" TargetType="ToggleButton">
        <Setter Property="Background" Value="Transparent"/>
        <Setter Property="Foreground" Value="{StaticResource Theme.TextBrush}"/>
        <Setter Property="Cursor" Value="Hand"/>
        <Setter Property="SnapsToDevicePixels" Value="True"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="ToggleButton">
                    <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="6">
                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Setter TargetName="Bd" Property="Background" Value="{StaticResource Theme.SubtleHoverBrush}"/>
                        </Trigger>
                        <Trigger Property="IsChecked" Value="True">
                            <Setter TargetName="Bd" Property="Background" Value="{StaticResource Theme.AccentBrush}"/>
                        </Trigger>
                        <Trigger Property="IsEnabled" Value="False">
                            <Setter Property="Opacity" Value="0.4"/>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <!-- Round color swatch with a selection ring (editor inspector) -->
    <Style x:Key="Theme.SwatchButton" TargetType="ToggleButton">
        <Setter Property="Width" Value="24"/>
        <Setter Property="Height" Value="24"/>
        <Setter Property="Cursor" Value="Hand"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="ToggleButton">
                    <Grid Background="Transparent">
                        <Ellipse x:Name="Ring" Stroke="Transparent" StrokeThickness="2"/>
                        <Ellipse Fill="{TemplateBinding Background}" Margin="4"/>
                    </Grid>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Setter TargetName="Ring" Property="Stroke" Value="#66FFFFFF"/>
                        </Trigger>
                        <Trigger Property="IsChecked" Value="True">
                            <Setter TargetName="Ring" Property="Stroke" Value="White"/>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <!-- ===== ComboBox ===== -->
    <ControlTemplate x:Key="Theme.ComboBoxToggle" TargetType="ToggleButton">
        <Border x:Name="Bd" Background="{StaticResource Theme.ControlBrush}"
                BorderBrush="{StaticResource Theme.BorderBrush}" BorderThickness="1" CornerRadius="6">
            <Path HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,10,0"
                  Data="M0,0 L4,4 L8,0" Stroke="{StaticResource Theme.SecondaryTextBrush}" StrokeThickness="1.6"
                  StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
        </Border>
        <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{StaticResource Theme.ControlHoverBrush}"/>
            </Trigger>
            <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{StaticResource Theme.ControlPressedBrush}"/>
            </Trigger>
        </ControlTemplate.Triggers>
    </ControlTemplate>

    <Style TargetType="ComboBox">
        <Setter Property="Foreground" Value="{StaticResource Theme.TextBrush}"/>
        <Setter Property="FontSize" Value="13"/>
        <Setter Property="Height" Value="30"/>
        <Setter Property="SnapsToDevicePixels" Value="True"/>
        <Setter Property="ScrollViewer.CanContentScroll" Value="False"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="ComboBox">
                    <Grid>
                        <ToggleButton Template="{StaticResource Theme.ComboBoxToggle}" Focusable="False"
                                      ClickMode="Press"
                                      IsChecked="{Binding IsDropDownOpen, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}"/>
                        <ContentPresenter Content="{TemplateBinding SelectionBoxItem}"
                                          ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                          Margin="11,0,26,0" VerticalAlignment="Center" IsHitTestVisible="False"
                                          TextElement.Foreground="{TemplateBinding Foreground}"/>
                        <Popup IsOpen="{TemplateBinding IsDropDownOpen}" Placement="Bottom"
                               AllowsTransparency="True" PopupAnimation="Fade" StaysOpen="False">
                            <Border Background="{StaticResource Theme.CardBrush}"
                                    BorderBrush="{StaticResource Theme.BorderBrush}" BorderThickness="1"
                                    CornerRadius="8" Margin="0,4,0,8" Padding="4"
                                    MinWidth="{TemplateBinding ActualWidth}"
                                    MaxHeight="{TemplateBinding MaxDropDownHeight}">
                                <ScrollViewer VerticalScrollBarVisibility="Auto">
                                    <ItemsPresenter/>
                                </ScrollViewer>
                            </Border>
                        </Popup>
                    </Grid>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <Style TargetType="ComboBoxItem">
        <Setter Property="Foreground" Value="{StaticResource Theme.TextBrush}"/>
        <Setter Property="FontSize" Value="13"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="ComboBoxItem">
                    <Border x:Name="Bd" Background="Transparent" CornerRadius="5" Padding="8,5">
                        <ContentPresenter/>
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsHighlighted" Value="True">
                            <Setter TargetName="Bd" Property="Background" Value="{StaticResource Theme.AccentBrush}"/>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <!-- ===== CheckBox ===== -->
    <Style TargetType="CheckBox">
        <Setter Property="Foreground" Value="{StaticResource Theme.TextBrush}"/>
        <Setter Property="FontSize" Value="13"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="CheckBox">
                    <StackPanel Orientation="Horizontal" Background="Transparent">
                        <Border x:Name="Box" Width="16" Height="16" CornerRadius="4"
                                Background="{StaticResource Theme.ControlBrush}"
                                BorderBrush="{StaticResource Theme.BorderBrush}" BorderThickness="1"
                                VerticalAlignment="Center">
                            <Path x:Name="Check" Data="M3,8 L6.5,11.5 L13,4.5" Stroke="White" StrokeThickness="2"
                                  StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"
                                  Visibility="Collapsed"/>
                        </Border>
                        <ContentPresenter Margin="8,0,0,0" VerticalAlignment="Center" RecognizesAccessKey="True"/>
                    </StackPanel>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Setter TargetName="Box" Property="BorderBrush" Value="{StaticResource Theme.SecondaryTextBrush}"/>
                        </Trigger>
                        <Trigger Property="IsChecked" Value="True">
                            <Setter TargetName="Box" Property="Background" Value="{StaticResource Theme.AccentBrush}"/>
                            <Setter TargetName="Box" Property="BorderBrush" Value="{StaticResource Theme.AccentBrush}"/>
                            <Setter TargetName="Check" Property="Visibility" Value="Visible"/>
                        </Trigger>
                        <Trigger Property="IsEnabled" Value="False">
                            <Setter Property="Opacity" Value="0.4"/>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <!-- ===== TextBox ===== -->
    <Style TargetType="TextBox">
        <Setter Property="Foreground" Value="{StaticResource Theme.TextBrush}"/>
        <Setter Property="CaretBrush" Value="{StaticResource Theme.TextBrush}"/>
        <Setter Property="Background" Value="{StaticResource Theme.ChromeBrush}"/>
        <Setter Property="BorderBrush" Value="{StaticResource Theme.BorderBrush}"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="Padding" Value="8,4"/>
        <Setter Property="FontSize" Value="13"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="TextBox">
                    <Border x:Name="Bd" Background="{TemplateBinding Background}"
                            BorderBrush="{TemplateBinding BorderBrush}"
                            BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6">
                        <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}"
                                      VerticalAlignment="Center"/>
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsKeyboardFocused" Value="True">
                            <Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource Theme.AccentBrush}"/>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <!-- ===== TabControl as a macOS segmented control ===== -->
    <Style TargetType="TabControl">
        <Setter Property="Background" Value="Transparent"/>
        <Setter Property="BorderThickness" Value="0"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="TabControl">
                    <DockPanel>
                        <Border DockPanel.Dock="Top" HorizontalAlignment="Center"
                                Background="{StaticResource Theme.SegmentTrackBrush}"
                                CornerRadius="8" Padding="3" Margin="0,2,0,12">
                            <TabPanel IsItemsHost="True"/>
                        </Border>
                        <Border Background="{TemplateBinding Background}">
                            <ContentPresenter ContentSource="SelectedContent"/>
                        </Border>
                    </DockPanel>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <Style TargetType="TabItem">
        <Setter Property="Foreground" Value="{StaticResource Theme.SecondaryTextBrush}"/>
        <Setter Property="FontSize" Value="13"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="TabItem">
                    <Border x:Name="Bd" Background="Transparent" CornerRadius="6" Padding="16,5" Margin="1,0">
                        <ContentPresenter ContentSource="Header" VerticalAlignment="Center"
                                          TextElement.Foreground="{TemplateBinding Foreground}"/>
                    </Border>
                    <ControlTemplate.Triggers>
                        <MultiTrigger>
                            <MultiTrigger.Conditions>
                                <Condition Property="IsMouseOver" Value="True"/>
                                <Condition Property="IsSelected" Value="False"/>
                            </MultiTrigger.Conditions>
                            <Setter Property="Foreground" Value="{StaticResource Theme.TextBrush}"/>
                        </MultiTrigger>
                        <Trigger Property="IsSelected" Value="True">
                            <Setter TargetName="Bd" Property="Background" Value="{StaticResource Theme.ControlBrush}"/>
                            <Setter Property="Foreground" Value="{StaticResource Theme.TextBrush}"/>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <!-- ===== Slim ScrollBar ===== -->
    <ControlTemplate x:Key="Theme.ScrollThumb" TargetType="Thumb">
        <Border Background="{StaticResource Theme.ScrollThumbBrush}" CornerRadius="4" Margin="2"/>
    </ControlTemplate>

    <Style TargetType="ScrollBar">
        <Setter Property="Background" Value="Transparent"/>
        <Setter Property="Width" Value="10"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="ScrollBar">
                    <Track x:Name="PART_Track" IsDirectionReversed="True">
                        <Track.DecreaseRepeatButton>
                            <RepeatButton Command="ScrollBar.PageUpCommand" Opacity="0" Focusable="False"/>
                        </Track.DecreaseRepeatButton>
                        <Track.IncreaseRepeatButton>
                            <RepeatButton Command="ScrollBar.PageDownCommand" Opacity="0" Focusable="False"/>
                        </Track.IncreaseRepeatButton>
                        <Track.Thumb>
                            <Thumb Template="{StaticResource Theme.ScrollThumb}"/>
                        </Track.Thumb>
                    </Track>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
        <Style.Triggers>
            <Trigger Property="Orientation" Value="Horizontal">
                <Setter Property="Width" Value="Auto"/>
                <Setter Property="Height" Value="10"/>
                <Setter Property="Template">
                    <Setter.Value>
                        <ControlTemplate TargetType="ScrollBar">
                            <Track x:Name="PART_Track">
                                <Track.DecreaseRepeatButton>
                                    <RepeatButton Command="ScrollBar.PageLeftCommand" Opacity="0" Focusable="False"/>
                                </Track.DecreaseRepeatButton>
                                <Track.IncreaseRepeatButton>
                                    <RepeatButton Command="ScrollBar.PageRightCommand" Opacity="0" Focusable="False"/>
                                </Track.IncreaseRepeatButton>
                                <Track.Thumb>
                                    <Thumb Template="{StaticResource Theme.ScrollThumb}"/>
                                </Track.Thumb>
                            </Track>
                        </ControlTemplate>
                    </Setter.Value>
                </Setter>
            </Trigger>
        </Style.Triggers>
    </Style>

    <!-- ===== ToolTip ===== -->
    <Style TargetType="ToolTip">
        <Setter Property="Background" Value="{StaticResource Theme.CardBrush}"/>
        <Setter Property="Foreground" Value="{StaticResource Theme.TextBrush}"/>
        <Setter Property="FontSize" Value="12"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="ToolTip">
                    <Border Background="{TemplateBinding Background}"
                            BorderBrush="{StaticResource Theme.BorderBrush}" BorderThickness="1"
                            CornerRadius="6" Padding="8,5">
                        <ContentPresenter/>
                    </Border>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
</ResourceDictionary>
```

- [x] **Step 2: Create `WindowThemer.cs`**:

```csharp
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using Window = System.Windows.Window;

namespace BetterScreenshot.App.Controls;

/// <summary>Darkens the DWM title bar of titled windows (Settings/Editor/History/Welcome). Safe no-op
/// when the attribute is unsupported (pre-20H1) — the window just keeps a light title bar.</summary>
public static class WindowThemer
{
    private const int DwmwaUseImmersiveDarkMode = 20;

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

    public static void ApplyDark(Window window)
    {
        if (new WindowInteropHelper(window).Handle != IntPtr.Zero) Apply(window);
        else window.SourceInitialized += (_, _) => Apply(window);
    }

    private static void Apply(Window window)
    {
        try
        {
            int on = 1;
            _ = DwmSetWindowAttribute(new WindowInteropHelper(window).Handle,
                DwmwaUseImmersiveDarkMode, ref on, sizeof(int));
        }
        catch (DllNotFoundException) { }
        catch (EntryPointNotFoundException) { }
    }
}
```

- [x] **Step 3: Merge into `App.xaml`** — add Theme.xaml after Icons.xaml:

```xml
            <ResourceDictionary.MergedDictionaries>
                <ResourceDictionary Source="Resources/Icons.xaml"/>
                <ResourceDictionary Source="Resources/Theme.xaml"/>
            </ResourceDictionary.MergedDictionaries>
```

- [x] **Step 4: Build + tests** — `dotnet build windows/BetterScreenshot.sln` → 0 errors; `dotnet test windows/tests/BetterScreenshot.Tests` → green. (Visual checks come with the preview task.)

- [x] **Step 5: Commit**

```bash
git add windows/src/BetterScreenshot.App/Resources/Theme.xaml windows/src/BetterScreenshot.App/Controls/WindowThemer.cs windows/src/BetterScreenshot.App/App.xaml
git commit -m "feat(win): app-wide dark theme dictionary + dark title-bar helper"
```

---

### Task 3: Settings — instant apply, dark restyle, tray shortcut sync

**Files:**
- Modify: `windows/src/BetterScreenshot.App/Settings/SettingsWindow.xaml` (full rewrite below)
- Modify: `windows/src/BetterScreenshot.App/Settings/SettingsWindow.xaml.cs` (instant-apply rework)
- Modify: `windows/src/BetterScreenshot.App/Tray/TrayIcon.cs` (add `UpdateShortcuts`)
- Modify: `windows/src/BetterScreenshot.App/App.xaml.cs` (wire `HotkeysChanged` → tray)

**Interfaces:**
- Consumes: theme brushes/styles from Task 2; `WindowThemer.ApplyDark`; `HotkeyCombo.DisplayString` (Task 1).
- Produces: `SettingsWindow.HotkeysChanged` (`public event Action?`); `TrayIcon.UpdateShortcuts(HotkeyBindings bindings)`.

- [x] **Step 1: Rewrite `SettingsWindow.xaml`** — dark, no footer, every control fires `Changed`:

```xml
<Window x:Class="BetterScreenshot.App.Settings.SettingsWindow"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="BetterScreenshot Settings"
        Width="540" Height="560"
        WindowStartupLocation="CenterScreen" ResizeMode="CanMinimize"
        Background="{StaticResource Theme.WindowBrush}" FontFamily="Segoe UI"
        Foreground="{StaticResource Theme.TextBrush}">
    <Window.Resources>
        <Style x:Key="RowLabel" TargetType="TextBlock">
            <Setter Property="Width" Value="170"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Setter Property="Foreground" Value="{StaticResource Theme.SecondaryTextBrush}"/>
        </Style>
    </Window.Resources>
    <TabControl Margin="14,12">
        <TabItem Header="General">
            <ScrollViewer VerticalScrollBarVisibility="Auto">
                <StackPanel Margin="18,8">
                    <StackPanel Orientation="Horizontal" Margin="0,6">
                        <TextBlock Text="After capture" Style="{StaticResource RowLabel}"/>
                        <ComboBox x:Name="AfterCaptureCombo" Width="240" SelectionChanged="Changed">
                            <ComboBoxItem Content="Show Quick Access overlay"/>
                            <ComboBoxItem Content="Copy to clipboard"/>
                            <ComboBoxItem Content="Save to folder"/>
                            <ComboBoxItem Content="Copy and save"/>
                        </ComboBox>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" Margin="0,6">
                        <TextBlock Text="Image format" Style="{StaticResource RowLabel}"/>
                        <ComboBox x:Name="FormatCombo" Width="120" SelectionChanged="Changed">
                            <ComboBoxItem Content="PNG"/>
                            <ComboBoxItem Content="JPG"/>
                        </ComboBox>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" Margin="0,6">
                        <TextBlock Text="Overlay corner" Style="{StaticResource RowLabel}"/>
                        <ComboBox x:Name="CornerCombo" Width="160" SelectionChanged="Changed">
                            <ComboBoxItem Content="Top Left"/>
                            <ComboBoxItem Content="Top Right"/>
                            <ComboBoxItem Content="Bottom Left"/>
                            <ComboBoxItem Content="Bottom Right"/>
                        </ComboBox>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" Margin="0,6">
                        <TextBlock Text="Overlay auto-dismiss" Style="{StaticResource RowLabel}"/>
                        <ComboBox x:Name="AutoDismissCombo" Width="120" SelectionChanged="Changed">
                            <ComboBoxItem Content="3 seconds"/>
                            <ComboBoxItem Content="6 seconds"/>
                            <ComboBoxItem Content="10 seconds"/>
                        </ComboBox>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" Margin="0,6">
                        <TextBlock Text="Save folder" Style="{StaticResource RowLabel}"/>
                        <TextBox x:Name="SaveDirBox" Width="220" VerticalContentAlignment="Center" LostFocus="Changed"/>
                        <Button x:Name="BrowseBtn" Content="Browse…" Margin="8,0,0,0" Padding="10,4" Click="Browse_Click"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" Margin="0,6">
                        <TextBlock Text="Pin corner radius" Style="{StaticResource RowLabel}"/>
                        <ComboBox x:Name="PinRadiusCombo" Width="90" SelectionChanged="Changed">
                            <ComboBoxItem Content="0"/>
                            <ComboBoxItem Content="4"/>
                            <ComboBoxItem Content="8"/>
                            <ComboBoxItem Content="12"/>
                            <ComboBoxItem Content="16"/>
                            <ComboBoxItem Content="20"/>
                        </ComboBox>
                    </StackPanel>
                    <CheckBox x:Name="PinShadowCheck" Content="Pin drop shadow" Margin="0,10,0,4" Checked="Changed" Unchecked="Changed"/>
                    <CheckBox x:Name="HistoryEnabledCheck" Content="Remember capture history" Margin="0,4" Checked="Changed" Unchecked="Changed"/>
                    <StackPanel Orientation="Horizontal" Margin="0,6">
                        <TextBlock Text="History limit" Style="{StaticResource RowLabel}"/>
                        <ComboBox x:Name="HistoryCapCombo" Width="90" SelectionChanged="Changed">
                            <ComboBoxItem Content="10"/>
                            <ComboBoxItem Content="50"/>
                            <ComboBoxItem Content="200"/>
                        </ComboBox>
                    </StackPanel>
                    <CheckBox x:Name="LaunchAtLoginCheck" Content="Launch at login" Margin="0,4" Checked="Changed" Unchecked="Changed"/>
                    <CheckBox x:Name="CaptureSoundCheck" Content="Play a sound on capture" Margin="0,4" Checked="Changed" Unchecked="Changed"/>
                    <TextBlock Text="Changes apply immediately." Foreground="{StaticResource Theme.SecondaryTextBrush}"
                               FontSize="11" Margin="0,14,0,0"/>
                </StackPanel>
            </ScrollViewer>
        </TabItem>

        <TabItem Header="Shortcuts">
            <ScrollViewer VerticalScrollBarVisibility="Auto">
                <StackPanel x:Name="ShortcutsPanel" Margin="18,8"/>
            </ScrollViewer>
        </TabItem>

        <TabItem Header="Recording">
            <ScrollViewer VerticalScrollBarVisibility="Auto">
                <StackPanel Margin="18,8">
                    <StackPanel Orientation="Horizontal" Margin="0,6">
                        <TextBlock Text="Format" Style="{StaticResource RowLabel}"/>
                        <ComboBox x:Name="RecFormatCombo" Width="120" SelectionChanged="Changed">
                            <ComboBoxItem Content="MP4"/>
                            <ComboBoxItem Content="GIF"/>
                        </ComboBox>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" Margin="0,6">
                        <TextBlock Text="Frame rate" Style="{StaticResource RowLabel}"/>
                        <ComboBox x:Name="FpsCombo" Width="120" SelectionChanged="Changed">
                            <ComboBoxItem Content="30 fps"/>
                            <ComboBoxItem Content="60 fps"/>
                        </ComboBox>
                    </StackPanel>
                    <CheckBox x:Name="SysAudioCheck" Content="Record system audio" Margin="0,8,0,4" Checked="Changed" Unchecked="Changed"/>
                    <CheckBox x:Name="MicCheck" Content="Record microphone" Margin="0,4" Checked="Changed" Unchecked="Changed"/>
                    <CheckBox x:Name="CameraCheck" Content="Show camera bubble" Margin="0,4" Checked="Changed" Unchecked="Changed"/>
                    <StackPanel Orientation="Horizontal" Margin="0,6">
                        <TextBlock Text="Camera size" Style="{StaticResource RowLabel}"/>
                        <ComboBox x:Name="CameraSizeCombo" Width="120" SelectionChanged="Changed">
                            <ComboBoxItem Content="Small"/>
                            <ComboBoxItem Content="Medium"/>
                        </ComboBox>
                    </StackPanel>
                    <CheckBox x:Name="ClicksCheck" Content="Highlight mouse clicks" Margin="0,4" Checked="Changed" Unchecked="Changed"/>
                    <CheckBox x:Name="KeystrokesCheck" Content="Show keystrokes" Margin="0,4" Checked="Changed" Unchecked="Changed"/>
                    <StackPanel Orientation="Horizontal" Margin="0,6">
                        <TextBlock Text="Countdown" Style="{StaticResource RowLabel}"/>
                        <ComboBox x:Name="CountdownCombo" Width="120" SelectionChanged="Changed">
                            <ComboBoxItem Content="Off"/>
                            <ComboBoxItem Content="3 seconds"/>
                            <ComboBoxItem Content="5 seconds"/>
                            <ComboBoxItem Content="10 seconds"/>
                        </ComboBox>
                    </StackPanel>
                </StackPanel>
            </ScrollViewer>
        </TabItem>
    </TabControl>
</Window>
```

- [x] **Step 2: Rework `SettingsWindow.xaml.cs`.** Keep `LoadGeneral`/`LoadRecording` and the index↔value
  mappings exactly as they are; restructure the rest:
  - Add fields `private bool _loading = true;` and `public event Action? HotkeysChanged;`; delete
    `_hotkeySnapshot` and `_saved`.
  - Ctor: `InitializeComponent(); LoadGeneral(); LoadRecording(); BuildShortcutRows(); _loading = false; Controls.WindowThemer.ApplyDark(this);`
  - New shared handler + apply (the body of `Apply()` is the old `Save_Click` body minus `_saved`/`Close()`):

```csharp
    /// <summary>Instant-apply: every control change persists immediately (no Save/Cancel; closing the
    /// window with ✕ must never lose changes — that was the old model's trap).</summary>
    private void Changed(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        Apply();
    }

    private void Apply()
    {
        _settings.Capture = new CaptureSettings { /* …old Save_Click mapping unchanged… */ };
        _settings.Recording = new RecordingConfig { /* …old Save_Click mapping unchanged… */ };
        _settings.SaveDirectory = SaveDirBox.Text;
        _settings.LaunchAtLogin = LaunchAtLoginCheck.IsChecked == true;
        _settings.CaptureSoundEnabled = CaptureSoundCheck.IsChecked == true;
        _settings.Save();
    }
```

  - `Browse_Click`: after `SaveDirBox.Text = dialog.FolderName;` add `Apply();`.
  - Hotkey mutations persist immediately — `ClearBinding` becomes:

```csharp
    private void ClearBinding(object sender, RoutedEventArgs e)
    {
        var action = (HotkeyAction)((Button)sender).Tag;
        _settings.Hotkeys.Clear(action);
        _shortcutLabels[action].Text = "(unbound)";
        ApplyHotkeys();
    }

    private void ApplyHotkeys()
    {
        _settings.Save();
        _hotkeys.Apply(_settings.Hotkeys);
        HotkeysChanged?.Invoke();
    }
```

    and in `OnPreviewKeyDown`, after `_settings.Hotkeys.Set(action, combo); _shortcutLabels[action].Text = combo.DisplayString;`
    call `StopRecording();` then `ApplyHotkeys();` (StopRecording already calls `_hotkeys.Apply`; keep it —
    `ApplyHotkeys` adds persistence + the event).
  - Delete `Save_Click`/`Cancel_Click`; `OnClosed` shrinks to
    `{ _hotkeys.Apply(_settings.Hotkeys); base.OnClosed(e); }` (covers a mid-recording close re-arming
    suspended hotkeys).
  - `BuildShortcutRows` restyle: the combo label becomes a rounded mono **chip**, Change/Clear use theme
    styles:

```csharp
    private void BuildShortcutRows()
    {
        foreach (var action in HotkeyActionInfo.All)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 5, 0, 5) };
            row.Children.Add(new TextBlock
            {
                Text = action.Title(), Width = 180, VerticalAlignment = VerticalAlignment.Center,
                Foreground = (System.Windows.Media.Brush)FindResource("Theme.SecondaryTextBrush"),
            });

            var label = new TextBlock
            {
                Text = _settings.Hotkeys.Combo(action)?.DisplayString ?? "(unbound)",
                FontFamily = new FontFamily("Cascadia Mono, Consolas"),
                FontSize = 12,
                VerticalAlignment = VerticalAlignment.Center,
                HorizontalAlignment = HorizontalAlignment.Center,
            };
            _shortcutLabels[action] = label;
            row.Children.Add(new Border
            {
                Child = label,
                Width = 130,
                Padding = new Thickness(8, 4, 8, 4),
                CornerRadius = new CornerRadius(5),
                Background = (System.Windows.Media.Brush)FindResource("Theme.ControlBrush"),
                Margin = new Thickness(0, 0, 10, 0),
            });

            var change = new Button { Content = "Change", Padding = new Thickness(10, 3, 10, 3), Tag = action };
            change.Click += StartRecording;
            row.Children.Add(change);

            var clear = new Button { Content = "Clear", Padding = new Thickness(10, 3, 10, 3), Margin = new Thickness(6, 0, 0, 0), Tag = action };
            clear.Click += ClearBinding;
            row.Children.Add(clear);

            ShortcutsPanel.Children.Add(row);
        }
    }
```

    (needs `using HorizontalAlignment = System.Windows.HorizontalAlignment;` alias only if ambiguous —
    check existing aliases.) In `StartRecording`, set the button content to `"Press keys…"` as today; in
    `StopRecording` restore `"Change"` as today.

- [x] **Step 3: `TrayIcon.UpdateShortcuts`** — register items per action and expose a refresh:

```csharp
    private readonly Dictionary<HotkeyAction, WF.ToolStripMenuItem> _actionItems = new();
```

    Change the private `Item(...)` helper signature to
    `Item(string text, string? shortcut, Action onClick, HotkeyAction? action = null)` and inside, after
    creating `item`: `if (action is { } a) _actionItems[a] = item;`. Update every call that has a shortcut
    to pass its action (CaptureArea/CaptureWindow/CaptureFullscreen/CaptureText/Record/
    PauseResumeRecording/PinFromClipboard/OpenHistory/RestoreRecentlyClosed). Add:

```csharp
    /// <summary>Refreshes the shortcut hints after a rebind in Settings (the menu is long-lived).</summary>
    public void UpdateShortcuts(HotkeyBindings bindings)
    {
        foreach (var (action, item) in _actionItems)
            item.ShortcutKeyDisplayString = bindings.Combo(action)?.DisplayString ?? string.Empty;
    }
```

- [x] **Step 4: Wire in `App.xaml.cs`** (`ShowSettings`):

```csharp
        _settingsWindow = new SettingsWindow(_settings, _hotkeys);
        _settingsWindow.HotkeysChanged += () => _tray.UpdateShortcuts(_settings.Hotkeys);
        _settingsWindow.Closed += (_, _) => _settingsWindow = null;
        _settingsWindow.Show();
```

- [x] **Step 5: Build + tests** — `dotnet build windows/BetterScreenshot.sln` → 0 errors; `dotnet test windows/tests/BetterScreenshot.Tests` → green.

- [x] **Step 6: Commit**

```bash
git add windows/src/BetterScreenshot.App/Settings/SettingsWindow.xaml windows/src/BetterScreenshot.App/Settings/SettingsWindow.xaml.cs windows/src/BetterScreenshot.App/Tray/TrayIcon.cs windows/src/BetterScreenshot.App/App.xaml.cs
git commit -m "feat(win): instant-apply dark settings window + live tray shortcut sync"
```

---

### Task 4: Quick Access — dark card, subtle buttons, drag-out dismiss

**Files:**
- Modify: `windows/src/BetterScreenshot.App/Overlays/QuickAccessWindow.xaml`
- Modify: `windows/src/BetterScreenshot.App/Overlays/QuickAccessWindow.xaml.cs`

**Interfaces:**
- Consumes: `Theme.CardBrush`/`Theme.BorderBrush`, `Theme.SubtleButton` (Task 2); `DismissReason` (existing).
- Produces: none new (behavioral fix only).

- [x] **Step 1: XAML** — dark card + hairline; light thumbnail well:

```xml
    <Border x:Name="Card" CornerRadius="12" Background="{StaticResource Theme.CardBrush}"
            BorderBrush="{StaticResource Theme.BorderBrush}" BorderThickness="1" Margin="6">
        <Border.Effect>
            <DropShadowEffect BlurRadius="16" ShadowDepth="2" Opacity="0.45"/>
        </Border.Effect>
        <Grid>
            <Border CornerRadius="6" ClipToBounds="True" Width="200" Height="112"
                    VerticalAlignment="Top" HorizontalAlignment="Center" Margin="0,10,0,0" Background="#14FFFFFF">
                <Image x:Name="Thumb" Stretch="Uniform"/>
            </Border>
            <StackPanel x:Name="ButtonRow" Orientation="Horizontal"
                        HorizontalAlignment="Center" VerticalAlignment="Bottom" Margin="0,0,0,8"/>
        </Grid>
    </Border>
```

- [x] **Step 2: Code-behind** —
  - `GlyphBrush` → `new(Color.FromRgb(0xF2, 0xF2, 0xF5));`
  - Delete the `Card.Background = …kind…` assignment in the ctor (both kinds share the dark card; the
    button set already differentiates them).
  - `MakeButton`: replace the `Background`/`BorderThickness` setters with the theme style:

```csharp
        var button = new Button
        {
            Content = new IconPresenter { IconKey = iconKey, Brush = GlyphBrush, Width = 17, Height = 17 },
            Width = 30,
            Height = 28,
            Margin = new Thickness(3, 0, 3, 0),
            ToolTip = tip,
            Style = (Style)System.Windows.Application.Current.FindResource("Theme.SubtleButton"),
            Cursor = Cursors.Hand,
        };
```

  - **Drag-out dismiss** in `Thumb_MouseMove`:

```csharp
        var data = new DataObject();
        data.SetFileDropList(new StringCollection { _dragFile });
        var result = DragDrop.DoDragDrop(Thumb, data, DragDropEffects.Copy);
        if (result != DragDropEffects.None) Dismiss(DismissReason.ActionTaken); // Esc-cancel keeps the card
```

- [x] **Step 3: Build + tests** — both green as in Task 3 Step 5.

- [x] **Step 4: Commit**

```bash
git add windows/src/BetterScreenshot.App/Overlays/QuickAccessWindow.xaml windows/src/BetterScreenshot.App/Overlays/QuickAccessWindow.xaml.cs
git commit -m "feat(win): dark Quick Access card, rounded hover buttons, drag-out dismisses"
```

---

### Task 5: Editor — icon toolbar with selection, styled inspector + bottom bar

**Files:**
- Modify: `windows/src/BetterScreenshot.App/Editor/EditorWindow.xaml`
- Modify: `windows/src/BetterScreenshot.App/Editor/EditorWindow.xaml.cs`

**Interfaces:**
- Consumes: `Icons.xaml` keys `cursor/arrow/line/rect/rect-fill/ellipse/text/counter/blur/pixelate/crop`
  via `IconPresenter` (`BetterScreenshot.App.Controls`); `Theme.ToolButton`, `Theme.SwatchButton`,
  `Theme.AccentButton` (Task 2); `WindowThemer.ApplyDark`.
- Produces: none new (UI only; `_tool`, `_style`, `StyleChanged` behavior unchanged).

- [x] **Step 1: XAML** — theme brushes + accent Copy:

```xml
        Title="BetterScreenshot Editor" Width="960" Height="720"
        WindowStartupLocation="CenterScreen" Background="{StaticResource Theme.WindowBrush}">
```

  top/bottom `Border`s: `Background="{StaticResource Theme.ChromeBrush}"`; bottom bar buttons:

```xml
                <Button Content="Done" Click="Done_Click" Padding="14,6" Margin="6,0,0,0"/>
                <Button Content="Stack" Click="Stack_Click" Padding="14,6" Margin="6,0,0,0"/>
                <Button Content="Save" Click="Save_Click" Padding="14,6" Margin="6,0,0,0"/>
                <Button Content="Copy" Click="Copy_Click" Padding="14,6" Margin="6,0,0,0"
                        Style="{StaticResource Theme.AccentButton}"/>
```

- [x] **Step 2: Code-behind toolbar** — add aliases `using ToggleButton = System.Windows.Controls.Primitives.ToggleButton;`
  and `using Brushes = System.Windows.Media.Brushes;`, plus `using BetterScreenshot.App.Controls;`. Replace `BuildToolbar` and add tool selection:

```csharp
    private static readonly System.Windows.Media.SolidColorBrush ToolGlyphBrush =
        new(System.Windows.Media.Color.FromRgb(0xD8, 0xD8, 0xDE));

    private readonly Dictionary<EditorTool, ToggleButton> _toolButtons = new();

    private void BuildToolbar()
    {
        (string Icon, string Name, EditorTool Tool)[] tools =
        {
            ("cursor", "Select", EditorTool.Select), ("arrow", "Arrow", EditorTool.Arrow),
            ("line", "Line", EditorTool.Line), ("rect", "Rectangle", EditorTool.Rectangle),
            ("rect-fill", "Filled rectangle", EditorTool.FilledRectangle),
            ("ellipse", "Ellipse", EditorTool.Ellipse), ("text", "Text", EditorTool.Text),
            ("counter", "Counter", EditorTool.Counter), ("blur", "Blur", EditorTool.Blur),
            ("pixelate", "Pixelate", EditorTool.Pixelate), ("crop", "Crop", EditorTool.Crop),
        };
        foreach (var (icon, name, tool) in tools)
        {
            var button = new ToggleButton
            {
                Content = new IconPresenter { IconKey = icon, Brush = ToolGlyphBrush, Width = 18, Height = 18 },
                Style = (Style)FindResource("Theme.ToolButton"),
                Width = 34,
                Height = 30,
                Margin = new Thickness(2, 0, 2, 0),
                ToolTip = name,
            };
            System.Windows.Automation.AutomationProperties.SetName(button, name);
            button.Click += (_, _) => SelectTool(tool);
            _toolButtons[tool] = button;
            Toolbar.Children.Add(button);
        }
        SelectTool(EditorTool.Select);
    }

    private void SelectTool(EditorTool tool)
    {
        _tool = tool;
        foreach (var (t, b) in _toolButtons)
        {
            b.IsChecked = t == tool;
            ((IconPresenter)b.Content).Brush = t == tool ? Brushes.White : ToolGlyphBrush;
        }
    }
```

- [x] **Step 3: Inspector with selection state** — replace `BuildInspector`/`AddInspectorButton` and the
  three setters:

```csharp
    private readonly List<(RGBAColor Color, ToggleButton Button)> _colorButtons = new();
    private readonly Dictionary<double, ToggleButton> _weightButtons = new();
    private readonly Dictionary<double, ToggleButton> _sizeButtons = new();

    private void BuildInspector()
    {
        RGBAColor[] presets =
        {
            new(1, 0.27, 0.23, 1), new(1, 0.62, 0.04, 1), new(1, 0.84, 0.04, 1), new(0.19, 0.82, 0.35, 1),
            new(0.04, 0.52, 1, 1), new(0.75, 0.35, 0.95, 1), new(1, 1, 1, 1), new(0, 0, 0, 1),
        };
        foreach (var color in presets)
        {
            var c = color;
            var swatch = new ToggleButton
            {
                Style = (Style)FindResource("Theme.SwatchButton"),
                Margin = new Thickness(2, 0, 2, 0),
                Background = new SolidColorBrush(Color.FromRgb((byte)(c.R * 255), (byte)(c.G * 255), (byte)(c.B * 255))),
                ToolTip = "Color",
            };
            swatch.Click += (_, _) => SetColor(c);
            _colorButtons.Add((c, swatch));
            Inspector.Children.Add(swatch);
        }
        Inspector.Children.Add(new Separator { Width = 12, Visibility = Visibility.Hidden });
        foreach (var w in new[] { 2.0, 4.0, 7.0 })
        {
            double weight = w;
            var dot = new System.Windows.Shapes.Ellipse { Width = 3 + weight, Height = 3 + weight, Fill = Brushes.White };
            _weightButtons[weight] = InspectorToggle(dot, $"Line width {weight:0}", () => SetWeight(weight));
        }
        Inspector.Children.Add(new Separator { Width = 12, Visibility = Visibility.Hidden });
        foreach (var s in new[] { 18.0, 24.0, 36.0 })
        {
            double size = s;
            var a = new TextBlock
            {
                Text = "A", Foreground = Brushes.White, FontSize = 9 + size / 3, FontWeight = FontWeights.SemiBold,
            };
            _sizeButtons[size] = InspectorToggle(a, $"Text size {size:0}", () => SetSize(size));
        }
        RefreshInspector();
    }

    private ToggleButton InspectorToggle(UIElement content, string tip, Action onClick)
    {
        var button = new ToggleButton
        {
            Content = content,
            Style = (Style)FindResource("Theme.ToolButton"),
            Width = 30,
            Height = 28,
            Margin = new Thickness(2, 0, 2, 0),
            ToolTip = tip,
        };
        System.Windows.Automation.AutomationProperties.SetName(button, tip);
        button.Click += (_, _) => onClick();
        Inspector.Children.Add(button);
        return button;
    }

    private void RefreshInspector()
    {
        foreach (var (color, button) in _colorButtons) button.IsChecked = color == _style.StrokeColor;
        foreach (var (weight, button) in _weightButtons) button.IsChecked = Math.Abs(weight - _style.LineWidth) < 0.01;
        foreach (var (size, button) in _sizeButtons) button.IsChecked = Math.Abs(size - _style.FontSize) < 0.01;
    }

    private void SetColor(RGBAColor c) { _style = _style with { StrokeColor = c, FillColor = c.WithAlpha(0.25) }; StyleChanged?.Invoke(_style); RefreshInspector(); }
    private void SetWeight(double w) { _style = _style with { LineWidth = w }; StyleChanged?.Invoke(_style); RefreshInspector(); }
    private void SetSize(double s) { _style = _style with { FontSize = s }; StyleChanged?.Invoke(_style); RefreshInspector(); }
```

  (If `RGBAColor` is not an equatable record, compare component-wise with `< 0.001` tolerance instead of
  `==` — check `windows/src/BetterScreenshot.Editor` for its definition and adjust.)

- [x] **Step 4: Small fixes** — in the ctor add `Controls.WindowThemer.ApplyDark(this);` after
  `InitializeComponent()`. In `PlaceTextBox`, add `Foreground = Brushes.Black,` to the `TextBox`
  initializer (the implicit dark theme would otherwise put near-white text on its white background).

- [x] **Step 5: Build + tests** — both green.

- [x] **Step 6: Commit**

```bash
git add windows/src/BetterScreenshot.App/Editor/EditorWindow.xaml windows/src/BetterScreenshot.App/Editor/EditorWindow.xaml.cs
git commit -m "feat(win): editor icon toolbar with selected-tool state + styled inspector"
```

---

### Task 6: Remaining surfaces — Welcome, History, RecordStrip, dark tray menu

**Files:**
- Modify: `windows/src/BetterScreenshot.App/Onboarding/WelcomeWindow.xaml` (+ `.xaml.cs` one line)
- Modify: `windows/src/BetterScreenshot.App/History/HistoryWindow.xaml` (+ `.xaml.cs` one line)
- Modify: `windows/src/BetterScreenshot.App/Recording/RecordStripWindow.xaml` + `.xaml.cs`
- Create: `windows/src/BetterScreenshot.App/Tray/DarkMenu.cs`
- Modify: `windows/src/BetterScreenshot.App/Tray/TrayIcon.cs` (attach renderer)

**Interfaces:**
- Consumes: theme brushes/styles (Task 2), `WindowThemer.ApplyDark`, `Theme.ToolButton`.
- Produces: `DarkMenuRenderer` (internal, Tray namespace).

- [x] **Step 1: WelcomeWindow** — dark rewrite. Window attrs:
  `Background="{StaticResource Theme.WindowBrush}" Foreground="{StaticResource Theme.TextBrush}"`;
  the description `TextBlock` gets `Foreground="{StaticResource Theme.SecondaryTextBrush}"`; the shortcut
  panel `Border` gets `Background="#14FFFFFF"`; each `Ctrl+Shift+N` TextBlock:
  `FontFamily="Cascadia Mono, Consolas" Foreground="{StaticResource Theme.TextBrush}"`; each description
  cell `Foreground="{StaticResource Theme.SecondaryTextBrush}"`; Start button:
  `Style="{StaticResource Theme.AccentButton}"` (drop its hardcoded Background/Foreground/BorderThickness).
  Keep the app-icon vignette block untouched. In `WelcomeWindow.xaml.cs` ctor add
  `Controls.WindowThemer.ApplyDark(this);` after `InitializeComponent()`.

- [x] **Step 2: HistoryWindow** — in XAML set window `Background="{StaticResource Theme.WindowBrush}"`,
  bottom bar `Background="{StaticResource Theme.ChromeBrush}"`, and mark the two destructive buttons:
  `ClearAllButton` and `DeleteButton` get `Style="{StaticResource Theme.DangerButton}"`. In code-behind
  ctor add `Controls.WindowThemer.ApplyDark(this);`.

- [x] **Step 3: RecordStripWindow** — XAML card:

```xml
    <Border x:Name="Card" CornerRadius="12" Background="{StaticResource Theme.CardBrush}"
            BorderBrush="{StaticResource Theme.BorderBrush}" BorderThickness="1" Margin="8" Padding="12,8">
```

  Code-behind: `AccentBrush` → `Color.FromRgb(0x0A, 0x84, 0xFF)`; `GlyphOff` →
  `Color.FromRgb(0xC8, 0xC8, 0xCF)`; `Separator()` background → `Color.FromArgb(0x26, 0xFF, 0xFF, 0xFF)`.
  Replace the hand-rolled `Button` toggles with `Theme.ToolButton` `ToggleButton`s so the checked state
  uses the theme (add alias `using ToggleButton = System.Windows.Controls.Primitives.ToggleButton;`):

```csharp
    private ToggleButton IconToggle(string iconKey, string tip, bool initial, Action<bool> onChanged)
    {
        var icon = new IconPresenter { IconKey = iconKey, Width = 18, Height = 18, Brush = initial ? GlyphOn : GlyphOff };
        var b = new ToggleButton
        {
            Content = icon,
            Style = (Style)FindResource("Theme.ToolButton"),
            Width = 34, Height = 30,
            Margin = new Thickness(2, 0, 2, 0),
            ToolTip = tip,
            IsChecked = initial,
        };
        System.Windows.Automation.AutomationProperties.SetName(b, tip);
        b.Click += (_, _) =>
        {
            bool on = b.IsChecked == true;
            icon.Brush = on ? GlyphOn : GlyphOff;
            onChanged(on);
        };
        return b;
    }
```

  and the format segment becomes two `Theme.ToolButton` toggles (checked = current format):

```csharp
    private UIElement BuildFormatSegment()
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(4, 0, 4, 0) };
        ToggleButton mp4 = null!, gif = null!;
        void Refresh()
        {
            bool isMp4 = _settings.Recording.Format == RecordingFormat.Mp4;
            mp4.IsChecked = isMp4;
            gif.IsChecked = !isMp4;
            mp4.Foreground = isMp4 ? GlyphOn : GlyphOff;
            gif.Foreground = isMp4 ? GlyphOff : GlyphOn;
        }
        mp4 = Segment("MP4", () => { Persist(_settings.Recording with { Format = RecordingFormat.Mp4 }); Refresh(); });
        gif = Segment("GIF", () => { Persist(_settings.Recording with { Format = RecordingFormat.Gif }); Refresh(); });
        panel.Children.Add(mp4);
        panel.Children.Add(gif);
        Refresh();
        return panel;

        ToggleButton Segment(string text, Action onClick)
        {
            var b = new ToggleButton
            {
                Content = text,
                Style = (Style)FindResource("Theme.ToolButton"),
                Width = 46, Height = 28, FontSize = 12,
            };
            b.Click += (_, _) => onClick();
            return b;
        }
    }
```

  Delete the now-unused `SegmentButton`/`StyleSegment` helpers; `IconButton` (Cancel ✕) switches to
  `Style = (Style)FindResource("Theme.SubtleButton")` on a `Button` and drops its manual
  Background/BorderThickness; `TextButton` keeps defaults (implicit theme). `GlyphOff` is now also the
  strip's text color — `TextButton` inherits the theme `Foreground` automatically.

- [x] **Step 4: Dark tray menu** — create `Tray/DarkMenu.cs`:

```csharp
using System.Drawing;
using WF = System.Windows.Forms;

namespace BetterScreenshot.App.Tray;

/// <summary>Dark palette for the tray ContextMenuStrip, mirroring Theme.xaml (card/hover/hairline/text).</summary>
internal sealed class DarkMenuColors : WF.ProfessionalColorTable
{
    public static readonly Color Surface = Color.FromArgb(0x2C, 0x2C, 0x30);
    public static readonly Color Hover = Color.FromArgb(0x3A, 0x3A, 0x3F);
    public static readonly Color Hairline = Color.FromArgb(0x45, 0x45, 0x4A);

    public override Color ToolStripDropDownBackground => Surface;
    public override Color ImageMarginGradientBegin => Surface;
    public override Color ImageMarginGradientMiddle => Surface;
    public override Color ImageMarginGradientEnd => Surface;
    public override Color MenuItemSelected => Hover;
    public override Color MenuItemSelectedGradientBegin => Hover;
    public override Color MenuItemSelectedGradientEnd => Hover;
    public override Color MenuItemBorder => Hover;
    public override Color MenuBorder => Hairline;
    public override Color SeparatorDark => Hairline;
    public override Color SeparatorLight => Hairline;
}

internal sealed class DarkMenuRenderer : WF.ToolStripProfessionalRenderer
{
    public DarkMenuRenderer() : base(new DarkMenuColors()) { }

    protected override void OnRenderItemText(WF.ToolStripItemTextRenderEventArgs e)
    {
        e.TextColor = e.Item.Enabled ? Color.FromArgb(0xF2, 0xF2, 0xF5) : Color.FromArgb(0x8A, 0x8A, 0x90);
        base.OnRenderItemText(e);
    }
}
```

  In `TrayIcon` ctor, right after `var menu = new WF.ContextMenuStrip();`:

```csharp
        menu.Renderer = new DarkMenuRenderer();
        menu.ShowImageMargin = false;
```

- [x] **Step 5: Build + tests** — both green.

- [x] **Step 6: Commit**

```bash
git add windows/src/BetterScreenshot.App/Onboarding/WelcomeWindow.xaml windows/src/BetterScreenshot.App/Onboarding/WelcomeWindow.xaml.cs windows/src/BetterScreenshot.App/History/HistoryWindow.xaml windows/src/BetterScreenshot.App/History/HistoryWindow.xaml.cs windows/src/BetterScreenshot.App/Recording/RecordStripWindow.xaml windows/src/BetterScreenshot.App/Recording/RecordStripWindow.xaml.cs windows/src/BetterScreenshot.App/Tray/DarkMenu.cs windows/src/BetterScreenshot.App/Tray/TrayIcon.cs
git commit -m "feat(win): dark welcome/history/record-strip surfaces + dark tray menu"
```

---

### Task 7: `--ui-preview` gallery, visual verification, publish, docs

**Files:**
- Create: `windows/src/BetterScreenshot.App/UiPreview.cs`
- Modify: `windows/src/BetterScreenshot.App/App.xaml.cs` (flag check at the top of `OnStartup`)
- Modify: `windows/docs/PROGRESS.md` (append findings/decisions)

**Interfaces:**
- Consumes: every window revamped above; `SettingsStore` (in-memory), `HotkeyController(IAppCommands)`,
  `QuickAccessActions` (property-init class of `Action`s), `QuickAccessKind`, `RecordStripWindow(SettingsStore)`.
- Produces: `BetterScreenshot.App.exe --ui-preview <settings|editor|quickaccess|welcome|strip>`.

- [x] **Step 1: Create `UiPreview.cs`**:

```csharp
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BetterScreenshot.App.Editor;
using BetterScreenshot.App.Onboarding;
using BetterScreenshot.App.Overlays;
using BetterScreenshot.App.Recording;
using BetterScreenshot.App.Settings;
using BetterScreenshot.App.Tray;
using BetterScreenshot.Platform;
using Application = System.Windows.Application;
using Color = System.Windows.Media.Color;
using Point = System.Windows.Point;
using Size = System.Windows.Size;

namespace BetterScreenshot.App;

/// <summary>
/// Dev-only window gallery: `BetterScreenshot.exe --ui-preview &lt;name&gt;` opens one window with sample
/// data and NO tray/hotkeys/single-instance mutex, so the themed UI can be screenshotted (even while a
/// real instance is running). Settings are in-memory defaults — nothing is persisted from a preview.
/// </summary>
internal static class UiPreview
{
    private sealed class NullCommands : IAppCommands
    {
        public void CaptureArea() { }
        public void CaptureWindow() { }
        public void CaptureFullscreen() { }
        public void CaptureText() { }
        public void ToggleRecording() { }
        public void PauseResumeRecording() { }
        public void PinFromClipboard() { }
        public void OpenHistory() { }
        public void RestoreRecentlyClosed() { }
        public void OpenSettings() { }
        public void Quit() { }
    }

    public static void Show(string name)
    {
        Application.Current.ShutdownMode = ShutdownMode.OnLastWindowClose;
        switch (name)
        {
            case "editor":
                new EditorWindow(SampleImage(900, 560)).Show();
                break;
            case "quickaccess":
                var qa = new QuickAccessWindow(SampleImage(400, 224), QuickAccessKind.Screenshot,
                    new QuickAccessActions(), dragFile: null);
                qa.MoveTo(320, 280);
                qa.Show();
                break;
            case "welcome":
                new WelcomeWindow().Show();
                break;
            case "strip":
                new RecordStripWindow(new SettingsStore()).Show();
                break;
            default:
                new SettingsWindow(new SettingsStore(), new HotkeyController(new NullCommands())).Show();
                break;
        }
    }

    /// <summary>A recognizable sample bitmap (diagonal gradient + a light panel) for thumbnails/canvas.</summary>
    private static BitmapSource SampleImage(int width, int height)
    {
        var visual = new DrawingVisual();
        using (var dc = visual.RenderOpen())
        {
            var gradient = new LinearGradientBrush(
                Color.FromRgb(0x3A, 0x5F, 0x9E), Color.FromRgb(0x7A, 0x4F, 0x8E),
                new Point(0, 0), new Point(1, 1));
            dc.DrawRectangle(gradient, null, new Rect(0, 0, width, height));
            dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb(0x66, 0xFF, 0xFF, 0xFF)), null,
                new Rect(width * 0.12, height * 0.18, width * 0.5, height * 0.4), 12, 12);
        }
        var bmp = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
        bmp.Render(visual);
        bmp.Freeze();
        return bmp;
    }
}
```

- [x] **Step 2: Flag check in `App.OnStartup`** — insert immediately after `base.OnStartup(e);`, **before**
  the mutex:

```csharp
        // Dev-only UI gallery (see UiPreview): no mutex/tray/hotkeys, coexists with a live instance.
        if (e.Args.Length >= 1 && e.Args[0] == "--ui-preview")
        {
            UiPreview.Show(e.Args.Length > 1 ? e.Args[1] : "settings");
            return;
        }
```

  Note: `OnExit` guards — `_commands`/`_hotkeys`/`_tray` are null in preview mode; the existing
  null-conditional calls (`?.`) already handle that, and `_ownsInstance` stays false.

- [x] **Step 3: Build, test, then screenshot each surface.** Build + tests green first, then from a
  PowerShell session:

```powershell
$exe = "windows\src\BetterScreenshot.App\bin\Debug\net9.0-windows10.0.19041.0\BetterScreenshot.App.exe"
foreach ($v in "settings","editor","quickaccess","welcome","strip") {
  $p = Start-Process $exe -ArgumentList "--ui-preview",$v -PassThru
  Start-Sleep 3
  Add-Type -AssemblyName System.Drawing, System.Windows.Forms
  $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($b.X, $b.Y, 0, 0, $bmp.Size)
  $bmp.Save("$env:TEMP\bs-preview-$v.png"); $g.Dispose(); $bmp.Dispose()
  Stop-Process -Id $p.Id -Force
}
```

  Inspect each PNG (Read tool): dark surfaces, rounded segmented tabs, no squared blue hover, icon
  toolbar in the editor, mono shortcut chips (`Ctrl+Shift+4`, not `(vk …)`). Fix and re-shoot until right.

- [x] **Step 4: Behavioral spot-checks** (manual, from the built exe): rebind a shortcut in a preview
  settings window → close via ✕ → the in-memory store kept it (watch for no revert); full end-to-end
  persistence is exercised by the real app on next launch.

- [x] **Step 5: Re-publish + docs** — run `pwsh windows/scripts/publish-app.ps1` so the Desktop-shortcut
  build has the new UI. Append to `windows/docs/PROGRESS.md` (UI revamp section): the instant-apply
  decision, US-layout OEM label assumption, `--ui-preview` usage, and any visual fixes made in Step 3.

- [x] **Step 6: Commit**

```bash
git add windows/src/BetterScreenshot.App/UiPreview.cs windows/src/BetterScreenshot.App/App.xaml.cs windows/docs/PROGRESS.md
git commit -m "feat(win): --ui-preview gallery for visual verification + revamp notes"
```

---

## Self-review notes

- Spec coverage: dark theme (T2), settings instant-apply + tray sync + chips (T3), key names (T1),
  Quick Access dark/hover/drag (T4), editor icons/inspector (T5), Welcome/History/RecordStrip/tray (T6),
  preview + screenshots + publish + PROGRESS (T7). Out-of-scope items match the spec.
- Types cross-checked against live code: `QuickAccessActions` is a property-init class (not a record) —
  `new QuickAccessActions()` is valid; `IAppCommands` has the 11 methods stubbed in `NullCommands`;
  `RecordStripWindow(SettingsStore)` and `EditorWindow(BitmapSource, AnnotationStyle?)` ctors confirmed.
- Known judgment calls: `RGBAColor` equality in T5 (verify record-struct equality; fall back to
  tolerance compare); Cascadia Mono falls back to Consolas via WPF font-family fallback syntax.
