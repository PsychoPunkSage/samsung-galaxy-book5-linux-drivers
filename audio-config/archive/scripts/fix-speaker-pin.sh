#!/bin/bash
# Samsung Galaxy Book5 Pro - Speaker Pin Output Amp Unmute Fix
# Fixes Node 0x17 (Speaker Pin) output amplifier mute issue

set -e

echo "========================================"
echo "Samsung Galaxy Book5 Pro - Speaker Fix"
echo "Unmuting Node 0x17 Output Amplifier"
echo "========================================"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

# Check if codec exists
if [ ! -e /sys/class/sound/hwC0D0/init_verbs ]; then
    echo "ERROR: HDA codec sysfs interface not found"
    echo "Path: /sys/class/sound/hwC0D0/init_verbs"
    exit 1
fi

echo "Step 1: Checking current state..."
echo
echo "Node 0x17 (Speaker Pin) - BEFORE FIX:"
grep -A8 "Node 0x17" /proc/asound/card0/codec#0 | grep "Amp-Out vals" || echo "  Could not read state"
echo

echo "Step 2: Applying HDA verbs..."
echo

# Unmute mixer node 0x0d (in case it's still muted)
echo "  - Unmuting mixer node 0x0d..."
echo "0x0d 0x7000 0xb000" > /sys/class/sound/hwC0D0/init_verbs

# Unmute speaker pin 0x17 output amplifier (CRITICAL FIX!)
echo "  - Unmuting speaker pin 0x17 output amp..."
echo "0x17 0x3000 0xb000" > /sys/class/sound/hwC0D0/init_verbs

# Enable EAPD on speaker pin
echo "  - Enabling speaker amplifier (EAPD)..."
echo "0x17 0x70c 0x0002" > /sys/class/sound/hwC0D0/init_verbs

# Set pin to output mode
echo "  - Setting pin to output mode..."
echo "0x17 0x707 0x0040" > /sys/class/sound/hwC0D0/init_verbs

echo
echo "Step 3: Triggering codec reconfiguration..."
echo 1 > /sys/class/sound/hwC0D0/reconfig

echo "  Waiting for codec to reinitialize..."
sleep 3

echo
echo "Step 4: Verifying fix..."
echo
echo "Node 0x17 (Speaker Pin) - AFTER FIX:"
grep -A8 "Node 0x17" /proc/asound/card0/codec#0 | grep "Amp-Out vals" || echo "  Could not read state"
echo

echo "========================================"
echo "Fix applied successfully!"
echo "========================================"
echo
echo "TEST AUDIO NOW:"
echo "  speaker-test -c2 -t wav -Dhw:0,0"
echo
echo "Or play a sound file:"
echo "  aplay -Dhw:0,0 /usr/share/sounds/alsa/Front_Center.wav"
echo
echo "Press Ctrl+C to stop speaker-test when you hear sound."
echo
