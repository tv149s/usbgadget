#!/usr/bin/env bash
set -euo pipefail

CFG_FILE=/etc/default/usb-gadget
SOURCE_CFG_FILE=/etc/default/usb-gadget-source
UVC_BIN=${UVC_BIN:-}
UVC_U_DEV=${UVC_U_DEV:-}
UVC_V_DEV=${UVC_V_DEV:-/dev/video0}
SOURCE_DEV=${SOURCE_DEV:-/dev/video43}
PLACEHOLDER_SIZE=${PLACEHOLDER_SIZE:-640x480}
PLACEHOLDER_FPS=${PLACEHOLDER_FPS:-30}
UVC_BUFFERS=${UVC_BUFFERS:-8}

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
  local now
  now="$(date --iso-8601=seconds 2>/dev/null || date)"
  echo "[usb-gadget-stream] $now $*"
}

dump_udc_state() {
  local udc_path state speed
  udc_path="/sys/class/udc/fe980000.usb"
  if [[ -d "$udc_path" ]]; then
    state="$(cat "$udc_path/state" 2>/dev/null || true)"
    speed="$(cat "$udc_path/current_speed" 2>/dev/null || true)"
    log "UDC state=${state:-unknown} speed=${speed:-unknown}"
  fi
}

dump_source_info() {
  local dev="$1"
  if ! command -v v4l2-ctl >/dev/null 2>&1; then
    return 0
  fi
  log "Source $dev v4l2 summary:"
  v4l2-ctl -d "$dev" --all 2>/dev/null | sed 's/^/[usb-gadget-stream]   /' || true
  log "Source $dev v4l2 fmt:"
  v4l2-ctl -d "$dev" --get-fmt-video 2>/dev/null | sed 's/^/[usb-gadget-stream]   /' || true
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
  dump_source_info "$dev"
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

is_capture_dev() {
  local dev="$1"
  if ! command -v v4l2-ctl >/dev/null 2>&1; then
    return 0
  fi
  v4l2-ctl -d "$dev" --all 2>/dev/null | grep -q 'Video Capture'
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

start_uvc_stream() {
  local bin="$1"
  local uvc_dev="$2"
  local src_dev="$3"

  log "Starting uvc-gadget stream: $bin -u $uvc_dev -v $src_dev -n $UVC_BUFFERS"
  exec "$bin" -u "$uvc_dev" -v "$src_dev" -n "$UVC_BUFFERS"
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
    if ! is_capture_dev "$SOURCE_DEV"; then
      log "Source device $SOURCE_DEV is not a video capture node, skip"
    else
    dump_udc_state
    dump_source_info "$SOURCE_DEV"
    if ! wait_for_source_fmt "$SOURCE_DEV" "${SOURCE_SIZE:-640x480}"; then
      exit 1
    fi
    log "Starting stream from external source: $bin -u $uvc_out -v $SOURCE_DEV -n $UVC_BUFFERS"
    local rc=0
    set +e
    "$bin" -u "$uvc_out" -v "$SOURCE_DEV" -n "$UVC_BUFFERS"
    rc=$?
    set -e
    if [[ "$rc" -eq 0 ]]; then
      exit 0
    fi
    log "External source mode failed (rc=$rc), fallback to dummy/placeholder"
    fi
  fi

  if [[ -n "$bin" && -n "$uvc_out" && -e "$uvc_out" && -e "$UVC_V_DEV" && "$UVC_V_DEV" != "$uvc_out" ]]; then
    if ! is_capture_dev "$UVC_V_DEV"; then
      log "Fallback device $UVC_V_DEV is not a video capture node, skip"
      exit 1
    fi
    dump_udc_state
    dump_source_info "$UVC_V_DEV"
    log "Starting stream from fallback source: $bin -u $uvc_out -v $UVC_V_DEV -n $UVC_BUFFERS"
    local rc=0
    set +e
    "$bin" -u "$uvc_out" -v "$UVC_V_DEV" -n "$UVC_BUFFERS"
    rc=$?
    set -e
    if [[ "$rc" -eq 0 ]]; then
      exit 0
    fi
    log "Fallback source mode failed (rc=$rc), continue to dummy/placeholder"
  fi

  if [[ -n "$bin" ]]; then
    log "uvc-gadget present but no usable source device, stop"
    exit 1
  fi

  log "uvc-gadget binary not found, try placeholder"

  if [[ -z "$uvc_out" || ! -e "$uvc_out" ]]; then
    log "No UVC gadget video node found, skip placeholder"
    exit 0
  fi

  start_placeholder_stream "$uvc_out"

  exit 0
}

main "$@"
