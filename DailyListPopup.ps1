Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName Microsoft.VisualBasic

# Path for data storage
$scriptDir = if ($env:DAFTAR_HARIAN_APP_DIR) { $env:DAFTAR_HARIAN_APP_DIR } elseif ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { Split-Path -Parent $PSCommandPath }
$scriptDir = if ([string]::IsNullOrWhiteSpace($scriptDir)) { Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'DaftarHarian' } else { $scriptDir }
$env:DAFTAR_HARIAN_APP_DIR = $scriptDir
$script:dataDirectory = Join-Path $scriptDir 'data'
$script:storagePath = Join-Path $script:dataDirectory 'daily-list-data.json'
$script:currentDate = (Get-Date).Date

function New-DataStore {
    return [pscustomobject]@{
        version          = 1
        lastRolloverDate = ''
        days             = [pscustomobject]@{}
    }
}

function Load-Data {
    if (Test-Path -LiteralPath $script:storagePath) {
        try {
            $loaded = Get-Content -LiteralPath $script:storagePath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $loaded -and $null -ne $loaded.days) {
                if ($null -eq $loaded.PSObject.Properties['lastRolloverDate']) {
                    $loaded | Add-Member -MemberType NoteProperty -Name 'lastRolloverDate' -Value ''
                }
                return $loaded
            }
        } catch { }
    }
    return New-DataStore
}

$script:data = Load-Data

function Get-DateKey { return $script:currentDate.ToString('yyyy-MM-dd') }

function Get-DayTasks {
    $key = Get-DateKey
    $property = $script:data.days.PSObject.Properties[$key]
    if ($null -eq $property) {
        $script:data.days | Add-Member -MemberType NoteProperty -Name $key -Value @()
        $property = $script:data.days.PSObject.Properties[$key]
    }
    return @($property.Value)
}

function Set-DayTasks([object[]]$tasks) {
    $key = Get-DateKey
    $script:data.days.PSObject.Properties[$key].Value = @($tasks)
}

function Save-Data {
    try {
        # WPF event handlers can run in a different script scope, so derive the
        # storage path from the process environment instead of a scoped variable.
        $appDirectory = $env:DAFTAR_HARIAN_APP_DIR
        if ([string]::IsNullOrWhiteSpace($appDirectory)) {
            $appDirectory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'DaftarHarian'
        }
        $dataDirectory = Join-Path $appDirectory 'data'
        $storagePath = Join-Path $dataDirectory 'daily-list-data.json'
        $script:dataDirectory = $dataDirectory
        $script:storagePath = $storagePath

        if (-not (Test-Path -LiteralPath $dataDirectory)) {
            New-Item -ItemType Directory -Path $dataDirectory -Force | Out-Null
        }
        $script:data | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $storagePath -Encoding UTF8
    } catch {
        [System.Windows.MessageBox]::Show("Tidak bisa menyimpan daftar: $($_.Exception.Message)", 'Daftar Harian') | Out-Null
    }
}

function Invoke-AutoRollover {
    $todayKey = (Get-Date).ToString('yyyy-MM-dd')
    $lastRollover = if ($script:data.PSObject.Properties['lastRolloverDate']) { [string]$script:data.lastRolloverDate } else { '' }
    if ($lastRollover -eq $todayKey) { return }

    # Find recorded past days before today
    $pastDays = @($script:data.days.PSObject.Properties | 
        Where-Object { $_.Name -lt $todayKey } | 
        Sort-Object { $_.Name })

    if ($pastDays.Count -gt 0) {
        $latestPastDay = $pastDays[-1]
        $pastUnfinished = @($latestPastDay.Value | Where-Object { -not $_.done })

        if ($pastUnfinished.Count -gt 0) {
            $todayProp = $script:data.days.PSObject.Properties[$todayKey]
            if ($null -eq $todayProp) {
                $script:data.days | Add-Member -MemberType NoteProperty -Name $todayKey -Value @()
                $todayProp = $script:data.days.PSObject.Properties[$todayKey]
            }

            $todayTasks = @($todayProp.Value)
            $existingTexts = @($todayTasks | ForEach-Object { [string]$_.text.Trim().ToLowerInvariant() })

            $toAdd = @()
            foreach ($item in $pastUnfinished) {
                $trimmed = [string]$item.text.Trim()
                if (-not [string]::IsNullOrWhiteSpace($trimmed) -and ($existingTexts -notcontains $trimmed.ToLowerInvariant())) {
                    $toAdd += [pscustomobject]@{
                        text = $trimmed
                        done = $false
                    }
                }
            }

            if ($toAdd.Count -gt 0) {
                $todayProp.Value = @($todayTasks) + @($toAdd)
            }
        }
    }

    if ($null -eq $script:data.PSObject.Properties['lastRolloverDate']) {
        $script:data | Add-Member -MemberType NoteProperty -Name 'lastRolloverDate' -Value $todayKey
    } else {
        $script:data.lastRolloverDate = $todayKey
    }
    Save-Data
}

# Auto-Start helpers
$script:startupShortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'Daftar Harian.lnk'
$script:launcherPath        = Join-Path $scriptDir 'DailyListPopup.ps1'
$script:powershellPath      = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Get-AutoStartStatus {
    return (Test-Path -LiteralPath $script:startupShortcutPath)
}

