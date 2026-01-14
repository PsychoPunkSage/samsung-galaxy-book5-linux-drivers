# Samsung Galaxy Book5 Pro Audio Configuration

## CRITICAL FIX: Speakers Visible but No Sound

### Quick Fix (Do This First!)

If speakers show in WirePlumber but produce no sound, you need to unmute the HDA codec mixer:

```bash
# Option 1: Python tool (recommended - best diagnostics)
sudo python3 /home/psychopunk_sage/dev/drivers/speaker_codec_fix.py

# Option 2: Shell script
sudo /home/psychopunk_sage/dev/drivers/fix-speaker-unmute.sh

# Option 3: Manual fix
sudo sh -c 'echo "0x0d 0x7000 0xb000" > /sys/class/sound/hwC0D0/init_verbs'
sudo sh -c 'echo 1 > /sys/class/sound/hwC0D0/reconfig'
```

Then test:
```bash
speaker-test -c2 -t wav -Dhw:0,0
```

See **`SPEAKER-FIX-GUIDE.md`** for complete technical details.

---

## Audio Configuration Files

### Fix Tools (in `/home/psychopunk_sage/dev/drivers/`)
- **`speaker_codec_fix.py`** - Python tool for HDA codec mixer unmute (RECOMMENDED)
- **`fix-speaker-unmute.sh`** - Bash script for quick fix
- **`speaker-unmute.service`** - Systemd service for persistent fix
- **`SPEAKER-FIX-GUIDE.md`** - Complete technical documentation

### UCM2 Configuration (this directory)
UCM2 configuration for Realtek ALC298 codec on Samsung 940XHA.

**Install UCM2:**
```bash
sudo ./install.sh
```

Installs UCM2 files to `/usr/share/alsa/ucm2/conf.d/sof-hda-dsp/` and restarts PipeWire.

---

## Hardware Specification

- **Model**: Samsung Galaxy Book5 Pro (940XHA)
- **Codec**: Realtek ALC298 (Subsystem: 0x144dca08)
- **Driver**: SOF (Sound Open Firmware) + HDA
- **Speaker Pin**: NID 0x17 (via Mixer 0x0d from DAC 0x03)
- **Headphone**: NID 0x21
- **Mic**: NID 0x18
- **DMIC**: PCM device 6

---

## Features

- Automatic speaker/headphone switching
- DMIC and headset mic routing
- Jack detection support
- PipeWire integration
- **Hardware codec mixer unmute fix**

---

## Installation

### 1. Fix Speaker Hardware Mute (Required!)

```bash
# Verify the issue
python3 /home/psychopunk_sage/dev/drivers/speaker_codec_fix.py --verify-only

# Apply fix
sudo python3 /home/psychopunk_sage/dev/drivers/speaker_codec_fix.py

# Make persistent across reboots
sudo cp /home/psychopunk_sage/dev/drivers/speaker_codec_fix.py /usr/local/bin/
sudo cp /home/psychopunk_sage/dev/drivers/speaker-unmute.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable speaker-unmute.service
sudo systemctl start speaker-unmute.service
```

### 2. Install UCM2 Configuration

```bash
cd /home/psychopunk_sage/dev/drivers/audio-config
sudo ./install.sh
```

---

## Testing

```bash
# Test speakers (after applying codec fix!)
speaker-test -c2 -t wav -Dhw:0,0

# Verify UCM loaded
alsaucm -c sof-hda-dsp listcards

# Test DMIC
arecord -D hw:0,6 -f S16_LE -r 48000 -c 2 -d 3 test.wav && aplay test.wav

# Check mixer controls
alsamixer -c 0
```

---

## Troubleshooting

### Speakers still silent after UCM install

**This is the most common issue!** UCM configuration alone is NOT enough.

The HDA codec mixer (Node 0x0d) is muted by default. You MUST apply the codec fix:

```bash
sudo python3 /home/psychopunk_sage/dev/drivers/speaker_codec_fix.py
```

See `SPEAKER-FIX-GUIDE.md` for why this happens and technical details.

### Verify codec mixer state

