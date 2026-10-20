import Quickshell
import Quickshell.Io
import QtQuick

// The plugin's whole job: run install.sh from this folder when the shell
// starts Bento. It hooks hypr/bento.lua into Hyprland and links the helpers,
// and does nothing when they are already in place. The bindings themselves
// live in Hyprland, not here.
//
// When the shell lets go of Bento (disabled, removed, or just a restart), it
// starts bin/bento-cleanup, which waits to see which it was and only cleans up
// after a disable or a remove.
Item {
  id: root

  // The shell sets this after creating the Service, and hands this kept
  // instance a fresh copy on every change to shell.json. Only a new version
  // (after `omarchy plugin update`) is worth another install.sh.
  property var manifest: null
  property string ranFor: ""
  property bool again: false

  readonly property string here: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")).replace(/\/$/, "")
  readonly property string installer: here + "/install.sh"
  // The cleanup runs from install.sh's copy outside the plugin folder, since a
  // remove deletes the folder; the checkout's own copy is for when install.sh
  // never got that far.
  readonly property string stateCleanup: Quickshell.env("HOME") + "/.local/state/bento/bento-cleanup"
  readonly property string repoCleanup: here + "/bin/bento-cleanup"

  function runInstall() {
    if (install.running) again = true
    else install.running = true
  }

  onManifestChanged: {
    if (!manifest) return
    const version = String(manifest.version || "")
    if (ranFor === "") {
      ranFor = version
    } else if (version !== ranFor) {
      ranFor = version
      runInstall()
    }
  }

  Process {
    id: install
    command: ["bash", root.installer]
    stderr: StdioCollector { id: errors }
    onExited: function (code) {
      if (code !== 0) {
        notify.command = ["notify-send", "-u", "critical", "Bento could not install", errors.text.trim() || ("install.sh exited with " + code)]
        notify.running = true
      }
      if (root.again) {
        root.again = false
        Qt.callLater(root.runInstall)
      }
    }
  }

  Process { id: notify }

  Component.onCompleted: runInstall()

  // Detached, so it outlives this Service, and the shell if need be.
  Component.onDestruction: Quickshell.execDetached(["bash", "-c",
    'f=$1; [ -f "$f" ] || f=$2; exec setsid -f bash "$f" --settle </dev/null >/dev/null 2>&1',
    "bento", root.stateCleanup, root.repoCleanup])
}
