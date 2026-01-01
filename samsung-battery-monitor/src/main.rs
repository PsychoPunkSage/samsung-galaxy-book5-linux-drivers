// SPDX-License-Identifier: GPL-2.0-or-later
//
// Samsung Galaxy Book5 Pro Battery Monitor
//
// Production-quality battery monitoring daemon for Linux/Wayland
// Monitors battery level and sends notifications via swaync
//
// Author: Battery Monitor Contributors
// Target Platform: Samsung Galaxy Book5 Pro (940XHA)
// Kernel: Linux 6.14+
// Notification Daemon: swaync

use std::fs;
use std::io;
use std::path::Path;
use std::process::Command;
use std::thread;
use std::time::Duration;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use signal_hook::consts::{SIGTERM, SIGINT};
use signal_hook::flag;

// ============================================================================
// CONFIGURATION
// ============================================================================

const BATTERY_PATH: &str = "/sys/class/power_supply/BAT1";
const AC_ADAPTER_PATH: &str = "/sys/class/power_supply/ADP1";
const POLL_INTERVAL_SECS: u64 = 60;
const LOW_BATTERY_THRESHOLD: u8 = 9;
const CRITICAL_BATTERY_THRESHOLD: u8 = 5;
const RESET_THRESHOLD: u8 = 15; // Clear notification state when battery rises above this

// ============================================================================
// BATTERY DATA STRUCTURES
// ============================================================================

#[derive(Debug, Clone)]
struct BatteryStatus {
    capacity: u8,              // Battery percentage (0-100)
    status: String,            // "Charging", "Discharging", "Full", "Not charging"
    charge_now: u64,           // Current charge in µAh
    #[allow(dead_code)]
    charge_full: u64,          // Full charge capacity in µAh (reserved for future health monitoring)
    current_now: u64,          // Current draw in µA
    voltage_now: u64,          // Current voltage in µV
    ac_online: bool,           // Is AC adapter connected?
}

#[derive(Debug)]
struct BatteryStats {
    power_draw_watts: f64,     // Current power consumption in watts
    time_remaining_mins: Option<u32>, // Estimated time remaining (None if charging)
}

#[derive(Debug, Default)]
struct NotificationState {
    low_battery_notified: bool,     // Have we sent low battery notification?
    critical_battery_notified: bool, // Have we sent critical battery notification?
}

// ============================================================================
// SYSFS READING FUNCTIONS
// ============================================================================

/// Read a sysfs file and return its contents as a trimmed string
fn read_sysfs_file(path: &str) -> io::Result<String> {
    fs::read_to_string(path)
        .map(|s| s.trim().to_string())
}

/// Read a sysfs file and parse it as a u64
fn read_sysfs_u64(path: &str) -> io::Result<u64> {
    read_sysfs_file(path)?
        .parse::<u64>()
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))
}

/// Read a sysfs file and parse it as a u8
fn read_sysfs_u8(path: &str) -> io::Result<u8> {
    read_sysfs_file(path)?
        .parse::<u8>()
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))
}

/// Read a sysfs file and parse it as a boolean (0=false, 1=true)
fn read_sysfs_bool(path: &str) -> io::Result<bool> {
    read_sysfs_file(path)
        .map(|s| s == "1")
}

// ============================================================================
// BATTERY STATUS READING
// ============================================================================

/// Read complete battery status from sysfs
fn read_battery_status() -> io::Result<BatteryStatus> {
    let battery_path = Path::new(BATTERY_PATH);
    let ac_path = Path::new(AC_ADAPTER_PATH);

    // Validate battery device exists
    if !battery_path.exists() {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            format!("Battery device not found at {}", BATTERY_PATH)
        ));
    }

    // Read battery attributes
    let capacity = read_sysfs_u8(&format!("{}/capacity", BATTERY_PATH))?;
    let status = read_sysfs_file(&format!("{}/status", BATTERY_PATH))?;
    let charge_now = read_sysfs_u64(&format!("{}/charge_now", BATTERY_PATH))?;
    let charge_full = read_sysfs_u64(&format!("{}/charge_full", BATTERY_PATH))?;
    let current_now = read_sysfs_u64(&format!("{}/current_now", BATTERY_PATH))?;
    let voltage_now = read_sysfs_u64(&format!("{}/voltage_now", BATTERY_PATH))?;

    // Read AC adapter status (may not exist on all systems)
    let ac_online = if ac_path.exists() {
        read_sysfs_bool(&format!("{}/online", AC_ADAPTER_PATH)).unwrap_or(false)
    } else {
        // Fallback: infer from battery status
        status == "Charging" || status == "Full"
    };

    Ok(BatteryStatus {
        capacity,
        status,
        charge_now,
        charge_full,
        current_now,
        voltage_now,
        ac_online,
    })
}

