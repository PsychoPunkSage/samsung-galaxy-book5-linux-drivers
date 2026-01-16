#!/usr/bin/env python3
"""
Samsung Galaxy Book5 Pro - HDA Codec Speaker Unmute Tool

This tool directly manipulates the Realtek ALC298 HDA codec registers
to unmute the audio mixer path to the physical speakers.

Usage:
    sudo python3 speaker_codec_fix.py [--verify-only]
"""

import sys
import os
import re
import time
import argparse
from pathlib import Path


class HDCodecController:
    """Interface to HDA codec via sysfs"""

    CODEC_PATH = Path("/sys/class/sound/hwC0D0")
    PROC_CODEC = Path("/proc/asound/card0/codec#0")

    def __init__(self):
        if not self.CODEC_PATH.exists():
            raise RuntimeError(f"Codec sysfs path not found: {self.CODEC_PATH}")
        if not self.PROC_CODEC.exists():
            raise RuntimeError(f"Codec proc interface not found: {self.PROC_CODEC}")

    def get_codec_info(self):
        """Read codec identification"""
        vendor = (self.CODEC_PATH / "vendor_name").read_text().strip()
        chip = (self.CODEC_PATH / "chip_name").read_text().strip()
        subsys = (self.CODEC_PATH / "subsystem_id").read_text().strip()
        return {
            'vendor': vendor,
            'chip': chip,
            'subsystem_id': subsys
        }

    def get_node_state(self, node_id):
        """
        Parse node state from /proc/asound/card0/codec#0

        Returns dict with node properties
        """
        content = self.PROC_CODEC.read_text()

        # Find the node section
        pattern = rf"Node (0x{node_id:02x}).*?\n(.*?)(?=\nNode|\Z)"
        match = re.search(pattern, content, re.DOTALL | re.IGNORECASE)

        if not match:
            return None

        node_text = match.group(2)

        # Extract Amp-In values
        amp_in_match = re.search(r"Amp-In vals:\s+\[([^\]]+)\]", node_text)
        amp_in_vals = amp_in_match.group(1) if amp_in_match else None

        # Extract Connection list
        conn_match = re.search(r"Connection:.*?\n\s+(.+)", node_text)
        connections = conn_match.group(1).strip() if conn_match else None

        return {
            'node_id': node_id,
            'amp_in_vals': amp_in_vals,
            'connections': connections,
            'raw': node_text
        }

    def write_hda_verb(self, node, verb, param):
        """
        Write HDA verb to codec via sysfs

        Args:
            node: Node ID (e.g., 0x0d)
            verb: Verb ID (e.g., 0x7000)
            param: Parameter value (e.g., 0xb000)
        """
        verb_str = f"0x{node:02x} 0x{verb:04x} 0x{param:04x}"
        verb_file = self.CODEC_PATH / "init_verbs"

        print(f"  Writing HDA verb: {verb_str}")

        try:
            verb_file.write_text(verb_str + "\n")
            return True
        except PermissionError:
            print(f"ERROR: Permission denied. Run with sudo.")
            return False
        except Exception as e:
            print(f"ERROR: Failed to write verb: {e}")
            return False

    def reconfigure_codec(self):
        """Trigger codec reconfiguration to apply verbs"""
        reconfig_file = self.CODEC_PATH / "reconfig"
        print("  Triggering codec reconfiguration...")

        try:
            reconfig_file.write_text("1\n")
            return True
        except Exception as e:
            print(f"ERROR: Failed to reconfigure codec: {e}")
            return False

    def check_mixer_node_muted(self, node_id=0x0d):
        """
        Check if mixer node input is muted

        Returns: (is_muted, amp_values)
        """
        node = self.get_node_state(node_id)
        if not node or not node['amp_in_vals']:
            return (None, None)

        amp_vals = node['amp_in_vals']

        # Parse hex values from string like "0x00 0x00" or "0x80 0x80"
        vals = [int(v, 16) for v in re.findall(r'0x[0-9a-fA-F]+', amp_vals)]

        if not vals:
            return (None, amp_vals)

        # Check if mute bit (bit 7) is set
        is_muted = any((v & 0x80) != 0 for v in vals)

        return (is_muted, vals)


