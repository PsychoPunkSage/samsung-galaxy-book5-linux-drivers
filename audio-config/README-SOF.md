# Samsung Galaxy Book5 Pro - Audio Fix for SOF Driver

## Critical Issue: init_verbs I/O Error

If you're seeing this error:

```bash
echo "0x17 0x3000 0xb000" > /sys/class/sound/hwC0D0/init_verbs
sh: echo: I/O error
```

**You're using the SOF driver, which doesn't support the init_verbs interface.**

This README provides the correct solution.

---

## Quick Start (90 Seconds to Working Speakers)

### Step 1: Install hda-verb tool
```bash
sudo apt-get update && sudo apt-get install -y alsa-tools
```

### Step 2: Unmute speakers
```bash
sudo hda-verb /dev/snd/hwC0D0 0x17 0x300 0xb000
```

### Step 3: Test
```bash
speaker-test -c2 -t wav -Dhw:0,0
```

**DONE.** You should hear pink noise from both speakers.

Press Ctrl+C to stop the test.

---

## Make It Permanent (Survives Reboots)

The manual fix above will be lost on reboot. To make it permanent:

```bash
cd /home/psychopunk_sage/dev/drivers/audio-config
sudo ./install-sof-fix.sh
```

This one-line installer:
1. Installs alsa-tools package
2. Creates systemd service that runs on boot
3. Creates `/usr/local/bin/sof-speaker-fix` command
4. Applies the fix immediately
5. Enables automatic fix on every boot

Reboot and test - speakers will work automatically.

---

## Understanding the Problem

### What is SOF?

**SOF (Sound Open Firmware)** is Intel's modern audio architecture for laptops with:
- Digital Signal Processor (DSP) for audio processing
- Low-power audio during sleep (S0ix)
- Advanced audio features (noise cancellation, echo suppression)

Your Samsung Galaxy Book5 Pro uses SOF instead of legacy HDA.

### Why Old Methods Don't Work

| Method | Legacy HDA | SOF Driver | Why |
|--------|-----------|------------|-----|
| `init_verbs` sysfs | Works | **Fails** | SOF doesn't expose this interface |
| `reconfig` sysfs | Works | **Fails** | Not implemented in SOF |
| `hda-verb` tool | Works | **Works** | Uses hwdep ioctl (universal) |
| Direct hwdep | Works | **Works** | Low-level interface |

**The old scripts in this directory (`speaker_codec_fix.py`, `fix-speaker-unmute.sh`) try to use init_verbs and will fail on SOF.**

### The New Solution

Use `hda-verb` tool which works with both legacy HDA and SOF:

```bash
# Old method (fails on SOF):
echo "0x17 0x3000 0xb000" > /sys/class/sound/hwC0D0/init_verbs

# New method (works on SOF):
hda-verb /dev/snd/hwC0D0 0x17 0x300 0xb000
```

---

## File Guide

### NEW FILES (SOF-compatible)

These work with SOF driver:

| File | Purpose | Usage |
|------|---------|-------|
| `COMMANDS-TO-RUN.md` | Quick reference | Read this first |
| `QUICK-SOF-FIX.md` | One-page summary | TL;DR version |
| `SOF-SPEAKER-FIX.md` | Complete technical docs | Deep dive |
| `sof_speaker_fix.py` | Python diagnostic tool | `sudo python3 sof_speaker_fix.py` |
| `install-sof-fix.sh` | Automated installer | `sudo ./install-sof-fix.sh` |
| `sof-speaker-unmute.service` | systemd service | Auto-runs on boot |
| `README-SOF.md` | This file | Overview |

### OLD FILES (Legacy HDA only)

These **will fail** on SOF driver (kept for reference):

| File | Purpose | Note |
|------|---------|------|
| `speaker_codec_fix.py` | Old Python fix | Uses init_verbs (fails on SOF) |
| `fix-speaker-unmute.sh` | Old bash fix | Uses init_verbs (fails on SOF) |
| `speaker-unmute.service` | Old service | Calls old script (fails) |
| `README.md` | Old documentation | Pre-SOF support |

### UCM2 Configuration

| Directory | Purpose | Status |
|-----------|---------|--------|
| `ucm2/` | ALSA Use Case Manager config | Works with SOF |

UCM2 configuration is still needed and works fine with SOF. Install it:

```bash
cd /home/psychopunk_sage/dev/drivers/audio-config
sudo ./install.sh
```

---

## Complete Setup (Recommended)

For full audio functionality, do both:

### 1. Install UCM2 Configuration
```bash
cd /home/psychopunk_sage/dev/drivers/audio-config
sudo ./install.sh
```

This configures:
- Speaker/headphone routing
- Microphone routing (headset mic + DMIC)
- Jack detection
- PipeWire integration

