import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import ".."
import "../Windows.js" as Windows

// Page dots: one dot per workspace on this bar's monitor, so every monitor
// has its own row. Hyprland destroys empty workspaces when you leave them, so
// empty pages simply vanish. The page the monitor shows is always there (even
// if empty) as a wider, brighter pill. Hover a dot for a live preview of that
// page. Sizes and previews come from Bento's settings (the "pages" section).
//
// With dots off, the widget shows Omarchy's own workspace numbers instead,
// loaded from Omarchy's widget so they look exactly stock. Once you have two
// setups, right-click the dots or the numbers (or the display icon after the
// numbers) for the setups menu (SetupsMenu.qml).
BarWidget {
  id: root
  moduleName: "io.github.benjaminsehl.bento"

  Settings { id: settings }
  readonly property bool previewsOn: settings.get("pages", "previews") !== false
  readonly property int previewDelay: Number(settings.get("pages", "previewDelay")) || 250
  readonly property real previewWidth: Number(settings.get("pages", "previewWidth")) || 260

  // Dots off: Omarchy's Workspaces.qml, from the same place the shell loads
  // it. If it can't load, the dots stay rather than leaving a hole.
  readonly property bool numbersWanted: settings.get("pages", "dots") === false
  readonly property bool showNumbers: numbersWanted && stock.status === Loader.Ready
  readonly property string stockWorkspaces: (Quickshell.env("OMARCHY_PATH") ? Quickshell.env("OMARCHY_PATH") + "/shell" : Quickshell.shellDir)
    + "/plugins/bar/widgets/Workspaces.qml"

  // The setups menu. Opening it closes any page preview.
  property bool menuOpen: false
  function close() { root.menuOpen = false }
  function toggleMenu() { root.menuOpen = !root.menuOpen }

  // The monitor this copy of the bar is on (there's one per monitor).
  readonly property var barScreen: root.QsWindow.window ? root.QsWindow.window.screen : null
  readonly property var monitor: (root.barScreen && Hyprland.monitorFor(root.barScreen)) || Hyprland.focusedMonitor
  readonly property string monitorName: root.monitor ? root.monitor.name : ""
  readonly property int focusedId: root.monitor && root.monitor.activeWorkspace ? root.monitor.activeWorkspace.id : -1
  readonly property string backgroundSource: "file://" + Quickshell.env("HOME") + "/.local/state/omarchy/current/background"

  // Once a preview has been shown, sliding to a neighbouring dot previews it
  // immediately instead of waiting out the hover delay again.
  property bool previewWarm: false
  property int openPreviews: 0
  onOpenPreviewsChanged: if (openPreviews > 0) { previewWarm = true; coolDown.stop() } else coolDown.restart()
  Timer { id: coolDown; interval: 400; onTriggered: root.previewWarm = false }

  readonly property var pageIds: {
    var ids = []
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var ws = values[i]
      if (ws.id <= 0) continue // skip special workspaces
      if (root.monitorName && ws.monitor && ws.monitor.name !== root.monitorName) continue
      if (Windows.live(ws.toplevels.values).length > 0 || ws.id === root.focusedId) ids.push(ws.id)
    }
    if (root.focusedId > 0 && ids.indexOf(root.focusedId) === -1) ids.push(root.focusedId)
    ids.sort(function(a, b) { return a - b })
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  readonly property real dotSize: Style.spaceReal(Number(settings.get("pages", "dotSize")) || 4)
  readonly property real pillLength: dotSize * 2.4
  readonly property real slot: Math.max(Style.spaceReal(11), dotSize * 2.75)
  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: root.showNumbers ? numbers.implicitWidth : row.implicitWidth + trailingGap
  implicitHeight: root.showNumbers ? numbers.implicitHeight : row.implicitHeight

  SetupsMenu {
    id: setupsMenu
    anchorItem: root
    bar: root.bar
    owner: root
    repo: settings.repo
    open: root.menuOpen
  }

  GridLayout {
    id: row
    visible: !root.showNumbers
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : Math.max(1, root.pageIds.length)
    columnSpacing: 0
    rowSpacing: 0

    Repeater {
      model: root.showNumbers ? [] : root.pageIds

      WidgetButton {
        id: page
        required property int modelData
        readonly property bool focused: modelData === root.focusedId

        bar: root.bar
        hasVisualContent: true
        labelVisible: false
        readonly property bool hovering: page.tooltipHovered
        property bool previewOpen: false
        onPreviewOpenChanged: root.openPreviews += previewOpen ? 1 : -1
        Component.onDestruction: if (previewOpen) root.openPreviews -= 1
        onHoveringChanged: {
          if (!hovering) { hoverDelay.stop(); previewOpen = false }
          else if (!focused && root.previewsOn && !root.menuOpen) { if (root.previewWarm) previewOpen = true; else hoverDelay.restart() }
        }
        onFocusedChanged: if (focused) { hoverDelay.stop(); previewOpen = false }
        readonly property bool menuOpen: root.menuOpen
        onMenuOpenChanged: if (menuOpen) { hoverDelay.stop(); previewOpen = false }

        Timer { id: hoverDelay; interval: root.previewDelay; onTriggered: page.previewOpen = page.hovering && !page.focused && !root.menuOpen }

        PagePreview {
          anchorItem: page
          bar: root.bar
          workspaceId: page.modelData
          backgroundSource: root.backgroundSource
          previewWidth: Style.space(root.previewWidth)
          open: page.previewOpen
        }
        fixedWidth: root.vertical ? root.barSize : (focused ? root.pillLength + root.slot - root.dotSize : root.slot)
        fixedHeight: root.vertical ? (focused ? root.pillLength + root.slot - root.dotSize : root.slot) : root.barSize
        onPressed: function(button) {
          if (button === Qt.RightButton && setupsMenu.available) root.toggleMenu()
          else root.focusWorkspace(modelData)
        }

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

  Grid {
    id: numbers
    visible: root.showNumbers
    columns: root.vertical ? 1 : 2

    Loader {
      id: stock
      active: root.numbersWanted
      source: active ? Util.fileUrl(root.stockWorkspaces) : ""
      onLoaded: item.bar = Qt.binding(function() { return root.bar })

      // Right-click opens the setups menu; other clicks reach the numbers.
      // Above the loaded widget (z), which the Loader adds after this.
      MouseArea {
        anchors.fill: parent
        z: 1
        acceptedButtons: Qt.RightButton
        enabled: setupsMenu.available
        onClicked: root.toggleMenu()
      }
    }

    BarIconButton {
      bar: root.bar
      visible: setupsMenu.available
      text: "\uDB80\uDF79"
      onPressed: function() { root.toggleMenu() }
    }
  }
}
