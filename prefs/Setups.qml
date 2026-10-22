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
// With no setup in use, the pane shows the displays as they are now instead,
// and dragging one arranges them until a display or dock changes.
// All reads and writes go through SetupsStore.
Column {
  id: root

  property var store: null
  property bool macModifiers: true
  // Hyprland's monitors as it lists them (each one's lastIpcObject), from
  // the window: where every display is right now.
  property var monitors: []
  // A text field or dropdown had the keyboard; the window wants it back.
  signal doneTyping()
  // An open dropdown needs this much room under the item: scroll it into view.
  signal reveal(Item item, real below)
  // Every dropdown list closes (see reset).
  signal closeLists()

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

  // The displays as they are now (Data.liveSetup), shown while no setup is
  // in use and none is picked. Boxes just dropped stay where they landed
  // (`arranging`) until Hyprland's monitors catch up.
  property var arranging: null
  readonly property var live: Data.liveSetup(monitors, setupState, arranging)

  // The setup shown below the list: your pick, else the one in use, else
  // the displays as they are now.
  property string pickedId: ""
  readonly property bool liveView: store !== null && store.activeId === "" && Data.byId(all, pickedId) === null && live !== null
  readonly property var selected: liveView ? live
    : Data.byId(all, pickedId) || Data.byId(all, store ? store.activeId : "") || (all.length ? all[0] : null)
  readonly property string selectedId: selected ? selected.id : ""
  readonly property var selectedRow: Data.byId(rows, selectedId)
  // Its displays as listed: one row per display, never a phantom tile (see
  // Data.shownDisplays). Edits go by each one's place in setups.json.
  readonly property var shown: selected ? Data.shownDisplays(selected) : []
  readonly property var displays: shown.map(function(x) { return x.entry })
  readonly property string displayKeys: JSON.stringify(displays.map(function(d) { return d.display }))
  readonly property var choices: selected && !liveView ? Data.whenChoices(selected, setupState) : []
  // The display picked in the drawing or the rows, -1 for none.
  property int selectedDisplay: -1

  function fileIndex(row) { return root.shown[row] ? root.shown[row].index : -1 }

  // The connector to outline on the display itself: the one being dragged,
  // else the one selected, while it's lit (a tiled display's left tile).
  // Nothing with a single display, or none selected.
  readonly property string identifyOutput: {
    var entry = displays.length > 1 ? displays[draggingDisplay >= 0 ? draggingDisplay : selectedDisplay] : null
    var now = entry && live ? live.displays.filter(function(d) { return d.display === entry.display }) : []
    return now.length ? now[0].output : ""
  }

  property bool naming: false
  property bool renaming: false
  property bool confirmingDelete: false

  onSelectedIdChanged: { selectedDisplay = -1; renaming = false; confirmingDelete = false }
  onDisplayKeysChanged: selectedDisplay = -1
  // The live view and a saved setup each have their own name field.
  onLiveViewChanged: if (naming) { naming = false; doneTyping() }

  // The window opens fresh: the setup in use, nothing half-typed or half-deleted,
  // and no dropdown list left open from before it closed.
  function reset() {
    pickedId = ""; selectedDisplay = -1; naming = false; renaming = false; confirmingDelete = false
    cancelDrag()
    closeLists()
  }

  function edit(change, note) { if (root.editable && !root.liveView) root.store.editSetup(root.selectedId, change, note) }

  Connections {
    target: root.store
    function onSaved(id) { root.pickedId = id; root.naming = false; root.doneTyping() }
    // An arrangement that failed goes back at once; one that worked waits
    // for Hyprland's monitors to say so (or a moment, if they already did).
    function onBusyChanged() {
      if (root.store.busy || root.arranging === null) return
      if (root.store.failed) root.settleArranging()
      else arrangingTimeout.restart()
    }
  }

  onMonitorsChanged: if (arranging !== null && idle) settleArranging()

  function settleArranging() {
    arrangingTimeout.stop()
    glide()
    arranging = null
  }

  Timer { id: arrangingTimeout; interval: 1500; onTriggered: root.settleArranging() }

  // ------------------------------------------------------------- dragging
  // Drag a box in the drawing to move that display. It snaps flush against
  // a neighbour (lined up with its start, centre or end when near), the
  // others close up behind it, and the whole starts at 0,0. The drawing is
  // frozen while you drag (`dragFrame`: rects, boxes and fit factor), so a
  // refresh can't move it under the pointer; a drop on a frame that changed
  // since is let go.
  readonly property bool draggable: displays.length > 1 && (liveView ? idle : editable)
  property int draggingDisplay: -1
  property var dragFrame: null
  property real dragDx: 0
  property real dragDy: 0

  function frame() {
    var rects = Data.displayRects(root.displays, root.omarchyScales)
    var fitted = drawing.fitted
    return { key: JSON.stringify([root.liveView, root.selectedId, rects, fitted.factor]), rects: rects, items: fitted.items, factor: fitted.factor }
  }

  function snapPx() { return Style.space(8) }

  // Where the dragged box lands if let go now, in the drawing: a ghost.
  readonly property var ghost: {
    var f = dragFrame, k = draggingDisplay
    if (k < 0 || !f || !f.rects[k] || !f.items[k]) return null
    var r = f.rects[k], b = f.items[k]
    var to = Data.snapOne(f.rects, k, r.x + dragDx / f.factor, r.y + dragDy / f.factor, Data.snapThreshold(r, f.factor, snapPx()))
    return to ? { x: b.x + (to.x - r.x) * f.factor, y: b.y + (to.y - r.y) * f.factor, w: b.w, h: b.h } : null
  }

  function startDrag(index) {
    if (!root.draggable) return false
    root.gliding = false
    root.dragFrame = root.frame()
    root.dragDx = 0; root.dragDy = 0
    root.draggingDisplay = index
    root.selectedDisplay = index
    return true
  }

  function cancelDrag() {
    if (root.draggingDisplay >= 0) root.glide()
    root.draggingDisplay = -1; root.dragFrame = null; root.dragDx = 0; root.dragDy = 0
  }

  // Let go of box `index` moved (dx, dy) on screen. With no setup in use the
  // displays move now (bento-setup arrange); otherwise it's an edit like any
  // other, applied and checked if the setup is in use, else saved. False
  // when the box springs back instead: nothing would change, or it can't
  // be dragged, or the drawing changed under it.
  function drop(index, dx, dy) {
    var f = root.dragFrame || root.frame()
    var r = f.rects[index]
    var places = root.draggable && r && f.factor > 0 && f.key === root.frame().key
      ? Data.arrangeDrop(f.rects, index, r.x + dx / f.factor, r.y + dy / f.factor, Data.snapThreshold(r, f.factor, root.snapPx()))
      : null
    var rows = places ? places.map(function(p, i) { return root.fileIndex(i) }) : []
    // Before anything moves, so the boxes that close up behind it ease too.
    root.glide()
    if (places && root.liveView) {
      root.store.arrange(places)
      if (root.store.busy) root.arranging = places
    } else if (places) {
      root.edit(function(s) {
        rows.forEach(function(i, n) { if (i >= 0 && Data.isObject(s.displays[i])) s.displays[i].at = places[n].at.slice() })
        return s
      })
    }
    root.cancelDrag()
    return places !== null
  }

  // Boxes ease into place after a drop, a spring back or a correction, and
  // jump everywhere else (opening the pane, following the pointer).
  property bool gliding: false
  function glide() { root.gliding = true; glideEnd.restart() }
  Timer { id: glideEnd; interval: 300; onTriggered: root.gliding = false }

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
      text: Data.problemLine(modelData)
      color: Color.urgent
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      bottomPadding: Style.spacing.sm
    }
  }

  // ---------------------------------------------------------- empty state
  // Not over a file that can't be read: that has setups, just none shown.
  Text {
    width: root.width
    visible: root.all.length === 0 && root.store !== null && root.store.fileError === ""
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

    // Clicking it also shows the displays as they are now, when no setup
    // is in use. While the displays are arranged by hand its radio still
    // works, though Automatic is chosen: it ends the arrangement, as Let
    // Omarchy arrange does. Clicking the row only shows them, so going back
    // to look at them never loses the arrangement.
    ChoiceRow {
      name: "Automatic"
      note: root.hasState ? Data.automaticNote(root.menu) : ""
      chosen: root.menu.automatic
      changes: root.menu.automaticChanges
      usable: root.hasState
      current: root.liveView
      onUse: if (root.menu.automaticChanges) root.store.use("auto")
      onPick: { root.pickedId = ""; if (!root.menu.automatic) root.store.use("auto") }
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
  // The live view has its own (below), right by the displays it saves.
  Item { width: root.width; height: Style.spacing.lg; visible: !root.liveView }

  Button {
    visible: !root.naming && !root.liveView
    text: "Save current as setup…"
    bordered: true
    enabled: root.editable && root.hasState
    opacity: enabled ? 1 : 0.5
    onClicked: { root.renaming = false; root.confirmingDelete = false; root.naming = true; nameField.text = ""; nameField.focusField() }
  }

  NameEditor {
    id: nameField
    visible: root.naming && !root.liveView
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
        text: root.liveView ? "Now" : root.selected ? String(root.selected.name || root.selected.id) : ""
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
        visible: !root.renaming && !root.confirmingDelete && !root.liveView
        Button {
          text: "Use"
          visible: root.selectedRow !== null && root.selectedRow.usable && !root.selectedRow.chosen && !root.selectedRow.active
          enabled: root.idle
          onClicked: root.store.use(root.selectedId)
        }
        Button {
          text: "Rename"
          enabled: root.editable
          onClicked: { root.naming = false; root.renaming = true; renameField.text = root.selected.name || ""; renameField.focusField() }
        }
        Button {
          text: "Delete"
          enabled: root.editable
          onClicked: { if (root.naming) { root.naming = false; root.doneTyping() } root.confirmingDelete = true }
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

    Column {
      visible: root.confirmingDelete
      width: parent.width
      bottomPadding: Style.spacing.lg
      Row {
        spacing: Style.spacing.lg
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, root.width - deleteButtons.width - Style.spacing.lg)
          wrapMode: Text.WordWrap
          text: "Delete " + (root.selected ? String(root.selected.name || root.selected.id) : "") + "?"
            + (!root.selectedRow || !root.selectedRow.active ? ""
              : root.all.length === 1 ? " Omarchy then arranges your displays as usual."
              : " Bento then uses whichever other setup matches, or Omarchy's own arrangement.")
          color: root.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
        Row {
          id: deleteButtons
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.lg
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

    // Now: arranged by hand, or as Omarchy and Hyprland placed them.
    Column {
      width: parent.width
      visible: root.liveView
      spacing: 0

      // Only with no list: when there is one, its Automatic row says so.
      Text {
        width: parent.width
        visible: root.menu.arranged && root.all.length === 0
        wrapMode: Text.WordWrap
        text: "Arranged by hand until a display or dock changes."
        color: root.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        bottomPadding: Style.spacing.md
      }

      Flow {
        width: parent.width
        visible: !root.naming
        spacing: Style.spacing.md
        bottomPadding: Style.spacing.lg
        Button {
          text: "Save as setup…"
          bordered: true
          enabled: root.editable && root.hasState
          opacity: enabled ? 1 : 0.5
          onClicked: { root.renaming = false; root.confirmingDelete = false; root.naming = true; liveName.text = ""; liveName.focusField() }
        }
        Button {
          text: "Let Omarchy arrange"
          bordered: true
          visible: root.menu.arranged
          enabled: root.idle
          opacity: enabled ? 1 : 0.5
          onClicked: root.store.use("auto")
        }
      }

      NameEditor {
        id: liveName
        visible: root.naming
        action: "Save"
        sayName: true
        exceptId: ""
        onAccepted: function(name) { root.store.saveCurrent(name) }
        onCancelled: { root.naming = false; root.doneTyping() }
      }
    }

    // The arrangement: each display at its logical size, all scaled alike.
    // Filled when connected, an outline when not; click one to select it,
    // drag it to move it.
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
      // Room either side for the narrowest display, so one dragged past the
      // others to the side stays in sight, even in a narrow window.
      readonly property var fitted: {
        var rects = root.displays.map(function(d) { return Data.rect(d, root.omarchyScales) })
        if (rects.length < 2) return Data.fit(rects, width, height - Style.spacing.lg * 2)
        var room = Math.min.apply(null, rects.map(function(r) { return r.w }))
        var left = Math.min.apply(null, rects.map(function(r) { return r.x }))
        var right = Math.max.apply(null, rects.map(function(r) { return r.x + r.w }))
        var f = Data.fit(rects.concat([{ x: left - room, y: rects[0].y, w: room, h: 1 }, { x: right, y: rects[0].y, w: room, h: 1 }]), width, height - Style.spacing.lg * 2)
        return { factor: f.factor, items: f.items.slice(0, rects.length) }
      }
      // A dragged box passes over what's below the drawing, not under it.
      z: root.draggingDisplay >= 0 ? 1 : 0

      // A click between the boxes selects none.
      MouseArea { anchors.fill: parent; onClicked: root.selectedDisplay = -1 }

      Rectangle {
        readonly property var box: root.ghost || ({ x: 0, y: 0, w: 0, h: 0 })
        visible: root.ghost !== null
        z: 1
        x: box.x + 2
        y: box.y + Style.spacing.lg + 2
        width: Math.max(4, box.w - 4)
        height: Math.max(4, box.h - 4)
        radius: Style.cornerRadius
        color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12)
        border.width: 1
        border.color: Color.accent
      }

      Repeater {
        model: root.displays.length
        Rectangle {
          id: screen
          required property int index
          readonly property var entry: root.displays[index] || ({})
          // While a drag is under way, where the frozen drawing has it.
          readonly property var box: (root.dragFrame && root.dragFrame.items[index]) || drawing.fitted.items[index] || ({ x: 0, y: 0, w: 0, h: 0 })
          readonly property bool connected: Data.isConnected(root.setupState, entry.display)
          readonly property var size: Data.logicalSize(entry, root.omarchyScales)
          readonly property bool dragging: index === root.draggingDisplay
          readonly property bool picked: (index === root.selectedDisplay || dragging) && root.displays.length > 1

          x: box.x + (dragging ? root.dragDx : 0) + 2
          y: box.y + (dragging ? root.dragDy : 0) + Style.spacing.lg + 2
          z: dragging ? 2 : 0
          width: Math.max(4, box.w - 4)
          height: Math.max(4, box.h - 4)
          Behavior on x { enabled: root.gliding; NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
          Behavior on y { enabled: root.gliding; NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
          Behavior on width { enabled: root.gliding; NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
          Behavior on height { enabled: root.gliding; NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
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

          // A click selects it; a drag past the system's drag distance
          // moves it, and the window's scrolling doesn't take the gesture.
          MouseArea {
            id: grab
            anchors.fill: parent
            preventStealing: root.draggable
            cursorShape: !root.draggable ? Qt.PointingHandCursor : screen.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            property point start: Qt.point(0, 0)
            property bool moved: false
            onPressed: function(mouse) { start = mapToItem(drawing, mouse.x, mouse.y); moved = false }
            onPositionChanged: function(mouse) {
              var p = mapToItem(drawing, mouse.x, mouse.y)
              var dx = p.x - start.x, dy = p.y - start.y
              if (!moved && root.draggable && Math.max(Math.abs(dx), Math.abs(dy)) >= Qt.styleHints.startDragDistance)
                moved = root.startDrag(screen.index)
              if (moved && screen.dragging) { root.dragDx = dx; root.dragDy = dy }
            }
            onReleased: {
              if (!moved) root.selectedDisplay = screen.index
              else if (screen.dragging) root.drop(screen.index, root.dragDx, root.dragDy)
              moved = false
            }
            onCanceled: { if (screen.dragging) root.cancelDrag(); moved = false }
          }

          Component.onDestruction: if (dragging) root.cancelDrag()
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

        // Nothing to change in the live view: there's no setup to save it to.
        readonly property bool hasControls: !root.liveView
        // Too narrow for name and controls side by side: controls go below.
        readonly property real controlsWidth: (scaleChoice.visible ? looksLike.implicitWidth + Style.spacing.dropdownWidth + Style.spacing.lg * 2 : 0) + primaryButton.implicitWidth
        readonly property bool stacked: hasControls && width < controlsWidth + Style.space(120)
        width: root.width
        height: (stacked ? rowLabel.implicitHeight + Style.spacing.md + controls.height
                         : Math.max(rowLabel.implicitHeight, hasControls ? controls.height : 0)) + Style.spacing.panelPadding
        color: index === root.selectedDisplay && root.displays.length > 1 ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.04) : "transparent"
        radius: Style.cornerRadius

        MouseArea { anchors.fill: parent; onClicked: root.selectedDisplay = displayRow.index }

        Column {
          id: rowLabel
          anchors {
            left: parent.left; leftMargin: Style.spacing.md
            right: displayRow.stacked || !displayRow.hasControls ? parent.right : controls.left
            rightMargin: displayRow.stacked || !displayRow.hasControls ? Style.spacing.md : Style.spacing.lg
          }
          y: displayRow.stacked ? Style.spacing.panelPadding / 2 : (displayRow.height - height) / 2
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
          visible: displayRow.hasControls
          x: displayRow.stacked ? Style.spacing.md : displayRow.width - width - Style.spacing.md
          y: displayRow.stacked ? rowLabel.y + rowLabel.height + Style.spacing.md : (displayRow.height - height) / 2
          spacing: Style.spacing.lg

          Text {
            id: looksLike
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
            // Shrinks so the row still fits the window at its narrowest.
            width: Math.max(Style.space(120), Math.min(Style.spacing.dropdownWidth,
              displayRow.width - Style.spacing.md * 2 - looksLike.implicitWidth - primaryButton.implicitWidth - Style.spacing.lg * 2))
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
            // Its list opens below it, so make room under it first.
            onPopupOpenChanged: {
              if (popupOpen) root.reveal(scaleChoice, Math.min(options.length, 8) * (popupRowHeight + Style.spacing.labelGap) + Style.spacing.xxs * 2)
              else root.doneTyping()
            }
            Connections { target: root; function onCloseLists() { scaleChoice.close() } }
          }
          Button {
            id: primaryButton
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

    // A saved setup's own: what identifies it, and its keyboards.
    Column {
      width: parent.width
      visible: !root.liveView
      spacing: 0

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
    // The setup in use: its note ("In use", "Chosen by hand") reads darker,
    // and it isn't greyed even when what it saved isn't all connected.
    property bool strong: false
    property bool chosen: false
    // Using it does something: not once it's chosen, unless choosing it
    // again still changes what's on the screens.
    property bool changes: !chosen
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
      enabled: choiceRow.usable && root.idle && choiceRow.changes
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
      color: choiceRow.usable || choiceRow.strong ? root.fg : root.faint
      font.family: Style.font.family
      font.pixelSize: Style.font.title
    }

    Text {
      anchors { left: rowName.right; leftMargin: Style.spacing.lg; right: parent.right; rightMargin: Style.spacing.lg; verticalCenter: parent.verticalCenter }
      text: choiceRow.note
      elide: Text.ElideRight
      // Dim, not faint, when it can't be used: the note is what says why.
      color: choiceRow.strong ? root.fg : root.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }

    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.hairline }
  }

  // A name field with its button: Enter or the button accepts, Esc cancels.
  // Says why a name won't do (taken, or one of bento setup's own words).
  // With `sayName`, the button reads "Save as Work" once a name is typed,
  // when there's room for it.
  component NameEditor: Column {
    id: editor
    property string action: "Save"
    property string exceptId: ""
    property bool sayName: false
    property alias text: field.text
    readonly property string problem: field.text.trim() === "" ? "" : Data.nameProblem(root.file, field.text, exceptId)
    readonly property string named: editor.action + " as " + field.text.trim()
    readonly property bool namedFits: labelFont.advanceWidth(named) + Style.spacing.controlPaddingX * 2 + 4
      <= editor.width - field.width - cancelButton.implicitWidth - Style.spacing.lg * 2
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
        placeholderTextColor: root.dim
        maximumLength: 40
        onAccepted: editor.accept()
        Keys.onEscapePressed: function(event) { editor.cancelled(); event.accepted = true }
      }
      Button {
        anchors.verticalCenter: parent.verticalCenter
        text: editor.sayName && field.text.trim() !== "" && editor.problem === "" && editor.namedFits ? editor.named : editor.action
        bordered: true
        enabled: field.text.trim() !== "" && editor.problem === "" && root.editable
        opacity: enabled ? 1 : 0.5
        onClicked: editor.accept()
      }
      Button {
        id: cancelButton
        anchors.verticalCenter: parent.verticalCenter
        text: "Cancel"
        onClicked: editor.cancelled()
      }
    }

    FontMetrics { id: labelFont; font.family: Style.font.family; font.pixelSize: Style.font.body }

    Text {
      visible: editor.problem !== ""
      text: editor.problem
      color: Color.urgent
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
  }
}
