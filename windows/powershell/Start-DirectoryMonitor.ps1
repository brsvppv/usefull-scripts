[void][System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
[void][System.Reflection.Assembly]::LoadWithPartialName('presentationframework')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName PresentationCore, PresentationFramework

[xml]$XAML = @"
<Window
xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
        xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"

        Title="Directory Monitor" Height="490" Width="650" ResizeMode="CanResize" WindowStartupLocation="CenterScreen" ShowInTaskbar="True">
            <Window.Resources>
                    <LinearGradientBrush x:Key="CheckedOrange" StartPoint="0,0" EndPoint="0,1">
                        <GradientStop Color="#FFCA6A13" Offset="0" />
                        <GradientStop Color="#FFF67D0C" Offset="0.2" />
                        <GradientStop Color="#FFFE7F0C" Offset="0.2" />
                        <GradientStop Color="#FFFA8E12" Offset="0.5" />
                        <GradientStop Color="#FFFF981D" Offset="0.5" />
                        <GradientStop Color="#FFFCBC5A" Offset="1" />
                    </LinearGradientBrush>
                    <SolidColorBrush x:Key="CheckedOrangeBorder" Color="#FFFF700E" />

                    <SolidColorBrush x:Key="NotCheckedGreen" Color="DarkGreen" />
                    <Style x:Key="OrangeSwitchStyle" TargetType="{x:Type CheckBox}">
                        <Setter Property="Foreground" Value="{DynamicResource {x:Static SystemColors.WindowTextBrushKey}}" />
                        <Setter Property="Background" Value="{DynamicResource {x:Static SystemColors.WindowBrushKey}}" />
                        <Setter Property="Template">
                            <Setter.Value>
                                <ControlTemplate TargetType="{x:Type CheckBox}">
                                    <ControlTemplate.Resources>
                                        <Storyboard x:Key="OnChecking">
                                            <DoubleAnimationUsingKeyFrames BeginTime="00:00:00" Storyboard.TargetName="slider" Storyboard.TargetProperty="(UIElement.RenderTransform).(TransformGroup.Children)[3].(TranslateTransform.X)">
                                                <SplineDoubleKeyFrame KeyTime="00:00:00.1000000" Value="50" />
                                            </DoubleAnimationUsingKeyFrames>
                                        </Storyboard>
                                        <Storyboard x:Key="OnUnchecking">
                                            <DoubleAnimationUsingKeyFrames BeginTime="00:00:00" Storyboard.TargetName="slider" Storyboard.TargetProperty="(UIElement.RenderTransform).(TransformGroup.Children)[3].(TranslateTransform.X)">
                                                <SplineDoubleKeyFrame KeyTime="00:00:00.1000000" Value="0" />
                                            </DoubleAnimationUsingKeyFrames>
                                        </Storyboard>
                                    </ControlTemplate.Resources>
                                    <DockPanel x:Name="dockPanel">
                                        <ContentPresenter SnapsToDevicePixels="{TemplateBinding SnapsToDevicePixels}" Content="{TemplateBinding Content}" ContentStringFormat="{TemplateBinding ContentStringFormat}" ContentTemplate="{TemplateBinding ContentTemplate}" RecognizesAccessKey="True" VerticalAlignment="Center" />
                                        <Grid>
                                            <Border x:Name="BackgroundBorder" BorderBrush="#FF939393" BorderThickness="1" CornerRadius="3" Height="21" Width="94">
                                                <Border.Background>
                                                    <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                                                        <GradientStop Color="#FFB5B5B5" Offset="0" />
                                                        <GradientStop Color="#FFDEDEDE" Offset="0.1" />
                                                        <GradientStop Color="#FFEEEEEE" Offset="0.5" />
                                                        <GradientStop Color="#FFFAFAFA" Offset="0.5" />
                                                        <GradientStop Color="#FFFEFEFE" Offset="1" />
                                                    </LinearGradientBrush>
                                                </Border.Background>
                                                <Grid>
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition />
                                                        <ColumnDefinition />
                                                    </Grid.ColumnDefinitions>
                                                    <Ellipse x:Name="Off" Width="14" Height="14" Stroke="#FF7A7A7A" StrokeThickness="2" Grid.Column="1" HorizontalAlignment="Center" VerticalAlignment="Center" />
                                                    <Line x:Name="On" X1="0" Y1="0" X2="0" Y2="14" Stroke="#FF7A7A7A" StrokeThickness="2" Grid.Column="0" HorizontalAlignment="Center" VerticalAlignment="Center" />
                                                </Grid>
                                            </Border>
                                            <Border BorderBrush="#FF939393" HorizontalAlignment="Left" x:Name="slider" Width="44" Height="21" BorderThickness="1" CornerRadius="3" RenderTransformOrigin="0.5,0.5" Margin="0">
                                                <Border.RenderTransform>
                                                    <TransformGroup>
                                                        <ScaleTransform ScaleX="1" ScaleY="1" />
                                                        <SkewTransform AngleX="0" AngleY="0" />
                                                        <RotateTransform Angle="0" />
                                                        <TranslateTransform X="0" Y="0" />
                                                    </TransformGroup>
                                                </Border.RenderTransform>
                                                <Border.Background>
                                                    <LinearGradientBrush EndPoint="0,1" StartPoint="0,0">
                                                        <GradientStop Color="#FFF0F0F0" Offset="0" />
                                                        <GradientStop Color="#FFCDCDCD" Offset="0.1" />
                                                        <GradientStop Color="#FFFBFBFB" Offset="1" />
                                                    </LinearGradientBrush>
                                                </Border.Background>
                                            </Border>
                                        </Grid>
                                    </DockPanel>
                                    <ControlTemplate.Triggers>
                                        <Trigger Property="IsChecked" Value="True">
                                            <Trigger.ExitActions>
                                                <BeginStoryboard Storyboard="{StaticResource OnUnchecking}" x:Name="OnUnchecking_BeginStoryboard" />
                                            </Trigger.ExitActions>
                                            <Trigger.EnterActions>
                                                <BeginStoryboard Storyboard="{StaticResource OnChecking}" x:Name="OnChecking_BeginStoryboard" />
                                            </Trigger.EnterActions>
                                            <Setter TargetName="On" Property="Stroke" Value="White" />
                                            <Setter TargetName="Off" Property="Stroke" Value="White" />
                                            <!-- Change Orange or Blue color here -->
                                            <Setter TargetName="BackgroundBorder" Property="Background" Value="{StaticResource CheckedOrange}" />
                                            <Setter TargetName="BackgroundBorder" Property="BorderBrush" Value="{StaticResource CheckedOrangeBorder}" />
                                        </Trigger>
                                        <Trigger Property="IsEnabled" Value="False">
                                            <!-- ToDo: Add Style for Isenabled == False -->
                                        </Trigger>
                                    </ControlTemplate.Triggers>
                                </ControlTemplate>
                            </Setter.Value>
                        </Setter>
                    </Style>
                </Window.Resources>
        <Grid Margin="1,1,1,1">
        
        <ListBox Name="ListBox_Monitor" Margin="105,2,2,35" IsEnabled="True"/>

            <StackPanel HorizontalAlignment="Left" Width="110">
            <Label Name="LBL_REGEVNT" Content=" Available Triggers"/>
                <CheckBox Name="CHB_Created" Content="Created"/>
                <CheckBox Name="CHB_Deleted" Content="Deleted"/>
                <CheckBox Name="CHB_Renamed" Content="Renamed"/>
                <CheckBox Name="CHB_Changed" Content="Changed"/>
                <Separator Height="4" Width="110" Margin="-10,0,0,0" />
                <Label Name="LBL_REGACTION" Content=" Available Actions"/>
  
                <Label Name="LBL_INFO" Content="INFO"/>
                
            </StackPanel>

            <Label Name="LBL_CurrTime" Content="" HorizontalAlignment="Left" Margin="5,0,353,8" VerticalAlignment="Bottom"/>
            <Label Name="LBL_DirPath" Content="Directory To Monitor" Margin="105,0,353,8" VerticalAlignment="Bottom"/>
            
            <TextBox Name="TXT_DirPath" Text="Select Directory To Monitor" Height="20" Margin="295,0,34,9" VerticalAlignment="Bottom" FontSize="11" IsReadOnly="true"/>
            <CheckBox Name="CHB_MailNotify" HorizontalAlignment="Left" Style="{DynamicResource OrangeSwitchStyle}" Margin="5,200,0,0" Height="21" VerticalAlignment="Top" Width="94" />
            <CheckBox Name="CHB_LogFile" HorizontalAlignment="Left" Style="{DynamicResource OrangeSwitchStyle}" Margin="5,250,0,0" Height="21" VerticalAlignment="Top" Width="94" />
            <CheckBox Name="chk_Rbutton3" HorizontalAlignment="Left" Style="{DynamicResource OrangeSwitchStyle}" Margin="5,300,0,0" Height="21" VerticalAlignment="Top" Width="94" />
            <CheckBox Name="chk_Rbutton4" HorizontalAlignment="Left" Style="{DynamicResource OrangeSwitchStyle}" Margin="5,350,0,0" Height="21" VerticalAlignment="Top" Width="94" />
            
            <Button Name="BTN_SelectDirectory" Content="..." Margin="0,0,9,9" VerticalAlignment="Bottom" Height="20" RenderTransformOrigin="0.933,0.42" HorizontalAlignment="Right" Width="27" />

            </Grid>
    </Window>
"@

# Read XAML
$reader = New-Object System.Xml.XmlNodeReader $XAML.DocumentElement
try { $DirectoryMonitor = [Windows.Markup.XamlReader]::Load($reader) }
catch { Write-Host "Unable to load Windows.Markup.XamlReader"; exit }

# Store Form Objects In PowerShell
$XAML.SelectNodes("//*[@Name]") | ForEach-Object { Set-Variable -Name ($_.Name) -Value $DirectoryMonitor.FindName($_.Name) }
$timer = New-Object System.Windows.Forms.Timer

$timer_Tick = {
    $LBL_CurrTime.Content = "$([string]::Format("{0:d2}:{1:d2}:{2:d2}", (Get-Date).Hour, (Get-Date).Minute, (Get-Date).Second))"
}

$timer.Enabled = $True
$timer.Interval = 1000
$timer.add_Tick($timer_Tick)

$OFS = "`r`n"
$LogFilePath = $env:LOCALAPPDATA
$DirMonName = "DirectoryMonitor"
$MonitorLog = "DirMonHistory.log"
$DirMonFullPath = Join-Path $LogFilePath -ChildPath $DirMonName 
$LogFilePath = Join-Path $DirMonFullPath -ChildPath $MonitorLog
$LogStartDate = Get-Date -UFormat "%d.%m.%Y"
$LogStartTime = Get-Date -UFormat "%H:%M"
$HeaderLog = 'Directory Monitoring Path ' + $TXT_DirPath.Text + ' Creation Date: ' + $LogStartDate + ';' + $LogStartTime
$ChangeTypes = [System.IO.WatcherChangeTypes]::Created, [System.IO.WatcherChangeTypes]::Deleted, [System.IO.WatcherChangeTypes]::Renamed, [System.IO.WatcherChangeTypes]::Deleted

$DirectoryMonitor.Add_Loaded({
    DisableCHB
    VerifyDirectory
})

Function CreateLog {
    if (!(Test-Path "$DirMonFullPath")) {
        New-Item -Path "$DirMonFullPath" -ItemType Directory -Force | Out-Null
        New-Item -ItemType File -Path $DirMonFullPath -Name $MonitorLog -Value $HeaderLog | Out-Null
    }
    else {
        $BoolVerifyLog = [System.IO.File]::Exists("$DirMonFullPath\$MonitorLog")
        if ($BoolVerifyLog -eq $false) {
            New-Item -ItemType File -Path $DirMonFullPath -Name $MonitorLog -Value $HeaderLog | Out-Null
        }
        else {
            $File = "$DirMonFullPath\$MonitorLog"
            $SetDate = Get-Date -UFormat "%y%m%dT%H%M%S"
            Write-Host $File $SetDate
            Rename-Item -Path $File -NewName "$DirMonFullPath\$SetDate-$MonitorLog"
            New-Item -ItemType File -Path $DirMonFullPath -Name $MonitorLog -Value $HeaderLog | Out-Null
        }
    }
}

Function VerifyDirectory {
    $BoolVerifyDirectory = [System.IO.Directory]::Exists($TXT_DirPath.Text)
    if ($BoolVerifyDirectory -eq $false) {
        [System.Windows.MessageBox]::Show("You Need To Select Target Directory To Monitor", 'Warning', 'OK', 'Information')
        SelectDirectory
    }
    else {
        [System.Windows.MessageBox]::Show("Target Directory Loaded Successfully", 'Info', 'OK', 'Information')
    }
}

Function DisableCHB {
    $CHB_Created.IsEnabled = $false
    $CHB_Created.Foreground = "Gray"
    $CHB_Deleted.IsEnabled = $false
    $CHB_Deleted.Foreground = "Gray"
    $CHB_Changed.IsEnabled = $false
    $CHB_Changed.Foreground = "Gray"
    $CHB_Renamed.IsEnabled = $false
    $CHB_Renamed.Foreground = "Gray"
}

Function EnableCHB {
    $CHB_Created.IsEnabled = $true
    $CHB_Created.Foreground = "Green"
    $CHB_Deleted.IsEnabled = $true
    $CHB_Deleted.Foreground = "Green"
    $CHB_Changed.IsEnabled = $true
    $CHB_Changed.Foreground = "Green"
    $CHB_Renamed.IsEnabled = $true
    $CHB_Renamed.Foreground = "Green"
}

$FileSystemWatcher = New-Object System.IO.FileSystemWatcher 
$FileSystemWatcher.Path = "C:\"
$FileSystemWatcher.Filter = "*.*"
$FileSystemWatcher.IncludeSubdirectories = $true
$FileSystemWatcher.EnableRaisingEvents = $true  
$FileSystemWatcher.NotifyFilter = [System.IO.WatcherChangeTypes]::Created, [System.IO.WatcherChangeTypes]::Deleted

$ActionOnCreate = {
    $FullPath = $Event.SourceEventArgs.FullPath
    $changeType = $Event.SourceEventArgs.ChangeType
    $Name = $Event.SourceEventArgs.Name
    $TimeStamp = $Event.TimeGenerated
    $Object = "File $Name was $changeType in $FullPath at $TimeStamp"
    $ListBox_Monitor.Items.Add($Object)
    Add-Content $DirMonFullPath\$MonitorLog "$OFS $Object" -Force  
}
$ActionOnChange = { 
    $FullPath = $Event.SourceEventArgs.FullPath
    $changeType = $Event.SourceEventArgs.ChangeType
    $Name = $Event.SourceEventArgs.Name
    $LastWrite =  $Event.SourceEventArgs.LastWrite
    $TimeStamp = $Event.TimeGenerated
    $Object = "File $Name was $changeType at $TimeStamp, Location: $FullPath, Previous Location: $LastWrite"
    $ListBox_Monitor.Items.Add($Object)
    Add-Content $DirMonFullPath\$MonitorLog "$OFS $Object" -Force  
}
$ActionOnRename = {
    $FullPath = $Event.SourceEventArgs.FullPath
    $changeType = $Event.SourceEventArgs.ChangeType
    $OldName = $Event.SourceEventArgs.OldName
    $Name = $Event.SourceEventArgs.Name
    $TimeStamp = $Event.TimeGenerated
    $Object = "File $OldName has been $changeType to $Name at $TimeStamp, Location: $FullPath"
    $ListBox_Monitor.Items.Add($Object)
    Add-Content $DirMonFullPath\$MonitorLog "$OFS $Object" -Force  
}
$ActionOnDelete = {
    $FullPath = $Event.SourceEventArgs.FullPath
    $changeType = $Event.SourceEventArgs.ChangeType
    $Name = $Event.SourceEventArgs.Name
    $TimeStamp = $Event.TimeGenerated
    $Object = "File $Name has been $changeType from Location: $FullPath at $TimeStamp" 
    $ListBox_Monitor.Items.Add($Object)
    Add-Content $DirMonFullPath\$MonitorLog "$OFS $Object" -Force  
}

function SelectDirectory {
    $browse = New-Object System.Windows.Forms.FolderBrowserDialog
    $browse.SelectedPath = "C:\"
    $browse.ShowNewFolderButton = $true
    $browse.Description = "Select a directory"
    $loop = $true
    while ($loop) {
        if ($browse.ShowDialog() -eq "OK") {
            $loop = $false
            $TXT_DirPath.Text = $browse.SelectedPath
            $browse.Dispose()
        }
        else {
            $res = [System.Windows.Forms.MessageBox]::Show("No Directory Selected. Try Again?", "Select a location", [System.Windows.Forms.MessageBoxButtons]::YesNo)
            if ($res -eq "No") {
                return
            }
        }
    }
}

$BTN_SelectDirectory.Add_Click({
    SelectDirectory
})

$TXT_DirPath.Add_TextChanged({
    $FileSystemWatcher.Path = $TXT_DirPath.Text
    EnableCHB
})

$CHB_Created.Add_Checked({
    Register-objectEvent $FileSystemWatcher -EventName Created -SourceIdentifier MonitorCreated -Action $ActionOnCreate
})
$CHB_Created.Add_UnChecked({
    Get-EventSubscriber -SourceIdentifier 'MonitorCreated' | Unregister-Event
})  
$CHB_Deleted.Add_Checked({
    Register-objectEvent $FileSystemWatcher -EventName Deleted -SourceIdentifier MonitorDeleted -Action $ActionOnDelete
})
$CHB_Deleted.Add_UnChecked({
    Get-EventSubscriber -SourceIdentifier 'MonitorDeleted' | Unregister-Event
})  
$CHB_Changed.Add_Checked({
    Register-objectEvent $FileSystemWatcher -EventName Changed -SourceIdentifier MonitorChanged -Action $ActionOnChange
})
$CHB_Changed.Add_UnChecked({
    Get-EventSubscriber -SourceIdentifier 'MonitorChanged' | Unregister-Event
}) 
$CHB_Renamed.Add_Checked({
    Register-objectEvent $FileSystemWatcher -EventName Renamed -SourceIdentifier MonitorRenamed -Action $ActionOnRename
})
$CHB_Renamed.Add_UnChecked({
    Get-EventSubscriber -SourceIdentifier 'MonitorRenamed' | Unregister-Event
})

$CHB_LogFile.Add_Checked({
    #CreateLog
})
$CHB_LogFile.Add_UnChecked({
    # Optionally handle log file uncheck
})  

$CHB_MailNotify.Add_Checked({
    # Optionally handle mail notify check
})
$CHB_MailNotify.Add_UnChecked({
    # Optionally handle mail notify uncheck
})  

$DirectoryMonitor.Add_Closing({
    Get-EventSubscriber | Unregister-Event
    $FileSystemWatcher.Dispose()
})

$DirectoryMonitor.ShowDialog() | Out-Null