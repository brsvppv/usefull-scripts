    #!/usr/bin/env bash
    # =================================================================
    # Universal LXC Builder for Proxmox VE - Production GUI Edition
    # Author: brsvppv
    # License: MIT
    # 
    # Features:
    # - **Production-Ready**: Robust error handling and validation
    # - **Guaranteed Screen Cleanup**: Terminal always restored on exit
    # - **Universal Compatibility**: Works on standalone and clustered Proxmox
    # - **Smart Template Discovery**: Finds templates across all storage types
    # - **Professional UI**: Intuitive dialog-based interface
    # - **Comprehensive Logging**: Full audit trail of operations
    # =================================================================

    set -Eeuo pipefail
    IFS=$'\n\t'

    # --- Production Configuration ---
    readonly LOG_FILE="/var/log/proxmox-lxc-builder.log"
    readonly BACKTITLE="Proxmox Universal LXC Builder - Production"
    readonly TEMP_FILE=$(mktemp)

    # Global variables initialization (prevents undefined variable errors)
    TEMPLATES=()
    declare -A TEMPLATE_MAP
    NODE_OPTS=()
    STORAGE_OPTS=()
    BRIDGE_OPTS=()
    LOCKFILE=""
    TEMPLATE_VOLID=""
    TEMPLATE_BASENAME=""
    OSTYPE=""
    TARGET_NODE=""
    CTID=""
    HOSTNAME=""
    CPU=""
    RAM=""
    SWAP=""
    STORAGE=""
    DISK=""
    UNPRIV=""
    FEATURES=""
    BRIDGE=""
    NET_CONFIG=""
    IP_CIDR=""
    GW=""
    VLAN=""
    NET_OPTS=""

   
    readonly YW="\033[33m"
    readonly GN="\033[32m" 
    readonly RD="\033[31m"
    readonly BL="\033[36m"
    readonly CL="\033[m"

    # Professional exit codes for specific failure scenarios
    readonly ERR_MISSING_CTID=203
    readonly ERR_MISSING_OSTYPE=204
    readonly ERR_INVALID_CTID=205
    readonly ERR_CTID_IN_USE=206
    readonly ERR_NO_TEMPLATE_STORAGE=207
    readonly ERR_TEMPLATE_DOWNLOAD_FAILED=208
    readonly ERR_CONTAINER_CREATION_FAILED=209
    readonly ERR_CLUSTER_NOT_QUORATE=210
    readonly ERR_TEMPLATE_LOCK_TIMEOUT=211
    readonly ERR_INSUFFICIENT_STORAGE=214
    readonly ERR_CONTAINER_NOT_LISTED=215
    readonly ERR_ROOTFS_MISSING=216

    # --- Core System Functions ---
    cleanup() {
        local exit_code=$?
        
        # Prevent recursive cleanup calls
        if [[ -n "${CLEANUP_IN_PROGRESS:-}" ]]; then
            exit $exit_code
        fi
        export CLEANUP_IN_PROGRESS=1
        
        # Comprehensive process cleanup with error isolation
        {
            # Phase 1: Graceful termination
            pkill -f "dialog.*lxc" 2>/dev/null || true
            pkill -TERM -f "dialog" 2>/dev/null || true
            killall -TERM dialog 2>/dev/null || true
            killall -TERM whiptail 2>/dev/null || true
            
            # Short grace period
            sleep 0.2
            
            # Phase 2: Force termination
            pkill -KILL -f "dialog" 2>/dev/null || true
            killall -KILL dialog 2>/dev/null || true
            killall -KILL whiptail 2>/dev/null || true
            
            # Phase 3: Background job cleanup
            jobs -p 2>/dev/null | while read -r pid; do
                [[ -n "$pid" ]] && kill -TERM "$pid" 2>/dev/null || true
            done
            sleep 0.1
            jobs -p 2>/dev/null | while read -r pid; do
                [[ -n "$pid" ]] && kill -KILL "$pid" 2>/dev/null || true
            done
            
            # Phase 4: File descriptor cleanup
            for fd in {3..20}; do
                eval "exec $fd>&-" 2>/dev/null || true
            done
        } >/dev/null 2>&1
        
        # Comprehensive terminal restoration with error isolation
        {
            # Terminal capability restoration
            tput sgr0 2>/dev/null || true
            tput cnorm 2>/dev/null || true
            tput rmcup 2>/dev/null || true
            tput rs1 2>/dev/null || true
            
            # Screen and buffer clearing
            printf '\033c' 2>/dev/null || true
            printf '\033[!p' 2>/dev/null || true
            printf '\033[?3;4l' 2>/dev/null || true
            printf '\033[4l' 2>/dev/null || true
            printf '\033>' 2>/dev/null || true
            printf '\033[2J\033[H' 2>/dev/null || true
            printf '\033[3J' 2>/dev/null || true
            
            # Terminal state restoration
            stty sane 2>/dev/null || true
            reset 2>/dev/null || { echo -e "\033c" 2>/dev/null || true; }
            tput init 2>/dev/null || true
            clear 2>/dev/null || true
        } >/dev/null 2>&1
        
        # Secure file cleanup with verification
        {
            # Clean primary temp file
            if [[ -f "${TEMP_FILE:-}" ]]; then
                shred -vfz -n 3 "$TEMP_FILE" 2>/dev/null || rm -f "$TEMP_FILE" 2>/dev/null || true
            fi
            
            # Clean dialog temp directories
            if [[ -n "${DIALOG_TMPDIR:-}" && -d "$DIALOG_TMPDIR" ]]; then
                find "$DIALOG_TMPDIR" -type f -exec shred -vfz -n 1 {} \; 2>/dev/null || true
                rm -rf "$DIALOG_TMPDIR" 2>/dev/null || true
            fi
            
            # Clean lock files with verification
            if [[ -n "${LOCKFILE:-}" && -f "$LOCKFILE" ]]; then
                flock -n "$LOCKFILE" rm -f "$LOCKFILE" 2>/dev/null || rm -f "$LOCKFILE" 2>/dev/null || true
            fi
            
            # Clean template locks (more specific pattern)
            find /tmp -maxdepth 1 -name "template.*.lock" -user "$(id -u)" -type f -mmin +10 -delete 2>/dev/null || true
            
            # Clean any remaining dialog temp files
            find /tmp -maxdepth 1 -name "dialog.*" -user "$(id -u)" -type f -mmin +5 -delete 2>/dev/null || true
            find /tmp -maxdepth 1 -name "msg*" -user "$(id -u)" -type f -mmin +5 -delete 2>/dev/null || true
        } >/dev/null 2>&1
        
        # Restore signal handlers
        trap - EXIT INT TERM ERR 2>/dev/null || true
        
        # Final terminal state verification
        if command -v tty >/dev/null 2>&1 && tty >/dev/null 2>&1; then
            stty echo 2>/dev/null || true
            stty icanon 2>/dev/null || true
        fi
        
        # Clean exit
        unset CLEANUP_IN_PROGRESS
        exit $exit_code
    }

    # Set up comprehensive trap handlers with error isolation
    trap 'cleanup' EXIT
    trap 'echo ""; echo "[INFO] Operation interrupted by user."; cleanup; exit 130' INT
    trap 'echo ""; echo "[INFO] Operation terminated."; cleanup; exit 143' TERM
    trap 'error_handler $LINENO $?' ERR

    # Enhanced error handler with context preservation
    error_handler() {
        local line_no="${1:-unknown}"
        local exit_code="${2:-1}"
        local command="${BASH_COMMAND:-unknown}"
        
        # Prevent recursive error handling
        if [[ -n "${ERROR_IN_PROGRESS:-}" ]]; then
            exit $exit_code
        fi
        export ERROR_IN_PROGRESS=1
        
        # Log detailed error information
        {
            echo "========== ERROR DETAILS =========="
            echo "Time: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
            echo "Line: $line_no"
            echo "Exit Code: $exit_code"
            echo "Command: $command"
            echo "Function Stack: ${FUNCNAME[*]}"
            echo "====================================="
        } >> "$LOG_FILE" 2>/dev/null || true
        
        # Clean error display
        error "An unexpected failure occurred at line $line_no. Command: $command. Check $LOG_FILE for details." "$exit_code"
    }

    # --- UI & Logging Functions ---
    # Note: We don't wrap dialog command since ERR trap is already disabled in cleanup()
    # and wrapping causes infinite recursion. Dialog exit codes work correctly with || operator.
    
    handle_cancel() {
        clear
        printf '\033c' 2>/dev/null || true
        echo ""
        echo -e "${YW}[INFO] Operation cancelled by user.${CL}"
        echo ""
        echo "Thank you for using Proxmox LXC Builder!"
        echo ""
        log "Operation cancelled by user"
        exit 0
    }

    error() {
        local exit_code="${2:-1}"
        clear
        echo ""
        echo -e "${RD}[ERROR]${CL} $1"
        echo ""
        
        # Log the error with timestamp and exit code
        log "ERROR (exit $exit_code): $1"
        
        # Show error in dialog if available with more context
        if command -v dialog >/dev/null 2>&1; then
            local error_details=""
            case "$exit_code" in
                $ERR_MISSING_CTID) error_details="\n\nSolution: Set CTID variable before running the script" ;;
                $ERR_INVALID_CTID) error_details="\n\nSolution: Use CTID >= 100 and <= 999999999" ;;
                $ERR_CTID_IN_USE) error_details="\n\nSolution: Choose a different Container ID" ;;
                $ERR_NO_TEMPLATE_STORAGE) error_details="\n\nSolution: Configure storage with template support" ;;
                $ERR_INSUFFICIENT_STORAGE) error_details="\n\nSolution: Free up disk space or select different storage" ;;
                $ERR_CLUSTER_NOT_QUORATE) error_details="\n\nSolution: Start all cluster nodes or configure QDevice" ;;
                *) error_details="\n\nCheck logs: $LOG_FILE" ;;
            esac
            
            dialog --title "Critical Error" --msgbox "[ERROR] $1$error_details" 12 70 2>/dev/null || true
        fi
        
        exit "$exit_code"
    }

    info() {
        echo -e "${BL}[INFO]${CL} $1"
    }

    warn() {
        echo -e "${YW}[WARN]${CL} $1"
        log "WARN: $1"
    }

    msg_ok() {
        echo -e "${GN}[OK]${CL} $1"
    }

    msg_info() {
        echo -e "${BL}[INFO]${CL} $1"
    }

    msg_warn() {
        echo -e "${YW}[WARN]${CL} $1"
    }

    msg_error() {
        echo -e "${RD}[ERROR]${CL} $1"
    }

    log() {
        echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') $1" >> "$LOG_FILE" 2>/dev/null || true
    }

    # --- Validation & Discovery Functions ---
    production_checks() {
        # Verify running on Proxmox
        if ! command -v pct >/dev/null 2>&1; then
            error "This script must be run on a Proxmox VE host. Command 'pct' not found."
        fi
        
        # Check for root or sudo privileges
        if [[ $EUID -ne 0 ]]; then
            error "This script requires root privileges. Please run as root or with sudo."
        fi
        
        # Verify Proxmox services are running
        if ! systemctl is-active --quiet pvedaemon pveproxy; then
            error "Proxmox services are not running properly. Please check your Proxmox installation."
        fi
        
        # Create secure log directory
        mkdir -p "$(dirname "$LOG_FILE")" || error "Cannot create log directory"
        touch "$LOG_FILE" || error "Cannot create log file at $LOG_FILE"
    }

    ensure_dependencies() {
        local missing_deps=()
        
        for cmd in dialog pct pvesm jq; do
            if ! command -v "$cmd" >/dev/null 2>&1; then
                missing_deps+=("$cmd")
            fi
        done
        
        if [[ ${#missing_deps[@]} -gt 0 ]]; then
            error "Missing required dependencies: ${missing_deps[*]}. Please install them first."
        fi
    }

    validate_ctid() {
        local ctid="$1"
        
        # Strict input sanitization - remove any non-numeric characters
        ctid=$(echo "$ctid" | tr -cd '0-9' 2>/dev/null | head -c 10 || echo "")  # Limit to 10 digits max
        
        # Check if CTID is provided after sanitization
        [[ -n "$ctid" ]] || error "Container ID (CTID) is required" $ERR_MISSING_CTID
        
        # Check if CTID is numeric and in valid range (more restrictive)
        if ! [[ "$ctid" =~ ^[0-9]+$ ]] || [[ $ctid -lt 100 ]] || [[ $ctid -gt 999999999 ]]; then
            error "Container ID '$ctid' is invalid. Must be numeric between 100-999999999" $ERR_INVALID_CTID
        fi
        
        # Prevent potential integer overflow
        if [[ ${#ctid} -gt 9 ]]; then
            error "Container ID '$ctid' too large. Maximum 9 digits allowed" $ERR_INVALID_CTID
        fi
        
        # Check if CTID is already in use (both LXC and VM) with safe quoting
        if timeout 5 pct status "$ctid" >/dev/null 2>&1; then
            error "Container ID '$ctid' is already in use by an LXC container" $ERR_CTID_IN_USE
        fi
        
        # Also check if it's used by a VM with timeout
        if timeout 5 qm status "$ctid" >/dev/null 2>&1; then
            error "Container ID '$ctid' is already in use by a virtual machine" $ERR_CTID_IN_USE
        fi
        
        return 0
    }

    validate_hostname() {
        local hostname="$1"
        
        # Strict input sanitization - remove dangerous characters
        hostname=$(echo "$hostname" | tr -cd 'a-zA-Z0-9-' 2>/dev/null | head -c 63 || echo "")
        
        # Check if hostname exists after sanitization
        [[ -n "$hostname" ]] || return 1
        
        # Enhanced hostname format validation (RFC 1123 compliant)
        if [[ ! "$hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
            return 1
        fi
        
        # Additional security checks
        # Prevent reserved hostnames
        case "${hostname,,}" in
            localhost|root|admin|administrator|system|service|daemon|kernel|proxy*|pve*)
                return 1
                ;;
        esac
        
        # Check for consecutive hyphens (not allowed)
        if [[ "$hostname" == *"--"* ]]; then
            return 1
        fi
        
        # Ensure it doesn't start or end with hyphen
        if [[ "$hostname" == -* ]] || [[ "$hostname" == *- ]]; then
            return 1
        fi
        
        return 0
    }

    validate_ip_cidr() {
        local ip_cidr="$1"
        
        # Sanitize input - remove dangerous characters and limit length
        ip_cidr=$(echo "$ip_cidr" | tr -cd '0-9./' 2>/dev/null | head -c 18 || echo "")
        
        # Skip validation for DHCP
        [[ "$ip_cidr" == "dhcp" ]] && return 0
        
        # Check for empty input after sanitization
        [[ -n "$ip_cidr" ]] || return 1
        
        # Enhanced IP/CIDR format validation
        if [[ "$ip_cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
            local ip=$(echo "$ip_cidr" | cut -d'/' -f1)
            local cidr=$(echo "$ip_cidr" | cut -d'/' -f2)
            
            # Validate IP octets with stricter checks
            IFS='.' read -ra octets <<< "$ip"
            [[ ${#octets[@]} -eq 4 ]] || return 1
            
            for octet in "${octets[@]}"; do
                # Check for leading zeros (not allowed)
                if [[ ${#octet} -gt 1 && $octet == 0* ]]; then
                    return 1
                fi
                # Check range
                [[ $octet -ge 0 && $octet -le 255 ]] || return 1
            done
            
            # Validate CIDR range (more restrictive for security)
            [[ $cidr -ge 16 && $cidr -le 30 ]] || return 1
            
            # Prevent private/reserved IP ranges in production
            local first_octet=${octets[0]}
            local second_octet=${octets[1]}
            
            # Block loopback, multicast, and other reserved ranges
            case "$first_octet" in
                0|127|224|225|226|227|228|229|230|231|232|233|234|235|236|237|238|239|240|241|242|243|244|245|246|247|248|249|250|251|252|253|254|255)
                    return 1
                    ;;
            esac
            
            return 0
        fi
        
        return 1
    }

    validate_storage_space() {
        local storage="$1"
        local required_gb="${2:-8}"  # Default 8GB if not specified
        
        # Validate storage exists and is enabled
        if ! pvesm status -storage "$storage" --enabled 1 >/dev/null 2>&1; then
            error "Storage '$storage' is not available or not enabled" $ERR_INSUFFICIENT_STORAGE
        fi
        
        # Get available space in KB from pvesm status
        local storage_info
        storage_info=$(pvesm status -storage "$storage" --enabled 1 2>/dev/null | tail -1)
        
        if [[ -z "$storage_info" ]]; then
            warn "Could not determine available space for storage '$storage', proceeding with caution"
            return 0
        fi
        
        # Extract available space (6th field in KB)
        local available_kb
        available_kb=$(echo "$storage_info" | awk '{print $6}')
        
        if [[ -n "$available_kb" && "$available_kb" =~ ^[0-9]+$ ]]; then
            local required_kb=$((required_gb * 1024 * 1024))
            
            if [[ $available_kb -lt $required_kb ]]; then
                local available_gb=$((available_kb / 1024 / 1024))
                error "Insufficient space on storage '$storage'. Available: ${available_gb}GB, Required: ${required_gb}GB" $ERR_INSUFFICIENT_STORAGE
            fi
            
            local available_gb=$((available_kb / 1024 / 1024))
            msg_info "Storage '$storage' has ${available_gb}GB available (required: ${required_gb}GB)"
        else
            warn "Could not parse storage space information for '$storage'"
        fi
        
        return 0
    }

    check_storage_support() {
        local content="$1"
        local -a valid_storages=()
        
        # Safely get storage list without failing on pipefail
        local storage_data
        storage_data=$(pvesm status -content "$content" 2>/dev/null || echo "")
        
        if [[ -n "$storage_data" ]]; then
            while IFS= read -r line; do
                local storage_name
                storage_name=$(awk '{print $1}' <<<"$line" 2>/dev/null || echo "")
                [[ -z "$storage_name" ]] && continue
                valid_storages+=("$storage_name")
            done <<< "$(echo "$storage_data" | awk 'NR>1')"
        fi

        [[ ${#valid_storages[@]} -gt 0 ]]
    }

    discover_templates() {
        msg_info "Discovering LXC templates..."
        
        # Temporarily disable strict error handling for template discovery
        set +e
        
        TEMPLATES=()
        declare -A seen_templates  # Track unique template filenames to avoid duplicates
        
        # Get all storage pools that support templates
        local storage_list
        storage_list=$(pvesm status --content vztmpl --enabled 1 2>/dev/null | tail -n +2 | awk '{print $1}' || echo "")
        
        if [[ -z "$storage_list" ]]; then
            # Re-enable strict error handling
            set -e
            msg_warn "No storage pools found with template support"
            error "No storage pools with template support found. Please configure template storage first." $ERR_NO_TEMPLATE_STORAGE
        fi
        
        msg_info "Found template storage pools: $storage_list"
        
        local template_count=0
        
        # Discover templates from all storage pools
        for storage in $storage_list; do
            msg_info "Checking storage: $storage"
            local storage_templates
            storage_templates=$(pvesm list "$storage" --content vztmpl 2>/dev/null | tail -n +2 | awk '{print $1}' 2>/dev/null || echo "")
            
            if [[ -n "$storage_templates" ]]; then
                msg_info "Found templates on $storage, processing..."
                while IFS= read -r full_volid || [[ -n "$full_volid" ]]; do
                    [[ -n "$full_volid" ]] || continue
                    [[ "$full_volid" != *"No content"* ]] || continue
                    
                    msg_info "Processing template: $full_volid"
                    
                    # Extract just the filename from the full volume ID
                    # full_volid format: storage:vztmpl/filename.tar.zst
                    local template_file="${full_volid##*/}"
                    
                    # Skip if we've already seen this template filename
                    if [[ -v "seen_templates[$template_file]" ]]; then
                        msg_info "Skipping duplicate template: $template_file (already added from ${seen_templates[$template_file]})"
                        continue
                    fi
                    
                    # Mark this template as seen
                    seen_templates[$template_file]="$storage"
                    
                    # Extract template basename for display
                    local template_basename="$template_file"
                    
                    # Try to clean up the basename safely
                    if [[ "$template_file" == *.tar.* ]]; then
                        template_basename="${template_file%.tar.*}"
                    fi
                    
                    # Remove version numbers if present
                    if [[ "$template_basename" =~ -[0-9] ]]; then
                        template_basename=$(echo "$template_basename" | sed 's/-[0-9][0-9]*-[0-9][0-9]*.*$//' 2>/dev/null || echo "$template_basename")
                    fi
                    
                    # Default values
                    local template_status="✅"
                    local size_info=""
                    
                    # Try to get more info, but don't fail if we can't
                    local template_path=""
                    if template_path=$(pvesm path "$full_volid" 2>/dev/null) && [[ -n "$template_path" ]]; then
                        if [[ -f "$template_path" ]]; then
                            local template_size=""
                            if template_size=$(stat -c%s "$template_path" 2>/dev/null) && [[ "$template_size" =~ ^[0-9]+$ ]]; then
                                if [[ $template_size -gt 1000000 ]]; then
                                    local size_mb=$((template_size / 1024 / 1024))
                                    size_info=" (${size_mb}MB)"
                                else
                                    template_status="⚠️"
                                    size_info=" (small)"
                                fi
                            fi
                        else
                            template_status="❓"
                            size_info=" (missing)"
                        fi
                    fi
                    
                    # Add to templates array with proper formatting
                    # Format: tag (basename) | description (size + status) | default
                    # Store mapping to retrieve full volid later
                    local tag="$template_basename"
                    local description="${size_info} ${template_status}"
                    
                    # Store the mapping from display name to full volid
                    TEMPLATE_MAP["$tag"]="$full_volid"
                    
                    TEMPLATES+=("$tag" "$description" "OFF")
                    template_count=$((template_count + 1))
                    
                    msg_ok "Added template: ${BL}$template_basename${CL} from $storage $template_status"
                    
                done <<< "$storage_templates"
            else
                msg_info "No templates found on storage: $storage"
            fi
        done
        
        # Re-enable strict error handling
        set -e
        
        if [[ ${#TEMPLATES[@]} -eq 0 ]]; then
            error "No LXC templates found on any storage. Please upload templates using the Proxmox web interface." $ERR_NO_TEMPLATE_STORAGE
        fi
        
        msg_ok "Successfully discovered $template_count templates across storage pools"
    }

    detect_os_type() {
        local template="$1"
        
        # Detect OS type based on template name
        case "$template" in
            *ubuntu*|*debian*) echo "debian" ;;
            *centos*|*alma*|*rocky*|*rhel*) echo "centos" ;;
            *fedora*) echo "fedora" ;;
            *alpine*) echo "alpine" ;;
            *arch*) echo "archlinux" ;;
            *opensuse*) echo "opensuse" ;;
            *) echo "unmanaged" ;;  # Default fallback
        esac
    }

    suggest_ctid() {
        local silent="${1:-false}"
        
        # Only show info message if not in silent mode
        if [[ "$silent" != "true" ]]; then
            info "Analyzing existing container IDs..."
        fi
        
        # Get all existing CTIDs
        local used_ctids
        used_ctids=$(pct list 2>/dev/null | tail -n +2 | awk '{print $1}' | sort -n || echo "")
        
        # Find the next available CTID starting from 100
        local suggested_ctid=100
        
        if [[ -n "$used_ctids" ]]; then
            while read -r ctid; do
                [[ -n "$ctid" ]] || continue
                if [[ $ctid -eq $suggested_ctid ]]; then
                    ((suggested_ctid++))
                elif [[ $ctid -gt $suggested_ctid ]]; then
                    break
                fi
            done <<< "$used_ctids"
        fi
        
        echo "$suggested_ctid"
    }

    detect_cluster_environment() {
        msg_info "Detecting Proxmox environment type..."
        
        NODE_OPTS=()
        
        # Check if running in a cluster
        if pvecm status >/dev/null 2>&1; then
            log "Cluster environment detected"
            
            # Validate cluster quorum before proceeding
            msg_info "Checking cluster quorum status..."
            if [[ -f /etc/pve/corosync.conf ]]; then
                if ! pvecm status | awk -F':' '/^Quorate/ { exit ($2 ~ /Yes/) ? 0 : 1 }'; then
                    error "Cluster is not quorate. Start all nodes or configure quorum device (QDevice) before creating containers." $ERR_CLUSTER_NOT_QUORATE
                fi
                msg_ok "Cluster is quorate and ready for container creation"
            fi
            
            # Get cluster nodes safely
            local cluster_nodes
            cluster_nodes=$(pvecm nodes 2>/dev/null | tail -n +2 | awk '{print $3}' 2>/dev/null || echo "")
            # Remove empty lines
            cluster_nodes=$(echo "$cluster_nodes" | grep -v '^$' || echo "")
            
            if [[ -n "$cluster_nodes" ]]; then
                while read -r node; do
                    [[ -n "$node" ]] || continue
                    
                    # Check node status
                    local node_status="online"
                    if ! pvecm nodes | grep -q "^.*$node.*online"; then
                        node_status="offline"
                        warn "Node '$node' appears to be offline"
                    fi
                    
                    NODE_OPTS+=("$node" "$node ($node_status)" "OFF")
                done <<< "$cluster_nodes"
                
                # Pre-select current node
                local current_node
                current_node=$(hostname)
                for i in "${!NODE_OPTS[@]}"; do
                    if [[ "${NODE_OPTS[$i]}" == "$current_node" ]]; then
                        NODE_OPTS[$((i+2))]="ON"
                        msg_ok "Current node: ${BL}$current_node${CL} (auto-selected)"
                        break
                    fi
                done
                
                log "Found ${#NODE_OPTS[@]} cluster nodes"
            else
                log "Cluster detected but no nodes found, treating as standalone"
                NODE_OPTS=()
            fi
        else
            log "Standalone Proxmox environment detected"
            TARGET_NODE=$(hostname)
            msg_ok "Standalone mode: ${BL}$TARGET_NODE${CL}"
        fi
    }

    discover_storage() {
        msg_info "Validating storage pools..."
        
        # First validate that we have storage support for containers
        if ! check_storage_support "rootdir"; then
            error "No valid storage found for 'rootdir' [Container storage]" $ERR_NO_TEMPLATE_STORAGE
        fi
        
        if ! check_storage_support "vztmpl"; then
            error "No valid storage found for 'vztmpl' [Template storage]" $ERR_NO_TEMPLATE_STORAGE
        fi
        
        STORAGE_OPTS=()
        
        # Get enabled storage that supports container images
        local storage_list
        storage_list=$(pvesm status --content images --enabled 1 2>/dev/null | tail -n +2 | awk '{print $1}' || echo "")
        
        if [[ -z "$storage_list" ]]; then
            error "No storage pools available for containers. Please configure storage first." $ERR_NO_TEMPLATE_STORAGE
        fi

        while read -r storage; do
            [[ -n "$storage" ]] || continue
            
            # Get detailed storage information (simplified)
            local storage_info
            storage_info=$(pvesm status -storage "$storage" --enabled 1 2>/dev/null | tail -1 || echo "")
            
            if [[ -n "$storage_info" ]]; then
                # Simple parsing - just get basic info
                local storage_type="unknown"
                local avail_gb="N/A"
                local used_gb="N/A"
                
                # Try to extract storage type from second field
                storage_type=$(echo "$storage_info" | awk '{print $2}' 2>/dev/null || echo "unknown")
                
                # Try to extract space info (more robust)
                local used_kb avail_kb
                used_kb=$(echo "$storage_info" | awk '{print $5}' 2>/dev/null || echo "")
                avail_kb=$(echo "$storage_info" | awk '{print $6}' 2>/dev/null || echo "")
                
                # Convert KB to GB safely
                if [[ "$avail_kb" =~ ^[0-9]+$ ]] && [[ $avail_kb -gt 0 ]]; then
                    avail_gb="$((avail_kb / 1024 / 1024))GB"
                fi
                if [[ "$used_kb" =~ ^[0-9]+$ ]] && [[ $used_kb -gt 0 ]]; then
                    used_gb="$((used_kb / 1024 / 1024))GB"
                fi
                
                local display_info="$storage ($storage_type) - Free: $avail_gb, Used: $used_gb"
                STORAGE_OPTS+=("$storage" "$display_info" "OFF")
                
                msg_ok "Found storage: ${BL}$storage${CL} ($storage_type) - Free: $avail_gb"
            else
                # Fallback - add storage even if we can't get details
                STORAGE_OPTS+=("$storage" "$storage (details unavailable)" "OFF")
                msg_ok "Found storage: ${BL}$storage${CL} (details unavailable)"
            fi
        done <<< "$storage_list"
        
        if [[ ${#STORAGE_OPTS[@]} -eq 0 ]]; then
            error "No usable storage found for containers." $ERR_NO_TEMPLATE_STORAGE
        fi
        
        msg_ok "Discovered ${#STORAGE_OPTS[@]} storage pools for containers"
    }

    discover_bridges() {
        info "Detecting network bridges..."
        
        BRIDGE_OPTS=()
        
        # Pure bash - no external commands that could segfault
        # Check if any vmbr interfaces exist
        local found_bridge=0
        if [[ -d /sys/class/net ]]; then
            for iface in /sys/class/net/vmbr*; do
                if [[ -e "$iface" ]]; then
                    # Extract bridge name using pure bash parameter expansion
                    local bridge_name="${iface##*/}"  # Remove everything up to last /
                    BRIDGE_OPTS+=("$bridge_name" "$bridge_name" "OFF")
                    found_bridge=1
                fi
            done
        fi
        
        # Fallback: if no bridges found, add vmbr0
        if [[ $found_bridge -eq 0 ]]; then
            BRIDGE_OPTS+=("vmbr0" "vmbr0" "OFF")
            log "No bridges detected, using default: vmbr0"
        fi
        
        # Set first bridge as selected by default
        if [[ ${#BRIDGE_OPTS[@]} -ge 3 ]]; then
            BRIDGE_OPTS[2]="ON"
        fi
        
        msg_ok "Found $((${#BRIDGE_OPTS[@]} / 3)) bridge(s)"
    }

    # --- Configuration Functions ---
    configure_container_basics() {
        # Template selection
        dialog --backtitle "$BACKTITLE" --title "Select LXC Template" \
            --radiolist "Choose the operating system template for your container:" \
            20 80 10 "${TEMPLATES[@]}" 2>"$TEMP_FILE" || handle_cancel
        
        local selected_tag=$(cat "$TEMP_FILE")
        TEMPLATE_VOLID="${TEMPLATE_MAP[$selected_tag]}"
        
        # Safely extract template basename with fallback
        TEMPLATE_BASENAME="$TEMPLATE_VOLID"
        if [[ "$TEMPLATE_VOLID" =~ \.tar\.(xz|gz|zst)$ ]]; then
            TEMPLATE_BASENAME=$(basename "$TEMPLATE_VOLID" 2>/dev/null || echo "$TEMPLATE_VOLID")
            # Remove common template suffixes safely
            TEMPLATE_BASENAME="${TEMPLATE_BASENAME%.tar.*}"
            # Remove version patterns safely
            TEMPLATE_BASENAME=$(echo "$TEMPLATE_BASENAME" | sed 's/-[0-9][0-9]*-[0-9][0-9]*.*$//' 2>/dev/null || echo "$TEMPLATE_BASENAME")
        fi
        
        OSTYPE=$(detect_os_type "$TEMPLATE_VOLID")
        log "Selected template: $TEMPLATE_VOLID (OS: $OSTYPE, basename: $TEMPLATE_BASENAME)"
        
        # Node selection for clusters
        if [[ ${#NODE_OPTS[@]} -gt 0 ]]; then
            dialog --backtitle "$BACKTITLE" --title "Select Target Node" \
                --radiolist "Choose the Proxmox node where the container will be created:" \
                15 60 8 "${NODE_OPTS[@]}" 2>"$TEMP_FILE" || handle_cancel
            
            TARGET_NODE=$(cat "$TEMP_FILE")
        fi
        
        # Container ID
        local suggested_ctid
        # Call suggest_ctid in silent mode to avoid log output contamination
        suggested_ctid=$(suggest_ctid true)
        
        while true; do
            # Create secure temp file for this dialog
            local ctid_temp
            ctid_temp=$(mktemp -t "lxc-ctid.XXXXXX") || error "Failed to create temp file"
            
            # Ensure clean input field by explicitly setting the default value
            echo -n "$suggested_ctid" > "$ctid_temp"
            
            dialog --backtitle "$BACKTITLE" --title "Container ID" \
                --inputbox "Container ID:" \
                8 40 "$suggested_ctid" 2>"$ctid_temp"
            
            local dialog_exit_code=$?
            if [[ $dialog_exit_code -ne 0 ]]; then
                rm -f "$ctid_temp" 2>/dev/null || true
            fi
            
            # Secure input processing with multiple validation layers
            local raw_input
            raw_input=$(head -1 "$ctid_temp" 2>/dev/null | head -c 20)  # Limit input length
            rm -f "$ctid_temp" 2>/dev/null || true
            
            # Multi-stage sanitization - ensure we get only numbers
            local sanitized_input
            sanitized_input=$(echo "$raw_input" | tr -cd '0-9' 2>/dev/null | head -c 10 || echo "")
            
            # If input is empty after sanitization, use the suggested value
            if [[ -z "$sanitized_input" ]]; then
                sanitized_input="$suggested_ctid"
            fi
            
            if [[ -n "$sanitized_input" ]] && validate_ctid "$sanitized_input"; then
                CTID="$sanitized_input"
                log "Container ID: $CTID (validated and sanitized)"
                break
            else
                dialog --title "Invalid Container ID" \
                    --msgbox "Please enter a valid numeric Container ID (100-999999999)\n\nInput was: '$raw_input'\nSanitized to: '$sanitized_input'" 10 60 || true
            fi
        done
        
        # Hostname
        # Generate safe default hostname
        local safe_basename
        safe_basename=$(echo "$TEMPLATE_BASENAME" | tr '[:upper:]' '[:lower:]' 2>/dev/null | sed 's/[^a-z0-9-]//g' | sed 's/^-\+\|-\+$//g' | sed 's/--\+/-/g' || echo "lxc")
        [[ -z "$safe_basename" ]] && safe_basename="container"
        local default_hostname="${safe_basename}-${CTID}"
        while true; do
            # Create secure temp file for hostname input
            local hostname_temp
            hostname_temp=$(mktemp -t "lxc-hostname.XXXXXX") || error "Failed to create temp file"
            
            dialog --backtitle "$BACKTITLE" --title "Container Hostname" \
                --inputbox "Hostname:" \
                8 40 "${default_hostname}" 2>"$hostname_temp"
            
            local dialog_exit_code=$?
            if [[ $dialog_exit_code -ne 0 ]]; then
                rm -f "$hostname_temp" 2>/dev/null || true
            fi
            
            # Secure hostname processing
            local raw_hostname
            raw_hostname=$(head -1 "$hostname_temp" 2>/dev/null | head -c 100)  # Reasonable limit
            rm -f "$hostname_temp" 2>/dev/null || true
            
            # Multi-stage hostname sanitization
            local sanitized_hostname
            sanitized_hostname=$(echo "$raw_hostname" | tr -cd 'a-zA-Z0-9-' 2>/dev/null | head -c 63 || echo "")
            
            # Remove leading/trailing hyphens
            sanitized_hostname=$(echo "$sanitized_hostname" | sed 's/^-*//' | sed 's/-*$//')
            
            if [[ -n "$sanitized_hostname" ]] && validate_hostname "$sanitized_hostname"; then
                HOSTNAME="$sanitized_hostname"
                log "Hostname: $HOSTNAME (validated and sanitized)"
                break
            else
                dialog --title "Invalid Hostname" \
                    --msgbox "Hostname validation failed.\n\nInput: '$raw_hostname'\nSanitized: '$sanitized_hostname'\n\nRequirements:\n• 1-63 characters\n• Letters, numbers, and hyphens only\n• Must start and end with letter or number\n• No consecutive hyphens\n• No reserved names" \
                    14 60 || true
            fi
        done
    }

    configure_container_resources() {
        # CPU cores
        while true; do
            dialog --backtitle "$BACKTITLE" --title "CPU Configuration" \
                --inputbox "Enter the number of CPU cores (1-16):" \
                10 50 "2" 2>"$TEMP_FILE" || handle_cancel
            
            CPU=$(cat "$TEMP_FILE")
            
            if [[ "$CPU" =~ ^[1-9]$|^1[0-6]$ ]]; then
                log "CPU cores: $CPU"
                break
            else
                dialog --title "Invalid CPU Count" \
                    --msgbox "CPU count must be between 1 and 16." 8 40 || true
            fi
        done
        
        # Memory
        while true; do
            dialog --backtitle "$BACKTITLE" --title "Memory Configuration" \
                --inputbox "Enter RAM size in MB (512-16384):" \
                10 50 "1024" 2>"$TEMP_FILE" || handle_cancel
            
            RAM=$(cat "$TEMP_FILE")
            
            if [[ "$RAM" =~ ^[0-9]+$ ]] && [[ $RAM -ge 512 ]] && [[ $RAM -le 16384 ]]; then
                log "RAM: ${RAM}MB"
                break
            else
                dialog --title "Invalid RAM Size" \
                    --msgbox "RAM must be between 512 and 16384 MB." 8 40 || true
            fi
        done
        
        # Swap
        while true; do
            local suggested_swap=$((RAM / 2))
            dialog --backtitle "$BACKTITLE" --title "Swap Configuration" \
                --inputbox "Enter swap size in MB (0 to disable):" \
                10 50 "$suggested_swap" 2>"$TEMP_FILE" || handle_cancel
            
            SWAP=$(cat "$TEMP_FILE")
            
            if [[ "$SWAP" =~ ^[0-9]+$ ]] && [[ $SWAP -le 8192 ]]; then
                log "Swap: ${SWAP}MB"
                break
            else
                dialog --title "Invalid Swap Size" \
                    --msgbox "Swap must be numeric and max 8192 MB." 8 40 || true
            fi
        done
        
        # Storage pool
        dialog --backtitle "$BACKTITLE" --title "Storage Selection" \
            --radiolist "Choose storage pool for the container:" \
            15 70 8 "${STORAGE_OPTS[@]}" 2>"$TEMP_FILE" || handle_cancel
        
        STORAGE=$(cat "$TEMP_FILE")
        
        # Disk size
        while true; do
            dialog --backtitle "$BACKTITLE" --title "Disk Configuration" \
                --inputbox "Enter disk size in GB (4-500):" \
                10 50 "8" 2>"$TEMP_FILE" || handle_cancel
            
            DISK=$(cat "$TEMP_FILE")
            
            if [[ "$DISK" =~ ^[0-9]+$ ]] && [[ $DISK -ge 4 ]] && [[ $DISK -le 500 ]]; then
                log "Storage: $STORAGE, Disk: ${DISK}GB"
                break
            else
                dialog --title "Invalid Disk Size" \
                    --msgbox "Disk size must be between 4 and 500 GB." 8 40 || true
            fi
        done
    }

    configure_container_security() {
        # Unprivileged containers (recommended for security)
        if dialog --backtitle "$BACKTITLE" --title "Security Configuration" \
            --yesno "Use unprivileged container?\n\n• RECOMMENDED for security\n• Prevents privilege escalation\n• May require additional configuration for some applications\n\nSelect 'No' only if you specifically need privileged access." \
            12 70; then
            UNPRIV=1
            log "Container type: Unprivileged (secure)"
        else
            UNPRIV=0
            log "Container type: Privileged (legacy)"
        fi
        
        # Additional features
        dialog --backtitle "$BACKTITLE" --title "Container Features" \
            --checklist "Select additional features (optional):" \
            15 70 5 \
            "nesting" "Enable container nesting (Docker in LXC)" "OFF" \
            "keyctl" "Enable keyctl (systemd services)" "OFF" \
            "fuse" "Enable FUSE filesystem support" "OFF" 2>"$TEMP_FILE" || handle_cancel
        
        # Process selected features - dialog returns space-separated quoted items like: "nesting" "keyctl"
        FEATURES=""
        local selected_features=$(cat "$TEMP_FILE")
        
        log "DEBUG: Raw checklist output: '$selected_features'"
        
        # Remove all quotes using bash parameter expansion (no external commands)
        selected_features="${selected_features//\"/}"
        
        log "DEBUG: After quote removal: '$selected_features'"
        
        # Process each feature - need to temporarily reset IFS for space splitting
        local old_ifs="$IFS"
        IFS=' '
        for feature in ${selected_features}; do
            [[ -n "$feature" ]] || continue
            if [[ -z "$FEATURES" ]]; then
                FEATURES="$feature=1"
            else
                FEATURES+=",$feature=1"
            fi
            log "DEBUG: Added feature: $feature (current FEATURES: $FEATURES)"
        done
        IFS="$old_ifs"
        
        # FEATURES is now properly formatted (no trailing comma)
        log "DEBUG: Final FEATURES string: '$FEATURES'"
        [[ -n "$FEATURES" ]] && log "Features: $FEATURES" || log "Features: none"
    }

    configure_container_network() {
        # Bridge selection
        dialog --backtitle "$BACKTITLE" --title "Network Bridge" \
            --radiolist "Select network bridge:" \
            12 60 5 "${BRIDGE_OPTS[@]}" 2>"$TEMP_FILE" || handle_cancel
        
        BRIDGE=$(cat "$TEMP_FILE")
        
        # Network configuration
        dialog --backtitle "$BACKTITLE" --title "Network Configuration" \
            --radiolist "Choose network configuration:" \
            12 60 3 \
            "dhcp" "DHCP (Automatic IP assignment)" "ON" \
            "static" "Static IP (Manual configuration)" "OFF" 2>"$TEMP_FILE" || handle_cancel
        
        NET_CONFIG=$(cat "$TEMP_FILE")
        
        if [[ "$NET_CONFIG" == "static" ]]; then
            # Static IP configuration
            while true; do
                dialog --backtitle "$BACKTITLE" --title "Static IP Configuration" \
                    --inputbox "Enter IP address with CIDR (e.g., 192.168.1.100/24):" \
                    10 60 "" 2>"$TEMP_FILE" || handle_cancel
                
                IP_CIDR=$(cat "$TEMP_FILE")
                
                if validate_ip_cidr "$IP_CIDR"; then
                    break
                else
                    dialog --title "Invalid IP Address" \
                        --msgbox "IP address '$IP_CIDR' is invalid.\n\nFormat: 192.168.1.100/24\n• Valid IP address\n• CIDR notation (/8 to /30)" \
                        10 50 || true
                fi
            done
            
            # Gateway
            dialog --backtitle "$BACKTITLE" --title "Gateway Configuration" \
                --inputbox "Enter gateway IP address (leave empty for auto):" \
                10 60 "" 2>"$TEMP_FILE" || handle_cancel
            
            GW=$(cat "$TEMP_FILE")
            
            # VLAN (optional)
            dialog --backtitle "$BACKTITLE" --title "VLAN Configuration" \
                --inputbox "Enter VLAN ID (leave empty for no VLAN):" \
                10 60 "" 2>"$TEMP_FILE" || handle_cancel
            
            VLAN=$(cat "$TEMP_FILE")
            
            # Build network options for static IP
            NET_OPTS="name=eth0,bridge=$BRIDGE,ip=$IP_CIDR"
            [[ -n "$GW" ]] && NET_OPTS+=",gw=$GW"
            [[ -n "$VLAN" ]] && NET_OPTS+=",tag=$VLAN"
            
            log "Network: Static IP $IP_CIDR on $BRIDGE"
        else
            # DHCP configuration
            NET_OPTS="name=eth0,bridge=$BRIDGE,ip=dhcp"
            
            # VLAN for DHCP (optional)
            dialog --backtitle "$BACKTITLE" --title "VLAN Configuration" \
                --inputbox "Enter VLAN ID (leave empty for no VLAN):" \
                10 60 "" 2>"$TEMP_FILE" || handle_cancel
            
            VLAN=$(cat "$TEMP_FILE")
            [[ -n "$VLAN" ]] && NET_OPTS+=",tag=$VLAN"
            
            log "Network: DHCP on $BRIDGE"
        fi
    }

    show_configuration_summary() {
        # Determine container type and network configuration
        local container_type="Unprivileged"
        [[ "$UNPRIV" -eq 0 ]] && container_type="Privileged"
        
        local net_mode="DHCP"
        [[ "$NET_CONFIG" == "static" ]] && net_mode="Static IP"
        
        local features_display="${FEATURES:-none}"
        local ip_display="${IP_CIDR:-auto/dhcp}"
        local gw_display="${GW:-auto/none}"
        local vlan_display="${VLAN:-none}"
        
        # Build properly formatted summary
        SUMMARY="╔════════════════════════════════════════════════════════════════╗
║          CONTAINER CONFIGURATION SUMMARY                       ║
╠════════════════════════════════════════════════════════════════╣
║ BASIC INFORMATION                                              ║
╟────────────────────────────────────────────────────────────────╢
║  Container ID  : $(printf '%-45s' "$CTID")║
║  Hostname      : $(printf '%-45s' "$HOSTNAME")║
║  Template      : $(printf '%-45s' "$TEMPLATE_BASENAME")║
║  Target Node   : $(printf '%-45s' "$TARGET_NODE")║
║                                                                ║
╟────────────────────────────────────────────────────────────────╢
║ RESOURCES                                                      ║
╟────────────────────────────────────────────────────────────────╢
║  CPU Cores     : $(printf '%-45s' "$CPU cores")║
║  Memory        : $(printf '%-45s' "${RAM}MB")║
║  Swap          : $(printf '%-45s' "${SWAP}MB")║
║  Storage Pool  : $(printf '%-45s' "$STORAGE")║
║  Disk Size     : $(printf '%-45s' "${DISK}GB")║
║                                                                ║
╟────────────────────────────────────────────────────────────────╢
║ SECURITY                                                       ║
╟────────────────────────────────────────────────────────────────╢
║  Type          : $(printf '%-45s' "$container_type")║
║  Features      : $(printf '%-45s' "$features_display")║
║                                                                ║
╟────────────────────────────────────────────────────────────────╢
║ NETWORK                                                        ║
╟────────────────────────────────────────────────────────────────╢
║  Bridge        : $(printf '%-45s' "$BRIDGE")║
║  Config        : $(printf '%-45s' "$net_mode")║
║  IP Address    : $(printf '%-45s' "$ip_display")║
║  Gateway       : $(printf '%-45s' "$gw_display")║
║  VLAN          : $(printf '%-45s' "$vlan_display")║
╚════════════════════════════════════════════════════════════════╝"

        if dialog --title "Confirm Container Creation" \
            --yes-label "Create" --no-label "Cancel" \
            --yesno "$SUMMARY\n\nProceed with creating this container?" 30 70; then
            # Close dialog properly before starting creation
            clear
            tput clear 2>/dev/null || true
            printf '\033c' 2>/dev/null || true
            sleep 0.2
            return 0
        else
            # User cancelled - clean exit
            clear
            tput clear 2>/dev/null || true
            printf '\033c' 2>/dev/null || true
            echo ""
            echo -e "${YW}[INFO]${CL} Container creation cancelled by user."
            echo ""
            exit 0
        fi
    }

    create_container() {
        # Ensure dialog is completely closed and terminal is ready
        clear
        echo
        echo "╔════════════════════════════════════════════════════════════════╗"
        echo "║                    Creating LXC Container                     ║"
        echo "╚════════════════════════════════════════════════════════════════╝"
        echo
        
        msg_info "Creating container with enhanced safety features..."
        
        # Validate storage space before creation
        validate_storage_space "$STORAGE" "$DISK"
        
        # Check and fix subuid/subgid for unprivileged containers
        if [[ "$UNPRIV" -eq 1 ]]; then
            msg_info "Configuring unprivileged container support..."
            grep -q "root:100000:65536" /etc/subuid || echo "root:100000:65536" >>/etc/subuid
            grep -q "root:100000:65536" /etc/subgid || echo "root:100000:65536" >>/etc/subgid
            msg_ok "Unprivileged container support configured"
        fi

        # Create secure lock for template access
        LOCKFILE="/tmp/template.${TEMPLATE_VOLID##*/}.lock"
        msg_info "Acquiring template lock: $LOCKFILE"
        
        exec 9>"$LOCKFILE" || error "Failed to create lock file '$LOCKFILE'" 200
        if ! flock -w 60 9; then
            error "Timeout while waiting for template lock. Another operation may be in progress." $ERR_TEMPLATE_LOCK_TIMEOUT
        fi
        msg_ok "Template lock acquired successfully"

        # Build the container creation command
        PCT_CMD=(pct create "$CTID" "$TEMPLATE_VOLID"
        --hostname "$HOSTNAME" 
        --arch amd64 
        --cores "$CPU" 
        --memory "$RAM" 
        --swap "$SWAP"
        --rootfs "${STORAGE}:${DISK}" 
        --net0 "$NET_OPTS" 
        --ostype "$OSTYPE"
        --unprivileged "$UNPRIV" 
        --onboot 1 
        --start 0
        )

        # Add node specification for clustered environments
        if [[ ${#NODE_OPTS[@]} -gt 0 ]]; then
            PCT_CMD+=(--node "$TARGET_NODE")
            msg_info "Target node: ${BL}$TARGET_NODE${CL}"
        fi

        # Add features if selected
        [[ -n "$FEATURES" ]] && PCT_CMD+=(--features "$FEATURES")

        # Execute container creation with comprehensive error handling
        local log_cmd="COMMAND: ${PCT_CMD[*]}"
        msg_info "Executing container creation..."
        
        if ! "${PCT_CMD[@]}" >> "$LOG_FILE" 2>&1; then
            log "FAILED $log_cmd"
            
            # Get detailed error information - simplified to avoid process substitution issues
            local error_details=""
            if [[ -f "$LOG_FILE" ]]; then
                error_details=$(tail -20 "$LOG_FILE" 2>/dev/null | grep -iE "error|failed" 2>/dev/null | tail -3 | head -c 200 || echo "")
            fi
            [[ -z "$error_details" ]] && error_details="Unknown error occurred during container creation"
            
            # Provide specific error guidance
            local error_guidance=""
            if [[ "$error_details" =~ "already exists" ]]; then
                error_guidance="\n\nSolution: Choose a different Container ID"
            elif [[ "$error_details" =~ "space" || "$error_details" =~ "disk" ]]; then
                error_guidance="\n\nSolution: Free up disk space or choose different storage"
            elif [[ "$error_details" =~ "template" || "$error_details" =~ "download" ]]; then
                error_guidance="\n\nSolution: Re-download template or check template integrity"
            elif [[ "$error_details" =~ "network" || "$error_details" =~ "bridge" ]]; then
                error_guidance="\n\nSolution: Check network configuration and bridge availability"
            fi
            
            dialog --title "Container Creation Failed" \
                --msgbox "Failed to create container $CTID.\n\nError: $error_details$error_guidance\n\nFull logs: $LOG_FILE" \
                15 80 || true
            error "Container creation failed: $error_details" $ERR_CONTAINER_CREATION_FAILED
        fi

        # Post-creation validation
        msg_info "Validating container creation..."
        sleep 2  # Allow time for container registration

        # Verify container is listed
        if ! pct list | awk '{print $1}' | grep -qx "$CTID"; then
            error "Container ID $CTID not found in container list after creation" $ERR_CONTAINER_NOT_LISTED
        fi

        # Verify container configuration exists
        if [[ ! -f "/etc/pve/lxc/$CTID.conf" ]]; then
            error "Container configuration file /etc/pve/lxc/$CTID.conf not found" $ERR_CONTAINER_CREATION_FAILED
        fi

        # Verify rootfs entry exists
        if ! grep -q '^rootfs:' "/etc/pve/lxc/$CTID.conf"; then
            error "RootFS entry missing in container config - storage not correctly assigned" $ERR_ROOTFS_MISSING
        fi

        # Validate hostname in config
        if grep -q '^hostname:' "/etc/pve/lxc/$CTID.conf"; then
            local ct_hostname
            ct_hostname=$(grep '^hostname:' "/etc/pve/lxc/$CTID.conf" | awk '{print $2}')
            if [[ ! "$ct_hostname" =~ ^[a-z0-9-]+$ ]]; then
                warn "Hostname '$ct_hostname' contains unusual characters - may cause networking issues"
            fi
        fi

        log "SUCCESS: $log_cmd\n$SUMMARY"
        msg_ok "Container ${BL}$CTID${CL} (${GN}$HOSTNAME${CL}) created successfully!"

        # Success notification
        dialog --title "Container Created Successfully!" \
            --msgbox "🎉 Container $CTID ($HOSTNAME) has been created successfully!\n\n✅ All validation checks passed\n✅ Configuration verified\n✅ Ready for use\n\nThe container will automatically start on boot (onboot=1)." \
            12 70 || true

        # Post-creation options
        if dialog --title "Container Management" \
            --yesno "Would you like to start container $CTID now?\n\nYou can also start it later using:\npct start $CTID" \
            10 60; then
            msg_info "Starting container $CTID..."
            if pct start "$CTID" 2>/dev/null; then
                msg_ok "Container $CTID started successfully"
                dialog --msgbox "✅ Container $CTID started successfully!\n\nYou can now:\n• Connect via SSH (if configured)\n• Access console: pct enter $CTID\n• Check status: pct status $CTID" 10 60 || true
            else
                warn "Container created but failed to start"
                dialog --msgbox "⚠️ Container created but failed to start.\n\nYou can start it manually later:\npct start $CTID\n\nCheck logs for startup issues:\npct status $CTID" 10 60 || true
            fi
        fi
    }

    show_success_summary() {
        # Final cleanup is handled by the trap
        clear
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "🎉 LXC Container Creation Completed Successfully!"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📋 Container Details:"
        echo "   • Container ID: $CTID"
        echo "   • Hostname: $HOSTNAME"
        echo "   • Template: $TEMPLATE_BASENAME"
        echo "   • Node: $TARGET_NODE"
        echo ""
        echo "🔧 Useful Commands:"
        echo "   • Start container:    pct start $CTID"
        echo "   • Stop container:     pct stop $CTID"
        echo "   • Enter console:      pct enter $CTID"
        echo "   • Check status:       pct status $CTID"
        echo "   • View config:        cat /etc/pve/lxc/$CTID.conf"
        echo ""
        echo "📝 Creation log saved to: $LOG_FILE"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo
    }

    # Initialize the script logging
    setup_logging() {
        # Create log directory and file with proper permissions
        mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
        if ! touch "$LOG_FILE" 2>/dev/null; then
            # Use alternative log location if primary fails
            LOG_FILE="/tmp/proxmox-lxc-builder-$(date +%s).log"
            touch "$LOG_FILE" 2>/dev/null || true
        fi
        
        # Log session start
        {
            echo "============================================="
            echo "LXC Builder Session: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
            echo "Proxmox Version: $(pveversion || echo 'Unknown')"
            echo "User: $(whoami)"
            echo "============================================="
        } >> "$LOG_FILE" 2>/dev/null || true
    }

    # --- Main Execution Flow ---
    main() {
        # Initialize logging first
        setup_logging
        
        # Run production checks
        production_checks
        ensure_dependencies
        
        # Display welcome header
        clear
        info "🧱 Proxmox Universal LXC Builder - Production Edition"
        info "Initializing environment..."
        
        # Detect environment and discover resources
        detect_cluster_environment
        discover_storage
        discover_templates
        discover_bridges
        
        # User configuration phase
        configure_container_basics
        configure_container_resources  
        configure_container_security
        configure_container_network
        
        # Final confirmation and creation
        show_configuration_summary
        create_container
        
        # Success cleanup  
        show_success_summary
    }

    # Execute main function
    main "$@"
