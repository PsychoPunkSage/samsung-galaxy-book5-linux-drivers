# Samsung Galaxy Book5 Pro Battery Monitor

Production-quality battery monitoring daemon for Samsung Galaxy Book5 Pro running Linux with Wayland/Hyprland.

## Features

- **Low Battery Notifications**: Alerts when battery drops below 9%
- **Critical Battery Warnings**: Urgent alerts at 5% battery
- **Persistent Nagging**: Continuous notifications while battery is low and discharging
- **Power Statistics**: Displays current power draw (Watts) and estimated time remaining
- **Compact Notifications**: Clean, informative alerts via swaync
- **Systemd Integration**: Runs automatically on login, restarts on failure
- **Resource Efficient**: Minimal CPU and memory usage
- **Safe & Reliable**: Written in Rust for memory safety and reliability

## System Requirements

- **Hardware**: Samsung Galaxy Book5 Pro (940XHA) or compatible
- **OS**: Ubuntu 25.04 or any modern Linux distribution
- **Kernel**: Linux 6.9+ (tested on 6.14)
- **Desktop**: Wayland with Hyprland window manager
- **Notification Daemon**: swaync (SwayNotificationCenter)
- **Rust Toolchain**: 1.70+ (for building)

## Installation

### Quick Install

```bash
cd ~/dev/drivers/samsung-battery-monitor
chmod +x install.sh
./install.sh
```

The installation script will:
1. Build the Rust binary in release mode
2. Install to `~/.local/bin/battery-monitor`
3. Install systemd service to `~/.config/systemd/user/`
4. Enable and start the service automatically
5. Verify the installation

### Manual Build

```bash
# Build the project
cargo build --release

# Copy binary to local bin
cp target/release/battery-monitor ~/.local/bin/

# Install systemd service
cp battery-monitor.service ~/.config/systemd/user/

# Enable and start service
systemctl --user daemon-reload
systemctl --user enable battery-monitor.service
systemctl --user start battery-monitor.service
```

## Usage

### Service Management

```bash
# Check service status
systemctl --user status battery-monitor

# View live logs
journalctl --user -u battery-monitor -f

# View last 50 log entries
journalctl --user -u battery-monitor -n 50

# Restart service
systemctl --user restart battery-monitor

# Stop service
systemctl --user stop battery-monitor

# Disable service (prevent auto-start)
systemctl --user disable battery-monitor
```

### Manual Testing

Run the monitor manually (stops systemd service first):

```bash
systemctl --user stop battery-monitor
~/.local/bin/battery-monitor
```

Press `Ctrl+C` to stop.

### Configuration

Thresholds and settings are configured in `src/main.rs`:

```rust
const LOW_BATTERY_THRESHOLD: u8 = 9;      // Low battery warning at 9%
const CRITICAL_BATTERY_THRESHOLD: u8 = 5; // Critical warning at 5%
const POLL_INTERVAL_SECS: u64 = 60;       // Check every 60 seconds
const RESET_THRESHOLD: u8 = 15;           // Clear notifications above 15%
```

After changing configuration, rebuild and reinstall:

```bash
cargo build --release
cp target/release/battery-monitor ~/.local/bin/
systemctl --user restart battery-monitor
```

## How It Works

### Architecture

```
┌─────────────────────────────────────────┐
│   systemd --user (automatic startup)    │
│                                          │
│   battery-monitor.service                │
│   └─> ~/.local/bin/battery-monitor      │
│        │                                 │
│        ├─> Reads /sys/class/power_supply/BAT1/
│        │   • capacity (percentage)       │
│        │   • charge_now, charge_full     │
│        │   • current_now, voltage_now    │
│        │   • status (Charging/Discharging)
│        │                                 │
│        ├─> Calculates:                   │
│        │   • Power draw (Watts)          │
│        │   • Time remaining (minutes)    │
│        │                                 │
│        └─> Sends notifications via       │
│            notify-send → swaync          │
└─────────────────────────────────────────┘
```

### Notification Logic

1. **Normal State** (>15% battery):
   - No notifications sent
   - Battery status logged every 60 seconds

2. **Low Battery State** (≤9%, >5%):
   - First notification sent immediately
   - Persistent notifications every 60 seconds while discharging
   - Shows: percentage, power draw, estimated time remaining

