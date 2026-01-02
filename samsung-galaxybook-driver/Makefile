# Samsung Galaxy Book Driver - Makefile
# Supports kernel module building, installation, and testing

obj-m += samsung-galaxybook.o

KDIR := /lib/modules/$(shell uname -r)/build
PWD := $(shell pwd)
INSTALL_DIR := /lib/modules/$(shell uname -r)/kernel/drivers/platform/x86

.PHONY: all clean install uninstall load unload reload dkms-install dkms-remove

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
	rm -f *.o *.ko *.mod.c *.mod *.order *.symvers .*.cmd

install: all
	@echo "Installing samsung-galaxybook driver..."
	sudo mkdir -p $(INSTALL_DIR)
	sudo cp samsung-galaxybook.ko $(INSTALL_DIR)/
	sudo depmod -a
	@echo "Driver installed. Load with: sudo modprobe samsung-galaxybook"

uninstall:
	@echo "Uninstalling samsung-galaxybook driver..."
	sudo rm -f $(INSTALL_DIR)/samsung-galaxybook.ko
	sudo depmod -a
	@echo "Driver uninstalled."

load:
	@if ! lsmod | grep -q platform_profile; then \
		sudo modprobe platform_profile; \
	fi
	sudo insmod samsung-galaxybook.ko

unload:
	sudo rmmod samsung_galaxybook 2>/dev/null || true

reload: unload load

status:
	@echo "=== Driver Status ==="
	@lsmod | grep samsung_galaxybook || echo "Driver not loaded"
	@echo ""
	@echo "=== Battery Threshold ==="
	@cat /sys/class/power_supply/BAT1/charge_control_end_threshold 2>/dev/null || echo "Not available"
	@echo ""
	@echo "=== Keyboard Backlight ==="
	@cat /sys/class/leds/samsung-galaxybook::kbd_backlight/brightness 2>/dev/null || echo "Not available"
	@echo ""
	@echo "=== Performance Profile ==="
	@cat /sys/firmware/acpi/platform_profile 2>/dev/null || echo "Not available"
