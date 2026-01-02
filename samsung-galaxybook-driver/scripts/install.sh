#!/bin/bash
# Samsung Galaxy Book Driver - Installation Script
# Builds, installs, and configures the driver for automatic loading

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DRIVER_NAME="samsung-galaxybook"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo "========================================"
echo "  Samsung Galaxy Book Driver Installer"
echo "========================================"
echo ""

# Check prerequisites
info "Checking prerequisites..."

if [ ! -f /sys/bus/acpi/devices/SAM0430:00/status ]; then
    error "SAM0430 ACPI device not found. This driver is for Samsung Galaxy Book laptops only."
fi

if ! command -v make &> /dev/null; then
    error "make not found. Install with: sudo apt install build-essential"
fi

if [ ! -d "/lib/modules/$(uname -r)/build" ]; then
    error "Kernel headers not found. Install with: sudo apt install linux-headers-$(uname -r)"
fi

info "All prerequisites met."
echo ""

# Build driver
info "Building driver..."
cd "$PROJECT_DIR"
make clean > /dev/null 2>&1 || true
make || error "Build failed. Check kernel headers installation."
info "Build successful."
echo ""

# Install driver
info "Installing driver..."
sudo make install || error "Installation failed."
echo ""

# Configure auto-load on boot
info "Configuring auto-load on boot..."
echo "$DRIVER_NAME" | sudo tee /etc/modules-load.d/${DRIVER_NAME}.conf > /dev/null
info "Driver will load automatically on boot."
echo ""

# Load driver now
info "Loading driver..."
sudo modprobe platform_profile 2>/dev/null || true
sudo modprobe $DRIVER_NAME || error "Failed to load driver. Check dmesg for details."
echo ""

# Verify installation
info "Verifying installation..."
echo ""

if [ -f /sys/class/power_supply/BAT1/charge_control_end_threshold ]; then
    THRESHOLD=$(cat /sys/class/power_supply/BAT1/charge_control_end_threshold)
    echo -e "  ${GREEN}✓${NC} Battery charge threshold: ${THRESHOLD}%"
else
    echo -e "  ${YELLOW}!${NC} Battery charge threshold not available"
fi

if [ -d /sys/class/leds/samsung-galaxybook::kbd_backlight ]; then
    BRIGHTNESS=$(cat /sys/class/leds/samsung-galaxybook::kbd_backlight/brightness)
    echo -e "  ${GREEN}✓${NC} Keyboard backlight: level ${BRIGHTNESS}/3"
else
    echo -e "  ${YELLOW}!${NC} Keyboard backlight not available"
fi

if [ -f /sys/firmware/acpi/platform_profile ]; then
    PROFILE=$(cat /sys/firmware/acpi/platform_profile)
    echo -e "  ${GREEN}✓${NC} Performance profile: ${PROFILE}"
else
    echo -e "  ${YELLOW}!${NC} Performance profile not available"
fi

echo ""
echo "========================================"
echo "  Installation Complete!"
echo "========================================"
echo ""
echo "Usage:"
echo "  # Set battery charge limit to 80%"
echo "  echo 80 | sudo tee /sys/class/power_supply/BAT1/charge_control_end_threshold"
echo ""
echo "  # Set keyboard backlight (0=off, 1=low, 2=med, 3=high)"
echo "  echo 3 | tee /sys/class/leds/samsung-galaxybook::kbd_backlight/brightness"
echo ""
echo "  # Set performance profile (low-power, balanced, performance)"
echo "  echo balanced | sudo tee /sys/firmware/acpi/platform_profile"
echo ""