3. **Critical Battery State** (≤5%):
   - Urgent critical notification
   - Persistent nagging every 60 seconds
   - Warning: "System will shutdown soon!"

4. **Recovery** (AC plugged in OR battery >15%):
   - Notification state reset
   - No more alerts until battery drops again

### Power Calculation

```rust
Power (Watts) = (current_now µA × voltage_now µV) / 1,000,000,000,000

Time Remaining (minutes) = (charge_now µAh / current_now µA) × 60
```

## Troubleshooting

### Service Won't Start

```bash
# Check service status
systemctl --user status battery-monitor

# View error logs
journalctl --user -u battery-monitor -n 50

# Common issues:
# 1. Binary not found - check ~/.local/bin/battery-monitor exists
# 2. Battery device not found - verify /sys/class/power_supply/BAT1 exists
# 3. Permission issues - ensure binary is executable (chmod +x)
```

### No Notifications Appearing

```bash
# Check if swaync is running
pgrep swaync

# Test notification system manually
notify-send "Test" "This is a test notification" -u critical

# Check WAYLAND_DISPLAY environment variable
echo $WAYLAND_DISPLAY

# Restart swaync if needed
killall swaync && swaync &
```

### Battery Device Not Found

```bash
# List all power supply devices
ls -la /sys/class/power_supply/

# If your battery is named differently (e.g., BAT0), edit src/main.rs:
const BATTERY_PATH: &str = "/sys/class/power_supply/BAT0";  # Change BAT1 to BAT0

# Then rebuild and reinstall
cargo build --release
cp target/release/battery-monitor ~/.local/bin/
systemctl --user restart battery-monitor
```

### High CPU Usage

The monitor is designed to be extremely lightweight (< 0.1% CPU average). If you see high usage:

```bash
# Check if multiple instances are running
pgrep -a battery-monitor

# Kill extra instances
killall battery-monitor
systemctl --user restart battery-monitor
```

## File Locations

```
Project Structure:
~/dev/drivers/samsung-battery-monitor/
├── Cargo.toml                    # Rust project configuration
├── src/
│   └── main.rs                   # Main application source code
├── battery-monitor.service       # Systemd service unit file
├── install.sh                    # Installation script
└── README.md                     # This file

Installed Files:
~/.local/bin/battery-monitor                        # Binary executable
~/.config/systemd/user/battery-monitor.service      # Service unit
```

## Logs and Monitoring

All output goes to systemd journal (stderr). View with:

```bash
# Live monitoring (follow mode)
journalctl --user -u battery-monitor -f

# Example log output:
# [INFO] Battery monitor started
# [INFO] Monitoring: /sys/class/power_supply/BAT1
# [STATUS] Battery: 95% | Status: Discharging | AC: No | Power: 4.7W
# [STATUS] Estimated time remaining: 5h 12m
# [WARNING] Battery at 9% - Low battery notification sent
```

## Future Enhancements (Planned)

### Phase 2: Battery Health Monitoring
- Track charge cycle history
- Monitor capacity degradation
- Export statistics to CSV/JSON

### Phase 3: Charge Threshold Control
- Set maximum charge limit (e.g., 80%) to extend battery life
- Requires reverse-engineering Samsung EC interface
- ACPI/WMI driver development needed

### Phase 4: Power Profile Integration
- Automatic power profile switching
- Integration with TLP or power-profiles-daemon
- Waybar module for visual battery status

## Contributing

This is a personal project for Samsung Galaxy Book5 Pro Linux enablement. Contributions welcome!

## License

GPL-2.0-or-later (same as Linux kernel)

## Author

Battery Monitor Contributors

## Platform Support

**Tested On:**
- Samsung Galaxy Book5 Pro (940XHA)
- Ubuntu 25.04
- Linux kernel 6.14.0-37-generic
- Hyprland (Wayland compositor)
- swaync 0.10.1

**Should Work On:**
- Any Samsung laptop with standard ACPI battery interface
- Any Linux distribution with systemd
- Any Wayland compositor with notification daemon support
- X11 environments with notification support

## Acknowledgments

- Linux kernel ACPI/battery subsystem maintainers
- Rust community for excellent documentation
- Hyprland and swaync developers
