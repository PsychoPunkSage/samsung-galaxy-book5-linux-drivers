#!/usr/bin/env python3
"""
Samsung Galaxy Book5 Pro - MAX98390 GPIO Calculator

Calculates the correct Linux GPIO number from ACPI GPIO pin number.
On Intel Meteor Lake/Arrow Lake, GPIOs are organized in communities.

ACPI declares: GPIO 0x62 (pin 98 decimal)

Intel GPIO numbering:
- Each GPIO controller (gpiochip) has a base number
- Actual GPIO = base + relative_pin
- Need to identify which community pin 98 belongs to
"""

import os
import sys
import subprocess
from pathlib import Path

class Color:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'

def read_sysfs(path):
    """Read a sysfs file safely."""
    try:
        return Path(path).read_text().strip()
    except Exception as e:
        return None

def get_gpio_chips():
    """Get all GPIO chips with their information."""
    chips = []
    gpio_path = Path('/sys/class/gpio')

    for chip_dir in sorted(gpio_path.glob('gpiochip*')):
        base = int(read_sysfs(chip_dir / 'base') or -1)
        ngpio = int(read_sysfs(chip_dir / 'ngpio') or 0)
        label = read_sysfs(chip_dir / 'label') or 'unknown'

        if base >= 0:
            chips.append({
                'name': chip_dir.name,
                'base': base,
                'ngpio': ngpio,
                'end': base + ngpio - 1,
                'label': label
            })

    return sorted(chips, key=lambda x: x['base'])

def check_gpio_debugfs():
    """Check GPIO debugfs for more information."""
    debugfs_path = Path('/sys/kernel/debug/gpio')
    if debugfs_path.exists():
        try:
            content = debugfs_path.read_text()
            return content
        except PermissionError:
            return "Permission denied. Run with sudo."
    return None

def find_gpio_in_chip(pin_number, chips):
    """Find which chip a pin number belongs to."""
    candidates = []

    # Method 1: Direct offset (pin_number is relative to chip base)
    for chip in chips:
        gpio_number = chip['base'] + pin_number
        if gpio_number <= chip['end']:
            candidates.append({
                'method': 'direct_offset',
                'chip': chip,
                'gpio': gpio_number,
                'confidence': 'high' if 'INT' in chip['label'] else 'medium'
            })

    # Method 2: Absolute pin number (if pin is in chip range)
    for chip in chips:
        if chip['base'] <= pin_number <= chip['end']:
            candidates.append({
                'method': 'absolute',
                'chip': chip,
                'gpio': pin_number,
                'confidence': 'medium'
            })

    return candidates

def test_gpio(gpio_number, dry_run=False):
    """Test if a GPIO number can be exported and controlled."""
    export_path = Path('/sys/class/gpio/export')
    gpio_path = Path(f'/sys/class/gpio/gpio{gpio_number}')

    if gpio_path.exists():
        print(f"  {Color.YELLOW}GPIO {gpio_number} already exported{Color.NC}")
        return True

    if dry_run:
        print(f"  [DRY RUN] Would export GPIO {gpio_number}")
        return False

    try:
        # Export GPIO
        export_path.write_text(str(gpio_number))
        print(f"  {Color.GREEN}✓ Exported GPIO {gpio_number}{Color.NC}")

        # Wait for sysfs to populate
        import time
        time.sleep(0.2)

        if not gpio_path.exists():
            print(f"  {Color.RED}✗ GPIO directory not created{Color.NC}")
            return False

        # Set direction
        (gpio_path / 'direction').write_text('out')
        print(f"  {Color.GREEN}✓ Set direction to output{Color.NC}")

        # Read current value
        current = (gpio_path / 'value').read_text().strip()
        print(f"  ℹ Current value: {current}")

        # Set to high
        (gpio_path / 'value').write_text('1')
        print(f"  {Color.GREEN}✓ Set value to HIGH{Color.NC}")

        time.sleep(0.5)

        # Test I2C
        print(f"  📡 Scanning I2C bus 2...")
        result = subprocess.run(['i2cdetect', '-y', '2'],
                              capture_output=True, text=True)
        if '38' in result.stdout or '39' in result.stdout:
            print(f"  {Color.GREEN}✓✓✓ SUCCESS! Device detected on I2C!{Color.NC}")
            return True
        else:
            print(f"  {Color.YELLOW}⚠ No device detected (yet){Color.NC}")
            return False

    except PermissionError:
        print(f"  {Color.RED}✗ Permission denied. Run with sudo.{Color.NC}")
        return False
    except Exception as e:
        print(f"  {Color.RED}✗ Error: {e}{Color.NC}")
        return False

