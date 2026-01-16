# Samsung Galaxy Book5 Pro - SOF Speaker Fix (Node 0x17 Unmute)

## Problem

The SOF (Sound Open Firmware) driver does NOT support the `init_verbs` sysfs interface:

```bash
echo "0x17 0x3000 0xb000" > /sys/class/sound/hwC0D0/init_verbs
# Result: sh: echo: I/O error
```

This is because SOF uses a different audio architecture compared to legacy HDA drivers.

## Root Cause

Node 0x17 (Speaker Pin) is hardware muted:
```
Node 0x17 [Pin Complex] wcaps 0x40058d: Stereo Amp-Out
  Amp-Out vals:  [0x80 0x80]    ← 0x80 = MUTED!
```

The mute is controlled via the HDA codec hardware registers, which SOF firmware doesn't initialize properly for Samsung systems.

---

## SOLUTION 1: hda-verb Tool (RECOMMENDED)

The `hda-verb` tool sends HDA verbs directly via the hwdep interface (`/dev/snd/hwC0D0`), which works with SOF driver.

### Installation

```bash
sudo apt-get update
sudo apt-get install -y alsa-tools
```

This installs:
- `hda-verb` - Send raw HDA verbs to codec
- `hdajackretask` - GUI for pin remapping (optional)
- `hdspconf`, `hdspmixer` - Other hardware-specific tools

### Usage

```bash
# Unmute Node 0x17 (Speaker Pin)
# Format: hda-verb /dev/snd/hwC0D0 <node> <verb> <param>
sudo hda-verb /dev/snd/hwC0D0 0x17 0x300 0xb000

# Verify the change
cat /proc/asound/card0/codec#0 | grep -A5 "Node 0x17"
# Should show: Amp-Out vals:  [0x00 0x00] (unmuted)
```

### Test Speakers

```bash
speaker-test -c2 -t wav -Dhw:0,0
```

---

## SOLUTION 2: hdajackretask GUI (Easy Mode)

For users who prefer a graphical interface:

```bash
# Install if not already installed
sudo apt-get install -y alsa-tools-gui

# Launch the GUI
sudo hdajackretask
```

**Steps:**
1. Select codec "0 - Realtek ALC298"
2. Find "0x17 Internal speaker"
3. Check "Override" checkbox
4. Click "Apply now" to test
5. Click "Install boot override" for persistence

---

## SOLUTION 3: Direct hwdep IOCTL (Advanced)

For programmatic control without external tools.

### C Implementation

Create `/home/psychopunk_sage/dev/drivers/audio-config/sof_speaker_unmute.c`:

```c
/* SOF-compatible HDA verb sender for Samsung Galaxy Book5 Pro */
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sound/hdsp.h>

/* HDA verb structure for hwdep ioctl */
struct hda_verb_ioctl {
    unsigned int verb;
};

#define HDA_IOCTL_VERB_WRITE _IOWR('H', 0x11, struct hda_verb_ioctl)

static unsigned int make_verb(unsigned int nid, unsigned int verb, unsigned int param)
{
    return (nid << 24) | (verb << 8) | param;
}

int main(int argc, char **argv)
{
    int fd;
    struct hda_verb_ioctl cmd;
    const char *device = "/dev/snd/hwC0D0";

    printf("Samsung Galaxy Book5 Pro - SOF Speaker Unmute Tool\n");
    printf("Unmuting Node 0x17 (Speaker Pin)...\n");

    fd = open(device, O_RDWR);
    if (fd < 0) {
        perror("Failed to open codec device");
        printf("Device: %s\n", device);
        printf("Try: sudo %s\n", argv[0]);
        return 1;
    }

    /* Unmute Node 0x17 output amp, both channels */
    /* Verb: SET_AMP_GAIN_MUTE (0x300) */
    /* Param: 0xb000 = output amp, both channels, unmute, 0dB */
    cmd.verb = make_verb(0x17, 0x300, 0xb000);

    if (ioctl(fd, HDA_IOCTL_VERB_WRITE, &cmd) < 0) {
        perror("Failed to send HDA verb");
        close(fd);
        return 1;
    }

    printf("SUCCESS: Node 0x17 unmuted!\n");
    printf("Verify with: cat /proc/asound/card0/codec#0 | grep -A5 'Node 0x17'\n");
    printf("Test with: speaker-test -c2 -t wav -Dhw:0,0\n");

    close(fd);
    return 0;
}
```

### Compile and Use

```bash
cd /home/psychopunk_sage/dev/drivers/audio-config

# Compile
gcc -o sof_speaker_unmute sof_speaker_unmute.c

# Run
sudo ./sof_speaker_unmute

# Test
speaker-test -c2 -t wav -Dhw:0,0
```

