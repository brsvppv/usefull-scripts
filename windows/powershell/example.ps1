<#
.SYNOPSIS
    Example PowerShell script for repo
.DESCRIPTION
    Prints basic system info as a smoke test example.
#>

Write-Output "Running example PowerShell script from usefull-scripts"
Write-Output "Time: $(Get-Date -Format o)"
Write-Output "Host: $env:COMPUTERNAME"
Write-Output "User: $env:USERNAME"

# Exit code 0 for success
exit 0
