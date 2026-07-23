#!/usr/bin/env bash
# ecc-pro6000.sh — RTX PRO 6000 Blackwell ECC memory toggle
# Requires sudo (nvidia-smi -e writes to the driver).
#
# Usage:
#   ./ecc-pro6000.sh status   # show current/pending ECC mode (no sudo needed)
#   ./ecc-pro6000.sh on       # enable ECC  (pending — needs a GPU reset/reboot)
#   ./ecc-pro6000.sh off      # disable ECC (pending — needs a GPU reset/reboot)
#
# IMPORTANT: nvidia-smi -e only sets the *pending* mode; it does not take
# effect until the GPU is reset. A reboot is the reliable way to do that —
# `nvidia-smi --gpu-reset` can work without one, but only if nothing else is
# using the GPU (no display, no compute jobs), which usually isn't true on a
# desktop.
#
# Turning ECC off removes the error-detection safety net this repo's
# memory-offset OC scripts (oc-memory-pro6000.sh, apply-*-pro6000.sh) lean
# on to catch a silently-corrupting unstable overclock. With ECC off,
# monitor.sh's ECC error counters stop being a useful signal — validate any
# memory offset with real workload *output* checking, not just a
# crash-free stress test, especially while ECC is disabled.

set -euo pipefail

GPU_INDEX=${GPU_INDEX:-0}

print_status() {
    echo "=== RTX PRO 6000 ECC Mode ==="
    nvidia-smi --query-gpu=name,ecc.mode.current,ecc.mode.pending,memory.total \
        --format=csv,noheader | \
    awk -F', ' '{
        printf "%-16s %s\n", "GPU:",          $1
        printf "%-16s %s\n", "Current ECC:",  $2
        printf "%-16s %s\n", "Pending ECC:",  $3
        printf "%-16s %s\n", "Total memory:", $4
    }'
}

usage() {
    echo "Usage: $0 [status|on|off]"
    echo ""
    echo "  status   Show current/pending ECC mode (no sudo required)"
    echo "  on       Enable ECC  (pending — requires GPU reset/reboot to apply)"
    echo "  off      Disable ECC (pending — requires GPU reset/reboot to apply)"
    echo ""
    print_status
}

ARG=${1:-status}

case "$ARG" in
    status)
        print_status
        exit 0
        ;;
    on)
        TARGET=1
        LABEL="Enabled"
        ;;
    off)
        TARGET=0
        LABEL="Disabled"
        ;;
    help|--help|-h)
        usage
        exit 0
        ;;
    *)
        echo "ERROR: Unknown argument '$ARG'"
        echo ""
        usage
        exit 1
        ;;
esac

echo "=== RTX PRO 6000 ECC Mode ==="
echo ""
print_status
echo ""
echo "Setting pending ECC mode to: ${LABEL}"
echo "Applying... (requires sudo)"
sudo nvidia-smi -i "$GPU_INDEX" -e "$TARGET"

echo ""
echo "Pending mode updated — this does NOT take effect until the GPU is reset."
echo "Reboot to apply, then verify with: $0 status"
