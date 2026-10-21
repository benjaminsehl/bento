.pragma library

// Plain functions over Bento's setup files, shared by the Setups pane, the
// Keyboards group and the bar's setups menu. Nothing here reads or writes a
// file; SetupsStore.qml does that.
//
//   ~/.config/bento/setups.json        your setups (the app edits it)
//   ~/.config/bento/keyboards.json     your keyboards' own keymaps
//   keyboards.json in the checkout     the built-in keyboards
//   ~/.local/state/bento/setup.json    what Hyprland found and chose
//
// Edits work on copies and keep every field they don't know about.

var keymaps = ["apple", "pc", "omarchy"]
var keymapNames = { apple: "Apple", pc: "PC", omarchy: "Omarchy" }

// The "looks like" scales on offer, relative to the panel's native size.
var scales = [1, 1.25, 1.5, 1.75, 2, 2.5, 3]

function isObject(v) { return v !== null && typeof v === "object" && !Array.isArray(v) }
function clone(v) { return v === undefined ? undefined : JSON.parse(JSON.stringify(v)) }
function list(v) { return Array.isArray(v) ? v : [] }
function isPair(v) { return Array.isArray(v) && v.length === 2 && isFinite(v[0]) && isFinite(v[1]) && v[0] > 0 && v[1] > 0 }

// Bento writes JSON with two-space indents and a trailing newline.
function encode(value) { return JSON.stringify(value, null, 2) + "\n" }

// { value, error }: value is null when the text is missing or not JSON.
function parse(text) {
  if (text === undefined || text === null || String(text).trim() === "") return { value: null, error: "" }
  try { return { value: JSON.parse(text), error: "" } } catch (e) { return { value: null, error: String(e.message || e) } }
}

// ---------------------------------------------------------------- setups

function setupsOf(file) {
  return list(isObject(file) ? file.setups : null).filter(function(s) { return isObject(s) && typeof s.id === "string" })
}

function byId(setups, id) {
  if (!id) return null
  var all = list(setups)
  for (var i = 0; i < all.length; i++) if (all[i] && all[i].id === id) return all[i]
  return null
}

function nameTaken(file, name, exceptId) {
  var want = String(name || "").trim().toLowerCase()
  return setupsOf(file).some(function(s) { return s.id !== exceptId && String(s.name || "").trim().toLowerCase() === want })
}

// bento-setup's own words, which can't name a setup.
var commands = ["auto", "pick", "save", "why", "apply", "status", "help"]

// Why a name won't do, or "" when it's fine.
function nameProblem(file, name, exceptId) {
  var n = String(name || "").trim()
  if (n === "") return "Give it a name."
  if (commands.indexOf(n.toLowerCase()) !== -1) return "“" + n + "” is a command, so it can't name a setup."
  if (n.charAt(0) === "-") return "A name can't start with a dash."
  if (nameTaken(file, n, exceptId)) return "Another setup is called " + n + "."
  return ""
}

function rename(file, id, name) {
  var next = clone(file)
  var s = byId(setupsOf(next), id)
  if (s) s.name = String(name).trim()
  return next
}

function remove(file, id) {
  var next = clone(file)
  next.setups = list(next.setups).filter(function(s) { return !(isObject(s) && s.id === id) })
  return next
}

// The state file's line for one setup: matches, usable, note...
function stateOf(state, id) {
  return byId(isObject(state) ? state.setups : null, id)
}

function nameOf(file, state, id) {
  var s = byId(setupsOf(file), id) || stateOf(state, id)
  return s ? String(s.name || s.id) : ""
}

