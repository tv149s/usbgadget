# UVC development log and steps

Date: 2026-02-16

## Goal

Bring up UVC on Raspberry Pi 4 gadget, ensure Windows enumerates it, and make the UVC source switchable between a local test stream and a USB camera.

## Baseline

- UDC available and gadget binds.
- HID keyboard/mouse and CDC ACM already working.
- Windows shows "Unknown USB Device" when UVC is enabled with the previous setup.

## Key changes made

### 1) Make UVC descriptors conservative

Files:
- /usr/local/bin/usb-gadget.sh
- scripts/usb-gadget.sh
- /etc/usb-gadget-video-formats.conf
- configs/usb-gadget-video-formats.conf

Actions:
- Set UVC streaming parameters:
  - streaming_maxpacket=1024
  - streaming_mult=1
  - streaming_maxburst=0
  - streaming_interval=1
- Ensure the formats file is not empty; default to `uncompressed 640 480`.
- Re-enable UVC in /etc/default/usb-gadget.

Rationale:
- Windows is sensitive to invalid UVC descriptors. Conservative endpoint settings and a single YUYV format reduce enumeration failures.

### 2) Provide local test stream without enabling UVC

Files:
- /usr/local/bin/usb-gadget-source.sh
- scripts/usb-gadget-source.sh
- /etc/default/usb-gadget-source
- configs/usb-gadget-source

Actions:
- Added `SOURCE_FORCE=1` to allow the test source to run even when UVC is disabled.
- Set up v4l2loopback-based test source at /dev/video43, 640x480@30.

Rationale:
- Allows validating source pipeline independently from UVC enumerations.

### 3) Install v4l2loopback

Status:
- v4l2loopback module was missing after kernel upgrade.

Actions:
- Installed headers for the current RPi kernel and v4l2loopback packages.
- Loaded v4l2loopback and verified /dev/video43 format.

### 4) Add switchable source profiles

Files:
- /etc/usb-gadget-source.d/testsrc.conf
- /etc/usb-gadget-source.d/usbcam.conf
- /etc/usb-gadget-source.d/testsrc-15.conf
- /etc/usb-gadget-source.d/usbcam-15.conf
- /usr/local/bin/usb-gadget-switch-source.sh
- scripts/usb-gadget-switch-source.sh
- configs/source-profiles/*

Actions:
- Added profiles for testsrc and USB camera (full rate and 15 fps).
- Added a switch script that copies the profile to /etc/default/usb-gadget-source and restarts the stream service.

Rationale:
- Enables fast switching between sources and lower-FPS stability testing.

### 5) Install uvc-gadget and fix stream invocation

Files:
- /opt/uvc-webcam (source)
- /usr/local/bin/uvc-gadget
- /usr/local/bin/usb-gadget-stream.sh
- scripts/usb-gadget-stream.sh

Actions:
- Downloaded and built uvc-gadget from peterbay/uvc-gadget (git auth failed for https clone).
- Updated usb-gadget-stream to call uvc-gadget with supported options:
  - `-u <uvc_out> -v <source_dev> -n 2`
- Removed unsupported placeholder flags that caused stream failures.

Rationale:
- The previously used uvc-gadget command-line flags were not supported by this binary.

## Verification

- Windows enumerates the UVC camera and can show the stream.
- Stream can be switched between:
  - testsrc (/dev/video43)
  - USB camera (/dev/video0)

## Known issue

- Pi can freeze shortly after Windows opens the UVC camera.
- Symptom: SSH disconnect, local display frozen, requires power cycle.

Mitigation steps already in place:
- Persistent journald enabled (`/var/log/journal`).
- Added 15 fps profiles to reduce load:
  - testsrc-15 and usbcam-15.

## How to use

Switch sources:

- Test pattern:
  - `sudo /usr/local/bin/usb-gadget-switch-source.sh testsrc`
- USB camera:
  - `sudo /usr/local/bin/usb-gadget-switch-source.sh usbcam`

Lower FPS (stability test):

- Test pattern:
  - `sudo /usr/local/bin/usb-gadget-switch-source.sh testsrc-15`
- USB camera:
  - `sudo /usr/local/bin/usb-gadget-switch-source.sh usbcam-15`

## Next steps

- Reproduce freeze with 15 fps profiles and collect logs with:
  - `sudo journalctl -k -b -1 --no-pager | tail -n 200`
  - `sudo journalctl -u usb-gadget-stream.service -b -1 --no-pager | tail -n 200`
- Analyze whether the freeze is due to bandwidth, CPU, or UVC driver behavior.
