#!/usr/bin/env bash
# oc-reset-5090.sh — Reset RTX 5090 memory overclock to stock
set -euo pipefail

GPU_INDEX=${GPU_INDEX:-0}
DISPLAY=${DISPLAY:-:0}
export DISPLAY

die() {
    echo "ERROR: $*" >&2
    exit 1
}

if [[ ${1:-} =~ ^gpu:[0-9]+$ ]]; then
    GPU_INDEX=${1#gpu:}
elif [[ -n ${1:-} ]]; then
    die "Usage: $0 [gpu:N]"
fi

if ! nvidia-settings -q gpus 2>/dev/null | grep -q "\[gpu:${GPU_INDEX}\]"; then
    die "Requested GPU gpu:$GPU_INDEX is not visible to nvidia-settings on DISPLAY=$DISPLAY"
fi

if ! nvidia-settings -q all 2>&1 | grep -Fq 'GPUMemoryTransferRateOffsetAllPerformanceLevels'; then
    die "Memory overclock controls are not exposed in this session. Log into an NVIDIA Xorg session with Coolbits enabled."
fi

echo "=== Resetting RTX 5090 memory overclock to stock ==="

if ! OUTPUT=$(nvidia-settings -a "[gpu:${GPU_INDEX}]/GPUMemoryTransferRateOffsetAllPerformanceLevels=0" 2>&1); then
    echo "$OUTPUT" >&2
    die "Failed to reset memory offset on gpu:$GPU_INDEX"
fi

echo "$OUTPUT"

echo ""
echo "Memory offset reset to 0."
nvidia-smi -i "$GPU_INDEX" --query-gpu=name,clocks.current.memory,clocks.max.memory --format=csv,noheader
