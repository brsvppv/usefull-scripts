# Architecture & Standards

This file describes repository standards, naming conventions, and CI expectations.

Standards (summary):
- Scripts must be small, focused, and documented.
- Use `common/` for reusable helpers.
- Keep distro-specific logic minimal and documented.
- Add tests or smoke checks for non-trivial scripts.

CI suggestions:
- Lint shell scripts (shellcheck), PowerShell (PSScriptAnalyzer), Python (ruff/pytest).
- Run smoke tests in containers or Windows runners.