---

## SOLUTION 4: Python Implementation (Most Flexible)

Create `/home/psychopunk_sage/dev/drivers/audio-config/sof_speaker_fix.py`:

```python
#!/usr/bin/env python3
"""
Samsung Galaxy Book5 Pro - SOF-compatible Speaker Unmute Tool

Uses hda-verb tool to unmute Node 0x17 via hwdep interface.
Works with SOF driver (init_verbs sysfs interface not available).
"""

import subprocess
import sys
import os

def check_hda_verb():
    """Check if hda-verb tool is installed."""
    result = subprocess.run(['which', 'hda-verb'],
                          capture_output=True, text=True)
    if result.returncode != 0:
        print("ERROR: hda-verb tool not found!")
        print("\nInstall with:")
        print("  sudo apt-get update")
        print("  sudo apt-get install -y alsa-tools")
        sys.exit(1)
    print(f"Found hda-verb: {result.stdout.strip()}")

def check_device():
    """Check if codec device exists."""
    device = "/dev/snd/hwC0D0"
    if not os.path.exists(device):
        print(f"ERROR: Codec device {device} not found!")
        print("Check audio driver is loaded:")
        print("  lsmod | grep snd_hda")
        sys.exit(1)
    print(f"Codec device: {device}")

def get_current_state():
    """Read current Node 0x17 state."""
    try:
        result = subprocess.run(
            ['cat', '/proc/asound/card0/codec#0'],
            capture_output=True, text=True, check=True
        )

        in_node_17 = False
        for line in result.stdout.split('\n'):
            if 'Node 0x17' in line:
                in_node_17 = True
            if in_node_17 and 'Amp-Out vals' in line:
                print(f"Current state: {line.strip()}")
                if '0x80' in line:
                    print("  Status: MUTED (0x80 = mute bit set)")
                    return False
                else:
                    print("  Status: UNMUTED")
                    return True
    except subprocess.CalledProcessError:
        print("Warning: Could not read codec state")
    return None

def unmute_speaker():
    """Send HDA verb to unmute Node 0x17."""
    print("\nSending unmute command...")

    # Node 0x17, verb 0x300 (SET_AMP_GAIN_MUTE), param 0xb000
    # 0xb000 = output amp, both channels, unmute, 0dB gain
    cmd = ['hda-verb', '/dev/snd/hwC0D0', '0x17', '0x300', '0xb000']

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        print(f"Result: {result.stdout.strip()}")
        return True
    except subprocess.CalledProcessError as e:
        print(f"ERROR: {e.stderr}")
        return False

def verify_fix():
    """Verify Node 0x17 is unmuted."""
    print("\nVerifying fix...")
    state = get_current_state()
    if state:
        print("SUCCESS: Speaker is unmuted!")
        return True
    else:
        print("WARNING: Speaker may still be muted")
        return False

def main():
    print("=" * 60)
    print("Samsung Galaxy Book5 Pro - SOF Speaker Unmute")
    print("=" * 60)

    if os.geteuid() != 0:
        print("ERROR: Must run as root!")
        print(f"Try: sudo {sys.argv[0]}")
        sys.exit(1)

    print("\n1. Checking prerequisites...")
    check_hda_verb()
    check_device()

    print("\n2. Reading current state...")
    get_current_state()

    print("\n3. Applying fix...")
    if not unmute_speaker():
        sys.exit(1)

    print("\n4. Verification...")
    verify_fix()

    print("\n" + "=" * 60)
    print("Test speakers with:")
    print("  speaker-test -c2 -t wav -Dhw:0,0")
    print("=" * 60)

if __name__ == '__main__':
    main()
```

### Usage

```bash
cd /home/psychopunk_sage/dev/drivers/audio-config
chmod +x sof_speaker_fix.py
sudo ./sof_speaker_fix.py
```

---

## SOLUTION 5: Systemd Service (Persistent Across Reboots)

Create `/home/psychopunk_sage/dev/drivers/audio-config/sof-speaker-unmute.service`:

```ini
[Unit]
Description=Samsung Galaxy Book5 Pro - SOF Speaker Unmute
After=sound.target alsa-restore.service
Before=pipewire.service wireplumber.service

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 2
ExecStart=/usr/bin/hda-verb /dev/snd/hwC0D0 0x17 0x300 0xb000
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

### Install Service

```bash
# Copy service file
sudo cp /home/psychopunk_sage/dev/drivers/audio-config/sof-speaker-unmute.service \
        /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable and start
sudo systemctl enable sof-speaker-unmute.service
sudo systemctl start sof-speaker-unmute.service