function Set-AutoStart([bool]$enable) {
    if ($enable) {
        try {
            $wsh = New-Object -ComObject WScript.Shell
            $sc = $wsh.CreateShortcut($script:startupShortcutPath)
            $sc.TargetPath = $script:powershellPath
            $sc.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script:launcherPath`""
            $sc.WorkingDirectory = $scriptDir
            $sc.Description = 'Daftar Harian Popup Otomatis'
            $sc.Save()
        } catch { }
    } else {
        if (Test-Path -LiteralPath $script:startupShortcutPath) {
            Remove-Item -LiteralPath $script:startupShortcutPath -Force -ErrorAction SilentlyContinue
        }
    }
}

# ----- Main UI XAML (refined macOS-style) -----
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Daftar Harian" Height="660" Width="440" MinHeight="480" MinWidth="380"
        WindowStartupLocation="CenterScreen" Topmost="True" ResizeMode="CanResizeWithGrip"
        AllowsTransparency="True" WindowStyle="None" Background="Transparent">
  <Window.Resources>
    <ResourceDictionary>

      <!-- ===== Palette ===== -->
      <SolidColorBrush x:Key="WindowBrush"     Color="#FFFFFF"/>
      <SolidColorBrush x:Key="CardBrush"       Color="#FFFFFF"/>
      <SolidColorBrush x:Key="PageBrush"       Color="#F5F5F7"/>
      <SolidColorBrush x:Key="AccentBrush"     Color="#0A84FF"/>
      <SolidColorBrush x:Key="AccentHover"     Color="#0071E3"/>
      <SolidColorBrush x:Key="AccentPressed"   Color="#005BB5"/>
      <SolidColorBrush x:Key="DangerBrush"     Color="#FF3B30"/>
      <SolidColorBrush x:Key="DangerHover"     Color="#E0281E"/>
      <SolidColorBrush x:Key="TextPrimary"     Color="#1D1D1F"/>
      <SolidColorBrush x:Key="TextSecondary"   Color="#86868B"/>
      <SolidColorBrush x:Key="BorderBrush2"    Color="#E2E2E6"/>
      <SolidColorBrush x:Key="RowHoverBrush"   Color="#F5F8FF"/>
      <SolidColorBrush x:Key="TitleBarBrush"   Color="#FAFAFA"/>

      <LinearGradientBrush x:Key="HeaderGradient" StartPoint="0,0" EndPoint="1,1">
        <GradientStop Color="#0A84FF" Offset="0"/>
        <GradientStop Color="#5AC8FA" Offset="1"/>
      </LinearGradientBrush>

      <FontFamily x:Key="AppFont">Segoe UI</FontFamily>
      <FontFamily x:Key="IconFont">Segoe MDL2 Assets</FontFamily>

      <DropShadowEffect x:Key="DropShadow" Color="#000000" BlurRadius="24" Opacity="0.18" Direction="270" ShadowDepth="6"/>
      <DropShadowEffect x:Key="SoftShadow" Color="#000000" BlurRadius="8"  Opacity="0.08" Direction="270" ShadowDepth="2"/>

      <!-- ===== Buttons ===== -->
      <Style x:Key="ModernButton" TargetType="Button">
        <Setter Property="Margin" Value="4"/>
        <Setter Property="Padding" Value="10,6"/>
        <Setter Property="Background" Value="{StaticResource AccentBrush}"/>
        <Setter Property="Foreground" Value="White"/>
        <Setter Property="FontWeight" Value="SemiBold"/>
        <Setter Property="FontSize" Value="13"/>
        <Setter Property="BorderThickness" Value="0"/>
        <Setter Property="Cursor" Value="Hand"/>
        <Setter Property="FontFamily" Value="{StaticResource AppFont}"/>
        <Setter Property="HorizontalContentAlignment" Value="Center"/>
        <Setter Property="Template">
          <Setter.Value>
            <ControlTemplate TargetType="Button">
              <Border x:Name="Bg" Background="{TemplateBinding Background}" CornerRadius="8">
                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
              </Border>
              <ControlTemplate.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                  <Setter TargetName="Bg" Property="Background" Value="{StaticResource AccentHover}"/>
                </Trigger>
                <Trigger Property="IsPressed" Value="True">
                  <Setter TargetName="Bg" Property="Background" Value="{StaticResource AccentPressed}"/>
                </Trigger>
              </ControlTemplate.Triggers>
            </ControlTemplate>
          </Setter.Value>
        </Setter>
      </Style>

      <Style x:Key="SecondaryButton" TargetType="Button" BasedOn="{StaticResource ModernButton}">
        <Setter Property="Background" Value="#F0F0F2"/>
        <Setter Property="Foreground" Value="{StaticResource TextPrimary}"/>
        <Setter Property="Template">
          <Setter.Value>
            <ControlTemplate TargetType="Button">
              <Border x:Name="Bg" Background="{TemplateBinding Background}" CornerRadius="8">
                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
              </Border>
              <ControlTemplate.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                  <Setter TargetName="Bg" Property="Background" Value="#E4E4E8"/>
                </Trigger>
                <Trigger Property="IsPressed" Value="True">
                  <Setter TargetName="Bg" Property="Background" Value="#D6D6DC"/>
                </Trigger>
              </ControlTemplate.Triggers>
            </ControlTemplate>
          </Setter.Value>
        </Setter>
      </Style>

      <!-- Familiar Windows-style title-bar controls -->
      <Style x:Key="WindowControlButton" TargetType="Button">
        <Setter Property="Width" Value="42"/>
        <Setter Property="Height" Value="34"/>
        <Setter Property="Padding" Value="0"/>
        <Setter Property="Margin" Value="0"/>
        <Setter Property="Background" Value="Transparent"/>
        <Setter Property="Foreground" Value="#4B5563"/>
        <Setter Property="BorderThickness" Value="0"/>
        <Setter Property="Cursor" Value="Hand"/>
        <Setter Property="FontFamily" Value="{StaticResource IconFont}"/>
        <Setter Property="FontSize" Value="10"/>
        <Setter Property="Template">
          <Setter.Value>
            <ControlTemplate TargetType="Button">
              <Border x:Name="Bg" Background="{TemplateBinding Background}">
                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <ControlTemplate.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                  <Setter TargetName="Bg" Property="Background" Value="#E5E7EB"/>
                </Trigger>
                <Trigger Property="IsPressed" Value="True">
                  <Setter TargetName="Bg" Property="Background" Value="#D1D5DB"/>
                </Trigger>
              </ControlTemplate.Triggers>
            </ControlTemplate>
          </Setter.Value>
        </Setter>
      </Style>

      <Style x:Key="WindowCloseButton" TargetType="Button" BasedOn="{StaticResource WindowControlButton}">
        <Setter Property="Template">
          <Setter.Value>
            <ControlTemplate TargetType="Button">
              <Border x:Name="Bg" Background="Transparent">
                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <ControlTemplate.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                  <Setter TargetName="Bg" Property="Background" Value="#E81123"/>
                  <Setter Property="Foreground" Value="White"/>
                </Trigger>
                <Trigger Property="IsPressed" Value="True">
                  <Setter TargetName="Bg" Property="Background" Value="#C50F1F"/>
                  <Setter Property="Foreground" Value="White"/>
                </Trigger>
              </ControlTemplate.Triggers>
            </ControlTemplate>
          </Setter.Value>
        </Setter>
      </Style>

      <!-- Circular nav / traffic-light style icon button -->
      <Style x:Key="RoundIconButton" TargetType="Button">
        <Setter Property="Width" Value="30"/>
        <Setter Property="Height" Value="30"/>
        <Setter Property="Background" Value="#F0F0F2"/>
        <Setter Property="Foreground" Value="{StaticResource TextPrimary}"/>
        <Setter Property="FontSize" Value="13"/>
        <Setter Property="Cursor" Value="Hand"/>
        <Setter Property="BorderThickness" Value="0"/>
        <Setter Property="FontFamily" Value="{StaticResource AppFont}"/>
        <Setter Property="Template">
          <Setter.Value>
            <ControlTemplate TargetType="Button">
              <Border x:Name="Bg" Background="{TemplateBinding Background}" CornerRadius="15">
                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <ControlTemplate.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                  <Setter TargetName="Bg" Property="Background" Value="#E4E4E8"/>
                </Trigger>
                <Trigger Property="IsPressed" Value="True">
                  <Setter TargetName="Bg" Property="Background" Value="#D6D6DC"/>
                </Trigger>
              </ControlTemplate.Triggers>
            </ControlTemplate>
          </Setter.Value>
        </Setter>
      </Style>

      <!-- Small flat icon button used for edit/delete on rows -->
      <Style x:Key="RowIconButton" TargetType="Button">
        <Setter Property="Width" Value="28"/>
        <Setter Property="Height" Value="28"/>
        <Setter Property="Margin" Value="3,0,0,0"/>
        <Setter Property="Background" Value="Transparent"/>
        <Setter Property="Foreground" Value="{StaticResource TextSecondary}"/>
        <Setter Property="FontFamily" Value="{StaticResource IconFont}"/>
        <Setter Property="FontSize" Value="14"/>
        <Setter Property="Cursor" Value="Hand"/>
        <Setter Property="BorderThickness" Value="0"/>
        <Setter Property="Template">
          <Setter.Value>
            <ControlTemplate TargetType="Button">
              <Border x:Name="Bg" Background="{TemplateBinding Background}" CornerRadius="7">
                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <ControlTemplate.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                  <Setter TargetName="Bg" Property="Background" Value="#EDEDF0"/>
                  <Setter Property="Foreground" Value="{StaticResource TextPrimary}"/>
                </Trigger>
              </ControlTemplate.Triggers>
            </ControlTemplate>
          </Setter.Value>
        </Setter>
      </Style>

      <!-- ===== Custom rounded checkbox ===== -->
      <Style x:Key="ModernCheckBox" TargetType="CheckBox">
        <Setter Property="FontFamily" Value="{StaticResource AppFont}"/>
        <Setter Property="Template">
          <Setter.Value>
            <ControlTemplate TargetType="CheckBox">
              <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                <Border x:Name="Box" Width="21" Height="21" CornerRadius="6" BorderBrush="{StaticResource BorderBrush2}"
                        BorderThickness="1.6" Background="White" VerticalAlignment="Center">
                  <TextBlock x:Name="CheckMark" Text="&#xE73E;" FontFamily="{StaticResource IconFont}" FontSize="11"
                             Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center" Opacity="0"/>
                </Border>
                <ContentPresenter x:Name="Cp" Margin="10,0,0,0" VerticalAlignment="Center"/>
              </StackPanel>
              <ControlTemplate.Triggers>
                <Trigger Property="IsChecked" Value="True">
                  <Setter TargetName="Box" Property="Background" Value="{StaticResource AccentBrush}"/>
                  <Setter TargetName="Box" Property="BorderBrush" Value="{StaticResource AccentBrush}"/>
                  <Setter TargetName="CheckMark" Property="Opacity" Value="1"/>
                </Trigger>
              </ControlTemplate.Triggers>
            </ControlTemplate>
          </Setter.Value>
        </Setter>
      </Style>

      <!-- ===== TextBox ===== -->
      <Style x:Key="ModernTextBox" TargetType="TextBox">
        <Setter Property="FontFamily" Value="{StaticResource AppFont}"/>
        <Setter Property="FontSize" Value="14"/>
        <Setter Property="Padding" Value="12,8"/>
        <Setter Property="Background" Value="White"/>
        <Setter Property="Foreground" Value="#1D1D1F"/>
        <Setter Property="BorderBrush" Value="{StaticResource BorderBrush2}"/>
        <Setter Property="BorderThickness" Value="1.2"/>
        <Setter Property="CaretBrush" Value="{StaticResource AccentBrush}"/>
        <Setter Property="SelectionBrush" Value="{StaticResource AccentBrush}"/>
        <Setter Property="Template">
          <Setter.Value>
            <ControlTemplate TargetType="TextBox">
              <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                      BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="9">
                <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}" VerticalAlignment="Center"
                              TextElement.Foreground="{TemplateBinding Foreground}"/>
              </Border>
              <ControlTemplate.Triggers>
                <Trigger Property="IsFocused" Value="True">
                  <Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource AccentBrush}"/>
                </Trigger>
              </ControlTemplate.Triggers>
            </ControlTemplate>
          </Setter.Value>
        </Setter>
      </Style>

      <!-- ===== Slim scrollbar ===== -->
      <Style x:Key="SlimThumb" TargetType="Thumb">
        <Setter Property="Template">
          <Setter.Value>
            <ControlTemplate TargetType="Thumb">
              <Border CornerRadius="4" Background="#C7C7CC"/>
            </ControlTemplate>
          </Setter.Value>
        </Setter>
      </Style>
      <Style TargetType="ScrollBar">
        <Setter Property="Width" Value="8"/>
        <Setter Property="Template">
          <Setter.Value>
            <ControlTemplate TargetType="ScrollBar">
              <Grid>
                <Track x:Name="PART_Track" IsDirectionReversed="True">
                  <Track.Thumb>
                    <Thumb Style="{StaticResource SlimThumb}"/>
                  </Track.Thumb>
                </Track>
              </Grid>
            </ControlTemplate>
          </Setter.Value>
        </Setter>
      </Style>

      <!-- ===== Checkbox used for "always on top" ===== -->
      <Style x:Key="OptionCheckBox" TargetType="CheckBox" BasedOn="{StaticResource ModernCheckBox}">
        <Setter Property="Foreground" Value="{StaticResource TextSecondary}"/>
        <Setter Property="FontSize" Value="12.5"/>
      </Style>

    </ResourceDictionary>
  </Window.Resources>

  <Border CornerRadius="14" Background="{StaticResource WindowBrush}" Padding="0" Effect="{StaticResource DropShadow}">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/> <!-- Title bar -->
        <RowDefinition Height="Auto"/> <!-- Header -->
        <RowDefinition Height="*"/>    <!-- Body -->
      </Grid.RowDefinitions>

      <!-- Custom title bar with familiar Windows controls -->
      <Grid x:Name="TitleBar" Grid.Row="0" Height="34" Background="{StaticResource TitleBarBrush}">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBlock x:Name="TitleBarText" Grid.Column="0" Text="Daftar Harian" FontFamily="{StaticResource AppFont}" FontSize="12.5"
                   FontWeight="SemiBold" Foreground="{StaticResource TextSecondary}"
                   VerticalAlignment="Center" HorizontalAlignment="Left" Margin="14,0,0,0"/>
        <Button x:Name="CompactToggle" Grid.Column="1" Content="Ringkas" Style="{StaticResource SecondaryButton}"
                FontSize="11" Padding="9,4" Margin="0,0,10,0" Height="22" ToolTip="Beralih ke tampilan ringkas"/>
        <Button x:Name="MinBtn" Grid.Column="2" Content="&#xE921;" Style="{StaticResource WindowControlButton}" ToolTip="Minimalkan"/>
        <Button x:Name="MaxBtn" Grid.Column="3" Content="&#xE922;" Style="{StaticResource WindowControlButton}" ToolTip="Maksimalkan atau pulihkan"/>
        <Button x:Name="CloseBtn" Grid.Column="4" Content="&#xE8BB;" Style="{StaticResource WindowCloseButton}" ToolTip="Tutup"/>
      </Grid>

      <!-- Header banner -->
      <Border x:Name="HeaderBanner" Grid.Row="1" Background="{StaticResource HeaderGradient}" Margin="16,14,16,0" Padding="18,16" CornerRadius="12">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <StackPanel Grid.Column="0">
            <TextBlock Text="DAFTAR HARIAN" Foreground="White" FontSize="19" FontWeight="Bold" FontFamily="{StaticResource AppFont}"/>
            <TextBlock Text="Tersimpan otomatis untuk setiap tanggal" Foreground="#EAF3FF" FontSize="12.5" Margin="0,4,0,0" FontFamily="{StaticResource AppFont}"/>
          </StackPanel>
          <TextBlock x:Name="ProgressText" Grid.Column="1" Text="0/0" Foreground="White" FontSize="20" FontWeight="Bold"
                     FontFamily="{StaticResource AppFont}" VerticalAlignment="Center"/>
        </Grid>
      </Border>

      <!-- Body -->
      <Grid Grid.Row="2" Margin="16,14,16,16">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/> <!-- Navigation -->
          <RowDefinition Height="*"/>    <!-- Task list -->
          <RowDefinition Height="Auto"/> <!-- New task -->
          <RowDefinition Height="Auto"/> <!-- Bottom controls -->
        </Grid.RowDefinitions>

        <!-- Navigation -->
        <Grid x:Name="NavRow" Grid.Row="0" Margin="0,0,0,12">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <Button x:Name="PreviousButton" Grid.Column="0" Content="&#xE72B;" FontFamily="{StaticResource IconFont}" Style="{StaticResource RoundIconButton}"/>
          <DatePicker x:Name="DayPicker" Grid.Column="1" Margin="8,0" HorizontalContentAlignment="Center" FontFamily="{StaticResource AppFont}" FontSize="13.5" BorderThickness="0" Background="Transparent" Foreground="#1D1D1F"/>
          <Button x:Name="NextButton" Grid.Column="2" Content="&#xE72A;" FontFamily="{StaticResource IconFont}" Style="{StaticResource RoundIconButton}"/>
        </Grid>

        <!-- Task List -->
        <Border Grid.Row="1" BorderBrush="{StaticResource BorderBrush2}" BorderThickness="1" CornerRadius="12" Background="{StaticResource CardBrush}" Padding="6">
          <ScrollViewer VerticalScrollBarVisibility="Auto">
            <StackPanel x:Name="TaskPanel" Margin="4"/>
          </ScrollViewer>
        </Border>

        <!-- New Task Input -->
        <StackPanel x:Name="NewTaskRow" Grid.Row="2" Margin="0,14,0,0">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBox x:Name="NewTaskBox" Grid.Column="0" Height="38" Style="{StaticResource ModernTextBox}"
                     Foreground="#1D1D1F" Background="White"
                     VerticalContentAlignment="Center" ToolTip="Tulis tugas baru lalu tekan Enter"/>
            <Button x:Name="AddButton" Grid.Column="1" Content="&#xE710;" FontFamily="{StaticResource IconFont}" FontSize="15"
                    ToolTip="Tambah tugas" Style="{StaticResource ModernButton}" Width="38" Height="38" Padding="0" Margin="8,0,0,0"/>
          </Grid>
        </StackPanel>

        <!-- Bottom Controls -->
        <Grid x:Name="BottomRow" Grid.Row="3" Margin="0,14,0,0">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <StackPanel Grid.Column="0" Orientation="Vertical" VerticalAlignment="Center">
            <CheckBox x:Name="TopmostBox" Content="Selalu di atas" IsChecked="True" Style="{StaticResource OptionCheckBox}"/>
            <CheckBox x:Name="AutoStartBox" Content="Mulai saat Windows menyala" Margin="0,5,0,0" Style="{StaticResource OptionCheckBox}"/>
          </StackPanel>
          <Button x:Name="ClearButton" Grid.Column="1" Content="Bersihkan yang selesai" Style="{StaticResource SecondaryButton}" FontSize="12.5" Padding="10,7" VerticalAlignment="Center"/>
        </Grid>
      </Grid>
    </Grid>
  </Border>
</Window>
'@

# Load XAML and create window
$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$script:window = [Windows.Markup.XamlReader]::Load($reader)
$windowIconPath = Join-Path $scriptDir 'assets\app-icon.ico'
if (Test-Path -LiteralPath $windowIconPath) {
    try {
        $script:window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([System.Uri]::new($windowIconPath))
    } catch { }
}

# Find controls
$script:taskPanel     = $script:window.FindName('TaskPanel')
$script:dayPicker      = $script:window.FindName('DayPicker')
$script:newTaskBox     = $script:window.FindName('NewTaskBox')
$script:topmostBox     = $script:window.FindName('TopmostBox')
$script:autoStartBox   = $script:window.FindName('AutoStartBox')
$script:progressText   = $script:window.FindName('ProgressText')
$script:headerBanner   = $script:window.FindName('HeaderBanner')
$script:navRow         = $script:window.FindName('NavRow')
$script:newTaskRow     = $script:window.FindName('NewTaskRow')
$script:bottomRow      = $script:window.FindName('BottomRow')
$script:compactToggle  = $script:window.FindName('CompactToggle')
$script:titleBarText   = $script:window.FindName('TitleBarText')
$script:isCompact      = $false
$script:savedBounds    = $null

# ----- Title bar interactions -----
$script:window.FindName('TitleBar').Add_MouseLeftButtonDown({
    param($sender, $eventArgs)
    # Do not start a window drag when the pointer is on one of the window buttons.
    $element = $eventArgs.OriginalSource
    $isWindowControl = $false
    while ($null -ne $element) {
        if ($element -is [System.Windows.Controls.Button]) {
            $isWindowControl = $true
            break
        }
        if ($element -is [System.Windows.Media.Visual]) {
            $element = [System.Windows.Media.VisualTreeHelper]::GetParent($element)
        } else {
            break
        }
    }
    if (-not $isWindowControl -and $eventArgs.ButtonState -eq 'Pressed') {
        $script:window.DragMove()
    }
})
$script:window.FindName('CloseBtn').Add_Click({
    param($sender, $eventArgs)
    $script:window.Close()
})
$script:window.FindName('MinBtn').Add_Click({
    param($sender, $eventArgs)
    $script:window.WindowState = 'Minimized'
})
$script:window.FindName('MaxBtn').Add_Click({
    param($sender, $eventArgs)
    if ($script:window.WindowState -eq 'Maximized') {
        $script:window.WindowState = 'Normal'
    } else {
        $script:window.WindowState = 'Maximized'
    }
})

function Update-WindowTitle {
    $dateStr = $script:currentDate.ToString('dddd, d MMMM yyyy', [cultureinfo]::GetCultureInfo('id-ID'))
    $script:window.Title = "Daftar Harian - $dateStr"
    if ($null -ne $script:titleBarText) {
        $script:titleBarText.Text = "Daftar Harian - $dateStr"
    }
}

# Cat animation state
$script:catWindow  = $null
$script:catTimer   = $null
$script:catItems   = @()   # array of [pscustomobject]@{ Canvas; X; Speed; TaskText; Bubble }

function Close-CatOverlay {
    if ($null -ne $script:catTimer) {
        $script:catTimer.Stop()
        $script:catTimer = $null
    }
    if ($null -ne $script:catWindow) {
        $script:catWindow.Close()
        $script:catWindow = $null
    }
    $script:catItems = @()
    $script:singleCat = $null
}

function Show-CatOverlay {
    Close-CatOverlay

    $tasks = @(Get-DayTasks | Where-Object { -not $_.done })
    if ($tasks.Count -eq 0) { return }

    $screen  = [System.Windows.SystemParameters]::WorkArea
    $stripH  = 145
    $screenW = [int]$screen.Width
    $screenL = [int]$screen.Left
    $screenB = [int]($screen.Bottom - $stripH)
    # Keep the cats close to the bottom edge without going behind the taskbar.
    $floorY  = 38.0

    # Build transparent overlay window (ClipToBounds=False so bubbles never get clipped)
    $catXamlStr = '<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" ' +
                  'xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" ' +
                  'WindowStyle="None" AllowsTransparency="True" Background="Transparent" ' +
                  'Topmost="True" ShowInTaskbar="False" ' +
                  "Left=`"$screenL`" Top=`"$screenB`" Width=`"$screenW`" Height=`"$stripH`" " +
                  'IsHitTestVisible="True" Cursor="Hand">' +
                  "<Canvas x:Name=`"CatCanvas`" Width=`"$screenW`" Height=`"$stripH`" Background=`"Transparent`" ClipToBounds=`"False`"/>" +
                  '</Window>'

    $catReader = New-Object System.Xml.XmlNodeReader ([xml]$catXamlStr)
    $script:catWindow = [Windows.Markup.XamlReader]::Load($catReader)
    $catCanvas = $script:catWindow.FindName('CatCanvas')

    # Bundled cat image expressions; all assets stay inside the application folder.
    $catIconDir = Join-Path $scriptDir 'assets\cat-expressions-1'
    $catIconDir2 = Join-Path $scriptDir 'assets\cat-expressions-2'

    function Load-CatBmp([string]$filename) {
        $p = Join-Path $catIconDir $filename
        if (Test-Path -LiteralPath $p) {
            return New-Object System.Windows.Media.Imaging.BitmapImage([System.Uri]::new($p))
        }
        return $null
    }

    function Load-CatBmp2([string]$filename) {
        if (-not $catIconDir2) { return $null }
        $p = Join-Path $catIconDir2 $filename
        if (Test-Path -LiteralPath $p) {
            return New-Object System.Windows.Media.Imaging.BitmapImage([System.Uri]::new($p))
        }
        return $null
    }

    $bitmaps = @{
        'buka_mata' = Load-CatBmp  'buka mata.png'
        'merem'     = Load-CatBmp  'merem.png'
        'nguap'     = Load-CatBmp  'nguap.png'
        'tidur'     = Load-CatBmp  'tidur.png'
        'marah'     = Load-CatBmp  'marah.png'
        # Expressions from icon kucing 2
        'bingung'   = Load-CatBmp2 'Bingung.png'
        'cinta'     = Load-CatBmp2 'Cinta.png'
        'grogi'     = Load-CatBmp2 'Grogi.png'
        'malu'      = Load-CatBmp2 'Malu.png'
        'panik'     = Load-CatBmp2 'Panik.png'
        'penasaran' = Load-CatBmp2 'Penasaran.png'
        'sedih'     = Load-CatBmp2 'Sedih.png'
        'senang'    = Load-CatBmp2 'Senang.png'
        'terkejut'  = Load-CatBmp2 'Terkejut.png'
        'lelah'     = Load-CatBmp2 'lelah.png'
    }

    # Helper to safely get a bitmap (fallback to buka_mata if nil)
    function B([string]$k) { if ($bitmaps[$k]) { $bitmaps[$k] } else { $bitmaps['buka_mata'] } }

    # Rich animation sequence personalities — one per cat (cycles through)
    $allFaceSeqs = @(
        # Kucing 1: normal curious
        @((B 'buka_mata'), (B 'buka_mata'), (B 'merem'), (B 'penasaran'), (B 'buka_mata'), (B 'merem')),
        # Kucing 2: sleepy
        @((B 'buka_mata'), (B 'lelah'), (B 'merem'), (B 'tidur'), (B 'tidur'), (B 'merem')),
        # Kucing 3: happy excited
        @((B 'senang'), (B 'buka_mata'), (B 'senang'), (B 'cinta'), (B 'buka_mata'), (B 'senang')),
        # Kucing 4: nervous / shy
        @((B 'buka_mata'), (B 'grogi'), (B 'malu'), (B 'malu'), (B 'grogi'), (B 'buka_mata')),
        # Kucing 5: yawny
        @((B 'buka_mata'), (B 'nguap'), (B 'nguap'), (B 'merem'), (B 'buka_mata'), (B 'lelah')),
        # Kucing 6: curious & surprised
        @((B 'penasaran'), (B 'buka_mata'), (B 'terkejut'), (B 'bingung'), (B 'penasaran'), (B 'buka_mata')),
        # Kucing 7: sad & worried
        @((B 'buka_mata'), (B 'sedih'), (B 'panik'), (B 'sedih'), (B 'buka_mata'), (B 'merem')),
        # Kucing 8: grumpy
        @((B 'marah'), (B 'buka_mata'), (B 'marah'), (B 'bingung'), (B 'buka_mata'), (B 'merem')),
        # Kucing 9: lovestruck
        @((B 'cinta'), (B 'buka_mata'), (B 'cinta'), (B 'senang'), (B 'buka_mata'), (B 'malu')),
        # Kucing 10: panic mode
        @((B 'buka_mata'), (B 'terkejut'), (B 'panik'), (B 'panik'), (B 'terkejut'), (B 'buka_mata'))
    )

    # Vivid border colors for speech bubbles
    $bubbleColors = @('#0A84FF', '#FF9F43', '#FF3B30', '#34C759', '#AF52DE', '#FF2D55', '#5856D6')

    $script:catItems = @()
    $spacing = [int]($screen.Width / $tasks.Count)
    if ($spacing -lt 240) { $spacing = 240 }

    for ($i = 0; $i -lt $tasks.Count; $i++) {
        $taskText = [string]$tasks[$i].text
        if ($taskText.Length -gt 36) { $taskText = $taskText.Substring(0, 33) + '...' }

        $color   = $bubbleColors[$i % $bubbleColors.Count]
        $faceSeq = $allFaceSeqs[$i % $allFaceSeqs.Count]

        # Container: speech bubble -> pointer -> custom cat image
        $container = New-Object System.Windows.Controls.StackPanel
        $container.Orientation = 'Vertical'
        $container.HorizontalAlignment = 'Center'

        # Speech bubble: Pixel-art retro dialog box (100% matches pixel art cat)
        $bubbleBrush = [System.Windows.Media.SolidColorBrush][System.Windows.Media.ColorConverter]::ConvertFromString($color)

        $bubble = New-Object System.Windows.Controls.Border
        $bubble.CornerRadius = 0
        $bubble.Background = [System.Windows.Media.Brushes]::White
        $bubble.BorderBrush = $bubbleBrush
        $bubble.BorderThickness = 2.5
        $bubble.Padding = '10,5'
        $bubble.Margin = '0,0,0,0'

        # Classic 8-bit hard pixel shadow (Zero blur!)
        $shadow = New-Object System.Windows.Media.Effects.DropShadowEffect
        $shadow.Color = [System.Windows.Media.Colors]::Black
        $shadow.BlurRadius = 0
        $shadow.Opacity = 0.35
        $shadow.ShadowDepth = 3
        $shadow.Direction = 315
        $bubble.Effect = $shadow

        $bubbleTxt = New-Object System.Windows.Controls.TextBlock
        $bubbleTxt.Text = $taskText
        $bubbleTxt.FontFamily = New-Object System.Windows.Media.FontFamily('Cascadia Code, Lucida Console, Consolas, Courier New')
        $bubbleTxt.FontSize = 11.5
        $bubbleTxt.FontWeight = 'Bold'
        $bubbleTxt.Foreground = [System.Windows.Media.SolidColorBrush][System.Windows.Media.ColorConverter]::ConvertFromString('#1D1D1F')
        $bubbleTxt.TextWrapping = 'NoWrap'
        [System.Windows.Media.TextOptions]::SetTextFormattingMode($bubbleTxt, [System.Windows.Media.TextFormattingMode]::Display)
        [System.Windows.Media.TextOptions]::SetTextRenderingMode($bubbleTxt, [System.Windows.Media.TextRenderingMode]::Aliased)
        $bubble.Child = $bubbleTxt
        [void]$container.Children.Add($bubble)

        # Pixel Tail (stepped pixel arrow pointing down to cat)
        $tail = New-Object System.Windows.Controls.StackPanel
        $tail.Orientation = 'Vertical'
        $tail.HorizontalAlignment = 'Center'
        $tail.Margin = '0,0,0,2'

        $t1 = New-Object System.Windows.Shapes.Rectangle
        $t1.Width = 10; $t1.Height = 2.5; $t1.Fill = $bubbleBrush; $t1.HorizontalAlignment = 'Center'
        [void]$tail.Children.Add($t1)

        $t2 = New-Object System.Windows.Shapes.Rectangle
        $t2.Width = 6; $t2.Height = 2.5; $t2.Fill = $bubbleBrush; $t2.HorizontalAlignment = 'Center'
        [void]$tail.Children.Add($t2)

        $t3 = New-Object System.Windows.Shapes.Rectangle
        $t3.Width = 3; $t3.Height = 2.5; $t3.Fill = $bubbleBrush; $t3.HorizontalAlignment = 'Center'
        [void]$tail.Children.Add($t3)

        [void]$container.Children.Add($tail)

        # Cat Image: custom pixel art image from Pictures/icon kucing
        $faceImg = New-Object System.Windows.Controls.Image
        $faceImg.Source = $faceSeq[0]
        $faceImg.Width = 48
        $faceImg.Height = 48
        $faceImg.HorizontalAlignment = 'Center'
        [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($faceImg, [System.Windows.Media.BitmapScalingMode]::NearestNeighbor)

        # Pixel hard shadow for cat
        $faceShadow = New-Object System.Windows.Media.Effects.DropShadowEffect
        $faceShadow.Color = [System.Windows.Media.Colors]::Black
        $faceShadow.BlurRadius = 0
        $faceShadow.Opacity = 0.35
        $faceShadow.ShadowDepth = 2.5
        $faceShadow.Direction = 315
        $faceImg.Effect = $faceShadow
        [void]$container.Children.Add($faceImg)

        # Measure dimensions
        $container.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
        $container.Arrange([System.Windows.Rect]::new($container.DesiredSize))

        $startX = $screen.Width + ($i * $spacing)
        [System.Windows.Controls.Canvas]::SetLeft($container, $startX)
        [System.Windows.Controls.Canvas]::SetTop($container, $floorY)
        [void]$catCanvas.Children.Add($container)

        $speed    = 0.95 + ($i % 4) * 0.20
        $bobPhase = [double]($i * 55)

        $catObj = [pscustomobject]@{
            Container   = $container
            FaceImg     = $faceImg
            X           = [double]$startX
            CurrentY    = [double]$floorY
            Speed       = $speed
            Faces       = $faceSeq
            FaceTick    = 0
            FaceIdx     = 0
            BobPhase    = $bobPhase
            Width       = [double]($container.DesiredSize.Width + 24)
            IsDragging  = $false
            IsFalling   = $false
            HasMoved    = $false
            DownPos     = $null
            DragOffsetX = 0.0
            DragOffsetY = 0.0
            Bitmaps     = $bitmaps
        }

        $container.Tag = $catObj
        $container.Cursor = [System.Windows.Input.Cursors]::Hand

        # Drag event: Mouse down
        $container.Add_MouseLeftButtonDown({
            param($s, $e)
            $e.Handled = $true
            $cat = $s.Tag
            $cat.IsDragging = $false
            $cat.HasMoved   = $false
            $cat.IsFalling  = $false
            $pos = $e.GetPosition($catCanvas)
            $cat.DownPos = $pos

            $curTop = [System.Windows.Controls.Canvas]::GetTop($s)
            if ([double]::IsNaN($curTop)) { $curTop = $cat.CurrentY }
            $cat.DragOffsetX = $pos.X - $cat.X
            $cat.DragOffsetY = $pos.Y - $curTop
            [void]$s.CaptureMouse()
        })

        # Drag event: Mouse move
        $container.Add_MouseMove({
            param($s, $e)
            $cat = $s.Tag
            if ($null -ne $cat.DownPos) {
                $pos = $e.GetPosition($catCanvas)
                $dx = [Math]::Abs($pos.X - $cat.DownPos.X)
                $dy = [Math]::Abs($pos.Y - $cat.DownPos.Y)

                # Threshold 5px: distinguish click vs drag
                if ($dx -gt 5 -or $dy -gt 5) {
                    $cat.IsDragging = $true
                    $cat.HasMoved   = $true
                    $s.Cursor = [System.Windows.Input.Cursors]::SizeAll

                    # Expression changes to angry/surprised while being held in air!
                    if ($null -ne $cat.Bitmaps['marah']) {
                        $cat.FaceImg.Source = $cat.Bitmaps['marah']
                    }

                    $newX = $pos.X - $cat.DragOffsetX
                    $newY = $pos.Y - $cat.DragOffsetY
                    if ($newY -lt 0) { $newY = 0 }
                    $maxY = [double]($floorY + 15)
                    if ($newY -gt $maxY) { $newY = $maxY }

                    $cat.X = $newX
                    $cat.CurrentY = $newY
                    [System.Windows.Controls.Canvas]::SetLeft($cat.Container, $newX)
                    [System.Windows.Controls.Canvas]::SetTop($cat.Container, $newY)
                }
            }
        })

        # Drag event: Mouse up
        $container.Add_MouseLeftButtonUp({
            param($s, $e)
            $cat = $s.Tag
            $s.Cursor = [System.Windows.Input.Cursors]::Hand
            if ($s.IsMouseCaptured) {
                [void]$s.ReleaseMouseCapture()
            }
            $cat.DownPos = $null

            if ($cat.HasMoved) {
                # Finished drag: gravity fall back to floor level
                $cat.IsDragging = $false
                $cat.IsFalling  = $true
                $e.Handled = $true
            } else {
                # Simple click on cat: reopen task list!
                $cat.IsDragging = $false
                $e.Handled = $true
                Set-CompactMode $false
            }
        })

        $script:catItems += $catObj
    }

    # Hint text (pixel theme)
    $hintTb = New-Object System.Windows.Controls.TextBlock
    $hintTb.Text = 'Klik kucing untuk buka daftar | Tahan untuk geser'
    $hintTb.FontFamily = New-Object System.Windows.Media.FontFamily('Cascadia Code, Lucida Console, Consolas, Segoe UI')
    $hintTb.FontSize = 9.5
    $hintTb.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.Color]::FromArgb(150, 40, 40, 40))
    [System.Windows.Media.TextOptions]::SetTextRenderingMode($hintTb, [System.Windows.Media.TextRenderingMode]::Aliased)
    [System.Windows.Controls.Canvas]::SetRight($hintTb, 14)
    [System.Windows.Controls.Canvas]::SetBottom($hintTb, 3)
    [void]$catCanvas.Children.Add($hintTb)

    # DispatcherTimer ~25 fps animation
    $script:catTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:catTimer.Interval = [TimeSpan]::FromMilliseconds(40)
    $script:catTimer.Add_Tick({
        $respawnX = [System.Windows.SystemParameters]::WorkArea.Width + 60
        foreach ($item in $script:catItems) {
            # Don't auto-move while user is actively dragging
            if ($item.IsDragging) {
                continue
            }

            # Gravity fall if dropped above floor level
            if ($item.IsFalling) {
                $item.CurrentY += 6.0
                if ($item.CurrentY -ge $floorY) {
                    $item.CurrentY  = $floorY
                    $item.IsFalling = $false
                    $item.FaceImg.Source = $item.Faces[$item.FaceIdx]
                }
                [System.Windows.Controls.Canvas]::SetTop($item.Container, $item.CurrentY)
            } else {
                # Normal gentle bobbing at floor level
                $item.BobPhase += 4.5
                $bob = [Math]::Sin($item.BobPhase * [Math]::PI / 180.0) * 4.0
                [System.Windows.Controls.Canvas]::SetTop($item.Container, $floorY + $bob)
            }

            # Move left
            $item.X -= $item.Speed
            if (($item.X + $item.Width) -lt -20) { $item.X = $respawnX }
            [System.Windows.Controls.Canvas]::SetLeft($item.Container, $item.X)

            # Cycle face expressions every 14 ticks (~560ms)
            $item.FaceTick++
            if ($item.FaceTick -ge 14) {
                $item.FaceTick = 0
                $item.FaceIdx  = ($item.FaceIdx + 1) % $item.Faces.Count
                if (-not $item.IsFalling) {
                    $item.FaceImg.Source = $item.Faces[$item.FaceIdx]
                }
            }
        }
    })
    $script:catTimer.Start()

    # Click empty background -> restore main window
    $script:catWindow.Add_MouseLeftButtonDown({
        param($s, $e)
        Set-CompactMode $false
    })

    $script:catWindow.Show()
}

function Set-CompactMode([bool]$enabled) {
    $script:isCompact = $enabled
    $script:compactToggle.Content = if ($enabled) { 'Tampilan Penuh' } else { 'Ringkas' }
    $script:compactToggle.ToolTip = if ($enabled) { 'Kembali ke tampilan lengkap' } else { 'Beralih ke tampilan ringkas' }

    if ($enabled) {
        $script:savedBounds = [pscustomobject]@{
            Left   = $script:window.Left
            Top    = $script:window.Top
            Width  = $script:window.Width
            Height = $script:window.Height
        }
        # Move main window far off-screen (Hide() ends ShowDialog, so we park it instead)
        $script:window.Left   = -32000
        $script:window.Top    = -32000
        $script:window.Width  = 1
        $script:window.Height = 1
        Show-CatOverlay
    } else {
        Close-CatOverlay
        # Restore bounds first, then bring window back on-screen
        if ($null -ne $script:savedBounds) {
            $script:window.Width  = $script:savedBounds.Width
            $script:window.Height = $script:savedBounds.Height
            $script:window.Left   = $script:savedBounds.Left
            $script:window.Top    = $script:savedBounds.Top
        }
        # Restore visibility of all panels
        $script:headerBanner.Visibility = 'Visible'
        $script:navRow.Visibility       = 'Visible'
        $script:newTaskRow.Visibility   = 'Visible'
        $script:bottomRow.Visibility    = 'Visible'
        Refresh-Tasks
        $script:window.Activate()
    }
}

function Update-Progress {
    $tasks = Get-DayTasks
    $done = @($tasks | Where-Object { $_.done }).Count
    $script:progressText.Text = "$done/$($tasks.Count)"
}

function New-TaskContent([object]$task) {
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = [string]$task.text
    $tb.TextWrapping = 'Wrap'
    $tb.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI')
    if ($task.done) {
        $tb.Foreground = [System.Windows.Media.Brushes]::Gray
        $tb.TextDecorations = [System.Windows.TextDecorations]::Strikethrough
    } else {
        $tb.Foreground = [System.Windows.Media.Brushes]::Black
        $tb.TextDecorations = $null
    }
    return $tb
}

function Commit-InlineEdit([System.Windows.Controls.TextBox]$box) {
    $ctx = $box.Tag
    if ($null -eq $ctx -or $ctx.Done) { return }
    $ctx.Done = $true
    $val = $box.Text.Trim()
    if (-not [string]::IsNullOrWhiteSpace($val)) {
        $ctx.Task.text = $val
        Save-Data
    }
    Refresh-Tasks
}

function Cancel-InlineEdit([System.Windows.Controls.TextBox]$box) {
    $ctx = $box.Tag
    if ($null -eq $ctx -or $ctx.Done) { return }
    $ctx.Done = $true
    Refresh-Tasks
}

function Start-InlineEdit([object]$task, [System.Windows.Controls.Border]$container) {
    $editBox = New-Object System.Windows.Controls.TextBox
    $editBox.Text = [string]$task.text
    $editBox.Style = $script:window.FindResource('ModernTextBox')
    $editBox.Height = 32
    $editBox.Padding = '8,4'
    $editBox.FontSize = 13.5
    $editBox.VerticalContentAlignment = 'Center'
    $editBox.Margin = '0,0,6,0'
    $editBox.Tag = [pscustomobject]@{
        Task      = $task
        Container = $container
        Done      = $false
    }

    $editBox.Add_KeyDown({
        param($s, $e)
        if ($e.Key -eq 'Return') {
            $e.Handled = $true
            Commit-InlineEdit $s
        } elseif ($e.Key -eq 'Escape') {
            $e.Handled = $true
            Cancel-InlineEdit $s
        }
    })

    $editBox.Add_LostFocus({
        param($s, $e)
        Commit-InlineEdit $s
    })

    $container.Child = $editBox
    [void]$editBox.Focus()
    $editBox.SelectAll()
}

function Refresh-Tasks {
    $script:taskPanel.Children.Clear()
    $tasks = Get-DayTasks
    if ($tasks.Count -eq 0) {
        $emptyPanel = New-Object System.Windows.Controls.StackPanel
        $emptyPanel.HorizontalAlignment = 'Center'
        $emptyPanel.Margin = '0,40'
        $icon = New-Object System.Windows.Controls.TextBlock
        $icon.Text = [char]0xE9D5
        $icon.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe MDL2 Assets')
        $icon.FontSize = 34
        $icon.Foreground = [System.Windows.Media.Brushes]::Gainsboro
        $icon.HorizontalAlignment = 'Center'
        [void]$emptyPanel.Children.Add($icon)
        $empty = New-Object System.Windows.Controls.TextBlock
        $empty.Text = 'Belum ada tugas untuk hari ini'
        $empty.Foreground = [System.Windows.Media.Brushes]::Gray
        $empty.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI')
        $empty.FontSize = 13
        $empty.HorizontalAlignment = 'Center'
        $empty.Margin = '0,10,0,0'
        [void]$emptyPanel.Children.Add($empty)
        [void]$script:taskPanel.Children.Add($emptyPanel)
        Update-Progress
        return
    }

    $modernCheckStyle = $script:window.FindResource('ModernCheckBox')
    $rowIconBtnStyle  = $script:window.FindResource('RowIconButton')

    foreach ($task in $tasks) {
        $row = New-Object System.Windows.Controls.Border
        $row.CornerRadius = 8
        $row.Padding = '8,6'
        $row.Margin = '0,2'
        $row.Background = [System.Windows.Media.Brushes]::Transparent

        $grid = New-Object System.Windows.Controls.Grid

        $colCheck = New-Object System.Windows.Controls.ColumnDefinition
        $colCheck.Width = [System.Windows.GridLength]::Auto
        [void]$grid.ColumnDefinitions.Add($colCheck)

        $colText = New-Object System.Windows.Controls.ColumnDefinition
        $colText.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        [void]$grid.ColumnDefinitions.Add($colText)

        $colActions = New-Object System.Windows.Controls.ColumnDefinition
        $colActions.Width = [System.Windows.GridLength]::Auto
        [void]$grid.ColumnDefinitions.Add($colActions)

        # Checkbox
        $check = New-Object System.Windows.Controls.CheckBox
        $check.Style = $modernCheckStyle
        $check.IsChecked = [bool]$task.done
        $check.VerticalAlignment = 'Center'
        $check.Margin = '0,0,10,0'

        # Content container (holds TextBlock or inline TextBox)
        $contentHolder = New-Object System.Windows.Controls.Border
        $contentHolder.VerticalAlignment = 'Center'
        $contentHolder.Background = [System.Windows.Media.Brushes]::Transparent
        $contentHolder.Cursor = [System.Windows.Input.Cursors]::IBeam
        $contentHolder.ToolTip = 'Klik 2x atau klik ikon pensil untuk mengubah'
        $contentHolder.Child = New-TaskContent $task
        $contentHolder.Tag = [pscustomobject]@{ Task = $task; Container = $contentHolder }

        $check.Tag = [pscustomobject]@{
            Task          = $task
            ContentHolder = $contentHolder
        }

        $check.Add_Checked({
            param($sender, $eventArgs)
            $ctx = $sender.Tag
            $ctx.Task.done = $true
            $ctx.ContentHolder.Child = New-TaskContent $ctx.Task
            Save-Data
            Update-Progress
        })
        $check.Add_Unchecked({
            param($sender, $eventArgs)
            $ctx = $sender.Tag
            $ctx.Task.done = $false
            $ctx.ContentHolder.Child = New-TaskContent $ctx.Task
            Save-Data
            Update-Progress
        })

        [System.Windows.Controls.Grid]::SetColumn($check, 0)
        [void]$grid.Children.Add($check)

        [System.Windows.Controls.Grid]::SetColumn($contentHolder, 1)
        [void]$grid.Children.Add($contentHolder)

        # Action Panel
        $actionPanel = New-Object System.Windows.Controls.StackPanel
        $actionPanel.Orientation = 'Horizontal'
        [System.Windows.Controls.Grid]::SetColumn($actionPanel, 2)

        $edit = New-Object System.Windows.Controls.Button
        $edit.Content = [char]0xE70F
        $edit.ToolTip = 'Ubah tugas'
        $edit.Tag = [pscustomobject]@{ Task = $task; Container = $contentHolder }
        $edit.Style = $rowIconBtnStyle
        $edit.Add_Click({
            param($s, $e)
            Start-InlineEdit $s.Tag.Task $s.Tag.Container
        })

        $delete = New-Object System.Windows.Controls.Button
        $delete.Content = [char]0xE74D
        $delete.ToolTip = 'Hapus tugas'
        $delete.Tag = $task
        $delete.Style = $rowIconBtnStyle
        $delete.Add_Click({
            param($sender, $eventArgs)
            $taskToRemove = $sender.Tag
            $remaining = @((Get-DayTasks) | Where-Object { $_ -ne $taskToRemove })
            Set-DayTasks $remaining
            Save-Data
            Refresh-Tasks
        })

        # Double-click text to start inline editing
        $contentHolder.Add_MouseDown({
            param($s, $e)
            if ($e.ClickCount -ge 2 -and $e.LeftButton -eq 'Pressed') {
                $e.Handled = $true
                Start-InlineEdit $s.Tag.Task $s.Tag.Container
            }
        })

        [void]$actionPanel.Children.Add($edit)
        [void]$actionPanel.Children.Add($delete)

        if ($script:isCompact) {
            $actionPanel.Visibility = 'Collapsed'
        }

        [void]$grid.Children.Add($actionPanel)
        $row.Child = $grid
        [void]$script:taskPanel.Children.Add($row)
    }
    Update-Progress
}

function Add-Task {
    $text = $script:newTaskBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return }
    $tasks = Get-DayTasks
    $newTask = [pscustomobject]@{ text = $text; done = $false }
    Set-DayTasks (@($tasks) + $newTask)
    $script:newTaskBox.Clear()
    Save-Data
    Refresh-Tasks
    $script:newTaskBox.Focus()
}

