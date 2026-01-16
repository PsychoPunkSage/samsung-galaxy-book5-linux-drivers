#!/bin/bash
# Samsung Galaxy Book5 Pro - MAX98390 I2C Smart Amplifier Diagnostic
#
# This script checks if the MAX98390 I2C smart amplifiers are actually
# present and responding on the I2C bus.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "MAX98390 I2C Smart Amplifier Diagnostic"
echo "=========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run as root${NC}"
    echo "Usage: sudo $0"
    exit 1
fi

# 1. Check ACPI device
echo -e "${BLUE}[1] Checking ACPI device...${NC}"
if [ -d /sys/bus/i2c/devices/i2c-MAX98390:00 ]; then
    echo -e "${GREEN}✓ ACPI device exists: /sys/bus/i2c/devices/i2c-MAX98390:00${NC}"

    echo "  Device name: $(cat /sys/bus/i2c/devices/i2c-MAX98390:00/name)"
    echo "  Modalias: $(cat /sys/bus/i2c/devices/i2c-MAX98390:00/modalias)"

    if [ -f /sys/bus/i2c/devices/i2c-MAX98390:00/firmware_node/path ]; then
        echo "  ACPI path: $(cat /sys/bus/i2c/devices/i2c-MAX98390:00/firmware_node/path)"
    fi
else
    echo -e "${RED}✗ ACPI device NOT found${NC}"
    exit 1
fi
echo ""

# 2. Check I2C bus
echo -e "${BLUE}[2] Checking I2C bus 2...${NC}"
if [ -d /sys/bus/i2c/devices/i2c-2 ]; then
    echo -e "${GREEN}✓ I2C bus 2 exists${NC}"

    # Get I2C controller info
    I2C_PATH=$(readlink -f /sys/bus/i2c/devices/i2c-2)
    echo "  Controller path: $I2C_PATH"

    # Check if i2c-dev module loaded
    if lsmod | grep -q i2c_dev; then
        echo -e "${GREEN}✓ i2c-dev module loaded${NC}"
    else
        echo -e "${YELLOW}! i2c-dev module not loaded, loading now...${NC}"
        modprobe i2c-dev
    fi
else
    echo -e "${RED}✗ I2C bus 2 NOT found${NC}"
    exit 1
fi
echo ""

# 3. Scan I2C bus for MAX98390 devices
echo -e "${BLUE}[3] Scanning I2C bus 2 for devices...${NC}"
echo "Expected addresses: 0x38 (left) and 0x39 (right)"
echo ""

if command -v i2cdetect >/dev/null 2>&1; then
    i2cdetect -y 2
    echo ""

    # Parse i2cdetect output to check for specific addresses
    SCAN_OUTPUT=$(i2cdetect -y 2)

    if echo "$SCAN_OUTPUT" | grep -q " 38"; then
        echo -e "${GREEN}✓ Device found at 0x38 (left channel)${NC}"
        ADDR_38_FOUND=1
    else
        echo -e "${RED}✗ No device at 0x38 (left channel)${NC}"
        ADDR_38_FOUND=0
    fi

    if echo "$SCAN_OUTPUT" | grep -q " 39"; then
        echo -e "${GREEN}✓ Device found at 0x39 (right channel)${NC}"
        ADDR_39_FOUND=1
    else
        echo -e "${RED}✗ No device at 0x39 (right channel)${NC}"
        ADDR_39_FOUND=0
    fi
else
    echo -e "${YELLOW}! i2cdetect not found, installing i2c-tools...${NC}"
    apt-get update && apt-get install -y i2c-tools

    # Retry scan
    i2cdetect -y 2
fi
echo ""

