#!/usr/bin/env bash
set -euo pipefail

log_dir="/var/log/usb-debug"
mkdir -p "$log_dir"

while true; do
  ts=$(date +%Y%m%d_%H%M%S)
  journalctl -k -n 200 -o short-iso-precise --no-pager > "$log_dir/kernel-tail-200-$ts.log"
  sleep 5
done
