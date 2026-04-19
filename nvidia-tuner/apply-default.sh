#!/usr/bin/env bash
set -euo pipefail

if ! command -v nvidia-tuner &>/dev/null; then
    echo "ERROR: nvidia-tuner not found in PATH" >&2
    echo "Install it first, then rerun this script." >&2
    exit 1
fi

PROFILE_MEMORY_OFFSET=2500
PROFILE_POWER_LIMIT=500
PROFILE_CORE_OFFSET=-125

echo "Applying nvidia-tuner default profile: core ${PROFILE_CORE_OFFSET}, memory +${PROFILE_MEMORY_OFFSET}, power ${PROFILE_POWER_LIMIT}W"
nvidia-tuner --core-clock-offset "$PROFILE_CORE_OFFSET" --memory-clock-offset "$PROFILE_MEMORY_OFFSET" --power-limit "$PROFILE_POWER_LIMIT"
