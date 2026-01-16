# Samsung Galaxy Book5 / Book5 Pro Linux Drivers

This repository provides **Linux driver patches, DKMS modules and firmware fixes** for Samsung Galaxy Book5 series laptops (Meteor Lake platform).

### Supported Models
• Galaxy Book5  
• Galaxy Book5 Pro  
• Galaxy Book5 Pro 360  

### What this repo fixes
- Fn hotkeys (airplane mode, brightness, keyboard backlight)
- RFKill / WiFi toggle (Fn+F9)
- Touchpad & HID quirks
- Audio codec routing (SOF HDA DSP)
- Speaker codec mute fix (HDA mixer unmute)
- Intel Meteor Lake platform ACPI issues
- Battery reporting & thermal sensors
- Platform controller quirks

### Why this exists
Samsung does not provide Linux support for Galaxy Book5 laptops.
This project provides **community-maintained kernel patches and DKMS drivers** to make Book5 devices fully usable on Linux.

---

## Component Directories

### `/audio-config/`
Complete audio diagnostics and fixes for Samsung Galaxy Book5 Pro speaker issue:
- **AUDIO-STATUS.md** - Consolidated status report (READ THIS FIRST)
- **Test scripts** - GPIO testing and I2C diagnostics
- **MAX98390 analysis** - Smart amplifier investigation
- **Archive** - Previous troubleshooting attempts
- See `/audio-config/README.md` for quick start guide

**Current Status:** Awaiting GPIO hardware test
```bash
cd /home/psychopunk_sage/dev/drivers/audio-config
sudo ./test-gpio-audio.sh
```

### `/samsung-galaxybook-driver/`
Platform driver for Samsung-specific hardware:
- Fn key handling
- Keyboard backlight control
- Performance modes
- Battery charge thresholds
- DKMS module and installation scripts

### `/samsung-battery-monitor/`
Battery monitoring and management tools:
- Charge level tracking
- Thermal monitoring
- Power consumption analysis
