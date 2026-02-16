# SD card migration notes (working Pi 4 gadget image)

Date: 2026-02-15

This document captures the working SD card state that successfully brings up UDC and the USB gadget stack on Raspberry Pi 4.

## Hardware and kernel

- Model: Raspberry Pi 4 Model B Rev 1.5
- Kernel: 6.12.62+rpt-rpi-v8
- UDC device: fe980000.usb (visible in /sys/class/udc)

## Boot configuration (critical)

File: /boot/firmware/config.txt

- Ensure device mode is enabled under [all]:
  - dtoverlay=dwc2,dr_mode=peripheral
- Do not override with host mode for Pi 4.
- Existing [cm4] and [cm5] sections may be present; they do not apply to Pi 4.

File: /boot/firmware/cmdline.txt

- Ensure gadget modules load at boot:
  - modules-load=dwc2,libcomposite

## Gadget configuration (critical)

File: /etc/default/usb-gadget

- ENABLE_ACM=1
- ENABLE_HID=1
- ENABLE_HID_MOUSE=1
- ENABLE_UVC=1

File: /etc/default/usb-gadget-source

- SOURCE_MODE=testsrc
- SOURCE_DEV=/dev/video43
- UVC_U_DEV=/dev/video2
- SOURCE_SIZE=640x480
- SOURCE_FPS=30

File: /etc/usb-gadget-video-formats.conf

- uncompressed 640 480

## Systemd services

Units:

- /etc/systemd/system/usb-gadget.service
- /etc/systemd/system/usb-gadget-stream.service
- /etc/systemd/system/usb-gadget-source.service
- /etc/systemd/system/usb-video-mixer.service

Enablement state on the working image:

- usb-gadget.service: enabled
- usb-gadget-stream.service: enabled
- usb-gadget-source.service: disabled (can be enabled if needed)
- usb-video-mixer.service: disabled

## Verification checklist

After boot:

- /sys/class/udc contains fe980000.usb
- /sys/kernel/config/usb_gadget/pi4g/UDC equals fe980000.usb
- Device nodes exist:
  - /dev/hidg0, /dev/hidg1
  - /dev/ttyGS0
  - /dev/video* (UVC gadget nodes)

Service status:

- usb-gadget.service active
- usb-gadget-stream.service active

## Migration steps to another SD card

1) Copy gadget scripts to /usr/local/bin:
   - usb-gadget.sh
   - usb-gadget-stream.sh
   - usb-gadget-source.sh
   - usb-video-mixer.sh
   - usb-gadget-healthcheck.sh
   - usb-gadget-webui.py

2) Copy config files to /etc:
   - /etc/default/usb-gadget
   - /etc/default/usb-gadget-source
   - /etc/default/usb-video-mixer
   - /etc/usb-gadget-video-formats.conf

3) Copy systemd units to /etc/systemd/system:
   - usb-gadget.service
   - usb-gadget-stream.service
   - usb-gadget-source.service
   - usb-video-mixer.service

4) Enable required services:
   - systemctl enable usb-gadget.service
   - systemctl enable usb-gadget-stream.service

5) Update boot files:
   - /boot/firmware/config.txt: dtoverlay=dwc2,dr_mode=peripheral
   - /boot/firmware/cmdline.txt: modules-load=dwc2,libcomposite

6) Reboot and verify the checklist above.