# Initialise controls
$script:dayPicker.SelectedDate = $script:currentDate
$script:dayPicker.Add_SelectedDateChanged({
    param($sender, $eventArgs)
    if ($null -ne $sender.SelectedDate) {
        $script:currentDate = ([datetime]$sender.SelectedDate).Date
        if ($script:currentDate -eq (Get-Date).Date) {
            Invoke-AutoRollover
        }
        Update-WindowTitle
        Refresh-Tasks
    }
})
$script:window.FindName('PreviousButton').Add_Click({ $script:dayPicker.SelectedDate = $script:currentDate.AddDays(-1) })
$script:window.FindName('NextButton').Add_Click({ $script:dayPicker.SelectedDate = $script:currentDate.AddDays(1) })
$script:window.FindName('AddButton').Add_Click({ Add-Task })
$script:newTaskBox.Add_KeyDown({ param($sender, $eventArgs) if ($eventArgs.Key -eq 'Return') { Add-Task; $eventArgs.Handled = $true } })
$script:topmostBox.Add_Click({ $script:window.Topmost = [bool]$script:topmostBox.IsChecked })
if ($null -ne $script:autoStartBox) {
    $script:autoStartBox.IsChecked = Get-AutoStartStatus
    $script:autoStartBox.Add_Click({
        Set-AutoStart ([bool]$script:autoStartBox.IsChecked)
    })
}
$script:compactToggle.Add_Click({ Set-CompactMode (-not $script:isCompact) })
$script:window.FindName('ClearButton').Add_Click({
    $remaining = @((Get-DayTasks) | Where-Object { -not $_.done })
    Set-DayTasks $remaining
    Save-Data
    Refresh-Tasks
})
$script:window.Add_Closing({ Save-Data; Close-CatOverlay })

Invoke-AutoRollover
Update-WindowTitle
Refresh-Tasks
[void]$script:newTaskBox.Focus()
[void]$script:window.ShowDialog()
