<#
.SYNOPSIS
    Automated, safe, extensible Windows disk & clutter cleanup.

.DESCRIPTION
    Modern rework of legacy cleanup script. Provides modular, parameter-driven
    cleanup with support for: DryRun / -WhatIf, retention windows, optional
    aggressive modes, size reporting, JSON log output, and safe exclusion rules.
    Uses CIM instead of deprecated WMI cmdlets and avoids risky deletions
    (driver folders, OEM payloads) unless explicitly requested.

.FEATURES
    • Supports -WhatIf and -Confirm (ShouldProcess pattern)
    • -DryRun (alias of -WhatIf for convenience)
    • Per-area enable/disable (e.g. -SkipPrefetch)
    • Retention control (-DaysToKeep)
    • Optional -Aggressive switch (enables extended targets)
    • Consolidated size accounting & summary table
    • JSON log file + human readable transcript
    • Exclusion list & safety guards
    • Functions easily reusable in remote jobs / scheduled tasks

.EXAMPLE
    PS> .\Start-Cleanup.ps1 -DaysToKeep 5 -Aggressive -Verbose -DryRun
    Shows what would be removed (no changes) with aggressive set enabled.

.EXAMPLE
    PS> Start-Cleanup -LogPath C:\Logs\daily-clean.json -SkipRecycleBin -Confirm:$false
    Runs full cleanup without recycling bin purge and auto-confirms operations.

.EXAMPLE
    # Dry run directly from GitHub (no changes made)
    PS> irm https://raw.githubusercontent.com/brsvppv/usefull-scripts/master/windows/powershell/Start-SystemCleanup.ps1 | iex
    PS> Start-Cleanup -DryRun -Verbose

.EXAMPLE
    # One-liner: download & execute with JSON log to C:\Logs
    PS> irm https://raw.githubusercontent.com/brsvppv/usefull-scripts/master/windows/powershell/Start-SystemCleanup.ps1 | iex; \
        Start-Cleanup -LogPath C:\Logs\Cleanup-$(Get-Date -Format yyyyMMdd-HHmmss).json -Confirm:$false

.NOTES
    Tested on PowerShell 5.1 & 7.x. Requires administrative privileges for
    system areas (SoftwareDistribution, Windows temp, etc.). Always start with
    -DryRun or -WhatIf in new environments.

.OUTPUTS
    Human readable console + JSON summary (freed bytes per category, errors).
