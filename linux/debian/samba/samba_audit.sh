#!/usr/bin/env bash
# samba_audit.sh
# Production-ready Samba audit report generator
# Generates an HTML audit report (and optional short CLI summary) for Samba hosts.
#
# Key features:
#  - Robust share discovery (testparm with smb.conf fallback)
#  - Filtered mount detection (only device-backed or remote mounts)
#  - Per-share ACL checks (getfacl/stat fallback)
#  - System info, capabilities detection, and session reporting
#  - Safe cleanup and error handling
#  - CLI options for automation (CI/CD friendly)
#
# Usage:
#   sudo ./samba_audit.sh --output-dir /var/reports/samba
#   ./samba_audit.sh --summary
#
# See --help for more details.

set -euo pipefail
IFS=$'\n\t'

# Defaults
OUTPUT_DIR="${OUTPUT_DIR:-/tmp}"
QUIET=false
NO_CLEANUP=false
VERBOSE=false
PRINT_SUMMARY=false
SMB_CONF_OVERRIDE=""

SCRIPT_VERSION="1.0.0"

usage() {
  cat <<USAGE
Usage: $0 [options]

Options:
  -o, --output-dir DIR    Output directory for HTML report (default: /tmp)
  --smb-conf PATH         Override smb.conf path (default: auto-discovered)
  --no-cleanup            Don't remove tempdir (useful for debugging)
  --quiet                 Less verbose output
  --verbose               More verbose output
  --summary               Print short human-readable text summary to stdout
  -h, --help              Show this help

Examples:
  # Run on Samba host (recommended as root)
  sudo $0 --output-dir /var/reports/samba

  # Quick summary only
  $0 --summary

  # CI/Testing with fixture
  SMB_CONF=/tmp/test.conf $0 --output-dir /tmp --summary
USAGE
}

log() { [ "$QUIET" = false ] && printf "[INFO] %s\n" "$*"; }
logv() { [ "$VERBOSE" = true ] && printf "[VERBOSE] %s\n" "$*"; }
warn() { printf "[WARN] %s\n" "$*" >&2; }
err() { printf "[ERROR] %s\n" "$*" >&2; }

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output-dir) OUTPUT_DIR="$2"; shift 2;;
    --smb-conf) SMB_CONF_OVERRIDE="$2"; shift 2;;
    --no-cleanup) NO_CLEANUP=true; shift;;
    --quiet) QUIET=true; shift;;
    --summary) PRINT_SUMMARY=true; shift;;
    --verbose) VERBOSE=true; shift;;
    -h|--help) usage; exit 0;;
    *) warn "Unknown option: $1"; usage; exit 2;;
  esac
done

# Validate output dir
mkdir -p "$OUTPUT_DIR" || { err "Could not create $OUTPUT_DIR"; exit 3; }

# Discover smb.conf if not overridden
if [ -n "$SMB_CONF_OVERRIDE" ]; then
  SMB_CONF="$SMB_CONF_OVERRIDE"
elif [ -n "${SMB_CONF:-}" ]; then
  # Allow environment variable SMB_CONF to work if set
  :
else
  SMB_CONF=""
  for c in /etc/samba/smb.conf /usr/local/samba/etc/smb.conf /usr/samba/etc/smb.conf; do
    if [ -f "$c" ]; then
      SMB_CONF="$c"
      break
    fi
  done
  if [ -z "$SMB_CONF" ]; then
    # Default fallback even if missing, so script can run partially
    SMB_CONF="/etc/samba/smb.conf"
  fi
fi

# Environment
HOSTNAME=$(hostname -s 2>/dev/null || echo unknown)
DATE_FULL=$(date +"%Y-%m-%d %H:%M:%S %Z")
DATE_FN=$(date +"%Y%m%d_%H%M%S")
REPORT_PATH="$OUTPUT_DIR/samba_audit_${DATE_FN}.html"

TMPDIR=$(mktemp -d -t samba_audit.XXXXXX)
SHARE_TSV="$TMPDIR/shares.tsv"
PDB_CACHE="$TMPDIR/pdb_users.txt"
MOUNT_TABLE="$TMPDIR/mounts.tsv"

# Capability arrays
CAPS=()
MISSING_CAPS=()

has() { command -v "$1" >/dev/null 2>&1; }

html_escape() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'; }

