import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Which display is which: a thin accent frame around the whole of the screen
// whose connector is `output` (the Setups pane's identifyOutput), and
// nothing anywhere else. It never takes the pointer or the keyboard.
//
// The window loads this file only while it has an output to show, and by
// name: a PanelWindow needs a backend that offscreen test runs don't have.
Item {
  id: root

  property string output: ""

  Variants {
    model: {
      var out = []
      for (var i = 0; i < Quickshell.screens.length; i++)
        if (root.output !== "" && Quickshell.screens[i].name === root.output) out.push(Quickshell.screens[i])
      return out
    }

    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData

      // Re-placed after a reload moves the screen.
      visible: !remap.remapping
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      WlrLayershell.namespace: "bento-identify"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      mask: Region {}

      ScreenMoveRemap { id: remap; window: panel }

      Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: 3
        border.color: Color.accent
      }
    }
  }
}
