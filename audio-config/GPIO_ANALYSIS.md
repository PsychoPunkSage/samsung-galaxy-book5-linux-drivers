# MAX98390 GPIO Power Enable - Technical Analysis

## Root Cause

The MAX98390 audio amplifiers are **not powered on** because their GPIO enable line has not been asserted by the kernel.

### Evidence
1. **I2C scan shows nothing**: `i2cdetect -y 2` reports `--` at addresses 0x38 and 0x39
2. **ACPI declares GPIO**: ACPI tables show `GpioIo` resource with pin 0x62 (98 decimal)
3. **No kernel driver handling**: No driver is currently managing this GPIO power line

### Why This Happens

On Windows, the audio driver or ACPI BIOS automatically enables this GPIO during boot. On Linux:
- The kernel sees the ACPI declaration but doesn't automatically enable it
- The SOF audio driver doesn't know to enable the GPIO
- The MAX98390 codec driver probes fail or don't enable power
- Result: Amplifiers stay in low-power state and don't respond on I2C

## GPIO Number Calculation

### Intel Platform GPIO Architecture

Intel Meteor Lake / Arrow Lake uses the **pinctrl-meteorlake** or **pinctrl-arrowlake** driver.

GPIOs are organized in **communities** with **groups**:
```
Community 0: GPP_A, GPP_B, GPP_C  (Platform Control)
Community 1: GPP_D, GPP_E, GPP_F  (Audio, I2C, Display)
Community 2: GPP_H, GPP_I, GPP_J  (PCIe, USB)
Community 3: GPP_K, GPP_L         (Misc)
```

Each community gets a **gpiochip** with a **base** number.

### From ACPI to Linux GPIO Number

**ACPI declares**: `GpioIo (...) { 0x62 }`

This means:
- **Relative pin 0x62 (98)** within a specific GPIO controller
- The controller is referenced by ACPI path (e.g., `\_SB.GPI0` or `\_SB.PCI0.GPI0`)

**Linux mapping**:
```
Linux GPIO Number = gpiochip_base + acpi_relative_pin
```

### Your System's GPIO Controllers

From your diagnostic output:
```
gpiochip512: base=512, ngpio=48   (Controller 0)
gpiochip560: base=560, ngpio=65   (Controller 1)
gpiochip625: base=625, ngpio=66   (Controller 2)
gpiochip691: base=691, ngpio=8    (Controller 3)
gpiochip699: base=699, ngpio=?    (Controller 4)
```

### Candidate Calculations

| Method | Base | Pin | Linux GPIO | Likelihood |
|--------|------|-----|------------|------------|
| Direct offset | 512 | 98 | **610** | High - if pin is in GPP_B/GPP_C group |
| Direct offset | 560 | 98 | **658** | High - if pin is in GPP_D (Audio) group |
| Direct offset | 625 | 98 | **723** | Medium - if pin is in GPP_H group |
| Absolute | - | 98 | **98** | Low - unlikely to be this low |

**Most likely: GPIO 610 or 658**

Why 658 is promising:
- GPP_D group typically handles I2C and Audio peripherals
- Base 560 + 98 = 658
- Fits within the 65-pin range (560-624)

## Solution Approaches

### 1. Userspace GPIO Control (Quick Test)

**Pros**:
- Fast to test
- No kernel compilation
- Can be scripted for boot

**Cons**:
- May fail if GPIO is ACPI-locked
- Not proper kernel integration
- Requires root permissions

**Method**:
```bash
sudo /home/psychopunk_sage/dev/drivers/audio-config/quick_gpio_test.sh
```

This script will:
1. Try GPIO 610, 658, 723 in order
2. Export each GPIO via sysfs
3. Set direction to output
4. Set value to HIGH
5. Scan I2C bus for device response
6. Report success if device found

### 2. Kernel Module (Proper Driver)

**Pros**:
- Proper kernel integration
- Can handle ACPI-locked GPIOs
- Automatic power management
- Proper probe ordering

**Cons**:
- Requires kernel headers
- Need to compile
- More complex to debug

**Method**:
```bash
cd /home/psychopunk_sage/dev/drivers/audio-config
make -f Makefile.gpio
sudo make -f Makefile.gpio load
```

The module (`max98390_gpio_enable.c`) will:
1. Bind to MAX98390 ACPI device
2. Request GPIO from ACPI resources using `devm_gpiod_get_index()`
3. Set GPIO HIGH to enable power
4. Handle suspend/resume if needed

### 3. Upstream Integration (Long-term)

The proper fix is to modify the existing MAX98390 codec driver:

**File**: `sound/soc/codecs/max98390.c`

**Changes needed**:
```c
static int max98390_i2c_probe(struct i2c_client *i2c)
{
    struct max98390_priv *max98390;
    struct gpio_desc *enable_gpio;

    /* Enable power GPIO if present in ACPI */
    enable_gpio = devm_gpiod_get_optional(&i2c->dev, "enable",
                                          GPIOD_OUT_HIGH);
    if (IS_ERR(enable_gpio))
        return dev_err_probe(&i2c->dev, PTR_ERR(enable_gpio),
                           "Failed to get enable GPIO\n");

    /* Wait for power stabilization */
    if (enable_gpio)
        msleep(10);

    /* Continue with existing probe code */
    ...
}
```

This way, the GPIO is managed by the codec driver itself.

## Testing Procedure

### Step 1: Quick Test (2 minutes)

```bash
cd /home/psychopunk_sage/dev/drivers/audio-config
sudo ./quick_gpio_test.sh
```

