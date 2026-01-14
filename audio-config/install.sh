#!/bin/bash
# Installation script for Samsung Galaxy Book5 Pro UCM2 audio configuration

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UCM2_DIR="/usr/share/alsa/ucm2"
TARGET_DIR="${UCM2_DIR}/conf.d/sof-hda-dsp"

echo "=== Samsung Galaxy Book5 Pro Audio Configuration Installer ==="
echo

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root (use sudo)"
   exit 1
fi

# Verify source files exist
if [[ ! -f "${SCRIPT_DIR}/ucm2/conf.d/sof-hda-dsp/Samsung-940XHA.conf" ]]; then
    echo "ERROR: Source files not found in ${SCRIPT_DIR}/ucm2/"
    exit 1
fi

echo "[1/5] Creating UCM2 directory structure..."
mkdir -p "${TARGET_DIR}"

echo "[2/5] Installing Samsung-940XHA.conf..."
cp -v "${SCRIPT_DIR}/ucm2/conf.d/sof-hda-dsp/Samsung-940XHA.conf" "${TARGET_DIR}/"

echo "[3/5] Installing HiFi-Samsung-940XHA.conf..."
cp -v "${SCRIPT_DIR}/ucm2/conf.d/sof-hda-dsp/HiFi-Samsung-940XHA.conf" "${TARGET_DIR}/"

echo "[4/5] Setting correct permissions..."
chmod 644 "${TARGET_DIR}/Samsung-940XHA.conf"
chmod 644 "${TARGET_DIR}/HiFi-Samsung-940XHA.conf"

echo "[5/7] Installing speaker codec fix script..."
cp -v "${SCRIPT_DIR}/fix-speaker-unmute.sh" /usr/local/bin/
chmod 755 /usr/local/bin/fix-speaker-unmute.sh

echo "[6/7] Installing speaker codec fix service..."
cp -v "${SCRIPT_DIR}/speaker-unmute.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable speaker-unmute.service

echo "[7/7] Restarting audio services..."
# Restart PipeWire for all users
for user in $(loginctl list-users --no-legend | awk '{print $2}'); do
    sudo -u "$user" XDG_RUNTIME_DIR=/run/user/$(id -u "$user") \
        systemctl --user restart pipewire pipewire-pulse wireplumber 2>/dev/null || true
done

# Start speaker fix service
systemctl start speaker-unmute.service

echo
echo "=== Installation Complete ==="
echo
echo "Speaker codec fix has been installed and enabled."
echo "The fix will run automatically on every boot."
echo
echo "Verification commands:"
echo "  alsaucm -c sof-hda-dsp listcards"
echo "  speaker-test -c 2 -t wav"
echo "  alsamixer -c 0"
echo "  systemctl status speaker-unmute.service"
echo
echo "Note: You may need to log out/in for changes to take full effect."
echo
