import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Exposé: every window at once.
//
// Pages run left to right in dot order, each a column with its windows
// spread out so none overlap. Minimized and scratchpad windows aren't pages,
// so they sit on a quieter shelf below. Click a window to go to it, a
// column to go to that page, or an empty frame at either end for a new page.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property int selected: -1

  readonly property string pluginId: (manifest && manifest.id) || "io.github.benjaminsehl.pages"
  readonly property string backgroundSource: "file://" + Quickshell.env("HOME") + "/.local/state/omarchy/current/background"

  readonly property var monitor: Hyprland.focusedMonitor
  readonly property var targetScreen: {
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++)
      if (monitor && screens[i].name === monitor.name) return screens[i]
    return screens.length ? screens[0] : null
  }

  // Layout metrics, in overlay pixels.
  readonly property real margin: Style.space(56)
  readonly property real gap: Style.space(28)
  readonly property real innerGap: Style.space(16)
  readonly property real ghostWidth: Style.space(44)
  readonly property real dotSize: Style.spaceReal(5)
  readonly property real indicatorHeight: Style.space(28)
  readonly property real captionHeight: Style.space(26)

  property var layout: ({ pages: [], ghosts: [], windows: [], captions: [], shelfY: -1 })

  function open(payloadJson) {
    Hyprland.refreshToplevels()
    Hyprland.refreshWorkspaces()
    root.opened = true
    rebuild()
    root.selected = activeWindowIndex()
    Qt.callLater(function() { keys.forceActiveFocus() })
  }

  function close() { root.opened = false }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened) dismiss()
    else open("{}")
  }

  function dispatch(expr) { Hyprland.dispatch(expr) }
  function q(s) { return JSON.stringify(String(s)) }

  // ----------------------------------------------------------------- model

  function ipcOf(t) { return t.lastIpcObject || {} }

  function readingOrder(list) {
    return list.slice().sort(function(a, b) {
      var A = ipcOf(a).at || [0, 0], B = ipcOf(b).at || [0, 0]
      if (Math.abs(A[1] - B[1]) > 40) return A[1] - B[1]
      return A[0] - B[0]
    })
  }

  function collect() {
    var mon = root.monitor
    var activeId = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
    var pages = [], minimized = [], scratchpad = [], other = []
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var ws = values[i]
      var wins = ws.toplevels.values
      if (ws.id > 0) {
        if (mon && ws.monitor && ws.monitor.name !== mon.name) continue
        if (wins.length === 0 && ws.id !== activeId) continue
        pages.push({ id: ws.id, focused: ws.id === activeId, windows: readingOrder(wins) })
      } else if (ws.name === "special:minimized") {
        minimized = minimized.concat(wins)
      } else if (ws.name === "special:scratchpad") {
        scratchpad = scratchpad.concat(wins)
      } else if (ws.name.indexOf("special:") === 0) {
        other = other.concat(wins)
      }
    }
    pages.sort(function(a, b) { return a.id - b.id })
    return { pages: pages, minimized: minimized, scratchpad: scratchpad, other: other }
  }

  // Fit windows into a box without overlap: try 1..4 columns and keep the
  // arrangement that shows the most window area.
  function pack(wins, bx, by, bw, bh, g, maxScale) {
    var n = wins.length
    if (n === 0) return []
    var best = null
    for (var cols = 1; cols <= Math.min(4, n); cols++) {
      var rows = Math.ceil(n / cols)
      var cw = (bw - g * (cols - 1)) / cols
      var ch = (bh - g * (rows - 1)) / rows
      if (cw <= 0 || ch <= 0) continue
      var rects = [], area = 0
      for (var i = 0; i < n; i++) {
        var size = ipcOf(wins[i]).size || [1600, 1000]
        var s = Math.min(cw / size[0], ch / size[1], maxScale)
        var w = size[0] * s, h = size[1] * s
        var r = Math.floor(i / cols), c = i % cols
        var inRow = Math.min(cols, n - r * cols)
        var rowOffset = (bw - (inRow * cw + (inRow - 1) * g)) / 2
        rects.push({ x: bx + rowOffset + c * (cw + g) + (cw - w) / 2, y: by + r * (ch + g) + (ch - h) / 2, w: w, h: h })
        area += w * h
      }
      if (!best || area > best.area) best = { rects: rects, area: area, rows: rows, ch: ch }
    }
    if (!best) return []
    // Pull the rows together vertically so the group sits centred.
    var used = 0
    for (var j = 0; j < best.rects.length; j++) used = Math.max(used, best.rects[j].y + best.rects[j].h - by)
    var minY = by
    for (var k = 0; k < best.rects.length; k++) minY = Math.min(minY, best.rects[k].y)
    var span = used - (minY - by)
    var shift = (by + (bh - span) / 2) - minY
    for (var m = 0; m < best.rects.length; m++) best.rects[m].y += shift
    return best.rects
  }

  // One row of thumbnails at a fixed height, shrunk to fit the width.
  function shelfRow(wins, x, y, maxW, h, g) {
    var widths = [], total = 0
    for (var i = 0; i < wins.length; i++) {
      var size = ipcOf(wins[i]).size || [1600, 1000]
      var w = h * size[0] / size[1]
      widths.push(w); total += w
    }
    total += g * Math.max(0, wins.length - 1)
    var s = total > maxW ? maxW / total : 1
    var rects = [], cx = x
    for (var j = 0; j < wins.length; j++) {
      var ww = widths[j] * s, hh = h * s
      rects.push({ x: cx, y: y + (h - hh) / 2, w: ww, h: hh })
      cx += ww + g * s
    }
    return { rects: rects, width: cx - x - g * s }
  }

  function rebuild() {
    if (!root.opened || !panel.width) return
    var W = panel.width, H = panel.height
    var data = collect()
    var out = { pages: [], ghosts: [], windows: [], captions: [], shelfY: -1 }

    var shelfGroups = []
    if (data.minimized.length) shelfGroups.push({ name: "Minimized", kind: "minimized", windows: data.minimized })
    if (data.scratchpad.length) shelfGroups.push({ name: "Scratchpad", kind: "scratchpad", windows: data.scratchpad })
    if (data.other.length) shelfGroups.push({ name: "Hidden", kind: "special", windows: data.other })

    var shelfH = shelfGroups.length ? Math.round(H * 0.2) : 0
    var top = root.margin, bottom = H - root.margin - (shelfH ? shelfH + root.gap : 0)

    // Pages, with an empty frame at each end for a new page.
    var n = Math.max(1, data.pages.length)
    var colW = (W - root.margin * 2 - root.ghostWidth * 2 - root.gap * (n + 1)) / n
    var x = root.margin
    out.ghosts.push({ side: "left", x: x, y: top + root.indicatorHeight, w: root.ghostWidth, h: bottom - top - root.indicatorHeight })
    x += root.ghostWidth + root.gap
    for (var p = 0; p < data.pages.length; p++) {
      var page = data.pages[p]
      var col = { id: page.id, focused: page.focused, x: x, y: top, w: colW, h: bottom - top, empty: page.windows.length === 0 }
      out.pages.push(col)
      var rects = pack(page.windows, x + root.innerGap, top + root.indicatorHeight + root.innerGap,
                       colW - root.innerGap * 2, col.h - root.indicatorHeight - root.innerGap * 2, root.innerGap, 0.6)
      for (var i = 0; i < rects.length; i++)
        out.windows.push({ toplevel: page.windows[i], kind: "page", workspaceId: page.id, x: rects[i].x, y: rects[i].y, w: rects[i].w, h: rects[i].h })
      x += colW + root.gap
    }
    out.ghosts.push({ side: "right", x: x, y: top + root.indicatorHeight, w: root.ghostWidth, h: bottom - top - root.indicatorHeight })

    // The shelf: groups side by side, each under a small caption.
    if (shelfH) {
      var sy = H - root.margin - shelfH
      out.shelfY = sy - root.gap / 2
      var groupW = (W - root.margin * 2 - root.gap * (shelfGroups.length - 1)) / shelfGroups.length
      var gx = root.margin
      for (var g = 0; g < shelfGroups.length; g++) {
        var grp = shelfGroups[g]
        out.captions.push({ text: grp.name, x: gx, y: sy })
        var row = shelfRow(grp.windows, gx, sy + root.captionHeight, groupW, shelfH - root.captionHeight, root.innerGap)
        for (var r = 0; r < row.rects.length; r++)
          out.windows.push({ toplevel: grp.windows[r], kind: grp.kind, workspaceId: -1, x: row.rects[r].x, y: row.rects[r].y, w: row.rects[r].w, h: row.rects[r].h })
        gx += groupW + root.gap
      }
    }
    root.layout = out
    if (root.selected >= out.windows.length) root.selected = out.windows.length - 1
  }

  function activeWindowIndex() {
    var active = Hyprland.activeToplevel
    for (var i = 0; i < root.layout.windows.length; i++)
      if (active && String(root.layout.windows[i].toplevel.address) === String(active.address)) return i
    return root.layout.windows.length ? 0 : -1
  }

  // Rebuild while open as windows come and go.
  Timer { id: rebuildSoon; interval: 50; onTriggered: root.rebuild() }
  Connections {
    target: Hyprland
    enabled: root.opened
    function onRawEvent(event) {
      var n = event.name
      if (n.indexOf("window") >= 0 || n.indexOf("workspace") >= 0 || n === "movewindowv2") {
        Hyprland.refreshToplevels()
        rebuildSoon.restart()
      }
    }
  }

  // ----------------------------------------------------------------- actions

  function activate(index) {
    var e = root.layout.windows[index]
    if (!e) return
    var raw = String(e.toplevel.address)
    var addr = "address:" + (raw.indexOf("0x") === 0 ? raw : "0x" + raw)
    if (e.kind === "minimized") {
      var here = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
      dispatch("hl.dsp.window.move({ workspace = " + q(here) + ", window = " + q(addr) + " })")
    }
    dispatch("hl.dsp.focus({ window = " + q(addr) + " })")
    dismiss()
  }

  function goToPage(id) {
    dispatch("hl.dsp.focus({ workspace = " + q(id) + " })")
    dismiss()
  }

  function newPage(side) {
    var pages = root.layout.pages
    if (!pages.length) return dismiss()
    var id = side === "left" ? pages[0].id - 1 : pages[pages.length - 1].id + 1
    if (id < 1) id = pages[0].id // no room on the left; pages.lua will make some
    goToPage(id)
  }

  // Arrow keys move to the nearest window in that direction.
  function move(dx, dy) {
    var list = root.layout.windows
    if (!list.length) return
    if (root.selected < 0) { root.selected = 0; return }
    var cur = list[root.selected]
    var cx = cur.x + cur.w / 2, cy = cur.y + cur.h / 2
    var best = -1, bestScore = Infinity
    for (var i = 0; i < list.length; i++) {
      if (i === root.selected) continue
      var e = list[i]
      var ex = e.x + e.w / 2 - cx, ey = e.y + e.h / 2 - cy
      var along = ex * dx + ey * dy
      if (along <= 1) continue
      var across = Math.abs(ex * dy) + Math.abs(ey * dx)
      var score = along + across * 2
      if (score < bestScore) { bestScore = score; best = i }
    }
    if (best >= 0) root.selected = best
  }

  function appIcon(t) {
    var id = t.wayland ? t.wayland.appId : (ipcOf(t).class || "")
    var entry = id ? DesktopEntries.heuristicLookup(id) : null
    return entry && entry.icon ? Quickshell.iconPath(entry.icon, true) : ""
  }

  // ----------------------------------------------------------------- view

  PanelWindow {
    id: panel
    screen: root.targetScreen
    visible: root.opened || content.opacity > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-pages-expose"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    onWidthChanged: root.rebuild()
    onHeightChanged: root.rebuild()

    Item {
      id: content
      anchors.fill: parent
      opacity: root.opened ? 1 : 0
      scale: root.opened ? 1 : 1.02
      Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

      // The desktop itself, dimmed: one quiet surface.
      Image {
        id: wallpaper
        anchors.fill: parent
        source: root.opened ? root.backgroundSource : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        visible: false
      }
      MultiEffect {
        anchors.fill: parent
        source: wallpaper
        blurEnabled: true
        blur: 0.6
        blurMax: 48
        brightness: -0.12
      }
      Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.38) }

      MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

      // Page columns: the dot marks the page, a faint surface marks the one you're on.
      Repeater {
        model: root.layout.pages
        Item {
          required property var modelData
          x: modelData.x; y: modelData.y; width: modelData.w; height: modelData.h

          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: (root.indicatorHeight - height) / 2
            width: modelData.focused ? root.dotSize * 2.4 : root.dotSize
            height: root.dotSize
            radius: height / 2
            color: Color.foreground
            opacity: modelData.focused ? 1 : 0.5
          }

          Rectangle {
            id: surface
            y: root.indicatorHeight
            width: parent.width
            height: parent.height - root.indicatorHeight
            radius: Style.cornerRadius
            color: Qt.rgba(1, 1, 1, modelData.focused ? 0.06 : (columnArea.containsMouse ? 0.04 : 0))
            border.width: modelData.focused ? 1 : 0
            border.color: Qt.rgba(1, 1, 1, 0.12)
            Behavior on color { ColorAnimation { duration: 120 } }
          }

          MouseArea {
            id: columnArea
            anchors.fill: surface
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.goToPage(modelData.id)
          }
        }
      }

      // Empty frames at each end: a new page there.
      Repeater {
        model: root.layout.ghosts
        Item {
          required property var modelData
          x: modelData.x; y: modelData.y; width: modelData.w; height: modelData.h

          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, ghostArea.containsMouse ? 0.35 : 0.08)
            Behavior on border.color { ColorAnimation { duration: 120 } }
          }
          Text {
            anchors.centerIn: parent
            text: "+"
            color: Color.foreground
            opacity: ghostArea.containsMouse ? 0.8 : 0.2
            font.family: Style.font.family
            font.pixelSize: Style.space(20)
            Behavior on opacity { NumberAnimation { duration: 120 } }
          }
          MouseArea {
            id: ghostArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.newPage(modelData.side)
          }
        }
      }

      // The shelf: a hairline and small captions, nothing more.
      Rectangle {
        visible: root.layout.shelfY >= 0
        x: root.margin
        y: root.layout.shelfY
        width: parent.width - root.margin * 2
        height: 1
        color: Qt.rgba(1, 1, 1, 0.1)
      }
      Repeater {
        model: root.layout.captions
        Text {
          required property var modelData
          x: modelData.x; y: modelData.y
          text: modelData.text
          color: Color.foreground
          opacity: 0.45
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
      }

      // Windows.
      Repeater {
        model: root.layout.windows
        Item {
          id: tile
          required property var modelData
          required property int index
          readonly property bool lit: root.selected === index
          x: modelData.x; y: modelData.y; width: modelData.w; height: modelData.h

          Rectangle {
            id: frame
            anchors.fill: parent
            anchors.margins: -3
            radius: 6
            color: "transparent"
            border.width: 2
            border.color: Color.accent
            opacity: tile.lit ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 100 } }
          }

          Item {
            id: shot
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect {
              maskEnabled: true
              maskSource: shotMask
              maskThresholdMin: 0.5
              maskSpreadAtMin: 1
            }

            Rectangle {
              anchors.fill: parent
              visible: !capture.hasContent
              color: Qt.rgba(1, 1, 1, 0.08)
              Image {
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height) * 0.35
                height: width
                source: root.opened ? root.appIcon(tile.modelData.toplevel) : ""
                sourceSize.width: 128
                sourceSize.height: 128
              }
            }

            ScreencopyView {
              id: capture
              anchors.fill: parent
              captureSource: root.opened ? tile.modelData.toplevel.wayland : null
              live: root.opened
              paintCursor: false
              constraintSize: Qt.size(tile.width * 2, tile.height * 2)
            }
          }

          Rectangle {
            id: shotMask
            anchors.fill: parent
            radius: 4
            visible: false
            layer.enabled: true
          }

          // Title on hover or selection only.
          Rectangle {
            visible: tile.lit
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(8)
            width: Math.min(title.implicitWidth + Style.space(20), parent.width - Style.space(12))
            height: title.implicitHeight + Style.space(10)
            radius: height / 2
            color: Qt.rgba(0, 0, 0, 0.7)
            Text {
              id: title
              anchors.centerIn: parent
              width: Math.min(implicitWidth, parent.width - Style.space(20))
              text: tile.modelData.toplevel.title || ""
              elide: Text.ElideRight
              color: "white"
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.selected = tile.index
            onClicked: root.activate(tile.index)
          }
        }
      }

      Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) {
          switch (event.key) {
          case Qt.Key_Escape: root.dismiss(); break
          case Qt.Key_Left: root.move(-1, 0); break
          case Qt.Key_Right: root.move(1, 0); break
          case Qt.Key_Up: root.move(0, -1); break
          case Qt.Key_Down: root.move(0, 1); break
          case Qt.Key_Tab: root.selected = (root.selected + 1) % Math.max(1, root.layout.windows.length); break
          case Qt.Key_Return:
          case Qt.Key_Enter: root.activate(root.selected); break
          default: return
          }
          event.accepted = true
        }
      }
    }
  }
}
