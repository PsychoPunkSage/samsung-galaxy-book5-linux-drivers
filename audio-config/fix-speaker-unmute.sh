#!/bin/bash
# Samsung Galaxy Book5 Pro - Speaker Unmute Fix
# This script unmutes the HDA codec mixer path (Node 0x0d) that routes
# DAC output to the physical speakers

set -e

echo "=== Samsung Galaxy Book5 Pro Speaker Fix ==="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

echo "Current codec state:"
echo "-------------------"
grep -A3 "Node 0x0d.*Audio Mixer" /proc/asound/card0/codec#0 | grep "Amp-In vals"
echo ""

# HDA verb format for sysfs: NODE_ID VERB_ID PARAMETER
#
# Node 0x0d: Audio Mixer (routes to speaker pin 0x17)
# Verb 0x703: SET_AMP_GAIN_MUTE
#   Bits 15-13: 0x7 = Input amp
#   Bits 12-8: 0x00 = Input index 0
#   Bits 3-0: 0x3 = Select input 0
#
# Parameter for unmute:
#   Bit 15: 0 = Set left channel
#   Bit 14: 0 = Set right channel
#   Bit 13: 1 = Set both channels
#   Bit 7: 0 = Unmute (1 = mute)
#   Bits 6-0: Gain (0x00 = 0dB)
#
# Combined: 0xb000 = Set both channels, unmute, 0dB gain

echo "Writing HDA verbs to unmute mixer node 0x0d..."

# Unmute input 0 (from DAC 0x03) - both channels
echo "0x0d 0x7000 0xb000" > /sys/class/sound/hwC0D0/init_verbs
echo "  Left channel: unmute, 0dB"

echo "0x0d 0x7001 0xb000" > /sys/class/sound/hwC0D0/init_verbs
echo "  Right channel: unmute, 0dB"

echo ""
echo "Triggering codec reconfiguration..."
echo 1 > /sys/class/sound/hwC0D0/reconfig

echo "Waiting for codec to reinitialize..."
sleep 2

echo ""
echo "New codec state:"
echo "----------------"
grep -A3 "Node 0x0d.*Audio Mixer" /proc/asound/card0/codec#0 | grep "Amp-In vals"

echo ""
echo "ALSA mixer controls:"
echo "--------------------"
amixer -c0 sget Speaker | grep -E "(Playback|values)"
amixer -c0 sget Master | grep -E "(Playback|values)"

echo ""
echo "=== Fix applied! ==="
echo ""
echo "Test audio with:"
echo "  speaker-test -c2 -t wav -Dhw:0,0"
echo ""
echo "Or play a sound file:"
echo "  aplay -Dhw:0,0 /usr/share/sounds/alsa/Front_Center.wav"
echo ""
echo "If speakers still don't work, the issue may be in SOF topology."
echo "Check /lib/firmware/intel/sof-tplg/ for topology files."
