#!/usr/bin/env python3
"""
Samsung Galaxy Book5 Pro - Complete Speaker Fix
Addresses BOTH mixer and pin amplifier muting issues

Root cause: Node 0x17 (Speaker Pin) output amplifier is MUTED
even though ALSA control "Speaker Playback Switch" reports "on"

Usage:
    sudo python3 speaker_pin_fix.py [--verify-only]
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
        pattern = rf"Node (0x{node_id:02x}).*?\n(.*?)(?=\nNode|\Z)"
        match = re.search(pattern, content, re.DOTALL | re.IGNORECASE)

        if not match:
            return None

        node_text = match.group(2)

        # Extract Amp-In values
        amp_in_match = re.search(r"Amp-In vals:\s+\[([^\]]+)\]", node_text)
        amp_in_vals = amp_in_match.group(1) if amp_in_match else None

        # Extract Amp-Out values
        amp_out_match = re.search(r"Amp-Out vals:\s+\[([^\]]+)\]", node_text)
        amp_out_vals = amp_out_match.group(1) if amp_out_match else None

        # Extract Connection list
        conn_match = re.search(r"Connection:.*?\n\s+(.+)", node_text)
        connections = conn_match.group(1).strip() if conn_match else None

        # Extract EAPD
        eapd_match = re.search(r"EAPD\s+(0x[0-9a-fA-F]+)", node_text)
        eapd = eapd_match.group(1) if eapd_match else None

        # Extract Pin-ctls
        pin_match = re.search(r"Pin-ctls:\s+(0x[0-9a-fA-F]+):\s+(.+)", node_text)
        pin_ctls = pin_match.group(1) if pin_match else None
        pin_ctls_desc = pin_match.group(2) if pin_match else None

        return {
            'node_id': node_id,
            'amp_in_vals': amp_in_vals,
            'amp_out_vals': amp_out_vals,
            'connections': connections,
            'eapd': eapd,
            'pin_ctls': pin_ctls,
            'pin_ctls_desc': pin_ctls_desc,
            'raw': node_text
        }

    def write_hda_verb(self, node, verb, param):
        """
        Write HDA verb to codec via sysfs
        Args:
            node: Node ID (e.g., 0x17)
            verb: Verb ID (e.g., 0x300)
            param: Parameter value (e.g., 0x0000)
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

    def check_amp_muted(self, amp_vals_str):
        """
        Check if amplifier is muted based on amp values string
        Args:
            amp_vals_str: String like "0x80 0x80" or "0x00 0x00"
        Returns: (is_muted, values_list)
        """
        if not amp_vals_str:
            return (None, None)

        vals = [int(v, 16) for v in re.findall(r'0x[0-9a-fA-F]+', amp_vals_str)]
        if not vals:
            return (None, amp_vals_str)

        # Mute bit is bit 7 (0x80)
        is_muted = any((v & 0x80) != 0 for v in vals)
        return (is_muted, vals)


def verify_codec_state(codec):
    """Print current codec state with detailed diagnostics"""
    print("\n=== DIAGNOSTIC REPORT ===\n")

    info = codec.get_codec_info()
    print(f"Codec: {info['chip']} (Vendor: {info['vendor']})")
    print(f"Subsystem ID: {info['subsystem_id']}")
    print()

    issues_found = []

    # Check mixer node 0x0d
    print("Node 0x0d (Audio Mixer):")
    node_0d = codec.get_node_state(0x0d)
    if node_0d and node_0d['amp_in_vals']:
        print(f"  Amp-In vals: {node_0d['amp_in_vals']}")
        print(f"  Connections: {node_0d['connections']}")

        is_muted, vals = codec.check_amp_muted(node_0d['amp_in_vals'])
        if is_muted is not None:
            status = "MUTED ❌" if is_muted else "UNMUTED ✓"
            print(f"  Status: {status}")
            if is_muted:
                issues_found.append("Node 0x0d (Mixer) input is MUTED")
    else:
        print("  ERROR: Could not read node state")
    print()

    # Check speaker pin 0x17 - THIS IS THE CRITICAL ONE
    print("Node 0x17 (Speaker Pin Complex):")
    node_17 = codec.get_node_state(0x17)
    if node_17:
        if node_17['amp_out_vals']:
            print(f"  Amp-Out vals: {node_17['amp_out_vals']}")
            is_muted, vals = codec.check_amp_muted(node_17['amp_out_vals'])
            if is_muted is not None:
                status = "MUTED ❌" if is_muted else "UNMUTED ✓"
                print(f"  Status: {status}")
                if is_muted:
                    issues_found.append("Node 0x17 (Speaker Pin) output amp is MUTED - THIS IS THE PROBLEM!")

        if node_17['eapd']:
            eapd_val = int(node_17['eapd'], 16)
            eapd_status = "ON ✓" if (eapd_val & 0x2) else "OFF ❌"
            print(f"  EAPD: {node_17['eapd']} ({eapd_status})")
            if not (eapd_val & 0x2):
                issues_found.append("Speaker amplifier EAPD is OFF")

        if node_17['pin_ctls']:
            print(f"  Pin-ctls: {node_17['pin_ctls']} ({node_17['pin_ctls_desc']})")
            pin_val = int(node_17['pin_ctls'], 16)
            if not (pin_val & 0x40):
                issues_found.append("Speaker pin output is not enabled")

        if node_17['connections']:
            print(f"  Connections: {node_17['connections']}")
    else:
        print("  ERROR: Could not read node state")
    print()

    # Check DAC node 0x03
    print("Node 0x03 (DAC / Audio Output):")
    node_03 = codec.get_node_state(0x03)
    if node_03:
        conv_match = re.search(r"Converter:\s+stream=(\d+)", node_03['raw'])
        if conv_match:
            stream = int(conv_match.group(1))
            stream_status = "ACTIVE ✓" if stream != 0 else "INACTIVE ❌"
            print(f"  Stream: {stream} ({stream_status})")
            if stream == 0:
                issues_found.append("DAC has no active audio stream")

        if node_03['amp_out_vals']:
            print(f"  Amp-Out vals: {node_03['amp_out_vals']}")
    print()

    # Summary
    print("=" * 60)
    if issues_found:
        print("\n⚠️  ISSUES DETECTED:\n")
        for i, issue in enumerate(issues_found, 1):
            print(f"  {i}. {issue}")
        print()
    else:
        print("\n✓ No issues detected in codec state")
        print("  If speakers still don't work, issue may be in:")
        print("    - SOF firmware topology")
        print("    - PipeWire routing")
        print("    - Hardware (physical speaker connection)")
        print()

    return issues_found


