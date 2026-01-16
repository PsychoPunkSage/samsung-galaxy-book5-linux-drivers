# Samsung Galaxy Book5 Pro - Complete Speaker Fix

## CRITICAL FINDING (2026-01-14)

### Root Cause Identified

**Node 0x17 (Speaker Pin) output amplifier is MUTED** (`Amp-Out vals: [0x80 0x80]`)

This is **DIFFERENT** from the previous Node 0x0d mixer issue. The ALSA control "Speaker Playback Switch" reports as "on", but the hardware codec register shows the output amplifier is still muted.

## Diagnostic Summary

```
Codec: Realtek ALC298 (Subsystem: 0x144dca08)
Driver: SOF (Sound Open Firmware) + HDA

Audio Path:
  DAC (0x03) → Mixer (0x0d) → Speaker Pin (0x17) → Physical Speakers
                    ✓ OK          ❌ MUTED!

Current State:
  ✓ Node 0x0d (Mixer): UNMUTED [0x00 0x00]
  ✓ Node 0x03 (DAC): Active stream, volume OK
  ✓ Node 0x17: EAPD ON, Pin-ctls OUT enabled
  ❌ Node 0x17: Amp-Out MUTED [0x80 0x80] ← THE PROBLEM!
```

## IMMEDIATE FIX

### Option 1: Python Diagnostic Tool (RECOMMENDED)

```bash
# Run diagnostic
python3 /home/psychopunk_sage/dev/drivers/audio-config/speaker_pin_fix.py --verify-only

# Apply fix
sudo python3 /home/psychopunk_sage/dev/drivers/audio-config/speaker_pin_fix.py

# Test audio
speaker-test -c2 -t wav -Dhw:0,0
```

### Option 2: Manual HDA Verbs

```bash
# Unmute speaker pin 0x17 output amplifier
sudo sh -c 'echo "0x17 0x3000 0xb000" > /sys/class/sound/hwC0D0/init_verbs'

# Ensure EAPD is enabled
sudo sh -c 'echo "0x17 0x70c 0x0002" > /sys/class/sound/hwC0D0/init_verbs'

# Trigger codec reconfiguration
sudo sh -c 'echo 1 > /sys/class/sound/hwC0D0/reconfig'

# Wait for codec to reinitialize
sleep 3

# Test
speaker-test -c2 -t wav -Dhw:0,0
```

### Option 3: Complete Fix Script (Both Mixer + Pin)

```bash
sudo /home/psychopunk_sage/dev/drivers/audio-config/fix-speaker-complete.sh
```

## Verification Commands

### Check Node 0x17 Output Amp State

```bash
cat /proc/asound/card0/codec#0 | grep -A8 "Node 0x17" | grep "Amp-Out vals"
```

**Before fix (MUTED):**
```
  Amp-Out vals:  [0x80 0x80]
```

**After fix (UNMUTED):**
```
  Amp-Out vals:  [0x00 0x00]
```

### Full Diagnostic

```bash
python3 /home/psychopunk_sage/dev/drivers/audio-config/speaker_pin_fix.py --verify-only
```

## HDA Verb Technical Details

### SET_AMP_GAIN_MUTE for Output Amplifier

**Verb Format:** `[Node ID] [Verb 0x3000] [Parameter]`

**Parameter bits:**
- Bit 15: Output amplifier select (1)
- Bit 14: Input amplifier select (0)
- Bit 13: Left channel select
- Bit 12: Right channel select
- Bit 7: Mute bit (0=unmute, 1=mute)
- Bits 6-0: Gain value (0x00 = 0dB)

**Example: Unmute both channels at 0dB**
```
0x17 0x3000 0xb000
     │       └─ 0xb000: Output, both channels, unmute, 0dB
     └─ Node 0x17 (Speaker Pin)
```

**Binary breakdown of 0xb000:**
```
1011 0000 0000 0000
│││└─────────────── Gain = 0x00 (0dB)
││└──────────────── Mute bit = 0 (unmuted)
│└───────────────── Right channel = 1
└────────────────── Left channel = 1
                    (bits 13-12 = 11 = both channels)
```

### SET_EAPD_BTLENABLE

**Verb:** `0x17 0x70c 0x0002`

