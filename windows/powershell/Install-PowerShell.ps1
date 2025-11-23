<#
.SYNOPSIS
    Installs the latest version of PowerShell 7 via MSI.

.DESCRIPTION
    Downloads and installs the latest PowerShell 7 release from GitHub.
    Checks for administrative privileges and self-elevates if necessary.
    Supports silent installation with standard arguments.

.PARAMETER Destination
    Download directory. Defaults to the user's Downloads folder.

.PARAMETER KeepInstaller
    If set, the MSI file will not be deleted after installation.

.EXAMPLE
    Install-PowerShell
    Installs the latest PowerShell 7.

.EXAMPLE
    Install-PowerShell -KeepInstaller
    Installs and keeps the MSI file.

.EXAMPLE
    # One-liner to run directly from GitHub
    irm https://raw.githubusercontent.com/brsvppv/usefull-scripts/master/windows/powershell/Install-PowerShell.ps1 | iex
#>
function Install-PowerShell {
    [CmdletBinding()]
    param (
        [string]$Destination,
        [switch]$KeepInstaller
    )

    process {
        # 1. Admin Check & Self-Elevation
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-Warning "Administrative privileges required. Elevating..."
            $newProcess = New-Object System.Diagnostics.ProcessStartInfo "PowerShell"
            $newProcess.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Definition)`""
            $newProcess.Verb = "runas"
            try {
                [System.Diagnostics.Process]::Start($newProcess)
                exit
            }
            catch {
                throw "Failed to elevate privileges. Please run as Administrator."
            }
        }

        # 2. Setup Paths
        if (-not $Destination) {
            # Robust way to get Downloads folder
            $Destination = "$env:USERPROFILE\Downloads"
            if (-not (Test-Path $Destination)) {
                $Destination = $env:TEMP
            }
        }

        # 3. Fetch Latest Release Info
        Write-Host "Fetching latest PowerShell release info..." -ForegroundColor Cyan
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        try {
            $latest = Invoke-RestMethod -Uri "https://api.github.com/repos/PowerShell/PowerShell/releases/latest" -ErrorAction Stop
        }
        catch {
            throw "Failed to query GitHub API: $_"
        }

        # 4. Find MSI Asset (x64)
        $msiAsset = $latest.assets | Where-Object { $_.name -match "win-x64.msi$" } | Select-Object -First 1
        
        if (-not $msiAsset) {
            throw "Could not find a win-x64.msi asset in the latest release ($($latest.tag_name))."
        }

        $downloadUrl = $msiAsset.browser_download_url
        $fileName = $msiAsset.name
        $localPath = Join-Path $Destination $fileName

        # 5. Download
        Write-Host "Downloading $fileName ($($latest.tag_name))..." -ForegroundColor Cyan
        try {
            # Use BitsTransfer for reliable download
            Start-BitsTransfer -Source $downloadUrl -Destination $localPath -Priority Foreground -ErrorAction Stop
        }
        catch {
            throw "Download failed: $_"
        }

        # 6. Install
        Write-Host "Installing PowerShell 7..." -ForegroundColor Cyan
        $msiArgs = "/i `"$localPath``" /qn ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1 USE_MU=1 ENABLE_MU=1 ADD_PATH=1"
        
        try {
            $process = Start-Process "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru
            
            if ($process.ExitCode -eq 0) {
                Write-Host "Installation completed successfully." -ForegroundColor Green
            } elseif ($process.ExitCode -eq 3010) {
                Write-Warning "Installation successful, but a reboot is required."
            } else {
                Write-Error "Installation failed with exit code $($process.ExitCode)."
            }
        }
        catch {
            throw "Failed to start installer: $_"
        }

        # 7. Cleanup
        if (-not $KeepInstaller) {
            Remove-Item $localPath -Force -ErrorAction SilentlyContinue
        }
    }
}

# Export function if dot-sourced
if ($MyInvocation.InvocationName -eq '.') {
    Write-Verbose "Install-PowerShell function loaded."
} else {
    # Run if executed directly
    Install-PowerShell @PSBoundParameters
}
