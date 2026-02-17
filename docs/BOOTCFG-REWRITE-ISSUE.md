# Boot config rewrite issue log

Date: 2026-02-16

## Summary
While following the documented steps to keep /boot/firmware/config.txt in
peripheral mode, the file repeatedly reverts to host mode after reboot.
UDC remains disabled and gadget nodes do not appear.

## Expected target state
- /boot/firmware/config.txt has:
  - [cm4] #otg_mode=1
  - [cm5] #dtoverlay=dwc2,dr_mode=host
  - [all] dtoverlay=dwc2,dr_mode=peripheral
- /sys/class/udc shows fe980000.usb
- /dev/hidg0, /dev/hidg1, /dev/ttyGS0 present

## What was done (per documentation)
1) Disable cloud-init rewrite module
- Created /etc/cloud/cloud.cfg.d/90-disable-raspberry-pi.cfg
  - raspberry_pi:
      disabled: true

2) Add audit rules to track writes
- Installed auditd
- Added rules to watch:
  - /boot/firmware/config.txt (key: bootcfg)
  - /boot/firmware/cmdline.txt (key: bootcmd)
- Verified audit rules are loaded with auditctl -l

3) Set peripheral mode in config.txt
- Edited /boot/firmware/config.txt to:
  - #otg_mode=1
  - #dtoverlay=dwc2,dr_mode=host
  - dtoverlay=dwc2,dr_mode=peripheral

## Result (not successful)
- After reboot, /boot/firmware/config.txt is back to host mode:
  - otg_mode=1
  - dtoverlay=dwc2,dr_mode=host
- /proc/device-tree/soc/usb@7e980000/status remains "disabled"
- /sys/class/udc is empty
- /dev/hidg0 and /dev/hidg1 are missing

## Evidence collected
- Kernel version: 6.12.62+rpt-rpi-v8 (matches required version)
- /boot/firmware is mounted rw on /dev/mmcblk0p1
- cloud-init is not installed (no cloud-init services present)
- auditd is active and rules are loaded
- ausearch for bootcfg/bootcmd after reboot shows no matches

## Open questions
- What process or firmware stage rewrites config.txt back to host mode?
- Is there an external tool (raspi-config or first-boot) restoring defaults?
- Is there another config file being used at boot (alternative config path)?

## Next steps (proposed)
1) Force-write /boot/firmware/config.txt using sudo, then immediately verify.
2) Reboot once and run:
   - sudo ausearch -k bootcfg -ts boot
   - sudo ausearch -k bootcmd -ts boot
3) If still reverting, check for other boot config sources:
   - /boot/firmware/usercfg.txt
   - EEPROM config for alternative config location
4) If a rewrite source is found, disable that service or script.
