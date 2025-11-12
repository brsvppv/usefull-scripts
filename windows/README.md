# Windows scripts

Folder layout:

- `powershell/` - `.ps1` scripts for modern automation
- `batch/` - `.bat` legacy scripts
- `common/` - small wrappers usable by both

Conventions:
- PowerShell scripts should include an `<# .SYNOPSIS ... #>` header and parameter blocks where applicable
- For PowerShell, consider signing and setting ExecutionPolicy via docs if needed
