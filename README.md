# NVIDIA RTX Tuning Toolkit for Linux
Scripts for tuning and overclocking nVidia RTX GPUs (customized and tested on MSI RTX 5090 Vanguard)

GPU detected: **RTX 5090** · Driver **580.126.09** · GDDR7 32 GB  
Stock memory clock: **14001 MHz** (28 Gbps)

---

## Quick Start

If `nvidia-smi` already works and the card is up, you can skip the driver bootstrap and start at step 2.

```bash
# 1. Install the NVIDIA driver + CUDA toolkit first
sudo bash install-driver.sh

# 2. Run the one-time setup (requires sudo for xorg config + display restart)
bash nvidia-settings/install.sh

# 3. Set power limit (daily default: 500 W; stock: 575 W; max: 600 W)
./nvidia-settings/power-limit.sh 500       # 500 W — daily default profile
./nvidia-settings/power-limit.sh default   # 575 W — stock TDP
./nvidia-settings/power-limit.sh max       # 600 W — board maximum
./nvidia-settings/power-limit.sh status    # show current limits (no sudo)

# 4. After your session restarts, apply a memory overclock (daily default: +2500)
./nvidia-settings/oc-memory.sh 2500   # daily default (RTX 5090 MSI Vanguard)
./nvidia-settings/oc-memory.sh 500    # conservative start
./nvidia-settings/oc-memory.sh 1000   # moderate
./nvidia-settings/oc-memory.sh 1500   # aggressive (test for stability first)
./nvidia-settings/oc-memory.sh 3000   # extreme (reported working on RTX 5090 MSI Vanguard)

# 5. Monitor in real time
./monitor.sh

# 6. Revert to stock
./nvidia-settings/oc-reset.sh

# Wayland-friendly method: nvidia-tuner presets
nvidia-tuner --core-clock-offset -125 --memory-clock-offset 2500 --power-limit 500
nvidia-tuner --memory-clock-offset 3000 --power-limit 500

If Secure Boot is enabled, `install-driver.sh` will prompt for a MOK enrollment password and the key will be enrolled on the next reboot.
If the driver is already installed and the GPU is working, `install-driver.sh` is optional unless you want the CUDA toolkit or need to refresh the Secure Boot enrollment path.

# Or reset clocks to stock and unlock max power with the bundled helper
./nvidia-tuner/apply-default.sh        # core 0, mem 0, PL 600W

# Undervolt profile helpers (increasing efficiency, all validated on this card)
./nvidia-tuner/apply-balanced.sh       # core -75,  mem +2500, PL 500W
./nvidia-tuner/apply-efficient.sh      # core -125, mem +2500, PL 450W
./nvidia-tuner/apply-max-efficiency.sh # core -125, mem +3000, PL 400W
```

---

## How It Works

### Coolbits (xorg)
NVIDIA locks overclocking in the driver by default. Setting `Coolbits=28` in
`/etc/X11/xorg.conf.d/10-coolbits.conf` unlocks:

| Bit | Value | Feature |
|-----|-------|---------|
| 2   | 4     | Clock rate adjustment |
| 3   | 8     | GPU overclocking |
| 4   | 16    | Fan speed control |

### Memory offset (`GPUMemoryTransferRateOffsetAllPerformanceLevels`)
`nvidia-settings` exposes this attribute once Coolbits is set. The value is a
**transfer-rate offset in MHz** applied on top of the stock GDDR7 frequency.

> **Important:** this control is exposed only from an NVIDIA-managed **Xorg**
> session. A Wayland session that only provides Xwayland compatibility is not
> enough.

| Offset | Effective memory clock | Risk |
|--------|------------------------|------|
| 0      | 14001 MHz (stock)      | None |
| +500   | ~14501 MHz             | Very low |
| +1000  | ~15001 MHz             | Low |
| +1500  | ~15501 MHz             | Medium — test thoroughly |
| +2000  | ~16001 MHz             | High |
| +2500  | ~16501 MHz             | Very high — validate with long stress tests |
| +3000  | ~17001 MHz             | Extreme — may be unstable on many cards |

> **Note:** GDDR7 uses PAM4 signalling. Small offsets can yield meaningfully
> higher bandwidth. Start at +500 and increase by +200 MHz increments.
> If you see visual artifacts, GPU resets, or crashes → reduce the offset.
> Reported working on one sample: **RTX 5090 MSI Vanguard** at +2500 and +3000.

---

## Power Limit

Your RTX 5090 is currently capped at **400 W**. The driver allows **400–600 W**.
Current daily default profile in this repo: **500 W power limit**.

| Command | Watts | Notes |
|---------|-------|-------|
| `power-limit.sh status` | — | Read current limits (no sudo) |
| `power-limit.sh default` | 575 W | Stock TDP, best performance/cooling balance |
| `power-limit.sh max` | 600 W | +4% headroom over default, extra heat |
| `power-limit.sh 500` | 500 W | Daily default profile |
| `power-limit.sh min` | 400 W | Current cap — restore if needed |

> Power limit changes take effect immediately and persist until the next driver unload or reboot.  
> To make it persistent for this profile, add `power-limit.sh 500` to your boot-time service.

---

## Stability Testing

