# Switch-SystemProxy
# Включение-выключение системного прокси одной кнопкой
#
# Roman Ermakov, EMG
# 
# история:
# 2026-02-02 v1.0 начальный релиз
# 2026-02-09 v1.1 список исключений заменён на адрес PAC-конфигурации (вводить в виде URL http://...)

Add-Type -AssemblyName PresentationFramework,WindowsBase,PresentationCore

# описание gui-интерфейса
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Proxy Toggle v1.1" Height="225" Width="330" WindowStartupLocation="CenterScreen" ResizeMode="NoResize">
  <Window.Resources>
    <Style TargetType="ToggleButton" x:Key="ProxyToggleStyle">
      <Setter Property="Width" Value="140"/>
      <Setter Property="Height" Value="40"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="Background" Value="Red"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToggleButton">
            <Border x:Name="Border" Background="{TemplateBinding Background}" CornerRadius="4" BorderThickness="0" Padding="4">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Border" Property="Opacity" Value="0.95"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Border" Property="Opacity" Value="0.9"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter Property="Background" Value="Red"/>
                <Setter Property="Foreground" Value="White"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="False">
                <Setter Property="Background" Value="Green"/>
                <Setter Property="Foreground" Value="White"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Border" Property="Opacity" Value="0.5"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Grid x:Name="GridRoot" Margin="10">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>

    <StackPanel Orientation="Horizontal" Grid.Row="0" Margin="0,0,0,8" VerticalAlignment="Center">
      <TextBlock Text="Системный прокси:" VerticalAlignment="Center" FontWeight="Bold" Margin="0,0,10,0"/>
      <TextBlock x:Name="StatusText" Text="Unknown" VerticalAlignment="Center" FontWeight="Bold"/>
    </StackPanel>

    <StackPanel Orientation="Horizontal" Grid.Row="1" HorizontalAlignment="Left" Margin="0,0,0,8">
      <ToggleButton x:Name="ToggleProxy" Style="{StaticResource ProxyToggleStyle}">Включить прокси</ToggleButton>
      <Button x:Name="RefreshBtn" Content="Обновить" Width="90" Height="40" Margin="10,0,0,0"/>
    </StackPanel>

    <Expander x:Name="ConfigExpander" Header="Автоконфигурация (PAC URL):" Grid.Row="2" IsExpanded="False" Margin="0,0,0,8" ExpandDirection="Down">
      <StackPanel>
        <TextBox x:Name="PacUrlText" Height="30" TextWrapping="Wrap" VerticalAlignment="Center" />
      </StackPanel>
    </Expander>

    <TextBlock Grid.Row="3" Text="Примечание: изменения применяются к системным настройкам WinINET/IE. Для некоторых приложений требуется перезапуск." TextWrapping="Wrap" Margin="0,4,0,0" FontSize="11"/>
  </Grid>
</Window>
"@

# загружаем XAML
$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# элементы UI
$toggle = $window.FindName("ToggleProxy")
$statusText = $window.FindName("StatusText")
$refreshBtn = $window.FindName("RefreshBtn")
$pacBox = $window.FindName("PacUrlText")
$expander = $window.FindName("ConfigExpander")
$grid = $window.FindName("GridRoot")
# куда писать в реестре
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"

function Get-ProxyState {
    try {
        $v = Get-ItemProperty -Path $regPath -Name ProxyEnable -ErrorAction Stop
        return ($v.ProxyEnable -eq 1)
    } catch {
        return $false
    }
}

function Get-AutoConfigUrl {
    try {
        $v = Get-ItemProperty -Path $regPath -Name AutoConfigURL -ErrorAction Stop
        return $v.AutoConfigURL
    } catch {
        return ""
    }
}

