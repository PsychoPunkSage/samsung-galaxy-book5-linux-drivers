#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Installation script for Samsung Galaxy Book5 Pro Battery Monitor
#
# This script will:
# 1. Build the Rust binary in release mode (with custom thresholds if specified)
# 2. Install the binary to ~/.local/bin/
# 3. Install the systemd service to ~/.config/systemd/user/
# 4. Enable and start the service
# 5. Verify the installation
#
# Usage: ./install.sh [OPTIONS]
#   -l, --low NUM         Low battery threshold (default: 9)
#   -c, --critical NUM    Critical battery threshold (default: 5)
#   -r, --reset NUM       Reset threshold - clears state when above (default: 15)
#   -p, --poll NUM        Poll interval in seconds (default: 60)
#   -h, --help            Show this help message

set -e  # Exit on error

# Default configuration values
LOW_THRESHOLD="${LOW_THRESHOLD:-9}"
CRITICAL_THRESHOLD="${CRITICAL_THRESHOLD:-5}"
RESET_THRESHOLD="${RESET_THRESHOLD:-15}"
POLL_INTERVAL="${POLL_INTERVAL:-60}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Usage function
show_help() {
    echo "Samsung Galaxy Book5 Pro Battery Monitor - Installation"
    echo ""
    echo "Usage: ./install.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -l, --low NUM         Low battery threshold % (default: 9)"
    echo "  -c, --critical NUM    Critical battery threshold % (default: 5)"
    echo "  -r, --reset NUM       Reset notification state when above % (default: 15)"
    echo "  -p, --poll NUM        Poll interval in seconds (default: 60)"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./install.sh                           # Use defaults (9%, 5%, 60s)"
    echo "  ./install.sh -l 15 -c 10               # Low at 15%, critical at 10%"
    echo "  ./install.sh --low 20 --poll 30       # Low at 20%, poll every 30s"
    echo ""
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -l|--low)
            LOW_THRESHOLD="$2"
            shift 2
            ;;
        -c|--critical)
            CRITICAL_THRESHOLD="$2"
            shift 2
            ;;
        -r|--reset)
            RESET_THRESHOLD="$2"
            shift 2
            ;;
        -p|--poll)
            POLL_INTERVAL="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate thresholds
if [[ ! "$LOW_THRESHOLD" =~ ^[0-9]+$ ]] || [ "$LOW_THRESHOLD" -gt 100 ]; then
    echo "Error: Low threshold must be a number 0-100"
    exit 1
fi
if [[ ! "$CRITICAL_THRESHOLD" =~ ^[0-9]+$ ]] || [ "$CRITICAL_THRESHOLD" -gt 100 ]; then
    echo "Error: Critical threshold must be a number 0-100"
    exit 1
fi
if [ "$CRITICAL_THRESHOLD" -ge "$LOW_THRESHOLD" ]; then
    echo "Error: Critical threshold ($CRITICAL_THRESHOLD) must be less than low threshold ($LOW_THRESHOLD)"
    exit 1
fi

# Print functions
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo ""
    echo "============================================================="
    echo "  Samsung Galaxy Book5 Pro Battery Monitor - Installation"
    echo "============================================================="
    echo ""
}

