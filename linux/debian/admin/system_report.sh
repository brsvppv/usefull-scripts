#!/usr/bin/env bash
# system_report.sh
# Generates a comprehensive HTML system report (Hardware, OS, Network, Security, Logs).
# Consolidates features from previous system reporting scripts.
#
# Usage:
#   sudo ./system_report.sh --output-dir /var/www/html/reports
#   ./system_report.sh --help

set -euo pipefail
IFS=$'\n\t'

# Defaults
OUTPUT_DIR="${OUTPUT_DIR:-/tmp}"
QUIET=false
VERBOSE=false
OPEN_REPORT=false

usage() {
  cat <<USAGE
Usage: $0 [options]

Options:
  -o, --output-dir DIR    Directory to save the report (default: /tmp)
  --open                  Open the report in default browser after generation
  --quiet                 Suppress output
  --verbose               Verbose output
  -h, --help              Show this help

Description:
  Generates a detailed HTML report containing:
  - Hardware Inventory (CPU, RAM, Disks, RAID, PCI/USB)
  - Software Config (OS, Kernel, Packages, Services)
  - Security Info (SSH, Firewall, Fail2Ban, Auth Logs)
  - Network Config (Interfaces, DNS, Listening Ports)
  - Storage (Mounts, Usage, SMART status)
USAGE
}

log() { [ "$QUIET" = false ] && printf "[INFO] %s\n" "$*"; }
warn() { printf "[WARN] %s\n" "$*" >&2; }
err() { printf "[ERROR] %s\n" "$*" >&2; }

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output-dir) OUTPUT_DIR="$2"; shift 2;;
    --open) OPEN_REPORT=true; shift;;
    --quiet) QUIET=true; shift;;
    --verbose) VERBOSE=true; shift;;
    -h|--help) usage; exit 0;;
    *) warn "Unknown option: $1"; usage; exit 2;;
  esac
done

# Check root for full details
if [ "$(id -u)" -ne 0 ]; then
  warn "Not running as root. Some hardware/security details may be missing."
fi

mkdir -p "$OUTPUT_DIR"
REPORT_FILE="$OUTPUT_DIR/system_report_$(hostname)_$(date +%Y%m%d_%H%M%S).html"

# Helpers
cmd_out() {
  if command -v "$1" >/dev/null 2>&1; then
    "$@" 2>&1 || echo "Error running $1"
  else
    echo "$1 not installed"
  fi
}

