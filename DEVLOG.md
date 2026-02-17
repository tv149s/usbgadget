# Development log

Date: 2026-02-15

## Context

- Source of truth is the USB drive contents, copied to /opt/usb-gadget.
- This repo hosts a development mirror of those scripts and configs.

## Steps completed

- Copied scripts, configs, and services into this repository under scripts/, configs/, services/.
- Verified gadget functions include HID keyboard/mouse, CDC ACM, and UVC.
- Enabled peripheral-mode overlay and gadget modules on the running system.
- Disabled the cloud-init raspberry_pi module to prevent boot config rewrites.
- Upgraded kernel to 6.12.62 to match the known-good SD card.
- Disabled UVC temporarily (ENABLE_UVC=0) for A/B testing Windows descriptor errors and restarted gadget services.
- Verified on Windows that HID keyboard/mouse and CDC ACM enumerate and the unknown USB device disappears when UVC is disabled.
- Added a local UVC test source config and enabled SOURCE_FORCE to allow the loopback test stream to run even with UVC disabled.
- Installed v4l2loopback DKMS and headers, then started usb-gadget-source with a local test stream on /dev/video43.
- Identified the USB camera on /dev/video0 (capture) and /dev/video1 (metadata-only), and added selectable source profiles plus a switch script at /usr/local/bin/usb-gadget-switch-source.sh.
- Re-enabled UVC, set conservative UVC streaming parameters (maxpacket/mult/maxburst/interval), and ensured a non-empty UVC formats file.
- Installed uvc-gadget from peterbay/uvc-gadget and updated usb-gadget-stream to use its -u/-v options, then verified the stream service runs.
- Verified stream switching: testsrc feeds /dev/video43 and USB camera profile feeds /dev/video0 via uvc-gadget.
- Enabled persistent journald storage and added 15 fps source profiles for stability testing.
- Increased UVC buffer count to 8 and raised usb-gadget-stream priority (Nice=-10) to improve stability.
- Increased UVC buffer count to 16 and enabled RR scheduling (priority 10) for usb-gadget-stream.
- Restored UVC frame intervals to include 30 fps (default 30) and set test source FPS back to 30 for Windows compatibility.
- Switched UVC output selection to auto-detect (cleared UVC_U_DEV) to avoid node changes after rebind.
- Enabled v4l2loopback exclusive caps for the test source to reduce format/REQBUFS errors.
- Added loopback format configuration (force YUYV + keep_format/sustain_framerate) before starting the source.
- Observed unstable UVC streaming with Windows Camera; stream can freeze within seconds to minutes, and host often requests UVC shutdown.
- Using the USB camera source has previously led to a full Pi freeze (SSH loss, local UI frozen) requiring power cycle.

## Current state

- Repository contains the full gadget stack with defaults.
- UDC availability depends on booting with peripheral mode.
- Boot config now stays in peripheral mode after reboot.
- UDC is present: /sys/class/udc shows fe980000.usb and gadget binds.
- HID nodes created: /dev/hidg0 and /dev/hidg1 are present.
- usb-gadget-stream.service is failing because uvc-gadget binary is missing and ffmpeg placeholder output returns EINVAL.
- With UVC disabled, usb-gadget.service is active and usb-gadget-stream.service is inactive.
- Host PC (Windows) no longer shows the unknown USB device when UVC is disabled.
- Gadget video node is /dev/video2 (name: fe980000.usb).
- v4l2-ctl reports /dev/video2 supports YUYV 640x480 output.
- v4l2-ctl reports /dev/video43 (loopback test source) is YUYV 640x480.
- USB camera supports YUYV 640x480 and smaller sizes at 30/15 fps on /dev/video0.

## Boot config rewrite issue (2026-02-16)

- While migrating to the new SD card, /boot/firmware/config.txt repeatedly reverts to host mode after reboot.
- Result: /sys/class/udc remains empty and gadget nodes do not appear.
- Kernel version matches the target: 6.12.62+rpt-rpi-v8.
- /boot/firmware is mounted rw on /dev/mmcblk0p1.

Actions taken:
- Created /etc/cloud/cloud.cfg.d/90-disable-raspberry-pi.cfg to disable the cloud-init raspberry_pi module.
- Installed and enabled auditd; added watches for config.txt and cmdline.txt.
- Attempted to set peripheral mode in config.txt, but it reverted after reboot.

Open questions:
- What process or boot stage rewrites config.txt to host mode?
- Is another config file or boot path being used?

Next steps:
- Force-write config.txt to peripheral mode, verify immediately, reboot, then use ausearch to identify the writer.

## UVC enablement notes

- UVC enumeration on Windows is now successful; the Windows Camera app can receive the stream.
- UVC streaming is provided by /usr/local/bin/uvc-gadget built from peterbay/uvc-gadget.
- usb-gadget-stream now calls uvc-gadget with -u (UVC output) and -v (capture source) and no longer uses unsupported flags.
- UVC formats are constrained to uncompressed 640x480 (YUYV) to keep descriptors and bandwidth conservative.
- Source switching is done via /usr/local/bin/usb-gadget-switch-source.sh and profiles in /etc/usb-gadget-source.d.

## GitHub access notes

- Cloning linux-usb-gadgets/uvc-gadget failed (404). The correct repo was peterbay/uvc-gadget.
- HTTPS git clone from GitHub prompted for credentials and failed because password auth is disabled.
- A tarball download (curl) was used instead; no GitHub credentials were stored on the device.

## Freeze observed

- When Windows opens the UVC camera, the Pi can stream video but may freeze shortly after.
- Symptoms: SSH disconnect, local display frozen, mouse unresponsive; only power cycle recovers.
- Persistent journald was enabled after the freeze, so earlier crash logs were not retained.
- Low-FPS profiles (15 fps) were added to test whether load/bandwidth triggers the freeze.

## Next steps

- Reboot and verify UDC device appears in /sys/class/udc.
- Decide whether to run via systemd or a local dev launcher.
- Validate UVC stream source pipeline and adjust formats if needed.