```bash
# Check if mixer is muted (the root cause)
cat /proc/asound/card0/codec#0 | grep -A3 "Node 0x0d" | grep "Amp-In vals"

# Should show unmuted values after fix
```

### ALSA mixers all correct but no sound

This confirms the issue is at codec hardware level, not ALSA software level.

```bash
# All these will show correct values but speakers are still silent:
amixer -c0 sget Speaker    # Shows [on] and volume
amixer -c0 sget Master     # Shows [on] and volume
wpctl status               # Shows speaker as default sink

# The problem is internal codec mixer node 0x0d is muted!
```

### DMIC not working

```bash
# Verify DMIC device exists
arecord -l | grep -i dmic

# Test DMIC directly
arecord -D hw:0,6 -f S16_LE -r 48000 -c 2 -d 3 test.wav
aplay test.wav
```

### Jack detection fails

```bash
# Monitor jack events
amixer -c 0 events
# Plug/unplug headphones - should see "Headphone Jack" events
```

### Reset everything

```bash
# Remove UCM config
sudo rm /usr/share/alsa/ucm2/conf.d/sof-hda-dsp/*940XHA*

# Restart audio
systemctl --user restart pipewire wireplumber

# Reapply codec fix
sudo systemctl restart speaker-unmute.service
```

---

## Files

### In `/home/psychopunk_sage/dev/drivers/`
```
speaker_codec_fix.py          # Python HDA codec fix tool
fix-speaker-unmute.sh         # Bash HDA codec fix script
speaker-unmute.service        # Systemd service for persistence
SPEAKER-FIX-GUIDE.md          # Complete technical documentation
```

### In `/home/psychopunk_sage/dev/drivers/audio-config/`
```
ucm2/conf.d/sof-hda-dsp/
├── Samsung-940XHA.conf       # DMI match
└── HiFi-Samsung-940XHA.conf  # Device routing
install.sh                    # UCM installation script
README.md                     # This file
```

---

## Technical Details

### Audio Signal Path

```
DAC (Node 0x03)
  ↓
Audio Mixer (Node 0x0d) ← MUTED BY DEFAULT!
  ↓
Speaker Pin (Node 0x17)
  ↓
Physical Speakers
```

**Root Cause**: SOF firmware doesn't unmute the internal mixer node 0x0d during initialization.

**Solution**: Manually write HDA verbs to unmute the mixer path.

### HDA Verbs Used

```
0x0d 0x7000 0xb000  # Unmute mixer input 0, both channels
```

Where:
- `0x0d` = Mixer node ID
- `0x7000` = SET_AMP_GAIN_MUTE verb (input amp 0)
- `0xb000` = Both channels, unmute (bit 7=0), 0dB gain

### PCM Devices

- **hw:0,0** - Analog output (speakers/headphones)
- **hw:0,6** - Digital microphone (DMIC)
- **hw:0,31** - Deepbuffer analog output

### Priorities

- **Playback**: Headphone (200) > Speaker (100)
- **Capture**: Headset Mic (200) > DMIC (100)

---

## Next Steps

If speakers still don't work after both fixes:

1. Check SOF firmware logs:
   ```bash
   sudo dmesg | grep -iE "sof|firmware|alc298"
   ```

2. Verify DAC is streaming:
   ```bash
   cat /proc/asound/card0/codec#0 | grep -A5 "Node 0x03"
   # Should show "Converter: stream=1" when playing audio
   ```

3. Test raw ALSA playback:
   ```bash
   aplay -Dhw:0,0 /usr/share/sounds/alsa/Front_Center.wav
   ```

4. Check EC audio controls (if any):
   ```bash
   sudo cat /sys/kernel/debug/ec/ec0/io
   ```

---

## Contributing Upstream

This codec fix needs to be upstreamed to Linux kernel as:
1. HDA quirk in `sound/pci/hda/patch_realtek.c`
2. SOF topology fix in firmware repository

See `SPEAKER-FIX-GUIDE.md` for patch submission details.

---

**Status**: Both UCM and codec fix required for full functionality
**Last Updated**: 2026-01-14
**Tested On**: Samsung Galaxy Book5 Pro (940XHA), Ubuntu 25.04, Kernel 6.14
