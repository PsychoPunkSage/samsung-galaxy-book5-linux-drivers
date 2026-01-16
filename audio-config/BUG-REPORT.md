# [BUG] No speaker audio on Samsung Galaxy Book5 Pro (NP940XHA) - Lunar Lake - Subsystem ID 0x144dca08

## System Information

| Component | Details |
|-----------|---------|
| **Device** | Samsung Galaxy Book5 Pro (NP940XHA / 940XHA) |
| **CPU** | Intel Core Ultra 7 258V (Lunar Lake) |
| **Audio Controller** | Intel Lunar Lake-M HD Audio (8086:a828) |
| **HDA Codec** | Realtek ALC298 |
| **Subsystem ID** | `0x144dca08` (Vendor: 0x144d, Device: 0xca08) |
| **Kernel** | 6.14.0-37-generic (Ubuntu 25.04) |
| **BIOS** | P05VAJ.280.250210.01 (02/10/2025) |

## Problem Description

Internal speakers produce no sound. Headphone output works perfectly.

## What Works

- Headphone output via HDA codec
- HDMI audio output
- Microphone input (DMIC)
- All ALSA mixer controls respond correctly
- HDA codec detection and configuration

## What Doesn't Work

- Internal speakers - completely silent
- No audio output from speaker-test or any application

## Investigation Summary

### Extensive Testing Performed

| Test | Result | Notes |
|------|--------|-------|
| ALSA mixer controls | All correct | Speaker unmuted, 100% volume |
| HDA GPIO toggle (all 8 pins) | No effect | GPIOs not the control mechanism |
| SOF firmware | Loads successfully | sof-lnl.ri v2.12.0.1 |
| SOF disabled, traditional HDA | Fixup applies, no sound | See details below |
| Samsung amp v2 quirk (4-amps) | Applies but no sound | Coefficient writes don't enable speakers |
| Samsung amp v2 quirk (2-amps) | Applies but no sound | Same result |
| Manual coefficient writes | No effect | Registers accessible but speakers stay silent |
| I2C MAX98390 probe | No devices respond | ACPI declares MAX98390, but nothing on I2C bus |
| Pin amp unmute (Node 0x17) | Stuck at 0x00 | hda-verb SET_AMP_GAIN_MUTE has no effect |

### Key Technical Findings

#### 1. SOF vs Traditional HDA

With SOF enabled (default):
```
Card: sofhdadsp - sof-hda-dsp
Driver: sof-audio-pci-intel-lnl
Topology: sof-hda-generic-2ch.tplg
Result: model= parameter ignored, no fixup applied
```

With SOF disabled (`options snd-intel-dspcfg dsp_driver=1`):
```
Card: HDA-Intel - HDA Intel PCH
Driver: snd-hda-intel
Result: Samsung fixup DOES apply, but still no sound
```

#### 2. Samsung Amp v2 Fixup Applies But Doesn't Work

```
dmesg output:
snd_hda_codec_realtek hdaudioC0D0: ALC298: picked fixup alc298-samsung-amp-v2-4-amps (model specified)
snd_hda_codec_realtek hdaudioC0D0: autoconfig for ALC298: line_outs=1 (0x17/0x0/0x0/0x0/0x0) type:speaker
```

The quirk IS being applied (confirmed by "model specified" message), but:
- No debug messages about amp enable during playback
- All 8 HDA GPIOs remain disabled
- Node 0x17 Amp-Out vals stuck at [0x00 0x00]

#### 3. Codec State Analysis

```
Codec: Realtek ALC298
Subsystem Id: 0x144dca08

GPIO: io=8, o=0, i=0, unsolicited=1, wake=0
  IO[0-7]: all enable=0, dir=0, data=0

Node 0x17 [Pin Complex] - Speaker:
  Amp-Out vals: [0x00 0x00]  <- MUTED at hardware level
  EAPD 0x2: EAPD
  Pin Default 0x90170110: [Fixed] Speaker at Int N/A
  Connection: 0x0c 0x0d* 0x06
```

#### 4. Coefficient Register State

```bash
# Coefficient 0x22 (amp selector): 0x3d
# Coefficient 0x3a: 0xe800 (not the expected 0x0081 for enabled)
# Coefficient 0xff: 0x00 (should be 0x01 when enabled)
```

Manual coefficient writes via hda-verb are accepted but have no audible effect.

#### 5. ACPI MAX98390 Declaration (Red Herring)

ACPI declares MAX98390 at `\_SB.PC00.I2C2.MX98` with I2C addresses 0x38, 0x39, 0x3C, 0x3D, but:
- I2C bus scan shows no devices
- Device ID register reads return 0x00 (should be 0x43)
- These addresses are actually HDA coefficient targets, not I2C addresses

## Configuration Files Used

```bash
# /etc/modprobe.d/disable-sof.conf
options snd-intel-dspcfg dsp_driver=1

# /etc/modprobe.d/samsung-audio-fix.conf
options snd-hda-intel model=alc298-samsung-amp-v2-4-amps
```

## Diagnostic Commands Output

### lspci (Audio Controller)
```
00:1f.3 Multimedia audio controller: Intel Corporation Lunar Lake-M HD Audio Controller (rev 20)
```

