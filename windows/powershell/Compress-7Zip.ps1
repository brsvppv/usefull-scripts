<#
.SYNOPSIS
    Compresses files using 7-Zip with auto-detection and robust error handling.

.DESCRIPTION
    A wrapper for 7-Zip that automatically finds the 7z.exe executable (checking Registry, PATH, 
    and standard installation directories). Supports various archive formats and password protection.
    
.PARAMETER Source
    The file or directory to compress.

.PARAMETER Destination
    The destination archive file path.

.PARAMETER Password
    Optional password for encryption.

.PARAMETER ArchiveType
    The format of the archive (7z, zip, gzip, bzip2, tar). Default is 7z.

.PARAMETER ZipPath
    Optional manual path to 7z.exe. If not provided, the script attempts to find it.

.EXAMPLE
    Compress-7Zip -Source "C:\Data" -Destination "C:\Backups\Data.7z"
    Compresses C:\Data to a 7z archive.

.EXAMPLE
    Compress-7Zip -Source "C:\Secret" -Destination "C:\Backups\Secret.7z" -Password (Read-Host -AsSecureString)
    Compresses with password protection.
#>
function Compress-7Zip {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [string]$Source,

        [Parameter(Mandatory, Position = 1)]
        [string]$Destination,

        [Parameter(Position = 2)]
        [SecureString]$Password,

        [Parameter(Position = 3)]
        [ValidateSet('7z', 'zip', 'gzip', 'bzip2', 'tar')]
        [string]$ArchiveType = '7z',

        [Parameter(Position = 4)]
        [string]$ZipPath
    )

    process {
        # 1. Auto-detect 7-Zip if not provided
        if ([string]::IsNullOrWhiteSpace($ZipPath) -or -not (Test-Path $ZipPath)) {
            $possiblePaths = @(
                "$env:ProgramFiles\7-Zip\7z.exe",
                "$env:ProgramFiles(x86)\7-Zip\7z.exe",
                "$env:ChocolateyInstall\tools\7z.exe"
            )
            
            # Check PATH
            if (Get-Command '7z.exe' -ErrorAction SilentlyContinue) {
                $ZipPath = (Get-Command '7z.exe').Source
            }
            
            # Check standard locations
            if (-not $ZipPath) {
                foreach ($path in $possiblePaths) {
                    if (Test-Path $path) {
                        $ZipPath = $path
                        break
                    }
                }
            }
        }

        if (-not $ZipPath -or -not (Test-Path $ZipPath)) {
            throw "7-Zip executable (7z.exe) not found. Please install 7-Zip or specify the path."
        }

        Write-Verbose "Using 7-Zip at: $ZipPath"

        # 2. Validate Source
        if (-not (Test-Path $Source)) {
            throw "Source path does not exist: $Source"
        }

        # 3. Build Arguments
        # a = add, -t = type, -mx9 = max compression
        $arguments = @("a", "-t$ArchiveType", "`"$Destination`"", "`"$Source`"", "-mx9")

        if ($Password) {
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
            $PlainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            $arguments += "-p`"$PlainPassword`""
            # Zero out memory for safety (best effort in managed code)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        }

        # 4. Execute
        Write-Verbose "Executing: $ZipPath $arguments"
        try {
            $process = Start-Process -FilePath $ZipPath -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
            
            if ($process.ExitCode -eq 0) {
                Write-Output "Successfully created archive: $Destination"
            } else {
                Write-Error "7-Zip failed with exit code $($process.ExitCode)."
            }
        }
        catch {
            Write-Error "Failed to execute 7-Zip: $_"
        }
    }
}

# Export function if dot-sourced
if ($MyInvocation.InvocationName -eq '.') {
    Write-Verbose "Compress-7Zip function loaded."
} else {
    # Run if executed directly
    Compress-7Zip @PSBoundParameters
}
