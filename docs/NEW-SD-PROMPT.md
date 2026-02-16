# New SD Card Development Prompt

Use this prompt to reproduce the current working state of the Raspberry Pi USB gadget stack on a new SD card. The goal is to match the present system behavior and configuration, including logging and analysis tooling.

## Target State
- Raspberry Pi USB gadget enabled in peripheral mode (UDC: fe980000.usb).
- Functions: UVC + HID keyboard/mouse + CDC ACM.
- Services enabled: usb-gadget, usb-gadget-stream, usb-gadget-webui, usb-gadget-watchdog, usb-debug-usbmon, usb-debug-kernel-tail, usb-debug-trigger-capture.
- UVC formats configured via /etc/usb-gadget-video-formats.conf.
- Baseline config preserved.

## Preconditions
- Fresh SD card booted with network/SSH access.
- Working repo clone available (or copy from USB drive) at /home/lei/usbgadget.
- Internet access is optional if you copy binaries and configs locally.

## Prompt (Step-by-step)
1) Confirm hardware and kernel
   - Ensure the board is a Raspberry Pi 4 in peripheral mode.
   - Kernel should be 6.12.62+rpt-rpi-v8 (match known-good state).

2) Boot configuration (critical)
   - Edit /boot/firmware/config.txt:
     - Under [all], set:
       - dtoverlay=dwc2,dr_mode=peripheral
   - Edit /boot/firmware/cmdline.txt:
     - Ensure modules-load=dwc2,libcomposite is present.

3) Disable cloud-init config rewrites
   - /etc/cloud/cloud.cfg.d/90-disable-raspberry-pi.cfg
   - Disable the raspberry_pi module so config.txt is not rewritten at boot.

4) Install scripts and configs
   - Copy scripts to /usr/local/bin (or use the repo path directly if services reference it):
     - usb-gadget.sh
     - usb-gadget-stream.sh
     - usb-gadget-source.sh
     - usb-video-mixer.sh
     - usb-gadget-healthcheck.sh
     - usb-gadget-webui.py
     - usb-debug-usbmon.sh
     - usb-debug-kernel-tail.sh
     - usb-debug-trigger-capture.sh
     - usb-gadget-switch-source.sh
     - usb-gadget-watchdog.sh
   - Copy config files to /etc:
     - /etc/default/usb-gadget
     - /etc/default/usb-gadget-source
     - /etc/default/usb-video-mixer
     - /etc/usb-gadget-video-formats.conf

5) Install systemd units
   - Copy unit files to /etc/systemd/system:
     - usb-gadget.service
     - usb-gadget-stream.service
     - usb-gadget-source.service
     - usb-video-mixer.service
     - usb-gadget-webui.service
     - usb-gadget-watchdog.service
     - usb-debug-usbmon.service
     - usb-debug-kernel-tail.service
     - usb-debug-trigger-capture.service
   - systemctl daemon-reload

6) Enable services (match current state)
   - systemctl enable usb-gadget.service
   - systemctl enable usb-gadget-stream.service
   - systemctl enable usb-gadget-webui.service
   - systemctl enable usb-gadget-watchdog.service
   - systemctl enable usb-debug-usbmon.service
   - systemctl enable usb-debug-kernel-tail.service
   - systemctl enable usb-debug-trigger-capture.service

7) Ensure UVC format config is set
   - Current test plan (MJPEG-only):
     - /etc/usb-gadget-video-formats.conf:
       - mjpeg 640 480
   - Baseline backup exists in repo:
     - /home/lei/usbgadget/configs/baselines/usb-gadget-video-formats.conf.20260216_145642

8) Reboot and verify
   - Reboot the Pi.
   - Verify UDC:
     - /sys/class/udc contains fe980000.usb
     - /sys/kernel/config/usb_gadget/pi4g/UDC == fe980000.usb
   - Verify device nodes:
     - /dev/hidg0, /dev/hidg1, /dev/ttyGS0
     - /dev/video* (gadget nodes)
   - Verify services:
     - systemctl status usb-gadget.service
     - systemctl status usb-gadget-stream.service

9) Optional runtime checks
   - Web UI:
     - usb-gadget-webui should listen on 0.0.0.0:8765
   - Trigger logs:
     - /var/log/usb-debug/triggers/ should populate after -61 events.

## Validation Checklist
- Host PC enumerates HID and CDC ACM.
- UVC device appears in host camera list.
- UVC streaming starts without immediate shutdown loops.

## Rollback
If MJPEG-only fails on the host, revert to baseline:
- cp /home/lei/usbgadget/configs/baselines/usb-gadget-video-formats.conf.20260216_145642 /etc/usb-gadget-video-formats.conf
- Rebind UDC or reboot.
