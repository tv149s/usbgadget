# Development log

Date: 2026-02-15

## Context

- Source of truth is the USB drive contents, copied to /opt/usb-gadget.
- This repo hosts a development mirror of those scripts and configs.

## Steps completed

- Copied scripts, configs, and services into this repository under scripts/, configs/, services/.
- Verified gadget functions include HID keyboard/mouse, CDC ACM, and UVC.
- Enabled peripheral-mode overlay and gadget modules on the running system.

## Current state

- Repository contains the full gadget stack with defaults.
- UDC availability depends on booting with peripheral mode.

## Next steps

- Reboot and verify UDC device appears in /sys/class/udc.
- Decide whether to run via systemd or a local dev launcher.
- Validate UVC stream source pipeline and adjust formats if needed.
