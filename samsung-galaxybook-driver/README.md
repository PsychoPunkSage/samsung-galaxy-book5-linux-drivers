# Samsung Galaxy Book Linux Driver

Linux kernel driver for Samsung Galaxy Book laptops, enabling hardware features that work on Windows via Samsung Settings.

## Supported Features

| Feature | Sysfs Path | Values |
|---------|------------|--------|
| Battery charge threshold | `/sys/class/power_supply/BAT1/charge_control_end_threshold` | 0-100 (0 = no limit) |
| Keyboard backlight | `/sys/class/leds/samsung-galaxybook::kbd_backlight/brightness` | 0-3 |
| Performance profile | `/sys/firmware/acpi/platform_profile` | low-power, balanced, performance |
| Fn+F9 hotkey | Cycles keyboard backlight | Automatic |

## Supported Models

Laptops with ACPI device `SAM0430`:
- Samsung Galaxy Book5 Pro (940XHA) - Tested
- Samsung Galaxy Book4 Pro
- Samsung Galaxy Book3 Pro
- Other Galaxy Book models with SAM0430

Check if your laptop is supported:
```bash
ls /sys/bus/acpi/devices/ | grep SAM0430
```

## Quick Install

```bash
# Install dependencies
sudo apt install build-essential linux-headers-$(uname -r)

# Clone and install
git clone https://github.com/YOUR_USERNAME/samsung-galaxybook-driver.git
cd samsung-galaxybook-driver
./scripts/install.sh
```

## Manual Install

```bash
# Build
make

# Install to kernel modules directory
sudo make install

# Load driver
sudo modprobe samsung-galaxybook

# Enable on boot
echo "samsung-galaxybook" | sudo tee /etc/modules-load.d/samsung-galaxybook.conf
```

## Usage

### Battery Charge Threshold

Limit battery charging to protect battery longevity:

```bash
# Read current threshold
cat /sys/class/power_supply/BAT1/charge_control_end_threshold

# Set to 80% (recommended for longevity)
echo 80 | sudo tee /sys/class/power_supply/BAT1/charge_control_end_threshold

# Remove limit (charge to 100%)
echo 0 | sudo tee /sys/class/power_supply/BAT1/charge_control_end_threshold
```

### Keyboard Backlight

```bash
# Read current level
cat /sys/class/leds/samsung-galaxybook::kbd_backlight/brightness

# Set brightness (0=off, 1=low, 2=medium, 3=high)
echo 3 | tee /sys/class/leds/samsung-galaxybook::kbd_backlight/brightness
```

Or use **Fn+F9** to cycle through brightness levels.

### Performance Profile

```bash
# Read current profile
cat /sys/firmware/acpi/platform_profile

# Available profiles
cat /sys/firmware/acpi/platform_profile_choices

# Set profile
echo balanced | sudo tee /sys/firmware/acpi/platform_profile
```

## Persist Settings on Boot

Create `/etc/udev/rules.d/99-samsung-galaxybook.rules`:

```udev
# Set battery threshold to 80% on boot
SUBSYSTEM=="power_supply", ATTR{type}=="Battery", ATTR{charge_control_end_threshold}="80"
```

Reload rules: `sudo udevadm control --reload-rules`

## Troubleshooting

### Driver won't load

```bash
# Check kernel messages
sudo dmesg | grep -i samsung

# Verify ACPI device exists
ls -la /sys/bus/acpi/devices/SAM0430:00/

# Check dependencies
sudo modprobe platform_profile
```

### Battery threshold not appearing

```bash
# Check if driver loaded
lsmod | grep samsung_galaxybook

# Check dmesg for errors
sudo dmesg | tail -20
```

### Fn+F9 not working

```bash
# Check if ACPI events are received
sudo dmesg -w
# Press Fn+F9 and look for:
# samsung-galaxybook SAM0430:00: unknown ACPI notification event: 0x7d

# If 0x7d appears but backlight doesn't change, driver patch needed
```

### Debugging ACPI events

```bash
# Monitor all ACPI events
sudo acpi_listen

# Monitor kernel messages
sudo dmesg -w | grep -i samsung

# Check keyboard scancodes
sudo showkey -s
```

## Technical Details

### ACPI Interface

The driver communicates with Samsung firmware via:
- **ACPI Device**: `SAM0430` (Samsung Platform Controller)
- **Methods**: `CSFI` (get), `CSXI` (set)
- **Protocol**: SAWB buffer structure with command codes

### Key Commands

| Feature | Command | Sub-command |
|---------|---------|-------------|
| Battery threshold GET | 0xe9 | 0x91 |
| Battery threshold SET | 0xe9 | 0x90 |
| Keyboard backlight | 0x78 | - |
| Performance mode | 0x43 | - |

### ACPI Hotkey Events

| Event Code | Function |
|------------|----------|
| 0x7d | Keyboard backlight (Fn+F9) |
| 0x61 | Performance mode cycle |

## Building from Source

### Requirements

- Linux kernel 5.10+
- kernel headers (`linux-headers-$(uname -r)`)
- build-essential (gcc, make)

### Build Commands

```bash
make            # Build module
make clean      # Clean build files
make install    # Install to system
make uninstall  # Remove from system
make status     # Check driver status
```

## Known Limitations

- **Firmware attributes** (USB charging, power-on-lid-open) disabled on Ubuntu kernel 6.14 due to unexported symbols
- Some hotkeys may require additional patches depending on firmware version

## Contributing

1. Fork the repository
2. Test on your hardware
3. Submit pull request with:
   - Your laptop model
   - Kernel version
   - What works/doesn't work

## License

GPL-2.0-or-later

## Credits

- **Joshua Grisham** - Original samsung-galaxybook driver
- **Giulio Girardi** - SCAI ACPI interface contributions
- Samsung Galaxy Book Linux community

## Related Projects

- [samsung-galaxybook mainline](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/platform/x86/samsung-galaxybook.c) - Upstream kernel driver
