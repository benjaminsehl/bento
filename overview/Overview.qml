import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Overview: a zoomed-out view of everything.
//
// Every page is a miniature of the monitor with its windows exactly where
// Hyprland put them, in dot order. The scratchpad is a miniature too,
// centred below. Minimized windows have no place on screen, so they sit in a
// small shelf centred above. Click a window to go to it, a page to go there,
// or an empty frame at either end for a new page.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property int selected: -1

  readonly property string pluginId: (manifest && manifest.id) || "io.github.benjaminsehl.bento"
  readonly property string backgroundSource: "file://" + Quickshell.env("HOME") + "/.local/state/omarchy/current/background"

  readonly property var monitor: Hyprland.focusedMonitor
  readonly property var targetScreen: {
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++)
      if (monitor && screens[i].name === monitor.name) return screens[i]
    return screens.length ? screens[0] : null
  }

  // Monitor geometry in layout (logical) pixels.
  readonly property real monScale: monitor && monitor.scale > 0 ? monitor.scale : 1
  readonly property real monX: monitor ? monitor.x : 0
  readonly property real monY: monitor ? monitor.y : 0
  readonly property real monW: monitor ? monitor.width / monScale : 1920
  readonly property real monH: monitor ? monitor.height / monScale : 1080

  // Spacing, in overlay pixels.
  readonly property real margin: Style.space(40)
  readonly property real gap: Style.space(28)
  readonly property real ghostWidth: Style.space(36)
  readonly property real indicatorHeight: Style.space(24)
  readonly property real captionHeight: Style.space(24)
  readonly property real dotSize: Style.spaceReal(5)

  property var layout: ({ pages: [], ghosts: [], windows: [], captions: [], scratch: null })

  function open(payloadJson) {
    Hyprland.refreshToplevels()
    Hyprland.refreshWorkspaces()
    Hyprland.refreshMonitors()
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
  function ipcOf(t) { return t.lastIpcObject || {} }

  // ----------------------------------------------------------------- model

  function collect() {
    var mon = root.monitor
    var activeId = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
    var pages = [], minimized = [], scratchpad = []
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var ws = values[i]
      var wins = ws.toplevels.values
      if (ws.id > 0) {
        if (mon && ws.monitor && ws.monitor.name !== mon.name) continue
        if (wins.length === 0 && ws.id !== activeId) continue
        pages.push({ id: ws.id, focused: ws.id === activeId, windows: stacked(wins) })
      } else if (ws.name === "special:scratchpad") {
        scratchpad = scratchpad.concat(stacked(wins))
      } else if (ws.name.indexOf("special:") === 0) {
        minimized = minimized.concat(wins) // minimized, and any other hidden workspace
      }
    }
    pages.sort(function(a, b) { return a.id - b.id })
    return { pages: pages, minimized: minimized, scratchpad: scratchpad }
  }

  // Tiled first, then floating, then fullscreen: the order Hyprland draws them.
  function stacked(list) {
    function rank(t) {
      var ipc = ipcOf(t)
      return (ipc.fullscreen ? 2 : 0) + (ipc.floating ? 1 : 0)
    }
    return list.slice().sort(function(a, b) { return rank(a) - rank(b) })
  }

  // A window's rectangle inside a miniature of the monitor at (x, y, w, h).
  function placeIn(t, x, y, w, h) {
    var ipc = ipcOf(t)
    var at = ipc.at || [root.monX, root.monY]
    var size = ipc.size || [root.monW, root.monH]
    var f = w / root.monW
    return { x: x + (at[0] - root.monX) * f, y: y + (at[1] - root.monY) * f, w: Math.max(2, size[0] * f), h: Math.max(2, size[1] * f) }
  }

  // One centred row of thumbnails at a fixed height, shrunk to fit the width.
  function shelfRow(wins, cx, y, maxW, h, g) {
    var widths = [], total = 0
    for (var i = 0; i < wins.length; i++) {
      var size = ipcOf(wins[i]).size || [1600, 1000]
      var w = h * size[0] / Math.max(1, size[1])
      widths.push(w); total += w
    }
    total += g * Math.max(0, wins.length - 1)
    var s = total > maxW ? maxW / total : 1
    var rects = [], x = cx - total * s / 2
    for (var j = 0; j < wins.length; j++) {
      var ww = widths[j] * s, hh = h * s
      rects.push({ x: x, y: y + (h - hh) / 2, w: ww, h: hh })
      x += ww + g * s
    }
    return rects
  }

  function rebuild() {
    if (!root.opened || !panel.width || !panel.height) return
    var W = panel.width, H = panel.height
    var aspect = root.monH / root.monW
    var data = collect()
    var out = { pages: [], ghosts: [], windows: [], captions: [], scratch: null }

    // Vertical budget: minimized shelf on top, scratchpad below, pages in between.
    var shelfH = data.minimized.length ? Math.round(H * 0.085) : 0
    var scratchH = data.scratchpad.length ? Math.round(H * 0.24) : 0
    var top = root.margin + (shelfH ? root.captionHeight + shelfH + root.gap : 0)
    var bottom = H - root.margin - (scratchH ? root.captionHeight + scratchH + root.gap : 0)

    // Pages: as large as fits, in one centred row.
    var n = Math.max(1, data.pages.length)
    var availW = W - root.margin * 2 - (root.ghostWidth + root.gap) * 2 - root.gap * (n - 1)
    var availH = bottom - top - root.indicatorHeight
    var miniW = Math.min(availW / n, availH / aspect)
    var miniH = miniW * aspect
    var rowW = miniW * n + root.gap * (n - 1)
    var x = (W - rowW) / 2
    var y = top + root.indicatorHeight + (availH - miniH) / 2

    out.ghosts.push({ side: "left", x: x - root.gap - root.ghostWidth, y: y, w: root.ghostWidth, h: miniH })
    for (var p = 0; p < data.pages.length; p++) {
      var page = data.pages[p]
      out.pages.push({ id: page.id, focused: page.focused, x: x, y: y, w: miniW, h: miniH })
      for (var i = 0; i < page.windows.length; i++) {
        var r = placeIn(page.windows[i], x, y, miniW, miniH)
        out.windows.push({ toplevel: page.windows[i], kind: "page", x: r.x, y: r.y, w: r.w, h: r.h, clipX: x, clipY: y, clipW: miniW, clipH: miniH })
      }
      x += miniW + root.gap
    }
    out.ghosts.push({ side: "right", x: x, y: y, w: root.ghostWidth, h: miniH })

    // Minimized: a small shelf centred at the top.
    if (shelfH) {
      var sy = root.margin
      out.captions.push({ text: "Minimized", cx: W / 2, y: sy })
      var rects = shelfRow(data.minimized, W / 2, sy + root.captionHeight, W - root.margin * 2, shelfH, Style.space(12))
      for (var m = 0; m < rects.length; m++)
        out.windows.push({ toplevel: data.minimized[m], kind: "minimized", x: rects[m].x, y: rects[m].y, w: rects[m].w, h: rects[m].h })
    }

    // Scratchpad: a miniature of the monitor centred at the bottom.
    if (scratchH) {
      var scW = scratchH / aspect
      var sx = (W - scW) / 2
      var scy = H - root.margin - scratchH
      out.captions.push({ text: "Scratchpad", cx: W / 2, y: scy - root.captionHeight })
      out.scratch = { x: sx, y: scy, w: scW, h: scratchH }
      for (var s = 0; s < data.scratchpad.length; s++) {
        var rr = placeIn(data.scratchpad[s], sx, scy, scW, scratchH)
        out.windows.push({ toplevel: data.scratchpad[s], kind: "scratchpad", x: rr.x, y: rr.y, w: rr.w, h: rr.h, clipX: sx, clipY: scy, clipW: scW, clipH: scratchH })
      }
    }

    root.layout = out
    if (root.selected >= out.windows.length) root.selected = out.windows.length - 1
  }

  function activeWindowIndex() {
    var active = Hyprland.activeToplevel
    var list = root.layout.windows
    for (var i = 0; i < list.length; i++)
      if (active && String(list[i].toplevel.address) === String(active.address)) return i
    return list.length ? 0 : -1
  }

  // Rebuild while open as windows come and go.
  Timer { id: rebuildSoon; interval: 50; onTriggered: root.rebuild() }
  Connections {
    target: Hyprland
    enabled: root.opened
    function onRawEvent(event) {
      var n = event.name
      if (n.indexOf("window") >= 0 || n.indexOf("workspace") >= 0) {
        Hyprland.refreshToplevels()
        rebuildSoon.restart()
      }
    }
  }

  // ----------------------------------------------------------------- actions

  function addressOf(t) {
    var raw = String(t.address)
    return "address:" + (raw.indexOf("0x") === 0 ? raw : "0x" + raw)
  }

  function activate(index) {
    var e = root.layout.windows[index]
    if (!e) return
    var addr = addressOf(e.toplevel)
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

  function openScratchpad() {
    dispatch("hl.dsp.workspace.toggle_special(\"scratchpad\")")
    dismiss()
  }

  function newPage(side) {
    var pages = root.layout.pages
    if (!pages.length) return dismiss()
    var id = side === "left" ? pages[0].id - 1 : pages[pages.length - 1].id + 1
    if (id < 1) id = pages[0].id // no room on the left; pages.lua makes some
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
      var score = along + (Math.abs(ex * dy) + Math.abs(ey * dx)) * 2
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

  component Caption: Text {
    color: Color.foreground
    opacity: 0.5
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    height: root.captionHeight
  }

  PanelWindow {
    id: panel
    screen: root.targetScreen
    visible: root.opened || content.opacity > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "bento-overview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    onWidthChanged: root.rebuild()
    onHeightChanged: root.rebuild()

    Item {
      id: content
      anchors.fill: parent
      opacity: root.opened ? 1 : 0
      scale: root.opened ? 1 : 1.03
      Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

      // Behind everything: the desktop, blurred and dimmed.
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
        blur: 0.8
        blurMax: 64
        brightness: -0.1
      }
      Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.5) }

      MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

      // Pages: miniatures of the monitor, marked by the same dot as the bar.
      Repeater {
        model: root.layout.pages
        Item {
          id: mini
          required property var modelData
          x: modelData.x; y: modelData.y; width: modelData.w; height: modelData.h

          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: -root.indicatorHeight / 2 - height / 2
            width: mini.modelData.focused ? root.dotSize * 2.4 : root.dotSize
            height: root.dotSize
            radius: height / 2
            color: Color.foreground
            opacity: mini.modelData.focused ? 1 : 0.5
          }

          Item {
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect {
              maskEnabled: true
              maskSource: miniMask
              maskThresholdMin: 0.5
              maskSpreadAtMin: 1
            }
            Image {
              anchors.fill: parent
              source: root.opened ? root.backgroundSource : ""
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              sourceSize.width: 640
            }
            Rectangle { anchors.fill: parent; color: Qt.rgba(1, 1, 1, pageArea.containsMouse ? 0.06 : 0) }
          }
          Rectangle {
            id: miniMask
            anchors.fill: parent
            radius: Style.cornerRadius
            visible: false
            layer.enabled: true
          }
          Rectangle {
            anchors.fill: parent
            anchors.margins: -2
            radius: Style.cornerRadius + 2
            color: "transparent"
            border.width: mini.modelData.focused ? 2 : 1
            border.color: mini.modelData.focused ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(1, 1, 1, 0.1)
          }
          MouseArea {
            id: pageArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.goToPage(mini.modelData.id)
          }
        }
      }

      // The scratchpad: a miniature with no wallpaper, since it floats over a page.
      Item {
        visible: root.layout.scratch !== null
        x: root.layout.scratch ? root.layout.scratch.x : 0
        y: root.layout.scratch ? root.layout.scratch.y : 0
        width: root.layout.scratch ? root.layout.scratch.w : 0
        height: root.layout.scratch ? root.layout.scratch.h : 0

        Rectangle {
          anchors.fill: parent
          radius: Style.cornerRadius
          color: Qt.rgba(1, 1, 1, scratchArea.containsMouse ? 0.08 : 0.04)
          border.width: 1
          border.color: Qt.rgba(1, 1, 1, 0.12)
        }
        MouseArea {
          id: scratchArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.openScratchpad()
        }
      }

      // Empty frames at each end of the pages: a new page there.
      Repeater {
        model: root.layout.ghosts
        Item {
          id: ghost
          required property var modelData
          x: modelData.x; y: modelData.y; width: modelData.w; height: modelData.h

          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, ghostArea.containsMouse ? 0.4 : 0.1)
            Behavior on border.color { ColorAnimation { duration: 120 } }
          }
          Text {
            anchors.centerIn: parent
            text: "+"
            color: Color.foreground
            opacity: ghostArea.containsMouse ? 0.8 : 0.25
            font.family: Style.font.family
            font.pixelSize: Style.space(18)
            Behavior on opacity { NumberAnimation { duration: 120 } }
          }
          MouseArea {
            id: ghostArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.newPage(ghost.modelData.side)
          }
        }
      }

      Repeater {
        model: root.layout.captions
        Caption {
          required property var modelData
          text: modelData.text
          x: modelData.cx - width / 2
          y: modelData.y
          width: Style.space(200)
        }
      }

      // Windows, each drawn live where it sits.
      Repeater {
        model: root.layout.windows
        Item {
          id: tile
          required property var modelData
          required property int index
          readonly property bool lit: root.selected === index
          readonly property bool clipped: modelData.clipW !== undefined
          // Keep page windows inside their miniature (gaps, off-screen floats).
          x: clipped ? modelData.clipX : modelData.x
          y: clipped ? modelData.clipY : modelData.y
          width: clipped ? modelData.clipW : modelData.w
          height: clipped ? modelData.clipH : modelData.h
          clip: clipped
          z: lit ? 1 : 0

          Item {
            id: win
            x: tile.modelData.x - tile.x
            y: tile.modelData.y - tile.y
            width: tile.modelData.w
            height: tile.modelData.h

            Item {
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
                color: Qt.rgba(0.15, 0.15, 0.15, 0.9)
                Image {
                  anchors.centerIn: parent
                  width: Math.min(parent.width, parent.height) * 0.4
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
                constraintSize: Qt.size(win.width * 2, win.height * 2)
              }
            }
            Rectangle {
              id: shotMask
              anchors.fill: parent
              radius: 3
              visible: false
              layer.enabled: true
            }

            Rectangle {
              anchors.fill: parent
              anchors.margins: tile.clipped ? 0 : -3
              radius: 4
              color: "transparent"
              border.width: 2
              border.color: Color.accent
              opacity: tile.lit ? 1 : 0
              Behavior on opacity { NumberAnimation { duration: 100 } }
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
      }

      // The selected window's title, just below it: the only text that moves.
      Rectangle {
        readonly property var sel: root.selected >= 0 ? root.layout.windows[root.selected] : null
        visible: sel !== null && sel !== undefined && titleText.text !== ""
        x: sel ? Math.max(Style.space(8), Math.min(content.width - width - Style.space(8), sel.x + sel.w / 2 - width / 2)) : 0
        y: sel ? Math.min(content.height - height - Style.space(8), sel.y + sel.h + Style.space(8)) : 0
        z: 2
        width: Math.min(titleText.implicitWidth + Style.space(20), Style.space(420))
        height: titleText.implicitHeight + Style.space(10)
        radius: height / 2
        color: Qt.rgba(0, 0, 0, 0.75)
        Text {
          id: titleText
          anchors.centerIn: parent
          width: Math.min(implicitWidth, parent.width - Style.space(20))
          text: parent.sel ? (parent.sel.toplevel.title || "") : ""
          elide: Text.ElideRight
          color: "white"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
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