# 4. Check MAX98390 codec module
echo -e "${BLUE}[4] Checking MAX98390 codec module...${NC}"
if modinfo snd_soc_max98390 >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Module exists: snd_soc_max98390${NC}"

    MODULE_PATH=$(modinfo snd_soc_max98390 | grep filename | awk '{print $2}')
    echo "  Path: $MODULE_PATH"
    echo "  Alias: $(modinfo snd_soc_max98390 | grep 'alias:.*acpi')"

    # Check if module loaded
    if lsmod | grep -q snd_soc_max98390; then
        echo -e "${GREEN}✓ Module is LOADED${NC}"

        # Check dmesg for MAX98390 messages
        if dmesg | grep -i max98390 | tail -5 | grep -q .; then
            echo ""
            echo "Recent kernel messages:"
            dmesg | grep -i max98390 | tail -5 | sed 's/^/  /'
        fi
    else
        echo -e "${YELLOW}! Module is NOT loaded${NC}"
        echo ""
        echo "Attempting to load module..."
        if modprobe snd_soc_max98390 2>&1; then
            echo -e "${GREEN}✓ Module loaded successfully${NC}"
            sleep 1

            # Check dmesg again
            if dmesg | grep -i max98390 | tail -10 | grep -q .; then
                echo ""
                echo "Kernel messages after loading:"
                dmesg | grep -i max98390 | tail -10 | sed 's/^/  /'
            fi
        else
            echo -e "${YELLOW}! Module loaded but no binding occurred${NC}"
            echo "This is expected - module needs machine driver to instantiate it"
        fi
    fi
else
    echo -e "${RED}✗ Module NOT found${NC}"
    exit 1
fi
echo ""

# 5. Check SOF machine driver
echo -e "${BLUE}[5] Checking SOF machine driver...${NC}"
CURRENT_DRIVER=$(lsmod | grep '^snd_soc.*hda_dsp' | awk '{print $1}')
if [ -n "$CURRENT_DRIVER" ]; then
    echo -e "${GREEN}✓ Machine driver loaded: $CURRENT_DRIVER${NC}"

    # Get driver info
    modinfo "$CURRENT_DRIVER" 2>/dev/null | grep -E 'filename|alias' | head -3 | sed 's/^/  /'

    if [ "$CURRENT_DRIVER" = "snd_soc_skl_hda_dsp" ]; then
        echo ""
        echo -e "${YELLOW}! Current driver: skl_hda_dsp_generic${NC}"
        echo -e "${YELLOW}  This is the generic fallback driver${NC}"
        echo -e "${YELLOW}  It does NOT support MAX98390 I2C amplifiers${NC}"
    fi
else
    echo -e "${YELLOW}! No SOF machine driver detected${NC}"
fi
echo ""

# 6. Check for second MAX98390 ACPI device
echo -e "${BLUE}[6] Checking for second MAX98390 device...${NC}"
if [ -d /sys/bus/i2c/devices/i2c-MAX98390:01 ]; then
    echo -e "${GREEN}✓ Second device exists: i2c-MAX98390:01${NC}"
    echo "  Name: $(cat /sys/bus/i2c/devices/i2c-MAX98390:01/name)"
else
    echo -e "${YELLOW}! Second device NOT found in sysfs${NC}"
    echo "  This may indicate single-amp configuration or naming issue"
fi
echo ""

# 7. Check GPIO for amplifier enable
echo -e "${BLUE}[7] Checking GPIO configuration...${NC}"
echo "ACPI declares GPIO 0x62 (pin 98) for amplifier enable"
echo ""

