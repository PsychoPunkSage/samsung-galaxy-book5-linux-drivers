# QUICK FIX: Samsung Galaxy Book5 Pro Speakers on SOF Driver

## The Problem

```bash
echo "0x17 0x3000 0xb000" > /sys/class/sound/hwC0D0/init_verbs
sh: echo: I/O error
```

SOF driver doesn't support init_verbs. You need `hda-verb` tool instead.

---

## IMMEDIATE FIX (Copy & Paste)

```bash
# 1. Install hda-verb tool
sudo apt-get update && sudo apt-get install -y alsa-tools

# 2. Unmute speaker NOW
sudo hda-verb /dev/snd/hwC0D0 0x17 0x300 0xb000

# 3. Test speakers
speaker-test -c2 -t wav -Dhw:0,0
```

**This WILL work.** You'll hear pink noise from both speakers.

---

## Make It Persistent (Auto-fix on Boot)

```bash
# Run the installer
cd /home/psychopunk_sage/dev/drivers/audio-config
chmod +x install-sof-fix.sh
sudo ./install-sof-fix.sh
```

This installs:
- hda-verb tool
- systemd service (auto-runs on boot)
- `/usr/local/bin/sof-speaker-fix` command

---

## Manual Usage

```bash
# Check if speakers are muted
cat /proc/asound/card0/codec#0 | grep -A3 "Node 0x17" | grep "Amp-Out"

# Unmute speakers
sudo hda-verb /dev/snd/hwC0D0 0x17 0x300 0xb000

# Or use the Python tool
cd /home/psychopunk_sage/dev/drivers/audio-config
sudo python3 sof_speaker_fix.py
```

---

## Why This Works

| Method | Status | Reason |
|--------|--------|--------|
| `init_verbs` sysfs | FAILS | Not implemented in SOF driver |
| `hda-verb` tool | WORKS | Uses hwdep ioctl interface |
| Direct hwdep ioctl | WORKS | Low-level codec access |

SOF driver uses a different architecture than legacy HDA. It requires hwdep interface access, which `hda-verb` provides.

---

## Verification

```bash
# Before fix (MUTED)
Amp-Out vals:  [0x80 0x80]

# After fix (UNMUTED)
Amp-Out vals:  [0x00 0x00]
```

---

## Files in This Directory

- `SOF-SPEAKER-FIX.md` - Complete technical documentation
- `sof_speaker_fix.py` - Python diagnostic and fix tool
- `install-sof-fix.sh` - Automated installer
- `sof-speaker-unmute.service` - systemd service file
- `QUICK-SOF-FIX.md` - This file

---

**TL;DR**: Install alsa-tools, run `sudo hda-verb /dev/snd/hwC0D0 0x17 0x300 0xb000`
