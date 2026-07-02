# ============================================================
#  C Drive Cleaner v1.0
#  Supports Windows 7 / 10 / 11
#  Beautiful WPF UI + Smart Cleaning
# ============================================================

# Administrator privilege check
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $scriptPath = $MyInvocation.MyCommand.Path
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
    exit
}

# Load WPF assemblies
Add-Type -AssemblyName PresentationFramework, System.Windows.Forms, System.Drawing

# Load Recycle Bin cleanup API
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class RecycleBinAPI {
    [DllImport("Shell32.dll", CharSet = CharSet.Unicode)]
    public static extern uint SHEmptyRecycleBin(IntPtr hwnd, string pszRootPath, uint dwFlags);
}
'@ -ErrorAction SilentlyContinue

# ============================================================
#  Helper Functions
# ============================================================

function Format-FileSize {
    param([long]$Bytes)
    if ($Bytes -lt 0) { return "0 B" }
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Get-FolderSizeSafe {
    param([string]$Path)
    try {
        if (-not (Test-Path $Path)) { return 0 }
        $items = Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue -File
        if ($items) {
            return ($items | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        }
        return 0
    } catch { return 0 }
}

function Get-FilePatternSize {
    param([string]$Path, [string]$Filter)
    try {
        if (-not (Test-Path $Path)) { return 0 }
        $items = Get-ChildItem -Path $Path -Filter $Filter -Force -ErrorAction SilentlyContinue -File
        if ($items) {
            return ($items | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        }
        return 0
    } catch { return 0 }
}

# ============================================================
#  Cleanup Item Definitions
# ============================================================

$cleanItems = @(
    @{
        Id       = "WindowsTemp"
        Name     = "Windows Temp Files"
        Desc     = "Cache files in the system temporary folder"
        Location = "$env:SystemRoot\Temp"
        Risk     = "safe"
        Default  = $true
        Paths    = @("$env:SystemRoot\Temp")
    },
    @{
        Id       = "UserTemp"
        Name     = "User Temp Files"
        Desc     = "Cache files in the user temporary folder"
        Location = "$env:TEMP"
        Risk     = "safe"
        Default  = $true
        Paths    = @($env:TEMP)
    },
    @{
        Id       = "RecycleBin"
        Name     = "Recycle Bin"
        Desc     = "Deleted files not yet permanently removed"
        Location = "C:\`$Recycle.Bin"
        Risk     = "safe"
        Default  = $true
        Paths    = @("RECYCLEBIN")
    },
    @{
        Id       = "BrowserCache"
        Name     = "Browser Cache"
        Desc     = "Chrome / Edge / Firefox cached data"
        Location = "$env:LOCALAPPDATA\Google\Chrome\... | Edge\... | Firefox\..."
        Risk     = "safe"
        Default  = $true
        Paths    = @(
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\GPUCache",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\GPUCache",
            "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
        )
    },
    @{
        Id       = "ThumbnailCache"
        Name     = "Thumbnail Cache"
        Desc     = "Explorer thumbnail database files"
        Location = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*"
        Risk     = "safe"
        Default  = $true
        Paths    = @("$env:LOCALAPPDATA\Microsoft\Windows\Explorer")
        Pattern  = "thumbcache_*"
    },
    @{
        Id       = "WindowsUpdate"
        Name     = "Windows Update Cache"
        Desc     = "Downloaded update packages (will re-download if needed)"
        Location = "$env:SystemRoot\SoftwareDistribution\Download"
        Risk     = "moderate"
        Default  = $false
        Paths    = @("$env:SystemRoot\SoftwareDistribution\Download")
    },
    @{
        Id       = "DNSCache"
        Name     = "DNS Cache"
        Desc     = "DNS resolver cache (slower first page load after clearing)"
        Location = "System DNS Resolver Cache"
        Risk     = "safe"
        Default  = $true
        Paths    = @("DNSCACHE")
    }
)

# ============================================================
#  XAML UI Definition
# ============================================================

$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="C Drive Cleaner" Height="720" Width="680"
    WindowStartupLocation="CenterScreen"
    ResizeMode="CanMinimize"
    Background="#FF0D1117">

    <Window.Resources>
        <Style x:Key="CardBorder" TargetType="Border">
            <Setter Property="Background" Value="#FF161B22"/>
            <Setter Property="CornerRadius" Value="10"/>
            <Setter Property="Padding" Value="16,12"/>
            <Setter Property="Margin" Value="0,4"/>
            <Setter Property="BorderBrush" Value="#FF30363D"/>
            <Setter Property="BorderThickness" Value="1"/>
        </Style>

        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#FFF0F6FC"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>

        <Style x:Key="ScanBtn" TargetType="Button">
            <Setter Property="FontFamily" Value="Segoe UI"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Background" Value="#FF1F6FEB"/>
            <Setter Property="Foreground" Value="#FFFFFFFF"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="8" Padding="20,10">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="CleanBtn" TargetType="Button">
            <Setter Property="FontFamily" Value="Segoe UI"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Background" Value="#FF238636"/>
            <Setter Property="Foreground" Value="#FFFFFFFF"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="8" Padding="20,10">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="SelectAllBtn" TargetType="Button">
            <Setter Property="FontFamily" Value="Segoe UI"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Background" Value="#FF30363D"/>
            <Setter Property="Foreground" Value="#FFF0F6FC"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="8" Padding="20,10">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="TitleBtn" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="#FF8B949E"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FontFamily" Value="Segoe UI"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" Width="36" Height="36">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="ProgressBar">
            <Setter Property="Height" Value="6"/>
            <Setter Property="Foreground" Value="#FF1F6FEB"/>
            <Setter Property="Background" Value="#FF21262D"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ProgressBar">
                        <Grid>
                            <Border Background="{TemplateBinding Background}" CornerRadius="3"/>
                            <Border x:Name="PART_Track" CornerRadius="3"/>
                            <Border x:Name="PART_Indicator" HorizontalAlignment="Left"
                                    Background="{TemplateBinding Foreground}" CornerRadius="3"/>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Border CornerRadius="12" BorderBrush="#FF30363D" BorderThickness="1" Background="#FF0D1117">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="56"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- Title Bar -->
            <Grid Grid.Row="0" Margin="20,0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock Text="C" FontSize="24" FontWeight="Bold" Margin="0,0,6,0" VerticalAlignment="Center"
                               Foreground="#FF58A6FF" FontFamily="Segoe UI"/>
                    <TextBlock Text="Drive Cleaner" FontSize="20" FontWeight="Bold"
                               Foreground="#FFF0F6FC" VerticalAlignment="Center"
                               FontFamily="Segoe UI"/>
                    <TextBlock Text="v1.0" FontSize="11" Foreground="#FF484F58"
                               VerticalAlignment="Bottom" Margin="6,0,0,4"
                               FontFamily="Segoe UI"/>
                </StackPanel>

                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                    <Button x:Name="BtnMinimize" Content="-" Style="{StaticResource TitleBtn}"/>
                    <Button x:Name="BtnClose" Content="x" Style="{StaticResource TitleBtn}"/>
                </StackPanel>
            </Grid>

            <!-- Disk Space Info -->
            <Border Grid.Row="1" Margin="20,0,20,12" Style="{StaticResource CardBorder}" Padding="20,16">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <Grid Grid.Row="0">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock x:Name="DiskInfo" Text="C Drive: Detecting..."
                                   Foreground="#FFF0F6FC" FontSize="15" FontWeight="SemiBold"
                                   FontFamily="Segoe UI"/>
                        <TextBlock x:Name="DiskPercent" Grid.Column="1" Text=""
                                   Foreground="#FF8B949E" FontSize="13"
                                   FontFamily="Segoe UI" VerticalAlignment="Center"/>
                    </Grid>

                    <ProgressBar Grid.Row="1" x:Name="DiskProgress" Value="0" Margin="0,10,0,0"/>

                    <Grid Grid.Row="2" Margin="0,8,0,0">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="Total: " Foreground="#FF8B949E" FontSize="12" FontFamily="Segoe UI"/>
                            <TextBlock x:Name="DiskTotal" Text="--" Foreground="#FFF0F6FC" FontSize="12" FontFamily="Segoe UI"/>
                        </StackPanel>
                        <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Center">
                            <TextBlock Text="Used: " Foreground="#FF8B949E" FontSize="12" FontFamily="Segoe UI"/>
                            <TextBlock x:Name="DiskUsed" Text="--" Foreground="#FFF0F6FC" FontSize="12" FontFamily="Segoe UI"/>
                        </StackPanel>
                        <StackPanel Grid.Column="2" Orientation="Horizontal" HorizontalAlignment="Right">
                            <TextBlock Text="Free: " Foreground="#FF8B949E" FontSize="12" FontFamily="Segoe UI"/>
                            <TextBlock x:Name="DiskFree" Text="--" Foreground="#FF3FB950" FontSize="12" FontWeight="SemiBold" FontFamily="Segoe UI"/>
                        </StackPanel>
                    </Grid>
                </Grid>
            </Border>

            <!-- Cleanup Items List -->
            <ScrollViewer Grid.Row="2" Margin="20,0,20,12" VerticalScrollBarVisibility="Auto">
                <StackPanel x:Name="ItemList"/>
            </ScrollViewer>

            <!-- Progress Area -->
            <Grid Grid.Row="3" Margin="20,0,20,8">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <ProgressBar x:Name="CleanProgress" Value="0" Grid.Row="0" Visibility="Collapsed"/>

                <TextBlock x:Name="StatusText" Grid.Row="1" Text="Ready - Click &quot;Scan&quot; to detect cleanable files"
                           Foreground="#FF8B949E" FontSize="12" Margin="0,8,0,0"
                           FontFamily="Segoe UI"/>
            </Grid>

            <!-- Action Buttons -->
            <Grid Grid.Row="4" Margin="20,0,20,20">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock x:Name="TotalSize" Text="Cleanable: --"
                               Foreground="#FF58A6FF" FontSize="14" FontWeight="SemiBold"
                               FontFamily="Segoe UI" VerticalAlignment="Center"/>
                </StackPanel>

                <Button x:Name="BtnSelectAll" Grid.Column="1" Content="Select All"
                        Style="{StaticResource SelectAllBtn}" Margin="0,0,10,0"/>
                <Button x:Name="BtnScan" Grid.Column="2" Content="Scan"
                        Style="{StaticResource ScanBtn}" Margin="0,0,10,0"/>
                <Button x:Name="BtnClean" Grid.Column="3" Content="Clean"
                        Style="{StaticResource CleanBtn}" IsEnabled="False"/>
            </Grid>
        </Grid>
    </Border>
</Window>
'@

# ============================================================
#  Load XAML and Create Window
# ============================================================

try {
    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]$xaml)
    $window = [Windows.Markup.XamlReader]::Load($reader)
} catch {
    [System.Windows.Forms.MessageBox]::Show("UI loading failed: $($_.Exception.Message)", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    exit 1
}

# ============================================================
#  Get Control References
# ============================================================

$BtnMinimize = $window.FindName("BtnMinimize")
$BtnClose = $window.FindName("BtnClose")
$BtnScan = $window.FindName("BtnScan")
$BtnClean = $window.FindName("BtnClean")
$BtnSelectAll = $window.FindName("BtnSelectAll")
$ItemList = $window.FindName("ItemList")
$DiskInfo = $window.FindName("DiskInfo")
$DiskPercent = $window.FindName("DiskPercent")
$DiskProgress = $window.FindName("DiskProgress")
$DiskTotal = $window.FindName("DiskTotal")
$DiskUsed = $window.FindName("DiskUsed")
$DiskFree = $window.FindName("DiskFree")
$TotalSize = $window.FindName("TotalSize")
$StatusText = $window.FindName("StatusText")
$CleanProgress = $window.FindName("CleanProgress")

# ============================================================
#  Window Drag & Button Events
# ============================================================

$window.Add_MouseLeftButtonDown({ $window.DragMove() })
$BtnMinimize.Add_Click({ $window.WindowState = [System.Windows.WindowState]::Minimized })
$BtnClose.Add_Click({ $window.Close() })

# ============================================================
#  Color Helper
# ============================================================

function Get-Brush {
    param([string]$Hex)
    return [System.Windows.Media.BrushConverter]::new().ConvertFrom($Hex)
}

# ============================================================
#  Dynamically Generate Cleanup Item Cards
# ============================================================

$checkBoxes = @{}
$sizeLabels = @{}
$scannedSizes = @{}

foreach ($item in $cleanItems) {
    $border = New-Object System.Windows.Controls.Border
    $border.Style = $window.Resources["CardBorder"]

    $grid = New-Object System.Windows.Controls.Grid
    $col1 = New-Object System.Windows.Controls.ColumnDefinition
    $col1.Width = [System.Windows.GridLength]::new(30)
    $col2 = New-Object System.Windows.Controls.ColumnDefinition
    $col2.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $col3 = New-Object System.Windows.Controls.ColumnDefinition
    $col3.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto)
    $grid.ColumnDefinitions.Add($col1)
    $grid.ColumnDefinitions.Add($col2)
    $grid.ColumnDefinitions.Add($col3)

    # Checkbox
    $checkbox = New-Object System.Windows.Controls.CheckBox
    $checkbox.IsChecked = $item.Default
    $checkbox.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $checkbox.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
    $checkbox.Tag = $item.Id
    [System.Windows.Controls.Grid]::SetColumn($checkbox, 0)
    $grid.Children.Add($checkbox)

    # Name and Description
    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [System.Windows.Controls.Grid]::SetColumn($stack, 1)

    $namePanel = New-Object System.Windows.Controls.StackPanel
    $namePanel.Orientation = [System.Windows.Controls.Orientation]::Horizontal

    $nameText = New-Object System.Windows.Controls.TextBlock
    $nameText.Text = $item.Name
    $nameText.Foreground = [System.Windows.Media.Brushes]::White
    $nameText.FontSize = 14
    $nameText.FontWeight = [System.Windows.FontWeights]::SemiBold
    $nameText.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
    $namePanel.Children.Add($nameText)

    # Risk Tag
    if ($item.Risk -eq "moderate") {
        $riskTag = New-Object System.Windows.Controls.Border
        $riskTag.Background = Get-Brush "#FFF0883E"
        $riskTag.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $riskTag.Padding = [System.Windows.Thickness]::new(6, 1, 6, 1)
        $riskTag.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
        $riskTag.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $riskLabel = New-Object System.Windows.Controls.TextBlock
        $riskLabel.Text = "Caution"
        $riskLabel.Foreground = [System.Windows.Media.Brushes]::Black
        $riskLabel.FontSize = 10
        $riskLabel.FontWeight = [System.Windows.FontWeights]::Bold
        $riskLabel.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
        $riskTag.Child = $riskLabel
        $namePanel.Children.Add($riskTag)
    }

    $stack.Children.Add($namePanel)

    $descText = New-Object System.Windows.Controls.TextBlock
    $descText.Text = $item.Desc
    $descText.Foreground = Get-Brush "#FF8B949E"
    $descText.FontSize = 12
    $descText.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
    $descText.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
    $stack.Children.Add($descText)

    # Location info
    $locText = New-Object System.Windows.Controls.TextBlock
    $locText.Text = $item.Location
    $locText.Foreground = Get-Brush "#FF484F58"
    $locText.FontSize = 10
    $locText.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
    $locText.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
    $stack.Children.Add($locText)

    $grid.Children.Add($stack)

    # Size Label
    $sizeText = New-Object System.Windows.Controls.TextBlock
    $sizeText.Text = "--"
    $sizeText.Foreground = Get-Brush "#FF58A6FF"
    $sizeText.FontSize = 14
    $sizeText.FontWeight = [System.Windows.FontWeights]::SemiBold
    $sizeText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $sizeText.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
    $sizeText.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
    [System.Windows.Controls.Grid]::SetColumn($sizeText, 2)
    $grid.Children.Add($sizeText)

    $border.Child = $grid

    # Click row to toggle checkbox
    $border.Add_MouseLeftButtonDown({
        param($s, $e)
        $cb = $s.Tag
        if ($cb) { $cb.IsChecked = -not $cb.IsChecked }
    }.GetNewClosure())

    $border.Tag = $checkbox

    $checkBoxes[$item.Id] = $checkbox
    $sizeLabels[$item.Id] = $sizeText
    $scannedSizes[$item.Id] = 0

    $ItemList.Children.Add($border)
}

# ============================================================
#  Update Disk Info
# ============================================================

function Update-DiskInfo {
    try {
        $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
        if (-not $disk) {
            $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
        }
        if ($disk) {
            $total = [long]$disk.Size
            $free = [long]$disk.FreeSpace
            $used = $total - $free
            $percent = [math]::Round(($used / $total) * 100, 1)

            $DiskInfo.Text = "C Drive: $(Format-FileSize $used) / $(Format-FileSize $total)"
            $DiskPercent.Text = "$percent% Used"
            $DiskTotal.Text = Format-FileSize $total
            $DiskUsed.Text = Format-FileSize $used
            $DiskFree.Text = Format-FileSize $free
            $DiskProgress.Value = $percent

            if ($percent -gt 85) {
                $DiskProgress.Foreground = Get-Brush "#FFF85149"
                $DiskFree.Foreground = Get-Brush "#FFF85149"
            } elseif ($percent -gt 70) {
                $DiskProgress.Foreground = Get-Brush "#FFF0883E"
                $DiskFree.Foreground = Get-Brush "#FFF0883E"
            } else {
                $DiskProgress.Foreground = Get-Brush "#FF1F6FEB"
                $DiskFree.Foreground = Get-Brush "#FF3FB950"
            }
        }
    } catch {
        $DiskInfo.Text = "C Drive: Unable to retrieve info"
    }
}

Update-DiskInfo

# ============================================================
#  Scan Function
# ============================================================

$BtnScan.Add_Click({
    $BtnScan.IsEnabled = $false
    $BtnClean.IsEnabled = $false
    $StatusText.Text = "Scanning, please wait..."
    $StatusText.Foreground = Get-Brush "#FF58A6FF"

    $totalScanned = 0

    foreach ($item in $cleanItems) {
        # Skip unchecked items
        if (-not $checkBoxes[$item.Id].IsChecked) {
            $sizeLabels[$item.Id].Text = "--"
            $sizeLabels[$item.Id].Foreground = Get-Brush "#FF484F58"
            $scannedSizes[$item.Id] = 0
            continue
        }

        $size = 0

        if ($item.Id -eq "RecycleBin") {
            try {
                # Use Shell API for Recycle Bin size (only user-visible items, excludes desktop.ini etc.)
                $shell = New-Object -ComObject Shell.Application
                $rb = $shell.NameSpace(0x0A)
                $rbItems = $rb.Items()
                foreach ($rbItem in $rbItems) {
                    try { $size += $rbItem.ExtendedProperty("System.Size") } catch {}
                }
            } catch { $size = 0 }
        }
        elseif ($item.Id -eq "DNSCache") {
            $size = 0
        }
        else {
            foreach ($path in $item.Paths) {
                if ($item.Pattern) {
                    $size += Get-FilePatternSize $path $item.Pattern
                } else {
                    if (Test-Path $path -ErrorAction SilentlyContinue) {
                        $itemAttr = Get-Item $path -Force -ErrorAction SilentlyContinue
                        if ($itemAttr -and -not $itemAttr.PSIsContainer) {
                            $size += $itemAttr.Length
                        } else {
                            $size += Get-FolderSizeSafe $path
                        }
                    }
                }
            }
        }

        $scannedSizes[$item.Id] = $size
        $totalScanned += $size

        if ($item.Id -eq "DNSCache") {
            $sizeLabels[$item.Id].Text = "Cache"
        } else {
            $sizeLabels[$item.Id].Text = Format-FileSize $size
        }

        if ($size -gt 1GB) {
            $sizeLabels[$item.Id].Foreground = Get-Brush "#FFF85149"
        } elseif ($size -gt 100MB) {
            $sizeLabels[$item.Id].Foreground = Get-Brush "#FFF0883E"
        } else {
            $sizeLabels[$item.Id].Foreground = Get-Brush "#FF58A6FF"
        }
    }

    $TotalSize.Text = "Cleanable: $(Format-FileSize $totalScanned)"
    $StatusText.Text = "Scan complete - $(Format-FileSize $totalScanned) cleanable files found"
    $StatusText.Foreground = Get-Brush "#FF3FB950"
    $BtnScan.IsEnabled = $true
    $BtnClean.IsEnabled = $true
})

# ============================================================
#  Clean Function
# ============================================================

$BtnClean.Add_Click({
    $selectedItems = @()
    foreach ($item in $cleanItems) {
        if ($checkBoxes[$item.Id].IsChecked) {
            $selectedItems += $item
        }
    }

    if ($selectedItems.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Please select at least one item to clean.", "Notice", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }

    $hasModerate = $selectedItems | Where-Object { $_.Risk -eq "moderate" }
    $msg = "Are you sure you want to clean $($selectedItems.Count) selected item(s)?"
    if ($hasModerate) {
        $msg += "`n`nThis includes items marked as `"Caution`" which may affect some features after cleaning."
    }
    $result = [System.Windows.MessageBox]::Show($msg, "Confirm Clean", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
    if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }

    $BtnClean.IsEnabled = $false
    $BtnScan.IsEnabled = $false
    $CleanProgress.Visibility = [System.Windows.Visibility]::Visible
    $CleanProgress.Value = 0
    $StatusText.Text = "Cleaning..."
    $StatusText.Foreground = Get-Brush "#FF58A6FF"

    $totalFreed = 0
    $totalSteps = $selectedItems.Count
    $currentStep = 0

    foreach ($item in $selectedItems) {
        $currentStep++
        $StatusText.Text = "Cleaning: $($item.Name) ($currentStep/$totalSteps)..."
        [System.Windows.Forms.Application]::DoEvents()

        $freed = 0

        try {
            switch ($item.Id) {
                "WindowsTemp" {
                    $freed = Get-FolderSizeSafe "$env:SystemRoot\Temp"
                    Remove-Item "$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
                }
                "UserTemp" {
                    $freed = Get-FolderSizeSafe $env:TEMP
                    Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
                }
                "RecycleBin" {
                    $freed = $scannedSizes["RecycleBin"]
                    # Method 1: Win32 API SHEmptyRecycleBin (most reliable)
                    try {
                        [RecycleBinAPI]::SHEmptyRecycleBin([IntPtr]::Zero, [NullString]::Value, 7) | Out-Null
                    } catch {}
                    # Method 2: Clear-RecycleBin (Win8+/PS5+)
                    try {
                        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
                    } catch {}
                }
                "BrowserCache" {
                    foreach ($path in $item.Paths) {
                        if (Test-Path $path -ErrorAction SilentlyContinue) {
                            $freed += Get-FolderSizeSafe $path
                            if ($path -like "*Firefox*") {
                                Get-ChildItem "$path\*\cache2" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                                    Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                                }
                            } else {
                                Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
                            }
                        }
                    }
                }
                "ThumbnailCache" {
                    $thumbPath = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
                    $freed = Get-FilePatternSize $thumbPath "thumbcache_*"
                    Remove-Item "$thumbPath\thumbcache_*" -Force -ErrorAction SilentlyContinue
                }
                "WindowsUpdate" {
                    $freed = Get-FolderSizeSafe "$env:SystemRoot\SoftwareDistribution\Download"
                    try {
                        Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
                        Remove-Item "$env:SystemRoot\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
                        Start-Service wuauserv -ErrorAction SilentlyContinue
                    } catch {}
                }
                "DNSCache" {
                    ipconfig /flushdns | Out-Null
                    $freed = 0
                }
            }
        } catch {}

        $totalFreed += $freed
        $scannedSizes[$item.Id] = 0
        $sizeLabels[$item.Id].Text = if ($item.Id -eq "DNSCache") { "Cleared" } else { "0 B" }
        $sizeLabels[$item.Id].Foreground = Get-Brush "#FF3FB950"

        $CleanProgress.Value = ($currentStep / $totalSteps) * 100
        [System.Windows.Forms.Application]::DoEvents()
    }

    Update-DiskInfo

    $CleanProgress.Visibility = [System.Windows.Visibility]::Collapsed
    $StatusText.Text = "Cleanup complete! Freed $(Format-FileSize $totalFreed) of disk space (some cache files could not be cleaned)"
    $StatusText.Foreground = Get-Brush "#FF3FB950"
    $TotalSize.Text = "Freed: $(Format-FileSize $totalFreed)"
    $BtnScan.IsEnabled = $true
    $BtnClean.IsEnabled = $false
})

# ============================================================
#  Select All / Deselect All
# ============================================================

$BtnSelectAll.Tag = $false
$BtnSelectAll.Add_Click({
    $BtnSelectAll.Tag = -not $BtnSelectAll.Tag
    $val = $BtnSelectAll.Tag
    foreach ($key in $checkBoxes.Keys) {
        $checkBoxes[$key].IsChecked = $val
    }
    $BtnSelectAll.Content = if ($val) { "Deselect All" } else { "Select All" }
})

# ============================================================
#  Show Window
# ============================================================

$window.ShowDialog() | Out-Null