// ============================================================================
// BATTERY STATISTICS CALCULATION
// ============================================================================

/// Calculate battery statistics (power draw, time remaining)
fn calculate_battery_stats(status: &BatteryStatus) -> BatteryStats {
    // Power draw in watts = (current_µA * voltage_µV) / 1,000,000,000,000
    let power_draw_watts = (status.current_now as f64 * status.voltage_now as f64) / 1_000_000_000_000.0;

    // Time remaining estimation (only when discharging)
    let time_remaining_mins = if status.status == "Discharging" && status.current_now > 0 {
        // Time = (charge_now µAh / current_now µA) * 60 minutes
        let hours = status.charge_now as f64 / status.current_now as f64;
        let minutes = (hours * 60.0) as u32;
        Some(minutes)
    } else {
        None
    };

    BatteryStats {
        power_draw_watts,
        time_remaining_mins,
    }
}

// ============================================================================
// NOTIFICATION FUNCTIONS
// ============================================================================

/// Send a desktop notification using notify-send
fn send_notification(title: &str, body: &str, urgency: &str) -> io::Result<()> {
    let output = Command::new("notify-send")
        .arg("--app-name=battery-monitor")
        .arg("--urgency")
        .arg(urgency)
        .arg("--category")
        .arg("battery")
        .arg("--icon")
        .arg("battery-caution")
        .arg(title)
        .arg(body)
        .output()?;

    if !output.status.success() {
        eprintln!("notify-send failed: {}", String::from_utf8_lossy(&output.stderr));
    }

    Ok(())
}

/// Format time remaining as human-readable string
fn format_time_remaining(minutes: u32) -> String {
    let hours = minutes / 60;
    let mins = minutes % 60;

    if hours > 0 {
        format!("{}h {}m", hours, mins)
    } else {
        format!("{}m", mins)
    }
}

/// Send low battery notification (9% threshold)
fn notify_low_battery(status: &BatteryStatus, stats: &BatteryStats) -> io::Result<()> {
    let mut body = format!("Battery at {}% - Please plug in your charger!", status.capacity);

    // Add power draw
    body.push_str(&format!("\nPower draw: {:.1}W", stats.power_draw_watts));

    // Add time remaining if available
    if let Some(mins) = stats.time_remaining_mins {
        body.push_str(&format!(" | Time left: ~{}", format_time_remaining(mins)));
    }

    send_notification(
        "Low Battery Warning",
        &body,
        "critical"
    )
}

/// Send critical battery notification (5% threshold)
fn notify_critical_battery(status: &BatteryStatus, stats: &BatteryStats) -> io::Result<()> {
    let mut body = format!("CRITICAL: Battery at {}%! System will shutdown soon!", status.capacity);

    // Add power draw
    body.push_str(&format!("\nPower: {:.1}W", stats.power_draw_watts));

    // Add time remaining if available
    if let Some(mins) = stats.time_remaining_mins {
        body.push_str(&format!(" | ~{} remaining", format_time_remaining(mins)));
    }

    send_notification(
        "CRITICAL Battery Level",
        &body,
        "critical"
    )
}

// ============================================================================
// NOTIFICATION STATE MANAGEMENT
// ============================================================================