# Main installation function
main() {
    print_header

    # Get script directory
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    print_info "Installation directory: $SCRIPT_DIR"

    # Check if we're in the right directory
    if [ ! -f "$SCRIPT_DIR/Cargo.toml" ]; then
        print_error "Cargo.toml not found. Please run this script from the project directory."
        exit 1
    fi

    # Check for Rust toolchain
    print_info "Checking for Rust toolchain..."
    if ! command -v cargo &> /dev/null; then
        print_error "Cargo not found. Please install Rust from https://rustup.rs/"
        exit 1
    fi
    print_success "Rust toolchain found: $(rustc --version)"

    # Check for notify-send
    print_info "Checking for notify-send..."
    if ! command -v notify-send &> /dev/null; then
        print_warning "notify-send not found. Notifications may not work."
        print_warning "Install it with: sudo apt install libnotify-bin"
    else
        print_success "notify-send found"
    fi

    # Check for swaync
    print_info "Checking for swaync..."
    if pgrep -x swaync > /dev/null; then
        print_success "swaync is running"
    else
        print_warning "swaync is not running. Notifications may not be displayed."
    fi

    # Build the project with configured thresholds
    print_info "Building battery-monitor (release mode)..."
    print_info "Configuration: low=${LOW_THRESHOLD}%, critical=${CRITICAL_THRESHOLD}%, reset=${RESET_THRESHOLD}%, poll=${POLL_INTERVAL}s"
    cd "$SCRIPT_DIR"
    LOW_THRESHOLD="$LOW_THRESHOLD" \
    CRITICAL_THRESHOLD="$CRITICAL_THRESHOLD" \
    RESET_THRESHOLD="$RESET_THRESHOLD" \
    POLL_INTERVAL="$POLL_INTERVAL" \
    cargo build --release
    print_success "Build completed"

    # Verify binary exists
    if [ ! -f "$SCRIPT_DIR/target/release/battery-monitor" ]; then
        print_error "Binary not found after build. Build may have failed."
        exit 1
    fi

    # Get binary size
    BINARY_SIZE=$(du -h "$SCRIPT_DIR/target/release/battery-monitor" | cut -f1)
    print_info "Binary size: $BINARY_SIZE"

    # Create installation directories
    print_info "Creating installation directories..."
    mkdir -p "$HOME/.local/bin"
    mkdir -p "$HOME/.config/systemd/user"
    print_success "Directories created"

    # Install binary
    print_info "Installing binary to ~/.local/bin/battery-monitor..."
    cp "$SCRIPT_DIR/target/release/battery-monitor" "$HOME/.local/bin/battery-monitor"
    chmod +x "$HOME/.local/bin/battery-monitor"
    print_success "Binary installed"

    # Install systemd service
    print_info "Installing systemd service..."
    cp "$SCRIPT_DIR/battery-monitor.service" "$HOME/.config/systemd/user/battery-monitor.service"
    print_success "Service file installed"

    # Reload systemd user daemon
    print_info "Reloading systemd user daemon..."
    systemctl --user daemon-reload
    print_success "Systemd daemon reloaded"

    # Enable the service
    print_info "Enabling battery-monitor service..."
    systemctl --user enable battery-monitor.service
    print_success "Service enabled (will start on login)"

    # Start the service
    print_info "Starting battery-monitor service..."
    systemctl --user start battery-monitor.service

    # Wait a moment for service to start
    sleep 2

    # Check service status
    if systemctl --user is-active --quiet battery-monitor.service; then
        print_success "Service started successfully"
    else
        print_error "Service failed to start. Check status with: systemctl --user status battery-monitor"
        exit 1
    fi

    # Display installation summary
    echo ""
    echo "============================================================="
    echo "  Installation Summary"
    echo "============================================================="
    echo ""
    echo "  Binary location:  ~/.local/bin/battery-monitor"
    echo "  Service file:     ~/.config/systemd/user/battery-monitor.service"
    echo "  Service status:   $(systemctl --user is-active battery-monitor.service)"
    echo ""
    echo "  Low battery threshold:      ${LOW_THRESHOLD}%"
    echo "  Critical battery threshold: ${CRITICAL_THRESHOLD}%"
    echo "  Reset threshold:            ${RESET_THRESHOLD}%"
    echo "  Poll interval:              ${POLL_INTERVAL} seconds"
    echo ""
    echo "============================================================="
    echo "  Useful Commands"
    echo "============================================================="
    echo ""
    echo "  View logs (live):           journalctl --user -u battery-monitor -f"
    echo "  View logs (last 50 lines):  journalctl --user -u battery-monitor -n 50"
    echo "  Check service status:       systemctl --user status battery-monitor"
    echo "  Stop service:               systemctl --user stop battery-monitor"
    echo "  Restart service:            systemctl --user restart battery-monitor"
    echo "  Disable service:            systemctl --user disable battery-monitor"
    echo ""
    echo "  Run manually (testing):     ~/.local/bin/battery-monitor"
    echo ""
    print_success "Installation complete!"
    echo ""

    # Offer to show logs
    read -p "Would you like to view the service logs now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        print_info "Displaying last 20 log lines (Ctrl+C to exit)..."
        echo ""
        journalctl --user -u battery-monitor -n 20 --no-pager
    fi
}

# Run main function
main "$@"
