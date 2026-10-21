import QtQuick
import Quickshell
import Quickshell.Io
import "SetupsData.js" as Data

// Bento's setup files for the app and the bar, read and written in one place:
//
//   ~/.config/bento/setups.json       your setups
//   ~/.config/bento/keyboards.json    your keyboards' own keymaps
//   keyboards.json in the checkout    the built-in keyboards
//   ~/.local/state/bento/setup.json   what Hyprland found and chose (Lua writes it)
//
// Every write keeps the old file as .prev. Then bin/bento-setup (setups) or
// bin/bento-apply (keyboards) reloads Hyprland, waits for the check, and
// puts the .prev file back if it fails (the store does that itself when the
// command can't run at all). A setups.json that isn't valid JSON is never
// written over; `fileError` says why editing is off.
//
// Every bar and the app have a store of their own, and the command line can
// change setups too, so the one-at-a-time that counts is bin/bento-setup's
// lock (`setupLock`). setups.json is written under it as well, so it never
// changes under another setup change's reload, check or rollback.
//
//   SetupsStore { id: setups; repo: settings.repo }
//   setups.use("w81c")       // or "auto"
//   setups.editSetup("w81c", function(s) { return Data.setPrimary(s, 0) })
Item {
  id: root

  property string repo: ""
  // While true, the state file and setups.json are also read again every
  // `pollInterval` ms, in case a change notification was missed (a file
  // replaced by rename can lose its watch).
  property bool watching: false
  property int pollInterval: 2000

  readonly property string home: Quickshell.env("HOME")
  readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")) + "/bento"
  readonly property string setupsPath: configDir + "/setups.json"
  readonly property string keyboardsPath: configDir + "/keyboards.json"
  readonly property string statePath: home + "/.local/state/bento/setup.json"
  readonly property string setupLock: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/bento-setup.lock"

  property var file: null           // setups.json; null when missing or broken
  property string fileError: ""
  property var setupState: null     // the state file; null until Hyprland has loaded Bento
  property var repoKeyboards: ({})
  property var userKeyboards: ({})
  property string keyboardsError: ""

  readonly property bool editable: fileError === ""
  readonly property var setups: Data.setupsOf(file)
  readonly property string activeId: setupState && setupState.active ? String(setupState.active) : ""
  readonly property string activeName: Data.nameOf(file, setupState, activeId)
  readonly property var laptopScale: setupState ? setupState.laptop_scale : null
  readonly property var externalScale: setupState ? setupState.external_scale : null
  readonly property var keyboards: Data.keyboardRows(repoKeyboards, userKeyboards, setupState ? setupState.keyboards : [], activeName)

  // What the footer says. `scope` is the pane it belongs to.
  property bool busy: false
  property string busyText: ""
  property string message: ""
  property bool failed: false
  property string scope: ""

  signal saved(string id)

  function tilde(path) { return String(path).replace(root.home, "~") }

  function begin(scope, text) {
    root.scope = scope
    root.busy = true
    root.busyText = text
    root.message = ""
    root.failed = false
  }

  // The outcome is set before `busy` drops, so whoever watches `busy` sees it.
  function finish(text, failed) {
    root.message = text
    root.failed = failed === true
    root.busyText = ""
    root.busy = false
    root.refresh()
  }

  // Read every file again, even if its text looks unchanged, so a write that
  // was rolled back shows what's really on disk.
  function refresh() {
    setupsView.lastText = null
    stateView.lastText = null
    userKeyboardsView.lastText = null
    setupsView.reload()
    stateView.reload()
    repoKeyboardsView.reload()
    userKeyboardsView.reload()
  }

  // ---------------------------------------------------------------- reading

  function takeSetups(text) {
    var p = Data.parse(text)
    if (p.error) { root.file = null; root.fileError = tilde(root.setupsPath) + " isn't valid JSON (" + p.error + "), so the app won't change it." }
    else if (p.value !== null && !(Data.isObject(p.value) && (p.value.setups === undefined || Array.isArray(p.value.setups)))) {
      root.file = null; root.fileError = tilde(root.setupsPath) + " isn't a setups file, so the app won't change it."
    } else { root.file = p.value; root.fileError = "" }
  }

  function takeState(text) {
    var p = Data.parse(text)
    root.setupState = Data.isObject(p.value) ? p.value : null
  }

  function takeKeyboards(text) {
    var p = Data.parse(text)
    if (p.error || (p.value !== null && !Data.isObject(p.value))) {
      root.userKeyboards = ({})
      root.keyboardsError = tilde(root.keyboardsPath) + " can't be read, so only the built-in keymaps apply and the app won't change it."
    } else { root.userKeyboards = p.value || ({}); root.keyboardsError = "" }
  }

  // ---------------------------------------------------------------- setups

  // Hold a setup until a display or dock changes, or go back to automatic.
  function use(id) {
    if (root.busy) return
    begin("setups", id === "auto" ? "Going back to automatic…" : "Switching to " + Data.nameOf(root.file, root.setupState, id) + "…")
    run(["bash", root.repo + "/bin/bento-setup", id], function(code, out, err) {
      if (code === 0) root.finish(Data.lastLine(out) || "Done.", false)
      else root.finish(Data.lastLine(err) || "bento-setup didn't work.", true)
    })
  }

  // Save what's connected, and how it's arranged, as a new setup.
  function saveCurrent(name) {
    if (root.busy || !root.editable) return
    var n = String(name).trim()
    begin("setups", "Saving " + n + "…")
    run(["bash", root.repo + "/bin/bento-setup", "save", n], function(code, out, err) {
      var id = Data.idFromOutput(out)
      if (code === 0) root.finish(Data.lastLine(err) || "Saved " + n + ".", false)
      else root.finish(Data.lastLine(err) || "Not saved.", true)
      if (code === 0 && id) root.saved(id)
    })
  }

  // Change one setup: `change` gets a copy and returns the new setup. `apply`
  // false only saves it, even when it's the setup in use, and changes nothing
  // else; any other edit also drops the setup's phantom displays (a dead
  // tile an older save kept, or a display listed twice), which the pane
  // never shows.
  function editSetup(id, change, note, apply) {
    if (root.busy || !root.editable) return
    var next = Data.clone(root.file) || { version: 1, setups: [] }
    var all = Data.list(next.setups)
    for (var i = 0; i < all.length; i++) {
      if (Data.isObject(all[i]) && all[i].id === id) {
        all[i] = change(all[i])
        if (apply !== false) all[i] = Data.withoutPhantoms(all[i])
        commit(next, id, note, apply)
        return
      }
    }
  }

  // A name changes nothing Hyprland places or checks, and the app and the bar
  // read names from setups.json, so a rename is only saved.
  function renameSetup(id, name) {
    var n = String(name).trim()
    editSetup(id, function(s) { s.name = n; return s }, "Renamed to " + n + ".", false)
  }

  function removeSetup(id) {
    if (root.busy || !root.editable) return
    commit(Data.remove(root.file, id), id, "Deleted " + Data.nameOf(root.file, root.setupState, id) + ".")
  }

  // Write setups.json. The setup in use is applied right away (and rolled
  // back if Hyprland's check fails), unless `apply` is false (a rename); any
  // other one is only saved.
  function commit(next, id, note, apply) {
    var active = apply !== false && root.activeId === id
    var name = Data.nameOf(next, root.setupState, id) || Data.nameOf(root.file, root.setupState, id)
    begin("setups", active ? "Applying…" : "Saving…")
    root.file = next
    write(root.setupsPath, next, function() {
      if (!active) { root.finish(note || "Saved. Checked the next time " + name + " is used.", false); return }
      run(["bash", root.repo + "/bin/bento-setup", "apply"], function(code, out, err) {
        var said = Data.lastLine(err)
        // bento-setup puts back only a file written together with its .prev;
        // anything else it leaves as it is, and says so.
        var kept = String(err).indexOf("setups.json stays as it is") !== -1
        var why = (kept ? "Not applied, and setups.json stays as it is: " : "Not applied, so the previous setups are back: ")
          + (said || "bento-setup apply failed")
        if (code === 127) root.restore(root.setupsPath, function() { root.finish(why, true) })
        else if (code !== 0) root.finish(why, true)
        // While Omarchy holds reloads for an update, the change waits for the
        // reload that ends it: a note, as with keymaps, not a failure.
        else if (said.indexOf("reloads are on hold") !== -1) root.finish(said.charAt(0).toUpperCase() + said.slice(1) + ".", false)
        else if (said) root.finish("Applied. " + said, true)
        else root.finish(note || "Applied.", false)
      })
    })
  }

  // -------------------------------------------------------------- keyboards

  // A keyboard's own keymap, kept in your keyboards.json only where it
  // differs from the built-in file.
  function setKeymap(id, keymap) {
    if (root.busy || root.keyboardsError !== "" || !Data.validKeymap(keymap)) return
    var next = Data.keyboardsWithKeymap(root.repoKeyboards, root.userKeyboards, id, keymap)
    var label = id
    for (var i = 0; i < root.keyboards.length; i++) if (root.keyboards[i].id === id) label = root.keyboards[i].label
    begin("keyboards", "Applying…")
    root.userKeyboards = next
    write(root.keyboardsPath, next, function() {
      run([root.repo + "/bin/bento-apply", "--file", "keyboards.json"], function(code, out, err) {
        // Without an error, bento-apply only writes to stderr when it has to
        // wait (Omarchy holds reloads during an update).
        var said = String(err).trim().split("\n")[0].replace(/^bento: /, "")
        var why = "Not applied, so the previous keymap is back: " + (said || "bento-apply failed")
        if (code === 0) root.finish(said ? said.charAt(0).toUpperCase() + said.slice(1) + "." : label + " uses the " + Data.keymapNames[keymap] + " keymap.", false)
        else if (code === 127) root.restore(root.keyboardsPath, function() { root.finish(why, true) })
        else root.finish(why, true)
      })
    })
  }

  // ------------------------------------------------------------- commands

  // Copy the old file to .prev (or drop a stale .prev when there's no old
  // file, so a rollback deletes instead), then write a temp file and move it
  // into place. setups.json waits (up to 30 s, then exits 75) for any setup
  // change that's under way to finish; a lock file that can't be opened at
  // all doesn't stop the write.
  function write(path, value, then) {
    var script = 'mkdir -p "$1" || exit 1; if [ -n "$4" ] && exec 8>"$4"; then flock -w 30 8 || exit 75; fi; { if [ -f "$2" ]; then cp "$2" "$2.prev"; else rm -f "$2.prev"; fi; } && printf "%s" "$3" > "$2.tmp.$$" && mv -f "$2.tmp.$$" "$2"'
    var lock = path === root.setupsPath ? root.setupLock : ""
    run(["bash", "-c", script, "_", root.configDir, path, Data.encode(value), lock], function(code) {
      if (code === 75) root.finish("Not saved: another setup change is still running; try again.", true)
      else if (code !== 0) root.finish("Couldn't save " + tilde(path), true)
      else then()
    })
  }

  // The command that rolls back never ran (missing, or not executable), so
  // put the old file back here: the .prev copy, or no file if there wasn't
  // one. setups.json goes back under bento-setup's lock too, after waiting
  // up to 30 s for a setup change under way; it goes back either way.
  function restore(path, then) {
    var script = 'if [ -n "$2" ] && exec 8>"$2"; then flock -w 30 8; fi; if [ -f "$1.prev" ]; then cp "$1.prev" "$1"; else rm -f "$1"; fi'
    var lock = path === root.setupsPath ? root.setupLock : ""
    run(["bash", "-c", script, "_", path, lock], function() { then() })
  }

  // Every command runs in its own session with its output in temp files, so
  // it outlives this item. Switching setups can turn off the display whose
  // bar started the switch; that bar (and this Process) goes away, but
  // bento-setup still finishes, rollback included. Exit 126/127 mean it
  // couldn't be run at all.
  readonly property string detached: 'o=$(mktemp) && e=$(mktemp) || exit 127; setsid -w "$@" >"$o" 2>"$e"; c=$?; cat "$o"; cat "$e" >&2; rm -f "$o" "$e"; exit $c'

  // One command at a time in this store (across stores and the command line,
  // bento-setup's lock does that); `then(code, stdout, stderr)` runs once it
  // has exited and both outputs are read.
  property var pending: null

  function run(command, then) {
    var name = command[0] === "bash" && command[1] !== "-c" ? command[1] : command[0]
    root.pending = { then: then, name: name, code: -1, exited: false, out: false, err: false }
    cli.command = ["bash", "-c", root.detached, "_"].concat(command)
    cli.running = true
    startCheck.restart()
  }

  // The next step starts after the Process has finished its own bookkeeping.
  function settle(force) {
    var p = root.pending
    if (!p || !p.exited) return
    if (!force && !(p.out && p.err)) { streamWait.restart(); return }
    streamWait.stop()
    root.pending = null
    var code = p.code, out = cliOut.text, err = cliErr.text
    if (code === 126 || code === 127) { code = 127; err = "Couldn't run " + tilde(p.name) }
    Qt.callLater(function() { p.then(code, out, err) })
  }

  Process {
    id: cli
    stdout: StdioCollector { id: cliOut; onStreamFinished: { if (root.pending) root.pending.out = true; root.settle(false) } }
    stderr: StdioCollector { id: cliErr; onStreamFinished: { if (root.pending) root.pending.err = true; root.settle(false) } }
    onExited: function(code) {
      if (!root.pending) return
      root.pending.code = code
      root.pending.exited = true
      root.settle(false)
    }
  }

  // Don't wait forever for output that's already gone.
  Timer { id: streamWait; interval: 300; onTriggered: root.settle(true) }

  // A Process that never started (no bash) never exits either.
  Timer {
    id: startCheck
    interval: 1000
    onTriggered: {
      if (!root.pending || root.pending.exited || cli.running) return
      var p = root.pending
      root.pending = null
      p.then(127, "", "Couldn't run " + root.tilde(p.name))
    }
  }

  // ---------------------------------------------------------------- files

  FileView {
    id: setupsView
    property var lastText: null
    path: root.setupsPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { var t = text(); if (t !== lastText) { lastText = t; root.takeSetups(t) } }
    onLoadFailed: { lastText = ""; root.takeSetups("") }
  }

  FileView {
    id: stateView
    property var lastText: null
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { var t = text(); if (t !== lastText) { lastText = t; root.takeState(t) } }
    onLoadFailed: { lastText = ""; root.takeState("") }
  }

  FileView {
    id: repoKeyboardsView
    path: root.repo ? root.repo + "/keyboards.json" : ""
    printErrors: false
    onLoaded: { var p = Data.parse(text()); root.repoKeyboards = Data.isObject(p.value) ? p.value : ({}) }
    onLoadFailed: root.repoKeyboards = ({})
  }

  FileView {
    id: userKeyboardsView
    property var lastText: null
    path: root.keyboardsPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { var t = text(); if (t !== lastText) { lastText = t; root.takeKeyboards(t) } }
    onLoadFailed: { lastText = ""; root.takeKeyboards("") }
  }

  Timer {
    interval: root.pollInterval
    repeat: true
    running: root.watching && !root.busy
    onTriggered: { stateView.reload(); setupsView.reload() }
  }
}
