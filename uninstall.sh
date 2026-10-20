#!/bin/bash
# Take Bento out by hand and give back stock Omarchy: turn it off in the shell,
# which puts Omarchy's workspaces back in its place in the bar, then remove
# everything install.sh put in place (bin/bento-cleanup). Disabling or
# removing Bento in Omarchy does all this by itself; this is for when the
# shell isn't running, or you'd rather see it done. The plugin folder stays:
# `omarchy plugin remove io.github.benjaminsehl.bento` deletes it.
#
#   uninstall.sh          your settings stay in ~/.config/bento
#   uninstall.sh --purge  delete them too
#
# The Magic Keyboard fn mode is separate: system/apple-fnmode.sh.

set -euo pipefail

id=io.github.benjaminsehl.bento
# -P: the plugin folder may be a symlink to this checkout.
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)

fail() { echo "bento: $*" >&2; exit 1; }

purge=()
for arg; do
  case $arg in
    --purge) purge=(--purge) ;;
    *) echo "Usage: uninstall.sh [--purge]" >&2; exit 2 ;;
  esac
done

# A tiled display (two halves, one screen) that Bento kept on one stream goes
# back to Omarchy's catch-all rule. Ask how Bento drove it before the cleanup
# deletes the state, to suggest monitors.lua lines that keep it that way.
tiles=$(bash "$repo/bin/bento-cleanup" --tile-hint 2>/dev/null || true)

# The shell is running: let Omarchy turn Bento off, as its own disable would.
# Not running: the cleanup edits shell.json the same way, for its next start.
if omarchy-shell shell listPlugins >/dev/null 2>&1; then
  answer=$(omarchy-shell shell setPluginEnabled "$id" false 2>&1) || fail "the shell didn't answer ($answer); try again"
  case $answer in
    ok) echo "Turned Bento off in Omarchy." ;;
    unknown) echo "Omarchy doesn't list Bento as a plugin; nothing to turn off there." ;;
    *) fail "the shell said: $answer" ;;
  esac
else
  echo "The shell isn't running; taking Bento out of ~/.config/omarchy/shell.json for its next start."
fi

bash "$repo/bin/bento-cleanup" --now "${purge[@]}"

echo
if (( ${#purge[@]} )); then
  echo "Bento is off and Omarchy is back, without your Bento settings."
else
  echo "Bento is off and Omarchy is back. Your settings stay in ~/.config/bento (uninstall.sh --purge deletes them)."
fi
echo "To delete Bento itself: omarchy plugin remove $id"

if [[ -n $tiles ]]; then
  echo
  echo "Stock Omarchy drives both halves of a tiled display at \"preferred\", which"
  echo "can leave it split or black. To keep it on one stream, add to"
  echo "~/.config/hypr/monitors.lua:"
  echo "$tiles"
fi
