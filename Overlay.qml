import QtQuick
import Quickshell
import Quickshell.Io
import "expose"
import "drawer"
import "prefs"

// omac's one overlay entry point, with three views:
//   {"view": "expose"}       every page, the scratchpad and minimized windows
//   {"view": "drawer"}       just the minimized windows, dropping from the top
//   {"view": "preferences"}  the omac app
// Summoning while open switches view. Hyprland is told which view is open
// (_G.omac_view), so gestures can close what they opened.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property bool opened: expose.opened || drawer.opened || preferences.opened
  readonly property string view: expose.opened ? "expose" : (drawer.opened ? "drawer" : (preferences.opened ? "preferences" : ""))

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) {}
    var want = payload.view || "expose"
    if (want !== "expose" && expose.opened) expose.close()
    if (want !== "drawer" && drawer.opened) drawer.close()
    if (want !== "preferences" && preferences.opened) preferences.close()
    if (want === "drawer") drawer.open(payloadJson)
    else if (want === "preferences") preferences.open(payloadJson)
    else expose.open(payloadJson)
  }

  function close() {
    expose.close()
    drawer.close()
    preferences.close()
  }

  function toggle() {
    if (root.opened) close()
    else open("{}")
  }

  // For the shell's `call` IPC, and testing.
  function activeWindowIndex() { return expose.activeWindowIndex() }
  function activate(index) { expose.activate(Number(index)) }

  function tellHyprland() {
    hyprState.command = ["hyprctl", "eval", "_G.omac_view = " + (root.view ? JSON.stringify(root.view) : "nil")]
    hyprState.running = true
  }
  onViewChanged: tellHyprland()
  Component.onDestruction: Quickshell.execDetached(["hyprctl", "eval", "_G.omac_view = nil"])

  Process { id: hyprState }

  Expose {
    id: expose
    shell: root.shell
    manifest: root.manifest
  }

  Drawer {
    id: drawer
    shell: root.shell
    manifest: root.manifest
  }

  Preferences {
    id: preferences
    shell: root.shell
    manifest: root.manifest
  }
}