### Codec Info
```
Codec: Realtek ALC298
Address: 0
Vendor Id: 0x10ec0298
Subsystem Id: 0x144dca08
Revision Id: 0x100103
```

### amixer Speaker Controls
```
Simple mixer control 'Speaker',0
  Capabilities: pvolume pswitch
  Playback channels: Front Left - Front Right
  Front Left: Playback 127 [100%] [0.00dB] [on]
  Front Right: Playback 127 [100%] [0.00dB] [on]
```

## Hypothesis

The Samsung Galaxy Book5 Pro (Lunar Lake) has a **different amplifier control mechanism** than the Galaxy Book2/Book3 Pro models. The existing `alc298-samsung-amp-v2` fixup coefficient sequences don't work for this hardware generation.

Possible reasons:
1. Different internal codec routing on Lunar Lake platform
2. Different coefficient values needed for this specific device
3. Additional power enable mechanism not covered by existing fixup
4. Hardware architectural change from previous Galaxy Book generations

## Request

1. **Add subsystem ID 0x144dca08** to the investigation list for Samsung Galaxy Book speaker support
2. **Investigate Lunar Lake-specific** amplifier control requirements
3. **Provide guidance** on capturing additional diagnostic data that would help identify the correct coefficient sequences

## Related Issues/Patches

- Josh Grisham's Samsung ALC298 speaker amp patch: https://lore.kernel.org/linux-sound/20240909193000.838815-1-josh@joshuagrisham.com/
- SOF Project Issue #4055: https://github.com/thesofproject/linux/issues/4055
- samsung-galaxybook-extras: https://github.com/joshuagrisham/samsung-galaxybook-extras

## Additional Notes

- No Windows dual-boot available for comparison/capture
- Willing to test patches and provide additional diagnostic data
- Full investigation log available with all commands and outputs

## Attachments

<details>
<summary>Full codec#0 dump (click to expand)</summary>

```
Codec: Realtek ALC298
Address: 0
AFG Function Id: 0x1 (unsol 1)
Vendor Id: 0x10ec0298
Subsystem Id: 0x144dca08
Revision Id: 0x100103
No Modem Function Group found
Default PCM:
    rates [0x60]: 44100 48000
    bits [0xe]: 16 20 24
    formats [0x1]: PCM
Default Amp-In caps: N/A
Default Amp-Out caps: N/A
State of AFG node 0x01:
  Power states:  D0 D1 D2 D3 D3cold CLKSTOP EPSS
  Power: setting=D0, actual=D0
GPIO: io=8, o=0, i=0, unsolicited=1, wake=0
  IO[0]: enable=0, dir=0, wake=0, sticky=0, data=0, unsol=0
  IO[1]: enable=0, dir=0, wake=0, sticky=0, data=0, unsol=0
  IO[2]: enable=0, dir=0, wake=0, sticky=0, data=0, unsol=0
  IO[3]: enable=0, dir=0, wake=0, sticky=0, data=0, unsol=0
  IO[4]: enable=0, dir=0, wake=0, sticky=0, data=0, unsol=0
  IO[5]: enable=0, dir=0, wake=0, sticky=0, data=0, unsol=0
  IO[6]: enable=0, dir=0, wake=0, sticky=0, data=0, unsol=0
  IO[7]: enable=0, dir=0, wake=0, sticky=0, data=0, unsol=0
Node 0x17 [Pin Complex] wcaps 0x40058d: Stereo Amp-Out
  Control: name="Speaker Playback Switch", index=0, device=0
  Amp-Out caps: ofs=0x00, nsteps=0x00, stepsize=0x00, mute=1
  Amp-Out vals:  [0x00 0x00]
  Pincap 0x0001001c: OUT HP EAPD Detect
  EAPD 0x2: EAPD
  Pin Default 0x90170110: [Fixed] Speaker at Int N/A
  Pin-ctls: 0x40: OUT
  Connection: 3
     0x0c 0x0d* 0x06
```

</details>

<details>
<summary>dmesg audio-related output (click to expand)</summary>

```
[    0.000000] DMI: SAMSUNG ELECTRONICS CO., LTD. 940XHA/NP940XHA-LG3IN, BIOS P05VAJ.280.250210.01 02/10/2025
[   20.992211] snd_hda_codec_realtek hdaudioC0D0: ALC298: picked fixup alc298-samsung-amp-v2-4-amps (model specified)
[   20.992623] snd_hda_codec_realtek hdaudioC0D0: autoconfig for ALC298: line_outs=1 (0x17/0x0/0x0/0x0/0x0) type:speaker
[   20.992625] snd_hda_codec_realtek hdaudioC0D0:    speaker_outs=0 (0x0/0x0/0x0/0x0/0x0)
[   20.992626] snd_hda_codec_realtek hdaudioC0D0:    hp_outs=1 (0x21/0x0/0x0/0x0/0x0)
[   20.992627] snd_hda_codec_realtek hdaudioC0D0:    mono: mono_out=0x0
[   20.992628] snd_hda_codec_realtek hdaudioC0D0:    inputs:
[   20.992629] snd_hda_codec_realtek hdaudioC0D0:      Mic=0x18
```

</details>

---

**Reporter**: psychopunk_sage
**Date**: 2026-01-16
**Platform**: Ubuntu 25.04, Kernel 6.14.0-37-generic
