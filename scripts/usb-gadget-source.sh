#!/usr/bin/env bash
set -euo pipefail

CFG_FILE=/etc/default/usb-gadget
SOURCE_CFG_FILE=/etc/default/usb-gadget-source

ENABLE_UVC=0
SOURCE_MODE=${SOURCE_MODE:-testsrc}
SOURCE_URL=${SOURCE_URL:-}
SOURCE_FILE=${SOURCE_FILE:-}
SOURCE_DEV=${SOURCE_DEV:-/dev/video42}
SOURCE_SIZE=${SOURCE_SIZE:-1280x720}
SOURCE_FPS=${SOURCE_FPS:-15}
SOURCE_LABEL=${SOURCE_LABEL:-GadgetSource}
SOURCE_EXCLUSIVE_CAPS=${SOURCE_EXCLUSIVE_CAPS:-0}
SOURCE_FORCE=${SOURCE_FORCE:-0}
SOURCE_PIXFMT=${SOURCE_PIXFMT:-YUYV}

if [[ -f "$CFG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CFG_FILE"
fi

if [[ -f "$SOURCE_CFG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$SOURCE_CFG_FILE"
fi

log() {
  echo "[usb-gadget-source] $*"
}

ensure_loopback() {
  local video_nr
  video_nr="${SOURCE_DEV#/dev/video}"

  if lsmod | grep -q '^v4l2loopback'; then
    if [[ -e "$SOURCE_DEV" ]] && command -v v4l2-ctl >/dev/null 2>&1; then
      if v4l2-ctl -d "$SOURCE_DEV" --all 2>/dev/null | grep -q 'Video Capture'; then
        return 0
      fi
    fi
    modprobe -r v4l2loopback || true
  fi

  modprobe v4l2loopback \
    devices=1 \
    video_nr="$video_nr" \
    card_label="$SOURCE_LABEL" \
    exclusive_caps="$SOURCE_EXCLUSIVE_CAPS" || true

  local i
  for i in $(seq 1 20); do
    if [[ -e "$SOURCE_DEV" ]]; then
      if command -v v4l2-ctl >/dev/null 2>&1; then
        if v4l2-ctl -d "$SOURCE_DEV" --all 2>/dev/null | grep -q 'Video Capture'; then
          return 0
        fi
      else
        return 0
      fi
    fi
    sleep 0.1
  done

  log "Failed to create source device $SOURCE_DEV"
  return 1
}

configure_loopback() {
  if ! command -v v4l2-ctl >/dev/null 2>&1; then
    return 0
  fi

  local w h
  w="${SOURCE_SIZE%x*}"
  h="${SOURCE_SIZE#*x}"

  v4l2-ctl -d "$SOURCE_DEV" --set-ctrl=keep_format=0 >/dev/null 2>&1 || true
  v4l2-ctl -d "$SOURCE_DEV" --set-fmt-video=width="$w",height="$h",pixelformat="$SOURCE_PIXFMT" >/dev/null 2>&1 || true
  v4l2-ctl -d "$SOURCE_DEV" --set-fmt-video-out=width="$w",height="$h",pixelformat="$SOURCE_PIXFMT" >/dev/null 2>&1 || true
  v4l2-ctl -d "$SOURCE_DEV" --set-ctrl=keep_format=1 >/dev/null 2>&1 || true
  v4l2-ctl -d "$SOURCE_DEV" --set-ctrl=sustain_framerate=1 >/dev/null 2>&1 || true
}

wait_for_consumer() {
  local i
  for i in $(seq 1 50); do
    if pgrep -f "uvc-gadget.*-v ${SOURCE_DEV}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

start_testsrc() {
  log "Starting local test source -> $SOURCE_DEV (${SOURCE_SIZE}@${SOURCE_FPS})"
  exec ffmpeg -hide_banner -loglevel warning -re \
    -f lavfi -i "testsrc2=size=${SOURCE_SIZE}:rate=${SOURCE_FPS}" \
    -an -pix_fmt yuyv422 -f v4l2 "$SOURCE_DEV"
}

start_url() {
  if [[ -z "$SOURCE_URL" ]]; then
    log "SOURCE_MODE=url but SOURCE_URL is empty"
    return 1
  fi

  local input_url="$SOURCE_URL"
  if echo "$SOURCE_URL" | grep -Eqi 'youtube\.com|youtu\.be'; then
    if command -v yt-dlp >/dev/null 2>&1; then
      local resolved
      resolved="$(yt-dlp -g --no-warnings --no-playlist "$SOURCE_URL" 2>/dev/null | head -n 1 || true)"
      if [[ -n "$resolved" ]]; then
        input_url="$resolved"
        log "Resolved YouTube URL via yt-dlp"
      else
        log "yt-dlp failed to resolve YouTube URL, fallback to original URL"
      fi
    else
      log "yt-dlp not found, cannot resolve YouTube share URL reliably"
    fi
  fi

  log "Starting URL source -> $SOURCE_DEV"
  exec ffmpeg -hide_banner -loglevel warning -re \
    -fflags +genpts -i "$input_url" \
    -an -vf "fps=${SOURCE_FPS},scale=${SOURCE_SIZE},format=yuyv422" \
    -f v4l2 "$SOURCE_DEV"
}

start_file() {
  if [[ -z "$SOURCE_FILE" ]]; then
    log "SOURCE_MODE=file but SOURCE_FILE is empty"
    return 1
  fi

  log "Starting file source loop -> $SOURCE_DEV"
  exec ffmpeg -hide_banner -loglevel warning -stream_loop -1 -re \
    -i "$SOURCE_FILE" \
    -an -vf "fps=${SOURCE_FPS},scale=${SOURCE_SIZE},format=yuyv422" \
    -f v4l2 "$SOURCE_DEV"
}

main() {
  if [[ "${ENABLE_UVC:-0}" -ne 1 && "${SOURCE_FORCE:-0}" -ne 1 ]]; then
    log "ENABLE_UVC=0 and SOURCE_FORCE=0, skip source service"
    exit 0
  fi

  if [[ "${SOURCE_MODE}" == "off" ]]; then
    log "SOURCE_MODE=off, skip source service"
    exit 0
  fi

  if ! command -v ffmpeg >/dev/null 2>&1; then
    log "ffmpeg not found"
    exit 1
  fi

  ensure_loopback
  configure_loopback

  if wait_for_consumer; then
    log "Detected uvc-gadget consumer on $SOURCE_DEV"
  else
    log "No uvc-gadget consumer detected yet, start source anyway"
  fi

  case "$SOURCE_MODE" in
    testsrc)
      start_testsrc
      ;;
    url)
      start_url
      ;;
    file)
      start_file
      ;;
    *)
      log "Unknown SOURCE_MODE=$SOURCE_MODE, stop source service"
      exit 1
      ;;
  esac
}

main "$@"
