import QtQuick
import Quickshell
import Quickshell.Io

// The plugin's one overlay entry point, with two views:
//   {"view": "expose"}  every page, the scratchpad and minimized windows
//   {"view": "drawer"}  just the minimized windows, dropping from the top
// Summoning while open switches view. Hyprland is told which view is open
// (_G.pages_view), so gestures can close what they opened.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property bool opened: expose.opened || drawer.opened
  readonly property string view: expose.opened ? "expose" : (drawer.opened ? "drawer" : "")

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) {}
    if (payload.view === "drawer") {
      if (expose.opened) expose.close()
      drawer.open(payloadJson)
    } else {
      if (drawer.opened) drawer.close()
      expose.open(payloadJson)
    }
  }

  function close() {
    expose.close()
    drawer.close()
  }

  function toggle() {
    if (root.opened) close()
    else open("{}")
  }

  // Used by the shell's `call` IPC and for testing.
  function activeWindowIndex() { return expose.activeWindowIndex() }
  function activate(index) { expose.activate(Number(index)) }

  function tellHyprland() {
    hyprState.command = ["hyprctl", "eval", "_G.pages_view = " + (root.view ? JSON.stringify(root.view) : "nil")]
    hyprState.running = true
  }
  onViewChanged: tellHyprland()
  Component.onDestruction: Quickshell.execDetached(["hyprctl", "eval", "_G.pages_view = nil"])

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
}