### 2. Install SOF Speaker Fix
```bash
cd /home/psychopunk_sage/dev/drivers/audio-config
sudo ./install-sof-fix.sh
```

This fixes:
- Speaker hardware mute issue
- Makes fix persistent across reboots

### 3. Test Everything
```bash
# Test speakers
speaker-test -c2 -t wav -Dhw:0,0

# Test DMIC (internal microphone)
arecord -D hw:0,6 -f S16_LE -r 48000 -c 2 -d 3 test.wav && aplay test.wav

# Test headphone jack detection
amixer -c 0 events
# Plug/unplug headphones, should see events
```

---

## Verification Commands

### Check if SOF driver is loaded
```bash
cat /proc/asound/cards
# Should show: sof-hda-dsp

lsmod | grep sof
# Should show: snd_sof_pci_intel_tgl
```

### Check codec info
```bash
cat /proc/asound/card0/codec#0 | head -20
# Should show: Codec: Realtek ALC298
```

### Check Node 0x17 mute state
```bash
cat /proc/asound/card0/codec#0 | grep -A5 "Node 0x17" | grep "Amp-Out vals"

# MUTED (bad):    Amp-Out vals:  [0x80 0x80]
# UNMUTED (good): Amp-Out vals:  [0x00 0x00]
```

### Check if hda-verb works
```bash
which hda-verb
# Should show: /usr/bin/hda-verb

# Test reading from codec
hda-verb /dev/snd/hwC0D0 0x17 0xf00 0x0000
# Should return: value = 0x00xxxxxx
```

### Check systemd service
```bash
sudo systemctl status sof-speaker-unmute.service
# Should show: active (exited) ... success

sudo journalctl -u sof-speaker-unmute.service -n 20
# Should show no errors
```

---

## Troubleshooting

### Still getting I/O error

If you still see:
```bash
echo "0x17 0x3000 0xb000" > /sys/class/sound/hwC0D0/init_verbs
sh: echo: I/O error
```

**This is expected behavior with SOF driver.** Stop trying to use init_verbs. Use hda-verb instead:

```bash
sudo hda-verb /dev/snd/hwC0D0 0x17 0x300 0xb000
```

### hda-verb not found

```bash
sudo apt-get update
sudo apt-get install -y alsa-tools

# Verify installation
which hda-verb
dpkg -l | grep alsa-tools
```

### Speakers still silent after fix

1. Check unmute actually worked:
```bash
cat /proc/asound/card0/codec#0 | grep -A5 "Node 0x17" | grep "Amp-Out vals"
```

2. Check ALSA mixer levels:
```bash
alsamixer -c 0
# Use arrow keys to find Speaker and Master
# Press M to unmute if needed
# Increase volume with Up arrow
```

3. Check PipeWire routing:
```bash
wpctl status
# Should show Speaker as available sink

wpctl set-default <speaker-id>
```

4. Test different output methods:
```bash
# Direct ALSA
aplay -Dhw:0,0 /usr/share/sounds/alsa/Front_Center.wav

# Via PipeWire
paplay /usr/share/sounds/alsa/Front_Center.wav

# Raw speaker test
speaker-test -c2 -t wav -Dhw:0,0
```

### Fix doesn't survive reboot

You need the systemd service:

```bash
cd /home/psychopunk_sage/dev/drivers/audio-config
sudo ./install-sof-fix.sh

# Verify service is enabled
sudo systemctl is-enabled sof-speaker-unmute.service
# Should show: enabled

# Check service starts on boot
sudo systemctl status sof-speaker-unmute.service
```

### Permission denied

hda-verb requires root access:

```bash
# Wrong (will fail):
hda-verb /dev/snd/hwC0D0 0x17 0x300 0xb000

# Correct:
sudo hda-verb /dev/snd/hwC0D0 0x17 0x300 0xb000
```

Or add user to audio group (requires re-login):

```bash
sudo usermod -aG audio $USER
# Log out and log back in
```

---

## Technical Background

### Why Node 0x17 is Muted

The Samsung Galaxy Book5 Pro has this audio path:

```
DAC 0x03 (Audio Output)
    ↓
Mixer 0x0d (Audio Mixer)
    ↓
Pin 0x17 (Speaker Pin) ← Hardware muted by default
    ↓
Physical Speakers
```

The BIOS/UEFI firmware initializes the codec, but doesn't unmute Pin 0x17. Linux SOF firmware also doesn't unmute it during initialization.

### HDA Verb Format

```bash
hda-verb /dev/snd/hwC0D0 0x17 0x300 0xb000
```

Breaking down `0x300 0xb000`:

**Verb: 0x300** = SET_AMP_GAIN_MUTE
- This is the HDA command to set amplifier gain and mute state

