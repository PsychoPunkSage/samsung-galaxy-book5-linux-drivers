#!/bin/bash
# Samsung Galaxy Book5 Pro - GPIO Audio Test
# Identifies which GPIO pin enables the speaker amplifier

set -e

if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root: sudo $0"
    exit 1
fi

echo "========================================"
echo "Samsung Galaxy Book5 - GPIO Audio Test"
echo "========================================"
echo ""
echo "This script will test all 8 GPIO pins on the Realtek ALC298 codec"
echo "to find which one enables the external speaker amplifier."
echo ""
echo "INSTRUCTIONS:"
echo "1. Keep this terminal window visible"
echo "2. Open another terminal and run: speaker-test -c2 -Dhw:0,0"
echo "3. You should hear silence initially"
echo "4. When a GPIO is enabled, listen for audio"
echo "5. Press ENTER in this window when you hear sound"
echo ""
echo "Press ENTER to start the test..."
read

# First, verify current GPIO state
echo ""
echo "=== Current GPIO State ==="
grep -A10 "^GPIO:" /proc/asound/card0/codec#0

# Test each GPIO individually
echo ""
echo "=== Testing Individual GPIOs ==="
echo ""

for gpio in 0 1 2 3 4 5 6 7; do
    mask=$((1 << gpio))

    printf "\n[Test %d/8] GPIO_%d (mask=0x%02X)\n" $((gpio + 1)) $gpio $mask
    printf "  Enabling GPIO_%d as OUTPUT=HIGH...\n" $gpio

    hda-verb /dev/snd/hwC0D0 0x01 SET_GPIO_MASK $mask > /dev/null 2>&1
    hda-verb /dev/snd/hwC0D0 0x01 SET_GPIO_DIRECTION $mask > /dev/null 2>&1
    hda-verb /dev/snd/hwC0D0 0x01 SET_GPIO_DATA $mask > /dev/null 2>&1

    echo "  >> Listening for 3 seconds..."
    sleep 3

    echo -n "  >> Do you hear audio? (y/n/skip): "
    read -t 10 answer || answer="n"

    if [ "$answer" = "y" ]; then
        echo ""
        echo "****************************************"
        echo "*** SUCCESS! GPIO_$gpio ENABLES AUDIO ***"
        echo "****************************************"
        echo ""
        echo "Codec GPIO configuration needed:"
        echo "  GPIO Mask:      0x$(printf '%02X' $mask)"
        echo "  GPIO Direction: 0x$(printf '%02X' $mask) (output)"
        echo "  GPIO Data:      0x$(printf '%02X' $mask) (high)"
        echo ""
        echo "Add this to /etc/modprobe.d/alsa-base.conf:"
        echo "  options snd-hda-intel patch=alc298-gpio$gpio.fw"
        echo ""
        echo "Kernel quirk needed in sound/pci/hda/patch_realtek.c:"
        echo "  { 0x144d, 0xca08, \"Samsung Galaxy Book5\", ALC298_FIXUP_GPIO$gpio },"
        echo ""
        echo "Verification command:"
        grep -A10 "^GPIO:" /proc/asound/card0/codec#0
        exit 0
    fi

    if [ "$answer" = "skip" ]; then
        echo "  Skipping to next GPIO..."
        continue
    fi

    echo "  No audio detected. Disabling GPIO_$gpio..."
    hda-verb /dev/snd/hwC0D0 0x01 SET_GPIO_DATA 0x00 > /dev/null 2>&1
    sleep 1
done

# None worked individually - try combinations
echo ""
echo "=== Individual GPIOs Failed - Testing Combinations ==="
echo ""

echo "[Test 9/10] All GPIOs HIGH (0xFF)"
echo "  Enabling all GPIOs..."
hda-verb /dev/snd/hwC0D0 0x01 SET_GPIO_MASK 0xff > /dev/null 2>&1
hda-verb /dev/snd/hwC0D0 0x01 SET_GPIO_DIRECTION 0xff > /dev/null 2>&1
hda-verb /dev/snd/hwC0D0 0x01 SET_GPIO_DATA 0xff > /dev/null 2>&1

