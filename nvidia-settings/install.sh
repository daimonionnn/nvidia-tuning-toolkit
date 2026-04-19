#!/usr/bin/env bash
# install.sh — One-shot setup: install Coolbits config and make scripts executable
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COOLBITS_SRC="$SCRIPT_DIR/config/10-coolbits.conf"
COOLBITS_DEST="/etc/X11/xorg.conf.d/10-coolbits.conf"

detect_session_type() {
    if [[ -n "${XDG_SESSION_TYPE:-}" ]]; then
        printf '%s\n' "$XDG_SESSION_TYPE"
        return 0
    fi

    if command -v loginctl &>/dev/null && [[ -n "${XDG_SESSION_ID:-}" ]]; then
        loginctl show-session "$XDG_SESSION_ID" -p Type --value 2>/dev/null || true
    fi
}

echo "=== NVIDIA RTX Overclock Toolkit — Setup ==="
echo ""

# 1. Make all scripts executable (including subdirectories)
find "$REPO_ROOT/nvidia-settings" "$REPO_ROOT/nvidia-tuner" -type f -name '*.sh' -exec chmod +x {} +
echo "[1/4] Scripts marked executable (nvidia-settings + nvidia-tuner)."

# 2. Install Coolbits xorg config
if [[ -f "$COOLBITS_DEST" ]]; then
    echo "[2/4] Coolbits config already exists at $COOLBITS_DEST — skipping."
else
    sudo cp "$COOLBITS_SRC" "$COOLBITS_DEST"
    echo "[2/4] Coolbits config installed to $COOLBITS_DEST"
fi

# 3. Unlock power limit to full TDP
echo ""
echo "[3/4] Setting GPU power limit to default TDP (575 W)..."
sudo nvidia-smi -i 0 -pl 575 && echo "      Power limit set to 575 W." || echo "      WARNING: Could not set power limit — try manually: sudo nvidia-smi -pl 575"

# 4. Prompt to restart display manager
echo ""
echo "[4/4] Coolbits requires a display-manager restart to take effect."
echo "      Detected display manager:"
cat /etc/X11/default-display-manager 2>/dev/null || echo "      (unknown)"

SESSION_TYPE=$(detect_session_type)
echo ""
if [[ "${SESSION_TYPE,,}" == "wayland" ]]; then
    echo "      WARNING: Current session type is Wayland."
    echo "               NVIDIA overclock controls usually require logging into an Xorg session"
    echo "               after the display manager restarts."
elif [[ "${SESSION_TYPE,,}" == "x11" || "${SESSION_TYPE,,}" == "xorg" ]]; then
    echo "      Current session type: ${SESSION_TYPE}"
    echo "      After restart, overclock controls should be available if the NVIDIA Xorg session starts cleanly."
elif [[ -n "$SESSION_TYPE" ]]; then
    echo "      Current session type: ${SESSION_TYPE}"
    echo "      If overclock controls are still missing after restart, switch to an Xorg session and try again."
else
    echo "      Session type could not be detected."
    echo "      If overclock controls are still missing after restart, log into an Xorg session and try again."
fi
echo ""
read -rp "      Restart display manager NOW? This will close your session. [y/N]: " CONFIRM
if [[ "${CONFIRM,,}" == "y" ]]; then
    DM=$(basename "$(cat /etc/X11/default-display-manager 2>/dev/null || echo gdm3)")
    sudo systemctl restart "$DM"
else
    echo ""
    echo "      Restart manually when ready:"
    echo "        sudo systemctl restart \$(basename \$(cat /etc/X11/default-display-manager))"
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "From repo root, you can now run:"
echo "  ./nvidia-settings/power-limit.sh [default|max|<watts>|status]   # power limit"
echo "  ./nvidia-settings/oc-memory.sh [offset_mhz]                     # memory OC"
echo "  ./monitor.sh                                                     # live stats"
echo "  ./nvidia-settings/oc-reset.sh                                    # revert OC to stock"
