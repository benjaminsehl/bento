import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../prefs"
import "../prefs/SetupsData.js" as Data

// The bar's setups menu: Automatic, every setup (greyed, with the reason, when
// what it needs isn't connected), and "Arrange displays…", which opens the
// Setups pane. Only offered once there are two setups. Choosing runs
// bin/bento-setup, like `bento setup <name>`; if that fails, the reason shows
// at the bottom of the menu instead of closing it.
Item {
  id: root

  required property Item anchorItem
  property QtObject bar: null
  property var owner: null         // has close(); the bar's popout coordinator uses it
  property string repo: ""
  property bool open: false

  readonly property var model: Data.menuModel(store.setupState, store.file, store.editable)
  readonly property bool available: model.items.length >= 2
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool showError: store.scope === "setups" && !store.busy && store.failed && store.message !== ""
  property string switching: ""    // the id being switched to, while bento-setup runs

  // Polled slowly too, so the right-click knows when there are two setups.
  // Every bar has its own store; bento-setup's lock keeps a switch from here
  // from mixing with one from another bar, the app or the command line.
  SetupsStore { id: store; repo: root.repo; watching: true; pollInterval: 10000 }

  onOpenChanged: if (open) { store.message = ""; store.refresh() }
  onAvailableChanged: if (!available && open) close()

  function close() {
    if (root.owner && typeof root.owner.close === "function") root.owner.close()
  }

  function choose(id, alreadyChosen) {
    if (store.busy) return
    if (alreadyChosen) { close(); return }
    root.switching = id
    store.use(id)
  }

  function arrange() {
    Quickshell.execDetached([root.repo + "/bin/bento", "preferences", "setups"])
    close()
  }

  // Done: close on success, stay open to show why not.
  Connections {
    target: store
    function onBusyChanged() {
      if (store.busy) return
      root.switching = ""
      if (root.open && store.scope === "setups" && !store.failed) root.close()
    }
  }

  PopupCard {
    id: card
    anchorItem: root.anchorItem
    bar: root.bar
    owner: root.owner
    open: root.open
    padding: Style.space(8)
    borderColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.45)
    contentWidth: card.fittedContentWidth(Style.space(232))
    contentHeight: card.fittedContentHeight(rows.implicitHeight, Style.space(420))

    Column {
      id: rows
      width: parent.width
      spacing: 0

      MenuRow {
        text: "Automatic"
        note: root.switching === "auto" ? "switching…" : (root.model.now ? "now: " + root.model.now : "")
        checked: root.model.automatic
        onActivated: root.choose("auto", root.model.automatic)
      }

      Repeater {
        model: root.model.items
        MenuRow {
          required property var modelData
          text: modelData.name
          note: root.switching === modelData.id ? "switching…" : !modelData.usable ? modelData.note : (modelData.active ? "in use" : "")
          checked: modelData.chosen
          usable: modelData.usable
          onActivated: root.choose(modelData.id, modelData.chosen)
        }
      }

      Item {
        width: rows.width
        implicitHeight: Style.space(11)
        Rectangle {
          anchors { left: parent.left; leftMargin: Style.space(10); right: parent.right; rightMargin: Style.space(10); verticalCenter: parent.verticalCenter }
          height: 1
          color: Color.popups.border
          opacity: 0.45
        }
      }

      MenuRow {
        text: "Arrange displays…"
        onActivated: root.arrange()
      }

      Text {
        visible: root.showError
        width: rows.width
        leftPadding: Style.space(10)
        rightPadding: Style.space(10)
        topPadding: Style.space(6)
        bottomPadding: Style.space(4)
        wrapMode: Text.WordWrap
        text: store.message
        color: Color.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
  }

  // A row like the tray menu's: a check for the current choice, the name,
  // and a quiet note on the right.
  component MenuRow: Item {
    id: menuRow
    property string text: ""
    property string note: ""
    property bool checked: false
    property bool usable: true
    signal activated()

    width: rows.width
    implicitHeight: Style.space(30)
    opacity: usable ? 1 : 0.45

    Rectangle {
      anchors.fill: parent
      radius: Math.max(2, Style.cornerRadius)
      color: rowMouse.containsMouse && menuRow.usable ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent"
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(22)
      horizontalAlignment: Text.AlignHCenter
      text: menuRow.checked ? "" : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      id: rowText
      anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: Style.space(28) }
      width: Math.min(implicitWidth, parent.width - Style.space(38) - (rowNote.text ? Style.space(40) : 0))
      text: menuRow.text
      color: root.foreground
      elide: Text.ElideRight
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      id: rowNote
      anchors { verticalCenter: parent.verticalCenter; left: rowText.right; leftMargin: Style.space(8); right: parent.right; rightMargin: Style.space(10) }
      horizontalAlignment: Text.AlignRight
      text: menuRow.note
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.6)
      elide: Text.ElideRight
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: menuRow.usable && !store.busy
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: menuRow.activated()
    }
  }
}
