#!/bin/bash
# Samsung Galaxy Book Driver - Uninstallation Script

set -e

DRIVER_NAME="samsung-galaxybook"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }

echo "========================================"
echo "  Samsung Galaxy Book Driver Uninstaller"
echo "========================================"
echo ""

# Unload driver
info "Unloading driver..."
sudo rmmod ${DRIVER_NAME} 2>/dev/null || true

# Remove auto-load config
info "Removing auto-load configuration..."
sudo rm -f /etc/modules-load.d/${DRIVER_NAME}.conf

# Remove driver
info "Removing driver module..."
sudo rm -f /lib/modules/$(uname -r)/kernel/drivers/platform/x86/${DRIVER_NAME}.ko
sudo depmod -a

echo ""
info "Uninstallation complete."