/// Update notification state based on current battery status
fn update_notification_state(
    status: &BatteryStatus,
    stats: &BatteryStats,
    state: &mut NotificationState,
) -> io::Result<()> {
    let is_discharging = status.status == "Discharging" && !status.ac_online;

    // Reset notification state when battery is charging or above reset threshold
    if status.ac_online || status.capacity >= RESET_THRESHOLD {
        if state.low_battery_notified || state.critical_battery_notified {
            eprintln!("[INFO] Battery recovering: {}% (AC: {})",
                     status.capacity, status.ac_online);
            state.low_battery_notified = false;
            state.critical_battery_notified = false;
        }
        return Ok(());
    }

    // Critical battery notification (5% and below)
    if is_discharging && status.capacity <= CRITICAL_BATTERY_THRESHOLD {
        // Always send critical notifications (persistent nagging)
        notify_critical_battery(status, stats)?;
        state.critical_battery_notified = true;
        eprintln!("[CRITICAL] Battery at {}% - Critical notification sent", status.capacity);
        return Ok(());
    }

    // Low battery notification (9% and below, but above critical)
    if is_discharging && status.capacity <= LOW_BATTERY_THRESHOLD {
        // Always send low battery notifications (persistent nagging)
        notify_low_battery(status, stats)?;
        state.low_battery_notified = true;
        eprintln!("[WARNING] Battery at {}% - Low battery notification sent", status.capacity);
        return Ok(());
    }

    Ok(())
}

// ============================================================================
// MAIN MONITORING LOOP
// ============================================================================

/// Main battery monitoring function
fn monitor_battery(shutdown_flag: Arc<AtomicBool>) -> io::Result<()> {
    eprintln!("[INFO] Battery monitor started");
    eprintln!("[INFO] Monitoring: {}", BATTERY_PATH);
    eprintln!("[INFO] Low battery threshold: {}%", LOW_BATTERY_THRESHOLD);
    eprintln!("[INFO] Critical battery threshold: {}%", CRITICAL_BATTERY_THRESHOLD);
    eprintln!("[INFO] Poll interval: {}s", POLL_INTERVAL_SECS);

    let mut notification_state = NotificationState::default();

    // Verify battery device exists on startup
    if !Path::new(BATTERY_PATH).exists() {
        eprintln!("[ERROR] Battery device not found at {}", BATTERY_PATH);
        eprintln!("[ERROR] This monitor is designed for Samsung Galaxy Book5 Pro");
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            "Battery device not found"
        ));
    }

    // Main monitoring loop
    while !shutdown_flag.load(Ordering::Relaxed) {
        match read_battery_status() {
            Ok(status) => {
                let stats = calculate_battery_stats(&status);

                // Log status (verbose mode for systemd journal)
                eprintln!(
                    "[STATUS] Battery: {}% | Status: {} | AC: {} | Power: {:.1}W",
                    status.capacity,
                    status.status,
                    if status.ac_online { "Yes" } else { "No" },
                    stats.power_draw_watts
                );

                if let Some(mins) = stats.time_remaining_mins {
                    eprintln!("[STATUS] Estimated time remaining: {}", format_time_remaining(mins));
                }

                // Update notification state and send notifications if needed
                if let Err(e) = update_notification_state(&status, &stats, &mut notification_state) {
                    eprintln!("[ERROR] Failed to send notification: {}", e);
                }
            }
            Err(e) => {
                eprintln!("[ERROR] Failed to read battery status: {}", e);
            }
        }

        // Sleep for poll interval (with early exit on shutdown signal)
        for _ in 0..POLL_INTERVAL_SECS {
            if shutdown_flag.load(Ordering::Relaxed) {
                break;
            }
            thread::sleep(Duration::from_secs(1));
        }
    }

    eprintln!("[INFO] Battery monitor shutting down gracefully");
    Ok(())
}

// ============================================================================
// MAIN ENTRY POINT
// ============================================================================

fn main() {
    // Set up signal handling for graceful shutdown
    let shutdown_flag = Arc::new(AtomicBool::new(false));

    // Register SIGTERM and SIGINT handlers
    flag::register(SIGTERM, Arc::clone(&shutdown_flag))
        .expect("Failed to register SIGTERM handler");
    flag::register(SIGINT, Arc::clone(&shutdown_flag))
        .expect("Failed to register SIGINT handler");

    eprintln!("=============================================================");
    eprintln!("  Samsung Galaxy Book5 Pro Battery Monitor");
    eprintln!("  Version: 0.1.0");
    eprintln!("  Platform: Linux (Wayland/Hyprland)");
    eprintln!("  Notification Daemon: swaync");
    eprintln!("=============================================================");

    // Run the battery monitor
    if let Err(e) = monitor_battery(shutdown_flag) {
        eprintln!("[FATAL] Battery monitor failed: {}", e);
        std::process::exit(1);
    }

    eprintln!("[INFO] Battery monitor exited successfully");
}
