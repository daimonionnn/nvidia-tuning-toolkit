#!/usr/bin/env bash
# oc-memory-5090.sh — RTX 5090 GDDR7 Memory Overclock
# Requires Coolbits=28 in xorg.conf.d and an active NVIDIA Xorg session.
#
# Usage:
#   ./oc-memory-5090.sh [offset_mhz] [gpu:N]
#   ./oc-memory-5090.sh 500            # +500 MHz transfer rate offset (conservative)
#   ./oc-memory-5090.sh 1000 gpu:0     # +1000 MHz on GPU 0
#   ./oc-memory-5090.sh gpu:1 1500     # +1500 MHz on GPU 1
#   ./oc-memory-5090.sh 0              # reset to stock

set -euo pipefail

GPU_INDEX=${GPU_INDEX:-0}
DISPLAY=${DISPLAY:-:0}
export DISPLAY

# ── Defaults ──────────────────────────────────────────────────────────────────
# RTX 5090 GDDR7 stock: 14001 MHz   (28 Gbps effective)
# Start low and increase by 100–200 MHz increments until artifacts appear,
# then back off by 200 MHz for a stable daily-use offset.
DEFAULT_OFFSET=2500

OFFSET=${DEFAULT_OFFSET}

usage() {
    cat <<EOF
Usage: $0 [offset_mhz] [gpu:N]

Examples:
  $0 500
  $0 1000 gpu:0
  $0 gpu:1 1500
  GPU_INDEX=0 $0 1200

Notes:
  - Offset must be an integer in MHz.
  - GPU target may be provided as gpu:N.
  - Overclock controls require an NVIDIA-managed Xorg session.
EOF
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

parse_args() {
    local arg

    for arg in "$@"; do
        case "$arg" in
            help|--help|-h)
                usage
                exit 0
                ;;
            gpu:[0-9]*)
                GPU_INDEX=${arg#gpu:}
                ;;
            -g|--gpu)
                die "Use gpu:N as a single argument, e.g. '$0 1000 gpu:0'"
                ;;
            -*)
                die "Unknown option '$arg'"
                ;;
            *)
                if [[ "$arg" =~ ^-?[0-9]+$ ]]; then
                    OFFSET=$arg
                else
                    die "Unknown argument '$arg'"
                fi
                ;;
        esac
    done
}

get_visible_gpu_indexes() {
    nvidia-settings -q gpus 2>/dev/null | sed -n 's/.*\[gpu:\([0-9]\+\)\].*/\1/p'
}

ensure_gpu_visible() {
    local visible

    visible=$(get_visible_gpu_indexes)
    if [[ -z "$visible" ]]; then
        die "nvidia-settings cannot see any NVIDIA GPU targets on DISPLAY=$DISPLAY. Check DISPLAY/XAUTHORITY and log into an NVIDIA Xorg session."
    fi

    if ! grep -qx "$GPU_INDEX" <<<"$visible"; then
        echo "Visible GPU targets:" >&2
        sed 's/^/  gpu:/' <<<"$visible" >&2
        die "Requested GPU gpu:$GPU_INDEX is not available on DISPLAY=$DISPLAY"
    fi
}

ensure_oc_controls_available() {
    if ! nvidia-settings -q all 2>&1 | grep -Fq 'GPUMemoryTransferRateOffsetAllPerformanceLevels'; then
        die "Memory overclock controls are not exposed in this session. Coolbits may not be active, or you may be on Wayland/Xwayland instead of an NVIDIA Xorg session. Restart into Xorg after installing config/10-coolbits.conf."
    fi
}

parse_args "$@"

# ── Sanity checks ─────────────────────────────────────────────────────────────
if ! command -v nvidia-settings &>/dev/null; then
    die "nvidia-settings not found. Install the NVIDIA driver package."
fi

if [[ ! "$OFFSET" =~ ^-?[0-9]+$ ]]; then
    die "Offset must be an integer (MHz). Got: $OFFSET"
fi

if (( OFFSET > 4000 )); then
    die "Offset $OFFSET MHz exceeds the 4000 MHz safety cap. Offsets above +3000 are extreme and likely unstable."
fi

ensure_gpu_visible
ensure_oc_controls_available

# ── Apply ─────────────────────────────────────────────────────────────────────
echo "=== RTX 5090 Memory Overclock ==="
echo "GPU index   : $GPU_INDEX"
echo "DISPLAY     : $DISPLAY"
echo "Mem offset  : ${OFFSET} MHz transfer rate"
echo ""

# Query current state before applying
CURRENT=$(nvidia-smi -i "$GPU_INDEX" --query-gpu=clocks.current.memory --format=csv,noheader,nounits 2>/dev/null || echo "N/A")
echo "Current memory clock : ${CURRENT} MHz"

if ! OUTPUT=$(nvidia-settings -a "[gpu:${GPU_INDEX}]/GPUMemoryTransferRateOffsetAllPerformanceLevels=${OFFSET}" 2>&1); then
    echo "$OUTPUT" >&2
    die "Failed to apply memory offset on gpu:$GPU_INDEX"
fi

echo "$OUTPUT"

echo ""
echo "Offset applied. Verifying..."
sleep 1

# Show result
nvidia-smi -i "$GPU_INDEX" --query-gpu=name,clocks.current.memory,clocks.max.memory --format=csv,noheader
echo ""
echo "Done. Monitor for stability with: ./monitor.sh"
echo "To revert:                        ./nvidia-settings/oc-reset-5090.sh"
