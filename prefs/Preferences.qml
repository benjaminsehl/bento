import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import ".."
import "Schema.js" as Schema

// The Bento app: one window, a sidebar of panes, and one row per setting.
// Changes save and apply right away (bin/bento-apply); if Hyprland rejects
// one, the previous settings come back and the error shows at the bottom.
// The Setups pane and the Keyboard pane's Keyboards group edit Bento's setup
// files instead, through SetupsStore, and report in the same footer. While
// the Setups pane has a display selected, Identify outlines that screen.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property bool closingFromHost: false
  property string pane: "keyboard"

  readonly property string pluginId: (manifest && manifest.id) || "io.github.benjaminsehl.bento"
  readonly property var currentPane: {
    for (var i = 0; i < Schema.panes.length; i++) if (Schema.panes[i].id === pane) return Schema.panes[i]
    return Schema.panes[0]
  }

  Settings { id: settings }
  SetupsStore { id: setups; repo: settings.repo; watching: root.opened }

  // Where Hyprland has each display now, for the Setups pane. Quickshell
  // doesn't hear of every move (a reload), so ask again whenever the state
  // changes and after every setup change.
  readonly property var monitors: {
    var out = [], all = Hyprland.monitors.values
    for (var i = 0; i < all.length; i++) out.push(all[i].lastIpcObject)
    return out
  }
  Connections {
    target: setups
    function onSetupStateChanged() { if (root.opened) Hyprland.refreshMonitors() }
    function onBusyChanged() { if (root.opened && !setups.busy) Hyprland.refreshMonitors() }
  }

  // The screen to outline: only while the window is open and in front on the
  // Setups pane (not left behind on another workspace, under a fullscreen
  // window), and not while a change moves the displays about.
  readonly property string identifyOutput: root.opened && keys.Window.active && root.pane === "setups" && !setups.busy && setupsLoader.item
    ? setupsLoader.item.identifyOutput : ""
  Loader {
    id: identify
    active: root.identifyOutput !== ""
    source: "Identify.qml"
  }
  Binding { target: identify.item; property: "output"; value: root.identifyOutput; when: identify.item !== null }

  // Each pane opens at its top, not where the last one was scrolled to.
  // Leaving a pane also takes the keyboard back from a field it had.
  onPaneChanged: { content.bottomMargin = 0; content.contentY = 0; keys.forceActiveFocus() }

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) {}
    if (Schema.panes.some(function(p) { return p.id === payload.pane })) root.pane = payload.pane
    // Opened after being closed: at the top, with nothing left half-typed.
    // Asked for again while open, it keeps what's under way, field focus too.
    var fresh = !root.opened
    if (fresh) {
      if (setupsLoader.item) setupsLoader.item.reset()
      content.bottomMargin = 0
      content.contentY = 0
    }
    if (!setups.busy) setups.message = ""
    setups.refresh()
    Hyprland.refreshMonitors()
    root.opened = true
    window.visible = true
    if (fresh) Qt.callLater(function() { keys.forceActiveFocus() })
  }

  function close() {
    root.closingFromHost = true
    window.visible = false
    root.opened = false
    root.closingFromHost = false
  }

  function dismiss() {
    root.opened = false
    window.visible = false
  }

  // Scrolls an item into view with room below it, for a dropdown's list,
  // adding space past the end of the pane when the item is near the bottom.
  function reveal(item, below) {
    var bottom = item.mapToItem(content.contentItem, 0, 0).y + item.height + below + Style.spacing.md
    var need = bottom - content.height
    if (need <= content.contentY) return
    content.bottomMargin = Math.max(0, need - (content.contentHeight - content.height))
    content.contentY = need
  }

  // The list closed: take the extra space away again.
  function unreveal() {
    if (content.bottomMargin === 0) return
    content.bottomMargin = 0
    content.returnToBounds()
  }

  function enabled(row) {
    if (!row.requires) return true
    var parent = null
    for (var i = 0; i < Schema.panes.length; i++)
      for (var j = 0; j < Schema.panes[i].rows.length; j++) {
        var r = Schema.panes[i].rows[j]
        if (r.section === row.requires[0] && r.key === row.requires[1]) parent = r
      }
    return settings.get(row.requires[0], row.requires[1]) === true && (!parent || enabled(parent))
  }

  readonly property color fg: Color.foreground
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.55)
  readonly property color hairline: Qt.rgba(fg.r, fg.g, fg.b, 0.1)

  // The setup files' last outcome, shown on the pane it came from.
  readonly property bool setupsSpeak: (setups.busy || setups.message !== "")
    && setups.scope === (root.pane === "keyboard" ? "keyboards" : root.pane)

  FloatingWindow {
    id: window
    title: "Bento"
    visible: false
    color: Color.background
    implicitWidth: 860
    implicitHeight: 600
    minimumSize: Qt.size(640, 420)

    onVisibleChanged: {
      if (!visible && !root.closingFromHost) {
        root.opened = false
        if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
      }
    }

    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape
            || (event.key === Qt.Key_W && (event.modifiers & Qt.ControlModifier))) {
          root.dismiss(); event.accepted = true
        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
          var ids = Schema.panes.map(function(p) { return p.id })
          var i = ids.indexOf(root.pane) + (event.key === Qt.Key_Down ? 1 : -1)
          root.pane = ids[(i + ids.length) % ids.length]
          event.accepted = true
        }
      }
    }

    // ------------------------------------------------------------ sidebar
    Rectangle {
      id: sidebar
      width: 190
      anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.03)

      Text {
        id: appName
        x: Style.spacing.panelPadding
        y: Style.spacing.panelPadding
        text: "Bento"
        color: root.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.heading
        font.weight: Font.DemiBold
      }

      Column {
        anchors { top: appName.bottom; topMargin: Style.spacing.panelPadding; left: parent.left; right: parent.right; leftMargin: Style.spacing.lg; rightMargin: Style.spacing.lg }
        spacing: 2
        Repeater {
          model: Schema.panes
          Rectangle {
            required property var modelData
            readonly property bool current: root.pane === modelData.id
            width: parent.width
            height: Style.spacing.controlHeight + 4
            radius: Style.cornerRadius
            color: current ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.1)
                           : (paneArea.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05) : "transparent")
            Text {
              anchors.verticalCenter: parent.verticalCenter
              x: Style.spacing.lg + 2
              text: modelData.title
              color: parent.current ? root.fg : root.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.title
            }
            MouseArea {
              id: paneArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.pane = modelData.id
            }
          }
        }
      }
    }

    Rectangle {
      anchors { top: parent.top; bottom: parent.bottom; left: sidebar.right }
      width: 1
      color: root.hairline
    }

    // ------------------------------------------------------------ content
    Flickable {
      id: content
      anchors { top: parent.top; bottom: footer.top; left: sidebar.right; right: parent.right; leftMargin: 1 }
      contentHeight: column.implicitHeight + Style.spacing.panelPadding * 2
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: column
        x: Style.spacing.panelPadding * 1.5
        y: Style.spacing.panelPadding
        width: content.width - Style.spacing.panelPadding * 3
        spacing: 0

        Text {
          text: root.currentPane.title
          color: root.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.display
          font.weight: Font.DemiBold
          bottomPadding: Style.spacing.panelPadding
        }

        Repeater {
          model: root.currentPane.rows
          Loader {
            required property var modelData
            width: column.width
            sourceComponent: modelData.header ? headerRow : settingRow
            onLoaded: item.row = modelData
          }
        }

        // Hidden when off: a Loader keeps the size of what it last held.
        Loader {
          active: root.pane === "keyboard"
          visible: active
          width: column.width
          sourceComponent: keyboardsGroup
        }

        Loader {
          id: setupsLoader
          active: root.pane === "setups"
          visible: active
          width: column.width
          sourceComponent: setupsPane
        }

        Loader {
          active: root.pane === "about"
          visible: active
          width: column.width
          sourceComponent: aboutPane
        }
      }
    }

    // ------------------------------------------------------------- footer
    Rectangle {
      id: footer
      anchors { bottom: parent.bottom; left: sidebar.right; right: parent.right; leftMargin: 1 }
      // Up to three lines, so a failure's reason isn't cut off.
      height: Math.max(Style.spacing.controlHeight, footerText.implicitHeight) + Style.spacing.panelPadding
      color: "transparent"
      Rectangle { width: parent.width; height: 1; color: root.hairline }
      Text {
        id: footerText
        anchors { verticalCenter: parent.verticalCenter; left: parent.left; right: parent.right; leftMargin: Style.spacing.panelPadding * 1.5; rightMargin: Style.spacing.panelPadding }
        text: settings.applying ? "Applying…"
            : settings.applyError ? "Not applied, so the previous setting is back: " + settings.applyError
            : root.setupsSpeak ? (setups.busy ? setups.busyText : setups.message)
            : root.pane === "setups" && setupsLoader.item && setupsLoader.item.liveView && setupsLoader.item.displays.length > 1
              ? "Drag to arrange. It applies right away and lasts until a display or dock changes. Save it to keep it."
            : root.pane === "setups" ? "Changes to the setup in use apply right away. Others are saved for next time."
            : "Changes apply right away."
        color: settings.applyError || (root.setupsSpeak && !setups.busy && setups.failed) ? Color.urgent : root.dim
        wrapMode: Text.Wrap
        maximumLineCount: 3
        elide: Text.ElideRight
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }
  }

  // ------------------------------------------------------------- rows
  Component {
    id: headerRow
    Item {
      property var row
      height: Style.spacing.panelPadding * 2.2
      Text {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.spacing.md
        text: row ? row.header : ""
        color: root.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.6
      }
    }
  }

  Component {
    id: settingRow
    Item {
      id: rowItem
      property var row
      readonly property bool on: row ? root.enabled(row) : true
      readonly property var value: row ? settings.get(row.section, row.key) : undefined
      height: Math.max(control.height, label.implicitHeight) + Style.spacing.panelPadding * 1.2
      opacity: on ? 1 : 0.4
      Behavior on opacity { NumberAnimation { duration: 120 } }

      Column {
        id: label
        anchors { left: parent.left; right: control.left; rightMargin: Style.spacing.panelPadding; verticalCenter: parent.verticalCenter }
        spacing: 3
        Text {
          width: parent.width
          text: rowItem.row ? rowItem.row.title : ""
          color: root.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.title
        }
        Text {
          width: parent.width
          text: rowItem.row ? rowItem.row.detail : ""
          color: root.dim
          wrapMode: Text.WordWrap
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          lineHeight: 1.15
        }
      }

      Loader {
        id: control
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        enabled: rowItem.on
        sourceComponent: !rowItem.row ? null
          : rowItem.row.type === "bool" ? boolControl
          : rowItem.row.type === "choice" ? choiceControl
          : numberControl
        onLoaded: item.rowItem = rowItem
      }

      Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.hairline }
    }
  }

  Component {
    id: boolControl
    ToggleSwitch {
      property var rowItem
      checked: rowItem ? rowItem.value === true : false
      interactive: rowItem ? rowItem.on : false
      busy: settings.applying
      onToggled: settings.set(rowItem.row.section, rowItem.row.key, !checked)
    }
  }

  Component {
    id: choiceControl
    ButtonGroup {
      property var rowItem
      options: rowItem ? rowItem.row.options : []
      value: rowItem ? String(rowItem.value) : ""
      onChanged: function(v) { settings.set(rowItem.row.section, rowItem.row.key, v) }
    }
  }

  Component {
    id: numberControl
    Row {
      property var rowItem
      spacing: Style.spacing.lg
      PanelSlider {
        id: slider
        width: 200
        anchors.verticalCenter: parent.verticalCenter
        minimum: parent.rowItem ? parent.rowItem.row.min : 0
        maximum: parent.rowItem ? parent.rowItem.row.max : 1
        step: parent.rowItem ? parent.rowItem.row.step : 1
        integer: true
        value: parent.rowItem ? Number(parent.rowItem.value) : 0
        trackColor: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.15)
        onReleased: function(v) { settings.set(parent.rowItem.row.section, parent.rowItem.row.key, Math.round(v)) }
      }
      Text {
        width: 56
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(slider.liveValue) + " " + (parent.rowItem ? parent.rowItem.row.unit : "")
        color: root.dim
        horizontalAlignment: Text.AlignRight
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }
  }

  Component {
    id: keyboardsGroup
    Keyboards {
      store: setups
      macModifiers: settings.get("keyboard", "macModifiers") === true
    }
  }

  Component {
    id: setupsPane
    Setups {
      store: setups
      monitors: root.monitors
      macModifiers: settings.get("keyboard", "macModifiers") === true
      onDoneTyping: { root.unreveal(); keys.forceActiveFocus() }
      onReveal: function(item, below) { root.reveal(item, below) }
    }
  }

  Component {
    id: aboutPane
    Column {
      spacing: Style.spacing.panelPadding
      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Omarchy, thoughtfully arranged. Pages instead of numbered workspaces, Overview, a drawer for minimized windows, a keyboard layout that gives apps their native shortcuts, and trackpad gestures that follow your fingers. Each piece can be switched off on its own."
        color: root.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        lineHeight: 1.2
      }
      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Settings live in " + settings.path.replace(Quickshell.env("HOME"), "~") + ". Only what differs from the defaults is saved, so new defaults reach you."
        color: root.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
      Flow {
        width: parent.width
        spacing: Style.spacing.lg
        Button {
          text: "Restore defaults"
          bordered: true
          onClicked: settings.reset()
        }
        Button {
          text: "Show keyboard shortcuts"
          bordered: true
          onClicked: Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/mac-keybindings"])
        }
        Button {
          text: "github.com/benjaminsehl/bento"
          onClicked: Quickshell.execDetached(["xdg-open", "https://github.com/benjaminsehl/bento"])
        }
      }
    }
  }
}