Expected output if successful:
```
Testing GPIO 658...
  ✓ Exported
  ✓ Direction set to output
  Current value: 0
  ✓ Set to HIGH
  Checking I2C bus 2...

╔════════════════════════════════════════╗
║          SUCCESS!!!                    ║
║  MAX98390 detected on I2C bus 2        ║
║  Working GPIO: 658                     ║
╚════════════════════════════════════════╝

Full I2C scan:
     0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
00:          -- -- -- -- -- -- -- -- -- -- -- -- --
10: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
20: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
30: -- -- -- -- -- -- -- -- 38 39 -- -- -- -- -- --
```

### Step 2: Verify Device Communication

Once I2C responds, read the device ID:

```bash
# Read MAX98390 device ID (register 0x21FF)
# The device uses 16-bit register addressing
i2cget -y 2 0x38 0x21 w
i2cget -y 2 0x39 0x21 w

# Expected response: 0x9000 (byte-swapped) or 0x0090
# This confirms the device is MAX98390
```

### Step 3: Make Permanent

Create a systemd service:

```bash
sudo tee /etc/systemd/system/max98390-gpio-enable.service <<EOF
[Unit]
Description=Enable MAX98390 Amplifier GPIO Power
Before=sound.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo 658 > /sys/class/gpio/export'
ExecStart=/bin/bash -c 'echo out > /sys/class/gpio/gpio658/direction'
ExecStart=/bin/bash -c 'echo 1 > /sys/class/gpio/gpio658/value'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable max98390-gpio-enable.service
```

### Step 4: Test Audio

After GPIO is enabled and I2C responds:

```bash
# Reload audio drivers
sudo modprobe -r snd_sof_pci_intel_mtl
sudo modprobe snd_sof_pci_intel_mtl

# Check if speakers now appear
speaker-test -t wav -c 2
```

## Verification Checklist

- [ ] GPIO export successful
- [ ] GPIO direction set to output
- [ ] GPIO value set to HIGH
- [ ] I2C scan shows 0x38 and 0x39
- [ ] Device ID read returns 0x0090
- [ ] `dmesg` shows MAX98390 probe success
- [ ] `aplay -l` shows speaker devices
- [ ] Audio playback works

## Troubleshooting

### Issue: "Device or resource busy"

**Cause**: GPIO already exported or in use by kernel driver

**Solution**:
```bash
# Check what's using it
lsof /sys/class/gpio/gpio658

# Or just try to set the value directly
echo 1 > /sys/class/gpio/gpio658/value
```

### Issue: "Invalid argument"

**Cause**: Wrong GPIO number

**Solution**: Try other candidates (610, 723) or run full diagnostic:
```bash
sudo ./enable_max98390_gpio.sh
```

### Issue: "Permission denied" even with sudo

**Cause**: GPIO locked by ACPI or pinctrl

**Solution**: Use kernel module approach:
```bash
make -f Makefile.gpio
sudo make -f Makefile.gpio load
```

### Issue: GPIO works but I2C still shows nothing

**Causes**:
1. Wrong GPIO (try others)
2. Need longer power-up delay
3. I2C bus mismatch (try bus 0, 1, 3)
4. Device in reset state (need additional GPIO)

**Debugging**:
```bash
# Check all I2C buses
for bus in 0 1 2 3 4 5; do
    echo "Bus $bus:"
    i2cdetect -y $bus 2>/dev/null || echo "Not available"
done

# Check GPIO value is actually high
cat /sys/class/gpio/gpio658/value  # Should be "1"
```

## Technical Details

### GPIO Electrical Characteristics
- **Logic HIGH**: 1.8V or 3.3V (depends on controller config)
- **Logic LOW**: 0V
- **Current capability**: Typically 2-4mA
- **Rise time**: ~1-10μs

### MAX98390 Power Sequencing
Per datasheet:
1. Apply power to AVDD/DVDD (via GPIO enable)
2. Wait 10ms for internal regulator stabilization
3. I2C interface becomes active
4. Device can be configured and enabled

### ACPI Resource Declaration Format
```asl
GpioIo (Exclusive, PullDefault, 0x0000, 0x0000,
        IoRestrictionOutputOnly, "\\_SB.GPI0",
        0x00, ResourceConsumer, ,)
{
    0x62  // Pin number (relative to controller)
}
```

Fields:
- **Exclusive**: GPIO cannot be shared
- **PullDefault**: Use controller's default pull configuration
- **IoRestrictionOutputOnly**: This GPIO is output-only
- **\\_SB.GPI0**: ACPI path to GPIO controller
- **0x62**: Pin number (98 decimal)

## Files Reference

| File | Purpose |
|------|---------|
| `quick_gpio_test.sh` | Fast automated testing of most likely GPIOs |
| `enable_max98390_gpio.sh` | Comprehensive diagnostic and testing script |
| `calculate_gpio.py` | Detailed GPIO number calculation with analysis |
| `max98390_gpio_enable.c` | Kernel module for proper GPIO management |
| `Makefile.gpio` | Build system for kernel module |
| `MAX98390_GPIO_GUIDE.md` | Complete usage guide |
| `GPIO_ANALYSIS.md` | This technical analysis document |

## Next Steps

1. **Immediate**: Run `sudo ./quick_gpio_test.sh` to find working GPIO
2. **Short-term**: Make GPIO enable permanent via systemd service
3. **Medium-term**: Integrate into audio driver probe sequence
4. **Long-term**: Submit patch to mainline kernel for max98390.c

## References

- Intel Meteor Lake GPIO Documentation
- MAX98390 I2C Amplifier Datasheet
- Linux kernel GPIO subsystem (Documentation/driver-api/gpio/)
- ACPI specification for GPIO resources
- Existing Samsung laptop platform drivers (platform/x86/samsung-laptop.c)
