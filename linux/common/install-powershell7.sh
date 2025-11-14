#!/usr/bin/env bash
# ==============================================================================
# PowerShell 7 Installer (Ubuntu/Debian)
# Author: brsvppv
# Description: Production-grade installer for PowerShell 7 on Ubuntu/Debian.
# - Adds Microsoft packages repo and installs powershell (or via Snap)
# - Supports dry-run, uninstall, preview channel, and non-interactive mode
# - Safe, idempotent, with clear logging and error handling
#
# Usage (direct from GitHub):
#   curl -fsSL https://raw.githubusercontent.com/brsvppv/usefull-scripts/master/linux/common/install-powershell7.sh | bash -s -- -y
#   curl -fsSL https://raw.githubusercontent.com/brsvppv/usefull-scripts/master/linux/common/install-powershell7.sh | bash -s -- --dry-run --verbose
#   curl -fsSL https://raw.githubusercontent.com/brsvppv/usefull-scripts/master/linux/common/install-powershell7.sh | bash -s -- --remove
#   curl -fsSL https://raw.githubusercontent.com/brsvppv/usefull-scripts/master/linux/common/install-powershell7.sh | bash -s -- --snap -y
#
# Local:
#   chmod +x linux/common/install-powershell7.sh
#   sudo linux/common/install-powershell7.sh -y
# ==============================================================================
set -Eeuo pipefail
IFS=$'\n\t'

# --- Config ---
ASSUME_YES=false
DRY_RUN=false
USE_SNAP=false
INSTALL_PREVIEW=false
VERBOSE=false
REMOVE=false

# --- Logging ---
log()  { printf "[INFO] %s\n" "$*"; }
warn() { printf "[WARN] %s\n" "$*" >&2; }
err()  { printf "[ERROR] %s\n" "$*" >&2; }

run() {
  if $DRY_RUN; then
    printf "[DRY-RUN] %s\n" "$*"
  else
    eval "$@"
  fi
}

usage() {
  cat <<'USAGE'
PowerShell 7 Installer for Ubuntu/Debian

Options:
  -y, --assume-yes        Non-interactive mode (auto-yes)
      --dry-run           Show what would be done without changing anything
      --snap              Install via Snap (classic confinement)
      --preview           Install powershell-preview package
      --remove            Uninstall PowerShell and exit
      --verbose           Enable verbose script output
  -h, --help              Show this help

Examples:
  # Install from GitHub (apt repo path)
  curl -fsSL https://raw.githubusercontent.com/brsvppv/usefull-scripts/master/linux/common/install-powershell7.sh | bash -s -- -y
  
  # Dry-run
  curl -fsSL https://raw.githubusercontent.com/brsvppv/usefull-scripts/master/linux/common/install-powershell7.sh | bash -s -- --dry-run --verbose

  # Uninstall
  curl -fsSL https://raw.githubusercontent.com/brsvppv/usefull-scripts/master/linux/common/install-powershell7.sh | bash -s -- --remove

  # Install via Snap
  curl -fsSL https://raw.githubusercontent.com/brsvppv/usefull-scripts/master/linux/common/install-powershell7.sh | bash -s -- --snap -y
USAGE
}

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--assume-yes) ASSUME_YES=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --snap) USE_SNAP=true; shift ;;
    --preview) INSTALL_PREVIEW=true; shift ;;
    --remove) REMOVE=true; shift ;;
    --verbose) VERBOSE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown option: $1"; usage; exit 2 ;;
  esac
done

if $VERBOSE; then set -x; fi

# --- Sudo helper ---
SUDO=""
if [[ $EUID -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then SUDO="sudo"; else err "Please run as root or install sudo."; exit 1; fi
fi

# --- OS detection ---
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
else
  err "/etc/os-release not found. Unsupported system."
  exit 1
fi
ID_LOWER=${ID,,}

case "$ID_LOWER" in
  ubuntu|debian) : ;;
  *) err "Unsupported ID=$ID_LOWER. Only Ubuntu/Debian are supported by this installer."; exit 1 ;;
esac

if [[ -z "${VERSION_ID:-}" ]]; then
  err "VERSION_ID missing from /etc/os-release."
  exit 1
fi

APT_GET="$SUDO apt-get -y"
if ! $ASSUME_YES; then APT_GET="$SUDO apt-get"; fi

# --- Functions ---
ensure_deps() {
  log "Installing prerequisites..."
  run "$APT_GET update"
  run "$APT_GET install curl ca-certificates apt-transport-https gnupg software-properties-common -y"
}

install_snap() {
  log "Installing PowerShell via Snap..."
  run "$APT_GET update"
  run "$APT_GET install snapd -y"
  run "$SUDO snap install powershell --classic"
}

repo_url() {
  # Official pattern uses VERSION_ID numeric path, e.g. ubuntu/22.04 or debian/12
  printf "https://packages.microsoft.com/config/%s/%s/packages-microsoft-prod.deb" "$ID_LOWER" "$VERSION_ID"
}

install_repo_and_pwsh() {
  local pkg_url tmp_deb pkg_name
  pkg_url=$(repo_url)
  tmp_deb=$(mktemp)
  pkg_name="powershell"
  if $INSTALL_PREVIEW; then pkg_name="powershell-preview"; fi

  log "Adding Microsoft packages repository ($pkg_url)..."
  run "curl -fsSL '$pkg_url' -o '$tmp_deb'"
  run "$SUDO dpkg -i '$tmp_deb'"
  run "rm -f '$tmp_deb'"
  run "$APT_GET update"

  log "Installing $pkg_name..."
  run "$APT_GET install $pkg_name -y"
}

uninstall_pwsh() {
  log "Uninstalling PowerShell..."
  if command -v pwsh >/dev/null 2>&1; then
    run "$APT_GET remove --purge -y powershell powershell-preview || true"
  else
    warn "pwsh not found; attempting package removal anyway."
    run "$APT_GET remove --purge -y powershell powershell-preview || true"
  fi
  log "Done."
}

post_check() {
  if $DRY_RUN; then
    warn "Dry-run enabled; no changes were made."
    return 0
  fi
  if command -v pwsh >/dev/null 2>&1; then
    log "PowerShell installed successfully: $(pwsh -v 2>/dev/null || true)"
    log "Try: pwsh"
  else
    warn "pwsh command not found after install. Check output above for errors."
    return 1
  fi
}

# --- Main ---
if $REMOVE; then
  uninstall_pwsh
  exit 0
fi

ensure_deps

if $USE_SNAP; then
  install_snap
else
  install_repo_and_pwsh
fi

post_check
