#!/usr/bin/env bash
# monitor.sh — Live GPU monitoring (1-second refresh)
# GPU-model-agnostic: works for RTX 5090, RTX PRO 6000, or whatever nvidia-smi
# reports. See nvidia-settings/ and nvidia-tuner/ for model-specific tuning
# scripts (distinguished by -5090 / -pro6000 filename suffix).
# Press Ctrl+C to exit.

set -euo pipefail

INTERVAL=${1:-1}
GPU_LABEL=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo "GPU")

echo "=== ${GPU_LABEL} Live Monitor  (Ctrl+C to stop) ==="
echo ""

while true; do
    clear
    echo "=== ${GPU_LABEL} Live Monitor  $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo ""
    nvidia-smi --query-gpu=\
name,driver_version,\
temperature.gpu,fan.speed,\
power.draw,power.limit,\
clocks.current.graphics,clocks.max.graphics,\
clocks.current.memory,clocks.max.memory,\
memory.used,memory.total,\
utilization.gpu,utilization.memory \
        --format=csv,noheader | \
    awk -F', ' '{
        printf "%-28s %s\n",  "GPU:",             $1
        printf "%-28s %s\n",  "Driver:",          $2
        printf "%-28s %s\n",  "Temperature:",     $3
        printf "%-28s %s\n",  "Fan Speed:",       $4
        printf "%-28s %s  /  %s  (limit)\n", "Power:", $5, $6
        printf "%-28s %s  /  max %s\n", "Core Clock:", $7, $8
        printf "%-28s %s  /  max %s\n", "Memory Clock:", $9, $10
        printf "%-28s %s  /  %s\n", "VRAM Used:", $11, $12
        printf "%-28s %s\n",  "GPU Utilisation:", $13
        printf "%-28s %s\n",  "Mem Utilisation:", $14
    }' || echo "(GPU query failed — retrying)"

    echo ""
    echo "─── Error Counters ──────────────────────────────────────────"
    nvidia-smi --query-gpu=ecc.errors.uncorrected.volatile.total,ecc.errors.corrected.volatile.total \
        --format=csv,noheader 2>/dev/null | \
        awk -F', ' '{printf "Uncorrected ECC errors: %s\nCorrected ECC errors:   %s\n", $1, $2}' || \
        echo "(ECC not available)"

    echo ""
    echo "─── Processes ───────────────────────────────────────────────"
    nvidia-smi pmon -c 1 2>/dev/null | tail -n +3 | head -20 || \
        nvidia-smi --query-compute-apps=pid,used_memory,name --format=csv,noheader 2>/dev/null || \
        echo "(No compute processes)"

    sleep "$INTERVAL"
done
