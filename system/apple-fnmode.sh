#!/bin/bash
# Apple keyboards: top row sends Mac functions (brightness, Mission Control,
# Spotlight, dictation, media, volume) without fn; fn + key gives F1–F12.
# The Magic Keyboard doesn't need it: Bento gives its plain F-keys the Mac
# functions, and with this they'd need fn.
#
#   sudo system/apple-fnmode.sh          Mac top row       (fnmode=1)
#   sudo system/apple-fnmode.sh --undo   F-keys first      (fnmode=2, Omarchy's default)
#
# Applies now and on every boot. Writes /etc/modprobe.d/hid_apple.conf, the
# file Omarchy's installer created with fnmode=2.

set -euo pipefail

mode=1
[[ ${1-} == "--undo" ]] && mode=2

[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }

echo "options hid_apple fnmode=$mode" > /etc/modprobe.d/hid_apple.conf
if [[ -w /sys/module/hid_apple/parameters/fnmode ]]; then
  echo "$mode" > /sys/module/hid_apple/parameters/fnmode
fi

echo "hid_apple fnmode=$mode (now and on boot)"