def verify_codec_state(codec):
    """Print current codec state"""
    print("\n=== Current Codec State ===\n")

    info = codec.get_codec_info()
    print(f"Codec: {info['chip']} (Vendor: {info['vendor']})")
    print(f"Subsystem ID: {info['subsystem_id']}")
    print()

    # Check mixer node 0x0d
    node_0d = codec.get_node_state(0x0d)
    if node_0d:
        print("Node 0x0d (Audio Mixer to Speaker):")
        print(f"  Amp-In vals: {node_0d['amp_in_vals']}")
        print(f"  Connections: {node_0d['connections']}")

        is_muted, vals = codec.check_mixer_node_muted(0x0d)
        if is_muted is not None:
            status = "MUTED" if is_muted else "UNMUTED"
            print(f"  Status: {status}")
            if is_muted:
                print("  ^ THIS IS THE PROBLEM!")
    else:
        print("ERROR: Could not read node 0x0d state")

    print()

    # Check speaker pin 0x17
    node_17 = codec.get_node_state(0x17)
    if node_17:
        print("Node 0x17 (Speaker Pin):")
        eapd_match = re.search(r"EAPD\s+(0x[0-9a-fA-F]+)", node_17['raw'])
        pin_match = re.search(r"Pin-ctls:\s+(0x[0-9a-fA-F]+):\s+(.+)", node_17['raw'])

        if eapd_match:
            print(f"  EAPD: {eapd_match.group(1)} (Amplifier powered)")
        if pin_match:
            print(f"  Pin-ctls: {pin_match.group(1)} ({pin_match.group(2)})")

    print()


def unmute_speaker_mixer(codec):
    """
    Unmute the mixer node 0x0d that routes to speakers

    HDA Verb: SET_AMP_GAIN_MUTE
      - Node 0x0d: Audio Mixer
      - Verb 0x7000: Set input amp 0, left channel
      - Verb 0x7001: Set input amp 0, right channel
      - Param 0xb000: Both channels, unmute, 0dB gain
                      (bit 13=both channels, bit 7=0 for unmute)
    """
    print("\n=== Applying Fix ===\n")

    # Write verbs to unmute both channels
    if not codec.write_hda_verb(0x0d, 0x7000, 0xb000):
        return False

    if not codec.write_hda_verb(0x0d, 0x7001, 0xb000):
        return False

    # Reconfigure codec to apply changes
    if not codec.reconfigure_codec():
        return False

    print("  Waiting for codec to reinitialize...")
    time.sleep(2)

    return True


def main():
    parser = argparse.ArgumentParser(
        description="Samsung Galaxy Book5 Pro - Fix speaker audio by unmuting HDA codec mixer"
    )
    parser.add_argument(
        '--verify-only',
        action='store_true',
        help='Only check codec state, do not apply fix'
    )
    parser.add_argument(
        '--force',
        action='store_true',
        help='Apply fix even if mixer appears unmuted'
    )

    args = parser.parse_args()

    print("=" * 60)
    print("Samsung Galaxy Book5 Pro - Speaker Codec Fix")
    print("=" * 60)

    # Check root privileges
    if os.geteuid() != 0 and not args.verify_only:
        print("\nERROR: This script must be run as root (use sudo)")
        print("       Or use --verify-only to just check state")
        sys.exit(1)

    try:
        codec = HDCodecController()
    except RuntimeError as e:
        print(f"\nERROR: {e}")
        sys.exit(1)

    # Show current state
    verify_codec_state(codec)

    if args.verify_only:
        print("Verification complete. Use without --verify-only to apply fix.")
        return 0

    # Check if fix is needed
    is_muted, _ = codec.check_mixer_node_muted(0x0d)

    if is_muted is None:
        print("WARNING: Could not determine mute state")
        if not args.force:
            print("Use --force to apply fix anyway")
            sys.exit(1)
    elif not is_muted and not args.force:
        print("Mixer node 0x0d is already unmuted.")
        print("If speakers still don't work, the issue may be elsewhere.")
        print("Use --force to apply fix anyway.")
        return 0

    # Apply fix
    if not unmute_speaker_mixer(codec):
        print("\nERROR: Failed to apply fix")
        sys.exit(1)

    # Verify fix
    print("\n=== Verification ===\n")
    is_muted_after, vals_after = codec.check_mixer_node_muted(0x0d)

    if is_muted_after is False:
        print("SUCCESS! Mixer node 0x0d is now unmuted")
        print(f"  Amp-In values: {[hex(v) for v in vals_after]}")
    else:
        print("WARNING: Fix applied but mixer still appears muted")
        print("  This may indicate a different issue")

    print("\n=== Test Audio ===\n")
    print("Test speakers with:")
    print("  speaker-test -c2 -t wav -Dhw:0,0")
    print("\nOr play a sound file:")
    print("  aplay -Dhw:0,0 /usr/share/sounds/alsa/Front_Center.wav")
    print()

    return 0


if __name__ == '__main__':
    sys.exit(main())
