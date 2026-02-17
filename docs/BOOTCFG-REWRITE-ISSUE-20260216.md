# Boot config rewrite investigation log (2026-02-16)

## Goal
Bring up the USB gadget stack on the new SD card and stop /boot/firmware/config.txt
from reverting to host mode after reboot.

## Expected target state
- /boot/firmware/config.txt:
  - [cm4] #otg_mode=1
  - [cm5] #dtoverlay=dwc2,dr_mode=host
  - [all] dtoverlay=dwc2,dr_mode=peripheral
- /sys/class/udc shows fe980000.usb
- /dev/hidg0, /dev/hidg1, /dev/ttyGS0 exist
- /dev/video2 exists (UVC gadget node)

## Steps taken
1) Confirm kernel version
- Running kernel: 6.12.62+rpt-rpi-v8

2) Disable boot config rewrites (per docs)
- Created /etc/cloud/cloud.cfg.d/90-disable-raspberry-pi.cfg
- cloud-init is not installed on this image (no services present)

3) Add audit tracking
- Installed auditd and enabled auditd.service
- Added rules to watch:
  - /boot/firmware/config.txt (key: bootcfg)
  - /boot/firmware/cmdline.txt (key: bootcmd)
- Verified audit rules are loaded with auditctl -l

4) Force-write peripheral mode
- Rewrote /boot/firmware/config.txt to set peripheral mode
- Verified file contents immediately after writing

## Results
- After reboot, UDC is present:
  - /sys/class/udc -> fe980000.usb
- Gadget nodes are created:
  - /dev/hidg0, /dev/hidg1, /dev/ttyGS0
  - /dev/video2
- usb-gadget.service is active (exited, success)
- usb-gadget-stream.service remains disabled
- Host shows "Unknown USB Device" after reboot

## Audit observations
- auditd is running and rules are loaded
- No boot-time write events captured by bootcfg/bootcmd after the reboot
- A write by python (sudo) to config.txt was recorded during manual edit

## Current status
- Device mode is active and gadget nodes exist
- Unknown USB Device remains on the host side
- UVC stream service not enabled yet

## Next steps
1) Enable and start UVC stream service:
   - systemctl enable --now usb-gadget-stream.service
2) Replug USB and check host enumeration
3) If still Unknown USB Device, collect:
   - journalctl -u usb-gadget-stream.service -b --no-pager | tail -n 200
   - dmesg | grep -i uvc | tail -n 200
