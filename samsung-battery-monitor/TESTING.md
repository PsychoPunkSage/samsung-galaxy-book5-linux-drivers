# Testing Guide - Samsung Battery Monitor

This guide covers testing procedures for the battery monitor before and after installation.

## Pre-Installation Testing

### 1. Quick Build Test

Verify the project compiles without errors:

```bash
cd ~/dev/drivers/samsung-battery-monitor
cargo build --release
```

Expected output:
```
   Compiling battery-monitor v0.1.0 (/home/psychopunk_sage/dev/drivers/samsung-battery-monitor)
    Finished `release` profile [optimized] target(s) in X.XXs
```

### 2. Manual Run Test

Run the monitor manually to see live output:

```bash
./test.sh
```

Or run the binary directly:

```bash
./target/release/battery-monitor
```

Expected output:
```
=============================================================
  Samsung Galaxy Book5 Pro Battery Monitor
  Version: 0.1.0
  Platform: Linux (Wayland/Hyprland)
  Notification Daemon: swaync
=============================================================
[INFO] Battery monitor started
[INFO] Monitoring: /sys/class/power_supply/BAT1
[INFO] Low battery threshold: 9%
[INFO] Critical battery threshold: 5%
[INFO] Poll interval: 60s
[STATUS] Battery: 95% | Status: Discharging | AC: No | Power: 4.7W
[STATUS] Estimated time remaining: 5h 12m
```

Press `Ctrl+C` to stop.

### 3. Notification Test

Send a test notification to verify swaync is working:

```bash
notify-send "Battery Monitor Test" "Testing notification system" -u critical --category battery --icon battery-caution
```

You should see a notification appear on your screen.

## Installation Testing

### 1. Run Installation Script

```bash
cd ~/dev/drivers/samsung-battery-monitor
./install.sh
```

The script will:
- Build the binary
- Install to `~/.local/bin/`
- Install systemd service
- Enable and start the service
- Verify the installation

### 2. Verify Service is Running

```bash
systemctl --user status battery-monitor
```

Expected output:
```
● battery-monitor.service - Samsung Galaxy Book5 Pro Battery Monitor
     Loaded: loaded (/home/psychopunk_sage/.config/systemd/user/battery-monitor.service; enabled; preset: enabled)
     Active: active (running) since ...
```

### 3. Check Logs

View the last 20 log entries:

```bash
journalctl --user -u battery-monitor -n 20 --no-pager
```

Expected log format:
```
Jan 01 23:30:00 Dumbo battery-monitor[12345]: [INFO] Battery monitor started
Jan 01 23:30:00 Dumbo battery-monitor[12345]: [STATUS] Battery: 95% | Status: Discharging | AC: No | Power: 4.7W
```

### 4. Follow Logs in Real-Time

```bash
journalctl --user -u battery-monitor -f
```

This will show logs as they are generated. Press `Ctrl+C` to exit.

## Functional Testing

### Test 1: Low Battery Notification

**IMPORTANT**: Only test this if you're comfortable letting your battery drain to 9%.

**Safer Alternative**: Modify the threshold temporarily for testing:

1. Edit `src/main.rs`:
   ```rust
   const LOW_BATTERY_THRESHOLD: u8 = 95;  // Temporarily set to current battery level
   ```

2. Rebuild and reinstall:
   ```bash
   cargo build --release
   cp target/release/battery-monitor ~/.local/bin/
   systemctl --user restart battery-monitor
   ```

3. Unplug AC adapter

4. Wait 60 seconds - you should receive a notification

5. Restore the threshold to 9% and rebuild again

### Test 2: AC Plug/Unplug Detection

1. Watch logs in real-time:
   ```bash
   journalctl --user -u battery-monitor -f
   ```

2. Unplug AC adapter - look for status change:
   ```
   [STATUS] Battery: 95% | Status: Discharging | AC: No | Power: 4.7W
   ```

3. Plug in AC adapter - look for status change:
   ```
   [STATUS] Battery: 95% | Status: Charging | AC: Yes | Power: 0.2W
   ```

### Test 3: Power Calculation Accuracy

Compare the monitor's power reading with system tools:

```bash
# Battery monitor reading
journalctl --user -u battery-monitor -n 1 --no-pager | grep Power

# Manual calculation
CURRENT=$(cat /sys/class/power_supply/BAT1/current_now)
VOLTAGE=$(cat /sys/class/power_supply/BAT1/voltage_now)
echo "scale=2; ($CURRENT * $VOLTAGE) / 1000000000000" | bc
```

Readings should match within 0.1W.

### Test 4: Time Remaining Accuracy

1. Note the estimated time from logs
2. Wait 15-30 minutes
3. Check if the estimate adjusts based on actual usage
4. Compare with `upower -i /org/freedesktop/UPower/devices/battery_BAT1`

### Test 5: Notification Recovery

1. Trigger a low battery notification (use threshold modification method)
2. Plug in AC adapter
3. Verify notification state resets (check logs for "Battery recovering" message)
4. Unplug AC again - verify no immediate notification (state properly reset)

### Test 6: Service Restart Reliability

```bash
# Restart the service multiple times
for i in {1..5}; do
    echo "Restart test $i/5"
    systemctl --user restart battery-monitor
    sleep 2
    systemctl --user is-active battery-monitor || echo "FAIL"
done
```

All iterations should show "active".

### Test 7: Signal Handling

Test graceful shutdown:

```bash
# Get the PID
PID=$(systemctl --user show -p MainPID battery-monitor | cut -d= -f2)

# Send SIGTERM
kill -TERM $PID

# Check logs for graceful shutdown message
journalctl --user -u battery-monitor -n 5 | grep "shutting down gracefully"
```

