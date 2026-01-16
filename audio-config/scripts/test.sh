LOG="/home/psychopunk_sage/dev/drivers/audio-config/INVESTIGATION-LOG.md"

echo "" >>"$LOG"
echo "### Quirk NOT Applied - Investigating" >>"$LOG"
echo '```' >>"$LOG"

# Check what models are available in the kernel
echo "=== Available ALC298 models in kernel ===" | tee -a "$LOG"
modinfo snd_hda_codec_realtek 2>/dev/null | grep -i "parm:" | tee -a "$LOG"

echo "" | tee -a "$LOG"
echo "=== Searching kernel source for samsung-amp models ===" | tee -a "$LOG"
grep -r "samsung-amp" /lib/modules/$(uname -r)/build/sound/pci/hda/ 2>/dev/null | head -10 | tee -a "$LOG"

# Alternative: check if the quirk table has our subsystem ID
echo "" | tee -a "$LOG"
echo "=== Checking if subsystem 0x144dca08 is in quirk table ===" | tee -a "$LOG"
strings /lib/modules/$(uname -r)/kernel/sound/pci/hda/snd-hda-codec-realtek.ko* 2>/dev/null | grep -i "144d" | tee -a "$LOG"

# Check kernel version
echo "" | tee -a "$LOG"
echo "=== Kernel version ===" | tee -a "$LOG"
uname -r | tee -a "$LOG"

echo '```' >>"$LOG"
