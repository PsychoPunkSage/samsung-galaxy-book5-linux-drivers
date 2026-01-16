# MAX98390 Smart Amplifier - Quick Start Guide

## TL;DR - What You Need to Do

Your Samsung Galaxy Book5 Pro has a MAX98390 I2C smart amplifier chip that is detected but not working. Before spending days on kernel development, we need to answer one critical question:

**Are the speakers actually wired to the MAX98390, or are they wired to the HDA codec with the MAX98390 being unused?**

This is common: OEMs often include amplifier chips in ACPI but don't actually use them on all SKUs.

---

## Step 1: Run Diagnostic (2 minutes)

This will check if the MAX98390 chips are actually responding on the I2C bus:

```bash
cd /home/psychopunk_sage/dev/drivers
sudo ./check-max98390.sh
```

**Expected outputs:**

### Scenario A: Amplifiers Responding
```
✓ Device found at 0x38 (left channel)
✓ Device found at 0x39 (right channel)
```
→ MAX98390 amplifiers are PRESENT and WORKING at hardware level
→ Need machine driver (complex fix)
→ Go to Step 3

### Scenario B: No Response
```
✗ No device at 0x38 (left channel)
✗ No device at 0x39 (right channel)
```
→ MAX98390 amplifiers NOT powered or not used
→ Speakers likely use HDA codec (simple fix)
→ Go to Step 2

---

## Step 2: Test HDA Codec GPIO (5 minutes)

If MAX98390 doesn't respond, test if speakers use the HDA codec with GPIO enable:

```bash
cd /home/psychopunk_sage/dev/drivers
sudo ./test-gpio-audio.sh
```

This will test all 8 GPIO pins on the Realtek ALC298 codec to find which one enables the amplifier.

**In a second terminal**, run audio:
```bash
speaker-test -c2 -Dhw:0,0
```

**If you hear sound**:
- The GPIO test will tell you which pin works
- I'll create a simple kernel patch (1 hour work)
- MAX98390 is unused on your model
- **PROBLEM SOLVED**

**If no sound from any GPIO**:
- Speakers definitely use MAX98390
- Go to Step 3

---

## Step 3: Verify MAX98390 Is Actually Needed (Windows Check)

If you have Windows installed (dual-boot), boot into Windows and check:

### Method A: Device Manager
1. Open Device Manager
2. Expand "Sound, video and game controllers"
3. Look for device names containing "MAX98390" or "Maxim"
4. If found → MAX98390 is used
5. If not found → MAX98390 might be unused

### Method B: PowerShell
```powershell
Get-PnpDevice | Where-Object {$_.FriendlyName -like "*MAX*"} | Format-List FriendlyName, InstanceId
Get-PnpDevice | Where-Object {$_.FriendlyName -like "*audio*"} | Format-List FriendlyName, InstanceId
```

Look for MAX98390 references.

---

## Step 4: Detailed I2C Analysis (If MAX98390 Confirmed)

If Steps 1-3 confirm MAX98390 is actually used, run detailed diagnostics:

```bash
# Check if i2c-tools installed
sudo apt install i2c-tools

# Detailed I2C scan
sudo i2cdetect -y 2

# Dump I2C device info
sudo i2cdump -y 2 0x38
sudo i2cdump -y 2 0x39
```

Save output and share it so we can determine:
- Exact chip configuration
- Register map
- Required initialization sequence

---

## Fix Paths Summary

### Path A: HDA GPIO Fix (SIMPLE - 90% success rate)
**Time**: 1 hour to create patch, 5 minutes to apply
**Complexity**: Low - just a quirk entry
**Risk**: Very low

**Steps**:
1. Run GPIO test
2. Identify working GPIO pin
3. Create patch for `sound/pci/hda/patch_realtek.c`
4. Compile and load
5. Done - speakers work

**Example patch**:
```c
static const struct hda_fixup alc298_fixup_tbl[] = {
    [ALC298_FIXUP_SAMSUNG_GALAXYBOOK5] = {
        .type = HDA_FIXUP_VERBS,
        .v.verbs = (const struct hda_verb[]) {
            { 0x01, AC_VERB_SET_GPIO_MASK, 0x04 },
            { 0x01, AC_VERB_SET_GPIO_DIRECTION, 0x04 },
            { 0x01, AC_VERB_SET_GPIO_DATA, 0x04 },
            { }
        },
    },
};
```

### Path B: MAX98390 Machine Driver (COMPLEX - 50% success rate)
**Time**: 2-4 days of development
**Complexity**: High - kernel driver development
**Risk**: Medium - may not work on first try

**Steps**:
1. Determine SSP interface (SSP0/1/2)
2. Create machine driver code (300 lines C)
3. Create or modify SOF topology file
4. Add ACPI match table
5. Compile kernel module
6. Test and debug
7. Iterate until working

**Required files**:
- `sound/soc/intel/boards/lnl_max98390_alc298.c` (new)
- `sound/soc/intel/common/soc-acpi-intel-lnl-match.c` (modify)
- `sof-lnl-max98390-alc298.tplg` (new or adapted)
- Kconfig and Makefile updates

**See**: `/home/psychopunk_sage/dev/drivers/MAX98390-ANALYSIS.md` for complete implementation

---

## Flowchart

