#!/bin/bash
# Quick GPIO test for MAX98390 - tests most likely candidates first

set -e

echo "=== Quick MAX98390 GPIO Test ==="
echo ""

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Must run as root"
    echo "Usage: sudo $0"
    exit 1
fi

# Most likely candidates based on typical Intel GPIO layout
# GPIO 98 + common Intel MTL/ARL base offsets
CANDIDATES=(610 658 723 560 512)

test_gpio() {
    local gpio=$1
    echo "----------------------------------------"
    echo "Testing GPIO $gpio..."

    # Export
    if ! echo $gpio > /sys/class/gpio/export 2>/dev/null; then
        if [ -d "/sys/class/gpio/gpio$gpio" ]; then
            echo "  Already exported, trying anyway..."
        else
            echo "  SKIP: Cannot export"
            return 1
        fi
    else
        echo "  ✓ Exported"
        sleep 0.3
    fi

    # Set direction
    if echo out > /sys/class/gpio/gpio$gpio/direction 2>/dev/null; then
        echo "  ✓ Direction set to output"
    else
        echo "  ✗ Failed to set direction"
        return 1
    fi

    # Read current value
    current=$(cat /sys/class/gpio/gpio$gpio/value 2>/dev/null || echo "?")
    echo "  Current value: $current"

    # Set to HIGH
    if echo 1 > /sys/class/gpio/gpio$gpio/value 2>/dev/null; then
        echo "  ✓ Set to HIGH"
    else
        echo "  ✗ Failed to set value"
        return 1
    fi

    # Wait for power-up
    sleep 0.5

    # Check I2C
    echo "  Checking I2C bus 2..."
    if i2cdetect -y 2 2>/dev/null | grep -qE '(38|39)'; then
        echo ""
        echo "╔════════════════════════════════════════╗"
        echo "║          SUCCESS!!!                    ║"
        echo "║  MAX98390 detected on I2C bus 2        ║"
        echo "║  Working GPIO: $gpio                   ║"
        echo "╚════════════════════════════════════════╝"
        echo ""
        echo "Full I2C scan:"
        i2cdetect -y 2
        echo ""
        echo "To make permanent, add to rc.local or systemd:"
        echo "  echo $gpio > /sys/class/gpio/export"
        echo "  echo out > /sys/class/gpio/gpio$gpio/direction"
        echo "  echo 1 > /sys/class/gpio/gpio$gpio/value"
        echo ""
        return 0
    else
        echo "  ✗ No device detected yet"
        return 1
    fi
}

# Test each candidate
for gpio in "${CANDIDATES[@]}"; do
    if test_gpio $gpio; then
        exit 0
    fi
    echo ""
done

echo "╔════════════════════════════════════════╗"
echo "║  No working GPIO found                 ║"
echo "╚════════════════════════════════════════╝"
echo ""
echo "Next steps:"
echo "1. Run full diagnostic: sudo ./enable_max98390_gpio.sh"
echo "2. Check ACPI tables: sudo acpidump > acpi.dat && iasl -d acpi.dat"
echo "3. Look for GpioIo resource in MAX98390 device section"
echo "4. Check if pinctrl driver locked the GPIO (dmesg | grep pinctrl)"
echo ""
exit 1
