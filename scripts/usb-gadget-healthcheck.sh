#!/usr/bin/env bash
set -euo pipefail

CFG_FILE=/etc/default/usb-gadget
SOURCE_CFG_FILE=/etc/default/usb-gadget-source
HEALTH_LOG_FILE=/var/log/usb-gadget-healthcheck.log

ENABLE_UVC=0
SOURCE_DEV=/dev/video43
SOURCE_SIZE=640x480
SOURCE_FPS=30
VS61_WINDOW=2
VS61_FAIL_THRESHOLD=20

if [[ -f "$CFG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CFG_FILE"
fi

if [[ -f "$SOURCE_CFG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$SOURCE_CFG_FILE"
fi

log() {
  echo "[usb-gadget-healthcheck] $*"
}

mkdir -p "$(dirname "$HEALTH_LOG_FILE")"
touch "$HEALTH_LOG_FILE"

persist_log() {
  local level="$1"
  shift
  local msg="$*"
  printf '%s [%s] %s\n' "$(date '+%F %T')" "$level" "$msg" >> "$HEALTH_LOG_FILE"
}

fail() {
  log "FAIL: $*"
  persist_log "FAIL" "$*"
  FAILED=1
}

warn() {
  log "WARN: $*"
  persist_log "WARN" "$*"
}

FAILED=0

if [[ "${ENABLE_UVC:-0}" -ne 1 ]]; then
  fail "ENABLE_UVC is not 1"
fi

for svc in usb-gadget.service usb-gadget-stream.service; do
  if ! systemctl is-active --quiet "$svc"; then
    fail "$svc is not active"
  fi
done

UPSTREAM=""
if systemctl is-active --quiet usb-video-mixer.service; then
  UPSTREAM="mixer"
elif systemctl is-active --quiet usb-gadget-source.service; then
  UPSTREAM="source"
else
  fail "Neither usb-video-mixer.service nor usb-gadget-source.service is active"
fi

uvc_count="$(pgrep -fc '(^|/)uvc-gadget( |$)')"
if [[ "$uvc_count" -ne 1 ]]; then
  fail "Expected exactly 1 uvc-gadget process, found $uvc_count"
fi

ffmpeg_lines="$(pgrep -fa "ffmpeg.*${SOURCE_DEV}" || true)"
ffmpeg_count="$(printf '%s\n' "$ffmpeg_lines" | sed '/^$/d' | wc -l)"
if [[ "$ffmpeg_count" -ne 1 ]]; then
  fail "Expected exactly 1 ffmpeg writer for ${SOURCE_DEV}, found $ffmpeg_count"
fi

w="${SOURCE_SIZE%x*}"
h="${SOURCE_SIZE#*x}"

if [[ "$UPSTREAM" == "mixer" ]]; then
  if ! printf '%s\n' "$ffmpeg_lines" | grep -q -- "-f v4l2 ${SOURCE_DEV}"; then
    fail "mixer ffmpeg is not writing v4l2 -> ${SOURCE_DEV}"
  fi
  if ! printf '%s\n' "$ffmpeg_lines" | grep -q -- "scale=${w}:${h}"; then
    fail "mixer ffmpeg is not scaling to ${w}:${h}"
  fi
  if ! printf '%s\n' "$ffmpeg_lines" | grep -q -- "pad=${w}:${h}"; then
    fail "mixer ffmpeg is not padding to ${w}:${h}"
  fi
  if ! printf '%s\n' "$ffmpeg_lines" | grep -q -- "-pix_fmt yuyv422"; then
    fail "mixer ffmpeg is not using yuyv422"
  fi
else
  if ! printf '%s\n' "$ffmpeg_lines" | grep -q -- "size=${SOURCE_SIZE}:rate=${SOURCE_FPS}"; then
    fail "ffmpeg on ${SOURCE_DEV} is not using ${SOURCE_SIZE}@${SOURCE_FPS}"
  fi
fi

if command -v v4l2-ctl >/dev/null 2>&1; then
  fmt_out="$(v4l2-ctl -d "$SOURCE_DEV" --get-fmt-video 2>/dev/null || true)"
  if ! printf '%s\n' "$fmt_out" | grep -Eq "Width/Height\s*:\s*${w}/${h}"; then
    warn "${SOURCE_DEV} current format is not ${SOURCE_SIZE} (v4l2-ctl)"
  fi
  if ! printf '%s\n' "$fmt_out" | grep -Eq "Pixel Format\s*:\s*'YUYV'"; then
    warn "${SOURCE_DEV} current Pixel Format is not YUYV (v4l2-ctl)"
  fi
fi

vs61_count="$(journalctl -k --since "${VS61_WINDOW} min ago" --no-pager | grep -c 'VS request completed with status -61' || true)"
if [[ "$vs61_count" -gt "$VS61_FAIL_THRESHOLD" ]]; then
  fail "Detected $vs61_count VS -61 errors in the last ${VS61_WINDOW} minutes (threshold ${VS61_FAIL_THRESHOLD})"
elif [[ "$vs61_count" -gt 0 ]]; then
  warn "Detected $vs61_count VS -61 errors in the last ${VS61_WINDOW} minutes"
fi

if [[ "$FAILED" -ne 0 ]]; then
  log "Health check failed"
  exit 1
fi

log "PASS: services active, upstream=${UPSTREAM}, single writer, ${SOURCE_SIZE}@${SOURCE_FPS}, VS-61 count=${vs61_count} in last ${VS61_WINDOW} min"
exit 0
