#!/usr/bin/env bash
set -euo pipefail

CFG_FILE=/etc/default/usb-gadget
MIXER_CFG_FILE=/etc/default/usb-video-mixer

ENABLE_UVC=0
MIXER_MODE=testsrc
INPUT_URL=
INPUT_FILE=
INPUT_DEV=/dev/video2
SOURCE_DEV=/dev/video43
OUTPUT_SIZE=640x480
OUTPUT_FPS=30
OUTPUT_PIX_FMT=yuyv422
SOURCE_LABEL=GadgetMixer
SOURCE_EXCLUSIVE_CAPS=0
SCALE_MODE=letterbox
USE_LOW_LATENCY=1

if [[ -f "$CFG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CFG_FILE"
fi

if [[ -f "$MIXER_CFG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$MIXER_CFG_FILE"
fi

log() {
  echo "[usb-video-mixer] $*"
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

  log "Failed to create mixer output device $SOURCE_DEV"
  return 1
}

size_to_wh() {
  local s="$1"
  local w h
  w="${s%x*}"
  h="${s#*x}"
  if [[ -z "$w" || -z "$h" || "$w" == "$s" || "$h" == "$s" ]]; then
    echo "640 480"
    return
  fi
  echo "$w $h"
}

build_filter() {
  local w h
  read -r w h < <(size_to_wh "$OUTPUT_SIZE")

  if [[ "$SCALE_MODE" == "crop" ]]; then
    echo "scale=${w}:${h}:force_original_aspect_ratio=increase,crop=${w}:${h},fps=${OUTPUT_FPS},format=${OUTPUT_PIX_FMT}"
    return
  fi

  echo "scale=${w}:${h}:force_original_aspect_ratio=decrease,pad=${w}:${h}:(ow-iw)/2:(oh-ih)/2:black,fps=${OUTPUT_FPS},format=${OUTPUT_PIX_FMT}"
}

ffmpeg_low_latency_opts() {
  if [[ "$USE_LOW_LATENCY" -eq 1 ]]; then
    echo "-fflags nobuffer -flags low_delay -max_delay 0 -probesize 32768 -analyzeduration 0"
    return
  fi
  echo ""
}

run_testsrc() {
  exec ffmpeg -hide_banner -loglevel warning -nostdin -re \
    -f lavfi -i "testsrc2=size=${OUTPUT_SIZE}:rate=${OUTPUT_FPS}" \
    -an -pix_fmt "$OUTPUT_PIX_FMT" -f v4l2 "$SOURCE_DEV"
}

run_url() {
  if [[ -z "$INPUT_URL" ]]; then
    log "MIXER_MODE=url but INPUT_URL is empty"
    exit 1
  fi

  local vf
  vf="$(build_filter)"
  local low_opts
  low_opts="$(ffmpeg_low_latency_opts)"

  if echo "$INPUT_URL" | grep -q '^rtsp://'; then
    exec ffmpeg -hide_banner -loglevel warning -nostdin \
      -rtsp_transport tcp $low_opts -i "$INPUT_URL" \
      -an -vf "$vf" -pix_fmt "$OUTPUT_PIX_FMT" -f v4l2 "$SOURCE_DEV"
  fi

  exec ffmpeg -hide_banner -loglevel warning -nostdin \
    $low_opts -i "$INPUT_URL" \
    -an -vf "$vf" -pix_fmt "$OUTPUT_PIX_FMT" -f v4l2 "$SOURCE_DEV"
}

run_file() {
  if [[ -z "$INPUT_FILE" ]]; then
    log "MIXER_MODE=file but INPUT_FILE is empty"
    exit 1
  fi

  local vf
  vf="$(build_filter)"
  local low_opts
  low_opts="$(ffmpeg_low_latency_opts)"

  exec ffmpeg -hide_banner -loglevel warning -nostdin -stream_loop -1 -re \
    $low_opts -i "$INPUT_FILE" \
    -an -vf "$vf" -pix_fmt "$OUTPUT_PIX_FMT" -f v4l2 "$SOURCE_DEV"
}

run_v4l2() {
  if [[ ! -e "$INPUT_DEV" ]]; then
    log "MIXER_MODE=v4l2 but INPUT_DEV not found: $INPUT_DEV"
    exit 1
  fi

  local vf
  vf="$(build_filter)"
  local low_opts
  low_opts="$(ffmpeg_low_latency_opts)"

  exec ffmpeg -hide_banner -loglevel warning -nostdin \
    $low_opts -thread_queue_size 64 -f v4l2 -i "$INPUT_DEV" \
    -an -vf "$vf" -pix_fmt "$OUTPUT_PIX_FMT" -f v4l2 "$SOURCE_DEV"
}

main() {
  if [[ "${ENABLE_UVC:-0}" -ne 1 ]]; then
    log "ENABLE_UVC=0, skip mixer"
    exit 0
  fi

  if ! command -v ffmpeg >/dev/null 2>&1; then
    log "ffmpeg not found"
    exit 1
  fi

  ensure_loopback

  case "$MIXER_MODE" in
    testsrc)
      log "Mode=testsrc output=${SOURCE_DEV} ${OUTPUT_SIZE}@${OUTPUT_FPS}"
      run_testsrc
      ;;
    url)
      log "Mode=url output=${SOURCE_DEV} ${OUTPUT_SIZE}@${OUTPUT_FPS}"
      run_url
      ;;
    file)
      log "Mode=file output=${SOURCE_DEV} ${OUTPUT_SIZE}@${OUTPUT_FPS}"
      run_file
      ;;
    v4l2)
      log "Mode=v4l2 output=${SOURCE_DEV} ${OUTPUT_SIZE}@${OUTPUT_FPS}"
      run_v4l2
      ;;
    *)
      log "Unknown MIXER_MODE=$MIXER_MODE, fallback to testsrc"
      run_testsrc
      ;;
  esac
}

main "$@"
