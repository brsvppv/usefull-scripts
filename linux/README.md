# Linux scripts

Folder layout:

- `common/` - works across distributions
- distro folders (debian, ubuntu, arch, redhat) contain distro-specific helpers

Naming & conventions:
- Use `.sh`
- Add a header with: purpose, supported distros, required packages, basic usage example
- Keep scripts idempotent where possible

Permissions:
- After adding Linux scripts run `chmod +x <script>` before use or when packaging.
