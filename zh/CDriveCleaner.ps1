# ============================================================
#  C盘清理工具 v1.0
#  支持 Windows 7 / 10 / 11
#  美观WPF界面 + 智能清理
# ============================================================

# 管理员权限检查
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $scriptPath = $MyInvocation.MyCommand.Path
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
    exit
}

# 加载WPF程序集
Add-Type -AssemblyName PresentationFramework, System.Windows.Forms, System.Drawing

# 加载回收站清理API
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class RecycleBinAPI {
    [DllImport("Shell32.dll", CharSet = CharSet.Unicode)]
    public static extern uint SHEmptyRecycleBin(IntPtr hwnd, string pszRootPath, uint dwFlags);
}
'@ -ErrorAction SilentlyContinue

# ============================================================
#  辅助函数
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
#  清理项定义
# ============================================================

$cleanItems = @(
    @{
        Id       = "WindowsTemp"
        Name     = "Windows 临时文件"
        Desc     = "系统临时文件夹中的缓存文件"
        Location = "$env:SystemRoot\Temp"
        Risk     = "safe"
        Default  = $true
        Paths    = @("$env:SystemRoot\Temp")
    },
    @{
        Id       = "UserTemp"
        Name     = "用户临时文件"
        Desc     = "用户临时文件夹中的缓存文件"
        Location = "$env:TEMP"
        Risk     = "safe"
        Default  = $true
        Paths    = @($env:TEMP)
    },
    @{
        Id       = "RecycleBin"
        Name     = "回收站"
        Desc     = "已删除但未彻底清除的文件"
        Location = "C:\`$Recycle.Bin"
        Risk     = "safe"
        Default  = $true
        Paths    = @("RECYCLEBIN")
    },
    @{
        Id       = "BrowserCache"
        Name     = "浏览器缓存"
        Desc     = "Chrome / Edge / Firefox 缓存数据"
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
        Name     = "缩略图缓存"
        Desc     = "资源管理器缩略图数据库文件"
        Location = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*"
        Risk     = "safe"
        Default  = $true
        Paths    = @("$env:LOCALAPPDATA\Microsoft\Windows\Explorer")
        Pattern  = "thumbcache_*"
    },
    @{
        Id       = "WindowsUpdate"
        Name     = "Windows 更新缓存"
        Desc     = "已下载的更新安装包（清理后需重新下载）"
        Location = "$env:SystemRoot\SoftwareDistribution\Download"
        Risk     = "moderate"
        Default  = $false
        Paths    = @("$env:SystemRoot\SoftwareDistribution\Download")
    },
    @{
        Id       = "DNSCache"
        Name     = "DNS 缓存"
        Desc     = "域名解析缓存（清理后网页首次加载略慢）"
        Location = "系统 DNS 解析缓存"
        Risk     = "safe"
        Default  = $true
        Paths    = @("DNSCACHE")
    }
)

# ============================================================
#  XAML 界面定义
# ============================================================

