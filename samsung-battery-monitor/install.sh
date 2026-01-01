#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Installation script for Samsung Galaxy Book5 Pro Battery Monitor
#
# This script will:
# 1. Build the Rust binary in release mode
# 2. Install the binary to ~/.local/bin/
# 3. Install the systemd service to ~/.config/systemd/user/
# 4. Enable and start the service
# 5. Verify the installation

set -e  # Exit on error

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

    # Build the project
    print_info "Building battery-monitor (release mode)..."
    cd "$SCRIPT_DIR"
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
    echo "  Low battery threshold:      9%"
    echo "  Critical battery threshold: 5%"
    echo "  Poll interval:              60 seconds"
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