**Parameter: 0xb000** (binary: 1011 0000 0000 0000)
- Bit 15 (1): Output amplifier (vs. input)
- Bit 14 (0): Reserved
- Bit 13 (1): Set left channel
- Bit 12 (1): Set right channel
- Bits 11-8 (0000): Reserved
- Bit 7 (0): **Unmute** (1 would mute)
- Bits 6-0 (0000000): Gain = 0dB

### SOF vs HDA Architecture

**Legacy HDA (snd-hda-intel):**
```
Application → ALSA → Kernel Driver → PCI Register Access → Codec
```

**SOF (snd-sof-pci-intel-tgl):**
```
Application → ALSA → Kernel Driver → IPC → DSP Firmware → Codec
```

The extra DSP firmware layer is why init_verbs doesn't work - there's no direct PCI register access for verb writes. Instead, we use the hwdep ioctl interface which works with both architectures.

### Device Files

```bash
/dev/snd/
├── hwC0D0       # Codec 0 on Card 0 (hwdep interface)
├── hwC0D2       # Codec 2 on Card 0 (HDMI)
├── pcmC0D0p     # PCM device 0 (analog output)
├── pcmC0D3p     # PCM device 3 (HDMI1)
├── pcmC0D6c     # PCM device 6 (DMIC capture)
└── controlC0    # Control interface
```

hda-verb communicates with `/dev/snd/hwC0D0` using ioctl calls.

---

## Alternative Methods

### Method 1: GUI Tool (hdajackretask)

```bash
sudo apt-get install -y alsa-tools-gui
sudo hdajackretask
```

1. Select "0 - Realtek ALC298"
2. Find "0x17 Internal speaker"
3. Check "Override"
4. Click "Apply now"
5. Click "Install boot override" for persistence

### Method 2: Direct C Program

See `SOF-SPEAKER-FIX.md` for a complete C implementation using hwdep ioctl.

### Method 3: Python with ctypes

You can also use Python ctypes to call ioctl directly without hda-verb binary dependency. See `SOF-SPEAKER-FIX.md` for example.

---

## Upstream Status

### Kernel Patch Needed

This issue should be fixed upstream in the Linux kernel. The proper fix is a quirk in `sound/pci/hda/patch_realtek.c`:

```c
SND_PCI_QUIRK(0x144d, 0xca08, "Samsung Galaxy Book5 Pro",
              ALC298_FIXUP_SAMSUNG_GALAXY_BOOK5),
```

With a fixup chain that unmutes Pin 0x17 during initialization.

### SOF Topology

Alternatively, the SOF firmware topology could be fixed to unmute Pin 0x17 in the topology file for this device.

### How You Can Help

If you want to contribute upstream:

1. Test the fix thoroughly
2. Document your hardware (run `sudo alsa-info.sh --upload`)
3. Report the issue to ALSA mailing list (alsa-devel@alsa-project.org)
4. Propose a kernel patch with DMI quirk

See `SOF-SPEAKER-FIX.md` section "Contributing Upstream" for details.

---

## Summary

| Task | Command | Frequency |
|------|---------|-----------|
| **Install fix** | `cd /home/psychopunk_sage/dev/drivers/audio-config && sudo ./install-sof-fix.sh` | Once |
| **Manual unmute** | `sudo hda-verb /dev/snd/hwC0D0 0x17 0x300 0xb000` | Each boot (if no service) |
| **Test speakers** | `speaker-test -c2 -t wav -Dhw:0,0` | Anytime |
| **Check status** | `sudo systemctl status sof-speaker-unmute.service` | Anytime |

---

## Further Reading

- `COMMANDS-TO-RUN.md` - Quick command reference
- `QUICK-SOF-FIX.md` - One-page summary
- `SOF-SPEAKER-FIX.md` - Complete technical documentation (16KB, all solutions)
- `/usr/share/doc/alsa-tools/` - hda-verb documentation

---

## Support

If you're still having issues:

1. Verify you're running SOF driver:
```bash
cat /proc/asound/cards
```

2. Verify Node 0x17 exists:
```bash
cat /proc/asound/card0/codec#0 | grep -A20 "Node 0x17"
```

3. Check kernel logs:
```bash
sudo dmesg | grep -iE "sof|alc298|audio|firmware"
```

4. Run the diagnostic tool:
```bash
cd /home/psychopunk_sage/dev/drivers/audio-config
sudo python3 sof_speaker_fix.py
```

5. Check the complete documentation:
```bash
cat /home/psychopunk_sage/dev/drivers/audio-config/SOF-SPEAKER-FIX.md
```

---

**Platform**: Samsung Galaxy Book5 Pro (940XHA)
**OS**: Ubuntu 25.04, Kernel 6.14
**Audio**: SOF driver (snd-sof-pci-intel-tgl)
**Codec**: Realtek ALC298 (Subsystem: 0x144dca08)
**Last Updated**: 2026-01-14
**Status**: WORKING - Solution verified
