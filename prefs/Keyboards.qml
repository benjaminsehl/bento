import QtQuick
import qs.Commons
import qs.Ui
import "SetupsData.js" as Data

// The Keyboard pane's Keyboards group: every keyboard Bento knows (built in,
// added by you, or seen by Hyprland) and its style. The choice goes
// to ~/.config/bento/keyboards.json, only where it differs from the built-in
// keyboards.json, and applies like any other setting. A setup can override
// it while it's in use; that's edited in the Setups pane.
Column {
  id: root

  property var store: null
  property bool macModifiers: true

  readonly property color fg: Color.foreground
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.55)
  readonly property color hairline: Qt.rgba(fg.r, fg.g, fg.b, 0.1)
  readonly property var options: Data.styles.map(function(k) { return { value: k, label: Data.styleNames[k] } })

  spacing: 0

  Item {
    width: root.width
    height: Style.spacing.panelPadding * 2.2
    Text {
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.spacing.md
      text: "Keyboards"
      color: root.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.capitalization: Font.AllUppercase
      font.letterSpacing: 0.6
    }
  }

  Text {
    width: root.width
    wrapMode: Text.WordWrap
    text: root.macModifiers
      ? "How each keyboard's shortcuts work. Mac: ⌃ ⌥ ⌘ next to Space, with Mac shortcuts. Mac on PC keys: the same shortcuts, with Ctrl, Win and Alt used as ⌃ ⌥ ⌘. PC: Omarchy's own keys, Super for the desktop and Ctrl for apps, with Bento's extras on Super."
      : "The Bento modifier layout is off, so every keyboard is PC: Omarchy's own keys, with Bento's extras on Super."
    color: root.dim
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    lineHeight: 1.15
    bottomPadding: Style.spacing.md
  }

  Text {
    width: root.width
    visible: root.macModifiers && root.store !== null && root.store.keyboardsError !== ""
    wrapMode: Text.WordWrap
    text: root.store ? root.store.keyboardsError : ""
    color: Color.urgent
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    bottomPadding: Style.spacing.md
  }

  Repeater {
    model: root.macModifiers && root.store ? root.store.keyboards : []

    Item {
      id: keyboard
      required property var modelData
      // "Not connected", and the active setup's override ("PC in Work").
      readonly property string detail: [modelData.connected === false ? "Not connected" : "", modelData.note]
        .filter(function(s) { return s !== "" }).join(" · ")

      width: root.width
      height: Math.max(choice.height, label.implicitHeight) + Style.spacing.panelPadding * 1.2

      Column {
        id: label
        anchors { left: parent.left; right: choice.left; rightMargin: Style.spacing.panelPadding; verticalCenter: parent.verticalCenter }
        spacing: 3
        Text {
          width: parent.width
          text: keyboard.modelData.label
          color: root.fg
          elide: Text.ElideRight
          font.family: Style.font.family
          font.pixelSize: Style.font.title
        }
        Text {
          width: parent.width
          visible: keyboard.detail !== ""
          text: keyboard.detail
          color: root.dim
          wrapMode: Text.WordWrap
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }

      ButtonGroup {
        id: choice
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        options: root.options
        value: keyboard.modelData.own
        enabled: root.store !== null && !root.store.busy && root.store.keyboardsError === ""
        onChanged: function(v) { if (v !== keyboard.modelData.own) root.store.setStyle(keyboard.modelData.id, v) }
      }

      Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.hairline }
    }
  }
}
