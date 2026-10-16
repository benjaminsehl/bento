import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "overview"
import "drawer"
import "prefs"
import "places"

// Bento's one overlay entry point. It stays loaded (manifest keepLoaded), so
// it is listening the moment fingers touch the trackpad.
//
// Views, summoned or sent as events:
//   {"view": "overview"}     every page, the scratchpad and minimized windows
//   {"view": "drawer"}       the minimized windows, hanging from the top
//   {"view": "preferences"}  the Bento app
//
// The drawer and the scratchpad sit on one vertical axis (places/Axis.qml)
// that fingers drag directly. Hyprland forwards the fingers as events
// (hypr/windows.lua), and knows this side is alive from a heartbeat, so it can
// fall back to its own gestures when the shell isn't running.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string pluginId: (manifest && manifest.id) || "io.github.benjaminsehl.bento"
  readonly property bool opened: overview.opened || drawer.opened || preferences.opened
  readonly property string view: overview.opened ? "overview" : (drawer.opened ? "drawer" : (preferences.opened ? "preferences" : ""))

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) {}
    var want = payload.view || "overview"
    if (want !== "overview" && overview.opened) overview.close()
    if (want !== "drawer" && drawer.opened) drawer.close()
    if (want !== "preferences" && preferences.opened) preferences.close()
    if (want === "drawer") drawer.open(payloadJson)
    else if (want === "preferences") preferences.open(payloadJson)
    else overview.open(payloadJson)
  }

  function close() {
    overview.close()
    drawer.close()
    preferences.close()
  }

  function toggle() {
    if (root.opened) close()
    else open("{}")
  }

  // For the shell's `call` IPC, and testing.
  function activeWindowIndex() { return overview.activeWindowIndex() }
  function activate(index) { overview.activate(Number(index)) }

  // ------------------------------------------------------------ Hyprland
  // Run Lua inside Hyprland. A dispatch has to return a dispatcher, so the
  // Lua runs in a function that returns a harmless event.
  function lua(body) {
    Hyprland.dispatch("(function() " + body + " return hl.dsp.event(\"bento>>ack\") end)()")
  }

  function tellHyprland() {
    lua("_G.bento_view = " + (root.view ? JSON.stringify(root.view) : "nil"))
  }
  onViewChanged: {
    tellHyprland()
    if (!root.view && root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  function heartbeat() { lua("_G.bento_shell_seen = os.time()") }
  Timer { interval: 10000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.heartbeat() }
  Component.onDestruction: Quickshell.execDetached(["hyprctl", "eval", "_G.bento_shell_seen = nil; _G.bento_view = nil; "
    + "hl.config({ decoration = { dim_special = " + root.hyprDim + " } })"])

  // Hyprland's look, so the scratchpad's stand-in matches it exactly. Bento
  // fades the page behind the scratchpad itself (places/Scratchpad.qml), so it
  // turns Hyprland's dim off, and puts it back on the way out. A reload puts
  // it back too, so read again then. (Read as 0, it's ours from before: keep
  // the one we have.)
  property real hyprDim: 0.2
  Process {
    id: look
    running: true
    command: ["bash", "-c", "for o in decoration:dim_special general:border_size decoration:rounding general:col.active_border general:col.inactive_border; do hyprctl getoption \"$o\" -j; done | jq -sc ."]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var o = JSON.parse(text)
          function color(g, fallback) {
            var hex = String((g && g.gradient) || "").split(" ")[0]
            return /^[0-9a-fA-F]{8}$/.test(hex) ? "#" + hex : fallback
          }
          if (o[0].float > 0) root.hyprDim = o[0].float
          root.lua("hl.config({ decoration = { dim_special = 0 } })")
          standIn.borderSize = o[1].int
          standIn.rounding = o[2].int
          standIn.activeBorder = color(o[3], standIn.activeBorder)
          standIn.inactiveBorder = color(o[4], standIn.inactiveBorder)
        } catch (e) {}
      }
    }
  }

  // ----------------------------------------------------------- the axis
  property bool scratchOpen: false       // Hyprland is showing the real scratchpad
  property bool scratchSettled: false    // ...and has for a couple of frames

  function scratchpadWindows() {
    var out = [], all = Hyprland.toplevels.values
    for (var i = 0; i < all.length; i++)
      if (all[i].workspace && all[i].workspace.name === "special:scratchpad") out.push(all[i])
    return out
  }

  function refreshPlaces() {
    drawer.refresh()
    standIn.windows = scratchpadWindows()
  }

  function showRealScratchpad(show) { lua("_G.bento.special_now(\"scratchpad\", " + (show ? "true" : "false") + ")") }

  Axis {
    id: axis
    drawerCount: drawer.cards.length
    scratchCount: standIn.windows.length
    onSettled: function(at) {
      if (at === -1 && !root.scratchOpen) root.showRealScratchpad(true)
      if (at !== -1 && root.scratchOpen) root.showRealScratchpad(false)
    }
  }

  // The real scratchpad hides once the stand-in is on screen over it.
  readonly property bool handOver: root.scratchOpen && axis.moving && standIn.ready
  onHandOverChanged: if (root.handOver) root.showRealScratchpad(false)

  onScratchOpenChanged: {
    settleTimer.restart()
    if (!root.scratchOpen) root.scratchSettled = false
    // Opened or closed some other way: follow without animating.
    if (!axis.moving) axis.sync(root.scratchOpen ? -1 : (axis.value < 0 ? 0 : axis.value))
  }
  Timer { id: settleTimer; interval: 34; onTriggered: root.scratchSettled = root.scratchOpen }

  Scratchpad {
    id: standIn
    progress: axis.scratch
    shown: axis.value < -0.0005 && !(root.scratchSettled && !axis.moving)
    realUp: root.scratchOpen
    guarding: root.scratchSettled && !axis.moving && standIn.windows.length > 0
    onOutsideClicked: root.scratchpad("hide")
  }

  function scratchpad(how) {
    refreshPlaces()
    var up = axis.target === -1
    if (how === "toggle") how = up ? "hide" : "show"
    if (how === "show" && standIn.windows.length) { if (overview.opened) overview.close(); axis.to(-1) }
    else if (how === "hide") axis.to(0)
  }

  // ------------------------------------------------------------- events
  property real _dismissTravel: 0
  property bool _dismissing: false

  function pull(phase, a, t) {
    if (phase === "start") {
      // Over Overview or the Bento app, a downward swipe puts them away.
      root._dismissing = overview.opened || preferences.opened
      root._dismissTravel = a
      if (root._dismissing) return
      refreshPlaces()
      axis.begin(a, t)
    } else if (phase === "move") {
      if (root._dismissing) root._dismissTravel += a
      else axis.move(a, t)
    } else if (phase === "end") {
      if (root._dismissing) {
        if (!a && root._dismissTravel > 40) { overview.dismiss(); preferences.close() }
        root._dismissing = false
      } else {
        axis.end(!!a, t)
      }
    }
  }

  // Fingers pinching together: Overview zooms out as they go
  // (hypr/windows.lua). Whatever else is up gives way once it shows.
  function zoom(phase, a, t) {
    if (phase === "start") overview.zoomBegin(a, t)
    else if (phase === "move") {
      overview.zoomMove(a, t)
      if (overview.progress > 0) {
        if (drawer.opened) drawer.close()
        if (preferences.opened) preferences.close()
        if (axis.target === -1) axis.to(0)
      }
    }
    else if (phase === "end") overview.zoomEnd(!!a, t)
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || !event.name) return
      var name = String(event.name)
      if (name === "activespecial") {
        var parts = String(event.data).split(",")
        var mon = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : parts[1]
        if (parts[1] === mon) root.scratchOpen = parts[0] === "special:scratchpad"
        return
      }
      if (name === "openwindow" || name === "closewindow" || name === "movewindowv2") {
        placesTimer.restart()
        return
      }
      if (name === "configreloaded") { look.running = true; root.heartbeat(); return }
      if (name !== "custom") return

      var p = String(event.data).split(">>")
      if (p[0] !== "bento") return
      switch (p[1]) {
        case "pull": root.pull(p[2], Number(p[3]), Number(p[4])); break
        case "zoom": root.zoom(p[2], Number(p[3]), Number(p[4])); break
        case "show": root.open(JSON.stringify({ view: p[2] })); break
        case "hide": root.close(); break
        case "overview": if (overview.opened) overview.dismiss(); else root.open('{"view":"overview"}'); break
        case "drawer": drawer.toggle(); break
        case "scratchpad": root.scratchpad(p[2]); break
        case "lua": root.heartbeat(); root.tellHyprland(); break
      }
    }
  }

  // Window lists settle a moment after Hyprland's events.
  Timer { id: placesTimer; interval: 60; onTriggered: { Hyprland.refreshToplevels(); root.refreshPlaces() } }

  Component.onCompleted: {
    Hyprland.refreshToplevels()
    Hyprland.refreshMonitors()
    initTimer.start()
  }
  // Find out whether the scratchpad is already open.
  Process {
    id: initial
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var mons = JSON.parse(text)
          for (var i = 0; i < mons.length; i++)
            if (mons[i].focused) root.scratchOpen = mons[i].specialWorkspace && mons[i].specialWorkspace.name === "special:scratchpad"
        } catch (e) {}
        root.refreshPlaces()
        axis.sync(root.scratchOpen ? -1 : 0)
      }
    }
  }
  Timer { id: initTimer; interval: 300; onTriggered: initial.running = true }

  // --------------------------------------------------------------- views
  Overview {
    id: overview
    shell: root.shell
    manifest: root.manifest
    hasScratchpadHost: true
    onScratchpadRequested: root.scratchpad("show")
    borderSize: standIn.borderSize
    rounding: standIn.rounding
    activeBorder: standIn.activeBorder
    inactiveBorder: standIn.inactiveBorder
  }

  Drawer {
    id: drawer
    shell: root.shell
    manifest: root.manifest
    axis: axis
  }

  Preferences {
    id: preferences
    shell: root.shell
    manifest: root.manifest
  }
}