detect_capabilities() {
  local want=(testparm pdbedit getfacl smbstatus findmnt lscpu df mount awk sed)
  for cmd in "${want[@]}"; do
    if has "$cmd"; then
      CAPS+=("$cmd")
    else
      MISSING_CAPS+=("$cmd")
    fi
  done
}

# Run detection
detect_capabilities || true

# Cleanup trap
finish() {
  local rc=${1:-0}
  if [ "$rc" -ne 0 ]; then
    err "Script failed with exit code $rc"
    if [ ! -f "$REPORT_PATH" ]; then
      # Write partial report
      mkdir -p "$(dirname "$REPORT_PATH")" 2>/dev/null || true
      {
        echo "<!doctype html><html><head><meta charset=\"utf-8\"><title>Samba Audit (partial)</title></head><body>"
        echo "<h3>Partial report — script failed (code: $rc)</h3>"
        echo "<pre>$(html_escape "$(printf 'Error: script failed with exit code %s' "$rc")")</pre>"
        echo "</body></html>"
      } > "$REPORT_PATH" || true
      chmod 0644 "$REPORT_PATH" || true
      log "Wrote partial report: $REPORT_PATH"
    fi
  fi

  if [ "$NO_CLEANUP" = false ]; then
    if [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ]; then
      rm -rf "$TMPDIR" || true
      logv "Cleaned up TMPDIR: $TMPDIR"
    fi
  else
    log "Leaving TMPDIR: $TMPDIR"
  fi

  if [ "$rc" -ne 0 ] && [ "$PRINT_SUMMARY" = true ]; then
    print_cli_summary || true
  fi
  return $rc
}
trap 'finish $?' EXIT

normalize_path() {
  printf '%s' "$1" | sed -E 's/^[^/]*//; s/^[[:space:]]+//; s/[[:space:]]+$//'
}

discover_shares() {
  : > "$SHARE_TSV"
  if has testparm; then
    logv "Using testparm for share discovery"
    testparm -s 2>/dev/null | awk '
      /^\[.*\]$/ { s=substr($0,2,length($0)-2); path[s]=""; valid[s]=""; next }
      /^[[:space:]]*path[[:space:]]*=/ { p=$0; sub(/^[[:space:]]*path[[:space:]]*=[[:space:]]*/,"",p); gsub(/^[ \t]+|[ \t]+$/,"",p); path[s]=p }
      /^[[:space:]]*valid users[[:space:]]*=/ { v=$0; sub(/^[[:space:]]*valid users[[:space:]]*=[[:space:]]*/,"",v); gsub(/^[ \t]+|[ \t]+$/,"",v); valid[s]=v }
      END { for (k in path) printf "%s\t%s\t%s\n", k, path[k], valid[k] }' > "$SHARE_TSV" || true
  else
    if [ -f "$SMB_CONF" ]; then
      logv "Falling back to parsing smb.conf"
      awk '
        /^\[[^]]+\]$/ { sec=substr($0,2,length($0)-2); path[sec]=""; valid[sec]=""; insec=1; next }
        insec && /^[[:space:]]*path[[:space:]]*=/ { p=$0; sub(/^[[:space:]]*path[[:space:]]*=[[:space:]]*/,"",p); gsub(/^[ \t]+|[ \t]+$/,"",p); path[sec]=p }
        insec && /^[[:space:]]*valid users[[:space:]]*=/ { v=$0; sub(/^[[:space:]]*valid users[[:space:]]*=[[:space:]]*/,"",v); gsub(/^[ \t]+|[ \t]+$/,"",v); valid[sec]=v }
        END { for (k in path) printf "%s\t%s\t%s\n", k, path[k], valid[k] }' "$SMB_CONF" > "$SHARE_TSV" || true
    fi
  fi
}

discover_samba_users() {
  : > "$PDB_CACHE"
  if has pdbedit; then
    (pdbedit -L 2>/dev/null || true) | cut -d: -f1 | sort -u > "$PDB_CACHE" || true
  fi
}