#>
function Start-Cleanup {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter()]
        [ValidateRange(0, 3650)]
        [int]$DaysToKeep = 7,
        
        [Parameter()]
        [ValidateScript({
            $dir = Split-Path -Parent $_
            if (-not (Test-Path $dir)) { throw "Log directory does not exist: $dir" }
            if (-not (Test-Path $dir -PathType Container)) { throw "Log path parent is not a directory: $dir" }
            $true
        })]
        [string]$LogPath = (Join-Path $env:TEMP "Cleanup-$(Get-Date -Format yyyyMMdd-HHmmss-fff).json"),
        
        [Parameter()][switch]$Aggressive,
        [Parameter()][switch]$DryRun,              # Convenience alias; maps to -WhatIf
        [Parameter()][switch]$SkipRecycleBin,
        [Parameter()][switch]$SkipSoftwareDistribution,
        [Parameter()][switch]$SkipPrefetch,
        [Parameter()][switch]$SkipIISLogs,
        [Parameter()][switch]$SkipUserTemps,
        [Parameter()][switch]$RunCleanmgr,         # Run Windows Disk Cleanup tool
        
        [Parameter()]
        [ValidateScript({
            foreach ($p in $_) {
                if (-not [System.IO.Path]::IsPathRooted($p)) {
                    throw "ExtraPaths must be absolute paths. Invalid: $p"
                }
                
                # Reject UNC/network paths
                if ($p -match '^\\\\\\\\') {
                    throw "Network paths (UNC) are not supported in ExtraPaths: $p"
                }
                
                # Normalize path for safety checks
                $normalized = $p.TrimEnd('\\').ToLower()
                
                # CRITICAL: Block dangerous system paths (exact + subdirectory match)
                $dangerousPaths = @(
                    'c:\windows\system32',
                    'c:\windows\syswow64',
                    'c:\windows\winsxs',
                    'c:\windows\boot',
                    'c:\windows\system',
                    'c:\program files\windowsapps',
                    'c:\program files\windows defender',
                    'c:\program files\windows nt',
                    'c:\programdata\microsoft\windows\start menu'
                )
                
                foreach ($danger in $dangerousPaths) {
                    if ($normalized -eq $danger -or $normalized.StartsWith("$danger\")) {
                        throw "BLOCKED: Cannot clean critical Windows system path: $p"
                    }
                }
                
                # CRITICAL: Block root directories entirely
                $rootsBlocked = @('c:\', 'c:\windows', 'c:\program files', 'c:\program files (x86)', 'c:\programdata', 'c:\users')
                if ($rootsBlocked -contains $normalized) {
                    throw "BLOCKED: Cannot clean root directory: $p (too dangerous)"
                }
                
                # WARN: Paths that are risky but might be intentional
                $riskyPatterns = @(
                    '^c:\\windows\\',
                    '^c:\\program files\\',
                    '^c:\\program files \(x86\)\\',
                    '^c:\\programdata\\'
                )
                
                $isRisky = $false
                foreach ($pattern in $riskyPatterns) {
                    if ($normalized -match $pattern) {
                        $isRisky = $true
                        break
                    }
                }
                
                if ($isRisky) {
                    # Allow but warn - script will prompt due to ConfirmImpact='Medium'
                    Write-Warning "CAUTION: Cleaning system area: $p - This path will require confirmation"
                }
            }
            $true
        })]
        [string[]]$ExtraPaths,        # Additional custom paths to purge
        
        [Parameter()][string[]]$ExcludePatterns = @('*.md', '*.txt'), # Safe defaults
        [Parameter()][switch]$JsonPretty,
        [Parameter()][switch]$NoTranscript
    )

    if ($DryRun) { $PSCmdlet.WhatIfPreference = $true }

    # Pre-flight validation
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Start-Cleanup must be run from an elevated (Administrator) PowerShell session."
    }

    $minSupportedMajor = 5
    if ($PSVersionTable.PSVersion.Major -lt $minSupportedMajor) {
        throw "PowerShell $minSupportedMajor or later is required. Current version: $($PSVersionTable.PSVersion)"
    }

    # Verify minimum disk space available (500MB) to prevent operation failures
    try {
        $systemDrive = [System.IO.Path]::GetPathRoot($env:SystemRoot)
        $drive = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($systemDrive.TrimEnd('\\'))'"
        $freeSpaceMB = [math]::Round($drive.FreeSpace / 1MB, 2)
        $minRequiredMB = 500
        
        if ($freeSpaceMB -lt $minRequiredMB) {
            throw "Insufficient disk space on $systemDrive. Free: ${freeSpaceMB}MB, Required: ${minRequiredMB}MB. Cleanup cannot proceed safely."
        }
        Write-Verbose "Pre-flight disk check: ${freeSpaceMB}MB free on $systemDrive"
    } catch {
        Write-Warning "Could not verify disk space: $($_.Exception.Message). Proceeding with caution."
    }

    $script:Summary = [ordered]@{
        StartTime = (Get-Date).ToString('o')
        Hostname  = $env:COMPUTERNAME
        DaysToKeep = $DaysToKeep
        Aggressive = [bool]$Aggressive
        Items = @()
        Errors = @()
        FreedBytes = 0
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $transcriptStarted = $false

    if (-not $NoTranscript) {
        $transcriptPath = "$LogPath.transcript.txt"
        try { 
            Start-Transcript -Path $transcriptPath -ErrorAction Stop | Out-Null
            $transcriptStarted = $true
        } catch { 
            Write-Warning "Transcript failed: $_"
        }
    }

    # Ensure transcript cleanup on any exit
    try {

    function Get-FreeSpaceReport {
        try {
            Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
                # Prevent division by zero for empty/unformatted drives
                $percentFree = if ($_.Size -gt 0) {
                    '{0:P1}' -f ($_.FreeSpace / $_.Size)
                } else {
                    'N/A'
                }
                
                [PSCustomObject]@{
                    Drive       = $_.DeviceID
                    SizeGB      = '{0:N1}' -f ($_.Size / 1GB)
                    FreeGB      = '{0:N1}' -f ($_.FreeSpace / 1GB)
                    PercentFree = $percentFree
                }
            }
        } catch { Write-Warning "Disk report failed: $_" }
    }

    $initialDisk = Get-FreeSpaceReport

    function Should-Purge($Path) {
        Test-Path -LiteralPath $Path
    }

    function Add-Result([string]$Category, [long]$Freed, [int]$Count) {
        $script:Summary.Items += [ordered]@{ Category = $Category; FreedBytes = $Freed; DeletedCount = $Count }
        $script:Summary.FreedBytes += $Freed
    }

    function Handle-Error($Category, $ErrorRecord, $Context = '') {
        $errorDetail = [ordered]@{ 
            Category = $Category
            Message = $ErrorRecord.Exception.Message
            TargetObject = if ($ErrorRecord.TargetObject) { $ErrorRecord.TargetObject.ToString() } else { 'N/A' }
            ScriptStackTrace = $ErrorRecord.ScriptStackTrace
            Context = $Context
        }
        $script:Summary.Errors += $errorDetail
        $msg = "$Category"
        if ($Context) { $msg += " [$Context]" }
        $msg += ": $($ErrorRecord.Exception.Message)"
        Write-Warning $msg
    }

    function Get-TargetFiles {
        param(
            [string]$Root,
            [int]$Days,
            [string]$Category,
            [string[]]$IncludeExtensions,
            [switch]$Recurse,
            [switch]$AggressiveMode
        )
        if (-not (Should-Purge $Root)) { return @() }
        $cutoff = (Get-Date).AddDays(-$Days)
        $opt = @{ Path = $Root; ErrorAction = 'SilentlyContinue' }
        if ($Recurse) { $opt.Recurse = $true }
        Get-ChildItem @opt | Where-Object {
            $file = $_
            $age = $_.LastWriteTime -lt $cutoff
            $excluded = $false
            foreach ($pattern in $ExcludePatterns) {
                if ($pattern -and ($file.Name -like $pattern -or $file.FullName -like $pattern)) {
                    $excluded = $true
                    break
                }
            }
            $age -and -not $excluded
        }
    }

    function Remove-Targets {
        param(
            [string]$Category,
            [System.IO.FileSystemInfo[]]$Items
        )
        $freed = 0
        $count = 0
        foreach ($i in $Items) {
            try {
                # Calculate size before deletion
                $size = 0
                if ($i -is [System.IO.FileInfo]) {
                    $size = $i.Length
                } elseif ($i.PSIsContainer) {
                    # Calculate directory size recursively
                    try {
                        $dirSize = (Get-ChildItem -LiteralPath $i.FullName -Recurse -File -ErrorAction SilentlyContinue | 
                                    Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                        if ($dirSize) { $size = $dirSize }
                    } catch { 
                        # If size calculation fails, continue with 0
                        Write-Verbose "Could not calculate size for directory: $($i.FullName)"
                    }
                }
                
                if ($PSCmdlet.ShouldProcess($i.FullName, "Remove")) {
                    Remove-Item -LiteralPath $i.FullName -Force -ErrorAction Stop -Recurse:$($i.PSIsContainer)
                    $freed += $size; $count++
                }
            } catch { 
                Handle-Error $Category $_ -Context $i.FullName
            }
        }
        Add-Result $Category $freed $count
    }

        Write-Verbose "Initial disk state:"; $initialDisk | Format-Table | Out-String | Write-Verbose

    # Region: Core Targets
    if (-not $SkipSoftwareDistribution) {
        $sdRoot = "$env:windir\SoftwareDistribution\Download"
        $sdItems = Get-TargetFiles -Root $sdRoot -Days $DaysToKeep -Category 'SoftwareDistribution' -Recurse
        Remove-Targets -Category 'SoftwareDistribution' -Items $sdItems
    }

    $windowsTemp = Get-TargetFiles -Root "$env:windir\Temp" -Days $DaysToKeep -Category 'WindowsTemp' -Recurse
    Remove-Targets -Category 'WindowsTemp' -Items $windowsTemp

    if (-not $SkipUserTemps) {
        $userTempPattern = 'C:\Users\*\AppData\Local\Temp'
        if (Test-Path 'C:\Users') {
            $userTemps = Get-ChildItem -Path $userTempPattern -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                Get-TargetFiles -Root $_.FullName -Days $DaysToKeep -Category 'UserTemp' -Recurse
            }
            Remove-Targets -Category 'UserTemp' -Items $userTemps
        }
    }

    if (-not $SkipIISLogs -and (Test-Path 'C:\inetpub\logs\LogFiles')) {
        $iisLogs = Get-TargetFiles -Root 'C:\inetpub\logs\LogFiles' -Days $DaysToKeep -Category 'IISLogs' -Recurse
        Remove-Targets -Category 'IISLogs' -Items $iisLogs
    }

    if (-not $SkipPrefetch -and (Test-Path "$env:windir\Prefetch")) {
        $prefetch = Get-TargetFiles -Root "$env:windir\Prefetch" -Days $DaysToKeep -Category 'Prefetch'
        Remove-Targets -Category 'Prefetch' -Items $prefetch
    }

    if ($Aggressive) {
        # Windows crash dumps (Minidump folder)
        $minidump = Get-TargetFiles -Root "$env:windir\Minidump" -Days $DaysToKeep -Category 'MiniDump'
        Remove-Targets -Category 'MiniDump' -Items $minidump
        
        # System memory dump (often large, single file)
        if (Test-Path "$env:windir\memory.dmp") {
            try {
                $memDump = Get-Item "$env:windir\memory.dmp" -ErrorAction Stop
                if ($memDump.LastWriteTime -lt (Get-Date).AddDays(-$DaysToKeep)) {
                    if ($PSCmdlet.ShouldProcess("$env:windir\memory.dmp", "Remove")) {
                        $size = $memDump.Length
                        Remove-Item -LiteralPath $memDump.FullName -Force -ErrorAction Stop
                        Add-Result 'MemoryDump' $size 1
                    }
                }
            } catch { Handle-Error 'MemoryDump' $_ }
        }
        
        # Windows Error Reporting
        $werSystem = Get-TargetFiles -Root "$env:ProgramData\Microsoft\Windows\WER" -Days $DaysToKeep -Category 'WERSystem' -Recurse
        Remove-Targets -Category 'WERSystem' -Items $werSystem
        
        # User Windows Error Reporting
        if (Test-Path 'C:\Users\*\AppData\Local\Microsoft\Windows\WER') {
            $werUser = Get-ChildItem -Path 'C:\Users\*\AppData\Local\Microsoft\Windows\WER' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                Get-TargetFiles -Root $_.FullName -Days $DaysToKeep -Category 'WERUser' -Recurse
            }
            Remove-Targets -Category 'WERUser' -Items $werUser
        }
        
        # CBS logs (component-based servicing)
        if (Test-Path "$env:windir\Logs\CBS") {
            $cbsLogs = Get-TargetFiles -Root "$env:windir\Logs\CBS" -Days $DaysToKeep -Category 'CBSLogs' -Recurse
            Remove-Targets -Category 'CBSLogs' -Items $cbsLogs
        }
        
        # Internet Explorer cache folders (legacy browsers)
        $iePaths = @(
            'C:\Users\*\AppData\Local\Microsoft\Windows\Temporary Internet Files',
            'C:\Users\*\AppData\Local\Microsoft\Windows\IECompatCache',
            'C:\Users\*\AppData\Local\Microsoft\Windows\IECompatUaCache',
            'C:\Users\*\AppData\Local\Microsoft\Windows\IEDownloadHistory',
            'C:\Users\*\AppData\Local\Microsoft\Windows\INetCache',
            'C:\Users\*\AppData\Local\Microsoft\Windows\INetCookies'
        )
        
        foreach ($iePath in $iePaths) {
            if (Test-Path $iePath) {
                $categoryName = Split-Path $iePath -Leaf
                $ieFiles = Get-ChildItem -Path $iePath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                    Get-TargetFiles -Root $_.FullName -Days $DaysToKeep -Category "IE_$categoryName" -Recurse
                }
                Remove-Targets -Category "IE_$categoryName" -Items $ieFiles
            }
        }
        
        # RDP cache
        if (Test-Path 'C:\Users\*\AppData\Local\Microsoft\Terminal Server Client\Cache') {
            $rdpCache = Get-ChildItem -Path 'C:\Users\*\AppData\Local\Microsoft\Terminal Server Client\Cache' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                Get-TargetFiles -Root $_.FullName -Days $DaysToKeep -Category 'RDPCache' -Recurse
            }
            Remove-Targets -Category 'RDPCache' -Items $rdpCache
        }
        
        # Optional: OEM temp folders (only if explicitly aggressive)
        foreach ($oemPath in @('C:\Intel', 'C:\PerfLogs', 'C:\Config.Msi')) {
            if (Test-Path $oemPath) {
                $oemName = Split-Path $oemPath -Leaf
                $oemFiles = Get-TargetFiles -Root $oemPath -Days $DaysToKeep -Category "OEM_$oemName" -Recurse
                Remove-Targets -Category "OEM_$oemName" -Items $oemFiles
            }
        }
    }

    if ($ExtraPaths) {
        foreach ($p in $ExtraPaths) {
            $extra = Get-TargetFiles -Root $p -Days $DaysToKeep -Category "Extra:$p" -Recurse
            Remove-Targets -Category "Extra:$p" -Items $extra
        }
    }

        if (-not $SkipRecycleBin) {
            try {
                # Calculate RecycleBin size before clearing
                $recycleBinSize = 0
                try {
                    if (-not $WhatIfPreference) {
                        $shell = New-Object -ComObject Shell.Application
                        $recycleBin = $shell.Namespace(0xA)
                        $recycleBinSize = ($recycleBin.Items() | Measure-Object -Property Size -Sum -ErrorAction SilentlyContinue).Sum
                        if (-not $recycleBinSize) { $recycleBinSize = 0 }
                    }
                } catch {
                    Write-Verbose "Could not calculate RecycleBin size: $($_.Exception.Message)"
                    $recycleBinSize = 0
                }
                
                if ($PSCmdlet.ShouldProcess('RecycleBin', 'Clear')) {
                    if (-not $WhatIfPreference) {
                        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
                    }
                }
                Add-Result 'RecycleBin' $recycleBinSize 1
            } catch { Handle-Error 'RecycleBin' $_ }
        }

        # Region: Large file scan (optional on Aggressive)
        if ($Aggressive -and -not $WhatIfPreference) {
            try {
                Write-Verbose "Scanning for large ISO/VHD files (may take time)..."
                # Scan all fixed drives instead of hardcoded C:
                $fixedDrives = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" | 
                               Select-Object -ExpandProperty DeviceID
                
                $large = @()
                foreach ($drive in $fixedDrives) {
                    $large += Get-ChildItem -Path "$drive\" -Include *.iso,*.vhd,*.vhdx -Recurse -ErrorAction SilentlyContinue
                }
                
                $script:Summary.LargeFiles = $large | 
                    Sort-Object Length -Descending | 
                    Select-Object -First 15 | 
                    Select-Object Name, Directory, @{n='SizeGB';e={'{0:N2}' -f ($_.Length/1GB)}}
            } catch { Handle-Error 'LargeFileScan' $_ }
        }

        # Region: Windows Disk Cleanup (Cleanmgr) - Optional
        if ($RunCleanmgr -and -not $WhatIfPreference) {
            try {
                # Verify cleanmgr.exe exists
                $cleanmgrPath = Join-Path $env:windir 'System32\cleanmgr.exe'
                if (Test-Path $cleanmgrPath) {
                    Write-Verbose "Running Windows Disk Cleanup (cleanmgr.exe)..."
                    if ($PSCmdlet.ShouldProcess('Windows Disk Cleanup', 'Run cleanmgr.exe /sagerun:1')) {
                        # /sagerun:1 uses predefined cleanup settings (requires prior /sageset:1 configuration)
                        $cleanmgrProc = Start-Process -FilePath $cleanmgrPath -ArgumentList '/sagerun:1' -Wait -PassThru -WindowStyle Minimized
                        if ($cleanmgrProc.ExitCode -eq 0) {
                            Write-Verbose "Cleanmgr.exe completed successfully"
                        } else {
                            Write-Warning "Cleanmgr.exe exited with code: $($cleanmgrProc.ExitCode)"
                        }
                    }
                } else {
                    Write-Warning "Cleanmgr.exe not found at $cleanmgrPath. Disk Cleanup feature not available."
                }
            } catch { Handle-Error 'Cleanmgr' $_ }
        }

    $finalDisk = Get-FreeSpaceReport
    $stopwatch.Stop()
    $script:Summary.EndTime = (Get-Date).ToString('o')
    $script:Summary.ElapsedSeconds = [math]::Round($stopwatch.Elapsed.TotalSeconds,2)
    $script:Summary.InitialDisk = $initialDisk
    $script:Summary.FinalDisk = $finalDisk

    # Output summary table
    $script:Summary.Items | Sort-Object Category | Format-Table Category, DeletedCount, @{n='FreedMB';e={[math]::Round($_.FreedBytes/1MB,2)}} | Out-String | Write-Verbose
    Write-Host "Total Freed (Estimated): {0:N2} MB" -f ($script:Summary.FreedBytes/1MB)
    Write-Host "Elapsed Seconds: $($script:Summary.ElapsedSeconds)" -ForegroundColor Cyan

        # Persist JSON log
        try {
            $json = if ($JsonPretty) { $script:Summary | ConvertTo-Json -Depth 6 } else { $script:Summary | ConvertTo-Json -Depth 6 -Compress }
            $json | Set-Content -Path $LogPath -Encoding UTF8
            Write-Verbose "JSON report written to $LogPath"
        } catch { Write-Warning "Failed writing JSON log: $_" }

    } finally {
        # Guaranteed cleanup
        if ($transcriptStarted) { 
            try { Stop-Transcript | Out-Null } catch { }
        }
    }
}

# If script is dot-sourced we do not auto-run; otherwise run when executed directly
if ($MyInvocation.InvocationName -eq '.') {
    Write-Verbose 'Start-Cleanup function loaded.'
} else {
    Start-Cleanup @PSBoundParameters
}