// The setups menu in the bar: Automatic, then each setup Hyprland knows,
// named as setups.json names them now (a rename shows before the next load).
function menuModel(state, file, fileReadable) {
  var hand = isObject(state) && isObject(state.hand) ? state.hand.id : null
  var active = isObject(state) ? state.active : null
  var items = list(isObject(state) ? state.setups : null).filter(function(s) {
    return isObject(s) && s.id && (!fileReadable || byId(setupsOf(file), s.id) !== null)
  }).map(function(s) {
    return {
      id: s.id,
      name: nameOf(file, state, s.id),
      usable: s.usable !== false,
      failed: s.failed === true,
      note: String(s.note || ""),
      chosen: hand === s.id,
      active: active === s.id
    }
  })
  var stopped = isObject(state) && typeof state.stopped === "string" && state.stopped !== ""
  return { automatic: !hand, now: active ? nameOf(file, state, active) : "", stopped: stopped, items: items }
}

// What the Automatic choice says, in the menu and the pane: what it uses
// now, or why nothing. Nothing while a setup is held by hand, since then
// Automatic isn't choosing. A stop comes first: the setup still in use is
// the one that just failed its check.
function automaticNote(menu) {
  if (!menu.automatic) return ""
  if (menu.stopped) return "stopped after a failed check"
  return menu.now ? "now: " + menu.now : "nothing matches now"
}

// A setup's note in the menu: why it failed or can't be used, or that it's
// in use. The menu has no room for the rest ("Not matched: …").
function menuNote(item) {
  if (item.failed) return item.note
  if (item.active) return "in use"
  return item.usable ? "" : item.note
}

// The Setups pane's list: every setup in setups.json, in file order, with
// the state's note. One Hyprland hasn't loaded yet can be edited, not used.
function paneModel(state, file) {
  var hand = isObject(state) && isObject(state.hand) ? state.hand.id : null
  var active = isObject(state) ? state.active : null
  return setupsOf(file).map(function(s) {
    var st = stateOf(state, s.id)
    return {
      id: s.id,
      name: String(s.name || s.id),
      usable: st !== null && st.usable !== false,
      note: st ? String(st.note || "") : "Not checked yet",
      chosen: hand === s.id,
      active: active === s.id
    }
  })
}

// ------------------------------------------------------------- displays

// A size that says there's no picture: a width or height of 0 (or less), or
// 640x480, the mode a connector falls back to when no working display
// answers on it. The right tile of an LG UltraFine on one stream flips
// between the two with nothing plugged in or out. Neither is ever read as
// "not sized yet".
function deadSize(v) {
  if (!Array.isArray(v) || v.length !== 2) return false
  var w = Number(v[0]), h = Number(v[1])
  return !(isFinite(w) && isFinite(h) && w > 0 && h > 0) || (w === 640 && h === 480)
}

// A phantom: an external display whose panel is a dead size. An older save
// could have kept one; a connector with nothing working on it can show one.
function phantom(entry) {
  return isObject(entry) && entry.internal !== true && entry.display !== "internal" && deadSize(entry.native)
}

// The connected displays as Bento shows them: the state's list, one entry
// per display. Never listed on their own: a tile of a tiled display (its
// connector is the tiled display's), a connector the tile guard turns off
// (`requested` has it disabled), a phantom, or a connector with no display
// identity at all (no usable EDID). A display listed twice is one display;
// its tiled entry wins.
function connectedDisplays(state) {
  var devices = isObject(state) && isObject(state.devices) ? state.devices : {}
  var all = list(devices.displays).filter(isObject)
  var off = {}, tileOf = {}
  list(isObject(state) && isObject(state.requested) ? state.requested.monitors : null).forEach(function(r) {
    if (isObject(r) && r.disabled === true && typeof r.output === "string") off[r.output] = true
  })
  all.forEach(function(d) { if (d.tiled === true) list(d.connectors).forEach(function(c) { tileOf[c] = d }) })
  function allOf(d, test) { var cs = list(d.connectors); return cs.length > 0 && cs.every(test) }
  var out = [], at = {}
  all.forEach(function(d) {
    if (typeof d.display !== "string" || d.display === "") return
    var internal = d.internal === true || d.display === "internal"
    if (!internal && d.tiled !== true) {
      if (phantom(d)) return
      if (allOf(d, function(c) { return off[c] === true })) return
      if (allOf(d, function(c) { return tileOf[c] !== undefined })) return
    }
    if (at[d.display] === undefined) { at[d.display] = out.length; out.push(d) }
    else if (d.tiled === true && out[at[d.display]].tiled !== true) out[at[d.display]] = d
  })
  return out
}

