import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Page dots: one dot per existing workspace. Hyprland destroys empty
// workspaces when you leave them, so empty pages simply vanish. The focused
// page is always shown (even if empty) as a wider, brighter pill.
BarWidget {
  id: root
  moduleName: "io.github.benjaminsehl.pages"

  readonly property int focusedId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1

  readonly property var pageIds: {
    var ids = []
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var ws = values[i]
      if (ws.id <= 0) continue // skip special workspaces
      if (ws.toplevels.values.length > 0 || ws.id === root.focusedId) ids.push(ws.id)
    }
    if (root.focusedId > 0 && ids.indexOf(root.focusedId) === -1) ids.push(root.focusedId)
    ids.sort(function(a, b) { return a - b })
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  readonly property real dotSize: Style.spaceReal(4)
  readonly property real pillLength: dotSize * 2.4
  readonly property real slot: Style.spaceReal(11)
  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: row.implicitWidth + trailingGap
  implicitHeight: row.implicitHeight

  GridLayout {
    id: row
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : Math.max(1, root.pageIds.length)
    columnSpacing: 0
    rowSpacing: 0

    Repeater {
      model: root.pageIds

      WidgetButton {
        id: page
        required property int modelData
        readonly property bool focused: modelData === root.focusedId

        bar: root.bar
        hasVisualContent: true
        labelVisible: false
        tooltipText: "Page " + modelData
        fixedWidth: root.vertical ? root.barSize : (focused ? root.pillLength + root.slot - root.dotSize : root.slot)
        fixedHeight: root.vertical ? (focused ? root.pillLength + root.slot - root.dotSize : root.slot) : root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }

        Behavior on fixedWidth { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on fixedHeight { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        Rectangle {
          anchors.centerIn: parent
          width: root.vertical ? root.dotSize : (page.focused ? root.pillLength : root.dotSize)
          height: root.vertical ? (page.focused ? root.pillLength : root.dotSize) : root.dotSize
          radius: root.dotSize / 2
          color: page.foreground
          opacity: page.focused ? 1 : 0.5

          Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
          Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
          Behavior on opacity { NumberAnimation { duration: 160 } }
        }
      }
    }
  }
}
