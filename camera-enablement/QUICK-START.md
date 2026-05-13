# Camera Enablement — Samsung Galaxy Book5 Pro

**Status: NOT WORKING**

> For a working reference on camera fixes for related Samsung models, see:
> **[Andycodeman/samsung-galaxy-book4-linux-fixes](https://github.com/Andycodeman/samsung-galaxy-book4-linux-fixes)**

---

## Hardware

- **IPU**: Intel IPU7 (8086:645d) — disabled at PCI level
- **Camera**: OmniVision OV02E1 (2MP IR, Windows Hello)

## Blockers

1. IPU hardware disabled (no memory access, no bus master)
2. `ov02e1` camera sensor driver missing from kernel
3. libcamera userspace stack not installed

---

## Step 1: Enable in BIOS

Reboot → F2 → Devices → Camera (or Security → Camera) → Enable

## Step 2: Install Packages

```bash
sudo apt install -y libcamera0.3 libcamera-tools v4l-utils gstreamer1.0-libcamera pipewire-libcamera
```

## Step 3: Load Drivers

```bash
sudo modprobe intel-ipu6
sudo modprobe ivsc-csi
sudo modprobe ivsc-ace
ls -la /dev/video*
v4l2-ctl --list-devices
```

---

## Enable IPU Hardware (experimental)

```bash
# Check current state
lspci -vvnn -s 00:05.0

# Enable PCI device — backup first
sudo setpci -s 00:05.0 COMMAND=0x0006

lspci -vvnn -s 00:05.0
dmesg | grep -i ipu
```

## Status Checks

```bash
lspci -vvnn -s 00:05.0 | grep "Control:"   # want: Mem+ BusMaster+
lsmod | grep -E 'ipu|ivsc'
ls -la /dev/video*
cam --list
```

## Relevant Paths

- Full recon log: `camera-recon.log`
- IPU firmware: `/lib/firmware/intel/ipu/`
- Camera sensor: `/sys/bus/i2c/devices/i2c-OVTI02E1:00/`
- Privacy LED: `/sys/class/leds/OVTI02E1_00::privacy_led/`

## Next Steps

1. Analyze ACPI DSDT for IPU power management
2. This is Lunar Lake (IPU7) — not covered by standard `ipu6-drivers`
3. Track Intel IPU7 upstream: https://github.com/intel/ipu6-drivers
4. Wait for kernel 6.16+ with full Lunar Lake support
