import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import ".."

// Drag handles between tiles. Bring the pointer to the gap between two tiled
// windows and a small handle appears there, level with the pointer. Drag it
// and the split follows. A page still starts half and half (Omarchy's dwindle
// layout), and a split you drag stays where you left it (preserve_split).
//
// Each monitor gets a transparent surface that only takes the pointer in thin
// strips over the gaps, so everything else reaches the windows as before.
// Bento moves the split itself, a frame at a time, and stops it short of
// making either side smaller than windows.minTileSize.
Item {
  id: root

  // Something of Bento's is over the page: Overview, the drawer, the scratchpad.
  property bool hidden: false

  Settings { id: settings }
  readonly property bool on: settings.get("windows", "dragResize") === true
  readonly property int minTile: settings.get("windows", "minTileSize") || 320

  // How far into each window the strip reaches past the gap.
  readonly property int reach: 6
  // Tiles further apart than this aren't neighbours.
  readonly property int widestGap: 48

  property bool dragging: false

  function resize(address, dx, dy) {
    Hyprland.dispatch("hl.dsp.window.resize({ x = " + dx + ", y = " + dy + ", relative = true, window = \"address:" + address + "\" })")
  }

  // ------------------------------------------------------------- the gaps
  // Each gap is a stretch of the line between tiles: where it is, which tiles
  // sit either side, and the tile to resize so that line moves. Hyprland's
  // dwindle moves a tile's inner edge when the outer one is on the edge of the
  // page, by however far the resize asks, so the line moves exactly that far.
  function gapsFor(monitor) {
    if (!monitor || !monitor.activeWorkspace) return []
    var mon = monitor.lastIpcObject || {}
    if (mon.specialWorkspace && mon.specialWorkspace.name) return []
    var wsId = monitor.activeWorkspace.id
    var tiles = [], all = Hyprland.toplevels.values
    for (var i = 0; i < all.length; i++) {
      var ipc = all[i].lastIpcObject || {}
      if (!ipc.at || !ipc.size || !ipc.workspace || ipc.workspace.id !== wsId) continue
      if (ipc.floating || ipc.hidden || ipc.mapped === false) continue
      if (ipc.fullscreen > 0) return []
      tiles.push({ address: ipc.address, x: ipc.at[0] - monitor.x, y: ipc.at[1] - monitor.y, w: ipc.size[0], h: ipc.size[1] })
    }
    if (tiles.length < 2) return []

    var page = { x0: Infinity, y0: Infinity, x1: -Infinity, y1: -Infinity }
    tiles.forEach(function(t) {
      page.x0 = Math.min(page.x0, t.x); page.y0 = Math.min(page.y0, t.y)
      page.x1 = Math.max(page.x1, t.x + t.w); page.y1 = Math.max(page.y1, t.y + t.h)
    })

    var gaps = []
    function add(vertical, a, b) {
      // a is left of (or above) b.
      var aEnd = vertical ? a.x + a.w : a.y + a.h
      var bStart = vertical ? b.x : b.y
      var d = bStart - aEnd
      if (d < 0 || d > root.widestGap) return
      var from = vertical ? Math.max(a.y, b.y) : Math.max(a.x, b.x)
      var to = vertical ? Math.min(a.y + a.h, b.y + b.h) : Math.min(a.x + a.w, b.x + b.w)
      if (to - from < 40) return
      var pos = (aEnd + bStart) / 2
      // Stretches of the same line, a tile's gap apart, are one gap.
      for (var g = 0; g < gaps.length; g++) {
        var o = gaps[g]
        if (o.vertical === vertical && Math.abs(o.pos - pos) < 2 && from <= o.to + root.widestGap && to >= o.from - root.widestGap) {
          o.from = Math.min(o.from, from); o.to = Math.max(o.to, to)
          if (o.before.indexOf(a) < 0) o.before.push(a)
          if (o.after.indexOf(b) < 0) o.after.push(b)
          return
        }
      }
      gaps.push({ vertical: vertical, pos: pos, gap: d, from: from, to: to, before: [a], after: [b] })
    }
    for (var p = 0; p < tiles.length; p++)
      for (var q = 0; q < tiles.length; q++)
        if (p !== q) { add(true, tiles[p], tiles[q]); add(false, tiles[p], tiles[q]) }

    return gaps.map(function(g) {
      var v = g.vertical
      function size(t) { return v ? t.w : t.h }
      var target = null
      g.before.forEach(function(t) { if (!target && Math.abs((v ? t.x : t.y) - (v ? page.x0 : page.y0)) < 2) target = t })
      g.after.forEach(function(t) { if (!target && Math.abs((v ? t.x + t.w : t.y + t.h) - (v ? page.x1 : page.y1)) < 2) target = t })
      target = target || g.before[0]
      // How far the line may go each way. A side that's already smaller than
      // the minimum (a crowded page) can still grow.
      var before = Math.min.apply(null, g.before.map(size))
      var after = Math.min.apply(null, g.after.map(size))
      return {
        vertical: v, pos: g.pos, gap: g.gap, from: g.from, to: g.to, target: target.address,
        lo: -Math.max(0, before - root.minTile), hi: Math.max(0, after - root.minTile)
      }
    })
  }

  // ----------------------------------------------------- keeping up to date
  // Windows can move without an event saying so (a keyboard resize), so look
  // again now and then too. Never mid-drag: the handle being dragged would go.
  property int tick: 0
  function refresh() {
    if (root.dragging || !root.on) return
    Hyprland.refreshToplevels()
    Hyprland.refreshMonitors()
    settle.restart()
  }
  Timer { id: settle; interval: 60; onTriggered: if (!root.dragging) root.tick++ }
  Timer { interval: 1000; repeat: true; running: root.on && !root.hidden && !root.dragging; onTriggered: root.refresh() }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = String(event && event.name)
      if (/^(openwindow|closewindow|movewindowv2|workspacev2|focusedmonv2|changefloatingmode|fullscreen|activespecial|activewindowv2|configreloaded)$/.test(name))
        root.refresh()
    }
  }
  Component.onCompleted: root.refresh()
  onOnChanged: root.refresh()
  onHiddenChanged: root.refresh()

  // --------------------------------------------------------- the surfaces
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData
      readonly property var monitor: Hyprland.monitorFor(modelData)

      // A copy, so a refresh mid-hover only rebuilds when something moved.
      property var gaps: []
      function update() {
        var next = (root.on && !root.hidden) ? root.gapsFor(panel.monitor) : []
        if (JSON.stringify(next) !== JSON.stringify(panel.gaps)) panel.gaps = next
      }
      Connections { target: root; function onTickChanged() { panel.update() } function onHiddenChanged() { panel.update() } function onOnChanged() { panel.update() } }

      visible: panel.gaps.length > 0
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      WlrLayershell.namespace: "bento-handles"
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      // The pointer reaches this surface only over the strips.
      mask: Region { id: strips }
      // After the repeater has made the strips for the new gaps.
      onGapsChanged: Qt.callLater(panel.fitMask)
      function fitMask() {
        var old = []
        for (var i = 0; i < strips.regions.length; i++) old.push(strips.regions[i])
        var list = []
        for (var j = 0; j < repeater.count; j++) list.push(stripRegion.createObject(strips, { item: repeater.itemAt(j) }))
        strips.regions = list
        for (var k = 0; k < old.length; k++) old[k].destroy()
      }
      Component { id: stripRegion; Region {} }

      Repeater {
        id: repeater
        model: panel.gaps

        MouseArea {
          id: strip
          required property var modelData
          readonly property var g: modelData
          readonly property real thickness: g.gap + root.reach * 2

          x: g.vertical ? g.pos - thickness / 2 : g.from
          y: g.vertical ? g.from : g.pos - thickness / 2
          width: g.vertical ? thickness : g.to - g.from
          height: g.vertical ? g.to - g.from : thickness

          hoverEnabled: true
          preventStealing: true
          cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

          // Where along the gap the pointer is, and how far the line has been
          // asked to move (want) and has moved (moved).
          property real along: g.vertical ? height / 2 : width / 2
          property real start: 0
          property real want: 0
          property int moved: 0

          function point(mouse) { return g.vertical ? mouse.x + x : mouse.y + y }
          onPositionChanged: function(mouse) {
            along = g.vertical ? mouse.y : mouse.x
            if (pressed) want = Math.max(g.lo, Math.min(g.hi, point(mouse) - start))
          }
          onPressed: function(mouse) {
            root.dragging = true
            start = point(mouse); want = 0; moved = 0
          }
          onReleased: { flush(); root.dragging = false; root.refresh() }
          onCanceled: { flush(); root.dragging = false; root.refresh() }

          // One resize a frame at most.
          function flush() {
            var step = Math.round(want) - moved
            if (step === 0) return
            root.resize(g.target, g.vertical ? step : 0, g.vertical ? 0 : step)
            moved += step
          }
          Timer { interval: 16; repeat: true; running: strip.pressed; onTriggered: strip.flush() }

          // The handle: a pill across the gap, level with the pointer.
          Rectangle {
            readonly property real length: 44
            readonly property real across: 6
            width: g.vertical ? across : length
            height: g.vertical ? length : across
            radius: across / 2
            x: g.vertical ? (strip.width - width) / 2 + strip.want : Math.max(0, Math.min(strip.width - width, strip.along - width / 2))
            y: g.vertical ? Math.max(0, Math.min(strip.height - height, strip.along - height / 2)) : (strip.height - height) / 2 + strip.want
            color: Color.menu.text
            border.width: 1
            border.color: Color.menu.background
            opacity: strip.containsMouse || strip.pressed ? 0.9 : 0
            Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
          }
        }
      }
    }
  }
}
