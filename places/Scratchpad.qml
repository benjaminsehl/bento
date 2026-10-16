import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Effects
import qs.Commons
import "../motion/Motion.js" as Motion

// The scratchpad's stand-in. Hyprland can't move a hidden workspace with
// your fingers, so while the scratchpad is moving Bento draws live captures
// of its windows instead, exactly where Hyprland shows them, rising from
// below the screen. At rest the real scratchpad takes over (Overlay.qml does
// the hand-off).
//
// One surface does all of it, so nothing appears or disappears at a hand-off:
//
//   moving    the captures and the fade, drawn by Bento
//   at rest   the real windows show through holes in Bento's fade, and the
//             pointer only gets through to them: the page underneath can't
//             take a click or (following the mouse) focus. A click anywhere
//             else puts the scratchpad away.
//
// The page fades the way it does behind the drawer: towards the theme's
// background, so lighter on a light theme and darker on a dark one. Bento
// draws it in both states (Hyprland's own dim is off while the shell runs), so
// there's never a second one to swap with.
Item {
  id: root

  // 0 hidden, 1 in place. Slightly past 1 while a spring lands.
  property real progress: 0
  // The stand-in is wanted: the scratchpad is moving or on its way.
  property bool shown: false
  // Hyprland is showing the real scratchpad.
  property bool realUp: false
  // The real scratchpad is up and at rest.
  property bool guarding: false
  // HyprlandToplevels on special:scratchpad.
  property var windows: []

  // A click outside the scratchpad's windows.
  signal outsideClicked()

  // Hyprland's look, so the hand-off doesn't show.
  property int borderSize: 2
  property int rounding: 0
  property color activeBorder: "#ffffff"
  property color inactiveBorder: "#595959"

  // Every capture has a frame: the stand-in looks exactly like the real thing
  // and is drawn over it.
  readonly property bool covering: {
    if (!root.shown) return false
    for (var i = 0; i < repeater.count; i++) {
      var item = repeater.itemAt(i)
      if (item && !item.hasContent) return false
    }
    return true
  }
  // ...and has been for a frame, so it's on screen: the real one can hide.
  property bool ready: false
  onCoveringChanged: { root.ready = false; if (root.covering) readyTimer.restart(); else readyTimer.stop() }
  Timer { id: readyTimer; interval: 20; onTriggered: root.ready = root.covering }

  readonly property var monitor: Hyprland.focusedMonitor
  readonly property real monScale: monitor && monitor.scale > 0 ? monitor.scale : 1
  readonly property real monX: monitor ? monitor.x : 0
  readonly property real monY: monitor ? monitor.y : 0
  readonly property real monH: monitor ? monitor.height / monScale : 1080

  readonly property real lift: Math.max(0, root.progress)
  // The windows rise together, from just below the bottom of the screen: the
  // whole way is from there up to where the topmost one sits.
  readonly property real highest: {
    var t = root.monH
    for (var i = 0; i < root.windows.length; i++) {
      var ipc = root.windows[i].lastIpcObject || {}
      if (ipc.at) t = Math.min(t, ipc.at[1] - root.monY - root.borderSize)
    }
    return t
  }
  readonly property real offset: (1 - root.lift) * (root.monH - root.highest)

  function focusedScreen() {
    var name = monitor ? monitor.name : ""
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) if (screens[i].name === name) return screens[i]
    return screens.length ? screens[0] : null
  }

  // The page: the screen below the bar. Dimmed, and guarded at rest.
  readonly property var reserved: (monitor && monitor.lastIpcObject && monitor.lastIpcObject.reserved) || [0, 0, 0, 0]

  // Where the scratchpad's windows are at rest, borders included.
  property int _tick: 0
  readonly property var rects: {
    root._tick
    var out = []
    for (var i = 0; i < root.windows.length; i++) {
      var ipc = root.windows[i].lastIpcObject || {}
      if (!ipc.at || !ipc.size) continue
      out.push({
        x: Math.round(ipc.at[0] - root.monX - root.borderSize),
        y: Math.round(ipc.at[1] - root.monY - root.borderSize),
        width: Math.round(ipc.size[0] + root.borderSize * 2),
        height: Math.round(ipc.size[1] + root.borderSize * 2)
      })
    }
    return out
  }
  onRectsChanged: punchHoles()

  // Windows can move without an event saying so; look again now and then.
  Timer {
    interval: 400
    repeat: true
    running: root.guarding
    onTriggered: { Hyprland.refreshToplevels(); root._tick++ }
  }

  // The real windows show through Bento's fade until the captures cover them.
  readonly property bool holesOpen: root.realUp && !root.covering
  readonly property bool guardOn: root.guarding && !root.shown

  function punchHoles() {
    var old = []
    for (var i = 0; i < guardMask.regions.length; i++) old.push(guardMask.regions[i])
    var list = []
    for (var j = 0; j < root.rects.length; j++) list.push(hole.createObject(guardMask, root.rects[j]))
    guardMask.regions = list
    for (var k = 0; k < old.length; k++) old[k].destroy()
  }

  // The surface stays up from the moment it's wanted until it hasn't been for
  // a moment. Handing over (moving to resting and back) can leave it unwanted
  // for an instant; unmapping then would bring it back without frames.
  readonly property bool wanted: root.shown || root.guarding || root.realUp
  property bool mapped: false
  onWantedChanged: {
    if (root.wanted) { unmapTimer.stop(); root.mapped = true }
    else unmapTimer.restart()
  }
  Timer { id: unmapTimer; interval: 150; onTriggered: root.mapped = root.wanted }

  Component {
    id: hole
    Region { intersection: Intersection.Subtract }
  }

  PanelWindow {
    id: panel
    visible: root.mapped
    screen: root.focusedScreen()
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "bento-scratchpad"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // At rest, the page takes no pointer except through the windows' holes.
    // Moving, nothing does.
    mask: Region {
      id: guardMask
      x: root.reserved[0]
      y: root.reserved[1]
      width: root.guardOn ? panel.width - root.reserved[0] - root.reserved[2] : 0
      height: root.guardOn ? panel.height - root.reserved[1] - root.reserved[3] : 0
    }

    MouseArea {
      anchors.fill: parent
      enabled: root.guardOn
      acceptedButtons: Qt.AllButtons
      onClicked: root.outsideClicked()
    }

    // The fade over the page, with holes for the real windows while they show.
    Item {
      anchors.fill: parent
      opacity: Motion.clamp(root.lift, 0, 1)
      layer.enabled: true
      layer.effect: MultiEffect {
        maskEnabled: true
        maskInverted: true
        maskSource: holes
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
      }
      Rectangle {
        x: root.reserved[0]
        y: root.reserved[1]
        width: parent.width - root.reserved[0] - root.reserved[2]
        height: parent.height - root.reserved[1] - root.reserved[3]
        color: Color.menu.scrim
      }
    }

    Item {
      id: holes
      anchors.fill: parent
      visible: false
      layer.enabled: true
      Repeater {
        model: root.holesOpen ? root.rects : []
        Rectangle {
          required property var modelData
          x: modelData.x; y: modelData.y; width: modelData.width; height: modelData.height
          radius: root.rounding > 0 ? root.rounding + root.borderSize : 0
          color: "black"
        }
      }
    }

    // The captures. They run whenever the surface is up, so they already have
    // frames when fingers take hold, and show once they can cover the real
    // windows (or when there are none to cover). Clipped to the page: a flick
    // lands a little past its place and mustn't cover the bar.
    Item {
      x: root.reserved[0]
      y: root.reserved[1]
      width: parent.width - root.reserved[0] - root.reserved[2]
      height: parent.height - root.reserved[1] - root.reserved[3]
      clip: true
      opacity: root.shown && (root.covering || !root.realUp) ? 1 : 0

      Repeater {
        id: repeater
        model: root.windows
        delegate: Item {
          id: win
          required property var modelData
          required property int index
          readonly property var ipc: modelData.lastIpcObject || ({})
          readonly property bool hasContent: capture.hasContent
          readonly property bool focused: Hyprland.activeToplevel === modelData || (index === 0 && !root.windows.some(function(w) { return Hyprland.activeToplevel === w }))

          x: (ipc.at ? ipc.at[0] : 0) - root.monX - root.reserved[0]
          y: (ipc.at ? ipc.at[1] : 0) - root.monY - root.reserved[1] + root.offset
          width: ipc.size ? ipc.size[0] : 0
          height: ipc.size ? ipc.size[1] : 0

          // Hyprland draws the border outside the window.
          Rectangle {
            anchors.fill: parent
            anchors.margins: -root.borderSize
            radius: root.rounding > 0 ? root.rounding + root.borderSize : 0
            color: "transparent"
            border.width: root.borderSize
            border.color: win.focused ? root.activeBorder : root.inactiveBorder
          }

          ScreencopyView {
            id: capture
            anchors.fill: parent
            captureSource: win.modelData.wayland
            live: root.mapped
            layer.enabled: root.rounding > 0
            layer.effect: MultiEffect {
              maskEnabled: true
              maskSource: corners
              maskThresholdMin: 0.5
              maskSpreadAtMin: 1.0
            }
          }

          Item {
            id: corners
            anchors.fill: parent
            visible: false
            layer.enabled: true
            Rectangle { anchors.fill: parent; radius: root.rounding; color: "black" }
          }
        }
      }
    }

    // Nothing in the scratchpad: say so, honestly, as it gives and springs back.
    Rectangle {
      visible: root.windows.length === 0
      anchors.horizontalCenter: parent.horizontalCenter
      y: parent.height - Math.min(1, root.lift / Motion.pull.rubberLimit) * (height + Style.space(56))
      width: emptyLabel.implicitWidth + Style.spacing.lg * 2
      height: emptyLabel.implicitHeight + Style.spacing.md * 2
      radius: height / 2
      color: Color.menu.background
      border.width: 1
      border.color: Color.menu.border
      opacity: Math.min(1, root.lift / (Motion.pull.rubberLimit * 0.5))

      Text {
        id: emptyLabel
        anchors.centerIn: parent
        text: "The scratchpad is empty"
        color: Color.menu.text
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.body
      }
    }
  }
}
