#!/usr/bin/env bash
set -euo pipefail

log_dir="/var/log/usb-debug/triggers"
mkdir -p "$log_dir"

window_s=5
cooldown_us=2000000
last_event_us=0

get_btime() {
  awk '/^btime/ {print $2}' /proc/stat
}

journalctl -k -f -o short-unix -g 'VS request completed with status -61' --no-pager | while read -r line; do
  ts=${line%% *}
  if [[ -z "$ts" ]]; then
    continue
  fi

  sec=${ts%%.*}
  usec=${ts#*.}
  usec=${usec%%[^0-9]*}
  if [[ -z "$usec" || "$usec" == "$ts" ]]; then
    usec=0
  fi
  if (( ${#usec} < 6 )); then
    printf -v usec '%-6s' "$usec"
    usec=${usec// /0}
  elif (( ${#usec} > 6 )); then
    usec=${usec:0:6}
  fi

  if ! [[ "$sec" =~ ^[0-9]+$ ]]; then
    continue
  fi

  btime=$(get_btime)
  event_us=$((sec * 1000000 + usec))
  event_us_since_boot=$((event_us - btime * 1000000))

  if (( event_us_since_boot < 0 )); then
    continue
  fi

  if (( last_event_us > 0 )) && (( event_us_since_boot - last_event_us < cooldown_us )); then
    continue
  fi

  last_event_us=$event_us_since_boot

  start_us=$((event_us_since_boot - window_s * 1000000))
  end_us=$((event_us_since_boot + window_s * 1000000))
  if (( start_us < 0 )); then
    start_us=0
  fi

  stamp=$(date -d "@${sec}" +%Y%m%d_%H%M%S)

  {
    printf 'line=%s\n' "$line"
    printf 'btime=%s\n' "$btime"
    printf 'event_us=%s\n' "$event_us"
    printf 'event_us_since_boot=%s\n' "$event_us_since_boot"
    printf 'start_us=%s\n' "$start_us"
    printf 'end_us=%s\n' "$end_us"
  } > "$log_dir/trigger-$stamp.txt"

  for bus in 1 2; do
    for kind in u s; do
      src="/var/log/usb-debug/usbmon-${bus}${kind}.log"
      if [[ -f "$src" ]]; then
        out="$log_dir/usbmon-${bus}${kind}-${stamp}.log"
        awk -v s="$start_us" -v e="$end_us" '$2>=s && $2<=e' "$src" > "$out"
      fi
    done

    win_u="$log_dir/usbmon-${bus}u-${stamp}.log"
    if [[ -f "$win_u" ]]; then
      grep -E ' C[io]:' "$win_u" > "$log_dir/usbmon-${bus}u-ctl-${stamp}.log" || true
    fi

    txt_src="/var/log/usb-debug/usbmon-${bus}t.log"
    if [[ -f "$txt_src" ]]; then
      tail -n 2000 "$txt_src" > "$log_dir/usbmon-${bus}t-tail-${stamp}.log"
    fi
  done

  since_epoch=$((event_us / 1000000 - window_s))
  until_epoch=$((event_us / 1000000 + window_s))
  kernel_out="$log_dir/kernel-${stamp}.log"
  journalctl -k -o short-iso-precise --since "@${since_epoch}" --until "@${until_epoch}" --no-pager > "$kernel_out"
  if [[ ! -s "$kernel_out" ]]; then
    journalctl -k -n 200 -o short-iso-precise --no-pager > "$log_dir/kernel-tail-${stamp}.log"
  fi

done
