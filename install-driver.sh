#!/usr/bin/env bash
# install-driver.sh — Bootstrap: install the NVIDIA driver + CUDA toolkit for a
# Blackwell GPU on Ubuntu, handling Secure Boot module signing. Covers both
# consumer (RTX 50-series, e.g. RTX 5090) and professional (RTX PRO 6000
# Blackwell) cards — both use the GB202 die.
#
# Run this FIRST, before nvidia-settings/install.sh. Requires sudo (apt + mokutil).
#
#   sudo bash install-driver.sh
#
# Blackwell (RTX 50xx / RTX PRO 6000, GB202) REQUIRES the open kernel modules
# (the "-open" driver flavour). The closed/proprietary modules do not support it.
set -euo pipefail

# Driver package: the open-kernel-module flavour recommended by `ubuntu-drivers`.
# Override if a newer branch is recommended on your system, e.g.:
#   DRIVER_PKG=nvidia-driver-600-open sudo -E bash install-driver.sh
DRIVER_PKG="${DRIVER_PKG:-nvidia-driver-595-open}"
MOK_DER="/var/lib/shim-signed/mok/MOK.der"

# --- Re-exec as root so apt/mokutil work ------------------------------------
if [[ $EUID -ne 0 ]]; then
    echo "Re-running with sudo..."
    exec sudo -E bash "$0" "$@"
fi

echo "=== NVIDIA driver bootstrap (Blackwell: RTX 50-series / RTX PRO 6000) ==="
echo ""

# --- 1. Sanity checks -------------------------------------------------------
echo "[1/5] Checking hardware and OS..."
if ! command -v lspci >/dev/null; then
    apt-get install -y pciutils >/dev/null
fi
GPU_LINE="$(lspci -nn | grep -iE '10de:.*(VGA|3D)' || lspci -nn | grep -i '10de:' || true)"
if [[ -z "$GPU_LINE" ]]; then
    echo "      ERROR: No NVIDIA GPU (vendor 10de) found on the PCI bus." >&2
    echo "             Check the card is seated and powered before continuing." >&2
    exit 1
fi
echo "      GPU: ${GPU_LINE}"
echo "      Kernel: $(uname -r)   Driver pkg: ${DRIVER_PKG}"

# --- 2. Install driver + CUDA toolkit ---------------------------------------
# noninteractive: build & sign the module against the existing MOK, but skip the
# package's own Secure Boot dialog — we enroll the key explicitly in step 4 so
# there is exactly one, predictable enrollment path.
echo ""
echo "[2/5] apt update + install (this downloads a few GB; please wait)..."
export DEBIAN_FRONTEND=noninteractive
apt-get -o Acquire::Retries=5 update
apt-get -o Acquire::Retries=5 -o Acquire::http::Timeout=60 --fix-missing install -y "$DRIVER_PKG"
echo "      Installed: ${DRIVER_PKG}"

if apt-get -o Acquire::Retries=5 -o Acquire::http::Timeout=60 --fix-missing install -y nvidia-cuda-toolkit; then
    echo "      Installed: nvidia-cuda-toolkit"
else
    echo "      WARNING: nvidia-cuda-toolkit could not be installed from the mirror."
    echo "               The NVIDIA driver is installed; retry the toolkit later if needed."
fi

# --- 3. Confirm the DKMS module built and was signed ------------------------
echo ""
echo "[3/5] Verifying the kernel module built via DKMS..."
if command -v dkms >/dev/null; then
    dkms status | grep -i nvidia || echo "      (no nvidia DKMS status yet — check 'dkms status')"
fi

# --- 4. Secure Boot: enroll the module-signing key --------------------------
echo ""
echo "[4/5] Secure Boot key enrollment..."
SB_STATE="$(mokutil --sb-state 2>/dev/null || echo unknown)"
echo "      ${SB_STATE}"
if echo "$SB_STATE" | grep -qi 'enabled'; then
    if [[ ! -f "$MOK_DER" ]]; then
        echo "      ERROR: Secure Boot is on but $MOK_DER is missing." >&2
        echo "             Cannot sign/enroll. Re-run after 'apt install --reinstall shim-signed'." >&2
        exit 1
    fi
    if mokutil --test-key "$MOK_DER" 2>/dev/null | grep -qi 'is already enrolled'; then
        echo "      Key already enrolled — nothing to do."
    elif mokutil --list-new 2>/dev/null | grep -q .; then
        echo "      An enrollment request is ALREADY pending for next boot — good."
    else
        echo ""
        echo "      >>> You will now choose a ONE-TIME enrollment password. <<<"
        echo "      >>> Remember it — you must retype it at the blue MOK     <<<"
        echo "      >>> Manager screen during the next reboot.               <<<"
        echo ""
        mokutil --import "$MOK_DER"
        echo "      Enrollment request queued for next boot."
    fi
else
    echo "      Secure Boot is not enabled — no key enrollment needed."
fi

# --- 5. Next steps ----------------------------------------------------------
echo ""
echo "[5/5] Done installing. NEXT STEPS (must be done at the physical console):"
echo ""
echo "  1. Reboot:   sudo reboot"
echo "  2. At the blue 'MOK Manager' / 'Perform MOK management' screen:"
echo "       -> Enroll MOK  ->  Continue  ->  Yes"
echo "       -> enter the one-time password you set above  ->  Reboot"
echo "     (If you don't see this screen, the key was already enrolled — fine.)"
echo "  3. After it boots, verify:   nvidia-smi   &&   nvcc --version"
echo ""
echo "Once nvidia-smi shows your GPU, run the tuning setup:"
echo "  bash nvidia-settings/install.sh"
echo ""
echo "=== Bootstrap complete ==="
