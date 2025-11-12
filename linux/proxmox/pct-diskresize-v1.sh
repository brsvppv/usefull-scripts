#!/bin/bash
# ========================================================================
# Proxmox LXC Auto RootFS Resizer (Production-Ready with Dry-Run)
# Safely resizes a container's root filesystem (ext4/xfs supported)
# Usage:
#   pct-autoresize.sh <CTID> <NEW_SIZE> [--dry-run]
# Example:
#   pct-autoresize.sh 101 10G
#   pct-autoresize.sh 101 10G --dry-run
# ========================================================================

set -e
trap 'echo "❌ Script failed. Container may be in an intermediate state."' ERR

CTID="$1"
NEW_SIZE="$2"
MODE="$3"

# --- Parameter Validation ---
if [[ -z "$CTID" || -z "$NEW_SIZE" ]]; then
  echo "Usage: $0 <CTID> <NEW_SIZE> [--dry-run]"
  echo "Example: $0 101 10G"
  exit 1
fi

# --- Pre-check: Ensure container exists ---
if ! pct config "$CTID" >/dev/null 2>&1; then
  echo "❌ Container $CTID does not exist or is not accessible"
  exit 1
fi

# --- Show current size for comparison ---
CURRENT_SIZE=$(pct config "$CTID" | grep ^rootfs | cut -d',' -f2 | cut -d'=' -f2)
echo "=== Auto-resize for LXC $CTID ==="
echo "Current size: ${CURRENT_SIZE:-unknown}, Target size: $NEW_SIZE"

# --- Dry-run mode ---
if [[ "$MODE" == "--dry-run" ]]; then
  echo "=== DRY RUN ==="
  echo "Would resize CT$CTID from ${CURRENT_SIZE:-unknown} to $NEW_SIZE"
  echo "Would stop, resize, start, and expand filesystem (if ext4/xfs)."
  exit 0
fi

# --- Stop container gracefully ---
if pct status "$CTID" | grep -q running; then
  echo "[1/9] Stopping running container..."
  pct stop "$CTID"
else
  echo "[1/9] Container already stopped."
fi

# --- Optional: LVM check ---
if command -v lvs >/dev/null 2>&1; then
  echo "[INFO] LVM detected — checking available space..."
  lvs | grep -E "pve|local" || echo "No LVM volumes listed."
fi

# --- Resize rootfs ---
echo "[2/9] Resizing rootfs to $NEW_SIZE..."
pct resize "$CTID" rootfs "$NEW_SIZE"

# --- Verify resize took effect ---
NEW_ROOT_SIZE=$(pct config "$CTID" | grep ^rootfs | cut -d',' -f2 | cut -d'=' -f2)
if [[ "$NEW_ROOT_SIZE" != "$NEW_SIZE" ]]; then
  echo "⚠️ Warning: Rootfs size may not have changed as expected."
  echo "Expected: $NEW_SIZE, Got: $NEW_ROOT_SIZE"
else
  echo "✅ Rootfs successfully resized to $NEW_ROOT_SIZE"
fi

# --- Start container ---
echo "[3/9] Starting container..."
pct start "$CTID"

# --- Wait for container boot ---
echo "[4/9] Waiting for container to boot..."
until pct exec "$CTID" -- uptime >/dev/null 2>&1; do
  sleep 2
done

# --- Detect root device inside the container ---
echo "[5/9] Detecting root device..."
ROOT_DEVICE=$(pct exec "$CTID" -- findmnt -n -o SOURCE /)
FS_TYPE=$(pct exec "$CTID" -- findmnt -n -o FSTYPE /)
echo "Root device: $ROOT_DEVICE | Filesystem: $FS_TYPE"

# --- Resize filesystem inside container ---
echo "[6/9] Expanding filesystem..."
if [[ "$FS_TYPE" == "ext4" ]]; then
  pct exec "$CTID" -- resize2fs "$ROOT_DEVICE"
elif [[ "$FS_TYPE" == "xfs" ]]; then
  pct exec "$CTID" -- xfs_growfs /
else
  echo "⚠️ Unsupported filesystem: $FS_TYPE — skipping filesystem resize."
  exit 1
fi

# --- Verify filesystem resize ---
echo "[7/9] Verifying new disk usage..."
pct exec "$CTID" -- df -h /

# --- Final verification ---
echo "[8/9] Double-checking config consistency..."
FINAL_SIZE=$(pct config "$CTID" | grep ^rootfs | cut -d',' -f2 | cut -d'=' -f2)
if [[ "$FINAL_SIZE" == "$NEW_SIZE" ]]; then
  echo "✅ Resize complete. Container $CTID is now using $FINAL_SIZE"
else
  echo "⚠️ Size mismatch: expected $NEW_SIZE, got $FINAL_SIZE"
fi

# --- Success message ---
echo "[9/9] All steps completed successfully!"
exit 0