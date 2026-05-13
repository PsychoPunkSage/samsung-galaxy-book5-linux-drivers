# Audio: Samsung Galaxy Book5 Pro

**Status: Speaker audio NOT working. Awaiting upstream kernel support.**

> For working audio fixes on related Samsung models, see:
> **[Andycodeman/samsung-galaxy-book4-linux-fixes](https://github.com/Andycodeman/samsung-galaxy-book4-linux-fixes)**

## Device

| Component | Details |
|-----------|---------|
| Model | Samsung Galaxy Book5 Pro (NP940XHA) |
| CPU | Intel Core Ultra 7 258V (Lunar Lake) |
| Audio Controller | Intel Lunar Lake-M HD Audio (8086:a828) |
| HDA Codec | Realtek ALC298 |
| Subsystem ID | `0x144dca08` |
| Kernel | 6.14.0-37-generic (Ubuntu 25.04) |

Internal speakers produce **no sound**. Headphones work fine.

## Open Issues

- **SOF Project**: [thesofproject/linux#5651](https://github.com/thesofproject/linux/issues/5651)
- **Samsung Galaxy Book Extras**: [joshuagrisham/samsung-galaxybook-extras#90](https://github.com/joshuagrisham/samsung-galaxybook-extras/issues/90)

## Key Finding

ACPI firmware declares MAX98390 I2C amplifiers at `0x38, 0x39, 0x3C, 0x3D`; these are **HDA coefficient register targets**, not real I2C devices. No physical MAX98390 chips on the I2C bus. Speaker amps are controlled via HDA codec coefficient writes.

## What Was Tested

| Test | Result |
|------|--------|
| SOF audio (default) | Fixup not applied |
| Traditional HDA + `alc298-samsung-amp-v2` quirk | Fixup applies, no sound |
| Manual coefficient writes | Registers accessible, no effect |
| HDA GPIO toggle (all 8 pins) | No effect |
| Pin amp unmute (Node 0x17) | Stuck at 0x00 |
| 2-amp and 4-amp variants | Both fail |

## Root Cause

`alc298-samsung-amp-v2` works for Book2/Book3 Pro but not Book5 Pro (Lunar Lake). This device likely needs different coefficient sequences, additional GPIO control, or a separate power enable mechanism.

## Directory Structure

```
audio-config/
├── README.md
├── INVESTIGATION-LOG.md         # full investigation history
├── BUG-REPORT.md                # bug report template
├── scripts/
│   ├── audio-full-debug.sh
│   ├── check-max98390.sh
│   ├── test-gpio-audio.sh
│   ├── test-fixes.sh
│   └── test.sh
├── reference/
│   ├── patch.txt                # Samsung ALC298 amp kernel patch
│   ├── samsung-galaxybook.c
│   ├── Kconfig
│   └── samsung-galaxybook-extras-README.md
├── samsung-galaxybook-extras/
│   ├── dsdt/
│   └── 61-keyboard-samsung-galaxybook.hwdb
├── ucm2/conf.d/sof-hda-dsp/
└── archive/
```

## Commands

### Check Audio Status

```bash
cat /proc/asound/cards
cat "/proc/asound/card0/codec#0" | head -80
amixer -c0 contents | grep -A3 "Speaker"
```

### Test Samsung Amp v2 Quirk (does NOT work on Book5 Pro)

```bash
echo "options snd-intel-dspcfg dsp_driver=1" | sudo tee /etc/modprobe.d/disable-sof.conf
echo "options snd-hda-intel model=alc298-samsung-amp-v2-4-amps" | sudo tee /etc/modprobe.d/samsung-audio-fix.conf
sudo update-initramfs -u && sudo reboot
```

### Revert to Default (SOF)

```bash
sudo rm -f /etc/modprobe.d/disable-sof.conf /etc/modprobe.d/samsung-audio-fix.conf
sudo update-initramfs -u && sudo reboot
```

## Workarounds

- USB audio adapter
- Bluetooth audio
- HDMI audio (external display)

## Related

- [Samsung Galaxy Book Driver (Kernel Docs)](https://docs.kernel.org/admin-guide/laptops/samsung-galaxybook.html)
- [SOF Project](https://github.com/thesofproject/sof)
- [Original Samsung ALC298 Patch](https://lore.kernel.org/linux-sound/20240909193000.838815-1-josh@joshuagrisham.com/)
- [SOF Issue #4055](https://github.com/thesofproject/linux/issues/4055)
