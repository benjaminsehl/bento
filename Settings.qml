import QtQuick
import Quickshell
import Quickshell.Io

// Bento's settings for the shell side: defaults.json in the checkout,
// overridden by ~/.config/bento/settings.json. Same rules as hypr/settings.lua:
// a user value counts only where the default has that key with the same type.
//
//   Settings { id: settings }
//   settings.get("pages", "dotSize")
//   settings.set("pages", "dotSize", 6)   // saves and applies (bento-apply)
Item {
  id: root

  readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/bento"
  readonly property string path: configDir + "/settings.json"
  readonly property string repo: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, ""))

  property var defaults: ({})
  property var user: ({})
  readonly property var values: merge(defaults, user)

  // The result of the last apply: "" while idle or fine, otherwise the error.
  property string applyError: ""
  property bool applying: false

  function merge(d, u) {
    var out = {}
    for (var k in d) {
      var uv = (u && typeof u === "object") ? u[k] : undefined
      if (d[k] !== null && typeof d[k] === "object" && !Array.isArray(d[k])) out[k] = merge(d[k], uv)
      else out[k] = (uv !== undefined && typeof uv === typeof d[k]) ? uv : d[k]
    }
    return out
  }

  function get(section, key) {
    var s = values[section]
    return s ? s[key] : undefined
  }

  function isDefault(section, key) {
    return get(section, key) === (defaults[section] || {})[key]
  }

  // Store only what differs from the defaults, so new defaults reach you.
  function set(section, key, value) {
    var next = JSON.parse(JSON.stringify(user || {}))
    if (!next[section] || typeof next[section] !== "object") next[section] = {}
    if (value === (defaults[section] || {})[key]) delete next[section][key]
    else next[section][key] = value
    if (Object.keys(next[section]).length === 0) delete next[section]
    save(next)
  }

  function reset() { save({}) }

  function save(next) {
    root.user = next
    var text = JSON.stringify(next, null, 2) + "\n"
    writer.command = ["bash", "-c", 'mkdir -p "$1" && [ -f "$2" ] && cp "$2" "$2.prev"; printf "%s" "$3" > "$2"', "_", root.configDir, root.path, text]
    writer.running = true
  }

  function parse(text) {
    try { return JSON.parse(text || "{}") || {} } catch (e) { return null }
  }

  Process {
    id: writer
    onExited: function(code) {
      if (code !== 0) { root.applyError = "Couldn't save " + root.path; return }
      root.applying = true
      apply.running = true
    }
  }

  // bento-apply reloads Hyprland, syncs the bar and Ghostty, and puts the
  // previous settings back if Hyprland rejects the new ones.
  Process {
    id: apply
    command: [root.repo + "/bin/bento-apply"]
    stderr: StdioCollector { id: applyErr }
    onExited: function(code) {
      root.applying = false
      root.applyError = code === 0 ? "" : (applyErr.text.trim() || "bento-apply failed")
      if (code !== 0) userFile.reload()
    }
  }

  FileView {
    path: root.repo + "/defaults.json"
    onLoaded: root.defaults = root.parse(text()) || {}
  }

  FileView {
    id: userFile
    path: root.path
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var parsed = root.parse(text())
      if (parsed !== null) root.user = parsed
    }
    onLoadFailed: root.user = ({})
  }
}
