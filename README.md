# usefull-scripts

Purpose
-------

This repository is a curated collection of small operational scripts and helpers intended for infrastructure and developer workflows. The objective is discoverability, consistent contribution patterns, and testable examples across platforms.

Repository philosophy
---------------------
- Keep scripts small and focused.
- Use OS-native formats for platform-specific utilities (PowerShell on Windows, shell on Linux).
- Prefer language-backed cross-platform tools (Python / Node) for utilities that must run on multiple OSes.
- Keep documentation centralized in this single README so contributors have one place to look.

Repository layout
-----------------
Top-level folders and purpose:
- `linux/` - distro-specific and common Linux scripts
	- `common/` - scripts intended to run across Linux distros
	- `debian/`, `ubuntu/`, `arch/`, `redhat/` - distro-specific helpers
- `windows/` - PowerShell, Batch and common Windows scripts
	- `powershell/` - `.ps1` automation
	- `batch/` - legacy `.bat` scripts
	- `common/` - shared helpers
- `cross-platform/` - language-based utilities runnable on multiple OSes
	- `python/`, `nodejs/`
- `templates/` - starter templates for new scripts (shell/PowerShell/python)
- `.github/workflows/` - CI workflows for linting and smoke tests

Examples and quick usage
------------------------
Linux (example):
```bash
# make executable once
chmod +x linux/common/example.sh
# run it
./linux/common/example.sh
```
PowerShell (Windows):
```powershell
pwsh -File .\windows\powershell\example.ps1
```
Python (cross-platform):
```bash
py -3 cross-platform/python/cli.py   # Windows (py launcher)
python3 cross-platform/python/cli.py # Linux
```

Contributing
------------
When adding a script:
1. Place it in the appropriate OS folder. If it runs cross-platform, prefer `cross-platform/python` or `cross-platform/nodejs`.
2. Include a short header in the script with: purpose, usage example, dependencies, and required privileges.
3. Add a smoke test or simple verification if possible.
4. Open a PR with a clear description of the change.

Templates
---------
Use `templates/` to bootstrap new scripts — they provide a standard header and basic scaffolding.

CI & Quality
------------
Recommended CI jobs (see `.github/workflows`):
- ShellCheck for `*.sh` on Ubuntu runners
- PSScriptAnalyzer for `*.ps1` on Windows runners
- Ruff/pytest (or similar) for Python on Ubuntu runners
- Smoke-test example scripts on the appropriate runner

Packaging and distribution
-------------------------
If you want to expose a set of stable commands to users, add a `bin/` folder that contains small launchers and provide an `install` script to link or copy those into a PATH location. For Windows, provide a PowerShell installer.

Notes and conventions
---------------------
- Keep scripts idempotent where practical.
- Prefer POSIX shell for cross-distro Linux scripts and avoid using bash-specific features unless documented.
- Add executable bits for Linux scripts before packaging (`chmod +x`).

Next steps
----------
1. Add `tests/` for smoke and unit tests if you want automated verification.
2. Add `LICENSE` to clarify reuse.
3. Consider `bin/` + release process if you publish stable commands.

Generated: 2025-11-12