if [ -d /sys/class/gpio ]; then
    echo "Available GPIO chips:"
    for chip in /sys/class/gpio/gpiochip*; do
        if [ -d "$chip" ]; then
            BASE=$(cat "$chip/base" 2>/dev/null || echo "unknown")
            NGPIO=$(cat "$chip/ngpio" 2>/dev/null || echo "unknown")
            LABEL=$(cat "$chip/label" 2>/dev/null || echo "unknown")
            echo "  $chip: base=$BASE, ngpio=$NGPIO, label=$LABEL"
        fi
    done
    echo ""

    # Try to export GPIO 98 if it exists
    if [ ! -d /sys/class/gpio/gpio98 ]; then
        echo "Attempting to export GPIO 98..."
        if echo 98 > /sys/class/gpio/export 2>/dev/null; then
            echo -e "${GREEN}✓ GPIO 98 exported${NC}"
            sleep 0.2

            # Set as output
            if [ -d /sys/class/gpio/gpio98 ]; then
                echo "out" > /sys/class/gpio/gpio98/direction 2>/dev/null || true
                echo "1" > /sys/class/gpio/gpio98/value 2>/dev/null || true

                DIRECTION=$(cat /sys/class/gpio/gpio98/direction 2>/dev/null || echo "unknown")
                VALUE=$(cat /sys/class/gpio/gpio98/value 2>/dev/null || echo "unknown")
                echo "  Direction: $DIRECTION"
                echo "  Value: $VALUE"
            fi
        else
            echo -e "${YELLOW}! Could not export GPIO 98${NC}"
            echo "  GPIO may be in use or not available"
        fi
    else
        echo -e "${GREEN}✓ GPIO 98 already exported${NC}"
        DIRECTION=$(cat /sys/class/gpio/gpio98/direction 2>/dev/null || echo "unknown")
        VALUE=$(cat /sys/class/gpio/gpio98/value 2>/dev/null || echo "unknown")
        echo "  Direction: $DIRECTION"
        echo "  Value: $VALUE"
    fi
else
    echo -e "${YELLOW}! GPIO sysfs interface not available${NC}"
fi
echo ""

# 8. Summary and recommendations
echo "=========================================="
echo "SUMMARY"
echo "=========================================="
echo ""

if [ "${ADDR_38_FOUND:-0}" -eq 1 ] && [ "${ADDR_39_FOUND:-0}" -eq 1 ]; then
    echo -e "${GREEN}✓ BOTH MAX98390 amplifiers detected on I2C bus${NC}"
    echo ""
    echo "This confirms the MAX98390 amplifiers are PHYSICALLY PRESENT"
    echo "and responding to I2C communication."
    echo ""
    echo -e "${YELLOW}ISSUE: No machine driver to bind them to audio subsystem${NC}"
    echo ""
    echo "RESOLUTION PATHS:"
    echo ""
    echo "1. QUICK TEST: Check if HDA speakers work with GPIO fix"
    echo "   cd /home/psychopunk_sage/dev/drivers"
    echo "   sudo ./test-gpio-audio.sh"
    echo ""
    echo "2. IF GPIO TEST FAILS: Create custom machine driver"
    echo "   - See: /home/psychopunk_sage/dev/drivers/MAX98390-ANALYSIS.md"
    echo "   - Estimated effort: 2-3 days of kernel development"
    echo ""

elif [ "${ADDR_38_FOUND:-0}" -eq 1 ] || [ "${ADDR_39_FOUND:-0}" -eq 1 ]; then
    echo -e "${YELLOW}! PARTIAL detection: Only one MAX98390 found${NC}"
    echo ""
    echo "Expected: 2 devices (stereo configuration)"
    echo "Found: 1 device"
    echo ""
    echo "POSSIBLE CAUSES:"
    echo "- Second amp may be disabled/not powered"
    echo "- Second amp may have different I2C address"
    echo "- Mono configuration (unusual for laptop)"
    echo ""
    echo "NEXT STEP: Check ACPI for second device address"

else
    echo -e "${RED}✗ NO MAX98390 devices detected on I2C bus${NC}"
    echo ""
    echo "ACPI declares devices at 0x38 and 0x39, but I2C scan found nothing."
    echo ""
    echo "POSSIBLE CAUSES:"
    echo "1. Amplifiers not powered (GPIO enable not set)"
    echo "2. I2C communication disabled/misconfigured"
    echo "3. ACPI declaration incorrect (OEM firmware bug)"
    echo "4. MAX98390 not actually used on this model"
    echo ""
    echo "RECOMMENDATION:"
    echo "Try the HDA GPIO test first - speakers may use HDA codec instead:"
    echo ""
    echo "  cd /home/psychopunk_sage/dev/drivers"
    echo "  sudo ./test-gpio-audio.sh"
    echo ""
    echo "If HDA speakers work, MAX98390 is likely unused on this model."
fi

echo ""
echo "=========================================="
echo "For detailed analysis, see:"
echo "/home/psychopunk_sage/dev/drivers/MAX98390-ANALYSIS.md"
echo "=========================================="