function connectedKeys(state) {
  var keys = {}
  connectedDisplays(state).forEach(function(d) { keys[d.display] = d })
  return keys
}

// A saved setup's displays as the pane lists them, each with its place in
// the file (edits go by that): one row per display, as Bento skips a
// display listed again, and no phantom. An entry that isn't an object can't
// be shown.
function shownDisplays(setup) {
  var out = [], seen = {}
  list(setup && setup.displays).forEach(function(d, i) {
    if (!isObject(d) || phantom(d)) return
    if (typeof d.display === "string" && d.display !== "") {
      if (seen[d.display]) return
      seen[d.display] = true
    }
    out.push({ entry: d, index: i })
  })
  return out
}

// The setup without its phantoms and repeated displays, so an edit never
// saves one back. Anything else stays as it is.
function withoutPhantoms(setup) {
  if (!isObject(setup) || !Array.isArray(setup.displays)) return setup
  var keep = {}
  shownDisplays(setup).forEach(function(x) { keep[x.index] = true })
  if (setup.displays.every(function(d, i) { return !isObject(d) || keep[i] === true })) return setup
  var next = clone(setup)
  next.displays = next.displays.filter(function(d, i) { return !isObject(d) || keep[i] === true })
  return next
}

function isConnected(state, key) {
  return connectedKeys(state)[key] !== undefined
}

function numericScale(v) { return typeof v === "number" && isFinite(v) && v > 0 ? v : null }

// Omarchy's scale for one display, from the state: `omarchy` is
// { laptop, external } (laptop_scale for the laptop panel, external_scale,
// the catch-all, for the rest). A bare value stands for both, and a missing
// `external` falls back to the laptop's, as for a state from before
// external_scale. A number, "auto", or null.
function omarchyValue(entry, omarchy) {
  if (!isObject(omarchy)) return omarchy
  if (entry && entry.display === "internal") return omarchy.laptop
  return omarchy.external !== undefined && omarchy.external !== null ? omarchy.external : omarchy.laptop
}

// Scale Bento uses when a display follows Omarchy's: Omarchy's scale from
// monitors.lua when it is a number, otherwise the rule setups.lua uses for
// tiles (native width / 2560, in quarters, at least 1). `value` is already
// this display's (see omarchyValue).
function omarchyScale(native, value) {
  var s = numericScale(value)
  if (s) return s
  return isPair(native) ? Math.max(1, Math.round(native[0] / 2560 * 4) / 4) : 1
}

function effectiveScale(entry, omarchy) {
  return numericScale(entry && entry.scale) || omarchyScale(entry && entry.native, omarchyValue(entry, omarchy))
}

function rotated(entry) { return entry && typeof entry.transform === "number" && entry.transform % 2 === 1 }

// Logical size: what setups.json saved, else the panel at its scale.
function logicalSize(entry, omarchy) {
  if (entry && isPair(entry.size)) return [Math.round(entry.size[0]), Math.round(entry.size[1])]
  var native = entry && isPair(entry.native) ? entry.native : [1920, 1080]
  var s = effectiveScale(entry, omarchy)
  var w = Math.round(native[0] / s), h = Math.round(native[1] / s)
  return rotated(entry) ? [h, w] : [w, h]
}

function whole(x) { return Math.abs(x - Math.round(x)) < 1e-6 }

// May the laptop carry its own scale? Only when Omarchy's is "auto".
function scaleEditable(entry, omarchy) {
  return !(entry && entry.display === "internal") || omarchyValue(entry, omarchy) === "auto"
}

function sizeLabel(w, h) { return Math.round(w) + " × " + Math.round(h) }

