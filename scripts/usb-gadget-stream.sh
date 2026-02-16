#!/usr/bin/env bash
set -euo pipefail

CFG_FILE=/etc/default/usb-gadget
SOURCE_CFG_FILE=/etc/default/usb-gadget-source
UVC_BIN=${UVC_BIN:-}
UVC_U_DEV=${UVC_U_DEV:-}
UVC_V_DEV=${UVC_V_DEV:-/dev/video1}
SOURCE_DEV=${SOURCE_DEV:-/dev/video43}
PLACEHOLDER_SIZE=${PLACEHOLDER_SIZE:-640x480}
PLACEHOLDER_FPS=${PLACEHOLDER_FPS:-30}

ENABLE_UVC=0
if [[ -f "$CFG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CFG_FILE"
fi

if [[ -f "$SOURCE_CFG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$SOURCE_CFG_FILE"
fi

log() {
  echo "[usb-gadget-stream] $*"
}

wait_for_source_fmt() {
  local dev="$1"
  local size="$2"

  if ! command -v v4l2-ctl >/dev/null 2>&1; then
    return 0
  fi

  local w h
  w="${size%x*}"
  h="${size#*x}"

  local i fmt
  for i in $(seq 1 30); do
    fmt="$(v4l2-ctl -d "$dev" --get-fmt-video 2>/dev/null || true)"
    if printf '%s\n' "$fmt" | grep -Eq "Width/Height\s*:\s*${w}/${h}" \
      && printf '%s\n' "$fmt" | grep -Eq "Pixel Format\s*:\s*'YUYV'"; then
      return 0
    fi
    sleep 0.1
  done

  log "Source device $dev not ready for UVC (${size} YUYV). Current:"
  printf '%s\n' "$fmt" | sed 's/^/[usb-gadget-stream]   /'
  return 1
}

pick_uvc_bin() {
  if [[ -n "$UVC_BIN" && -x "$UVC_BIN" ]]; then
    echo "$UVC_BIN"
    return
  fi

  for candidate in \
    /opt/uvc-webcam/uvc-gadget \
    /usr/local/bin/uvc-gadget \
    /usr/bin/uvc-gadget
  do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return
    fi
  done

  echo ""
}

find_uvc_gadget_dev() {
  local sysnode
  shopt -s nullglob
  for sysnode in /sys/class/video4linux/video*; do
    local name
    name="$(cat "$sysnode/name" 2>/dev/null || true)"
    if echo "$name" | grep -Eqi 'uvc|gadget|fe980000\.usb'; then
      echo "/dev/$(basename "$sysnode")"
      shopt -u nullglob
      return 0
    fi
  done
  shopt -u nullglob
  return 1
}

is_gadget_video_dev() {
  local dev="$1"
  local node
  node="$(basename "$dev")"
  if [[ ! -r "/sys/class/video4linux/$node/name" ]]; then
    return 1
  fi
  local name
  name="$(cat "/sys/class/video4linux/$node/name" 2>/dev/null || true)"
  echo "$name" | grep -Eqi 'uvc|gadget|fe980000\.usb'
}

start_placeholder_stream() {
  local uvc_dev="$1"

  if ! command -v ffmpeg >/dev/null 2>&1; then
    log "ffmpeg not found, cannot start placeholder stream"
    return 1
  fi

  log "Starting placeholder stream to $uvc_dev (${PLACEHOLDER_SIZE}@${PLACEHOLDER_FPS})"
  exec ffmpeg -hide_banner -loglevel warning -re \
    -f lavfi -i "testsrc2=size=${PLACEHOLDER_SIZE}:rate=${PLACEHOLDER_FPS}" \
    -pix_fmt yuyv422 -f v4l2 "$uvc_dev"
}

start_uvc_dummy_stream() {
  local bin="$1"
  local uvc_dev="$2"

  log "Starting uvc-gadget dummy stream to $uvc_dev"
  exec "$bin" -d -f 1 -r 1 -u "$uvc_dev"
}

main() {
  if [[ "${ENABLE_UVC:-0}" -ne 1 ]]; then
    log "ENABLE_UVC=0, skip stream"
    exit 0
  fi

  local bin
  bin="$(pick_uvc_bin)"

  local uvc_out=""
  if [[ -n "$UVC_U_DEV" && -e "$UVC_U_DEV" ]] && is_gadget_video_dev "$UVC_U_DEV"; then
    uvc_out="$UVC_U_DEV"
  fi
  if [[ -z "$uvc_out" ]]; then
    uvc_out="$(find_uvc_gadget_dev || true)"
  fi

  if [[ -n "$bin" && -n "$uvc_out" && -e "$uvc_out" && -e "$SOURCE_DEV" ]]; then
    if ! wait_for_source_fmt "$SOURCE_DEV" "${SOURCE_SIZE:-640x480}"; then
      exit 1
    fi
    log "Starting stream from external source: $bin -f 1 -r 1 -u $uvc_out -v $SOURCE_DEV"
    local rc=0
    set +e
    "$bin" -f 1 -r 1 -u "$uvc_out" -v "$SOURCE_DEV"
    rc=$?
    set -e
    if [[ "$rc" -eq 0 ]]; then
      exit 0
    fi
    log "External source mode failed (rc=$rc), fallback to dummy/placeholder"
  fi

  if [[ -n "$bin" && -n "$uvc_out" && -e "$uvc_out" && -e "$UVC_V_DEV" && "$UVC_V_DEV" != "$uvc_out" ]]; then
    log "Starting stream from fallback source: $bin -f 1 -r 1 -u $uvc_out -v $UVC_V_DEV"
    local rc=0
    set +e
    "$bin" -f 1 -r 1 -u "$uvc_out" -v "$UVC_V_DEV"
    rc=$?
    set -e
    if [[ "$rc" -eq 0 ]]; then
      exit 0
    fi
    log "Fallback source mode failed (rc=$rc), continue to dummy/placeholder"
  fi

  if [[ -n "$bin" ]]; then
    log "uvc-gadget present but source devices missing (U=$UVC_U_DEV V=$UVC_V_DEV), try placeholder"
  else
    log "uvc-gadget binary not found, try placeholder"
  fi

  if [[ -z "$uvc_out" || ! -e "$uvc_out" ]]; then
    log "No UVC gadget video node found, skip placeholder"
    exit 0
  fi

  if [[ -n "$bin" ]]; then
    start_uvc_dummy_stream "$bin" "$uvc_out"
  fi

  start_placeholder_stream "$uvc_out"

  exit 0
}

main "$@"
