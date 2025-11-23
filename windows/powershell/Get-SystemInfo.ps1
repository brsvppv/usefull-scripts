<#
.SYNOPSIS
    Retrieves system information as a structured object.

.DESCRIPTION
    Collects hardware and OS details (BIOS, CPU, Memory, Disk, OS) and returns them
    as a PSCustomObject. This allows for easy manipulation, filtering, and exporting
    (e.g., to JSON or CSV) compared to legacy Write-Host scripts.
    Uses CIM cmdlets for modern compatibility.

.EXAMPLE
    Get-SystemInfo
    Returns the system information object.

.EXAMPLE
    Get-SystemInfo | ConvertTo-Json
    Returns the system information in JSON format.
#>
function Get-SystemInfo {
    [CmdletBinding()]
    param()

    process {
        try {
            $computerSystem = Get-CimInstance CIM_ComputerSystem -ErrorAction Stop
            $computerBIOS   = Get-CimInstance CIM_BIOSElement -ErrorAction Stop
            $computerOS     = Get-CimInstance CIM_OperatingSystem -ErrorAction Stop
            $computerCPU    = Get-CimInstance CIM_Processor -ErrorAction Stop
            
            # Get all logical disks that are local hard disks (DriveType 3)
            $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType = 3" | Select-Object DeviceID, 
                @{N='SizeGB';E={[math]::Round($_.Size / 1GB, 2)}}, 
                @{N='FreeGB';E={[math]::Round($_.FreeSpace / 1GB, 2)}},
                @{N='PercentFree';E={[math]::Round(($_.FreeSpace / $_.Size) * 100, 1)}}

            $props = [ordered]@{
                Hostname        = $computerSystem.Name
                Manufacturer    = $computerSystem.Manufacturer
                Model           = $computerSystem.Model
                SerialNumber    = $computerBIOS.SerialNumber
                CPU             = $computerCPU.Name
                MemoryGB        = [math]::Round($computerSystem.TotalPhysicalMemory / 1GB, 2)
                OS              = $computerOS.Caption
                OSVersion       = $computerOS.Version
                ServicePack     = $computerOS.ServicePackMajorVersion
                LastBoot        = $computerOS.LastBootUpTime
                LoggedUser      = $computerSystem.UserName
                Disks           = $disks
            }

            [PSCustomObject]$props
        }
        catch {
            Write-Error "Failed to retrieve system info: $_"
        }
    }
}

# Export function if dot-sourced
if ($MyInvocation.InvocationName -eq '.') {
    Write-Verbose "Get-SystemInfo function loaded."
} else {
    # Run if executed directly
    Get-SystemInfo
}