$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="C盘清理工具" Height="720" Width="680"
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
            <Setter Property="FontFamily" Value="Microsoft YaHei"/>
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
            <Setter Property="FontFamily" Value="Microsoft YaHei"/>
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
            <Setter Property="FontFamily" Value="Microsoft YaHei"/>
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
            <Setter Property="FontFamily" Value="Microsoft YaHei"/>
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

            <!-- 标题栏 -->
            <Grid Grid.Row="0" Margin="20,0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock Text="C" FontSize="24" FontWeight="Bold" Margin="0,0,6,0" VerticalAlignment="Center"
                               Foreground="#FF58A6FF" FontFamily="Microsoft YaHei"/>
                    <TextBlock Text="盘清理工具" FontSize="20" FontWeight="Bold"
                               Foreground="#FFF0F6FC" VerticalAlignment="Center"
                               FontFamily="Microsoft YaHei"/>
                    <TextBlock Text="v1.0" FontSize="11" Foreground="#FF484F58"
                               VerticalAlignment="Bottom" Margin="6,0,0,4"
                               FontFamily="Microsoft YaHei"/>
                </StackPanel>

                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                    <Button x:Name="BtnMinimize" Content="-" Style="{StaticResource TitleBtn}"/>
                    <Button x:Name="BtnClose" Content="x" Style="{StaticResource TitleBtn}"/>
                </StackPanel>
            </Grid>

            <!-- 磁盘空间信息 -->
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
                        <TextBlock x:Name="DiskInfo" Text="C盘: 正在检测..."
                                   Foreground="#FFF0F6FC" FontSize="15" FontWeight="SemiBold"
                                   FontFamily="Microsoft YaHei"/>
                        <TextBlock x:Name="DiskPercent" Grid.Column="1" Text=""
                                   Foreground="#FF8B949E" FontSize="13"
                                   FontFamily="Microsoft YaHei" VerticalAlignment="Center"/>
                    </Grid>

                    <ProgressBar Grid.Row="1" x:Name="DiskProgress" Value="0" Margin="0,10,0,0"/>

                    <Grid Grid.Row="2" Margin="0,8,0,0">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="总容量: " Foreground="#FF8B949E" FontSize="12" FontFamily="Microsoft YaHei"/>
                            <TextBlock x:Name="DiskTotal" Text="--" Foreground="#FFF0F6FC" FontSize="12" FontFamily="Microsoft YaHei"/>
                        </StackPanel>
                        <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Center">
                            <TextBlock Text="已用: " Foreground="#FF8B949E" FontSize="12" FontFamily="Microsoft YaHei"/>
                            <TextBlock x:Name="DiskUsed" Text="--" Foreground="#FFF0F6FC" FontSize="12" FontFamily="Microsoft YaHei"/>
                        </StackPanel>
                        <StackPanel Grid.Column="2" Orientation="Horizontal" HorizontalAlignment="Right">
                            <TextBlock Text="可用: " Foreground="#FF8B949E" FontSize="12" FontFamily="Microsoft YaHei"/>
                            <TextBlock x:Name="DiskFree" Text="--" Foreground="#FF3FB950" FontSize="12" FontWeight="SemiBold" FontFamily="Microsoft YaHei"/>
                        </StackPanel>
                    </Grid>
                </Grid>
            </Border>

            <!-- 清理项列表 -->
            <ScrollViewer Grid.Row="2" Margin="20,0,20,12" VerticalScrollBarVisibility="Auto">
                <StackPanel x:Name="ItemList"/>
            </ScrollViewer>

            <!-- 进度区域 -->
            <Grid Grid.Row="3" Margin="20,0,20,8">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <ProgressBar x:Name="CleanProgress" Value="0" Grid.Row="0" Visibility="Collapsed"/>

                <TextBlock x:Name="StatusText" Grid.Row="1" Text="就绪 - 点击「扫描」检测可清理的文件"
                           Foreground="#FF8B949E" FontSize="12" Margin="0,8,0,0"
                           FontFamily="Microsoft YaHei"/>
            </Grid>

            <!-- 操作按钮 -->
            <Grid Grid.Row="4" Margin="20,0,20,20">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock x:Name="TotalSize" Text="可清理: --"
                               Foreground="#FF58A6FF" FontSize="14" FontWeight="SemiBold"
                               FontFamily="Microsoft YaHei" VerticalAlignment="Center"/>
                </StackPanel>

                <Button x:Name="BtnSelectAll" Grid.Column="1" Content="全选"
                        Style="{StaticResource SelectAllBtn}" Margin="0,0,10,0"/>
                <Button x:Name="BtnScan" Grid.Column="2" Content="扫描"
                        Style="{StaticResource ScanBtn}" Margin="0,0,10,0"/>
                <Button x:Name="BtnClean" Grid.Column="3" Content="清理"
                        Style="{StaticResource CleanBtn}" IsEnabled="False"/>
            </Grid>
        </Grid>
    </Border>
</Window>
'@

# ============================================================
#  加载XAML并创建窗口
# ============================================================