def main():
    print("=== Samsung Galaxy Book5 Pro MAX98390 GPIO Calculator ===\n")

    acpi_pin = 0x62  # From ACPI declaration
    print(f"ACPI GPIO Pin: 0x{acpi_pin:02X} (decimal {acpi_pin})\n")

    # Get GPIO chips
    print("[1] Detecting GPIO controllers...\n")
    chips = get_gpio_chips()

    if not chips:
        print(f"{Color.RED}No GPIO chips found!{Color.NC}")
        return 1

    print(f"Found {len(chips)} GPIO controllers:\n")
    for chip in chips:
        print(f"  {chip['name']}:")
        print(f"    Base:   {chip['base']}")
        print(f"    Count:  {chip['ngpio']}")
        print(f"    Range:  {chip['base']}-{chip['end']}")
        print(f"    Label:  {chip['label']}")
        print()

    # Find candidates
    print(f"[2] Calculating GPIO candidates for pin {acpi_pin}...\n")
    candidates = find_gpio_in_chip(acpi_pin, chips)

    if not candidates:
        print(f"{Color.RED}No valid candidates found!{Color.NC}")
        return 1

    print(f"Found {len(candidates)} candidates:\n")
    for i, cand in enumerate(candidates, 1):
        conf_color = Color.GREEN if cand['confidence'] == 'high' else Color.YELLOW
        print(f"  {i}. GPIO {cand['gpio']} "
              f"({conf_color}{cand['confidence']} confidence{Color.NC})")
        print(f"     Chip: {cand['chip']['label']} (base {cand['chip']['base']})")
        print(f"     Method: {cand['method']}")
        print()

    # Check debugfs
    print("[3] Checking GPIO debugfs...\n")
    debugfs = check_gpio_debugfs()
    if debugfs:
        # Look for pin 98 references
        for line in debugfs.split('\n'):
            if '98' in line or 'gpio-98' in line.lower():
                print(f"  {line}")
    else:
        print("  Not available or permission denied")
    print()

    # Interactive testing
    if os.geteuid() != 0:
        print(f"{Color.YELLOW}Not running as root. Cannot test GPIOs.{Color.NC}")
        print("\nTo test, run:")
        print(f"  sudo python3 {sys.argv[0]}")
        return 0

    print("[4] Testing candidates...\n")
    dry_run = '--dry-run' in sys.argv

    for i, cand in enumerate(candidates, 1):
        print(f"Testing candidate {i}: GPIO {cand['gpio']}")
        if test_gpio(cand['gpio'], dry_run):
            print(f"\n{Color.GREEN}=== SUCCESS ==={Color.NC}")
            print(f"Working GPIO: {cand['gpio']}")
            print(f"\nTo make permanent, add to boot script:")
            print(f"  echo {cand['gpio']} > /sys/class/gpio/export")
            print(f"  echo out > /sys/class/gpio/gpio{cand['gpio']}/direction")
            print(f"  echo 1 > /sys/class/gpio/gpio{cand['gpio']}/value")
            return 0
        print()

    print(f"{Color.YELLOW}No working GPIO found.{Color.NC}")
    print("\nNext steps:")
    print("  1. Decompile DSDT and verify GPIO pin number")
    print("  2. Check if GPIO is managed by ACPI")
    print("  3. Verify pinctrl driver is loaded (lsmod | grep pinctrl)")

    return 1

if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print(f"\n{Color.YELLOW}Interrupted{Color.NC}")
        sys.exit(130)
