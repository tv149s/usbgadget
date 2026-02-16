#!/usr/bin/env bash
set -euo pipefail

LOG_FILE=/var/log/usb-gadget-watchdog.log
KERNEL_LOG_FILE=/var/log/usb-gadget-watchdog-kernel.log
TOP_LOG_FILE=/var/log/usb-gadget-watchdog-top.log
INTERVAL=${WATCHDOG_INTERVAL:-5}
KERNEL_INTERVAL=${WATCHDOG_KERNEL_INTERVAL:-10}
ROTATE_BYTES=$((5 * 1024 * 1024))
BASELINE_MARK=${WATCHDOG_BASELINE_MARK:-}

rotate_if_needed() {
  local file="$1"
  if [[ -f "$file" ]]; then
    local size
    size=$(stat -c%s "$file" 2>/dev/null || echo 0)
    if [[ "$size" -ge "$ROTATE_BYTES" ]]; then
      mv -f "$file" "${file}.1" 2>/dev/null || true
      : > "$file"
    fi
  fi
}

log_sample() {
  local now uptime load throttled temp volts clock mem_avail swap_free
  now=$(date --iso-8601=seconds)
  uptime=$(cut -d' ' -f1 /proc/uptime)
  load=$(cut -d' ' -f1-3 /proc/loadavg)
  throttled=""
  if command -v vcgencmd >/dev/null 2>&1; then
    throttled=$(vcgencmd get_throttled 2>/dev/null || true)
    temp=$(vcgencmd measure_temp 2>/dev/null || true)
    volts=$(vcgencmd measure_volts core 2>/dev/null || true)
    clock=$(vcgencmd measure_clock arm 2>/dev/null || true)
  fi
  mem_avail=$(awk '/MemAvailable/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
  swap_free=$(awk '/SwapFree/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
  printf '%s uptime=%s load=%s mem_avail_kb=%s swap_free_kb=%s throttled=%s temp=%s volts=%s clock=%s\n' \
    "$now" "$uptime" "$load" "$mem_avail" "$swap_free" "$throttled" "$temp" "$volts" "$clock" >> "$LOG_FILE"
}

log_kernel_tail() {
  local now
  now=$(date --iso-8601=seconds)
  {
    printf '%s\n' "---- $now ----"
    journalctl -k -n 30 --no-pager --output=short-iso-precise 2>/dev/null || true
  } >> "$KERNEL_LOG_FILE"
}

main() {
  touch "$LOG_FILE" "$KERNEL_LOG_FILE" "$TOP_LOG_FILE"
  chmod 0644 "$LOG_FILE" "$KERNEL_LOG_FILE" "$TOP_LOG_FILE" || true

  if [[ -n "$BASELINE_MARK" ]]; then
    local now
    now=$(date --iso-8601=seconds)
    printf '%s baseline=%s\n' "$now" "$BASELINE_MARK" >> "$LOG_FILE"
    printf '%s baseline=%s\n' "$now" "$BASELINE_MARK" >> "$KERNEL_LOG_FILE"
    printf '%s baseline=%s\n' "$now" "$BASELINE_MARK" >> "$TOP_LOG_FILE"
  fi

  local ticks=0
  local ticks_per_kernel
  ticks_per_kernel=$((KERNEL_INTERVAL / INTERVAL))
  if [[ "$ticks_per_kernel" -lt 1 ]]; then
    ticks_per_kernel=1
  fi

  while true; do
    rotate_if_needed "$LOG_FILE"
    rotate_if_needed "$KERNEL_LOG_FILE"
    rotate_if_needed "$TOP_LOG_FILE"
    log_sample
    local load1 throttled_now
    load1=$(cut -d' ' -f1 /proc/loadavg)
    throttled_now=""
    if command -v vcgencmd >/dev/null 2>&1; then
      throttled_now=$(vcgencmd get_throttled 2>/dev/null || true)
    fi
    if awk -v l="$load1" 'BEGIN{exit !(l>1.5)}'; then
      {
        printf '---- %s load_spike ----\n' "$(date --iso-8601=seconds)"
        ps -eo pid,comm,pcpu,pmem --sort=-pcpu | head -n 6
      } >> "$TOP_LOG_FILE"
    elif [[ -n "$throttled_now" && "$throttled_now" != *"0x0" ]]; then
      {
        printf '---- %s throttled ----\n' "$(date --iso-8601=seconds)"
        ps -eo pid,comm,pcpu,pmem --sort=-pcpu | head -n 6
      } >> "$TOP_LOG_FILE"
    fi
    ticks=$((ticks + 1))
    if (( ticks % ticks_per_kernel == 0 )); then
      log_kernel_tail
    fi
    sleep "$INTERVAL"
  done
}

main "$@"
