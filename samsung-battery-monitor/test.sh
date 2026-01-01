#!/bin/bash
# Quick test script for battery monitor
#
# This script tests the battery monitoring functionality without installing
# the systemd service. Useful for development and debugging.

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "============================================================="
echo "  Samsung Battery Monitor - Test Mode"
echo "============================================================="
echo ""

# Check if binary exists
if [ ! -f "$SCRIPT_DIR/target/release/battery-monitor" ]; then
    echo "Binary not found. Building..."
    cd "$SCRIPT_DIR"
    cargo build --release
    echo ""
fi

# Display battery info
echo "Current Battery Status:"
echo "----------------------"
if [ -f /sys/class/power_supply/BAT1/capacity ]; then
    echo "  Capacity: $(cat /sys/class/power_supply/BAT1/capacity)%"
    echo "  Status: $(cat /sys/class/power_supply/BAT1/status)"
    echo "  Charge Now: $(cat /sys/class/power_supply/BAT1/charge_now) µAh"
    echo "  Charge Full: $(cat /sys/class/power_supply/BAT1/charge_full) µAh"
    echo "  Current Now: $(cat /sys/class/power_supply/BAT1/current_now) µA"
    echo "  Voltage Now: $(cat /sys/class/power_supply/BAT1/voltage_now) µV"
else
    echo "  ERROR: Battery device not found at /sys/class/power_supply/BAT1"
    exit 1
fi

if [ -f /sys/class/power_supply/ADP1/online ]; then
    AC_ONLINE=$(cat /sys/class/power_supply/ADP1/online)
    if [ "$AC_ONLINE" = "1" ]; then
        echo "  AC Adapter: Connected"
    else
        echo "  AC Adapter: Disconnected"
    fi
fi

echo ""
echo "============================================================="
echo "  Running Battery Monitor (Press Ctrl+C to stop)"
echo "============================================================="
echo ""

# Run the monitor
"$SCRIPT_DIR/target/release/battery-monitor"
