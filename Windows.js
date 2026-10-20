.pragma library

// Quickshell's list of Hyprland windows can keep one that's gone. Its refresh
// adds and updates but never removes, so a window that closes while a refresh
// is in flight comes back from the reply and stays until the shell restarts:
// a grey tile with a generic icon. A real window has a Wayland surface; a
// ghost doesn't.
function live(list) {
  var out = []
  for (var i = 0; i < list.length; i++) if (list[i].wayland) out.push(list[i])
  return out
}
