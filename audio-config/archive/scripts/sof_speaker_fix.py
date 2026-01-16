#!/usr/bin/env python3
"""
Samsung Galaxy Book5 Pro - SOF-compatible Speaker Unmute Tool

Uses hda-verb tool to unmute Node 0x17 via hwdep interface.
Works with SOF driver (init_verbs sysfs interface not available).
"""

import subprocess
import sys
import os

def check_hda_verb():
    """Check if hda-verb tool is installed."""
    result = subprocess.run(['which', 'hda-verb'],
                          capture_output=True, text=True)
    if result.returncode != 0:
        print("ERROR: hda-verb tool not found!")
        print("\nInstall with:")
        print("  sudo apt-get update")
        print("  sudo apt-get install -y alsa-tools")
        sys.exit(1)
    print(f"Found hda-verb: {result.stdout.strip()}")

def check_device():
    """Check if codec device exists."""
    device = "/dev/snd/hwC0D0"
    if not os.path.exists(device):
        print(f"ERROR: Codec device {device} not found!")
        print("Check audio driver is loaded:")
        print("  lsmod | grep snd_hda")
        sys.exit(1)
    print(f"Codec device: {device}")

def get_current_state():
    """Read current Node 0x17 state."""
    try:
        result = subprocess.run(
            ['cat', '/proc/asound/card0/codec#0'],
            capture_output=True, text=True, check=True
        )

        in_node_17 = False
        for line in result.stdout.split('\n'):
            if 'Node 0x17' in line:
                in_node_17 = True
            if in_node_17 and 'Amp-Out vals' in line:
                print(f"Current state: {line.strip()}")
                if '0x80' in line:
                    print("  Status: MUTED (0x80 = mute bit set)")
                    return False
                else:
                    print("  Status: UNMUTED")
                    return True
    except subprocess.CalledProcessError:
        print("Warning: Could not read codec state")
    return None

def unmute_speaker():
    """Send HDA verb to unmute Node 0x17."""
    print("\nSending unmute command...")

    # Node 0x17, verb 0x300 (SET_AMP_GAIN_MUTE), param 0xb000
    # 0xb000 = output amp, both channels, unmute, 0dB gain
    cmd = ['hda-verb', '/dev/snd/hwC0D0', '0x17', '0x300', '0xb000']

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        print(f"Result: {result.stdout.strip()}")
        return True
    except subprocess.CalledProcessError as e:
        print(f"ERROR: {e.stderr}")
        return False

def verify_fix():
    """Verify Node 0x17 is unmuted."""
    print("\nVerifying fix...")
    state = get_current_state()
    if state:
        print("SUCCESS: Speaker is unmuted!")
        return True
    else:
        print("WARNING: Speaker may still be muted")
        return False

def main():
    print("=" * 60)
    print("Samsung Galaxy Book5 Pro - SOF Speaker Unmute")
    print("=" * 60)

    if os.geteuid() != 0:
        print("ERROR: Must run as root!")
        print(f"Try: sudo {sys.argv[0]}")
        sys.exit(1)

    print("\n1. Checking prerequisites...")
    check_hda_verb()
    check_device()

    print("\n2. Reading current state...")
    get_current_state()

    print("\n3. Applying fix...")
    if not unmute_speaker():
        sys.exit(1)

    print("\n4. Verification...")
    verify_fix()

    print("\n" + "=" * 60)
    print("Test speakers with:")
    print("  speaker-test -c2 -t wav -Dhw:0,0")
    print("=" * 60)

if __name__ == '__main__':
    main()
