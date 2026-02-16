#!/usr/bin/env bash
set -euo pipefail

G=/sys/kernel/config/usb_gadget/pi4g
CFG_FILE=/etc/default/usb-gadget
VIDEO_FORMATS_FILE=/etc/usb-gadget-video-formats.conf
VIDEO_FORMATS_USER_FILE=/boot/usb-gadget-video-formats.conf

ENABLE_ACM=1
ENABLE_HID=0
ENABLE_HID_MOUSE=1
ENABLE_UVC=0

if [[ -f "$CFG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CFG_FILE"
fi

log() {
  echo "[usb-gadget] $*"
}

safe_link() {
  local src="$1"
  local dst="$2"
  if [[ -L "$dst" ]]; then
    local current
    current="$(readlink "$dst" || true)"
    if [[ "$current" != "$src" ]]; then
      rm -f "$dst"
      ln -s "$src" "$dst"
    fi
    return
  fi
  rm -rf "$dst" 2>/dev/null || true
  ln -s "$src" "$dst"
}

remove_link_if_exists() {
  local path="$1"
  if [[ -L "$path" ]]; then
    rm -f "$path"
  fi
}

remove_configfs_tree() {
  local root="$1"
  [[ -d "$root" ]] || return 0

  find "$root" -depth -type l -exec rm -f {} + 2>/dev/null || true
  find "$root" -depth -type d -exec rmdir {} + 2>/dev/null || true
}

setup_core() {
  mkdir -p "$G"
  mkdir -p "$G/strings/0x409"
  mkdir -p "$G/configs/c.1/strings/0x409"

  echo 0x1d6b > "$G/idVendor"
  echo 0x0104 > "$G/idProduct"
  echo 0x0102 > "$G/bcdDevice"
  echo 0x0200 > "$G/bcdUSB"
  echo 0xEF > "$G/bDeviceClass"
  echo 0x02 > "$G/bDeviceSubClass"
  echo 0x01 > "$G/bDeviceProtocol"
  echo 0x40 > "$G/bMaxPacketSize0"

  local serial="0123456789"
  if [[ -r /sys/firmware/devicetree/base/serial-number ]]; then
    serial="$(tr -d '\0' < /sys/firmware/devicetree/base/serial-number)"
  fi

  echo "$serial" > "$G/strings/0x409/serialnumber"
  echo "Raspberry Pi" > "$G/strings/0x409/manufacturer"
  echo "Pi USB Gadget" > "$G/strings/0x409/product"
  echo "Config 1" > "$G/configs/c.1/strings/0x409/configuration"
  echo 250 > "$G/configs/c.1/MaxPower"
}

setup_acm() {
  mkdir -p "$G/functions/acm.usb0"
  safe_link "$G/functions/acm.usb0" "$G/configs/c.1/acm.usb0"
}

setup_hid_keyboard() {
  mkdir -p "$G/functions/hid.usb0"
  echo 1 > "$G/functions/hid.usb0/protocol"
  echo 1 > "$G/functions/hid.usb0/subclass"
  echo 8 > "$G/functions/hid.usb0/report_length"
  printf '\x05\x01\x09\x06\xa1\x01\x05\x07\x19\xe0\x29\xe7\x15\x00\x25\x01\x75\x01\x95\x08\x81\x02\x95\x01\x75\x08\x81\x01\x95\x05\x75\x01\x05\x08\x19\x01\x29\x05\x91\x02\x95\x01\x75\x03\x91\x01\x95\x06\x75\x08\x15\x00\x25\x65\x05\x07\x19\x00\x29\x65\x81\x00\xc0' > "$G/functions/hid.usb0/report_desc"
  safe_link "$G/functions/hid.usb0" "$G/configs/c.1/hid.usb0"
}

setup_hid_mouse() {
  mkdir -p "$G/functions/hid.usb1"
  echo 2 > "$G/functions/hid.usb1/protocol"
  echo 1 > "$G/functions/hid.usb1/subclass"
  echo 4 > "$G/functions/hid.usb1/report_length"
  printf '\x05\x01\x09\x02\xa1\x01\x09\x01\xa1\x00\x05\x09\x19\x01\x29\x03\x15\x00\x25\x01\x95\x03\x75\x01\x81\x02\x95\x01\x75\x05\x81\x01\x05\x01\x09\x30\x09\x31\x09\x38\x15\x81\x25\x7f\x75\x08\x95\x03\x81\x06\xc0\xc0' > "$G/functions/hid.usb1/report_desc"
  safe_link "$G/functions/hid.usb1" "$G/configs/c.1/hid.usb1"
}

cleanup_uvc_tree() {
  remove_link_if_exists "$G/configs/c.1/uvc.usb0"

  local fn
  shopt -s nullglob
  for fn in "$G/functions"/uvc.*; do
    local name
    name="$(basename "$fn")"
    remove_link_if_exists "$G/configs/c.1/$name"
    remove_configfs_tree "$fn"
  done
  shopt -u nullglob
}

pick_formats_file() {
  if [[ -r "$VIDEO_FORMATS_USER_FILE" ]]; then
    echo "$VIDEO_FORMATS_USER_FILE"
    return
  fi
  if [[ -r /boot/firmware/usb-gadget-video-formats.conf ]]; then
    echo /boot/firmware/usb-gadget-video-formats.conf
    return
  fi
  if [[ -r "$VIDEO_FORMATS_FILE" ]]; then
    echo "$VIDEO_FORMATS_FILE"
    return
  fi
  echo ""
}

write_frame_descriptor() {
  local format="$1"
  local name="$2"
  local width="$3"
  local height="$4"
  local frame_dir="$G/functions/uvc.usb0/streaming/$format/$name/${height}p"

  mkdir -p "$frame_dir"
  echo "$width" > "$frame_dir/wWidth"
  echo "$height" > "$frame_dir/wHeight"
  echo 333333 > "$frame_dir/dwDefaultFrameInterval"
  echo $((width * height * 80)) > "$frame_dir/dwMinBitRate"
  echo $((width * height * 160)) > "$frame_dir/dwMaxBitRate"

  if [[ "$format" == "mjpeg" ]]; then
    echo $((width * height * 2)) > "$frame_dir/dwMaxVideoFrameBufferSize"
  else
    echo $((width * height * 2)) > "$frame_dir/dwMaxVideoFrameBufferSize"
  fi

  cat > "$frame_dir/dwFrameInterval" <<'EOF'
333333
400000
666666
1000000
EOF
}

setup_uvc() {
  modprobe usb_f_uvc || true
  cleanup_uvc_tree

  if [[ ! -e /dev/video0 ]]; then
    log "Camera device /dev/video0 not found, continue with UVC placeholder-capable setup"
  fi

  local formats_file
  formats_file="$(pick_formats_file)"

  mkdir -p "$G/functions/uvc.usb0/control/header/h"
  mkdir -p "$G/functions/uvc.usb0/control/class/fs"
  mkdir -p "$G/functions/uvc.usb0/control/class/ss"
  safe_link "$G/functions/uvc.usb0/control/header/h" "$G/functions/uvc.usb0/control/class/fs/h"
  safe_link "$G/functions/uvc.usb0/control/header/h" "$G/functions/uvc.usb0/control/class/ss/h"

  if [[ -e "$G/functions/uvc.usb0/streaming_maxpacket" ]]; then
    echo 1024 > "$G/functions/uvc.usb0/streaming_maxpacket"
  fi
  if [[ -e "$G/functions/uvc.usb0/streaming_mult" ]]; then
    echo 1 > "$G/functions/uvc.usb0/streaming_mult"
  fi
  if [[ -e "$G/functions/uvc.usb0/streaming_maxburst" ]]; then
    echo 0 > "$G/functions/uvc.usb0/streaming_maxburst"
  fi
  if [[ -e "$G/functions/uvc.usb0/streaming_interval" ]]; then
    echo 1 > "$G/functions/uvc.usb0/streaming_interval"
  fi

  local configured_count=0
  if [[ -n "$formats_file" ]]; then
    while read -r format width height; do
      [[ -z "${format:-}" ]] && continue
      [[ "${format:0:1}" == "#" ]] && continue
      if [[ "$format" != "mjpeg" && "$format" != "uncompressed" ]]; then
        continue
      fi
      if [[ ! "$width" =~ ^[0-9]+$ || ! "$height" =~ ^[0-9]+$ ]]; then
        continue
      fi
      local hdr
      hdr="${format:0:1}"
      log "Enable UVC format ${width}x${height} ($format)"
      write_frame_descriptor "$format" "$hdr" "$width" "$height"
      configured_count=$((configured_count + 1))
    done < "$formats_file"
  fi

  if [[ "$configured_count" -eq 0 ]]; then
    log "No valid formats file found, fallback to uncompressed 640x480"
    write_frame_descriptor uncompressed u 640 480
  fi

  mkdir -p "$G/functions/uvc.usb0/streaming/header/h"
  mkdir -p "$G/functions/uvc.usb0/streaming/class/fs"
  mkdir -p "$G/functions/uvc.usb0/streaming/class/hs"
  mkdir -p "$G/functions/uvc.usb0/streaming/class/ss"

  if [[ -d "$G/functions/uvc.usb0/streaming/mjpeg/m" ]]; then
    safe_link "$G/functions/uvc.usb0/streaming/mjpeg/m" "$G/functions/uvc.usb0/streaming/header/h/m"
  fi
  if [[ -d "$G/functions/uvc.usb0/streaming/uncompressed/u" ]]; then
    safe_link "$G/functions/uvc.usb0/streaming/uncompressed/u" "$G/functions/uvc.usb0/streaming/header/h/u"
  fi

  safe_link "$G/functions/uvc.usb0/streaming/header/h" "$G/functions/uvc.usb0/streaming/class/fs/h"
  safe_link "$G/functions/uvc.usb0/streaming/header/h" "$G/functions/uvc.usb0/streaming/class/hs/h"
  safe_link "$G/functions/uvc.usb0/streaming/header/h" "$G/functions/uvc.usb0/streaming/class/ss/h"

  safe_link "$G/functions/uvc.usb0" "$G/configs/c.1/uvc.usb0"
  [[ -L "$G/configs/c.1/uvc.usb0" ]]
}

ensure_default_formats_file() {
  mkdir -p /etc

  if [[ ! -s "$VIDEO_FORMATS_FILE" ]]; then
    cat > "$VIDEO_FORMATS_FILE" <<'EOF'
# format width height
uncompressed 640 480
EOF
  fi
}

main() {
  local current_udc=""
  local setup_failed=0

  modprobe libcomposite || true
  mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config
  [[ -d /sys/kernel/config/usb_gadget ]] || exit 0

  ensure_default_formats_file
  setup_core

  if [[ -f "$G/UDC" ]]; then
    current_udc="$(cat "$G/UDC" || true)"
    if [[ -n "$current_udc" ]]; then
      echo "" > "$G/UDC"
    fi
  fi

  remove_link_if_exists "$G/configs/c.1/acm.usb0"
  remove_link_if_exists "$G/configs/c.1/hid.usb0"
  remove_link_if_exists "$G/configs/c.1/hid.usb1"
  remove_link_if_exists "$G/configs/c.1/uvc.usb0"

  if [[ "$ENABLE_ACM" -eq 1 ]]; then
    setup_acm
  fi

  if [[ "$ENABLE_HID" -eq 1 ]]; then
    local rc=0
    set +e
    setup_hid_keyboard
    rc=$?
    set -e
    if [[ "$rc" -ne 0 ]]; then
      log "HID keyboard setup failed, keep ACM"
      setup_failed=1
    fi
    if [[ "$ENABLE_HID_MOUSE" -eq 1 ]]; then
      set +e
      setup_hid_mouse
      rc=$?
      set -e
      if [[ "$rc" -ne 0 ]]; then
        log "HID mouse setup failed, keep ACM"
        setup_failed=1
      fi
    fi
  fi

  if [[ "$ENABLE_UVC" -eq 1 ]]; then
    local rc=0
    set +e
    setup_uvc
    rc=$?
    set -e
    if [[ "$rc" -ne 0 ]]; then
      log "UVC setup failed, keep ACM"
      setup_failed=1
    fi
  else
    cleanup_uvc_tree
  fi

  if [[ "$setup_failed" -eq 1 ]]; then
    remove_link_if_exists "$G/configs/c.1/hid.usb0"
    remove_link_if_exists "$G/configs/c.1/hid.usb1"
    cleanup_uvc_tree
    setup_acm || true
  fi

  if [[ -f "$G/UDC" ]]; then
    if [[ -n "$current_udc" ]]; then
      echo "$current_udc" > "$G/UDC"
    else
      local udc_dev=""
      udc_dev="$(ls /sys/class/udc | head -n 1 || true)"
      if [[ -n "$udc_dev" ]]; then
        echo "$udc_dev" > "$G/UDC"
      fi
    fi
  fi

  udevadm settle -t 5 || true
}

main "$@"