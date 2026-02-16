# UVC test status and issues

Date: 2026-02-16

## Current status

- HID keyboard/mouse and CDC ACM are enumerating again after Pi reboot.
- UVC enumerates, but source stability depends on the selected input.

## Source results

### USB camera source (/dev/video0)

- Image appears in Windows Camera.
- Long-run stability not yet fully tested (risk of Pi freeze observed in earlier runs).

### Local test source (v4l2loopback /dev/video43)

- Intermittent black screen.
- Logs show the source format sometimes flips to `BGR4` instead of `YUYV`.
- When format is `BGR4`, uvc-gadget fails to start streaming.

## Symptoms and errors

- Windows Camera freezes or shows black screen while uvc-gadget is running.
- `usb-gadget-stream` logs show `STREAM ON` followed quickly by `STREAM OFF` when host stops streaming.
- Kernel logs contain repeated `uvc: VS request completed with status -61` and `uvc_function_set_alt(...)` messages.

## Current configuration (relevant)

- UVC output: `/dev/video2` or `/dev/video3` (auto-detected)
- UVC format: YUYV 640x480
- UVC buffers: 16
- Source size: 640x480
- Source fps: 30 (reverted from 15 for compatibility)
- Stream service scheduling: Nice=-10, RR priority 10
- Loopback options: `exclusive_caps=1`
- Loopback control: `keep_format=1` and `sustain_framerate=1`

## Hypotheses

- Windows Camera stops streaming if the device only exposes 15 fps.
- Local source instability is likely due to v4l2loopback format switching to `BGR4`.
- USB camera source is more reliable but may cause system freeze under load.

## Next steps

1. Long-run test USB camera source to confirm stability and confirm no Pi freeze.
2. Harden local test source:
   - Enforce YUYV format persistently.
   - Add a watchdog to reset format if it changes.
   - Verify loopback module settings are effective after reload.
3. Compare Windows Camera with alternative clients (OBS/AMCap) to validate host behavior.
