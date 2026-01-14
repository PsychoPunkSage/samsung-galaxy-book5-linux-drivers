#!/bin/bash
# Samsung Galaxy Book5 Pro - SOF Speaker Fix Installer

set -e

echo "=========================================="
echo "Samsung Galaxy Book5 Pro - SOF Speaker Fix"
echo "=========================================="

# Check root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Must run as root"
    echo "Try: sudo $0"
    exit 1
fi

# Install hda-verb
echo ""
echo "[1/5] Installing alsa-tools (hda-verb)..."
apt-get update -qq
apt-get install -y alsa-tools

# Verify installation
if ! which hda-verb > /dev/null; then
    echo "ERROR: hda-verb installation failed"
    exit 1
fi
echo "  Installed: $(which hda-verb)"

# Create Python script
echo ""
echo "[2/5] Installing Python fix script..."
cat > /usr/local/bin/sof-speaker-fix << 'EOFPY'
#!/usr/bin/env python3
import subprocess
import sys
import os

if os.geteuid() != 0:
    print("ERROR: Must run as root!")
    sys.exit(1)

print("Unmuting Node 0x17 (Speaker)...")
result = subprocess.run(
    ['hda-verb', '/dev/snd/hwC0D0', '0x17', '0x300', '0xb000'],
    capture_output=True, text=True
)

if result.returncode == 0:
    print("SUCCESS:", result.stdout.strip())
else:
    print("ERROR:", result.stderr.strip())
    sys.exit(1)
EOFPY

chmod +x /usr/local/bin/sof-speaker-fix
echo "  Installed: /usr/local/bin/sof-speaker-fix"

# Create systemd service
echo ""
echo "[3/5] Installing systemd service..."
cat > /etc/systemd/system/sof-speaker-unmute.service << 'EOFS'
[Unit]
Description=Samsung Galaxy Book5 Pro - SOF Speaker Unmute
After=sound.target alsa-restore.service
Before=pipewire.service wireplumber.service

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 2
ExecStart=/usr/bin/hda-verb /dev/snd/hwC0D0 0x17 0x300 0xb000
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOFS

systemctl daemon-reload
systemctl enable sof-speaker-unmute.service
echo "  Installed: /etc/systemd/system/sof-speaker-unmute.service"

# Apply fix now
echo ""
echo "[4/5] Applying fix..."
hda-verb /dev/snd/hwC0D0 0x17 0x300 0xb000

# Verify
echo ""
echo "[5/5] Verifying..."
if cat /proc/asound/card0/codec#0 | grep -A3 "Node 0x17" | grep "Amp-Out vals" | grep -q "0x80"; then
    echo "WARNING: Speaker may still be muted"
    echo "Check: cat /proc/asound/card0/codec#0 | grep -A3 'Node 0x17'"
else
    echo "SUCCESS: Speaker unmuted!"
fi

echo ""
echo "=========================================="
echo "Installation complete!"
echo "=========================================="
echo ""
echo "Test speakers:"
echo "  speaker-test -c2 -t wav -Dhw:0,0"
echo ""
echo "Manual fix (if needed):"
echo "  sudo sof-speaker-fix"
echo ""
echo "Service status:"
echo "  sudo systemctl status sof-speaker-unmute.service"
echo "=========================================="