// "Looks like" choices for one display: Omarchy's scale first (no `scale`
// field), then every scale that gives whole logical pixels on the panel.
// With the mode Hyprland drives (a tile's single stream), also keep only
// scales Hyprland accepts for it: n/120, whole pixels at that mode.
// When Omarchy's scale is "auto", Hyprland picks it for an ordinary display,
// so there's no size to show; tiles get Bento's rule even then.
function scaleOptions(entry, omarchy, mode) {
  var native = entry && isPair(entry.native) ? entry.native : null
  if (!native) return []
  var tile = entry.tiles !== undefined || isPair(mode)
  var value = omarchyValue(entry, omarchy)
  var o = numericScale(value) || (tile ? omarchyScale(native, value) : null)
  var out = [{ value: "", label: o ? sizeLabel(native[0] / o, native[1] / o) + " · Omarchy's scale" : "Omarchy's scale (automatic)" }]
  var current = numericScale(entry.scale)
  var offered = scales.slice()
  if (current && offered.indexOf(current) === -1) offered.push(current)
  offered.sort(function(a, b) { return a - b })
  for (var i = 0; i < offered.length; i++) {
    var s = offered[i]
    var w = native[0] / s, h = native[1] / s
    var fits = whole(w) && whole(h)
    if (fits && isPair(mode)) {
      var hs = s * mode[0] / native[0]
      fits = whole(hs * 120) && whole(mode[0] / hs) && whole(mode[1] / hs)
    }
    if (fits || s === current) out.push({ value: String(s), label: sizeLabel(w, h) })
  }
  return out
}

// The mode Hyprland was asked for on a display's connector, from the state's
// `requested` rules ("3840x2160@59.999" -> [3840, 2160]), when it has one.
// A dead size ("0x0@60") is no mode at all.
function requestedMode(state, key) {
  var d = connectedKeys(state)[key]
  if (!d) return null
  var connector = d.left || list(d.connectors)[0]
  var rules = list(isObject(state.requested) ? state.requested.monitors : null)
  for (var i = 0; i < rules.length; i++) {
    var r = rules[i]
    if (!isObject(r) || r.output !== connector || typeof r.mode !== "string") continue
    var m = /^(\d+)x(\d+)/.exec(r.mode)
    var mode = m ? [Number(m[1]), Number(m[2])] : null
    if (mode && isPair(mode) && !deadSize(mode)) return mode
  }
  return null
}

function rect(entry, omarchy) {
  var size = logicalSize(entry, omarchy)
  var at = entry && Array.isArray(entry.at) && entry.at.length === 2 ? entry.at : [0, 0]
  return { x: Number(at[0]) || 0, y: Number(at[1]) || 0, w: size[0], h: size[1] }
}

// Fit every display into a box for the drawing: one factor for all, centred.
function fit(rects, width, height) {
  if (!rects.length || width <= 0 || height <= 0) return { factor: 0, items: [] }
  var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
  for (var i = 0; i < rects.length; i++) {
    var r = rects[i]
    minX = Math.min(minX, r.x); minY = Math.min(minY, r.y)
    maxX = Math.max(maxX, r.x + r.w); maxY = Math.max(maxY, r.y + r.h)
  }
  var factor = Math.min(width / Math.max(1, maxX - minX), height / Math.max(1, maxY - minY))
  var ox = (width - (maxX - minX) * factor) / 2, oy = (height - (maxY - minY) * factor) / 2
  return {
    factor: factor,
    items: rects.map(function(r) {
      return { x: ox + (r.x - minX) * factor, y: oy + (r.y - minY) * factor, w: r.w * factor, h: r.h * factor }
    })
  }
}

// Pairs of displays that overlap, as "A and B".
function overlaps(entries, omarchy) {
  var out = []
  for (var i = 0; i < entries.length; i++)
    for (var j = i + 1; j < entries.length; j++) {
      var a = rect(entries[i], omarchy), b = rect(entries[j], omarchy)
      if (a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h)
        out.push((entries[i].label || "Display " + (i + 1)) + " and " + (entries[j].label || "Display " + (j + 1)))
    }
  return out
}