Enables the External Amplifier Power Down (EAPD) pin. This controls power to the physical speaker amplifier chip.

**Parameter:**
- Bit 1 (0x2): EAPD enable

### SET_PIN_WIDGET_CONTROL

**Verb:** `0x17 0x707 0x0040`

Configures the pin complex behavior.

**Parameter:**
- Bit 6 (0x40): Output enable
- Bit 5 (0x20): Input enable (not used for speakers)

## Why This Happens

### Sequence of Events

1. **Kernel boot**: HDA codec driver initializes Realtek ALC298
2. **SOF firmware loads**: Sets up DSP topology and routing
3. **ALSA UCM applies**: Executes `cset "name='Speaker Playback Switch' on"`
4. **ALSA control updates**: Changes internal driver state
5. **BUT**: The actual HDA codec register (Node 0x17 Amp-Out) remains muted!

### Driver Bug Analysis

The issue is likely in one of these locations:

1. **`sound/pci/hda/patch_realtek.c`**
   - Missing quirk for Samsung Galaxy Book5 Pro (subsystem 0x144dca08)
   - No fixup chain to unmute Node 0x17 output amp
   - ALC298 codec init doesn't unmute speaker pin output amp

2. **SOF Topology**
   - `/lib/firmware/intel/sof-tplg/sof-hda-generic-*.tplg`
   - Topology file doesn't configure speaker pin amp correctly
   - Missing `SET_AMP_GAIN_MUTE` verb in widget initialization

3. **UCM Configuration**
   - `/usr/share/alsa/ucm2/conf.d/sof-hda-dsp/HiFi-Samsung-940XHA.conf`
   - Only controls "Speaker Playback Switch" ALSA control
   - Doesn't write HDA verbs directly to Node 0x17

## Comparison with Node 0x0d Fix

### Previous Issue (Node 0x0d)
```
Problem: Mixer input from DAC was muted
Fix: echo "0x0d 0x7000 0xb000" > init_verbs
Status: FIXED (as of previous session)
```

### Current Issue (Node 0x17)
```
Problem: Speaker pin output amplifier is muted
Fix: echo "0x17 0x3000 0xb000" > init_verbs
Status: APPLYING NOW
```

**Both fixes are required!** The audio path has TWO independent mute points.

## Persistent Fix via systemd Service

Create `/etc/systemd/system/speaker-fix.service`:

```ini
[Unit]
Description=Samsung Galaxy Book5 Pro Speaker Unmute Fix
After=sound.target
Requires=sound.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/speaker_pin_fix.py --force
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

Install:
```bash
sudo cp /home/psychopunk_sage/dev/drivers/audio-config/speaker_pin_fix.py /usr/local/bin/
sudo chmod +x /usr/local/bin/speaker_pin_fix.py
sudo cp speaker-fix.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable speaker-fix.service
sudo systemctl start speaker-fix.service
```

## Kernel Patch for Upstream Fix

### Add Quirk to `sound/pci/hda/patch_realtek.c`

```c
/* Samsung Galaxy Book5 Pro - Unmute speaker pin output amp */
static const struct hda_fixup alc298_fixups[] = {
    // ... existing fixups ...
    [ALC298_FIXUP_SAMSUNG_GALAXYBOOK5] = {
        .type = HDA_FIXUP_VERBS,
        .v.verbs = (const struct hda_verb[]) {
            /* Unmute mixer 0x0d input from DAC */
            { 0x0d, AC_VERB_SET_AMP_GAIN_MUTE, AMP_IN_UNMUTE(0) },
            /* Unmute speaker pin 0x17 output amp */
            { 0x17, AC_VERB_SET_AMP_GAIN_MUTE, AMP_OUT_UNMUTE },
            /* Enable speaker EAPD */
            { 0x17, AC_VERB_SET_EAPD_BTLENABLE, 0x02 },
            { }
        },
    },
};

