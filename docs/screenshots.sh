#!/bin/bash
# Retake the README screenshots into docs/images/.
#
#   docs/screenshots.sh [overview] [drawer] [app]     (default: all three)
#
# Overview and the drawer capture the whole focused monitor, and they show
# every page, the scratchpad and every minimized window. Run this on a desktop
# with nothing private on it. The drawer needs at least one minimized window.
# The Bento app is captured on a fresh empty page so only the wallpaper shows
# through it; you're taken back to where you were afterwards.
set -euo pipefail

repo=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd -P)
out="$repo/docs/images"
plugin=io.github.benjaminsehl.bento
settle=1.2   # seconds for a view to finish animating in

for cmd in grim hyprctl jq omarchy-shell; do
  command -v "$cmd" >/dev/null || { echo "missing $cmd" >&2; exit 1; }
done

monitor=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')
go() { hyprctl dispatch "hl.dsp.focus({ workspace = \"$1\" })" >/dev/null; }
hide() { omarchy-shell shell hide "$plugin" >/dev/null 2>&1 || true; sleep 0.5; }

shoot_view() { # view file
  hide
  "$repo/bin/bento" "$1" >/dev/null
  sleep "$settle"
  grim -o "$monitor" "$out/$2"
  hide
  echo "wrote docs/images/$2"
}

shoot_app() {
  local back empty geometry pane
  back=$(hyprctl activeworkspace -j | jq -r .id)
  empty=$(( $(hyprctl workspaces -j | jq '[.[].id] | max') + 1 ))
  go "$empty"
  sleep 0.5
  for pane in trackpad; do
    "$repo/bin/bento" preferences "$pane" >/dev/null
    sleep "$settle"
    geometry=$(hyprctl clients -j | jq -r '.[] | select(.title == "Bento") | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"' | head -1)
    [[ -n $geometry ]] || { echo "the Bento app didn't open" >&2; hide; break; }
    grim -g "$geometry" "$out/app-$pane.png"
    echo "wrote docs/images/app-$pane.png"
  done
  hide
  go "$back"
}

(( $# )) || set -- overview drawer app
for what in "$@"; do
  case $what in
    overview) shoot_view overview overview.png ;;
    drawer)
      if [[ $(hyprctl clients -j | jq '[.[] | select(.workspace.name == "special:minimized")] | length') == 0 ]]; then
        echo "skipping the drawer: minimize a window or two first (⌘M)" >&2
      else
        shoot_view drawer drawer.png
      fi ;;
    app) shoot_app ;;
    *) echo "unknown shot: $what" >&2; exit 2 ;;
  esac
done
