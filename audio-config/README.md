# Samsung Galaxy Book5 Pro - Linux Audio Investigation

**Status**: Speaker audio NOT working - Awaiting upstream kernel support

## Device Information

| Component | Details |
|-----------|---------|
| **Model** | Samsung Galaxy Book5 Pro (NP940XHA / 940XHA) |
| **CPU** | Intel Core Ultra 7 258V (Lunar Lake) |
| **Audio Controller** | Intel Lunar Lake-M HD Audio (8086:a828) |
| **HDA Codec** | Realtek ALC298 |
| **Subsystem ID** | `0x144dca08` |
| **Kernel Tested** | 6.14.0-37-generic (Ubuntu 25.04) |

## Problem Summary

Internal speakers produce **no sound**. Headphones work perfectly.

## Issue Trackers

Bug reports submitted to upstream projects:

- **SOF Project**: [thesofproject/linux#5651](https://github.com/thesofproject/linux/issues/5651)
- **Samsung Galaxy Book Extras**: [joshuagrisham/samsung-galaxybook-extras#90](https://github.com/joshuagrisham/samsung-galaxybook-extras/issues/90)

## Investigation Findings

### Key Discovery

The ACPI firmware declares MAX98390 I2C amplifiers, but this is **misleading**:

- The addresses `0x38, 0x39, 0x3C, 0x3D` are **HDA coefficient register targets**, NOT I2C device addresses
- No physical MAX98390 chips exist on the I2C bus
- Speaker amplifiers are controlled via HDA codec coefficient writes

### What Was Tested

| Test | Result |
|------|--------|
| SOF audio (default) | Fixup not applied |
| Traditional HDA with Samsung amp v2 quirk | Fixup applies but no sound |
| Manual coefficient writes | Registers accessible, no effect |
| HDA GPIO toggle (all 8 pins) | No effect |
| Pin amplifier unmute (Node 0x17) | Stuck at 0x00 |
| 2-amp and 4-amp variants | Both fail |

### Root Cause

The existing `alc298-samsung-amp-v2` kernel fixup works for Galaxy Book2/Book3 Pro but **does NOT work** for the Galaxy Book5 Pro (Lunar Lake). This device likely requires:

1. Different coefficient sequences
2. Additional GPIO control
3. A separate power enable mechanism
4. Or a completely different driver approach

## Repository Structure

```
audio-config/
├── README.md                    # This file
├── INVESTIGATION-LOG.md         # Complete investigation history
├── BUG-REPORT.md               # Ready-to-use bug report template
├── scripts/                     # Diagnostic scripts
│   ├── audio-full-debug.sh     # Full audio diagnostics
│   ├── check-max98390.sh       # MAX98390/I2C checker
│   ├── test-gpio-audio.sh      # GPIO testing
│   ├── test-fixes.sh           # Fix testing script
│   └── test.sh                 # General test script
├── reference/                   # Reference code and documentation
│   ├── patch.txt               # Samsung ALC298 amp kernel patch
│   ├── samsung-galaxybook.c    # Samsung platform driver source
│   ├── Kconfig                 # Kernel config for samsung-galaxybook
│   └── samsung-galaxybook-extras-README.md
├── samsung-galaxybook-extras/   # Reference DSDT files from other models
│   ├── dsdt/                   # DSDT dumps from various models
│   └── 61-keyboard-samsung-galaxybook.hwdb
├── ucm2/                        # ALSA UCM2 configuration attempts
│   └── conf.d/sof-hda-dsp/
└── archive/                     # Old investigation attempts (kept for reference)
```

## Quick Commands

### Check Current Audio Status

```bash
# Card info
cat /proc/asound/cards

# Codec details
cat "/proc/asound/card0/codec#0" | head -80

# ALSA mixer
amixer -c0 contents | grep -A3 "Speaker"
```

### Test Samsung Amp v2 Quirk (Does NOT work on Book5 Pro)

```bash
# Disable SOF, enable traditional HDA
echo "options snd-intel-dspcfg dsp_driver=1" | sudo tee /etc/modprobe.d/disable-sof.conf
echo "options snd-hda-intel model=alc298-samsung-amp-v2-4-amps" | sudo tee /etc/modprobe.d/samsung-audio-fix.conf
sudo update-initramfs -u
sudo reboot
```

### Revert to Default (SOF)

```bash
sudo rm -f /etc/modprobe.d/disable-sof.conf /etc/modprobe.d/samsung-audio-fix.conf
sudo update-initramfs -u
sudo reboot
```

## Workarounds

Until kernel support is added:

- **USB Audio Adapter** - Works immediately
- **Bluetooth Audio** - Works with built-in Bluetooth
- **HDMI Audio** - Works when connected to external display

## Contributing

If you have a Samsung Galaxy Book5 Pro and can help with testing:

1. Check the open issues linked above
2. Run the diagnostic scripts in `scripts/`
3. Share your findings in the GitHub issues

If you have **Windows dual-boot**, capturing what the Windows driver does would be extremely valuable for reverse engineering the correct coefficient sequences.

## Related Resources

- [Samsung Galaxy Book Driver (Kernel Docs)](https://docs.kernel.org/admin-guide/laptops/samsung-galaxybook.html)
- [SOF Project](https://github.com/thesofproject/sof)
- [Original Samsung ALC298 Patch](https://lore.kernel.org/linux-sound/20240909193000.838815-1-josh@joshuagrisham.com/)
- [SOF Issue #4055](https://github.com/thesofproject/linux/issues/4055) - Background on Samsung speaker amp support

## License

This investigation documentation is provided as-is for the benefit of the Linux audio community. Reference code files retain their original licenses.

---

*Last updated: 2026-01-16*