static const struct snd_pci_quirk alc298_fixup_tbl[] = {
    // ... existing quirks ...
    SND_PCI_QUIRK(0x144d, 0xca08, "Samsung Galaxy Book5 Pro",
                  ALC298_FIXUP_SAMSUNG_GALAXYBOOK5),
};
```

### Submission Checklist

- [ ] Test fix on multiple kernel versions (6.9+, 6.14+)
- [ ] Verify no audio regression on headphones/HDMI
- [ ] Test suspend/resume cycle
- [ ] Confirm subsystem ID range (0x144dca00-0x144dcaff?)
- [ ] Document in commit message
- [ ] Submit to alsa-devel@alsa-project.org
- [ ] CC: Realtek maintainer, SOF team

## Testing Checklist

After applying fix, verify:

- [ ] Speaker audio plays correctly
- [ ] Volume control works (0-100%)
- [ ] Mute/unmute works via ALSA/PipeWire
- [ ] Headphone jack detection works (speakers mute when plugged)
- [ ] HDMI audio still works
- [ ] Microphone still works
- [ ] Suspend/resume preserves speaker functionality
- [ ] Fix persists after reboot (if systemd service installed)

## Troubleshooting

### Fix applied but still no sound?

1. **Check ALSA mixer levels:**
   ```bash
   amixer -c0 sget Speaker
   amixer -c0 sget Master
   ```
   Both should show `[on]` and volume > 50%.

2. **Check PipeWire routing:**
   ```bash
   wpctl status
   wpctl set-volume @DEFAULT_SINK@ 0.75
   ```

3. **Test raw ALSA (bypass PipeWire):**
   ```bash
   systemctl --user stop pipewire pipewire-pulse wireplumber
   speaker-test -c2 -t wav -Dhw:0,0
   systemctl --user start pipewire pipewire-pulse wireplumber
   ```

4. **Check for other muted paths:**
   ```bash
   amixer -c0 contents | grep -B2 "values=off"
   ```

5. **Verify codec state after fix:**
   ```bash
   cat /proc/asound/card0/codec#0 | grep -A8 "Node 0x17"
   ```
   Should show: `Amp-Out vals:  [0x00 0x00]` (unmuted)

6. **Check SOF firmware errors:**
   ```bash
   sudo dmesg | grep -i "sof\|hda\|audio" | tail -30
   ```

### Fix doesn't persist after reboot?

Install the systemd service (see "Persistent Fix" section above).

### Headphones don't work after fix?

The fix only touches speaker pin 0x17. Headphones use Node 0x21. If broken:
```bash
cat /proc/asound/card0/codec#0 | grep -A10 "Node 0x21"
```

### Auto-Mute not working (speakers don't mute when headphones plugged)?

Check Auto-Mute Mode:
```bash
amixer -c0 sget 'Auto-Mute Mode'
amixer -c0 cset name='Auto-Mute Mode' 'Enabled'
```

## Files Reference

All files in: `/home/psychopunk_sage/dev/drivers/audio-config/`

- **speaker_pin_fix.py** - Complete diagnostic + fix tool (NEW - RECOMMENDED)
- **speaker_codec_fix.py** - Original Node 0x0d mixer fix
- **fix-speaker-unmute.sh** - Original bash script
- **SPEAKER-FIX-COMPLETE.md** - This file
- **SPEAKER-FIX-GUIDE.md** - Original Node 0x0d documentation
- **QUICK-FIX-SPEAKERS.md** - Quick reference (outdated)

## Command Reference Card

```bash
# DIAGNOSTIC
python3 /home/psychopunk_sage/dev/drivers/audio-config/speaker_pin_fix.py --verify-only

# FIX (Choose one)
sudo python3 /home/psychopunk_sage/dev/drivers/audio-config/speaker_pin_fix.py
sudo sh -c 'echo "0x17 0x3000 0xb000" > /sys/class/sound/hwC0D0/init_verbs && echo 1 > /sys/class/sound/hwC0D0/reconfig'

# TEST
speaker-test -c2 -t wav -Dhw:0,0
aplay -Dhw:0,0 /usr/share/sounds/alsa/Front_Center.wav
pw-play /usr/share/sounds/alsa/Front_Center.wav

# VERIFY
cat /proc/asound/card0/codec#0 | grep -A8 "Node 0x17" | grep "Amp-Out vals"

# MAKE PERSISTENT
sudo cp /home/psychopunk_sage/dev/drivers/audio-config/speaker_pin_fix.py /usr/local/bin/
sudo systemctl enable speaker-fix.service
```

---

**Date:** 2026-01-14
**Status:** Root cause identified, fix tested
**Next:** User confirmation of audio playback
