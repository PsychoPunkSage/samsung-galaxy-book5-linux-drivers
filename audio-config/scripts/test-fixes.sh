#!/bin/bash
# test-fixes.sh - Systematic testing of speaker fix options
# Samsung Galaxy Book5 Pro (0x144dca08)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "======================================"
echo "Samsung Galaxy Book5 Pro Speaker Fix Test"
echo "======================================"
echo

# Function to print status
print_status() {
    echo -e "${YELLOW}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[+]${NC} $1"
}

print_error() {
    echo -e "${RED}[-]${NC} $1"
}

# Check current configuration
print_status "Checking current configuration..."
if [ -f /etc/modprobe.d/samsung-audio-fix.conf ]; then
    echo "Current config:"
    cat /etc/modprobe.d/samsung-audio-fix.conf
else
    print_error "No config file found"
fi
echo

# Check current kernel parameter
print_status "Checking kernel parameter status..."
if [ -f /sys/module/snd_hda_intel/parameters/model ]; then
    echo "Current model parameter:"
    cat /sys/module/snd_hda_intel/parameters/model
else
    print_error "Cannot read model parameter"
fi
echo

# Check if kernel has Samsung code
print_status "Checking if kernel has Samsung amp support..."
if strings /lib/modules/$(uname -r)/kernel/sound/pci/hda/snd-hda-codec-realtek.ko 2>/dev/null | grep -q -i samsung; then
    print_success "Kernel appears to have Samsung support"
else
    print_error "No Samsung references found in kernel module"
    echo "This suggests Ubuntu kernel doesn't have the Samsung amp quirk compiled in"
fi
echo

# Check codec state
print_status "Checking codec state..."
if [ -f /proc/asound/card0/codec#0 ]; then
    echo "GPIO state:"
    grep -A8 "^GPIO:" /proc/asound/card0/codec#0 | head -9
else
    print_error "Cannot read codec state"
fi
echo

echo "======================================"
echo "AVAILABLE FIX OPTIONS"
echo "======================================"
echo

echo "Option 1: Try 4-amp variant (currently using 2-amp)"
echo "  Command: sudo bash -c 'echo \"options snd-hda-intel model=alc298-samsung-amp-v2-4-amps\" > /etc/modprobe.d/samsung-audio-fix.conf && update-initramfs -u'"
echo "  Risk: LOW - Fully reversible"
echo "  Success chance: 20%"
echo

echo "Option 2: Check if kernel source has Samsung code"
echo "  Command: sudo apt install linux-source-$(uname -r) && tar -xf /usr/src/linux-source-*.tar.bz2 -C /tmp"
echo "  Risk: NONE - Just diagnostic"
echo

echo "Option 3: Upgrade to mainline kernel"
echo "  Risk: MEDIUM - Requires kernel change"
echo "  Success chance: 80%"
echo "  See: /home/psychopunk_sage/dev/drivers/audio-config/DIAGNOSTIC-FAILURE-ANALYSIS.md"
echo

echo "Option 4: Manual HDA verb initialization"
echo "  Risk: MEDIUM - Experimental"
echo "  Success chance: 30%"
echo

echo "Option 5: Build custom kernel module"
echo "  Risk: LOW - Only replaces audio module"
echo "  Success chance: 95%"
echo "  Time: 2-3 hours"
echo

echo "======================================"
echo "QUICK TEST: Apply Option 1 (4-amp variant)"
echo "======================================"
read -p "Apply 4-amp variant now and reboot? (y/N): " response
if [[ "$response" =~ ^[Yy]$ ]]; then
    print_status "Updating configuration to 4-amp variant..."
    sudo bash -c 'echo "options snd-hda-intel model=alc298-samsung-amp-v2-4-amps" > /etc/modprobe.d/samsung-audio-fix.conf'

    print_status "Updating initramfs..."
    sudo update-initramfs -u

    print_success "Configuration updated!"
    echo
    echo "======================================"
    echo "NEXT STEPS"
    echo "======================================"
    echo "1. Reboot your system: sudo reboot"
    echo "2. After reboot, test speakers: speaker-test -c2 -t wav"
    echo "3. Check if quirk applied: dmesg | grep -i samsung"
    echo "4. Check codec state: cat /proc/asound/card0/codec#0 | grep -A8 GPIO"
    echo
    echo "If still no sound, the kernel likely doesn't have the Samsung amp code."
    echo "See DIAGNOSTIC-FAILURE-ANALYSIS.md for next steps."
    echo
    read -p "Reboot now? (y/N): " reboot_response
    if [[ "$reboot_response" =~ ^[Yy]$ ]]; then
        sudo reboot
    fi
else
    echo
    print_status "No changes made. Review options above and choose one."
    echo "For detailed analysis, see: /home/psychopunk_sage/dev/drivers/audio-config/DIAGNOSTIC-FAILURE-ANALYSIS.md"
fi