```
START
  |
  ├─→ Run check-max98390.sh
  |     |
  |     ├─→ I2C devices respond (0x38, 0x39 found)
  |     |   |
  |     |   └─→ MAX98390 PRESENT → Need machine driver → Path B
  |     |
  |     └─→ No I2C response
  |         |
  |         └─→ Run test-gpio-audio.sh
  |             |
  |             ├─→ GPIO works → FIXED with HDA patch → Path A
  |             |
  |             └─→ No GPIO works
  |                 |
  |                 ├─→ Check Windows
  |                 |   |
  |                 |   ├─→ Windows uses MAX98390 → Need machine driver → Path B
  |                 |   |
  |                 |   └─→ Windows uses HDA only → MAX98390 unused, different issue
  |                 |
  |                 └─→ No Windows → Deep debug required
```

---

## Current Status

You have already:
- ✓ Analyzed HDA codec paths (all correct)
- ✓ Confirmed audio stream active
- ✓ Identified MAX98390 ACPI device
- ✓ Verified MAX98390 codec module exists
- ✓ Documented machine driver requirements

What's missing:
- ⚠ Whether MAX98390 actually responds on I2C
- ⚠ Whether speakers use HDA or MAX98390
- ⚠ Which SSP interface MAX98390 uses (if needed)

---

## Action Items - IN ORDER

### Right Now (5 minutes)
```bash
cd /home/psychopunk_sage/dev/drivers
sudo ./check-max98390.sh | tee max98390-diagnostic.log
```

Share the output.

### If I2C Scan Shows No Devices (5 minutes)
```bash
sudo ./test-gpio-audio.sh
```

Listen for audio. If you hear sound, we're 95% done.

### If Both Tests Fail (Optional)
Boot Windows and check Device Manager for MAX98390 usage.

### After We Know Which Path
- **Path A**: I'll create HDA patch (1 hour)
- **Path B**: We'll build machine driver (2-3 days)

---

## Files You Have

### Documentation
- `/home/psychopunk_sage/dev/drivers/MAX98390-ANALYSIS.md` - Complete technical analysis
- `/home/psychopunk_sage/dev/drivers/MAX98390-QUICK-START.md` - This file
- `/home/psychopunk_sage/dev/drivers/AUDIO-ROOT-CAUSE-FOUND.md` - HDA codec analysis
- `/home/psychopunk_sage/dev/drivers/AUDIO-NEXT-STEPS.md` - HDA GPIO testing

### Scripts
- `/home/psychopunk_sage/dev/drivers/check-max98390.sh` - MAX98390 I2C diagnostic
- `/home/psychopunk_sage/dev/drivers/test-gpio-audio.sh` - HDA GPIO tester
- `/home/psychopunk_sage/dev/drivers/audio-full-debug.sh` - Complete system diagnostic

### Code (if needed for Path B)
- Machine driver implementation in `MAX98390-ANALYSIS.md`
- Compilation instructions included
- ACPI match tables provided

---

## Quick Reference

### Check I2C Devices
```bash
sudo i2cdetect -y 2
```
Should show devices at 0x38 and 0x39 if MAX98390 active.

### Load MAX98390 Module
```bash
sudo modprobe snd_soc_max98390
dmesg | grep -i max98390
```

### Check Current Machine Driver
```bash
lsmod | grep snd_soc.*hda_dsp
# Currently shows: snd_soc_skl_hda_dsp (generic, no MAX98390 support)
```

### Check Sound Card
```bash
cat /proc/asound/cards
aplay -l
```

### Test Audio
```bash
speaker-test -c2 -Dhw:0,0
paplay /usr/share/sounds/alsa/Front_Center.wav
```

---

## What to Share

After running `check-max98390.sh`, share:

1. **I2C scan output**:
   ```
   Did devices appear at 0x38 and 0x39? YES/NO
   ```

2. **GPIO test results** (if I2C failed):
   ```
   Did any GPIO enable speakers? Which one?
   ```

3. **Windows check** (if available):
   ```
   Does Device Manager show MAX98390? YES/NO
   ```

Based on these answers, I'll provide:
- **Simple HDA patch** (if GPIO works), OR
- **Complete machine driver** (if MAX98390 confirmed), OR
- **Alternative diagnosis** (if neither works)

---

## Expected Timeline

### Scenario A: HDA GPIO Fix
- Diagnosis: 5 minutes
- Patch creation: 30 minutes
- Testing: 10 minutes
- **Total: ~1 hour to working speakers**

### Scenario B: MAX98390 Machine Driver
- Diagnosis: 10 minutes
- Information gathering: 2-4 hours
- Driver development: 8-16 hours
- Testing and debugging: 4-8 hours
- **Total: 2-4 days to working speakers**

### Scenario C: Unknown Issue
- Extended debugging: Variable
- May require hardware documentation
- Community support may be needed

---

## Need Help?

If scripts fail or output is unclear:

1. Save complete output:
```bash
cd /home/psychopunk_sage/dev/drivers
sudo ./check-max98390.sh > max98390.log 2>&1
sudo ./test-gpio-audio.sh > gpio-test.log 2>&1
```

2. Share logs with these details:
   - Did you hear audio during GPIO test?
   - Any error messages?
   - Windows behavior (if dual-boot)?

3. I'll provide next steps based on results

---

**BOTTOM LINE**: Run `check-max98390.sh` first, then `test-gpio-audio.sh`. One of these will point us to the correct fix path.