def unmute_speaker_pin(codec):
    """
    Unmute BOTH mixer and speaker pin output amplifiers

    Critical fix: Node 0x17 output amp is muted even though
    ALSA control shows "Speaker Playback Switch = on"

    HDA Verbs:
      1. Node 0x0d: Unmute mixer input (from DAC 0x03)
      2. Node 0x17: Unmute speaker pin output amplifier
      3. Node 0x17: Set EAPD to enable speaker amplifier
    """
    print("\n=== APPLYING COMPLETE SPEAKER FIX ===\n")

    # Step 1: Unmute mixer node 0x0d (DAC → Mixer path)
    print("Step 1: Unmuting mixer node 0x0d...")
    if not codec.write_hda_verb(0x0d, 0x7000, 0xb000):  # Both channels
        return False

    # Step 2: Unmute speaker pin 0x17 OUTPUT amplifier (CRITICAL!)
    # SET_AMP_GAIN_MUTE for output amp:
    #   - 0x300: Output amp control
    #   - 0x0000: Both channels unmuted, 0dB gain
    #   But we need to use the proper format: 0xb000 = both channels unmuted
    print("Step 2: Unmuting speaker pin 0x17 output amplifier...")
    # Verb 0x300 = SET_AMP_GAIN_MUTE for output
    # Parameter: bit 15 (output), bit 13-12 (both channels), bit 7=0 (unmute)
    if not codec.write_hda_verb(0x17, 0x3000, 0xb000):  # Output amp, both channels
        return False

    # Step 3: Ensure EAPD is enabled on speaker pin
    print("Step 3: Enabling speaker amplifier (EAPD)...")
    # SET_EAPD_BTLENABLE verb: 0x70c
    # Parameter: 0x0002 (EAPD bit set)
    if not codec.write_hda_verb(0x17, 0x70c, 0x0002):
        return False

    # Step 4: Ensure pin is configured for output
    print("Step 4: Setting speaker pin to output mode...")
    # SET_PIN_WIDGET_CONTROL verb: 0x707
    # Parameter: 0x40 (output enabled)
    if not codec.write_hda_verb(0x17, 0x707, 0x0040):
        return False

    # Reconfigure codec to apply all changes
    if not codec.reconfigure_codec():
        return False

    print("  Waiting for codec to reinitialize...")
    time.sleep(3)

    return True


def main():
    parser = argparse.ArgumentParser(
        description="Samsung Galaxy Book5 Pro - Complete speaker fix (mixer + pin amp)"
    )
    parser.add_argument(
        '--verify-only',
        action='store_true',
        help='Only check codec state, do not apply fix'
    )
    parser.add_argument(
        '--force',
        action='store_true',
        help='Apply fix even if no issues detected'
    )

    args = parser.parse_args()

    print("=" * 70)
    print("  Samsung Galaxy Book5 Pro - Complete Speaker Fix")
    print("  Addresses BOTH mixer and pin amplifier issues")
    print("=" * 70)

    # Check root privileges
    if os.geteuid() != 0 and not args.verify_only:
        print("\n❌ ERROR: This script must be run as root (use sudo)")
        print("       Or use --verify-only to just check state")
        sys.exit(1)

    try:
        codec = HDCodecController()
    except RuntimeError as e:
        print(f"\n❌ ERROR: {e}")
        sys.exit(1)

    # Show current state
    issues = verify_codec_state(codec)

    if args.verify_only:
        print("\nDiagnostic complete. Use without --verify-only to apply fix.")
        return 0 if not issues else 1

    # Decide if fix is needed
    if not issues and not args.force:
        print("No issues detected. Use --force to apply fix anyway.")
        return 0

    # Apply comprehensive fix
    if not unmute_speaker_pin(codec):
        print("\n❌ ERROR: Failed to apply fix")
        sys.exit(1)

    # Verify fix
    print("\n=== POST-FIX VERIFICATION ===\n")
    issues_after = verify_codec_state(codec)

    if not issues_after:
        print("\n✅ SUCCESS! All speaker paths are now properly configured\n")
    else:
        print("\n⚠️  WARNING: Some issues remain after fix:")
        for issue in issues_after:
            print(f"    - {issue}")
        print()

    print("=" * 70)
    print("\n🔊 TEST AUDIO NOW:\n")
    print("  Option 1: speaker-test -c2 -t wav -Dhw:0,0")
    print("  Option 2: aplay -Dhw:0,0 /usr/share/sounds/alsa/Front_Center.wav")
    print("  Option 3: pw-play /usr/share/sounds/alsa/Front_Center.wav")
    print("\n  Press Ctrl+C to stop speaker-test when you hear sound.")
    print("=" * 70)
    print()

    return 0


if __name__ == '__main__':
    sys.exit(main())