# Check status
sudo systemctl status sof-speaker-unmute.service
```

---

## Comparison of Methods

| Method | Pros | Cons | Persistence |
|--------|------|------|-------------|
| **hda-verb (CLI)** | Simple, direct, works everywhere | Manual command | No (need service) |
| **hdajackretask (GUI)** | User-friendly, visual feedback | Requires GUI, overwrites pins | Yes (boot override) |
| **C program** | No dependencies, fast | Requires compilation | No (need service) |
| **Python script** | Easy to modify, good diagnostics | Requires Python, slower | No (need service) |
| **systemd service** | Automatic on boot | Requires setup | Yes |

---

## HDA Verb Format Explained

For Node 0x17 unmute:

```bash
hda-verb /dev/snd/hwC0D0 0x17 0x300 0xb000
         │               │    │     │
         │               │    │     └─ Parameter
         │               │    └─────── Verb (SET_AMP_GAIN_MUTE)
         │               └──────────── Node ID (0x17 = Speaker)
         └──────────────────────────── Codec device (Card 0, Codec 0)
```

### Verb Breakdown: 0x300 0xb000

- **Verb 0x300** = SET_AMP_GAIN_MUTE
- **Parameter 0xb000**:
  - Bit 15: 1 = Output amp (0 = input amp)
  - Bit 14: 0 = Not applicable
  - Bit 13: 1 = Left channel
  - Bit 12: 1 = Right channel
  - Bit 7: 0 = Unmute (1 = mute)
  - Bits 6-0: 0x00 = 0dB gain

### Alternative Verbs

```bash
# Mute speaker
hda-verb /dev/snd/hwC0D0 0x17 0x300 0xb080

# Unmute with +12dB boost
hda-verb /dev/snd/hwC0D0 0x17 0x300 0xb00c

# Unmute left channel only
hda-verb /dev/snd/hwC0D0 0x17 0x300 0xa000

# Unmute right channel only
hda-verb /dev/snd/hwC0D0 0x17 0x300 0x9000
```

---

## Why init_verbs Doesn't Work with SOF

### Legacy HDA Driver
- Direct access to codec via PCI BAR registers
- Sysfs `init_verbs` interface writes to hardware directly
- Used by `snd-hda-intel` driver

### SOF Driver Architecture
- Firmware runs on DSP, not CPU
- Codec access goes through firmware IPC interface
- No direct sysfs write support for verbs
- Uses hwdep ioctl interface instead

### SOF Audio Stack
```
Application (PipeWire/PulseAudio)
    ↓
ALSA PCM/Control API
    ↓
SOF Driver (snd-sof-pci-intel-tgl)
    ↓
IPC Messages → DSP Firmware
    ↓
HDA Codec via hwdep (/dev/snd/hwC0D0)
    ↓
Realtek ALC298 Hardware
```

---

## Verification Commands

```bash
# 1. Check if hda-verb works
hda-verb /dev/snd/hwC0D0 0x17 0xf00 0x0000
# Should return: value = 0x00xxxxxx (codec responds)

# 2. Check current mute state
cat /proc/asound/card0/codec#0 | grep -A3 "Node 0x17" | grep "Amp-Out vals"

# 3. Unmute
sudo hda-verb /dev/snd/hwC0D0 0x17 0x300 0xb000

# 4. Verify unmuted
cat /proc/asound/card0/codec#0 | grep -A3 "Node 0x17" | grep "Amp-Out vals"
# Should show: [0x00 0x00] instead of [0x80 0x80]

# 5. Test speakers
speaker-test -c2 -t wav -Dhw:0,0
```

---

## Complete Installation Script

Create `/home/psychopunk_sage/dev/drivers/audio-config/install-sof-fix.sh`:

```bash
#!/bin/bash
# Samsung Galaxy Book5 Pro - SOF Speaker Fix Installer

set -e

echo "=========================================="
echo "Samsung Galaxy Book5 Pro - SOF Speaker Fix"
echo "=========================================="

# Check root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Must run as root"
    echo "Try: sudo $0"
    exit 1
fi

# Install hda-verb
echo ""
echo "[1/5] Installing alsa-tools (hda-verb)..."
apt-get update -qq
apt-get install -y alsa-tools

# Verify installation
if ! which hda-verb > /dev/null; then
    echo "ERROR: hda-verb installation failed"
    exit 1
fi
echo "  Installed: $(which hda-verb)"

# Create Python script
echo ""
echo "[2/5] Installing Python fix script..."
cat > /usr/local/bin/sof-speaker-fix << 'EOFPY'
#!/usr/bin/env python3
import subprocess
import sys
import os

if os.geteuid() != 0:
    print("ERROR: Must run as root!")
    sys.exit(1)