Should see:
```
[INFO] Battery monitor shutting down gracefully
```

### Test 8: Resource Usage

Monitor CPU and memory usage:

```bash
# Check resource usage
systemctl --user status battery-monitor | grep -E "Memory|CPU"

# Or use top
top -p $(pgrep battery-monitor)
```

Expected:
- Memory: < 10 MB
- CPU: < 1% average

## Stress Testing

### Long-Term Stability Test

Run the monitor for 24+ hours:

```bash
# Start time
date

# Check uptime after 24 hours
systemctl --user status battery-monitor | grep Active

# Check for any errors in logs
journalctl --user -u battery-monitor --since "24 hours ago" | grep ERROR
```

Should have no errors and remain active.

### Rapid AC Plug/Unplug Test

```bash
# Watch logs
journalctl --user -u battery-monitor -f

# Rapidly plug/unplug AC adapter 10 times
# Monitor should handle all state changes correctly
```

Check logs for consistent state tracking.

## Troubleshooting Tests

### Test: Service Won't Start

```bash
# Stop service
systemctl --user stop battery-monitor

# Run manually to see error output
~/.local/bin/battery-monitor
```

Common issues:
- Battery device not found
- Permission denied
- notify-send not in PATH

### Test: No Notifications

```bash
# Verify notify-send works
notify-send "Test" "Test message"

# Check DBUS_SESSION_BUS_ADDRESS
echo $DBUS_SESSION_BUS_ADDRESS

# Verify swaync is running
pgrep swaync || swaync &
```

### Test: High CPU Usage

```bash
# Check if multiple instances are running
pgrep -a battery-monitor

# Kill all instances
killall battery-monitor

# Restart service
systemctl --user restart battery-monitor

# Verify only one instance
pgrep -c battery-monitor  # Should output: 1
```

## Performance Benchmarks

### Binary Size

```bash
ls -lh target/release/battery-monitor
```

Expected: < 2 MB (optimized with LTO and strip)

### Startup Time

```bash
time target/release/battery-monitor &
sleep 1
killall battery-monitor
```

Expected: < 100ms

### Memory Footprint

```bash
ps -o pid,rss,vsz,cmd -p $(pgrep battery-monitor)
```

Expected RSS (Resident Set Size): < 5 MB

## Test Checklist

Before considering the installation complete, verify:

- [ ] Binary compiles without errors
- [ ] Binary runs without crashes
- [ ] Service starts automatically
- [ ] Service restarts on failure
- [ ] Logs appear in journalctl
- [ ] Battery status is read correctly
- [ ] Power draw calculation is accurate
- [ ] Time remaining estimation works
- [ ] AC plug/unplug detection works
- [ ] Notifications are sent and displayed
- [ ] Notification state resets properly
- [ ] Resource usage is minimal
- [ ] No memory leaks over 24 hours
- [ ] Graceful shutdown on SIGTERM

## Test Results Template

Use this template to document your test results:

```
========================================
Battery Monitor Test Results
========================================

Date: YYYY-MM-DD
Kernel: uname -r
Distribution: cat /etc/os-release | grep PRETTY_NAME

Build Test:            [ PASS / FAIL ]
Manual Run Test:       [ PASS / FAIL ]
Service Install:       [ PASS / FAIL ]
Service Active:        [ PASS / FAIL ]
Log Output:            [ PASS / FAIL ]
Low Battery Alert:     [ PASS / FAIL ]
AC Detection:          [ PASS / FAIL ]
Power Calculation:     [ PASS / FAIL ]
Time Estimation:       [ PASS / FAIL ]
Notification Display:  [ PASS / FAIL ]
State Reset:           [ PASS / FAIL ]
Resource Usage:        [ PASS / FAIL ]
24hr Stability:        [ PASS / FAIL ]

Notes:
_______________________________________
_______________________________________
_______________________________________

Issues Found:
_______________________________________
_______________________________________
_______________________________________
```

## Debugging Commands

Useful commands for debugging issues:

```bash
# View all battery attributes
cat /sys/class/power_supply/BAT1/uevent

# Check systemd environment
systemctl --user show-environment

# Verify service file syntax
systemd-analyze verify ~/.config/systemd/user/battery-monitor.service

# Check binary dependencies
ldd ~/.local/bin/battery-monitor

# Trace system calls (advanced)
strace -e trace=file ~/.local/bin/battery-monitor

# Check notification daemon
busctl --user monitor org.freedesktop.Notifications
```

## Next Steps After Testing

Once all tests pass:

1. **Daily Use**: Let it run for a week to verify stability
2. **Edge Cases**: Test with suspend/resume, hibernate, etc.
3. **Battery Calibration**: Run battery through full discharge/charge cycle
4. **Documentation**: Note any quirks or system-specific behavior
5. **Optimization**: Adjust thresholds and polling interval to your preferences

## Reporting Issues

If you encounter issues, collect this information:

```bash
# System info
uname -a
cat /sys/class/dmi/id/product_name
cat /sys/class/dmi/id/sys_vendor

# Service status
systemctl --user status battery-monitor

# Recent logs
journalctl --user -u battery-monitor -n 100 --no-pager

# Battery device info
ls -la /sys/class/power_supply/
cat /sys/class/power_supply/BAT1/uevent

# Binary info
file ~/.local/bin/battery-monitor
ldd ~/.local/bin/battery-monitor

# Rust version
rustc --version
cargo --version
```

Save this information when reporting issues or requesting help.