echo "  >> Listening for 3 seconds..."
sleep 3

echo -n "  >> Do you hear audio? (y/n): "
read -t 10 answer || answer="n"

if [ "$answer" = "y" ]; then
    echo ""
    echo "Audio works with ALL GPIOs HIGH!"
    echo "Now narrowing down which specific combination is needed..."
    echo ""

    # Binary search through GPIO combinations
    echo "Testing lower 4 GPIOs (0-3)..."
    hda-verb /dev/snd/hwC0D0 0x01 SET_GPIO_MASK 0x0f > /dev/null 2>&1
    hda-verb /dev/snd/hwC0D0 0x01 SET_GPIO_DIRECTION 0x0f > /dev/null 2>&1
    hda-verb /dev/snd/hwC0D0 0x01 SET_GPIO_DATA 0x0f > /dev/null 2>&1
    sleep 2
    echo -n "Audio with GPIO 0-3? (y/n): "
    read answer_low

    echo "Testing upper 4 GPIOs (4-7)..."
    hda-verb /dev/snd/hwC0D0 0x01 SET_GPIO_MASK 0xf0 > /dev/null 2>&1
    hda-verb /dev/snd/hwC0D0 0x01 SET_GPIO_DIRECTION 0xf0 > /dev/null 2>&1
    hda-verb /dev/snd/hwC0D0 0x01 SET_GPIO_DATA 0xf0 > /dev/null 2>&1
    sleep 2
    echo -n "Audio with GPIO 4-7? (y/n): "
    read answer_high

    echo ""
    echo "Results:"
    echo "  GPIO 0-3: $answer_low"
    echo "  GPIO 4-7: $answer_high"
    echo ""
    echo "Multiple GPIOs needed. Manual analysis required."
    echo "Restoring all GPIOs HIGH state..."
    hda-verb /dev/snd/hwC0D0 0x01 SET_GPIO_DATA 0xff > /dev/null 2>&1
    exit 0
fi

# Try mixer switching as last resort
echo ""
echo "[Test 10/10] Alternative Mixer Path"
echo "  Switching speaker from Mixer 0x0d to Mixer 0x0c..."
hda-verb /dev/snd/hwC0D0 0x17 SET_CONNECT_SEL 0 > /dev/null 2>&1

echo "  >> Listening for 3 seconds..."
sleep 3

echo -n "  >> Do you hear audio? (y/n): "
read -t 10 answer || answer="n"

if [ "$answer" = "y" ]; then
    echo ""
    echo "****************************************"
    echo "*** Audio works with MIXER 0x0c!     ***"
    echo "****************************************"
    echo ""
    echo "The problem is the default mixer selection."
    echo "Pin 0x17 should connect to Mixer 0x0c (DAC 0x02) instead of Mixer 0x0d (DAC 0x03)"
    echo ""
    echo "Add this init_verb:"
    echo "  0x17 SET_CONNECT_SEL 0"
    exit 0
fi

# Nothing worked
echo ""
echo "========================================"
echo "RESULT: No GPIO configuration enabled audio"
echo "========================================"
echo ""
echo "This suggests:"
echo "1. External amplifier on I2C/SPI bus (not GPIO-controlled)"
echo "2. EC-controlled amplifier enable"
echo "3. SOF DSP topology routing issue"
echo ""
echo "Next steps:"
echo "  1. Run: sudo dmesg | grep -iE 'cs35l|tas256|rt131'"
echo "  2. Check: ls -la /sys/bus/i2c/devices/"
echo "  3. Analyze ACPI tables for amplifier devices"
echo ""
echo "Current GPIO state:"
grep -A10 "^GPIO:" /proc/asound/card0/codec#0
