# Samsung Galaxy Book5 Pro — Linux Driver Work

Reverse engineering and driver work for the Samsung Galaxy Book5 Pro (Lunar Lake) on Linux.

> For camera and audio fixes on related Samsung models (Book4), see:
> **[Andycodeman/samsung-galaxy-book4-linux-fixes](https://github.com/Andycodeman/samsung-galaxy-book4-linux-fixes)**

---

## Directories

### [`/audio-config/`](audio-config/README.md)
Speaker audio investigation. Internal speakers broken; headphones work. Root cause identified (ALC298 coefficient sequences), fix not yet found. See README for full findings and open upstream issues.

### [`/camera-enablement/`](camera-enablement/QUICK-START.md)
Intel IPU7 / OmniVision OV02E1 camera investigation. Hardware present but disabled at PCI level. Blocked on missing `ov02e1` driver and Lunar Lake IPU7 kernel support.

### [`/samsung-galaxybook-driver/`](samsung-galaxybook-driver/)
Platform driver for Samsung-specific hardware: Fn keys, keyboard backlight, performance modes, battery charge thresholds.

### [`/samsung-battery-monitor/`](samsung-battery-monitor/)
Battery monitoring and thermal management tools.

### [`/samsung-acpi-investigation/`](samsung-acpi-investigation/)
ACPI / DSDT analysis for power management and hardware enable sequences.
