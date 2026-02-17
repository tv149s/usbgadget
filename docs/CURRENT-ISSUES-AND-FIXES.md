# Current issues and fixes (2026-02-16)

This document records the issues encountered during the new SD card bring-up
and the fixes or recommended actions.

## Issue 1: Boot config reverts to host mode

Symptoms:
- /proc/device-tree/soc/usb@7e980000/status is "disabled" after reboot
- /sys/class/udc empty
- /dev/hidg* and /dev/ttyGS0 missing
- Host does not enumerate gadget functions

Fix / actions:
1) Ensure /boot/firmware/config.txt matches peripheral mode:
   - [cm4] #otg_mode=1
   - [cm5] #dtoverlay=dwc2,dr_mode=host
   - [all] dtoverlay=dwc2,dr_mode=peripheral
2) Ensure /boot/firmware/cmdline.txt contains:
   - modules-load=dwc2,libcomposite
3) Disable boot-time rewrite by cloud-init (if present):
   - /etc/cloud/cloud.cfg.d/90-disable-raspberry-pi.cfg
4) Add audit rules to track unexpected writes:
   - /boot/firmware/config.txt (bootcfg)
   - /boot/firmware/cmdline.txt (bootcmd)
5) Reboot and verify UDC nodes appear.

Status:
- Peripheral mode successfully enabled after forcing config.txt and rebooting.
- UDC and gadget nodes are present on the new SD card.

## Issue 2: Host shows "Unknown USB Device"

Symptoms:
- UDC and gadget nodes exist
- Host still shows "Unknown USB Device"

Fix / actions:
1) Enable and start the UVC stream service:
   - systemctl enable --now usb-gadget-stream.service
2) Replug USB or refresh the host device list.
3) If still unknown, collect logs:
   - journalctl -u usb-gadget-stream.service -b --no-pager | tail -n 200
   - dmesg | grep -i uvc | tail -n 200

Status:
- usb-gadget-stream.service is currently disabled; enabling is the next step.

## Issue 3: UVC instability / -61 storms

Symptoms:
- Repeated "VS request completed with status -61"
- Stream starts then stops immediately

Fix / actions:
1) Reduce bandwidth requirements:
   - MJPEG 640x480 or lower FPS
2) Verify streaming parameters match host capacity:
   - streaming_maxpacket=1024
   - interval=1
3) Capture usbmon and kernel logs when storms occur.

Status:
- See UVC analysis and stability documents for details.

## Related documents
- docs/NEW-SD-PROMPT.md
- docs/REBOOT-REQUIRED-CHANGES.md
- docs/UVC-ANALYSIS.md
- docs/BOOTCFG-REWRITE-ISSUE-20260216.md
