#!/bin/bash
# Samsung Galaxy Book5 Pro - MAX98390 GPIO Power Enable
# ACPI declares GPIO 0x62 (pin 98) for amp enable
# This script calculates the correct GPIO number and enables power

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== Samsung Galaxy Book5 Pro MAX98390 GPIO Power Enable ==="
echo ""

# First, let's gather GPIO controller information
echo "[1] Gathering GPIO controller information..."
echo ""

GPIO_BASES=(512 560 625 691 699)
ACPI_PIN=98  # 0x62 in decimal

echo "Available GPIO controllers:"
for chip in /sys/class/gpio/gpiochip*; do
    if [ -d "$chip" ]; then
        base=$(cat "$chip/base")
        ngpio=$(cat "$chip/ngpio")
        label=$(cat "$chip/label")
        end=$((base + ngpio - 1))
        echo "  - Base: $base, Count: $ngpio (range $base-$end), Label: $label"
    fi
done
echo ""

# Calculate possible GPIO numbers
echo "[2] Calculating possible GPIO numbers for ACPI pin $ACPI_PIN (0x62)..."
echo ""

CANDIDATES=()
for base in "${GPIO_BASES[@]}"; do
    gpio=$((base + ACPI_PIN))
    echo "  - GPIO $gpio (base $base + $ACPI_PIN)"
    CANDIDATES+=($gpio)
done
echo ""

# Method 1: Try direct GPIO export and enable
echo "[3] Method 1: Direct GPIO export and power-on..."
echo ""

for gpio in "${CANDIDATES[@]}"; do
    echo -e "${YELLOW}Testing GPIO $gpio...${NC}"

    # Try to export
    if echo $gpio > /sys/class/gpio/export 2>/dev/null; then
        echo "  ✓ Exported GPIO $gpio"
        sleep 0.5

        if [ -d "/sys/class/gpio/gpio$gpio" ]; then
            # Set direction to output
            if echo out > /sys/class/gpio/gpio$gpio/direction 2>/dev/null; then
                echo "  ✓ Set direction to output"

                # Read current value
                current=$(cat /sys/class/gpio/gpio$gpio/value 2>/dev/null || echo "?")
                echo "  ✓ Current value: $current"

                # Set to high (enable)
                if echo 1 > /sys/class/gpio/gpio$gpio/value 2>/dev/null; then
                    echo -e "  ${GREEN}✓ Set GPIO $gpio to HIGH (enabled)${NC}"

                    # Wait for device to power up
                    echo "  ⏳ Waiting 500ms for device power-up..."
                    sleep 0.5

                    # Scan I2C bus 2 for MAX98390 at 0x38 and 0x39
                    echo "  📡 Scanning I2C bus 2 for MAX98390..."
                    if command -v i2cdetect &> /dev/null; then
                        i2cdetect -y 2 2>&1 | grep -E "(38|39)" && {
                            echo -e "${GREEN}  ✓✓✓ SUCCESS! MAX98390 detected on I2C bus 2${NC}"
                            echo ""
                            echo "Working GPIO: $gpio"
                            echo "To make permanent, add to boot script:"
                            echo "  echo $gpio > /sys/class/gpio/export"
                            echo "  echo out > /sys/class/gpio/gpio$gpio/direction"
                            echo "  echo 1 > /sys/class/gpio/gpio$gpio/value"
                            exit 0
                        }
                    else
                        echo "  ⚠ i2cdetect not found, install i2c-tools"
                    fi
                else
                    echo -e "  ${RED}✗ Failed to set GPIO value${NC}"
                fi
            else
                echo -e "  ${RED}✗ Failed to set direction${NC}"
            fi
        else
            echo -e "  ${RED}✗ GPIO directory not created${NC}"
        fi
    else
        echo "  ℹ GPIO $gpio not available (may be already in use or invalid)"
    fi
    echo ""
done

# Method 2: Try ACPI device power control
echo "[4] Method 2: ACPI device power control..."
echo ""

ACPI_DEVICES=(
    "/sys/bus/acpi/devices/MAX98390:00"
    "/sys/bus/acpi/devices/MXIM8390:00"
    "/sys/bus/acpi/devices/10EC5682:00"  # In case it's under codec
)

for device in "${ACPI_DEVICES[@]}"; do
    if [ -d "$device" ]; then
        echo "Found ACPI device: $device"

        # Check power state
        if [ -f "$device/power_state" ]; then
            state=$(cat "$device/power_state" 2>/dev/null || echo "unknown")
            echo "  Current power state: $state"
        fi

        # Check status
        if [ -f "$device/status" ]; then
            status=$(cat "$device/status" 2>/dev/null || echo "unknown")
            echo "  Status: $status"
        fi

        # Try to enable
        if [ -f "$device/power/control" ]; then
            echo "  Attempting to set power control to 'on'..."
            echo on > "$device/power/control" 2>/dev/null && {
                echo -e "  ${GREEN}✓ Power control set to 'on'${NC}"
                sleep 0.5

                # Check I2C again
                echo "  📡 Scanning I2C bus 2..."
                i2cdetect -y 2 2>&1 | grep -E "(38|39)" && {
                    echo -e "${GREEN}  ✓✓✓ SUCCESS via ACPI power control!${NC}"
                    exit 0
                }
            } || echo -e "  ${RED}✗ Failed to set power control${NC}"
        fi
        echo ""
    fi
done

# Method 3: Check if GPIO is managed by ACPI resource
echo "[5] Method 3: ACPI GPIO resource inspection..."
echo ""

echo "Checking ACPI tables for GPIO resources..."
if [ -f "/sys/firmware/acpi/tables/DSDT" ]; then
    echo "DSDT table found. Checking for MAX98390 GPIO resources..."

    # This requires iasl to be installed
    if command -v iasl &> /dev/null; then
        TMP_DIR=$(mktemp -d)
        cp /sys/firmware/acpi/tables/DSDT "$TMP_DIR/dsdt.dat"
        cd "$TMP_DIR"
        iasl -d dsdt.dat 2>&1 | grep -i max98390 || echo "  No direct MAX98390 references found"
        cd - > /dev/null
        rm -rf "$TMP_DIR"
    else
        echo "  ⚠ iasl not installed (apt install acpica-tools)"
    fi
fi
echo ""

# Method 4: Try pinctrl/gpiod approach
echo "[6] Method 4: Check pinctrl subsystem..."
echo ""

if [ -d "/sys/kernel/debug/gpio" ]; then
    echo "Available GPIOs from debugfs:"
    cat /sys/kernel/debug/gpio 2>/dev/null | grep -E "(gpio-98|GPP.*98)" || echo "  Pin 98 not found in debugfs"
else
    echo "  GPIO debugfs not available (may need CONFIG_DEBUG_FS)"
fi
echo ""

# Summary
echo "=== Summary ==="
echo ""
echo -e "${YELLOW}If no method worked, the GPIO might be:${NC}"
echo "  1. Already enabled by firmware (check dmesg for MAX98390)"
echo "  2. Using a different pin number (check DSDT decompilation)"
echo "  3. Controlled via ACPI methods (_PS0/_PS3)"
echo "  4. Managed by pinctrl and needs kernel driver"
echo ""
echo "Next steps:"
echo "  1. Check dmesg: dmesg | grep -iE 'max98390|gpio'"
echo "  2. Decompile DSDT: sudo acpidump > acpi.dat && iasl -d acpi.dat"
echo "  3. Search for GpioInt/GpioIo in MAX98390 device section"
echo "  4. Check if kernel has CONFIG_PINCTRL_METEORLAKE=y"
echo ""
