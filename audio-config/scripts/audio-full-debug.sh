#!/bin/bash
# Samsung Galaxy Book5 Pro - Complete Audio Diagnostic
# Identifies missing audio components

echo "================================================"
echo "Samsung Galaxy Book5 Pro - Audio Full Diagnostic"
echo "================================================"
echo ""

echo "=== ACPI Audio Devices ==="
echo "Looking for audio amplifiers, codecs, DSPs..."
find /sys/bus/acpi/devices/ -type d 2>/dev/null | while read dev; do
    if [ -f "$dev/status" ]; then
        status=$(cat "$dev/status" 2>/dev/null)
        if [ "$status" = "15" ] || [ "$status" = "0x0000000f" ]; then
            hid=$(cat "$dev/hid" 2>/dev/null || echo "unknown")
            path=$(cat "$dev/path" 2>/dev/null || echo "unknown")
            echo "  Device: $hid (Path: $path) - Status: $status (Present & Functional)"
        fi
    fi
done

echo ""
echo "=== I2C Bus Scan ==="
echo "Scanning all I2C buses for audio amplifiers..."
for bus in /sys/bus/i2c/devices/i2c-*; do
    if [ -d "$bus" ]; then
        busnum=$(basename "$bus" | sed 's/i2c-//')
        echo "  Bus $busnum:"
        ls -1 "$bus" | grep -E "^[0-9]+-[0-9a-f]+$" | while read device; do
            name=$(cat "$bus/$device/name" 2>/dev/null || echo "unknown")
            echo "    - $device: $name"
        done
    fi
done

# Try to scan I2C buses for common amplifier addresses
echo ""
echo "  Attempting hardware I2C scan (requires i2c-tools)..."
if command -v i2cdetect >/dev/null 2>&1; then
    for i in $(seq 0 10); do
        if [ -e "/dev/i2c-$i" ]; then
            echo "    Bus $i:"
            sudo i2cdetect -y $i 2>/dev/null | grep -E "40|41|42|43" && echo "      ^ Possible audio amp at 0x40-0x43"
        fi
    done
else
    echo "    (Install i2c-tools for detailed scan: sudo apt install i2c-tools)"
fi

echo ""
echo "=== SPI Devices ==="
ls -la /sys/bus/spi/devices/ 2>/dev/null || echo "  No SPI devices found"

echo ""
echo "=== Platform Audio Devices ==="
ls -1 /sys/bus/platform/devices/ 2>/dev/null | grep -iE "audio|amp|codec|cs35|tas|rt|speaker" || echo "  None found"

echo ""
echo "=== GPIO State ==="
if [ -r /sys/kernel/debug/gpio ]; then
    sudo cat /sys/kernel/debug/gpio 2>/dev/null | grep -iE "audio|amp|speaker|codec|enable|mute" || echo "  No audio-related GPIOs found"
else
    echo "  /sys/kernel/debug/gpio not accessible (try: sudo)"
fi

echo ""
echo "=== SOF Firmware & Topology ==="
echo "Loaded firmware:"
sudo dmesg | grep -E "sof.*firmware.*load|sof.*tplg.*load" | tail -5
echo ""
echo "Available topology files:"
ls -1 /lib/firmware/intel/sof-tplg/ 2>/dev/null | grep -iE "lnl|mtl|tgl|hda" | head -10

echo ""
echo "=== Active Audio Modules ==="
lsmod | grep -E "^(snd|sof|cs35|tas|rt)" | awk '{printf "  %-30s %s\n", $1, $2}'

echo ""
echo "=== HDA Codec Connections ==="
echo "Speaker Pin (Node 0x17) connections:"
cat /proc/asound/card0/codec#0 2>/dev/null | grep -A15 "Node 0x17" | grep -E "Connection:|Connection: [0-9]"

echo ""
echo "Current selection:"
cat /proc/asound/card0/codec#0 2>/dev/null | grep -A15 "Node 0x17" | grep "0x0c 0x0d"

echo ""
echo "=== EC Debug (if available) ==="
if [ -r /sys/kernel/debug/ec/ec0/io ]; then
    echo "EC I/O space (first 128 bytes, audio control typically in 0x80-0x9F):"
    sudo cat /sys/kernel/debug/ec/ec0/io 2>/dev/null | hexdump -C -n 128
else
    echo "  EC debug interface not available"
    echo "  Try: sudo modprobe ec_sys"
fi

echo ""
echo "=== ACPI Method Scan ==="
if command -v acpidump >/dev/null 2>&1; then
    echo "Extracting ACPI tables..."
    tmpdir=$(mktemp -d)
    cd "$tmpdir"
    sudo acpidump -b >/dev/null 2>&1
    iasl -d *.dat >/dev/null 2>&1

    echo "Searching for audio amplifier device declarations..."
    grep -h "CS35L\|TAS25\|TAS256\|RT131\|RT1318\|ESSX\|NAU88\|MAX98" *.dsl 2>/dev/null | head -20

    echo ""
    echo "Searching for I2C/GPIO audio controls..."
    grep -h "I2cSerialBusV2.*0x0040\|I2cSerialBusV2.*0x0041\|GpioIo.*audio\|GpioIo.*amp" *.dsl 2>/dev/null | head -10

    cd - >/dev/null
    rm -rf "$tmpdir"
else
    echo "  acpidump not available (install: sudo apt install acpica-tools)"
fi

echo ""
echo "=== Windows Driver Comparison (if dual-boot) ==="
if [ -d "/sys/firmware/efi/efivars" ]; then
    echo "UEFI system detected. If you have Windows installed, check:"
    echo "  Device Manager -> Sound controllers -> Realtek -> Details -> Hardware IDs"
    echo "  Look for INTELAUDIO\\FUNC_01&VEN_10EC&DEV_0298&SUBSYS_144DCA08"
    echo ""
    echo "  Also check for separate 'Smart Audio' or 'Amplifier' device"
fi

echo ""
echo "=== Current Audio Routing ==="
echo "DAC 0x03 -> Mixer 0x0d -> Pin 0x17 -> Physical Speaker"
echo ""
echo "Node 0x03 (DAC) state:"
cat /proc/asound/card0/codec#0 2>/dev/null | grep -A8 "Node 0x03" | grep -E "Amp-Out vals|Converter:"
echo ""
echo "Node 0x0d (Mixer) state:"
cat /proc/asound/card0/codec#0 2>/dev/null | grep -A4 "Node 0x0d" | grep "Amp-In vals"
echo ""
echo "Node 0x17 (Speaker Pin) state:"
cat /proc/asound/card0/codec#0 2>/dev/null | grep -A12 "Node 0x17" | grep -E "Amp-Out vals|EAPD|Pin-ctls"

echo ""
echo "=== PCM Stream Status ==="
cat /proc/asound/card0/pcm0p/sub0/status 2>/dev/null | grep -E "state:|hw_ptr:|appl_ptr:"

echo ""
echo "================================================"
echo "Diagnostic complete. Save this output and analyze."
echo "================================================"
