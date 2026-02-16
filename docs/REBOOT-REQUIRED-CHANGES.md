# Reboot required changes

Date: 2026-02-15

This note lists the changes that require a reboot to take effect on the target SD card.

## Boot configuration changes

File: /boot/firmware/config.txt

- Ensure gadget device mode is enabled under [all]:
  - dtoverlay=dwc2,dr_mode=peripheral

- Host-mode overrides were disabled to avoid conflicts:
  - [cm4] otg_mode=1 was commented out
  - [cm5] dtoverlay=dwc2,dr_mode=host was commented out

File: /boot/firmware/cmdline.txt

- Ensure gadget modules load at boot:
  - modules-load=dwc2,libcomposite

## Cloud-init change (prevents boot config rewrite)

File: /etc/cloud/cloud.cfg.d/90-disable-raspberry-pi.cfg

- Disabled the cloud-init raspberry_pi module so it no longer rewrites
  /boot/firmware/config.txt at boot.

## Kernel/firmware update

- Upgraded kernel packages to 6.12.62 to match the known-good SD card:
  - linux-image-rpi-v8
  - linux-image-rpi-2712
  - linux-image-6.12.62+rpt-rpi-v8
  - linux-image-6.12.62+rpt-rpi-2712
  - related headers and linux-kbuild

## Why reboot is required

Bootloader and kernel read config.txt and cmdline.txt only at boot. Changes to those files do not apply until the system restarts.

## Post-reboot checks

After reboot:

- /sys/class/udc should list fe980000.usb
- /sys/kernel/config/usb_gadget/pi4g/UDC should equal fe980000.usb
- /dev/hidg0, /dev/hidg1, /dev/ttyGS0, and /dev/video* should exist
- usb-gadget.service and usb-gadget-stream.service should be active
