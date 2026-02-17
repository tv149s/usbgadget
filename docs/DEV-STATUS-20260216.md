# Development status (2026-02-16)

This document summarizes the latest bring-up work on the new SD card, the
current working state, issues encountered, and the applied fixes.

## Current working state
- Kernel: 6.12.62+rpt-rpi-v8
- UDC: fe980000.usb present in /sys/class/udc
- Gadget nodes:
  - /dev/hidg0, /dev/hidg1, /dev/ttyGS0
  - UVC gadget node: /dev/video2 (name: fe980000.usb)
- Services:
  - usb-gadget.service enabled and active
  - usb-gadget-stream.service enabled and active

## Issues encountered and fixes

### 1) Boot config reverting to host mode
Symptoms:
- /sys/class/udc empty after reboot
- /proc/device-tree/soc/usb@7e980000/status = disabled
- /dev/hidg* and /dev/ttyGS0 missing

Fix:
- Ensure /boot/firmware/config.txt uses peripheral mode:
  - [cm4] #otg_mode=1
  - [cm5] #dtoverlay=dwc2,dr_mode=host
  - [all] dtoverlay=dwc2,dr_mode=peripheral
- Ensure /boot/firmware/cmdline.txt has:
  - modules-load=dwc2,libcomposite
- Added audit rules to track unexpected writes to boot files.

Result:
- After forcing peripheral mode and rebooting, UDC and gadget nodes returned.

### 2) Unknown USB Device after reboot
Symptoms:
- Host shows "Unknown USB Device" even though UDC is present.

Fix:
- Enable and start usb-gadget-stream.service.
- Confirm UVC gadget node and stream source are correct.

Result:
- UVC camera appears again after reboot; HID devices present.

### 3) UVC node mismatch (video2/video3)
Symptoms:
- usb-gadget-stream logs show "VIDIOC_DQEVENT failed: No such device".
- UVC node changed from /dev/video2 to /dev/video3 temporarily.

Fix:
- Detect the current gadget node via /sys/class/video4linux
  and update UVC_U_DEV in /etc/default/usb-gadget-source if needed.

Result:
- After reboot, gadget node stabilized on /dev/video2 and stream runs.

## Current configuration notes
- /etc/default/usb-gadget:
  - ENABLE_UVC=1
  - UVC_BUFFERS=16
- /etc/usb-gadget-video-formats.conf:
  - mjpeg 640 480 (lower bandwidth target)

## Next steps
1) Observe stability; if Unknown USB Device returns, capture:
   - dmesg | grep -iE 'dwc2|udc|gadget|uvc' | tail -n 200
   - journalctl -u usb-gadget-stream.service -b --no-pager | tail -n 200
2) If UVC node changes again, update /etc/default/usb-gadget-source and restart
   usb-gadget-stream.service.