After applying an offset, stress-test before committing to it:

```bash
# Simple VRAM bandwidth test (requires cuda-samples or pytorch)
python3 -c "
import torch, time
a = torch.randn(8192, 8192, device='cuda')
b = torch.randn(8192, 8192, device='cuda')
torch.cuda.synchronize()
t = time.time()
for _ in range(200):
    c = a @ b
torch.cuda.synchronize()
print(f'Matmul throughput test: {200/(time.time()-t):.1f} iter/s')
"

# Or use gpu-burn (install separately)
# gpu-burn 120   # 2-minute stress test
```

Watch `./monitor.sh` in a second terminal for temperature spikes or
ECC error counts climbing.

---

## Making the Overclock Persistent on Boot

Create a systemd service that re-applies the offset after each login:

```bash
# /etc/systemd/system/rtx5090-oc.service
[Unit]
Description=RTX 5090 Memory Overclock
After=graphical.target

[Service]
Type=oneshot
Environment=DISPLAY=:0
ExecStart=/home/matt/development/nvidia-tuning-toolkit/nvidia-settings/oc-memory.sh 2500
RemainAfterExit=yes

[Install]
WantedBy=graphical.target
```

```bash
sudo systemctl enable --now rtx5090-oc.service
```

---

## Wayland-friendly method: nvidia-tuner

If you prefer `nvidia-tuner` (works well on Wayland), this is the current daily-driver preset:

```bash
nvidia-tuner --core-clock-offset -125 --memory-clock-offset 2500 --power-limit 500
```

### Install `nvidia-tuner`

```bash
# Download latest release binary
curl -fL https://github.com/WickedLukas/nvidia-tuner/releases/latest/download/nvidia-tuner -o nvidia-tuner

# Install system-wide
sudo install -m 0755 nvidia-tuner /usr/local/bin/nvidia-tuner

# Verify
nvidia-tuner --help
```

### Make preset persistent after reboot (systemd)

Create `/etc/systemd/system/nvidia-tuner.service`:

```ini
[Unit]
Description=NVIDIA tuner preset (RTX 5090)
After=graphical.target
Wants=graphical.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/nvidia-tuner --core-clock-offset -125 --memory-clock-offset 2500 --power-limit 500
RemainAfterExit=yes

[Install]
WantedBy=graphical.target
```

Enable and start it:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now nvidia-tuner.service
```

Check status/logs:

```bash
systemctl status nvidia-tuner.service
sudo journalctl -u nvidia-tuner.service -n 50 --no-pager
```

### Undervolt profiles (Linux / `nvidia-tuner`)

These profiles trade a deeper core undervolt and lower power limit for efficiency
while keeping the memory overclock high. All values are validated on this card
(RTX 5090 MSI Vanguard); test for stability on your own hardware before relying on
them. Going down the table lowers the power limit and increases the memory offset.

| Profile | Core offset | Memory offset | Power limit |
|---------|-------------|---------------|-------------|
| Balanced | `-75` | `+2500` | `500 W` |
| Efficient | `-125` | `+2500` | `450 W` |
| Max efficiency | `-125` | `+3000` | `400 W` |

Apply a profile:

```bash
./nvidia-tuner/apply-balanced.sh
./nvidia-tuner/apply-efficient.sh
./nvidia-tuner/apply-max-efficiency.sh
```

If a profile is unstable on your card, lower the memory offset in `-250` steps
and re-test.

---

## Files

```
nvidia-tuning-toolkit/
├── install-driver.sh           # Driver + CUDA bootstrap (NVIDIA open driver + Secure Boot)
├── monitor.sh                  # Live GPU stats (1s refresh)
├── nvidia-settings/
│   ├── install.sh              # One-shot setup (Coolbits + permissions)
│   ├── config/
│   │   └── 10-coolbits.conf    # xorg.conf.d snippet — unlock OC controls
│   ├── power-limit.sh          # Main script: set GPU power limit (400–600 W)
│   ├── oc-memory.sh            # Main script: apply memory transfer-rate offset
│   └── oc-reset.sh             # Main script: reset offset to stock (0)
└── nvidia-tuner/
    ├── apply-default.sh        # Stock clocks, max power (0 core, 0 mem, 600 W)
    ├── apply-balanced.sh       # Undervolt profile: -75 core, +2500 mem, 500 W
    ├── apply-efficient.sh      # Undervolt profile: -125 core, +2500 mem, 450 W
    └── apply-max-efficiency.sh # Undervolt profile: -125 core, +3000 mem, 400 W
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `No targets match 'gpu:0'` | Wayland/Xwayland session or Coolbits not active | Log into an Xorg session, then restart display manager after installing config |
| Screen goes black / GPU reset | Offset too high | Run `oc-reset.sh` from a TTY (`Ctrl+Alt+F2`) |
| `nvidia-settings` not found | Package missing | `sudo apt install nvidia-settings` |
| Offset applied but clock unchanged | Driver ignoring offset at idle | Run a GPU load first |
| Coolbits installed but OC controls still missing | Wrong `BusID` in `10-coolbits.conf` | Run `lspci \| grep -i nvidia`, convert the address to `PCI:bus:device:function`, and update the `BusID` line (or omit it on single-GPU systems) |
