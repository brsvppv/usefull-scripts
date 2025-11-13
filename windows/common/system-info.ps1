#
# system-info.ps1
# Displays comprehensive system information
#
# Usage: .\system-info.ps1

[CmdletBinding()]
param()

Write-Host "=== Windows System Information ===" -ForegroundColor Cyan
Write-Host ""

# Computer Information
Write-Host "Computer Name: " -NoNewline -ForegroundColor Yellow
Write-Host $env:COMPUTERNAME

Write-Host "User: " -NoNewline -ForegroundColor Yellow
Write-Host $env:USERNAME

# OS Information
$os = Get-CimInstance -ClassName Win32_OperatingSystem
Write-Host "`n--- Operating System ---" -ForegroundColor Green
Write-Host "OS: $($os.Caption)"
Write-Host "Version: $($os.Version)"
Write-Host "Build: $($os.BuildNumber)"
Write-Host "Architecture: $($os.OSArchitecture)"
Write-Host "Install Date: $($os.InstallDate)"
Write-Host "Last Boot: $($os.LastBootUpTime)"

# Hardware Information
$cs = Get-CimInstance -ClassName Win32_ComputerSystem
Write-Host "`n--- Hardware ---" -ForegroundColor Green
Write-Host "Manufacturer: $($cs.Manufacturer)"
Write-Host "Model: $($cs.Model)"
Write-Host "Total Physical Memory: $([math]::Round($cs.TotalPhysicalMemory/1GB, 2)) GB"

# Processor Information
$cpu = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
Write-Host "`n--- Processor ---" -ForegroundColor Green
Write-Host "Name: $($cpu.Name)"
Write-Host "Cores: $($cpu.NumberOfCores)"
Write-Host "Logical Processors: $($cpu.NumberOfLogicalProcessors)"
Write-Host "Max Clock Speed: $($cpu.MaxClockSpeed) MHz"

# Disk Information
Write-Host "`n--- Disks ---" -ForegroundColor Green
Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
    $freePct = [math]::Round(($_.FreeSpace / $_.Size) * 100, 2)
    Write-Host "Drive $($_.DeviceID)"
    Write-Host "  Size: $([math]::Round($_.Size/1GB, 2)) GB"
    Write-Host "  Free: $([math]::Round($_.FreeSpace/1GB, 2)) GB ($freePct%)"
}

# Network Adapters
Write-Host "`n--- Network Adapters ---" -ForegroundColor Green
Get-NetAdapter | Where-Object Status -eq 'Up' | ForEach-Object {
    Write-Host "$($_.Name) ($($_.InterfaceDescription))"
    Write-Host "  Status: $($_.Status)"
    Write-Host "  Speed: $($_.LinkSpeed)"
}

Write-Host "`n=== End of Report ===" -ForegroundColor Cyan