// Change one display's scale ("" = Omarchy's). Its saved size follows, and
// displays entirely to its right (sharing some height) or below it (sharing
// some width) move by the change, so the arrangement keeps its shape.
function rescale(setup, index, value, omarchy) {
  var next = clone(setup)
  var displays = list(next.displays)
  var d = displays[index]
  if (!isObject(d)) return next
  var before = rect(d, omarchy)
  var s = value === "" || value === null || value === undefined ? null : Number(value)
  if (s && isFinite(s) && s > 0) d.scale = s
  else delete d.scale
  delete d.size
  var size = logicalSize(d, omarchy)
  d.size = size
  var dw = size[0] - before.w, dh = size[1] - before.h
  for (var i = 0; i < displays.length; i++) {
    if (i === index || !isObject(displays[i])) continue
    var r = rect(displays[i], omarchy)
    var at = [r.x, r.y]
    if (r.x >= before.x + before.w && r.y < before.y + before.h && before.y < r.y + r.h) at[0] += dw
    if (r.y >= before.y + before.h && r.x < before.x + before.w && before.x < r.x + r.w) at[1] += dh
    if (at[0] !== r.x || at[1] !== r.y) displays[i].at = at
  }
  return next
}

// At most one primary; choosing the primary again clears it, and Bento
// then takes the first connected display.
function setPrimary(setup, index) {
  var next = clone(setup)
  var displays = list(next.displays)
  if (!isObject(displays[index])) return next
  var on = displays[index].primary !== true
  for (var i = 0; i < displays.length; i++) {
    if (!isObject(displays[i])) continue
    if (i === index && on) displays[i].primary = true
    else delete displays[i].primary
  }
  return next
}

// ------------------------------------------------------------ identified by

var kinds = ["display", "thunderbolt", "usb"]

function whenKey(entry) {
  if (!isObject(entry)) return ""
  for (var i = 0; i < kinds.length; i++) if (typeof entry[kinds[i]] === "string" && entry[kinds[i]]) return kinds[i] + ":" + entry[kinds[i]]
  return ""
}

function connectedWhenKeys(state) {
  var keys = {}
  var devices = isObject(state) && isObject(state.devices) ? state.devices : {}
  connectedDisplays(state).forEach(function(d) { if (!d.internal) keys["display:" + d.display] = true })
  list(devices.thunderbolt).forEach(function(t) { if (isObject(t) && t.thunderbolt) keys["thunderbolt:" + t.thunderbolt] = true })
  list(devices.usb).forEach(function(u) { if (typeof u === "string") keys["usb:" + u] = true })
  return keys
}

// The chips under "Identified by": what the setup lists now, its external
// displays, and the displays and Thunderbolt devices connected right now. A
// tiled display is one chip; a phantom or a tile on its own is none.
function whenChoices(setup, state) {
  var out = [], seen = {}
  var on = {}
  list(setup && setup.when).forEach(function(w) { var k = whenKey(w); if (k) on[k] = true })
  var connected = connectedWhenKeys(state)
  function add(entry) {
    var k = whenKey(entry)
    if (!k || seen[k]) return
    seen[k] = true
    var id = k.slice(k.indexOf(":") + 1)
    var clean = {}
    clean[k.slice(0, k.indexOf(":"))] = id
    clean.label = String(entry.label || id)
    out.push({ key: k, label: clean.label, on: on[k] === true, connected: connected[k] === true, entry: clean })
  }
  var devices = isObject(state) && isObject(state.devices) ? state.devices : {}
  list(setup && setup.when).forEach(add)
  shownDisplays(setup).forEach(function(x) { var d = x.entry; if (d.display && d.display !== "internal") add({ display: d.display, label: d.label }) })
  connectedDisplays(state).forEach(function(d) { if (!d.internal) add({ display: d.display, label: d.label }) })
  list(devices.thunderbolt).forEach(function(t) { if (isObject(t)) add({ thunderbolt: t.thunderbolt, label: t.label }) })
  return out
}

