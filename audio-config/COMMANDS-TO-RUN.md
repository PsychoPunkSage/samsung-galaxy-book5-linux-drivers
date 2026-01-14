# Samsung Galaxy Book5 Pro - EXACT COMMANDS TO FIX SPEAKERS

## Problem Statement

```bash
echo "0x17 0x3000 0xb000" > /sys/class/sound/hwC0D0/init_verbs
# FAILS with: sh: echo: I/O error
```

**Root Cause**: SOF driver doesn't support `init_verbs` sysfs interface.

**Solution**: Use `hda-verb` tool that works via hwdep interface.

---

## OPTION 1: Quick Manual Fix (Immediate, Not Persistent)

Copy and paste these commands:

```bash
# Install hda-verb tool
sudo apt-get update && sudo apt-get install -y alsa-tools

# Unmute Node 0x17 (Speaker Pin) - THIS WILL WORK
sudo hda-verb /dev/snd/hwC0D0 0x17 0x300 0xb000

# Test speakers (you should hear pink noise)
speaker-test -c2 -t wav -Dhw:0,0
```

Press Ctrl+C to stop the test when you hear sound.

---

## OPTION 2: Automated Installation (Recommended, Persistent)

This installs everything and makes it permanent:

```bash
# Navigate to audio config directory
cd /home/psychopunk_sage/dev/drivers/audio-config

# Run the automated installer (installs hda-verb, creates service, applies fix)
sudo ./install-sof-fix.sh

# Test speakers
speaker-test -c2 -t wav -Dhw:0,0
```

The installer does:
1. Installs `alsa-tools` package (contains hda-verb)
2. Creates `/usr/local/bin/sof-speaker-fix` command
3. Installs systemd service (runs on every boot)
4. Applies the fix immediately
5. Verifies the fix worked

---

## OPTION 3: Python Diagnostic Tool (Detailed Feedback)

First install hda-verb if not already installed:

```bash
sudo apt-get update && sudo apt-get install -y alsa-tools
```

Then run the diagnostic tool:

```bash
cd /home/psychopunk_sage/dev/drivers/audio-config
sudo python3 sof_speaker_fix.py
```

This shows:
- Whether hda-verb is installed
- Current mute state of Node 0x17
- Applies the unmute command
- Verifies the fix worked

---

## Verification

### Check Current State

```bash
# See if Node 0x17 is muted
cat /proc/asound/card0/codec#0 | grep -A5 "Node 0x17" | grep "Amp-Out vals"

# MUTED (bad):   Amp-Out vals:  [0x80 0x80]
# UNMUTED (good): Amp-Out vals:  [0x00 0x00]
```

### Test Speakers Work

```bash
# Test via ALSA directly
speaker-test -c2 -t wav -Dhw:0,0

# Test via PipeWire/PulseAudio
paplay /usr/share/sounds/alsa/Front_Center.wav

# Or play any audio in your browser/media player
```

---

## After Reboot

If you used OPTION 1 (manual fix), the unmute will be lost on reboot. You need to either:

**A) Run command again after each boot:**
```bash
sudo hda-verb /dev/snd/hwC0D0 0x17 0x300 0xb000
```

**B) Install the systemd service for automatic fix:**
```bash
cd /home/psychopunk_sage/dev/drivers/audio-config
sudo ./install-sof-fix.sh
```

**C) Use the installed command:**
```bash
sudo sof-speaker-fix
```

---

## Troubleshooting

### "hda-verb: command not found"

```bash
sudo apt-get update
sudo apt-get install -y alsa-tools
```

### "Permission denied" when running hda-verb

You MUST use sudo:
```bash
sudo hda-verb /dev/snd/hwC0D0 0x17 0x300 0xb000
```

### Still no sound after unmute

```bash
# 1. Check ALSA mixer levels
alsamixer -c 0
# Press F6 to select card 0
# Use arrow keys to find "Speaker" and "Master"
# Press M to unmute if needed
# Increase volume with Up arrow

# 2. Verify unmute worked
cat /proc/asound/card0/codec#0 | grep -A5 "Node 0x17" | grep "Amp-Out vals"
# Should show [0x00 0x00] not [0x80 0x80]

# 3. Check if PipeWire sees speakers
wpctl status
# Should list "Speaker" as an output

# 4. Try different test method
aplay -Dhw:0,0 /usr/share/sounds/alsa/Front_Center.wav
```

### Service not starting on boot

```bash
# Check service status
sudo systemctl status sof-speaker-unmute.service

# Check logs
sudo journalctl -u sof-speaker-unmute.service -n 50

# Manually start service
sudo systemctl start sof-speaker-unmute.service

# Re-enable service
sudo systemctl daemon-reload
sudo systemctl enable sof-speaker-unmute.service
```

---

## Technical Details

### What the command does

```bash
sudo hda-verb /dev/snd/hwC0D0 0x17 0x300 0xb000
         │                  │    │     │
         │                  │    │     └─ Parameter: 0xb000
         │                  │    │        (output amp, both channels, unmute, 0dB)
         │                  │    │
         │                  │    └─────── Verb: 0x300
         │                  │             (SET_AMP_GAIN_MUTE)
         │                  │
         │                  └──────────── Node: 0x17
         │                                (Speaker Pin Complex)
         │
         └─────────────────────────────── Device: /dev/snd/hwC0D0
                                          (Card 0, Codec 0)
```

### Why init_verbs doesn't work

| Driver Type | init_verbs Support | Working Method |
|-------------|-------------------|----------------|
| Legacy HDA (snd-hda-intel) | YES | sysfs init_verbs |
| SOF (snd-sof-pci) | NO | hda-verb via hwdep |

SOF uses DSP firmware and IPC messaging. The codec is accessed through hwdep ioctl interface, not direct sysfs writes.

### Alternative verbs

```bash
# Mute speaker
sudo hda-verb /dev/snd/hwC0D0 0x17 0x300 0xb080

# Unmute with +12dB boost
sudo hda-verb /dev/snd/hwC0D0 0x17 0x300 0xb00c

# Unmute left channel only
sudo hda-verb /dev/snd/hwC0D0 0x17 0x300 0xa000

# Unmute right channel only
sudo hda-verb /dev/snd/hwC0D0 0x17 0x300 0x9000
```

---

## Summary

**FASTEST FIX** (copy & paste):

```bash
sudo apt-get install -y alsa-tools && sudo hda-verb /dev/snd/hwC0D0 0x17 0x300 0xb000 && speaker-test -c2 -t wav -Dhw:0,0
```

**PERMANENT FIX** (run once, works forever):

```bash
cd /home/psychopunk_sage/dev/drivers/audio-config && sudo ./install-sof-fix.sh
```

---

## Files Created

All files are in `/home/psychopunk_sage/dev/drivers/audio-config/`:

- `COMMANDS-TO-RUN.md` - This file (quick reference)
- `QUICK-SOF-FIX.md` - One-page summary
- `SOF-SPEAKER-FIX.md` - Complete technical documentation
- `sof_speaker_fix.py` - Python diagnostic tool
- `install-sof-fix.sh` - Automated installer
- `sof-speaker-unmute.service` - systemd service file

---

**Last Updated**: 2026-01-14
**Platform**: Samsung Galaxy Book5 Pro (940XHA)
**OS**: Ubuntu 25.04, Kernel 6.14
**Audio Driver**: SOF (snd-sof-pci-intel-tgl)
**Codec**: Realtek ALC298
