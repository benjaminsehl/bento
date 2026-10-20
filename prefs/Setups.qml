import QtQuick
import qs.Commons
import qs.Ui
import "SetupsData.js" as Data

// The Setups pane. A setup remembers a desk: its displays, how they're
// arranged and scaled, and each keyboard's keymap. Bento uses the one whose
// devices are connected, or the one you hold by hand. The radio on the left
// of each setup uses it; clicking the setup itself shows it below to edit.
// Edits to the setup in use apply right away (and roll back if Hyprland's
// check fails); a new name, or an edit to any other setup, is only saved.
// All reads and writes go through SetupsStore.
Column {
  id: root

  property var store: null
  property bool macModifiers: true
  // A text field or dropdown had the keyboard; the window wants it back.
  signal doneTyping()

  readonly property color fg: Color.foreground
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.55)
  readonly property color faint: Qt.rgba(fg.r, fg.g, fg.b, 0.3)
  readonly property color hairline: Qt.rgba(fg.r, fg.g, fg.b, 0.1)

  readonly property var setupState: store ? store.setupState : null
  readonly property var file: store ? store.file : null
  readonly property var all: store ? store.setups : []
  readonly property bool hasState: setupState !== null
  readonly property bool idle: store !== null && !store.busy
  readonly property bool editable: idle && store.editable
  readonly property var laptopScale: store ? store.laptopScale : null
  // Omarchy's scales, for the laptop panel and for every other display.
  readonly property var omarchyScales: ({ laptop: laptopScale, external: store ? store.externalScale : null })
  readonly property var rows: Data.paneModel(setupState, file)
  readonly property var menu: Data.menuModel(setupState, file, true)

  // The setup shown below the list: your pick, else the one in use.
  property string pickedId: ""
  readonly property var selected: Data.byId(all, pickedId) || Data.byId(all, store ? store.activeId : "") || (all.length ? all[0] : null)
  readonly property string selectedId: selected ? selected.id : ""
  readonly property var selectedRow: Data.byId(rows, selectedId)
  // Its displays as listed: one row per display, never a phantom tile (see
  // Data.shownDisplays). Edits go by each one's place in setups.json.
  readonly property var shown: selected ? Data.shownDisplays(selected) : []
  readonly property var displays: shown.map(function(x) { return x.entry })
  readonly property var choices: selected ? Data.whenChoices(selected, setupState) : []
  property int selectedDisplay: 0

  function fileIndex(row) { return root.shown[row] ? root.shown[row].index : -1 }

  property bool naming: false
  property bool renaming: false
  property bool confirmingDelete: false

  onSelectedIdChanged: { selectedDisplay = 0; renaming = false; confirmingDelete = false }

  function edit(change, note) { if (root.editable) root.store.editSetup(root.selectedId, change, note) }

  Connections {
    target: root.store
    function onSaved(id) { root.pickedId = id; root.naming = false; root.doneTyping() }
  }

  spacing: 0

  // ------------------------------------------------------------- notices
  Text {
    width: root.width
    visible: text !== ""
    wrapMode: Text.WordWrap
    text: root.store ? root.store.fileError : ""
    color: Color.urgent
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    bottomPadding: Style.spacing.lg
  }

  Text {
    width: root.width
    visible: !root.hasState
    wrapMode: Text.WordWrap
    text: "Hyprland hasn't told Bento which displays are connected yet, so setups can't be used or saved right now."
    color: root.dim
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    bottomPadding: Style.spacing.lg
  }

  Repeater {
    model: root.setupState ? Data.list(root.setupState.problems) : []
    Text {
      required property var modelData
      width: root.width
      wrapMode: Text.WordWrap
      text: "setups.json: " + String(modelData)
      color: Color.urgent
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      bottomPadding: Style.spacing.sm
    }
  }

  // ---------------------------------------------------------- empty state
  Text {
    width: root.width
    visible: root.all.length === 0
    wrapMode: Text.WordWrap
    text: "No setups yet. Arrange your displays the way you like them at this desk, then save it, and Bento brings it back whenever you're here."
    color: root.fg
    font.family: Style.font.family
    font.pixelSize: Style.font.title
    lineHeight: 1.2
    bottomPadding: Style.spacing.panelPadding
  }

  // ------------------------------------------------------------ the list
  Column {
    width: root.width
    visible: root.all.length > 0
    spacing: 0

    ChoiceRow {
      name: "Automatic"
      note: root.menu.now ? "now: " + root.menu.now : (root.hasState ? "nothing matches now" : "")
      chosen: root.menu.automatic
      usable: root.hasState
      onUse: if (!root.menu.automatic) root.store.use("auto")
      onPick: if (!root.menu.automatic) root.store.use("auto")
    }

    Repeater {
      model: root.rows
      ChoiceRow {
        required property var modelData
        name: modelData.name
        note: modelData.note
        strong: modelData.active
        chosen: modelData.chosen
        usable: modelData.usable
        current: modelData.id === root.selectedId
        onUse: if (!modelData.chosen) root.store.use(modelData.id)
        onPick: root.pickedId = modelData.id
      }
    }
  }

  // ------------------------------------------------- save current as setup
  Item { width: root.width; height: Style.spacing.lg }

  Button {
    visible: !root.naming
    text: "Save current as setup…"
    bordered: true
    enabled: root.editable && root.hasState
    opacity: enabled ? 1 : 0.5
    onClicked: { root.naming = true; nameField.text = ""; nameField.focusField() }
  }

  NameEditor {
    id: nameField
    visible: root.naming
    action: "Save"
    exceptId: ""
    onAccepted: function(name) { root.store.saveCurrent(name) }
    onCancelled: { root.naming = false; root.doneTyping() }
  }

  // ------------------------------------------------------ selected setup
  Column {
    width: root.width
    visible: root.selected !== null
    spacing: 0

    Item {
      width: parent.width
      height: Style.spacing.panelPadding * 2.6

      Text {
        id: selectedName
        anchors { left: parent.left; right: actions.left; rightMargin: Style.spacing.lg; bottom: parent.bottom; bottomMargin: Style.spacing.md }
        text: root.selected ? String(root.selected.name || root.selected.id) : ""
        elide: Text.ElideRight
        color: root.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.6
      }

      // The buttons' labels sit on the name's baseline.
      FontMetrics { id: buttonFont; font.family: Style.font.family; font.pixelSize: Style.font.body }

      Row {
        id: actions
        anchors { right: parent.right; verticalCenter: selectedName.baseline; verticalCenterOffset: buttonFont.height / 2 - buttonFont.ascent }
        spacing: Style.spacing.md
        visible: !root.renaming && !root.confirmingDelete
        Button {
          text: "Use"
          visible: root.selectedRow !== null && root.selectedRow.usable && !root.selectedRow.chosen && !root.selectedRow.active
          enabled: root.idle
          onClicked: root.store.use(root.selectedId)
        }
        Button {
          text: "Rename"
          enabled: root.editable
          onClicked: { root.renaming = true; renameField.text = root.selected.name || ""; renameField.focusField() }
        }
        Button {
          text: "Delete"
          enabled: root.editable
          onClicked: root.confirmingDelete = true
        }
      }
    }

    NameEditor {
      id: renameField
      visible: root.renaming
      action: "Rename"
      exceptId: root.selectedId
      onAccepted: function(name) { root.store.renameSetup(root.selectedId, name); root.renaming = false; root.doneTyping() }
      onCancelled: { root.renaming = false; root.doneTyping() }
    }

    Row {
      visible: root.confirmingDelete
      spacing: Style.spacing.lg
      bottomPadding: Style.spacing.lg
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.selectedRow && root.selectedRow.active
          ? "Delete " + root.selected.name + "? Bento then uses whichever setup matches."
          : "Delete " + (root.selected ? root.selected.name : "") + "?"
        color: root.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      Button {
        text: "Delete"
        bordered: true
        foreground: Color.urgent
        enabled: root.editable
        onClicked: { root.confirmingDelete = false; root.store.removeSetup(root.selectedId) }
      }
      Button {
        text: "Cancel"
        onClicked: root.confirmingDelete = false
      }
    }

    Text {
      width: parent.width
      visible: text !== ""
      wrapMode: Text.WordWrap
      text: !root.selectedRow || root.selectedRow.active ? ""
        : "Not in use, so changes are saved and checked the next time " + root.selectedRow.name + " is used."
      color: root.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      bottomPadding: Style.spacing.lg
    }

    // The arrangement: each display at its logical size, all scaled alike.
    // Filled when connected, an outline when not; click one to select it.
    Text {
      width: parent.width
      visible: root.displays.length === 0
      wrapMode: Text.WordWrap
      text: "No displays saved, so Omarchy arranges them as usual while this setup is in use."
      color: root.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      bottomPadding: Style.spacing.lg
    }

    Item {
      id: drawing
      width: parent.width
      height: root.displays.length ? Style.space(170) : 0
      visible: root.displays.length > 0
      readonly property var fitted: Data.fit(root.displays.map(function(d) { return Data.rect(d, root.omarchyScales) }), width, height - Style.spacing.lg * 2)

      Repeater {
        model: root.displays.length
        Rectangle {
          id: screen
          required property int index
          readonly property var entry: root.displays[index] || ({})
          readonly property var box: drawing.fitted.items[index] || ({ x: 0, y: 0, w: 0, h: 0 })
          readonly property bool connected: Data.isConnected(root.setupState, entry.display)
          readonly property var size: Data.logicalSize(entry, root.omarchyScales)
          readonly property bool picked: index === root.selectedDisplay

          x: box.x + 2
          y: box.y + Style.spacing.lg + 2
          width: Math.max(4, box.w - 4)
          height: Math.max(4, box.h - 4)
          radius: Style.cornerRadius
          color: connected ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08) : "transparent"
          border.width: picked ? 2 : 1
          border.color: picked ? Color.accent : (connected ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.35) : root.faint)

          Column {
            anchors.centerIn: parent
            width: parent.width - Style.spacing.md * 2
            spacing: 2
            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: screen.entry.label || screen.entry.display || ""
              elide: Text.ElideRight
              color: screen.connected ? root.fg : root.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              width: parent.width
              visible: screen.height > Style.space(48)
              horizontalAlignment: Text.AlignHCenter
              text: "looks like " + Data.sizeLabel(screen.size[0], screen.size[1])
              elide: Text.ElideRight
              color: root.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            Text {
              width: parent.width
              visible: screen.entry.primary === true
              horizontalAlignment: Text.AlignHCenter
              text: "★"
              color: root.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.selectedDisplay = screen.index
          }
        }
      }
    }

    Text {
      width: parent.width
      readonly property var pairs: Data.overlaps(root.displays, root.omarchyScales)
      visible: pairs.length > 0
      wrapMode: Text.WordWrap
      text: pairs.join(", ") + (pairs.length === 1 ? " overlap." : " overlap each other.")
      color: Color.urgent
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      bottomPadding: Style.spacing.md
    }

    // One row per display: how big things look, and which one is primary.
    Repeater {
      model: root.displays.length
      Rectangle {
        id: displayRow
        required property int index
        readonly property var entry: root.displays[index] || ({})
        readonly property var device: Data.connectedKeys(root.setupState)[entry.display] || null
        readonly property bool connected: device !== null
        readonly property bool tiled: entry.tiles !== undefined || (device !== null && device.tiled === true)
        readonly property bool scalable: Data.scaleEditable(entry, root.omarchyScales)
        readonly property string scaleValue: typeof entry.scale === "number" ? String(entry.scale) : ""

        width: root.width
        height: Math.max(rowLabel.implicitHeight, controls.height) + Style.spacing.panelPadding
        color: index === root.selectedDisplay && root.displays.length > 1 ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.04) : "transparent"
        radius: Style.cornerRadius

        MouseArea { anchors.fill: parent; onClicked: root.selectedDisplay = displayRow.index }

        Column {
          id: rowLabel
          anchors { left: parent.left; leftMargin: Style.spacing.md; right: controls.left; rightMargin: Style.spacing.lg; verticalCenter: parent.verticalCenter }
          spacing: 3
          Text {
            width: parent.width
            text: displayRow.entry.label || displayRow.entry.display || ""
            elide: Text.ElideRight
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.title
          }
          Text {
            width: parent.width
            readonly property string mode: !displayRow.scalable
              ? "Scale " + (typeof root.laptopScale === "number" ? root.laptopScale + " · " : "") + "Omarchy's scale"
              : ""
            visible: text !== ""
            wrapMode: Text.WordWrap
            text: [mode, displayRow.tiled ? "Single stream, scaled to the whole panel." : "", displayRow.connected ? "" : "Not connected"]
              .filter(function(s) { return s !== "" }).join(" · ")
            color: root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }

        Row {
          id: controls
          anchors { right: parent.right; rightMargin: Style.spacing.md; verticalCenter: parent.verticalCenter }
          spacing: Style.spacing.lg

          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: scaleChoice.visible
            text: "Looks like"
            color: root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
          Dropdown {
            id: scaleChoice
            anchors.verticalCenter: parent.verticalCenter
            visible: displayRow.scalable && options.length > 0
            enabled: root.editable
            options: Data.scaleOptions(displayRow.entry, root.omarchyScales, Data.requestedMode(root.setupState, displayRow.entry.display))
            value: displayRow.scaleValue
            onChanged: function(v) {
              var i = root.fileIndex(displayRow.index)
              if (i >= 0) root.edit(function(s) { return Data.rescale(s, i, v, root.omarchyScales) })
              // Picking an option overwrote `value`; follow the file again,
              // so a rollback shows the scale that's really saved.
              scaleChoice.value = Qt.binding(function() { return displayRow.scaleValue })
            }
            onPopupOpenChanged: if (!popupOpen) root.doneTyping()
          }
          Button {
            anchors.verticalCenter: parent.verticalCenter
            text: "★ Primary"
            bordered: true
            selected: displayRow.entry.primary === true
            enabled: root.editable
            onClicked: {
              var i = root.fileIndex(displayRow.index)
              if (i >= 0) root.edit(function(s) { return Data.setPrimary(s, i) })
            }
          }
        }
      }
    }

    // ------------------------------------------------------ identified by
    SectionHeader { text: "Identified by" }

    Flow {
      width: parent.width
      spacing: Style.spacing.md
      Repeater {
        model: root.choices
        Button {
          required property var modelData
          text: (modelData.on ? "✓ " : "") + modelData.label + (modelData.connected ? "" : " · not connected")
          bordered: true
          selected: modelData.on
          enabled: root.editable
          onClicked: {
            var choice = modelData
            root.edit(function(s) { return Data.toggleWhen(s, choice) })
          }
        }
      }
    }

    Text {
      width: parent.width
      readonly property var whenList: root.selected ? Data.list(root.selected.when) : []
      readonly property string twin: root.selected ? Data.sameWhenAs(root.file, root.selectedId) : ""
      wrapMode: Text.WordWrap
      topPadding: Style.spacing.md
      text: whenList.length === 0
        ? "Nothing ticked, so " + (root.selected ? root.selected.name : "this setup") + " is used when no other setup matches."
        : "Used when all of these are connected." + (twin ? " " + twin + " has the same ones, and whichever is listed first wins." : "")
      color: twin ? Color.urgent : root.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }

    // --------------------------------------------------------- keyboards
    SectionHeader { text: "Keyboards" }

    Text {
      width: parent.width
      visible: !root.macModifiers || root.store === null || root.store.keyboards.length === 0
      wrapMode: Text.WordWrap
      text: !root.macModifiers
        ? "Keymaps are part of the Bento modifier layout, so there's nothing to choose while it's off."
        : "Bento doesn't know any keyboards yet."
      color: root.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }

    Repeater {
      model: root.macModifiers && root.store ? root.store.keyboards : []
      Item {
        id: keyboard
        required property var modelData
        readonly property string keymap: root.selected && Data.isObject(root.selected.keyboards) && Data.validKeymap(root.selected.keyboards[modelData.id])
          ? root.selected.keyboards[modelData.id] : "own"

        width: root.width
        height: Math.max(keymapChoice.height, kbLabel.implicitHeight) + Style.spacing.panelPadding

        Column {
          id: kbLabel
          anchors { left: parent.left; right: keymapChoice.left; rightMargin: Style.spacing.lg; verticalCenter: parent.verticalCenter }
          spacing: 3
          Text {
            width: parent.width
            text: keyboard.modelData.label
            elide: Text.ElideRight
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.title
          }
          Text {
            width: parent.width
            visible: keyboard.modelData.own !== ""
            text: "Its own: " + (Data.keymapNames[keyboard.modelData.own] || "")
            color: root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }

        ButtonGroup {
          id: keymapChoice
          anchors { right: parent.right; verticalCenter: parent.verticalCenter }
          options: [{ value: "own", label: "Its own" }].concat(Data.keymaps.map(function(k) { return { value: k, label: Data.keymapNames[k] } }))
          value: keyboard.keymap
          enabled: root.editable
          onChanged: function(v) {
            var id = keyboard.modelData.id
            if (v !== keyboard.keymap) root.edit(function(s) { return Data.setKeyboardOverride(s, id, v) })
          }
        }
      }
    }
  }

  // ----------------------------------------------------------- components

  // A heading like the other panes' ("TILES", "GESTURES").
  component SectionHeader: Item {
    property alias text: heading.text
    width: root.width
    height: Style.spacing.panelPadding * 2.2
    Text {
      id: heading
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.spacing.md
      color: root.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.capitalization: Font.AllUppercase
      font.letterSpacing: 0.6
    }
  }

  // One line of the list: a radio that uses the setup, its name and note.
  component ChoiceRow: Rectangle {
    id: choiceRow
    property string name: ""
    property string note: ""
    // The setup in use: its note ("In use", "Chosen by hand") reads darker.
    property bool strong: false
    property bool chosen: false
    property bool usable: true
    property bool current: false
    signal use()
    signal pick()

    width: root.width
    height: Style.spacing.controlHeight + Style.spacing.lg
    radius: Style.cornerRadius
    color: current ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.07)
                   : (rowArea.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.035) : "transparent")

    MouseArea {
      id: rowArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: choiceRow.pick()
    }

    Rectangle {
      id: radio
      x: Style.spacing.lg
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(14)
      height: width
      radius: width / 2
      color: "transparent"
      border.width: radioArea.containsMouse && radioArea.enabled ? 2 : 1.5
      border.color: choiceRow.usable ? root.fg : root.faint
      Rectangle {
        anchors.centerIn: parent
        visible: choiceRow.chosen
        width: parent.width * 0.5
        height: width
        radius: width / 2
        color: root.fg
      }
    }

    // A wide target around the radio, so it's easy to hit.
    MouseArea {
      id: radioArea
      x: 0
      width: radio.x * 2 + radio.width
      height: parent.height
      hoverEnabled: true
      enabled: choiceRow.usable && root.idle && !choiceRow.chosen
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: choiceRow.use()
    }

    Text {
      id: rowName
      x: radioArea.width
      width: Style.space(150)
      anchors.verticalCenter: parent.verticalCenter
      text: choiceRow.name
      elide: Text.ElideRight
      color: choiceRow.usable ? root.fg : root.faint
      font.family: Style.font.family
      font.pixelSize: Style.font.title
    }

    Text {
      anchors { left: rowName.right; leftMargin: Style.spacing.lg; right: parent.right; rightMargin: Style.spacing.lg; verticalCenter: parent.verticalCenter }
      text: choiceRow.note
      elide: Text.ElideRight
      color: !choiceRow.usable ? root.faint : (choiceRow.strong ? root.fg : root.dim)
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }

    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.hairline }
  }

  // A name field with its button: Enter or the button accepts, Esc cancels.
  // Says why a name won't do (taken, or one of bento setup's own words).
  component NameEditor: Column {
    id: editor
    property string action: "Save"
    property string exceptId: ""
    property alias text: field.text
    readonly property string problem: field.text.trim() === "" ? "" : Data.nameProblem(root.file, field.text, exceptId)
    signal accepted(string name)
    signal cancelled()

    function focusField() { field.forceActiveFocus() }
    function accept() { if (field.text.trim() !== "" && problem === "" && root.editable) editor.accepted(field.text.trim()) }

    width: root.width
    spacing: Style.spacing.sm
    bottomPadding: Style.spacing.lg

    Row {
      spacing: Style.spacing.lg
      TextField {
        id: field
        width: Style.space(240)
        placeholderText: "Name, like Work or Home"
        maximumLength: 40
        onAccepted: editor.accept()
        Keys.onEscapePressed: function(event) { editor.cancelled(); event.accepted = true }
      }
      Button {
        anchors.verticalCenter: parent.verticalCenter
        text: editor.action
        bordered: true
        enabled: field.text.trim() !== "" && editor.problem === "" && root.editable
        opacity: enabled ? 1 : 0.5
        onClicked: editor.accept()
      }
      Button {
        anchors.verticalCenter: parent.verticalCenter
        text: "Cancel"
        onClicked: editor.cancelled()
      }
    }

    Text {
      visible: editor.problem !== ""
      text: editor.problem
      color: Color.urgent
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
  }
}
