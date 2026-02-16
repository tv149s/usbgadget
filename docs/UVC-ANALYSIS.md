# UVC -61 Storm Analysis (2026-02-16)

## Scope
This document summarizes the data captured, the observed symptoms, and the current hypothesis for the recurring UVC "VS request completed with status -61" storms and occasional UDC detach. It also outlines candidate fixes for validation.

## Data Sources
- Kernel log slices from the previous boot (pre-reboot window).
- usb-gadget stream logs from the same window.
- usbmon raw and text windows captured on -61 triggers.

## Key Observations
### 1) set_alt/reset closely precede -61 storms
Multiple cycles show this sequence:
- uvc_function_set_alt(5, 1)
- reset UVC
- 0.8-1.2s later: repeated "VS request completed with status -61"

This pattern repeats at 13:34:26, 14:18:22, 14:25:07, 14:28:55, etc.

### 2) Stream start immediately followed by "Possible USB shutdown"
In usb-gadget-stream logs, right after PROBE/COMMIT and STREAM ON, the process reports:
- "UVC: Possible USB shutdown requested from Host, seen during VIDIOC_DQBUF"
- STREAM OFF and device uninit follow immediately

This suggests that the host rejects the stream or forces a stop immediately after set_alt.

### 3) usbmon windows show no control transfers during -61 bursts
Trigger captures around -61 windows show only isochronous traffic. Control transfers (Ci/Co) are absent in these windows. This implies the -61 errors can be a gadget-side state machine failure after a transition, not necessarily an active control transfer in the same window.

### 4) Current UVC bandwidth parameters are too high for HS with maxpacket=1024
Configured streaming parameters are:
- maxpacket = 1024
- maxburst = 0
- interval = 1
- format = uncompressed 640x480 (YUYV)
- default frame interval = 333333 (30 fps)

Bandwidth requirement for 640x480@30 YUYV:
- frame size = 640 * 480 * 2 = 614400 bytes
- per second = 614400 * 30 = 18432000 bytes/s
- HS isochronous capacity with maxpacket=1024 and interval=1: 1024 * 8000 = 8192000 bytes/s

Result: 640x480@30 is over the available HS isochronous budget, so the host is likely to deny or immediately stop the stream.

## Working Hypothesis
Primary cause (B): control vs stream state mismatch caused by bandwidth rejection.
- Host sets altsetting to start stream.
- Gadget starts V4L2 pipeline, but host immediately requests shutdown (likely bandwidth insufficiency).
- This leaves gadget UVC state machine misaligned, producing -61 storms.

Secondary cause (C): long-run instability or driver race.
- The -61 storms can persist and occasionally lead to UDC detach ("not attached").
- Reboot restores function, indicating a system-level drift or race rather than permanent hardware failure.

## Evidence Timeline (Example: 14:18:22)
- 14:18:22.210 uvc_function_set_alt(5,1)
- 14:18:22.211 reset UVC
- 14:18:22.193 stream PROBE/COMMIT, format set, STREAM ON
- 14:18:22.196 "Possible USB shutdown requested from Host" -> STREAM OFF
- 14:18:23.019 first -61

## Candidate Fix Directions (for validation)
1) Reduce bandwidth while keeping YUYV:
   - Use 10-15 fps as default (frame interval 666666 or 1000000).
   - Or reduce resolution (e.g., 320x240@30).

2) Switch to MJPEG:
   - Same resolution with much lower bandwidth.
   - Avoid host-side immediate shutdown.

3) Increase isochronous capacity if feasible:
   - Adjust maxpacket and mult/maxburst (subject to UDC and host limits).

## Parameter Source Analysis (Root of Mismatch)
The gadget configuration hard-codes isochronous transport parameters in
setup_uvc(), while the format list defines a default 640x480 uncompressed mode.
This combination exceeds HS isochronous bandwidth and likely triggers the host
shutdown behavior observed during VIDIOC_DQBUF.

- UVC transport (hard-coded in setup_uvc):
   - streaming_maxpacket = 1024
   - streaming_interval = 1
   - streaming_maxburst = 0
   - streaming_mult is not present in configfs on this system
- Format list (default):
   - uncompressed 640 480
   - default frame interval: 333333 (30 fps)

HS isochronous capacity with maxpacket=1024 and interval=1 is 8.192 MB/s, while
640x480@30 YUYV requires about 18.4 MB/s. This mismatch can cause the host to
accept set_alt but immediately request shutdown.

## Baseline Preservation and Current Planned Test
Baseline config saved before modifications:
- /home/lei/usbgadget/configs/baselines/usb-gadget-video-formats.conf.20260216_145642

Planned test change (not yet applied to runtime):
- /etc/usb-gadget-video-formats.conf set to:
   - mjpeg 640 480

## Next Steps (Analysis Path)
- Confirm if host rejects stream due to bandwidth by testing with lower fps or MJPEG.
- If storms persist at lower bandwidth, investigate deeper driver race or kernel version issues.

## Notes
- usbmon control packets were not observed during storms, indicating the failure can be in the gadget state machine after a transition rather than during a control transfer.
