#!/usr/bin/env bash
set -euo pipefail

log_dir="/var/log/usb-debug"
mkdir -p "$log_dir"

if ! mountpoint -q /sys/kernel/debug; then
  mount -t debugfs debugfs /sys/kernel/debug
fi

if [[ ! -d /sys/kernel/debug/usb/usbmon ]]; then
  modprobe usbmon || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if [[ -d /sys/kernel/debug/usb/usbmon ]]; then
      break
    fi
    sleep 0.5
  done
fi

if [[ ! -d /sys/kernel/debug/usb/usbmon ]]; then
  echo "usbmon debugfs not available" >&2
  exit 1
fi

pids=()

if [[ -r /sys/kernel/debug/usb/usbmon/1u ]]; then
  cat /sys/kernel/debug/usb/usbmon/1u >> "$log_dir/usbmon-1u.log" &
  pids+=("$!")
else
  echo "usbmon 1u not readable" >&2
fi

if [[ -r /sys/kernel/debug/usb/usbmon/2u ]]; then
  cat /sys/kernel/debug/usb/usbmon/2u >> "$log_dir/usbmon-2u.log" &
  pids+=("$!")
else
  echo "usbmon 2u not readable" >&2
fi

if [[ -r /sys/kernel/debug/usb/usbmon/1s ]]; then
  cat /sys/kernel/debug/usb/usbmon/1s >> "$log_dir/usbmon-1s.log" &
  pids+=("$!")
else
  echo "usbmon 1s not readable" >&2
fi

if [[ -r /sys/kernel/debug/usb/usbmon/2s ]]; then
  cat /sys/kernel/debug/usb/usbmon/2s >> "$log_dir/usbmon-2s.log" &
  pids+=("$!")
else
  echo "usbmon 2s not readable" >&2
fi

if [[ -r /sys/kernel/debug/usb/usbmon/1t ]]; then
  cat /sys/kernel/debug/usb/usbmon/1t >> "$log_dir/usbmon-1t.log" &
  pids+=("$!")
else
  echo "usbmon 1t not readable" >&2
fi

if [[ -r /sys/kernel/debug/usb/usbmon/2t ]]; then
  cat /sys/kernel/debug/usb/usbmon/2t >> "$log_dir/usbmon-2t.log" &
  pids+=("$!")
else
  echo "usbmon 2t not readable" >&2
fi

trap 'for pid in "${pids[@]:-}"; do kill "$pid" 2>/dev/null || true; done' TERM INT

for pid in "${pids[@]:-}"; do
  wait "$pid"
done
