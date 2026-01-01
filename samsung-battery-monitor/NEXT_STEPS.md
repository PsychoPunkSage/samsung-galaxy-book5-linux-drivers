# Next Steps: Charge Threshold Implementation

This document outlines the roadmap for implementing battery charge threshold control for the Samsung Galaxy Book5 Pro on Linux.

## Current Status

**IMPLEMENTED (Phase 1)**:
- Low battery monitoring and notifications
- Power draw calculation
- Time remaining estimation
- Persistent notification system
- Systemd service integration

**NOT YET IMPLEMENTED**:
- Battery charge threshold control (80% limit, etc.)
- Performance mode switching (Silent/Balanced/Performance)
- Fan curve management
- Keyboard backlight control
- Other Samsung-specific features

## Why Charge Threshold Doesn't Work Yet

### The Technical Reality

Your Samsung Galaxy Book5 Pro **has the hardware capability** to limit battery charge (you've seen it work on Windows). The problem is that Linux doesn't know how to communicate with Samsung's firmware to enable this feature.

**What We Need to Discover:**

1. **The Interface Method**: How does Windows talk to the EC firmware?
   - ACPI WMI method calls?
   - Direct EC register writes?
   - ACPI method invocation?

2. **The Protocol**: What commands/values are needed?
   - Set threshold to 80%: `ACPI Method SBAT(0x50)` ?
   - Or EC write: `ec_write(0x40, 80)` ?
   - Or WMI call: `wmi_evaluate_method(SAMSUNG_GUID, ...)` ?

3. **Safety Validation**: How do we avoid bricking the laptop?
   - Test in safe read-only mode first
   - Verify with dual-boot comparisons
   - Implement bounds checking

## Phase 2: ACPI Investigation

### Step 1: Extract ACPI Tables

**YOU NEED TO RUN THESE COMMANDS** to give me the firmware information I need:

```bash
# Create investigation directory
mkdir -p ~/dev/drivers/samsung-acpi-investigation
cd ~/dev/drivers/samsung-acpi-investigation

# Extract ACPI tables (REQUIRES ROOT)
sudo acpidump > acpidump.dat

# Extract individual tables
acpixtract -a acpidump.dat

# Decompile tables to human-readable format
iasl -d *.dat

# List the generated .dsl files
ls -lh *.dsl
```

**Upload the following files for analysis:**
- `DSDT.dsl` (Main System Description Table - MOST IMPORTANT)
- `SSDT*.dsl` (Supplemental System Description Tables)
- List all `.dsl` files generated

### Step 2: WMI Device Enumeration

```bash
# Create WMI investigation script
cat > ~/dev/drivers/samsung-acpi-investigation/wmi_investigate.sh << 'EOF'
#!/bin/bash
echo "========================================="
echo "Samsung Galaxy Book5 Pro WMI Investigation"
echo "========================================="
echo ""

cd /sys/bus/wmi/devices/

for device in *; do
    echo "DEVICE: $device"
    echo "----------------------------------------"

    # Read basic device info
    if [ -f "$device/modalias" ]; then
        echo "Modalias: $(cat $device/modalias)"
    fi

    # Check for methods
    if [ -d "$device/" ]; then
        echo "Attributes:"
        ls -1 "$device/" | grep -v "^driver$\|^subsystem$\|^uevent$\|^power$" | while read attr; do
            if [ -f "$device/$attr" ] && [ -r "$device/$attr" ]; then
                echo "  $attr: $(cat $device/$attr 2>/dev/null | head -1)"
            fi
        done
    fi

    echo ""
done

echo "========================================="
echo "Checking for Samsung-specific WMI GUIDs"
echo "========================================="
echo ""

# Known Samsung WMI GUIDs (from other models)
KNOWN_GUIDS=(
    "C16C47BA-50E3-444A-AF3A-B1C348380002"  # Samsung Settings (common)
    "A6FEA33E-DABF-46F5-BFC8-460D961BEC9F"  # Platform driver
    "8246028B-F06A-4AC3-9607-F99BAD39DC8F"  # Performance control
)

for guid in "${KNOWN_GUIDS[@]}"; do
    if [ -d "/sys/bus/wmi/devices/$guid" ] || [ -L "/sys/bus/wmi/devices/$guid" ]; then
        echo "FOUND: $guid"
    else
        echo "NOT FOUND: $guid"
    fi
done
EOF

chmod +x ~/dev/drivers/samsung-acpi-investigation/wmi_investigate.sh
~/dev/drivers/samsung-acpi-investigation/wmi_investigate.sh > ~/dev/drivers/samsung-acpi-investigation/wmi_devices.txt
cat ~/dev/drivers/samsung-acpi-investigation/wmi_devices.txt
```

### Step 3: EC Debug Filesystem (Optional - requires kernel config)

Check if EC debugging is available:

```bash
# Check if EC debug interface exists
ls -la /sys/kernel/debug/ec/

# If available, dump EC RAM (BE CAREFUL - READ ONLY)
sudo cat /sys/kernel/debug/ec/ec0/io > ~/dev/drivers/samsung-acpi-investigation/ec_dump_before.txt
```

## Phase 3: Safe ACPI Method Testing

Once we have the ACPI tables, we can safely test ACPI methods using the `acpi_call` kernel module.

### Install acpi_call Module

```bash
# Ubuntu/Debian
sudo apt install acpi-call-dkms

# Or build from source
git clone https://github.com/nix-community/acpi_call.git
cd acpi_call
make
sudo insmod acpi_call.ko
```

### Test ACPI Methods (SAFE - READ ONLY FIRST)

```bash
# Example: Read battery charge threshold (if method exists)
# We'll discover the actual method name from DSDT.dsl
echo '\_SB.PCI0.LPCB.EC0.GBAT' | sudo tee /proc/acpi/call
sudo cat /proc/acpi/call
```

**IMPORTANT**: We'll only test WRITE methods after thoroughly analyzing the DSDT and understanding what they do.

## Phase 4: Kernel Driver Development

Once we identify the correct interface, I will develop a kernel module:

### Driver Architecture

```c
// drivers/platform/x86/samsung-galaxybook5.c

/*
 * Samsung Galaxy Book5 Pro Platform Driver
 *
 * Provides control over:
 * - Battery charge threshold
 * - Performance modes
 * - Keyboard backlight
 * - Fan curves
 */

#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/acpi.h>
#include <linux/wmi.h>
#include <linux/power_supply.h>

// WMI GUID for Samsung platform control (to be discovered)
#define SAMSUNG_GALAXYBOOK5_WMI_GUID "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"

struct galaxybook5_data {
    struct platform_device *pdev;
    struct power_supply *battery;
    u8 charge_threshold;
};

// Battery charge threshold control
static ssize_t charge_control_end_threshold_show(struct device *dev,
                                                   struct device_attribute *attr,
                                                   char *buf)
{
    struct galaxybook5_data *data = dev_get_drvdata(dev);
    return sprintf(buf, "%d\n", data->charge_threshold);
}

static ssize_t charge_control_end_threshold_store(struct device *dev,
                                                    struct device_attribute *attr,
                                                    const char *buf, size_t count)
{
    struct galaxybook5_data *data = dev_get_drvdata(dev);
    u8 threshold;
    int ret;

    ret = kstrtou8(buf, 10, &threshold);
    if (ret)
        return ret;

    if (threshold < 50 || threshold > 100)
        return -EINVAL;

    // Method 1: WMI call (example - actual implementation depends on discovery)
    // ret = wmi_evaluate_method(SAMSUNG_GALAXYBOOK5_WMI_GUID, 0, METHOD_ID, ...);

    // Method 2: ACPI method call (example)
    // ret = acpi_execute_simple_method(NULL, "\\_SB.PCI0.LPCB.EC0.SBAT", threshold);

    // Method 3: Direct EC write (example - DANGEROUS without validation)
    // ret = ec_write(EC_BATTERY_THRESHOLD_REG, threshold);

    if (ret)
        return ret;

    data->charge_threshold = threshold;
    return count;
}

static DEVICE_ATTR_RW(charge_control_end_threshold);

// Module initialization
static int galaxybook5_probe(struct platform_device *pdev)
{
    struct galaxybook5_data *data;
    int ret;

    data = devm_kzalloc(&pdev->dev, sizeof(*data), GFP_KERNEL);
    if (!data)
        return -ENOMEM;

    data->pdev = pdev;
    platform_set_drvdata(pdev, data);

    // Create sysfs attributes
    ret = device_create_file(&pdev->dev, &dev_attr_charge_control_end_threshold);
    if (ret)
        return ret;

    pr_info("Samsung Galaxy Book5 Pro platform driver loaded\n");
    return 0;
}

static struct platform_driver galaxybook5_driver = {
    .driver = {
        .name = "samsung-galaxybook5",
        .acpi_match_table = galaxybook5_acpi_match,
    },
    .probe = galaxybook5_probe,
};

module_platform_driver(galaxybook5_driver);

MODULE_AUTHOR("Your Name");
MODULE_DESCRIPTION("Samsung Galaxy Book5 Pro Platform Driver");
MODULE_LICENSE("GPL");
```

### Expected sysfs Interface

Once the driver is loaded:

```bash
# Set charge threshold to 80%
echo 80 | sudo tee /sys/class/power_supply/BAT1/charge_control_end_threshold

# Read current threshold
cat /sys/class/power_supply/BAT1/charge_control_end_threshold
```

## Phase 5: Integration with Battery Monitor

Once the kernel driver works, we'll integrate it into the Rust battery monitor:

### Enhanced Battery Monitor Features

```rust
// Check if charge threshold control is available
fn has_charge_threshold_support() -> bool {
    Path::new("/sys/class/power_supply/BAT1/charge_control_end_threshold").exists()
}

// Set charge threshold
fn set_charge_threshold(threshold: u8) -> io::Result<()> {
    if threshold < 50 || threshold > 100 {
        return Err(io::Error::new(io::ErrorKind::InvalidInput,
                                   "Threshold must be 50-100"));
    }

    fs::write("/sys/class/power_supply/BAT1/charge_control_end_threshold",
              threshold.to_string())
}

// Get current threshold
fn get_charge_threshold() -> io::Result<u8> {
    read_sysfs_u8("/sys/class/power_supply/BAT1/charge_control_end_threshold")
}
```

### Configuration File Support

Add to battery monitor config:

```json
{
    "low_battery_threshold": 9,
    "critical_battery_threshold": 5,
    "poll_interval_secs": 60,
    "charge_control": {
        "enabled": true,
        "threshold": 80,
        "auto_adjust": false
    }
}
```

## Timeline Estimate

Based on typical reverse engineering efforts:

**Week 1-2**: ACPI table analysis
- Decompile and analyze DSDT/SSDT
- Identify EC device path
- Map WMI GUIDs to functionality
- Cross-reference with known Samsung patterns

**Week 3-4**: Safe testing
- Install acpi_call module
- Test read-only ACPI methods
- Validate findings with dual-boot comparison
- Document EC register layout

**Week 5-6**: Prototype driver development
- Implement basic kernel module
- Create sysfs interface
- Test charge threshold control
- Validate safety and reliability

**Week 7-8**: Integration and polish
- Integrate with battery monitor
- Add configuration support
- Write documentation
- Prepare for upstream submission

**Total**: 1-2 months of part-time investigation and development

## Required Information from You

To proceed with Phase 2, I need:

1. **ACPI Tables** (MOST IMPORTANT):
   ```bash
   sudo acpidump > acpidump.dat
   acpixtract -a acpidump.dat
   iasl -d *.dat
   # Upload DSDT.dsl and all SSDT*.dsl files
   ```

2. **WMI Device List**:
   ```bash
   # Run the wmi_investigate.sh script created above
   ```

3. **Current Battery Info**:
   ```bash
   cat /sys/class/power_supply/BAT1/uevent
   ls -la /sys/class/power_supply/BAT1/
   ```

4. **Windows Behavior** (if you have dual-boot):
   - What app do you use in Windows to set charge threshold?
   - Screenshot of the settings interface
   - Any error messages or logs from that app

## Resources and References

### Similar Laptop Drivers (for reference)

- **ThinkPad**: `drivers/platform/x86/thinkpad_acpi.c`
- **Dell**: `drivers/platform/x86/dell-laptop.c`
- **HP**: `drivers/platform/x86/hp-wmi.c`
- **Framework**: `drivers/power/supply/framework_laptop.c`
- **Samsung (old)**: `drivers/platform/x86/samsung-laptop.c`

### Kernel Documentation

- ACPI: `Documentation/firmware-guide/acpi/`
- WMI: `Documentation/wmi/`
- Power Supply: `Documentation/power/power_supply_class.rst`
- Platform Drivers: `Documentation/driver-api/driver-model/platform.rst`

### Useful Tools

- `acpidump` / `acpixtract` / `iasl` - ACPI table extraction and decompilation
- `acpi_call` - Safe ACPI method testing
- `rwmem` - Memory-mapped register access
- `ioport` - I/O port access for EC communication
- `lspci` / `lsusb` - Device enumeration

## Safety Guidelines

**ALWAYS FOLLOW THESE RULES**:

1. NEVER write to EC registers without understanding what they do
2. ALWAYS test read-only methods first
3. NEVER skip bounds checking on user input
4. ALWAYS implement safe defaults (e.g., threshold >= 50%)
5. NEVER run untested code on your only laptop
6. ALWAYS have a recovery plan (Live USB, dual-boot, etc.)
7. NEVER ignore kernel warnings or errors
8. ALWAYS document what each register/method does

## Getting Started

To begin the charge threshold investigation:

```bash
# 1. Create investigation directory
mkdir -p ~/dev/drivers/samsung-acpi-investigation
cd ~/dev/drivers/samsung-acpi-investigation

# 2. Extract ACPI tables
sudo acpidump > acpidump.dat
acpixtract -a acpidump.dat
iasl -d *.dat

# 3. Investigate WMI devices
bash ~/dev/drivers/samsung-battery-monitor/NEXT_STEPS.md  # (contains wmi_investigate.sh script)

# 4. Share the results
ls -lh *.dsl
echo "Upload DSDT.dsl and SSDT*.dsl files for analysis"
```

Once I receive your ACPI tables, I can:
- Identify the battery control interface
- Map EC registers
- Locate WMI method GUIDs
- Provide a safe testing plan
- Develop the kernel driver

## Contact and Collaboration

This is a collaborative reverse-engineering effort. Your contributions:

1. Running diagnostic commands
2. Testing safe ACPI methods
3. Validating driver behavior
4. Reporting results

My contributions:

1. Analyzing ACPI tables
2. Writing kernel driver code
3. Ensuring safety and correctness
4. Preparing upstream submission

Together, we can enable full hardware support for Samsung Galaxy Book5 Pro on Linux!

---

**Ready to start?** Run the ACPI extraction commands above and share the results!
