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
- Intel Meteor Lake platform ACPI issues
- Battery reporting & thermal sensors
- Platform controller quirks

### Why this exists
Samsung does not provide Linux support for Galaxy Book5 laptops.  
This project provides **community-maintained kernel patches and DKMS drivers** to make Book5 devices fully usable on Linux.
