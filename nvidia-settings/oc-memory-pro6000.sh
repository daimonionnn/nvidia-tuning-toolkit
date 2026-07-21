#!/usr/bin/env bash
# oc-memory-pro6000.sh — RTX PRO 6000 Blackwell GDDR7 Memory Overclock
# Requires Coolbits=28 in xorg.conf.d and an active NVIDIA Xorg session.
#
# Usage:
#   ./oc-memory-pro6000.sh [offset_mhz] [gpu:N]
#   ./oc-memory-pro6000.sh 250            # +250 MHz transfer rate offset (very conservative)
#   ./oc-memory-pro6000.sh 500 gpu:0      # +500 MHz on GPU 0
#   ./oc-memory-pro6000.sh gpu:1 750      # +750 MHz on GPU 1
#   ./oc-memory-pro6000.sh 0              # reset to stock

set -euo pipefail

GPU_INDEX=${GPU_INDEX:-0}
DISPLAY=${DISPLAY:-:0}
export DISPLAY

# ── Defaults ──────────────────────────────────────────────────────────────────
# RTX PRO 6000 Blackwell (Workstation Edition) uses the same 512-bit / 28 Gbps
# GDDR7 signalling as the RTX 5090, so stock nvidia-smi clock should also read
# ~14001 MHz. Unlike the 5090, this card ships with ECC memory and 96 GB across
# clamshell-mounted modules — denser packing generally means less OC headroom,
# and ECC makes an unstable offset a silent-corruption risk rather than just a
# visible artifact, so treat this as a professional/compute card, not a gaming
# card being pushed for FPS.
#
# No offsets have been validated on this card yet. Start low, run a long
# stress test (see README "Stability Testing"), and watch both
# `./monitor.sh` (ECC error counters) and your workload's actual output
# correctness before increasing.
DEFAULT_OFFSET=250

OFFSET=${DEFAULT_OFFSET}

usage() {
    cat <<EOF
Usage: $0 [offset_mhz] [gpu:N]

Examples:
  $0 250
  $0 500 gpu:0
  $0 gpu:1 750
  GPU_INDEX=0 $0 500

Notes:
  - Offset must be an integer in MHz.
  - GPU target may be provided as gpu:N.
  - Overclock controls require an NVIDIA-managed Xorg session.
  - This card has ECC memory: an unstable offset can silently corrupt
    compute results instead of just crashing. Validate with real workload
    output, not just a stress test that doesn't check results.
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
                die "Use gpu:N as a single argument, e.g. '$0 500 gpu:0'"
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

if (( OFFSET > 1500 )); then
    die "Offset $OFFSET MHz exceeds the 1500 MHz safety cap for this card. No offsets are validated on RTX PRO 6000 yet — this cap is intentionally tighter than the 5090 scripts until you've established a stable point. Test incrementally below the cap first."
fi

ensure_gpu_visible
ensure_oc_controls_available

# ── Apply ─────────────────────────────────────────────────────────────────────
echo "=== RTX PRO 6000 Memory Overclock ==="
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
echo "To revert:                        ./nvidia-settings/oc-reset-pro6000.sh"
