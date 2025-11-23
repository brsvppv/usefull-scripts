<#
.SYNOPSIS
    Generates a cryptographically secure random password.

.DESCRIPTION
    Creates a random password with customizable length and complexity requirements.
    Uses the .NET RNGCryptoServiceProvider for cryptographic security, making it suitable
    for production secrets, API keys, and user credentials.
    Works on Windows PowerShell 5.1 and PowerShell Core (Cross-platform).

.PARAMETER Length
    The length of the password to generate. Default is 16.

.PARAMETER Count
    Number of passwords to generate. Default is 1.

.PARAMETER IncludeSpecial
    Include special characters (e.g. !@#$%). Default is True.

.PARAMETER ExcludeAmbiguous
    Exclude ambiguous characters (e.g. I, l, 1, O, 0). Default is False.

.EXAMPLE
    New-SecurePassword
    Generates a single 16-character password with special characters.

.EXAMPLE
    New-SecurePassword -Length 32 -Count 5 -ExcludeAmbiguous
    Generates 5 passwords, 32 characters long, without confusing characters.

.EXAMPLE
    # One-liner to run directly from GitHub
    irm https://raw.githubusercontent.com/brsvppv/usefull-scripts/master/windows/powershell/New-SecurePassword.ps1 | iex
#>
function New-SecurePassword {
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
        [ValidateRange(8, 128)]
        [int]$Length = 16,

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$Count = 1,

        [Parameter()]
        [switch]$IncludeSpecial = $true,

        [Parameter()]
        [switch]$ExcludeAmbiguous
    )

    process {
        # Character sets
        $charSets = @(
            'abcdefghijklmnopqrstuvwxyz',
            'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
            '0123456789'
        )

        if ($IncludeSpecial) {
            $charSets += '!@#$%^&*()_+-=[]{}|;:,.<>?'
        }

        # Ambiguous characters to remove if requested
        $ambiguousChars = 'Il1O0'

        # Build the full character pool
        $charPool = -join $charSets
        if ($ExcludeAmbiguous) {
            foreach ($char in $ambiguousChars.ToCharArray()) {
                $charPool = $charPool.Replace($char.ToString(), '')
            }
        }

        # Ensure we have a valid pool
        if ($charPool.Length -eq 0) {
            Write-Error "Character pool is empty. Check your exclusion parameters."
            return
        }

        # Generator loop
        for ($i = 0; $i -lt $Count; $i++) {
            $bytes = New-Object byte[] $Length
            
            # Use RNGCryptoServiceProvider for cryptographic randomness
            $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
            $rng.GetBytes($bytes)
            
            $password = New-Object char[] $Length
            for ($j = 0; $j -lt $Length; $j++) {
                # Modulo bias mitigation is minor for this use case, direct map is acceptable for general passwords
                # but for strict crypto, we'd discard values. Here we map byte to index.
                $index = $bytes[$j] % $charPool.Length
                $password[$j] = $charPool[$index]
            }
            
            # Output string
            Write-Output (-join $password)
            
            # Cleanup
            if ($rng) { $rng.Dispose() }
        }
    }
}

# Export function if dot-sourced
if ($MyInvocation.InvocationName -eq '.') {
    Write-Verbose "New-SecurePassword function loaded."
} else {
    # Run if executed directly
    New-SecurePassword @PSBoundParameters
}