collect_mounts() {
  : > "$MOUNT_TABLE"
  if has findmnt; then
    logv "Using findmnt to collect mounts"
    while IFS= read -r line; do
      tgt_raw=$(printf '%s' "$line" | awk '{print $1}')
      src_raw=$(printf '%s' "$line" | awk '{print $2}')
      fstype=$(printf '%s' "$line" | awk '{print $3}')
      tgt=$(normalize_path "$tgt_raw")
      src=$(normalize_path "$src_raw")
      case "$src" in
        /dev/*|/dev/mapper/*|/dev/md*|UUID=*|LABEL=*|//*)
          if [ -z "$tgt" ] || [ "${tgt:0:1}" != "/" ]; then continue; fi
          avail=$(df -h "$tgt" 2>/dev/null | awk 'NR==2{print $2" "$3" "$4" "$5}' || echo "n/a")
          printf "%s\t%s\t%s\t%s\n" "$tgt" "$src" "$fstype" "$avail" >> "$MOUNT_TABLE"
          ;;
        *) ;;
      esac
    done < <(findmnt -n -o TARGET,SOURCE,FSTYPE 2>/dev/null || true)
  else
    while IFS= read -r tgt_raw src_raw fstype; do
      tgt=$(normalize_path "$tgt_raw")
      src=$(normalize_path "$src_raw")
      case "$src" in
        /dev/*|/dev/mapper/*|/dev/md*|UUID=*|LABEL=*|//*)
          if [ -z "$tgt" ] || [ "${tgt:0:1}" != "/" ]; then continue; fi
          avail=$(df -h "$tgt" 2>/dev/null | awk 'NR==2{print $2" "$3" "$4" "$5}' || echo "n/a")
          printf "%s\t%s\t%s\t%s\n" "$tgt" "$src" "$fstype" "$avail" >> "$MOUNT_TABLE"
          ;;
        *) ;;
      esac
    done < <(mount | awk '{print $3 " " $1 " " $5}') || true
  fi
}

build_header() {
  E_HOST=$(html_escape "$HOSTNAME")
  E_DATE=$(html_escape "$DATE_FULL")
  E_SMB_CONF=$(html_escape "${SMB_CONF:-(not found)}")
  E_VERSION=$(html_escape "$SCRIPT_VERSION")
  
  cat > "$REPORT_PATH" <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Samba Audit — $E_HOST</title>
<style>
  body, html { height:100%; margin:0; padding:0; font-family:Inter,Arial,sans-serif; background:#f6fbfd; color:#123744; }
  .layout{display:flex; min-height:100vh;}
  .sidebar{width:260px;background:linear-gradient(180deg,#063449,#0b6fa5);color:#fff;display:flex;flex-direction:column;}
  .sidebar-header{padding:24px 18px;font-size:1.1rem;font-weight:700;border-bottom:1px solid rgba(255,255,255,0.1);}
  .menu{flex:1;overflow:auto;padding:12px 0;}
  .menu-btn{width:100%;background:none;border:none;color:#fff;text-align:left;padding:12px 18px;font-size:1em;cursor:pointer;transition:background 0.2s;}
  .menu-btn:hover, .menu-btn.active{background:rgba(255,255,255,0.1);}
  .main {flex:1;padding:24px;overflow:auto;}
  .card {background:#fff;padding:16px;border-radius:8px;margin-bottom:16px;box-shadow:0 2px 8px rgba(0,0,0,0.05);}
  .section-title{color:#0b6fa5;font-weight:700;margin-bottom:12px;font-size:1.1em;border-bottom:1px solid #eee;padding-bottom:8px;}
  .table{width:100%;border-collapse:collapse;margin-top:8px;}
  .table th, .table td{border:1px solid #eef2f5;padding:8px 12px;text-align:left;font-size:0.95em;}
  .table th{background:#f8fafe;font-weight:600;color:#556;}
  pre{background:#f8fafe;padding:12px;border-radius:6px;overflow:auto;font-size:0.9em;border:1px solid #eef2f5;}
  .footer{margin-top:24px;color:#889;font-size:0.9em;text-align:center;}
</style>
</head>
<body>
<div class="layout">
  <div class="sidebar">
    <div class="sidebar-header">🗂 Samba Audit<br><span style="font-size:0.8em;opacity:0.8">$E_HOST</span></div>
    <div class="menu">
      <button class="menu-btn" onclick="show('summary')">Summary</button>
      <button class="menu-btn" onclick="show('shares')">Shares</button>
      <button class="menu-btn" onclick="show('users')">Users</button>
      <button class="menu-btn" onclick="show('acls')">ACLs</button>
      <button class="menu-btn" onclick="show('sessions')">Sessions</button>
      <button class="menu-btn" onclick="show('config')">Config</button>
    </div>
  </div>
  <div class="main">
HTML
}

build_footer() {
  cat >> "$REPORT_PATH" <<HTML
    <div class="footer">Generated: $E_DATE • Script v$E_VERSION</div>
  </div>
</div>
<script>
function show(panel){
  var ids=['summary','shares','users','acls','sessions','config'];
  ids.forEach(function(id){
    var el=document.getElementById('panel-'+id); 
    if(el) el.style.display='none';
  }); 
  var el=document.getElementById('panel-'+panel); 
  if(el) el.style.display='block';
  
  document.querySelectorAll('.menu-btn').forEach(function(b){
    b.classList.remove('active');
    if(b.getAttribute('onclick').includes(panel)) b.classList.add('active');
  });
}
window.onload=function(){show('summary')}
</script>
</body>
</html>
HTML
}

build_summary() {
  local share_count=$( [ -s "$SHARE_TSV" ] && wc -l < "$SHARE_TSV" | tr -d ' ' || echo 0 )
  local user_count=$( [ -s "$PDB_CACHE" ] && wc -l < "$PDB_CACHE" | tr -d ' ' || echo 0 )
  
  local OS_INFO=$( [ -f /etc/os-release ] && grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2 | tr -d '"' || echo unknown )
  local KERNEL=$(uname -r 2>/dev/null || echo unknown)
  local CPU_INFO=$(has lscpu && lscpu 2>/dev/null | awk -F: '/Model name/ {print $2}' | xargs || echo "n/a")
  
  echo "<div class='card' id='panel-summary'>
    <div class='section-title'>Summary</div>
    <table class='table' style='width:auto;min-width:50%'>
      <tr><th>Host</th><td>$(html_escape "$HOSTNAME")</td></tr>
      <tr><th>OS</th><td>$(html_escape "$OS_INFO")</td></tr>
      <tr><th>Kernel</th><td>$(html_escape "$KERNEL")</td></tr>
      <tr><th>CPU</th><td>$(html_escape "$CPU_INFO")</td></tr>
      <tr><th>Shares Found</th><td>$share_count</td></tr>
      <tr><th>Samba Users</th><td>$user_count</td></tr>
      <tr><th>smb.conf</th><td>$(html_escape "${SMB_CONF:-(not found)}")</td></tr>
    </table>" >> "$REPORT_PATH"

  if [ ${#MISSING_CAPS[@]} -ne 0 ]; then
    local missing_list=$(IFS=','; echo "${MISSING_CAPS[*]}")
    echo "<div style='margin-top:12px;color:#d44;background:#fff0f0;padding:8px;border-radius:4px'>
      <b>Missing optional utilities:</b> $(html_escape "$missing_list")
    </div>" >> "$REPORT_PATH"
  fi
  echo "</div>" >> "$REPORT_PATH"
}

build_shares() {
  echo "<div class='card' id='panel-shares' style='display:none'><div class='section-title'>Shares</div>
  <table class='table'><thead><tr><th>Share</th><th>Path</th><th>Exists</th><th>World Writable</th><th>Disk Usage</th><th>Valid Users</th></tr></thead><tbody>" >> "$REPORT_PATH"
  
  if [ -s "$SHARE_TSV" ]; then
    while IFS=$'\t' read -r share path valid; do
      if [ "$share" = "global" ] || [ -z "$share" ]; then continue; fi
      
      exists="No"; world="No"; disk="n/a"
      if [ -n "$path" ] && [ -d "$path" ]; then
        exists="Yes"
        if has getfacl; then
          other_perm=$(getfacl -p "$path" 2>/dev/null | awk -F: '/^other:/ {print $2}' || true)
          if [[ "$other_perm" == *"w"* ]]; then world="Yes"; fi
        elif has stat; then
          mode=$(stat -c %a "$path" 2>/dev/null || echo 000)
          if [ "${mode: -1}" -ge 2 ] 2>/dev/null; then world="Yes"; fi
        fi
        if has du; then
          disk=$(du -sh "$path" 2>/dev/null | awk '{print $1}' || echo 'n/a')
        fi
      fi
      
      echo "<tr>
        <td>$(html_escape "$share")</td>
        <td>$(html_escape "$path")</td>
        <td>$(html_escape "$exists")</td>
        <td style='color:$( [ "$world" = "Yes" ] && echo "#d44" || echo "inherit" )'>$(html_escape "$world")</td>
        <td>$(html_escape "$disk")</td>
        <td>$(html_escape "$valid")</td>
      </tr>" >> "$REPORT_PATH"
    done < "$SHARE_TSV"
  else
    echo "<tr><td colspan='6'>No shares found</td></tr>" >> "$REPORT_PATH"
  fi
  echo "</tbody></table></div>" >> "$REPORT_PATH"
}

build_users() {
  echo "<div class='card' id='panel-users' style='display:none'><div class='section-title'>Users</div>
  <table class='table'><thead><tr><th>User</th><th>System Account</th></tr></thead><tbody>" >> "$REPORT_PATH"
  
  if [ -s "$PDB_CACHE" ]; then
    while IFS= read -r u; do
      if id "$u" >/dev/null 2>&1; then
        echo "<tr><td>$(html_escape "$u")</td><td>Present</td></tr>" >> "$REPORT_PATH"
      else
        echo "<tr><td>$(html_escape "$u")</td><td style='color:#d44'>Missing</td></tr>" >> "$REPORT_PATH"
      fi
    done < "$PDB_CACHE"
  else
    echo "<tr><td colspan='2'>No users found or pdbedit missing</td></tr>" >> "$REPORT_PATH"
  fi
  echo "</tbody></table></div>" >> "$REPORT_PATH"
}

build_acls() {
  echo "<div class='card' id='panel-acls' style='display:none'><div class='section-title'>ACLs</div>" >> "$REPORT_PATH"
  if [ -s "$SHARE_TSV" ] && has getfacl; then
    awk -F'\t' '{print $2}' "$SHARE_TSV" | sort -u | while IFS= read -r p; do
      [ -z "$p" ] && continue
      if [ -d "$p" ]; then
        echo "<div style='margin-bottom:16px'><b>$(html_escape "$p")</b><pre>" >> "$REPORT_PATH"
        getfacl -p "$p" 2>/dev/null | html_escape "$(cat)" >> "$REPORT_PATH" || echo "(getfacl failed)" >> "$REPORT_PATH"
        echo "</pre></div>" >> "$REPORT_PATH"
      fi
    done
  else
    echo "<div>No ACL info available.</div>" >> "$REPORT_PATH"
  fi
  echo "</div>" >> "$REPORT_PATH"
}

build_sessions() {
  echo "<div class='card' id='panel-sessions' style='display:none'><div class='section-title'>Sessions</div>" >> "$REPORT_PATH"
  if has smbstatus; then
    echo "<pre>$(html_escape "$(smbstatus 2>/dev/null || true)")</pre>" >> "$REPORT_PATH"
  else
    echo "<div>smbstatus not installed or no active sessions</div>" >> "$REPORT_PATH"
  fi
  echo "</div>" >> "$REPORT_PATH"
}

build_config() {
  echo "<div class='card' id='panel-config' style='display:none'><div class='section-title'>Config</div>" >> "$REPORT_PATH"
  if has testparm; then
    echo "<pre>$(html_escape "$(testparm -s 2>/dev/null || true)")</pre>" >> "$REPORT_PATH"
  elif [ -f "$SMB_CONF" ]; then
    echo "<pre>$(html_escape "$(cat "$SMB_CONF")")</pre>" >> "$REPORT_PATH"
  else
    echo "<div>Config not found.</div>" >> "$REPORT_PATH"
  fi
  echo "</div>" >> "$REPORT_PATH"
}

print_cli_summary() {
  local share_count=$( [ -s "$SHARE_TSV" ] && wc -l < "$SHARE_TSV" | tr -d ' ' || echo 0 )
  local user_count=$( [ -s "$PDB_CACHE" ] && wc -l < "$PDB_CACHE" | tr -d ' ' || echo 0 )
  
  echo "Samba Audit Report"
  echo "------------------"
  echo "Host: $HOSTNAME"
  echo "Report: $REPORT_PATH"
  echo "Shares Found: $share_count"
  echo "Samba Users: $user_count"
  
  if [ ${#MISSING_CAPS[@]} -ne 0 ]; then
    echo "Missing tools: ${MISSING_CAPS[*]}"
  fi
  
  if [ "$(id -u)" -ne 0 ]; then
    echo "NOTE: Not running as root. Results may be incomplete."
  fi
}

# Main execution
log "Starting Samba audit..."
if [ "$(id -u)" -ne 0 ]; then
  warn "Not running as root. Some info may be limited."
fi

discover_shares
discover_samba_users
collect_mounts

build_header
build_summary
build_shares
build_users
build_acls
build_sessions
build_config
build_footer

chmod 0644 "$REPORT_PATH" || true
log "Report generated: $REPORT_PATH"

if [ "$PRINT_SUMMARY" = true ]; then
  print_cli_summary
fi

exit 0