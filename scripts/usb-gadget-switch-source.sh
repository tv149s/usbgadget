#!/usr/bin/env bash
set -euo pipefail

PROFILE_DIR=/etc/usb-gadget-source.d
CFG=/etc/default/usb-gadget-source
MODE=${1:-}

log() {
  echo "[usb-gadget-switch] $*"
}

if [[ -z "$MODE" ]]; then
  echo "Usage: $0 testsrc|usbcam" >&2
  exit 2
fi

PROFILE="$PROFILE_DIR/${MODE}.conf"
if [[ ! -f "$PROFILE" ]]; then
  echo "Unknown mode: $MODE" >&2
  exit 2
fi

cp "$PROFILE" "$CFG"
log "Applied $PROFILE -> $CFG"

if [[ "$MODE" == testsrc* ]]; then
  systemctl reset-failed usb-gadget-source.service >/dev/null 2>&1 || true
  systemctl enable --now usb-gadget-source.service >/dev/null 2>&1 || true
else
  systemctl stop usb-gadget-source.service >/dev/null 2>&1 || true
  systemctl reset-failed usb-gadget-source.service >/dev/null 2>&1 || true
fi

systemctl restart usb-gadget-stream.service >/dev/null 2>&1 || true
