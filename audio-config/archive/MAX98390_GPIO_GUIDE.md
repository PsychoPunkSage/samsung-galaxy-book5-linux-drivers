# MAX98390 GPIO Power Enable Guide

## Problem Statement

The MAX98390 amplifiers on Samsung Galaxy Book5 Pro are not responding on I2C bus 2 at addresses 0x38/0x39 because their GPIO power enable line is not activated.

**ACPI Declaration**: GPIO 0x62 (pin 98 decimal) for amplifier enable

## GPIO Number Calculation

Linux GPIO numbers are calculated as: **GPIO = base + offset**

### Known GPIO Controllers (from your system)
```
Base 512: Controller 0
Base 560: Controller 1
Base 625: Controller 2
Base 691: Controller 3
Base 699: Controller 4
```

### Calculation Methods

#### Method 1: Direct Offset (Most Common)
ACPI pin 98 is relative to a specific GPIO controller base.

**Candidates**:
- `512 + 98 = 610` (Controller 0)
- `560 + 98 = 658` (Controller 1)
- `625 + 98 = 723` (Controller 2)

#### Method 2: Absolute Pin Number
If pin 98 falls within a controller's range:
- Controller 0: 512-559 (48 pins) - **No**
- Controller 1: 560-624 (65 pins) - **No**
- Controller 2: 625-690 (66 pins) - **No**
- Controller 3: 691-698 (8 pins) - **No**
- Controller 4: 699+ - **Possible if range extends**

#### Method 3: Intel MTL/ARL GPIO Communities
Intel Meteor Lake / Arrow Lake GPIOs are organized in communities:

```
GPP_A (0-24)    - General Purpose
GPP_B (0-23)    - PCH/Platform
GPP_C (0-23)    - PCIe/Display
GPP_D (0-12)    - Audio/I2C
GPP_E (0-23)    - Various
```

Pin 98 could map to a specific community. Typical formula:
```
Linux GPIO = gpiochip_base + community_offset + pin_in_group
```

## Step-by-Step Testing Procedure

### Step 1: Run the Automated Script

```bash
cd /home/psychopunk_sage/dev/drivers/audio-config
chmod +x enable_max98390_gpio.sh
sudo ./enable_max98390_gpio.sh
```

This will:
- Enumerate all GPIO controllers
- Calculate candidate GPIO numbers
- Attempt to export and enable each candidate
- Scan I2C bus after each attempt
- Report success if MAX98390 responds

### Step 2: Run the Python Calculator (More Detailed)

```bash
chmod +x calculate_gpio.py
sudo python3 calculate_gpio.py
```

This provides:
- Detailed GPIO controller analysis
- Multiple calculation methods
- GPIO debugfs inspection
- Interactive testing with I2C verification

### Step 3: Manual Testing (if scripts fail)

```bash
# Try each candidate manually
for gpio in 610 658 723; do
    echo "Testing GPIO $gpio..."
    echo $gpio > /sys/class/gpio/export
    sleep 0.5
    echo out > /sys/class/gpio/gpio$gpio/direction
    echo 1 > /sys/class/gpio/gpio$gpio/value
    sleep 0.5
    echo "Scanning I2C..."
    i2cdetect -y 2
    read -p "Did it work? (y/n) " answer
    if [ "$answer" = "y" ]; then
        echo "Success! Working GPIO: $gpio"
        break
    fi
done
```

### Step 4: Check ACPI Power State

```bash
# List ACPI devices related to MAX98390
ls -la /sys/bus/acpi/devices/ | grep -i max

# If found, check and modify power state
cat /sys/bus/acpi/devices/MAX98390:00/power_state
echo on > /sys/bus/acpi/devices/MAX98390:00/power/control
```

### Step 5: Verify GPIO from ACPI Table

```bash
# Decompile DSDT
sudo acpidump > acpidump.out
iasl -d acpidump.out

# Search for MAX98390 device
grep -A 50 "MAX98390" dsdt.dsl

# Look for GpioIo or GpioInt resources
grep -B 5 -A 10 "GpioIo.*0x62" dsdt.dsl
```

The ACPI resource will show:
```
GpioIo (Exclusive, PullDefault, 0x0000, 0x0000,
    IoRestrictionOutputOnly, "\\_SB.GPI0",
    0x00, ResourceConsumer, ,)
    { 0x62 }  // Pin 98 (0x62)
```

The `\\_SB.GPI0` reference tells you which GPIO controller.

## Using the Kernel Module

If userspace GPIO control doesn't work (ACPI may have locked the GPIO), use the kernel module:

### Compile and Load

```bash
cd /home/psychopunk_sage/dev/drivers/audio-config
make -f Makefile.gpio
sudo make -f Makefile.gpio load
```

### Check Result

