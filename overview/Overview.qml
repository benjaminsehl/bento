import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import ".."
import "../motion"
import "../motion/Motion.js" as Motion
import "../Windows.js" as Windows

// Overview: the desktop, zoomed out.
//
// Every page is the page itself, shrunk: its wallpaper and live windows drawn
// at full size, exactly where Hyprland put them, then scaled down as one. So
// opening Overview is a camera pulling back from the page you're on, and
// closing it pushes in to the page you chose; at either end the picture is the
// real desktop. Fingers coming together pull the camera back as they go
// (zoomBegin, zoomMove, zoomEnd); keys and clicks run the same zoom on Bento's
// spring. Only transforms change while it moves, so it runs at the screen's
// rate. Behind the pages the desktop fades, as it does behind the drawer.
//
// The scratchpad is a miniature too, centred below. Minimized windows have no
// place on screen, so they sit in a small shelf centred above. Click a window
// to go to it, a page to go there, or an empty frame at either end for a new
// page. Overview covers the page, not the bar.
//
// Drag a page by the strip with its dot to put it somewhere else in the row;
// the others make room. Drag it to the edge facing another monitor and it
// moves there, to the end of that monitor's pages. pages.lua does the moving
// (move_page). Drag a window instead and just the window goes: onto another
// page, an empty frame for a new page, or another monitor's edge for the page
// that monitor is showing.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property int selected: -1

  // Hyprland's look, so a page at full size is the page.
  property int borderSize: 2
  property int rounding: 0
  property color activeBorder: "#ffffff"
  property color inactiveBorder: "#595959"

  readonly property string pluginId: (manifest && manifest.id) || "io.github.benjaminsehl.bento"
  readonly property string backgroundSource: "file://" + Quickshell.env("HOME") + "/.local/state/omarchy/current/background"

  // The monitor it opened on, while it's open: moving a page to another
  // monitor can take the focus there for a moment.
  property var heldMonitor: null
  readonly property var monitor: root.heldMonitor || Hyprland.focusedMonitor
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

  // The page: the screen below the bar, where windows go. Overview covers
  // just this, and every miniature is one of it.
  readonly property var reserved: (monitor && monitor.lastIpcObject && monitor.lastIpcObject.reserved) || [0, 0, 0, 0]
  readonly property real pageX: root.monX + root.reserved[0]
  readonly property real pageY: root.monY + root.reserved[1]
  readonly property real pageW: root.monW - root.reserved[0] - root.reserved[2]
  readonly property real pageH: root.monH - root.reserved[1] - root.reserved[3]

  // Spacing, in overlay pixels.
  readonly property real margin: Style.space(40)
  readonly property real gap: Style.space(28)
  readonly property real ghostWidth: Style.space(36)
  readonly property real indicatorHeight: Style.space(24)
  readonly property real captionHeight: Style.space(24)
  readonly property real dotSize: Style.spaceReal(5)

  readonly property var empty: ({ pages: [], step: 0, ghosts: [], windows: [], extras: [], captions: [], scratch: null })
  property var layout: root.empty

  // ------------------------------------------------------------------ zoom

  // 0 the page, 1 zoomed out; a little past 1 while fingers push or a spring
  // lands. Zero is a wall: closing stops dead on the page.
  Spring { id: zoom; side: 1 }
  readonly property real progress: zoom.value
  property bool holding: false
  readonly property bool shown: root.opened || root.holding || zoom.running || zoom.value > 0.0005

  // The labels, dots and frames come in over the second half of the zoom.
  readonly property real chrome: Motion.clamp((zoom.value - 0.35) / 0.65, 0, 1)

  // The page the camera pulls back from, or pushes in to.
  property int zoomId: -1
  readonly property var zoomRect: {
    var pages = root.layout.pages, hit = null
    for (var i = 0; i < pages.length; i++) {
      if (pages[i].id === root.zoomId) return pages[i]
      if (pages[i].focused) hit = pages[i]
    }
    return hit || { x: root.pageW * 0.2, y: root.pageH * 0.2, w: root.pageW * 0.6, h: root.pageH * 0.6 }
  }
  // Scaling about this point takes the miniature to the whole page.
  readonly property real _fill: root.pageW / Math.max(1, root.zoomRect.w)
  readonly property real originX: root.zoomRect.x / Math.max(0.001, 1 - 1 / root._fill)
  readonly property real originY: root.zoomRect.y / Math.max(0.001, 1 - 1 / root._fill)
  // Even steps in scale, however far out: each bit of the zoom looks alike.
  readonly property real camera: Math.pow(root._fill, 1 - zoom.value)

  // Shown once the page being zoomed has its windows' first frames, so the
  // first picture is the real one. (Or shortly after, if one never comes.)
  // Until then it's drawn all the same, unseen, so the first frame it shows
  // costs no more than any other.
  property int cold: 0
  property bool revealed: false
  property int _unseen: 0   // frames drawn unseen so far
  onShownChanged: {
    root.revealed = false
    root._unseen = 0
    if (root.shown) waitTimer.restart()
    else {
      waitTimer.stop()
      root._launch = false
      // Let the captures and their textures go while it rests. It's built
      // afresh each time it opens.
      root.layout = root.empty
      root.selected = -1
      root.heldMonitor = null
      root.dragEnd(true)
    }
  }
  function reveal() { if (root.shown && root._unseen >= 2 && root.cold === 0) root.revealed = true }
  onColdChanged: reveal()
  // No longer than this waiting for windows.
  Timer { id: waitTimer; interval: 150; onTriggered: root.revealed = root.shown }

  // Keys and clicks: the zoom starts once the first picture is on screen.
  property bool _launch: false
  onRevealedChanged: if (root.revealed && root._launch) launchFrame.armed = true

  function prepare() {
    root.heldMonitor = Hyprland.focusedMonitor
    Hyprland.refreshToplevels()
    Hyprland.refreshWorkspaces()
    Hyprland.refreshMonitors()
    root.zoomId = -1
    rebuild()
    rebuildSoon.restart()
  }

  function open(payloadJson) {
    if (root.dragId !== -1) root.dragEnd(true)
    var cold = !root.shown
    if (cold) prepare()
    root.opened = true
    root.selected = activeWindowIndex()
    if (cold) root._launch = true
    else zoom.animateTo(1)
    Qt.callLater(function() { keys.forceActiveFocus() })
  }

  function close() {
    if (root.dragId !== -1) root.dragEnd(true)
    root.opened = false
    if (!root.holding) zoom.animateTo(0)
  }

  function dismiss() {
    close()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened) dismiss()
    else open("{}")
  }

  // Fingers. scale is the pinch's own: 1 where it began, smaller as the
  // fingers come together. t in ms.
  property real _base: 0
  property real _raw: 0
  property var _samples: []

  function zoomBegin(scale, t) {
    if (!root.shown) prepare()
    root._launch = false
    zoom.stop()
    root._base = zoom.value
    root._samples = []
    root.holding = true
    zoomMove(scale, t)
  }

  function zoomMove(scale, t) {
    if (!root.holding) return
    var raw = Math.max(0, root._base + Math.log(Math.max(0.05, scale)) / Math.log(Motion.zoom.fullScale))
    root._raw = raw
    zoom.jump(raw > 1 ? 1 + Motion.rubber(raw - 1, Motion.pull.rubberLimit, Motion.pull.rubberStiffness) : raw)
    if (raw > 0 && !root.opened) { root.opened = true; root.selected = activeWindowIndex() }
    var s = root._samples
    s.push({ t: t, v: raw })
    while (s.length > 2 && t - s[0].t > Motion.pull.velocityWindowMs) s.shift()
  }

  function zoomEnd(cancelled, t) {
    if (!root.holding) return
    root.holding = false
    var s = root._samples, speed = 0
    if (s.length >= 2 && s[s.length - 1].t > s[0].t)
      speed = (s[s.length - 1].v - s[0].v) / ((s[s.length - 1].t - s[0].t) / 1000)
    var stop = cancelled ? Math.round(root._base)
      : Motion.clamp(Math.round(root._raw + speed * Motion.pull.projection), 0, 1)
    if (stop === 1) {
      root.opened = true
      Qt.callLater(function() { keys.forceActiveFocus() })
    } else {
      root.opened = false
    }
    zoom.animateTo(stop, zoom.value > 1 ? speed * 0.2 : speed)
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
      var wins = Windows.live(ws.toplevels.values)
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

  // A window's rectangle on the page, in page pixels.
  function onPage(t) {
    var ipc = ipcOf(t)
    var at = ipc.at || [root.pageX, root.pageY]
    var size = ipc.size || [root.pageW, root.pageH]
    return { x: at[0] - root.pageX, y: at[1] - root.pageY, w: Math.max(2, size[0]), h: Math.max(2, size[1]) }
  }

  // A window's rectangle inside a miniature of the page at (x, y, w, h).
  function placeIn(t, x, y, w, h) {
    var r = onPage(t), f = w / root.pageW
    return { x: x + r.x * f, y: y + r.y * f, w: Math.max(2, r.w * f), h: Math.max(2, r.h * f) }
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
    // Not while it's closing: the camera is on its way into a page. Nor while
    // a page is being dragged, or is on its way to where it was let go.
    if (root.shown && !root.opened && !root.holding) return
    if (root.dragId !== -1) return
    var W = root.pageW, H = root.pageH
    if (W <= 0 || H <= 0) return
    var aspect = H / W
    var data = collect()
    var out = { pages: [], step: 0, ghosts: [], windows: [], extras: [], captions: [], scratch: null }

    // Vertical budget: minimized shelf on top, scratchpad below, pages in between.
    var shelfH = data.minimized.length ? Math.round(H * 0.085) : 0
    var scratchH = data.scratchpad.length ? Math.round(H * 0.24) : 0
    var top = root.margin + (shelfH ? root.captionHeight + shelfH + root.gap : 0)
    var bottom = H - root.margin - (scratchH ? root.captionHeight + scratchH + root.gap : 0)

    // Pages: as large as fits, in one centred row.
    var n = Math.max(1, data.pages.length)
    // Another monitor to the side: room for its edge outside the empty frames,
    // since a dragged window can go to either.
    var zones = monitorZones(), aside = 0
    for (var z = 0; z < zones.length; z++)
      if (zones[z].side === "left" || zones[z].side === "right") aside = root.zoneInset + root.zoneSize
    var availW = W - (root.margin + aside) * 2 - (root.ghostWidth + root.gap) * 2 - root.gap * (n - 1)
    var availH = bottom - top - root.indicatorHeight
    var miniW = Math.min(availW / n, availH / aspect)
    var miniH = miniW * aspect
    var rowW = miniW * n + root.gap * (n - 1)
    var x = (W - rowW) / 2
    var y = top + root.indicatorHeight + (availH - miniH) / 2
    var f = miniW / W
    out.step = miniW + root.gap

    out.ghosts.push({ side: "left", x: x - root.gap - root.ghostWidth, y: y, w: root.ghostWidth, h: miniH })
    for (var p = 0; p < data.pages.length; p++) {
      var page = data.pages[p]
      var wins = []
      for (var i = 0; i < page.windows.length; i++) {
        var r = onPage(page.windows[i])
        wins.push({ toplevel: page.windows[i], index: out.windows.length, x: r.x, y: r.y, w: r.w, h: r.h })
        out.windows.push({ toplevel: page.windows[i], kind: "page", page: page.id,
          x: x + r.x * f, y: y + r.y * f, w: r.w * f, h: r.h * f })
      }
      out.pages.push({ id: page.id, focused: page.focused, x: x, y: y, w: miniW, h: miniH, s: f, windows: wins })
      x += miniW + root.gap
    }
    out.ghosts.push({ side: "right", x: x, y: y, w: root.ghostWidth, h: miniH })

    // Minimized: a small shelf centred at the top.
    if (shelfH) {
      var sy = root.margin
      out.captions.push({ text: "Minimized", cx: W / 2, y: sy })
      var rects = shelfRow(data.minimized, W / 2, sy + root.captionHeight, W - root.margin * 2, shelfH, Style.space(12))
      for (var m = 0; m < rects.length; m++) {
        var e = { toplevel: data.minimized[m], kind: "minimized", index: out.windows.length, x: rects[m].x, y: rects[m].y, w: rects[m].w, h: rects[m].h }
        out.windows.push(e); out.extras.push(e)
      }
    }

    // Scratchpad: a miniature of the page centred at the bottom.
    if (scratchH) {
      var scW = scratchH / aspect
      var sx = (W - scW) / 2
      var scy = H - root.margin - scratchH
      out.captions.push({ text: "Scratchpad", cx: W / 2, y: scy - root.captionHeight })
      out.scratch = { x: sx, y: scy, w: scW, h: scratchH }
      for (var s = 0; s < data.scratchpad.length; s++) {
        var rr = placeIn(data.scratchpad[s], sx, scy, scW, scratchH)
        var es = { toplevel: data.scratchpad[s], kind: "scratchpad", index: out.windows.length, x: rr.x, y: rr.y, w: rr.w, h: rr.h, clipX: sx, clipY: scy, clipW: scW, clipH: scratchH }
        out.windows.push(es); out.extras.push(es)
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
  Timer { id: rebuildSoon; interval: 60; onTriggered: root.rebuild() }
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
    if (e.kind === "page") root.zoomId = e.page
    afterRelease.dispatch("hl.dsp.focus({ window = " + q(addr) + " })")
    dismiss()
  }

  function goToPage(id) {
    root.zoomId = id
    afterRelease.dispatch("hl.dsp.focus({ workspace = " + q(id) + " })")
    dismiss()
  }

  // Where you're going waits until Overview lets go of the keyboard.
  AfterRelease { id: afterRelease; window: content.Window.window }

  // The host raises the scratchpad with Bento's motion; without a host,
  // Hyprland does it.
  signal scratchpadRequested()
  function openScratchpad() {
    dismiss()
    if (root.hasScratchpadHost) root.scratchpadRequested()
    else afterRelease.dispatch("hl.dsp.workspace.toggle_special(\"scratchpad\")")
  }
  property bool hasScratchpadHost: false

  // The nearest id past the end that no other monitor has a page on.
  function newPage(side) {
    var pages = root.layout.pages
    if (!pages.length) return dismiss()
    var id = newPageId(side)
    goToPage(id < 1 ? pages[0].id : id) // no room on the left; pages.lua makes some
  }

  function newPageId(side) {
    var pages = root.layout.pages
    var step = side === "left" ? -1 : 1
    var id = (side === "left" ? pages[0].id : pages[pages.length - 1].id) + step
    while (id >= 1 && elsewhere(id)) id += step
    return id
  }

  function elsewhere(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++)
      if (values[i].id === id) return !root.monitor || !values[i].monitor || values[i].monitor.name !== root.monitor.name
    return false
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

  // ----------------------------------------------------------------- drag

  property int dragId: -1          // the page picked up, until it's in its place
  property bool dragging: false    // ...and still held
  property int dragFrom: -1        // its place in the row
  property int dropIndex: -1       // where it would go; -1 over another monitor
  property string dropMonitor: ""  // the monitor it would go to
  property real dragX: 0           // its top-left, in overlay pixels
  property real dragY: 0
  property real _grabX: 0
  property real _grabY: 0
  property var zones: []           // the edges facing other monitors
  property var dragWin: null       // the window picked up, when it's a window
  property int dropPage: -1        // ...the page it would go to
  property string dropGhost: ""    // ...or the empty frame, for a new page
  readonly property bool pageDrag: root.dragId !== -1 && root.dragWin === null

  // A page's place, given in slots along the row (fractions too).
  function slotX(k) {
    var pages = root.layout.pages
    return pages.length ? pages[0].x + k * root.layout.step : 0
  }

  // Where page i sits while one is being dragged: the others close up behind
  // it and open up where it would go.
  function slotOf(i) {
    if (i === root.dragFrom) return root.dropIndex >= 0 ? root.dropIndex : i
    var j = i < root.dragFrom ? i : i - 1
    if (root.dropIndex < 0) return j + 0.5
    return j >= root.dropIndex ? j + 1 : j
  }

  // Each other monitor gets the edge facing it, shared with any others there.
  function monitorZones() {
    var mon = root.monitor
    if (!mon) return []
    var cx = root.monX + root.monW / 2, cy = root.monY + root.monH / 2
    var sides = { left: [], right: [], top: [], bottom: [] }
    var all = Hyprland.monitors.values
    for (var i = 0; i < all.length; i++) {
      var m = all[i]
      var ipc = m.lastIpcObject || {}
      if (m.name === mon.name || m.width <= 0 || m.height <= 0 || ipc.disabled) continue
      var s = m.scale > 0 ? m.scale : 1
      var dx = m.x + m.width / s / 2 - cx, dy = m.y + m.height / s / 2 - cy
      var side = Math.abs(dx) >= Math.abs(dy) ? (dx < 0 ? "left" : "right") : (dy < 0 ? "top" : "bottom")
      sides[side].push({ name: m.name, along: side === "left" || side === "right" ? dy : dx,
        aspect: m.height / Math.max(1, m.width) })
    }
    var W = root.pageW, H = root.pageH, t = root.zoneSize, out = []
    for (var key in sides) {
      var list = sides[key].sort(function(a, b) { return a.along - b.along })
      var vertical = key === "left" || key === "right"
      var length = (vertical ? H : W) - root.margin * 2
      var each = (length - root.gap * (list.length - 1)) / Math.max(1, list.length)
      for (var k = 0; k < list.length; k++) {
        var a = root.margin + k * (each + root.gap)
        out.push({ name: list[k].name, side: key, aspect: list[k].aspect,
          x: vertical ? (key === "left" ? root.zoneInset : W - root.zoneInset - t) : a,
          y: vertical ? a : (key === "top" ? root.zoneInset : H - root.zoneInset - t),
          w: vertical ? t : each, h: vertical ? each : t })
      }
    }
    return out
  }
  // Inside the room the row leaves at each end (margin, empty frame, gap),
  // which a held page doesn't need: the empty frames make way for these.
  readonly property real zoneInset: Style.space(8)
  readonly property real zoneSize: root.margin + root.ghostWidth + root.gap - root.zoneInset * 2

  // The zone under (x, y). Past the overlay's edge counts too: the pointer
  // can be on the other monitor already.
  function zoneAt(x, y) {
    for (var i = 0; i < root.zones.length; i++) {
      var z = root.zones[i]
      var x0 = z.side === "left" ? -1e6 : z.x, x1 = z.side === "right" ? 1e6 : z.x + z.w
      var y0 = z.side === "top" ? -1e6 : z.y, y1 = z.side === "bottom" ? 1e6 : z.y + z.h
      if (x >= x0 && x <= x1 && y >= y0 && y <= y1) return z.name
    }
    return ""
  }

  // The theme's text colour, see-through: shows on light wallpapers and dark.
  function ink(a) { return Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, a) }

  // A drag starts from a page's MouseAreas: the page's own, its handle, or
  // one of its windows. Each has its own DragHandler, inside it, so a click
  // still reaches the MouseArea; one laid over them all took the clicks too.
  // It stays on for the page whose drag it is, a window's as much as the
  // page's: turned off, it would keep the pointer but stop following it.
  function canDrag(page) {
    return root.opened && !root.holding && page.windows.length > 0
      && (root.dragId === -1 || root.dragId === page.id)
  }

  function dragStart(index, winIndex, press) {
    var page = root.layout.pages[index]
    if (!page) return
    root.zones = monitorZones()
    root.dragFrom = index
    root.dropIndex = index
    root.dropMonitor = ""
    root.dropPage = -1
    root.dropGhost = ""
    var win = winIndex >= 0 ? root.layout.windows[winIndex] : null
    var from = win || page
    root._grabX = press.x - from.x
    root._grabY = press.y - from.y
    root.dragX = from.x
    root.dragY = from.y
    root.dragWin = win
    root.dragId = page.id
    root.dragging = true
  }

  function rectAt(list, x, y) {
    for (var i = 0; i < list.length; i++) {
      var r = list[i]
      if (x >= r.x && x <= r.x + r.w && y >= r.y && y <= r.y + r.h) return r
    }
    return null
  }

  function dragMove(at) {
    if (!root.dragging) return
    root.dragX = at.x - root._grabX
    root.dragY = at.y - root._grabY
    root.dropMonitor = zoneAt(at.x, at.y)
    if (root.dragWin) {
      var page = root.dropMonitor ? null : rectAt(root.layout.pages, at.x, at.y)
      var ghost = root.dropMonitor ? null : rectAt(root.layout.ghosts, at.x, at.y)
      root.dropPage = page ? page.id : -1
      root.dropGhost = ghost ? ghost.side : ""
    }
    if (root.dropMonitor) {
      root.dropIndex = -1
      // Past the edge it's on the other monitor, which gets the button's
      // release instead of Overview: let go for it.
      if (at.x < 0 || at.y < 0 || at.x > content.width || at.y > content.height) root.drop()
      return
    }
    if (root.dragWin) return
    var n = root.layout.pages.length
    var k = root.layout.step > 0 ? Math.round((root.dragX - root.slotX(0)) / root.layout.step) : 0
    root.dropIndex = Math.max(0, Math.min(n - 1, k))
  }

  // Let go: into its new place, onto another monitor, or back where it was.
  function drop() {
    if (!root.dragging) return
    root.dragging = false
    var id = root.dragId
    if (root.dragWin) return dropWindow()
    if (root.dropMonitor)
      lua("_G.bento.move_page(" + id + ", " + q(root.dropMonitor) + ", nil)")
    else if (root.dropIndex !== root.dragFrom)
      lua("_G.bento.move_page(" + id + ", nil, " + (root.dropIndex + 1) + ")")
    else { settle.moved = false; settle.restart(); return }
    settle.moved = true
    settle.restart()
  }

  // A window goes to another page, a new one, or the page another monitor
  // is showing.
  function dropWindow() {
    var to = -1
    if (root.dropMonitor) {
      var all = Hyprland.monitors.values
      for (var i = 0; i < all.length; i++)
        if (all[i].name === root.dropMonitor && all[i].activeWorkspace) to = all[i].activeWorkspace.id
    } else if (root.dropGhost) {
      to = newPageId(root.dropGhost)
    } else if (root.dropPage !== root.dragId) {
      to = root.dropPage
    }
    settle.moved = to >= 1
    if (settle.moved)
      dispatch("hl.dsp.window.move({ workspace = " + q(to) + ", follow = false, window = " + q(addressOf(root.dragWin.toplevel)) + " })")
    settle.restart()
  }

  // Esc while holding a page puts it back.
  function cancelDrag() {
    root.dragging = false
    root.dropIndex = root.dragFrom
    root.dropMonitor = ""
    settle.moved = false
    settle.restart()
  }

  function dragEnd(quiet) {
    settle.stop()
    settled.stop()
    root.dragging = false
    root.dragId = -1
    root.dragFrom = -1
    root.dropIndex = -1
    root.dropMonitor = ""
    root.dragWin = null
    root.dropPage = -1
    root.dropGhost = ""
    // At once, so no frame shows the old order; and again shortly, in case
    // Quickshell's workspaces were still on their way.
    if (!quiet) { rebuild(); rebuildSoon.restart() }
  }

  // Once it's glided into place, read Hyprland's pages afresh. Quickshell only
  // sees a workspace's new id when it asks again.
  Timer {
    id: settle
    property bool moved: false
    interval: 220
    onTriggered: {
      if (!settle.moved) return root.dragEnd(false)
      Hyprland.refreshWorkspaces()
      Hyprland.refreshToplevels()
      settled.restart()
    }
  }
  Timer { id: settled; interval: 120; onTriggered: root.dragEnd(false) }

  function lua(body) {
    dispatch("(function() if _G.bento and _G.bento.move_page then " + body + " end return hl.dsp.event(\"bento>>ack\") end)()")
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

  // The four corners of a rounded rectangle, outside its curve: what a mask
  // takes away to round it.
  component Corners: Item {
    id: corners
    property real r: 0
    visible: r > 0
    Repeater {
      model: 4
      Item {
        required property int index
        readonly property bool atRight: index === 1 || index === 2
        readonly property bool atBottom: index >= 2
        x: atRight ? corners.width - corners.r : 0
        y: atBottom ? corners.height - corners.r : 0
        width: corners.r
        height: corners.r
        clip: true
        // A ring around the curve's centre, wide enough to fill the corner.
        Rectangle {
          readonly property real outer: corners.r * 2
          x: (parent.atRight ? 0 : corners.r) - outer
          y: (parent.atBottom ? 0 : corners.r) - outer
          width: outer * 2
          height: outer * 2
          radius: outer
          color: "transparent"
          border.width: corners.r
          border.color: "black"
        }
      }
    }
  }

  // The wallpaper as the page shows it: cropped to the whole monitor, bar
  // and all, seen through the page.
  component Wallpaper: Image {
    x: -root.reserved[0]
    y: -root.reserved[1]
    width: root.monW
    height: root.monH
    sourceSize: Qt.size(Math.round(root.monW * root.monScale), Math.round(root.monH * root.monScale))
    source: root.backgroundSource
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
  }

  PanelWindow {
    id: panel
    screen: root.targetScreen
    // Always mapped at the page's full size, so opening neither waits for a
    // window to be made nor resizes one. (Grown from a resting pixel, the
    // picture was drawn into a box easing out of the top-left corner, so the
    // zoom seemed to come from there.) At rest it's empty, lets everything
    // through and sits on the background layer: Hyprland lets fullscreen
    // windows scan out directly unless something is on the overlay layer.
    visible: true
    mask: Region { width: root.shown ? panel.width : 0; height: root.shown ? panel.height : 0 }
    anchors { top: true; bottom: true; left: true; right: true }
    margins { left: root.reserved[0]; top: root.reserved[1]; right: root.reserved[2]; bottom: root.reserved[3] }
    color: "transparent"
    WlrLayershell.namespace: "bento-overview"
    WlrLayershell.layer: root.shown ? WlrLayer.Overlay : WlrLayer.Background
    WlrLayershell.keyboardFocus: root.opened && !root.holding ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Item {
      id: content
      anchors.fill: parent
      visible: root.shown
      opacity: root.revealed ? 1 : 0.002

      // Frames drawn unseen; and the frame after the first picture shows,
      // when the zoom can start.
      Connections {
        id: launchFrame
        property bool armed: false
        target: content.Window.window
        function onFrameSwapped() {
          if (root.shown && !root.revealed) { root._unseen++; root.reveal() }
          if (!launchFrame.armed) return
          launchFrame.armed = false
          if (root._launch && root.opened) zoom.animateTo(1)
          root._launch = false
        }
      }

      // Behind the pages: the desktop, fading as Overview comes in.
      Item {
        anchors.fill: parent
        clip: true
        Wallpaper {}
        Rectangle {
          anchors.fill: parent
          color: Color.menu.scrim
          opacity: Motion.clamp(root.progress, 0, 1)
        }
      }

      MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

      // Everything zooms together, as one picture.
      Item {
        id: world
        anchors.fill: parent
        transform: Scale {
          origin.x: root.originX
          origin.y: root.originY
          xScale: root.camera
          yScale: root.camera
        }

        // Pages: the page itself, shrunk, marked by the same dot as the bar.
        Repeater {
          model: root.layout.pages
          Item {
            id: mini
            required property var modelData
            required property int index
            readonly property bool zoomed: modelData === root.zoomRect
            // Picked up, it follows the pointer; the rest slide out of its way.
            readonly property bool lifted: root.dragging && root.pageDrag && root.dragId === modelData.id
            readonly property bool leaving: !root.dragging && root.pageDrag && root.dragId === modelData.id && root.dropMonitor !== ""
            x: lifted ? root.dragX : (root.pageDrag ? root.slotX(root.slotOf(index)) : modelData.x)
            y: lifted ? root.dragY : modelData.y
            width: modelData.w; height: modelData.h
            z: root.pageDrag && root.dragId === modelData.id ? 1 : 0
            scale: lifted ? (root.dropMonitor ? 0.5 : 1.03) : 1
            opacity: leaving ? 0 : 1
            Behavior on x { enabled: root.pageDrag && !mini.lifted; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on y { enabled: root.pageDrag && !mini.lifted; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 160 } }

            Rectangle {
              anchors.horizontalCenter: parent.horizontalCenter
              y: -root.indicatorHeight / 2 - height / 2
              width: mini.modelData.focused ? root.dotSize * 2.4 : root.dotSize
              height: root.dotSize
              radius: height / 2
              color: Color.foreground
              opacity: (mini.modelData.focused || handle.containsMouse || mini.lifted ? 1 : 0.5) * root.chrome
            }

            // The strip with the dot is the page's handle: windows nearly
            // fill a page, and dragging one of them moves just that window.
            MouseArea {
              id: handle
              y: -root.indicatorHeight
              width: parent.width
              height: root.indicatorHeight
              hoverEnabled: true
              cursorShape: Qt.OpenHandCursor
              onClicked: root.goToPage(mini.modelData.id)
              DragHandler {
                target: null
                enabled: root.canDrag(mini.modelData)
                cursorShape: Qt.ClosedHandCursor
                onActiveChanged: if (active) root.dragStart(mini.index, -1, centroid.scenePressPosition); else root.drop()
                onCentroidChanged: if (active) root.dragMove(centroid.scenePosition)
                onCanceled: root.drop()
              }
            }

            MouseArea {
              id: pageArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goToPage(mini.modelData.id)
              DragHandler {
                target: null
                enabled: root.canDrag(mini.modelData)
                cursorShape: Qt.ClosedHandCursor
                onActiveChanged: if (active) root.dragStart(mini.index, -1, centroid.scenePressPosition); else root.drop()
                onCentroidChanged: if (active) root.dragMove(centroid.scenePosition)
                onCanceled: root.drop()
              }
            }

            // At the page's own size, then scaled: crisp when the camera is
            // close, one texture when it's far.
            Item {
              id: body
              width: root.pageW
              height: root.pageH
              scale: mini.modelData.s
              transformOrigin: Item.TopLeft
              // The page being zoomed is drawn at full resolution; the rest
              // only need to hold up at a few times their miniature.
              readonly property size texture: mini.zoomed
                ? Qt.size(Math.ceil(root.pageW * root.monScale), Math.ceil(root.pageH * root.monScale))
                : Qt.size(Math.ceil(mini.width * root.monScale * 2.5), Math.ceil(mini.height * root.monScale * 2.5))

              Item {
                anchors.fill: parent
                layer.enabled: true
                layer.textureSize: body.texture
                layer.smooth: true
                layer.effect: MultiEffect {
                  maskEnabled: true
                  maskInverted: true
                  maskSource: cut
                  maskThresholdMin: 0.5
                  maskSpreadAtMin: 1
                }

                Wallpaper {}
                Rectangle { anchors.fill: parent; color: Qt.rgba(1, 1, 1, pageArea.containsMouse ? 0.06 * root.chrome : 0) }

                Repeater {
                  model: mini.modelData.windows
                  Item {
                    id: pw
                    required property var modelData
                    x: modelData.x; y: modelData.y; width: modelData.w; height: modelData.h
                    readonly property bool cold: mini.zoomed && !capture.hasContent
                    opacity: root.dragWin && root.dragWin.index === modelData.index ? 0.2 : 1
                    onColdChanged: root.cold += pw.cold ? 1 : -1
                    Component.onCompleted: if (pw.cold) root.cold++
                    Component.onDestruction: if (pw.cold) root.cold--

                    Rectangle {
                      anchors.fill: parent
                      visible: !capture.hasContent
                      color: Qt.rgba(0.15, 0.15, 0.15, 0.9)
                      Image {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height) * 0.3
                        height: width
                        source: root.shown ? root.appIcon(pw.modelData.toplevel) : ""
                        sourceSize.width: 256
                        sourceSize.height: 256
                      }
                    }
                    ScreencopyView {
                      id: capture
                      anchors.fill: parent
                      captureSource: root.shown ? pw.modelData.toplevel.wayland : null
                      live: root.shown
                      paintCursor: false
                    }
                  }
                }
              }

              // What rounds the page and its windows, as Hyprland does.
              Item {
                id: cut
                anchors.fill: parent
                visible: false
                layer.enabled: true
                layer.textureSize: body.texture
                Corners { anchors.fill: parent; r: Style.cornerRadius / mini.modelData.s }
                Repeater {
                  model: root.rounding > 0 ? mini.modelData.windows : []
                  Corners {
                    required property var modelData
                    x: modelData.x - root.borderSize; y: modelData.y - root.borderSize
                    width: modelData.w + root.borderSize * 2; height: modelData.h + root.borderSize * 2
                    r: root.rounding + root.borderSize
                  }
                }
              }

              // Hyprland's borders, outside each window.
              Repeater {
                model: mini.modelData.windows
                Item {
                  id: frame
                  required property var modelData
                  x: modelData.x; y: modelData.y; width: modelData.w; height: modelData.h
                  readonly property bool lit: root.selected === modelData.index

                  Rectangle {
                    anchors.fill: parent
                    anchors.margins: -root.borderSize
                    radius: root.rounding > 0 ? root.rounding + root.borderSize : 0
                    color: "transparent"
                    border.width: root.borderSize
                    border.color: Hyprland.activeToplevel === frame.modelData.toplevel ? root.activeBorder : root.inactiveBorder
                  }
                  // The selection: two pixels however small the page is.
                  Rectangle {
                    readonly property real px: 1 / mini.modelData.s
                    anchors.fill: parent
                    anchors.margins: -px * 3
                    radius: px * 4
                    color: "transparent"
                    border.width: px * 2
                    border.color: Color.accent
                    opacity: frame.lit ? root.chrome : 0
                  }
                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.selected = frame.modelData.index
                    onClicked: root.activate(frame.modelData.index)
                    DragHandler {
                      target: null
                      enabled: root.canDrag(mini.modelData)
                      cursorShape: Qt.ClosedHandCursor
                      onActiveChanged: if (active) root.dragStart(mini.index, frame.modelData.index, centroid.scenePressPosition); else root.drop()
                      onCentroidChanged: if (active) root.dragMove(centroid.scenePosition)
                      onCanceled: root.drop()
                    }
                  }
                }
              }
            }

            Rectangle {
              anchors.fill: parent
              anchors.margins: -2
              radius: Style.cornerRadius + 2
              color: "transparent"
              readonly property bool target: root.dragWin !== null && root.dropPage === mini.modelData.id
                && root.dropPage !== root.dragId
              border.width: mini.modelData.focused || target ? 2 : 1
              border.color: target ? Color.accent
                : mini.modelData.focused ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(1, 1, 1, 0.1)
              opacity: root.chrome
            }
          }
        }

        // Everything but the pages comes in with the labels.
        Item {
          anchors.fill: parent
          opacity: root.chrome
          visible: opacity > 0

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
              // A held page can't go there; the other monitors take the ends.
              opacity: root.pageDrag ? 0 : 1
              visible: opacity > 0
              Behavior on opacity { NumberAnimation { duration: 140 } }

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: "transparent"
                border.width: root.dropGhost === ghost.modelData.side ? 2 : 1
                border.color: root.dropGhost === ghost.modelData.side ? Color.accent
                  : Qt.rgba(1, 1, 1, ghostArea.containsMouse ? 0.4 : 0.1)
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

          // Minimized and scratchpad windows, each drawn live where it sits.
          Repeater {
            model: root.layout.extras
            Item {
              id: tile
              required property var modelData
              readonly property bool lit: root.selected === modelData.index
              readonly property bool clipped: modelData.clipW !== undefined
              // Keep scratchpad windows inside their miniature.
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
                      source: root.shown ? root.appIcon(tile.modelData.toplevel) : ""
                      sourceSize.width: 128
                      sourceSize.height: 128
                    }
                  }
                  ScreencopyView {
                    id: capture
                    anchors.fill: parent
                    captureSource: root.shown ? tile.modelData.toplevel.wayland : null
                    live: root.shown
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
                  onEntered: root.selected = tile.modelData.index
                  onClicked: root.activate(tile.modelData.index)
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
        }
      }

      // While a page is held: the edges facing other monitors, to drop it on.
      Item {
        anchors.fill: parent
        opacity: root.dragging && root.zones.length ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
        Repeater {
          model: root.zones
          Rectangle {
            id: zone
            required property var modelData
            readonly property bool hot: root.dropMonitor === modelData.name
            x: modelData.x; y: modelData.y; width: modelData.w; height: modelData.h
            radius: Style.cornerRadius
            color: root.ink(hot ? 0.14 : 0.06)
            border.width: hot ? 2 : 1
            border.color: hot ? Color.accent : root.ink(0.25)
            Behavior on color { ColorAnimation { duration: 120 } }
            Behavior on border.color { ColorAnimation { duration: 120 } }
            // The monitor itself, small, with its name: drop the page on it.
            Column {
              anchors.centerIn: parent
              spacing: Style.space(8)
              Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(zone.width, zone.height) * 0.62
                height: width * zone.modelData.aspect
                radius: Style.spaceReal(3)
                color: zone.hot ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.3) : root.ink(0.08)
                border.width: zone.hot ? 2 : 1
                border.color: zone.hot ? Color.accent : root.ink(0.6)
                Behavior on color { ColorAnimation { duration: 120 } }
              }
              Caption {
                anchors.horizontalCenter: parent.horizontalCenter
                width: zone.width
                height: implicitHeight
                text: zone.modelData.name
                opacity: zone.hot ? 0.95 : 0.6
              }
            }
          }
        }
      }

      // The window being dragged, following the pointer.
      Item {
        id: carried
        visible: root.dragging && root.dragWin !== null
        x: root.dragX
        y: root.dragY
        width: root.dragWin ? root.dragWin.w : 0
        height: root.dragWin ? root.dragWin.h : 0
        scale: root.dropMonitor ? 0.5 : 1.04
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Rectangle {
          anchors.fill: parent
          anchors.margins: -2
          radius: 4
          color: "transparent"
          border.width: 2
          border.color: Color.accent
        }
        ScreencopyView {
          anchors.fill: parent
          captureSource: carried.visible ? root.dragWin.toplevel.wayland : null
          live: true
          paintCursor: false
          constraintSize: Qt.size(carried.width * 2, carried.height * 2)
        }
      }

      Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) {
          switch (event.key) {
          case Qt.Key_Escape: if (root.dragging) root.cancelDrag(); else root.dismiss(); break
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