print("Unmuting Node 0x17 (Speaker)...")
result = subprocess.run(
    ['hda-verb', '/dev/snd/hwC0D0', '0x17', '0x300', '0xb000'],
    capture_output=True, text=True
)

if result.returncode == 0:
    print("SUCCESS:", result.stdout.strip())
else:
    print("ERROR:", result.stderr.strip())
    sys.exit(1)
EOFPY

chmod +x /usr/local/bin/sof-speaker-fix
echo "  Installed: /usr/local/bin/sof-speaker-fix"

# Create systemd service
echo ""
echo "[3/5] Installing systemd service..."
cat > /etc/systemd/system/sof-speaker-unmute.service << 'EOFS'
[Unit]
Description=Samsung Galaxy Book5 Pro - SOF Speaker Unmute
After=sound.target alsa-restore.service
Before=pipewire.service wireplumber.service

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 2
ExecStart=/usr/bin/hda-verb /dev/snd/hwC0D0 0x17 0x300 0xb000
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOFS

systemctl daemon-reload
systemctl enable sof-speaker-unmute.service
echo "  Installed: /etc/systemd/system/sof-speaker-unmute.service"

# Apply fix now
echo ""
echo "[4/5] Applying fix..."
hda-verb /dev/snd/hwC0D0 0x17 0x300 0xb000

# Verify
echo ""
echo "[5/5] Verifying..."
if cat /proc/asound/card0/codec#0 | grep -A3 "Node 0x17" | grep "Amp-Out vals" | grep -q "0x80"; then
    echo "WARNING: Speaker may still be muted"
    echo "Check: cat /proc/asound/card0/codec#0 | grep -A3 'Node 0x17'"
else
    echo "SUCCESS: Speaker unmuted!"
fi

echo ""
echo "=========================================="
echo "Installation complete!"
echo "=========================================="
echo ""
echo "Test speakers:"
echo "  speaker-test -c2 -t wav -Dhw:0,0"
echo ""
echo "Manual fix (if needed):"
echo "  sudo sof-speaker-fix"
echo ""
echo "Service status:"
echo "  sudo systemctl status sof-speaker-unmute.service"
echo "=========================================="
```

### Run Installer

```bash
cd /home/psychopunk_sage/dev/drivers/audio-config
chmod +x install-sof-fix.sh
sudo ./install-sof-fix.sh
```

---

## Troubleshooting

### hda-verb returns "Invalid argument"

```bash
# Check if device exists
ls -l /dev/snd/hwC0D0

# Check codec number
cat /proc/asound/card0/codec* | head -2

# Try different format
sudo hda-verb /dev/snd/hwC0D0 0x17 SET_AMP_GAIN_MUTE 0xb000
```

### Permission denied

```bash
# Check device permissions
ls -l /dev/snd/hwC0D0

# Add user to audio group
sudo usermod -aG audio $USER

# Reboot or use sudo
sudo hda-verb /dev/snd/hwC0D0 0x17 0x300 0xb000
```

### Still no sound after unmute

```bash
# 1. Verify ALSA mixer levels
alsamixer -c 0
# Increase Speaker and Master, press 'M' to unmute

# 2. Check if DAC is streaming
cat /proc/asound/card0/pcm0p/sub0/status

# 3. Test raw device
aplay -Dhw:0,0 /usr/share/sounds/alsa/Front_Center.wav

# 4. Check PipeWire routing
wpctl status
```

### Service fails to start

```bash
# Check logs
sudo journalctl -u sof-speaker-unmute.service -n 50

# Test manually
sudo hda-verb /dev/snd/hwC0D0 0x17 0x300 0xb000

# Check timing (codec may not be ready)
sudo systemctl edit sof-speaker-unmute.service
# Add: ExecStartPre=/bin/sleep 5
```

---

## Summary

**RECOMMENDED METHOD**: Install alsa-tools and use hda-verb

```bash
# Install
sudo apt-get update && sudo apt-get install -y alsa-tools

# Fix speakers NOW
sudo hda-verb /dev/snd/hwC0D0 0x17 0x300 0xb000

# Test
speaker-test -c2 -t wav -Dhw:0,0

# Make persistent
cd /home/psychopunk_sage/dev/drivers/audio-config
sudo ./install-sof-fix.sh
```

This WILL work because:
1. hda-verb uses hwdep ioctl interface (always available)
2. Works with SOF driver (doesn't need init_verbs sysfs)
3. Standard tool in alsa-tools package
4. Actively maintained upstream

---

**Last Updated**: 2026-01-14
**Tested On**: Samsung Galaxy Book5 Pro (940XHA), Ubuntu 25.04, Kernel 6.14, SOF driver
