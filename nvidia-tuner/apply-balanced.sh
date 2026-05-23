#!/usr/bin/env bash
set -euo pipefail

if ! command -v nvidia-tuner &>/dev/null; then
    echo "ERROR: nvidia-tuner not found in PATH" >&2
    echo "Install it first, then rerun this script." >&2
    exit 1
fi

PROFILE_NAME="balanced"
PROFILE_CORE_OFFSET=-75
PROFILE_MEMORY_OFFSET=2500
PROFILE_POWER_LIMIT=500

echo "Applying nvidia-tuner ${PROFILE_NAME} profile: core ${PROFILE_CORE_OFFSET}, memory ${PROFILE_MEMORY_OFFSET}, power ${PROFILE_POWER_LIMIT}W"
nvidia-tuner \
    --core-clock-offset "$PROFILE_CORE_OFFSET" \
    --memory-clock-offset "$PROFILE_MEMORY_OFFSET" \
    --power-limit "$PROFILE_POWER_LIMIT"
