import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.Commons

// omac's minimized-window drawer, like the iPad app switcher: minimized
// windows (⌘M puts them on the hidden "special:minimized" workspace) shrink
// into cards on a scrollable strip that drops from the top.
//
//   click / ↩        restore the window to the current workspace
//   swipe a card up,
//   middle-click, ⌫  close the window
//   ← →              choose a card
//   Esc / click away close the drawer
//
// Hyprland opens it (four fingers down, ⌃↓). The drawer tells Hyprland when
// it's open, so four fingers up can close it again.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool shown: false
  property int selectedIndex: 0
  property var cards: []

  readonly property string pluginId: (manifest && manifest.id) || "io.github.benjaminsehl.omac"

  function minimizedToplevels() {
    var out = []
    var all = Hyprland.toplevels.values
    for (var i = 0; i < all.length; i++) {
      var t = all[i]
      if (t.workspace && t.workspace.name === "special:minimized") out.push(t)
    }
    return out
  }

  function refresh() {
    root.cards = minimizedToplevels()
    if (root.selectedIndex >= root.cards.length) root.selectedIndex = Math.max(0, root.cards.length - 1)
    if (root.opened && root.cards.length === 0) root.dismiss()
  }

  function address(t) {
    var a = t.address || ""
    return a.indexOf("0x") === 0 ? a : "0x" + a
  }

  function tellHyprland(open) {
    hyprState.command = ["hyprctl", "eval", "_G.omac_drawer_open = " + (open ? "true" : "false")]
    hyprState.running = true
  }

  function open(payloadJson) {
    Hyprland.refreshToplevels()
    Hyprland.refreshWorkspaces()
    root.selectedIndex = 0
    root.cards = minimizedToplevels()
    root.opened = true
    root.tellHyprland(true)
    Qt.callLater(function() {
      root.shown = true
      keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    root.shown = false
    root.opened = false
    root.tellHyprland(false)
  }

  // Slide up and away, then let the host unload us.
  function dismiss() {
    if (!root.opened) return
    root.shown = false
    closeTimer.restart()
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function restore(t) {
    if (!t) return
    var monitor = Hyprland.focusedMonitor
    var ws = monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : 1
    var a = address(t)
    Hyprland.dispatch('hl.dsp.window.move({ window = "address:' + a + '", workspace = "' + ws + '", follow = false })')
    Hyprland.dispatch('hl.dsp.focus({ window = "address:' + a + '" })')
    root.dismiss()
  }

  function closeWindow(t) {
    if (!t) return
    Hyprland.dispatch('hl.dsp.window.close({ window = "address:' + address(t) + '" })')
    refreshTimer.restart()
  }

  Process { id: hyprState }

  Timer {
    id: closeTimer
    interval: 200
    onTriggered: {
      root.opened = false
      root.tellHyprland(false)
      if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    }
  }

  // Closing a window takes a moment to show up in Hyprland's list.
  Timer {
    id: refreshTimer
    interval: 250
    onTriggered: { Hyprland.refreshToplevels(); root.refresh() }
  }

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() { if (root.opened) root.refresh() }
  }

  function focusedScreen() {
    var name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      if (screens[i].name === name) return screens[i]
    }
    return screens.length > 0 ? screens[0] : null
  }

  PanelWindow {
    id: panel
    visible: root.opened
    screen: root.focusedScreen()
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omac-drawer"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    readonly property int cardHeight: Math.round(height * 0.34)
    readonly property int labelHeight: Math.max(Style.space(28), Style.font.body + Style.spacing.md)

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
      opacity: root.shown ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(event) {
        var n = root.cards.length
        if (event.key === Qt.Key_Escape) {
          root.dismiss()
        } else if (event.key === Qt.Key_Left && n > 0) {
          root.selectedIndex = (root.selectedIndex - 1 + n) % n
          strip.positionViewAtIndex(root.selectedIndex, ListView.Contain)
        } else if ((event.key === Qt.Key_Right || event.key === Qt.Key_Tab) && n > 0) {
          root.selectedIndex = (root.selectedIndex + 1) % n
          strip.positionViewAtIndex(root.selectedIndex, ListView.Contain)
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
          root.restore(root.cards[root.selectedIndex])
        } else if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete
                   || (event.key === Qt.Key_W && (event.modifiers & Qt.ControlModifier))) {
          root.closeWindow(root.cards[root.selectedIndex])
        } else {
          return
        }
        event.accepted = true
      }
    }

    // The strip drops from the top, the way four fingers down opens it, and
    // goes back up when it closes.
    Item {
      id: drawer
      width: parent.width
      height: panel.cardHeight + panel.labelHeight + Style.spacing.md * 2
      y: root.shown ? Math.round((parent.height - height) / 2) : -height
      Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

      ListView {
        id: strip
        anchors.fill: parent
        orientation: ListView.Horizontal
        spacing: Style.spacing.lg * 2
        model: root.cards
        clip: false
        boundsBehavior: Flickable.StopAtBounds
        // Few cards sit in the middle; many scroll.
        // Always some room at the screen edges, even scrolled all the way.
        readonly property int edge: Math.round(width * 0.05)
        leftMargin: Math.max(edge, (width - contentWidth) / 2)
        rightMargin: edge

        // Scrolling is handled by stripScroll below.
        interactive: false

        delegate: Item {
          id: card
          required property var modelData
          required property int index

          readonly property var size: modelData.lastIpcObject && modelData.lastIpcObject.size
          readonly property real aspect: size && size[1] > 0 ? size[0] / size[1] : 1.6
          readonly property bool selected: index === root.selectedIndex

          width: Math.round(panel.cardHeight * Math.min(Math.max(aspect, 0.6), 2.4))
          height: strip.height

          Item {
            id: lift
            width: parent.width
            height: parent.height
            y: 0

            Rectangle {
              id: frame
              width: parent.width
              height: panel.cardHeight
              y: Style.spacing.md
              radius: Style.cornerRadius
              color: Color.menu.background
              border.width: card.selected ? Math.max(2, Style.space(3)) : 1
              border.color: card.selected ? Color.menu.text : Color.menu.border
              clip: true

              ScreencopyView {
                id: thumb
                anchors.fill: parent
                anchors.margins: frame.border.width
                captureSource: card.modelData.wayland
                live: root.opened
              }

              Text {
                anchors.centerIn: parent
                visible: !thumb.hasContent
                text: (card.modelData.lastIpcObject && card.modelData.lastIpcObject.class) || "Window"
                color: Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.title
              }
            }

            Text {
              anchors.top: frame.bottom
              anchors.topMargin: Style.spacing.sm
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              text: card.modelData.title || ""
              color: Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
            }

            MouseArea {
              id: cardMouse
              property bool swiped: false
              anchors.fill: frame
              anchors.topMargin: Style.spacing.md
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton | Qt.MiddleButton
              drag.target: lift
              drag.axis: Drag.YAxis
              drag.maximumY: 0
              drag.minimumY: -panel.height
              onEntered: root.selectedIndex = card.index
              onPressed: swiped = false
              onReleased: function(mouse) {
                // Moved more than a few pixels: a swipe, not a click. Past a
                // third of the card up, it closes the window.
                swiped = lift.y < -4
                if (lift.y < -panel.cardHeight / 3) root.closeWindow(card.modelData)
                lift.y = 0
              }
              onClicked: function(mouse) {
                if (swiped) return
                if (mouse.button === Qt.MiddleButton) root.closeWindow(card.modelData)
                else root.restore(card.modelData)
              }
            }

            Behavior on y { enabled: !cardMouse.drag.active; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
          }
        }
      }

      // Two fingers, sideways or up and down, move the strip with the fingers.
      // Omarchy scales touchpad scrolling down (scroll_factor 0.4) and Qt's
      // own wheel handling is slow on top of that, so move it here instead.
      // No buttons: clicks and drags still reach the cards.
      MouseArea {
        id: stripScroll
        anchors.fill: strip
        acceptedButtons: Qt.NoButton
        readonly property real speed: 5

        onWheel: function(wheel) {
          var px = wheel.pixelDelta
          var d
          if (px.x !== 0 || px.y !== 0) {
            d = Math.abs(px.x) > Math.abs(px.y) ? px.x : px.y
          } else {
            var a = wheel.angleDelta
            d = (Math.abs(a.x) > Math.abs(a.y) ? a.x : a.y) / 2
          }
          var min = -strip.leftMargin
          var max = Math.max(min, strip.contentWidth - strip.width + strip.rightMargin)
          strip.contentX = Math.min(max, Math.max(min, strip.contentX - d * speed))
          wheel.accepted = true
        }
      }
    }
  }
}
