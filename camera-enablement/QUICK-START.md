# Samsung Galaxy Book5 Pro - Camera Enablement Quick Start

## Current Status: NOT WORKING

### Hardware Detected
- **IPU**: Intel IPU7 (device 8086:645d) - **DISABLED**
- **Camera**: OmniVision OV02E1 (2MP IR sensor for Windows Hello)
- **Status**: Hardware present but disabled at PCI level

### Blockers
1. IPU hardware disabled (no memory access, no bus master)
2. Camera sensor driver (ov02e1) missing from kernel
3. libcamera userspace stack not installed

## Quick Start: 3 Steps to Try

### Step 1: Enable in BIOS
```bash
# Reboot and enter BIOS (usually F2 during boot)
# Look for: Devices → Camera or Security → Camera
# Enable the camera/IPU option
```

### Step 2: Install Required Packages
```bash
sudo apt update
sudo apt install -y \
    libcamera0.3 \
    libcamera-tools \
    v4l-utils \
    gstreamer1.0-libcamera \
    pipewire-libcamera
```

### Step 3: Try Loading Drivers
```bash
# Load IPU driver
sudo modprobe intel-ipu6

# Load IVSC drivers
sudo modprobe ivsc-csi
sudo modprobe ivsc-ace

# Check for video devices
ls -la /dev/video*
v4l2-ctl --list-devices
```

## Advanced: Enable IPU Hardware

```bash
# Check current state
lspci -vvnn -s 00:05.0

# Try to enable PCI device (DANGEROUS - backup first!)
sudo setpci -s 00:05.0 COMMAND=0x0006

# Verify
lspci -vvnn -s 00:05.0
dmesg | grep -i ipu
```

## Check Status
```bash
# Is IPU enabled?
lspci -vvnn -s 00:05.0 | grep "Control:"
# Should see: "Control: I/O+ Mem+ BusMaster+"

# Are drivers loaded?
lsmod | grep -E 'ipu|ivsc'

# Are video devices present?
ls -la /dev/video*

# Test with libcamera
cam --list
```

## Key Files
- Full recon log: `/home/psychopunk_sage/dev/drivers/camera-enablement/camera-recon.log`
- IPU firmware: `/lib/firmware/intel/ipu/`
- Camera sensor: `/sys/bus/i2c/devices/i2c-OVTI02E1:00/`
- Privacy LED: `/sys/class/leds/OVTI02E1_00::privacy_led/`

## Next Steps if This Doesn't Work
1. Analyze ACPI DSDT to understand IPU power management
2. Search for Intel IPU7 driver (this is Lunar Lake, not standard IPU6)
3. Consider out-of-tree drivers from Intel GitHub
4. Wait for kernel 6.16+ with full Lunar Lake support

## Get Help
- See detailed findings: `camera-recon.log`
- Intel IPU drivers: https://github.com/intel/ipu6-drivers
- Linux media list: linux-media@vger.kernel.org
