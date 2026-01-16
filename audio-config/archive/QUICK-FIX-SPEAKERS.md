# Samsung Galaxy Book5 Pro - Speaker Fix (Quick Reference)

## Problem
Speaker shows in WirePlumber with volume 0.75, but **NO SOUND**.

## Root Cause
HDA codec internal mixer (Node 0x0d) is muted. This is NOT visible in ALSA mixer controls.

---

## IMMEDIATE FIX (Choose One)

### Option 1: Python Tool (Best - has diagnostics)
```bash
sudo python3 /home/psychopunk_sage/dev/drivers/audio-config/speaker_codec_fix.py
```

### Option 2: Shell Script
```bash
sudo /home/psychopunk_sage/dev/drivers/audio-config/fix-speaker-unmute.sh
```

### Option 3: Manual Commands
```bash
sudo sh -c 'echo "0x0d 0x7000 0xb000" > /sys/class/sound/hwC0D0/init_verbs'
sudo sh -c 'echo 1 > /sys/class/sound/hwC0D0/reconfig'
sleep 2
```

---

## TEST AUDIO
```bash
speaker-test -c2 -t wav -Dhw:0,0
```

or

```bash
aplay -Dhw:0,0 /usr/share/sounds/alsa/Front_Center.wav
```

---

## MAKE PERSISTENT (Run After Fix Works)

```bash
# Copy files to system locations
sudo cp /home/psychopunk_sage/dev/drivers/audio-config/speaker_codec_fix.py /usr/local/bin/
sudo cp /home/psychopunk_sage/dev/drivers/audio-config/speaker-unmute.service /etc/systemd/system/

# Enable service
sudo systemctl daemon-reload
sudo systemctl enable speaker-unmute.service
sudo systemctl start speaker-unmute.service

# Verify
sudo systemctl status speaker-unmute.service
```

---

## VERIFY FIX WORKED

### Before Fix (MUTED):
```bash
cat /proc/asound/card0/codec#0 | grep -A3 "Node 0x0d" | grep "Amp-In vals"
```
Output: `Amp-In vals:  [0x00 0x00]` (with internal mute bit set)

### After Fix (UNMUTED):
Same command should show mixer unmuted.

### Python verification:
```bash
python3 /home/psychopunk_sage/dev/drivers/audio-config/speaker_codec_fix.py --verify-only
```

---

## TROUBLESHOOTING

### Still no sound after fix?

1. Check ALSA mixer controls:
   ```bash
   amixer -c0 sget Speaker
   amixer -c0 sget Master
   ```
   Both should show `[on]` and volume > 0.

2. Check DAC is streaming:
   ```bash
   # Play audio, then check:
   cat /proc/asound/card0/codec#0 | grep -A3 "Node 0x03" | grep Converter
   ```
   Should show: `Converter: stream=1, channel=0`

3. Check SOF firmware:
   ```bash
   sudo dmesg | grep -i sof | tail -20
   ```

4. Test raw ALSA (bypass PipeWire):
   ```bash
   aplay -Dhw:0,0 /usr/share/sounds/alsa/Front_Center.wav
   ```

---

## TECHNICAL SUMMARY

**Codec**: Realtek ALC298 (Subsystem: 0x144dca08)
**Driver**: SOF (Sound Open Firmware) + HDA

**Audio Path**:
```
DAC (0x03) → Mixer (0x0d) → Speaker Pin (0x17) → Physical Speakers
                  ↑
            MUTED HERE!
```

**Fix**: Write HDA verb `0x0d 0x7000 0xb000` to unmute mixer input.

---

## FILES REFERENCE

All files in: `/home/psychopunk_sage/dev/drivers/audio-config/`

- **speaker_codec_fix.py** - Python fix tool (RECOMMENDED)
- **fix-speaker-unmute.sh** - Bash fix script
- **speaker-unmute.service** - Systemd service for persistence
- **SPEAKER-FIX-GUIDE.md** - Complete technical documentation
- **QUICK-FIX-SPEAKERS.md** - This file
- **README.md** - UCM configuration + fix guide

---

## ONE-LINER FIX

```bash
sudo sh -c 'echo "0x0d 0x7000 0xb000" > /sys/class/sound/hwC0D0/init_verbs && echo 1 > /sys/class/sound/hwC0D0/reconfig' && sleep 2 && speaker-test -c2 -t wav -Dhw:0,0
```

Press Ctrl+C to stop test when you hear sound.

---

**Date**: 2026-01-14
**Status**: TESTED - Fix confirmed working
