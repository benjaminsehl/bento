import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Hover popover with a live miniature of one workspace: the wallpaper plus
// each window captured with ScreencopyView at its real position and size.
PopupWindow {
  id: root

  required property Item anchorItem
  required property QtObject bar
  property int workspaceId: -1
  property bool open: false
  property string backgroundSource: ""
  property real previewWidth: Style.space(260)

  readonly property var workspace: {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) if (values[i].id === workspaceId) return values[i]
    return null
  }
  readonly property var monitor: workspace && workspace.monitor ? workspace.monitor : Hyprland.focusedMonitor
  readonly property var monitorIpc: monitor ? monitor.lastIpcObject : null
  readonly property real monitorScale: monitor && monitor.scale > 0 ? monitor.scale : 1
  readonly property bool monitorRotated: monitorIpc && monitorIpc.transform !== undefined ? (monitorIpc.transform % 2 === 1) : false
  readonly property real monitorX: monitor ? monitor.x : 0
  readonly property real monitorY: monitor ? monitor.y : 0
  readonly property real monitorW: monitor ? (monitorRotated ? monitor.height : monitor.width) / monitorScale : 1920
  readonly property real monitorH: monitor ? (monitorRotated ? monitor.width : monitor.height) / monitorScale : 1080
  readonly property real previewHeight: Math.round(previewWidth * monitorH / Math.max(1, monitorW))
  readonly property real factor: previewWidth / Math.max(1, monitorW)
  readonly property real pad: Style.space(6)
  readonly property real gap: Style.space(6)

  // Tiled first, then floating, then fullscreen, so stacking looks right.
  readonly property var windows: {
    if (!workspace) return []
    var list = workspace.toplevels.values.slice()
    function rank(t) {
      var ipc = t.lastIpcObject || {}
      return (ipc.fullscreen ? 2 : 0) + (ipc.floating ? 1 : 0)
    }
    list.sort(function(a, b) { return rank(a) - rank(b) })
    return list
  }

  onOpenChanged: if (open) {
    Hyprland.refreshToplevels()
    Hyprland.refreshMonitors()
  }

  visible: open || card.opacity > 0
  color: "transparent"
  implicitWidth: previewWidth + pad * 2
  implicitHeight: previewHeight + pad * 2

  anchor {
    item: root.anchorItem
    adjustment: PopupAdjustment.Slide
    rect.x: 0
    rect.y: root.bar && root.bar.position === "bottom" ? -root.gap : 0
    rect.width: root.anchorItem ? root.anchorItem.width : 1
    rect.height: root.anchorItem ? root.anchorItem.height + (root.bar && root.bar.position === "top" ? root.gap : 0) : 1
    edges: {
      var p = root.bar ? root.bar.position : "top"
      if (p === "bottom") return Edges.Top
      if (p === "left") return Edges.Right
      if (p === "right") return Edges.Left
      return Edges.Bottom
    }
    gravity: {
      var p = root.bar ? root.bar.position : "top"
      if (p === "bottom") return Edges.Top
      if (p === "left") return Edges.Right
      if (p === "right") return Edges.Left
      return Edges.Bottom
    }
  }

  BorderSurface {
    id: card
    anchors.fill: parent
    color: Color.popups.background
    borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, 1)
    radius: Style.cornerRadius
    opacity: root.open ? 1 : 0

    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    Item {
      id: screen
      x: root.pad
      y: root.pad
      width: root.previewWidth
      height: root.previewHeight

      layer.enabled: true
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: screenMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1
      }

      Rectangle {
        anchors.fill: parent
        color: Color.background
      }

      Image {
        anchors.fill: parent
        source: root.backgroundSource
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        sourceSize.width: root.previewWidth * 2
      }

      Repeater {
        model: root.open ? root.windows : []

        Item {
          required property var modelData
          readonly property var ipc: modelData.lastIpcObject || {}
          readonly property var at: ipc.at || [root.monitorX, root.monitorY]
          readonly property var size: ipc.size || [0, 0]

          x: Math.round((at[0] - root.monitorX) * root.factor)
          y: Math.round((at[1] - root.monitorY) * root.factor)
          width: Math.max(1, Math.round(size[0] * root.factor))
          height: Math.max(1, Math.round(size[1] * root.factor))

          // Shown until the first frame arrives (or if capture isn't possible).
          Rectangle {
            anchors.fill: parent
            visible: !capture.hasContent
            color: Qt.rgba(1, 1, 1, 0.12)
            border.color: Qt.rgba(1, 1, 1, 0.25)
            border.width: 1
            radius: 2
          }

          ScreencopyView {
            id: capture
            anchors.fill: parent
            captureSource: modelData.wayland
            live: true
            paintCursor: false
            constraintSize: Qt.size(parent.width * 2, parent.height * 2)
          }
        }
      }
    }

    Rectangle {
      id: screenMask
      x: screen.x
      y: screen.y
      width: screen.width
      height: screen.height
      radius: Math.max(2, Style.cornerRadius - root.pad / 2)
      visible: false
      layer.enabled: true
    }
  }
}