```bash
# Check kernel messages
dmesg | tail -20

# Should see:
# "MAX98390 power GPIO set to HIGH"
# "MAX98390 GPIO enable driver initialized successfully"

# Verify I2C
i2cdetect -y 2
```

### Make Permanent

```bash
sudo make -f Makefile.gpio install
echo "max98390_gpio_enable" | sudo tee /etc/modules-load.d/max98390.conf
```

## Alternative: pinctrl Override

If the GPIO is locked by ACPI, you may need to override it via pinctrl:

```bash
# Check which pinctrl driver is managing the pin
cat /sys/kernel/debug/pinctrl/*/pins | grep -A 2 "pin 98"

# If locked, you need a kernel patch to export it
# Or use ACPI method override (advanced)
```

## Verification After Enable

Once GPIO is enabled, verify the amplifier responds:

```bash
# I2C detection
i2cdetect -y 2
# Should show "38" and/or "39"

# Read device ID (register 0x21FF = 0x0090 for MAX98390)
i2cget -y 2 0x38 0x21 w
i2cget -y 2 0x39 0x21 w

# Expected: 0x9000 (byte-swapped) or 0x0090
```

## Common Issues

### Issue 1: GPIO Already Exported
```
echo: write error: Device or resource busy
```
**Solution**: GPIO is already managed. Check `lsof /sys/class/gpio/gpio<N>` or just set the value:
```bash
echo 1 > /sys/class/gpio/gpio<N>/value
```

### Issue 2: Permission Denied
```
echo: write error: Permission denied
```
**Solution**: Run with sudo or check GPIO is not locked by kernel.

### Issue 3: Invalid GPIO Number
```
echo: write error: Invalid argument
```
**Solution**: GPIO number out of range. Try different calculation.

### Issue 4: ACPI Locked
The GPIO may be reserved by ACPI and cannot be exported from userspace.
**Solution**: Use the kernel module approach or modify ACPI DSDT.

## Expected Results

### Success Indicators
1. **GPIO Export**: Successfully creates `/sys/class/gpio/gpio<N>/`
2. **Direction Set**: Can write to `direction` file
3. **Value Set**: `cat value` shows `1` after setting HIGH
4. **I2C Response**: `i2cdetect -y 2` shows `38` and `39`
5. **Device ID**: Reading register 0x21FF returns 0x0090

### Timeline
- GPIO export: Immediate
- Power stabilization: ~10-50ms
- I2C response: ~100-500ms after power-on

## Integration with Audio Driver

Once GPIO is working, the main audio driver needs to:

1. **Include GPIO control in probe**:
```c
struct gpio_desc *enable_gpio;
enable_gpio = devm_gpiod_get(&pdev->dev, "enable", GPIOD_OUT_HIGH);
```

2. **Or use existing ACPI power management**:
```c
acpi_device_set_power(adev, ACPI_STATE_D0);
```

3. **Add to MAX98390 codec driver** (sound/soc/codecs/max98390.c):
```c
static int max98390_i2c_probe(struct i2c_client *i2c)
{
    /* Ensure GPIO power is enabled */
    devm_gpiod_get_optional(&i2c->dev, "enable", GPIOD_OUT_HIGH);

    /* Continue with normal probe */
    ...
}
```

## Next Steps After GPIO Enable

1. Verify I2C communication
2. Test audio playback through amplifiers
3. Implement proper power management (suspend/resume)
4. Add GPIO control to mainline audio driver
5. Submit patches upstream

## Files Created

- `/home/psychopunk_sage/dev/drivers/audio-config/enable_max98390_gpio.sh` - Automated bash script
- `/home/psychopunk_sage/dev/drivers/audio-config/calculate_gpio.py` - Python calculator
- `/home/psychopunk_sage/dev/drivers/audio-config/max98390_gpio_enable.c` - Kernel module
- `/home/psychopunk_sage/dev/drivers/audio-config/Makefile.gpio` - Module build file
- `/home/psychopunk_sage/dev/drivers/audio-config/MAX98390_GPIO_GUIDE.md` - This guide

## Quick Command Reference

```bash
# List GPIO controllers
for chip in /sys/class/gpio/gpiochip*; do
    echo "$chip: base=$(cat $chip/base) count=$(cat $chip/ngpio) $(cat $chip/label)"
done

# Test specific GPIO
gpio=610
echo $gpio > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio$gpio/direction
echo 1 > /sys/class/gpio/gpio$gpio/value
i2cdetect -y 2

# Check ACPI devices
ls /sys/bus/acpi/devices/ | grep -i max

# Read GPIO debugfs
sudo cat /sys/kernel/debug/gpio

# Decompile ACPI
sudo acpidump > acpi.dat && iasl -d acpi.dat && grep -A 20 MAX98390 dsdt.dsl
```