function toggleWhen(setup, choice) {
  var next = clone(setup)
  var when = list(next.when).filter(function(w) { return whenKey(w) !== choice.key })
  if (!choice.on) when.push(clone(choice.entry))
  next.when = when
  return next
}

// Another setup identified by exactly the same devices, if any (the one
// listed first would always win).
function sameWhenAs(file, id) {
  function keys(s) { return list(s.when).map(whenKey).filter(function(k) { return k }).sort().join(",") }
  var mine = byId(setupsOf(file), id)
  if (!mine || keys(mine) === "") return ""
  var all = setupsOf(file)
  for (var i = 0; i < all.length; i++) if (all[i].id !== id && keys(all[i]) === keys(mine)) return String(all[i].name || all[i].id)
  return ""
}

// ---------------------------------------------------------------- keyboards

function validKeymap(k) { return keymaps.indexOf(k) !== -1 }

// One row per known keyboard: the built-in ones, yours, and any the state
// lists. `own` comes from the files, so a change shows before Hyprland reloads;
// `connected` and the active setup's `override` come from the state.
function keyboardRows(repo, user, stateKeyboards, activeName) {
  repo = isObject(repo) ? repo : {}
  user = isObject(user) ? user : {}
  var fromState = {}, ids = []
  list(stateKeyboards).forEach(function(k) {
    if (!isObject(k) || !k.id || fromState[k.id]) return
    fromState[k.id] = k
    ids.push(k.id)
  })
  Object.keys(repo).concat(Object.keys(user)).forEach(function(id) { if (ids.indexOf(id) === -1 && (isObject(repo[id]) || isObject(user[id]))) ids.push(id) })
  return ids.map(function(id) {
    var r = isObject(repo[id]) ? repo[id] : {}, u = isObject(user[id]) ? user[id] : {}, s = fromState[id]
    var own = validKeymap(u.keymap) ? u.keymap : validKeymap(r.keymap) ? r.keymap : (s && validKeymap(s.own) ? s.own : "")
    var override = s && validKeymap(s.override) ? s.override : ""
    return {
      id: id,
      label: String(u.label || r.label || (s && s.label) || id),
      own: own,
      connected: s ? s.connected === true : null,
      override: override,
      note: override && activeName ? keymapNames[override] + " in " + activeName : ""
    }
  })
}

// Your keyboards.json after choosing `keymap` for one keyboard. Only what
// differs from the built-in file is kept, so new built-ins reach you.
function keyboardsWithKeymap(repo, user, id, keymap) {
  var next = isObject(user) ? clone(user) : {}
  var mine = isObject(next[id]) ? next[id] : {}
  var builtIn = isObject(repo) && isObject(repo[id]) ? repo[id] : null
  if (builtIn && builtIn.keymap === keymap) delete mine.keymap
  else mine.keymap = keymap
  if (Object.keys(mine).length === 0) delete next[id]
  else next[id] = mine
  return next
}

// A setup's keymap for one keyboard: "own" removes the override.
function setKeyboardOverride(setup, id, keymap) {
  var next = clone(setup)
  var kb = isObject(next.keyboards) ? next.keyboards : {}
  if (validKeymap(keymap)) kb[id] = keymap
  else delete kb[id]
  if (Object.keys(kb).length === 0) delete next.keyboards
  else next.keyboards = kb
  return next
}

// ------------------------------------------------------------------- misc

// `bento-setup save` prints the new setup's id.
function idFromOutput(text) {
  var lines = String(text || "").split("\n").map(function(l) { return l.trim() })
  for (var i = lines.length - 1; i >= 0; i--) if (/^[a-z0-9]{4,12}$/.test(lines[i])) return lines[i]
  return ""
}

// The last non-empty line of a command's output, for the footer.
function lastLine(text) {
  var lines = String(text || "").split("\n").map(function(l) { return l.trim() }).filter(function(l) { return l !== "" })
  return lines.length ? lines[lines.length - 1] : ""
}