# Start HTML
cat > "$REPORT_FILE" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>System Report - $(hostname)</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; line-height: 1.6; margin: 0; padding: 20px; background: #f4f7f9; color: #333; }
        .container { max-width: 1200px; margin: 0 auto; background: #fff; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.05); }
        h1 { border-bottom: 2px solid #3498db; padding-bottom: 10px; color: #2c3e50; }
        h2 { color: #34495e; margin-top: 30px; border-bottom: 1px solid #eee; padding-bottom: 5px; }
        h3 { color: #7f8c8d; font-size: 1.1em; margin-top: 20px; }
        pre { background: #f8f9fa; padding: 12px; border-radius: 4px; overflow-x: auto; font-size: 0.9em; border: 1px solid #e9ecef; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(400px, 1fr)); gap: 20px; }
        .card { background: #fff; border: 1px solid #e1e4e8; border-radius: 6px; padding: 15px; }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; }
        th, td { padding: 8px 12px; border: 1px solid #ddd; text-align: left; }
        th { background: #f1f3f5; font-weight: 600; }
        .footer { margin-top: 40px; text-align: center; color: #999; font-size: 0.85em; }
        .status-active { color: #27ae60; font-weight: bold; }
        .status-inactive { color: #e74c3c; }
    </style>
</head>
<body>
<div class="container">
    <h1>System Report: $(hostname)</h1>
    <p><strong>Generated:</strong> $(date) &bull; <strong>Kernel:</strong> $(uname -r) &bull; <strong>Uptime:</strong> $(uptime -p)</p>

    <!-- HARDWARE -->
    <h2>1. Hardware Inventory</h2>
    <div class="grid">
        <div class="card">
            <h3>CPU</h3>
            <pre>$(cmd_out lscpu | grep -E 'Model name|Socket|Thread|Core|Architecture')</pre>
        </div>
        <div class="card">
            <h3>Memory</h3>
            <pre>$(cmd_out free -h)</pre>
            <pre>$(cmd_out sudo dmidecode -t memory 2>/dev/null | grep -E 'Size:|Type:|Speed:' | grep -v 'No Module' | head -n 6 || echo "dmidecode not available/root needed")</pre>
        </div>
    </div>
    
    <h3>Storage & Disks</h3>
    <pre>$(cmd_out lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL,STATE)</pre>
    <pre>$(cmd_out df -hT --exclude-type=tmpfs --exclude-type=devtmpfs)</pre>

    <div class="grid">
        <div class="card">
            <h3>RAID Status</h3>
            <pre>$( [ -f /proc/mdstat ] && cat /proc/mdstat || echo "No software RAID detected" )</pre>
        </div>
        <div class="card">
            <h3>SMART Status (Summary)</h3>
            <pre>$(
              if command -v smartctl >/dev/null; then
                for d in $(lsblk -d -n -o NAME | grep -v loop); do
                  echo "--- /dev/$d ---"
                  sudo smartctl -H "/dev/$d" 2>/dev/null | grep -v "smartctl" || echo "No SMART data"
                done
              else
                echo "smartctl not installed"
              fi
            )</pre>
        </div>
    </div>

    <!-- SOFTWARE -->
    <h2>2. Software & Services</h2>
    <div class="grid">
        <div class="card">
            <h3>OS Info</h3>
            <pre>$(cmd_out lsb_release -a 2>/dev/null || cat /etc/os-release)</pre>
        </div>
        <div class="card">
            <h3>Critical Services</h3>
            <table>
                <tr><th>Service</th><th>Status</th><th>Enabled</th></tr>
EOF

# Service loop
for svc in ssh smbd nmbd fail2ban ufw docker nginx apache2; do
    if systemctl list-unit-files "$svc.service" >/dev/null 2>&1; then
        STATUS=$(systemctl is-active "$svc" 2>/dev/null || echo "unknown")
        ENABLED=$(systemctl is-enabled "$svc" 2>/dev/null || echo "unknown")
        COLOR="status-inactive"
        [ "$STATUS" = "active" ] && COLOR="status-active"
        echo "<tr><td>$svc</td><td class='$COLOR'>$STATUS</td><td>$ENABLED</td></tr>" >> "$REPORT_FILE"
    fi
done

cat >> "$REPORT_FILE" <<EOF
            </table>
        </div>
    </div>

    <!-- SECURITY -->
    <h2>3. Security Configuration</h2>
    <div class="grid">
        <div class="card">
            <h3>Open Ports (Listen)</h3>
            <pre>$(cmd_out ss -tulnp | head -n 20)</pre>
        </div>
        <div class="card">
            <h3>Firewall (UFW)</h3>
            <pre>$(cmd_out sudo ufw status numbered 2>/dev/null || echo "UFW not available/root needed")</pre>
        </div>
    </div>
    
    <h3>SSH Config (Active)</h3>
    <pre>$(cmd_out sudo sshd -T 2>/dev/null | grep -E 'permitrootlogin|passwordauthentication|port|allowusers|protocol' || echo "Cannot read sshd config")</pre>

    <h3>Fail2Ban Jails</h3>
    <pre>$(cmd_out sudo fail2ban-client status 2>/dev/null || echo "Fail2Ban not running/installed")</pre>

    <!-- LOGS -->
    <h2>4. Recent Activity</h2>
    <div class="grid">
        <div class="card">
            <h3>Auth Log (Last 10)</h3>
            <pre>$(tail -n 10 /var/log/auth.log 2>/dev/null || echo "Cannot read /var/log/auth.log")</pre>
        </div>
        <div class="card">
            <h3>Samba Log (Last 10)</h3>
            <pre>$(tail -n 10 /var/log/samba/log.smbd 2>/dev/null || echo "Cannot read Samba logs")</pre>
        </div>
    </div>

    <div class="footer">
        Generated by system_report.sh
    </div>
</div>
</body>
</html>
EOF

log "Report generated: $REPORT_FILE"

if [ "$OPEN_REPORT" = true ]; then
    if command -v xdg-open >/dev/null; then
        xdg-open "$REPORT_FILE"
    else
        warn "xdg-open not found, cannot open report automatically."
    fi
fi

exit 0