try {
    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]$xaml)
    $window = [Windows.Markup.XamlReader]::Load($reader)
} catch {
    [System.Windows.Forms.MessageBox]::Show("界面加载失败: $($_.Exception.Message)", "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    exit 1
}

# ============================================================
#  获取控件引用
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
#  窗口拖动 & 按钮事件
# ============================================================

$window.Add_MouseLeftButtonDown({ $window.DragMove() })
$BtnMinimize.Add_Click({ $window.WindowState = [System.Windows.WindowState]::Minimized })
$BtnClose.Add_Click({ $window.Close() })

# ============================================================
#  颜色辅助
# ============================================================

function Get-Brush {
    param([string]$Hex)
    return [System.Windows.Media.BrushConverter]::new().ConvertFrom($Hex)
}

# ============================================================
#  动态生成清理项卡片
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

    # 复选框
    $checkbox = New-Object System.Windows.Controls.CheckBox
    $checkbox.IsChecked = $item.Default
    $checkbox.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $checkbox.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
    $checkbox.Tag = $item.Id
    [System.Windows.Controls.Grid]::SetColumn($checkbox, 0)
    $grid.Children.Add($checkbox)

    # 名称和描述
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
    $nameText.FontFamily = New-Object System.Windows.Media.FontFamily("Microsoft YaHei")
    $namePanel.Children.Add($nameText)

    # 风险标签
    if ($item.Risk -eq "moderate") {
        $riskTag = New-Object System.Windows.Controls.Border
        $riskTag.Background = Get-Brush "#FFF0883E"
        $riskTag.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $riskTag.Padding = [System.Windows.Thickness]::new(6, 1, 6, 1)
        $riskTag.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
        $riskTag.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $riskLabel = New-Object System.Windows.Controls.TextBlock
        $riskLabel.Text = "注意"
        $riskLabel.Foreground = [System.Windows.Media.Brushes]::Black
        $riskLabel.FontSize = 10
        $riskLabel.FontWeight = [System.Windows.FontWeights]::Bold
        $riskLabel.FontFamily = New-Object System.Windows.Media.FontFamily("Microsoft YaHei")
        $riskTag.Child = $riskLabel
        $namePanel.Children.Add($riskTag)
    }

    $stack.Children.Add($namePanel)

    $descText = New-Object System.Windows.Controls.TextBlock
    $descText.Text = $item.Desc
    $descText.Foreground = Get-Brush "#FF8B949E"
    $descText.FontSize = 12
    $descText.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
    $descText.FontFamily = New-Object System.Windows.Media.FontFamily("Microsoft YaHei")
    $stack.Children.Add($descText)

    # 位置信息
    $locText = New-Object System.Windows.Controls.TextBlock
    $locText.Text = $item.Location
    $locText.Foreground = Get-Brush "#FF484F58"
    $locText.FontSize = 10
    $locText.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
    $locText.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
    $stack.Children.Add($locText)

    $grid.Children.Add($stack)

    # 大小标签
    $sizeText = New-Object System.Windows.Controls.TextBlock
    $sizeText.Text = "--"
    $sizeText.Foreground = Get-Brush "#FF58A6FF"
    $sizeText.FontSize = 14
    $sizeText.FontWeight = [System.Windows.FontWeights]::SemiBold
    $sizeText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $sizeText.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
    $sizeText.FontFamily = New-Object System.Windows.Media.FontFamily("Microsoft YaHei")
    [System.Windows.Controls.Grid]::SetColumn($sizeText, 2)
    $grid.Children.Add($sizeText)

    $border.Child = $grid

    # 整行可点击切换复选框
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
#  更新磁盘信息
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

            $DiskInfo.Text = "C盘: $(Format-FileSize $used) / $(Format-FileSize $total)"
            $DiskPercent.Text = "$percent% 已使用"
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
        $DiskInfo.Text = "C盘: 无法获取信息"
    }
}

Update-DiskInfo

# ============================================================
#  扫描功能
# ============================================================

