# UVC stability investigation

Date: 2026-02-16

## Symptom summary

- Windows Camera freezes the UVC image after a variable time window.
- Freeze duration varies widely (seconds to tens of minutes).
- Pi remains alive during most freezes, but the stream stops refreshing.
- USB camera source has previously caused a full Pi freeze (SSH loss, local UI frozen) requiring power cycle.

## Observations from logs

- `usb-gadget-stream` logs frequently show:
  - `UVC: Possible USB shutdown requested from Host` followed by a clean stream shutdown.
- Kernel logs show repeated:
  - `uvc: VS request completed with status -61`
  - `uvc_function_set_alt(...)` and `reset UVC`

Interpretation:
- Windows host often requests UVC shutdown, which causes uvc-gadget to stop streaming.
- The repeated `status -61` hints at host/device negotiation failures or timing issues.

## Current streaming setup

- UVC output: /dev/video2
- Test source: /dev/video43 (v4l2loopback testsrc)
- USB camera source: /dev/video0
- Format: YUYV 640x480
- Framerate: 15 fps for stability tests
- UVC buffers: 16
- Streaming params: maxpacket=1024, mult=1, maxburst=0, interval=1
- Service priority: Nice=-10, RR scheduling, priority 10

## Stability attempts applied

- Reduced FPS to 15.
- Increased UVC buffers from 2 -> 8 -> 16.
- Raised stream service priority and enabled RR scheduling.
- Enabled persistent journald for post-crash inspection.

## Known risks

- Windows Camera appears to be an aggressive client and may stop stream on minor hiccups.
- USB camera source may induce system-wide freezes.

## Next steps

1. A/B compare sources with identical settings (testsrc-15 vs usbcam-15) and measure freeze times.
2. Add periodic stream watchdog to auto-restart uvc-gadget when host shutdown occurs.
3. Consider moving source generation to a lighter-weight pipeline (avoid ffmpeg if possible).
4. Evaluate UVC bulk mode if supported by the gadget driver, or reduce bandwidth further.
5. Collect kernel logs immediately after any full system freeze (post-reboot).