function Set-ProxyState([bool]$enable, [string]$pacUrl) {
    try {
        New-Item -Path $regPath -Force | Out-Null
        Set-ItemProperty -Path $regPath -Name ProxyEnable -Value ([int]$enable) -Type DWord

        if ($enable -and [string]::IsNullOrWhiteSpace($pacUrl) -eq $false) {
            Set-ItemProperty -Path $regPath -Name AutoConfigURL -Value $pacUrl -Type String
        } else {
            try { Remove-ItemProperty -Path $regPath -Name AutoConfigURL -ErrorAction SilentlyContinue } catch {}
        }

        $native = @"
using System;
using System.Runtime.InteropServices;
public class NativeMethods {
    [DllImport("wininet.dll", SetLastError=true)]
    public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int dwBufferLength);
}
"@
        Add-Type -TypeDefinition $native -ErrorAction SilentlyContinue
        [NativeMethods]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
        [NativeMethods]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null

        return $true
    } catch {
        return $false
    }
}

function Load-UI {
    $state = Get-ProxyState
    if ($state) {
        $statusText.Text = "Включён"
        # зелёный цвет для вкл
        $statusText.Foreground = [System.Windows.Media.Brushes]::Green
        $toggle.IsChecked = $true
        $toggle.Content = "Отключить прокси"
    } else {
        $statusText.Text = "Отключён"
        # красный цвет для выкл
        $statusText.Foreground = [System.Windows.Media.Brushes]::Red
        $toggle.IsChecked = $false
        $toggle.Content = "Включить прокси"
    }

    $pac = Get-AutoConfigUrl
    if ($pac -ne "") {
        $pacBox.Text = $pac
    } else {
        $pacBox.Text = "http://172.16.110.127/autoproxy/proxy.txt"
    }

    Adjust-WindowHeight
}

# добавляем высоты окна при разворачивании
function Adjust-WindowHeight {
    $base = 225
    if ($expander.IsExpanded) {
        $contentHeight = 80
        $window.Height = $base + $contentHeight
    } else {
        $window.Height = $base
    }
}

# обработка нажатия
$toggle.Add_Click({
    $newState = -not (Get-ProxyState)
    $pacUrl = $pacBox.Text.Trim()
    $ok = Set-ProxyState -enable:$newState -pacUrl $pacUrl
    if (-not $ok) {
        [System.Windows.MessageBox]::Show("Не удалось изменить состояние прокси. Попробуйте запустить PowerShell от имени администратора.", "Ошибка")
    }
    Load-UI
})

$refreshBtn.Add_Click({
    Load-UI
})

# при потере фокуса созраняем адрес PAC
$pacBox.Add_LostFocus({
    $text = $pacBox.Text.Trim()
    try {
        if ($text -ne "") {
            New-Item -Path $regPath -Force | Out-Null
            Set-ItemProperty -Path $regPath -Name AutoConfigURL -Value $text -Type String
        } else {
            Remove-ItemProperty -Path $regPath -Name AutoConfigURL -ErrorAction SilentlyContinue
        }
        $native = @"
using System;
using System.Runtime.InteropServices;
public class NativeMethods {
    [DllImport("wininet.dll", SetLastError=true)]
    public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int dwBufferLength);
}
"@
        Add-Type -TypeDefinition $native -ErrorAction SilentlyContinue
        [NativeMethods]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
        [NativeMethods]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
    } catch {}
})

# подписка на разворачивание/сворачивание
$expander.Add_Expanded({ Adjust-WindowHeight })
$expander.Add_Collapsed({ Adjust-WindowHeight })

# закрытие окна по Esc
$window.Add_KeyDown({
    param($s,$e)
    try {
        if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
            $window.Close()
        }
    } catch {}
})

# перехватим PreviewKeyDown у корневого Grid на случай фокуса вложенных контролов
$grid.Add_PreviewKeyDown({
    param($s,$e)
    try {
        if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
            $window.Close()
        }
    } catch {}
})

# фокус на окно при запуске
$window.Add_SourceInitialized({
    $window.Focus() | Out-Null
})

# пошло-поехали
Load-UI
$window.ShowDialog() | Out-Null