$BtnScan.Add_Click({
    $BtnScan.IsEnabled = $false
    $BtnClean.IsEnabled = $false
    $StatusText.Text = "正在扫描，请稍候..."
    $StatusText.Foreground = Get-Brush "#FF58A6FF"

    $totalScanned = 0

    foreach ($item in $cleanItems) {
        # 跳过未勾选的项目
        if (-not $checkBoxes[$item.Id].IsChecked) {
            $sizeLabels[$item.Id].Text = "--"
            $sizeLabels[$item.Id].Foreground = Get-Brush "#FF484F58"
            $scannedSizes[$item.Id] = 0
            continue
        }

        $size = 0

        if ($item.Id -eq "RecycleBin") {
            try {
                # 用 Shell API 获取回收站大小（只统计用户可见内容，排除 desktop.ini 等）
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
            $sizeLabels[$item.Id].Text = "缓存"
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

    $TotalSize.Text = "可清理: $(Format-FileSize $totalScanned)"
    $StatusText.Text = "扫描完成 - 共发现 $(Format-FileSize $totalScanned) 可清理文件"
    $StatusText.Foreground = Get-Brush "#FF3FB950"
    $BtnScan.IsEnabled = $true
    $BtnClean.IsEnabled = $true
})

# ============================================================
#  清理功能
# ============================================================

$BtnClean.Add_Click({
    $selectedItems = @()
    foreach ($item in $cleanItems) {
        if ($checkBoxes[$item.Id].IsChecked) {
            $selectedItems += $item
        }
    }

    if ($selectedItems.Count -eq 0) {
        [System.Windows.MessageBox]::Show("请至少选择一项清理内容", "提示", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }

    $hasModerate = $selectedItems | Where-Object { $_.Risk -eq "moderate" }
    $msg = "确定要清理选中的 $($selectedItems.Count) 项内容吗？"
    if ($hasModerate) {
        $msg += "`n`n其中包含标记为「注意」的项目，清理后可能影响部分功能。"
    }
    $result = [System.Windows.MessageBox]::Show($msg, "确认清理", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
    if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }

    $BtnClean.IsEnabled = $false
    $BtnScan.IsEnabled = $false
    $CleanProgress.Visibility = [System.Windows.Visibility]::Visible
    $CleanProgress.Value = 0
    $StatusText.Text = "正在清理..."
    $StatusText.Foreground = Get-Brush "#FF58A6FF"

    $totalFreed = 0
    $totalSteps = $selectedItems.Count
    $currentStep = 0

    foreach ($item in $selectedItems) {
        $currentStep++
        $StatusText.Text = "正在清理: $($item.Name) ($currentStep/$totalSteps)..."
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
                    # 方法1: Win32 API SHEmptyRecycleBin (最可靠)
                    try {
                        [RecycleBinAPI]::SHEmptyRecycleBin([IntPtr]::Zero, [NullString]::Value, 7) | Out-Null
                    } catch {}
                    # 方法2: Clear-RecycleBin (Win8+/PS5+)
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
        $sizeLabels[$item.Id].Text = if ($item.Id -eq "DNSCache") { "已清理" } else { "0 B" }
        $sizeLabels[$item.Id].Foreground = Get-Brush "#FF3FB950"

        $CleanProgress.Value = ($currentStep / $totalSteps) * 100
        [System.Windows.Forms.Application]::DoEvents()
    }

    Update-DiskInfo

    $CleanProgress.Visibility = [System.Windows.Visibility]::Collapsed
    $StatusText.Text = "清理完成！共释放 $(Format-FileSize $totalFreed) 磁盘空间（部分缓存文件无法清理）"
    $StatusText.Foreground = Get-Brush "#FF3FB950"
    $TotalSize.Text = "已释放: $(Format-FileSize $totalFreed)"
    $BtnScan.IsEnabled = $true
    $BtnClean.IsEnabled = $false



})

# ============================================================
#  全选/取消全选
# ============================================================

$BtnSelectAll.Tag = $false
$BtnSelectAll.Add_Click({
    $BtnSelectAll.Tag = -not $BtnSelectAll.Tag
    $val = $BtnSelectAll.Tag
    foreach ($key in $checkBoxes.Keys) {
        $checkBoxes[$key].IsChecked = $val
    }
    $BtnSelectAll.Content = if ($val) { "取消全选" } else { "全选" }
})

# ============================================================
#  显示窗口
# ============================================================

$window.ShowDialog() | Out-Null
