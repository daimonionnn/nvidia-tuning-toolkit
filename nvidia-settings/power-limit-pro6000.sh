#!/usr/bin/env bash
# power-limit-pro6000.sh — RTX PRO 6000 Blackwell power limit manager
# Requires sudo (nvidia-smi -pl writes to the driver).
#
# Usage:
#   ./power-limit-pro6000.sh [watts|default|max|min|status]
#
#   ./power-limit-pro6000.sh status    # show current limits (no sudo needed)
#   ./power-limit-pro6000.sh default   # 600 W  — stock TGP (Workstation Edition)
#   ./power-limit-pro6000.sh max       # 600 W  — board maximum
#   ./power-limit-pro6000.sh min       # 150 W  — board minimum
#   ./power-limit-pro6000.sh 500       # 500 W  — custom value
#
# Allowed range: 150 W – 600 W
#
# NOTE: these constants were confirmed via `nvidia-smi --query-gpu=power.min_limit,
# power.max_limit,power.default_limit` on an actual Workstation Edition card
# (150 / 600 / 600 W) — not estimated from spec sheets. If you have a Max-Q
# (300 W hard cap) or Server edition (450–600 W depending on power cable),
# run `status` first and adjust LIMIT_DEFAULT/LIMIT_MAX/LIMIT_MIN below to
# match what nvidia-smi reports on your card.

set -euo pipefail

GPU_INDEX=${GPU_INDEX:-0}

# ── Known limits (Workstation Edition; verify with `status` on your card) ─────
LIMIT_DEFAULT=600
LIMIT_MAX=600
LIMIT_MIN=150

# ── Helpers ───────────────────────────────────────────────────────────────────
print_status() {
    echo "=== RTX PRO 6000 Power Limits ==="
    nvidia-smi \
        --query-gpu=name,power.draw,power.limit,power.min_limit,power.max_limit,power.default_limit \
        --format=csv,noheader | \
    awk -F', ' '{
        printf "%-26s %s\n",  "GPU:",            $1
        printf "%-26s %s\n",  "Current draw:",   $2
        printf "%-26s %s\n",  "Active limit:",   $3
        printf "%-26s %s\n",  "Board minimum:",  $4
        printf "%-26s %s\n",  "Board maximum:",  $5
        printf "%-26s %s\n",  "Default TDP:",    $6
    }'
}

usage() {
    echo "Usage: $0 [watts|default|max|min|status]"
    echo ""
    echo "  status          Show current power info (no sudo required)"
    echo "  default         Set to default TGP (${LIMIT_DEFAULT} W)"
    echo "  max             Set to board maximum (${LIMIT_MAX} W)"
    echo "  min             Set to board minimum (${LIMIT_MIN} W)"
    echo "  <watts>         Set to a custom value between ${LIMIT_MIN} – ${LIMIT_MAX} W"
    echo ""
    print_status
}

# ── Argument parsing ──────────────────────────────────────────────────────────
ARG=${1:-status}

case "$ARG" in
    status)
        print_status
        exit 0
        ;;
    default)
        TARGET=$LIMIT_DEFAULT
        ;;
    max)
        TARGET=$LIMIT_MAX
        ;;
    min)
        TARGET=$LIMIT_MIN
        ;;
    help|--help|-h)
        usage
        exit 0
        ;;
    *)
        if [[ "$ARG" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            TARGET=$(printf "%.0f" "$ARG")
        else
            echo "ERROR: Unknown argument '$ARG'"
            echo ""
            usage
            exit 1
        fi
        ;;
esac

# ── Range check ───────────────────────────────────────────────────────────────
if (( TARGET < LIMIT_MIN || TARGET > LIMIT_MAX )); then
    echo "ERROR: ${TARGET} W is outside the allowed range [${LIMIT_MIN} W – ${LIMIT_MAX} W]."
    exit 1
fi

# ── Apply ─────────────────────────────────────────────────────────────────────
echo "=== RTX PRO 6000 Power Limit ==="
echo ""

BEFORE=$(nvidia-smi --query-gpu=power.limit --format=csv,noheader,nounits | xargs printf "%.0f")
echo "Current limit : ${BEFORE} W"
echo "Target limit  : ${TARGET} W"
echo ""

if (( TARGET == BEFORE )); then
    echo "Already set to ${TARGET} W — nothing to do."
    exit 0
fi

echo "Applying... (requires sudo)"
sudo nvidia-smi -i "$GPU_INDEX" -pl "$TARGET"

echo ""
echo "Verifying..."
sleep 0.5
AFTER=$(nvidia-smi --query-gpu=power.limit --format=csv,noheader,nounits | xargs printf "%.0f")
echo "New limit: ${AFTER} W"

if (( AFTER == TARGET )); then
    echo "Success."
else
    echo "WARNING: limit reported as ${AFTER} W, expected ${TARGET} W."
fi

echo ""
echo "Run './monitor.sh' to watch power draw live."
