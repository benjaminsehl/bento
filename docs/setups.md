# Setups

**Status:** stage 0 (Bento as a clean Omarchy plugin), stage 1 (displays
and keyboards) and stage 1b (dragging displays into place) are built. Audio
(stage 2) and the camera (stage 3) come later; their sections below are still
the plan. See [Stages](#stages).

A setup is a named desk: home, work, the other room at work. Bento picks one
from what is plugged in, or you pick one by hand. A setup arranges the
displays and gives each keyboard its keymap. From stage 2 it also chooses the
default speakers and microphone, and from stage 3 it tells you which camera
each call app will open. With no setup in use, you can drag the displays into
place in the Setups pane; that holds until a display or dock changes, unless
you save it as a setup.

This page describes what is built. The design was revised after a review that
tried to break it; [What the review changed](#what-the-review-changed) lists
what moved.

## What we found

These facts shaped the design. The research ran read-only on this machine and
against Hyprland 0.56.2, aquamarine 0.15, WirePlumber 0.5.17 and Chromium
source. A second pass checked each claim against the source, and building
stage 1 checked the display and keyboard facts again. Those are verified;
where the build proved something different, the bullet says so. The audio and
camera facts wait for their stages.

### Displays

- **Bento's rules already win.** Bento loads as an Omarchy toggle, after
  `~/.config/hypr/monitors.lua`, and in Hyprland the newest matching monitor
  rule wins. Omarchy's lid and mirror toggles load after Bento, so they still
  win for the laptop panel. That is the right order.
- **Connector names move.** DP-1 was the Studio Display at home and an
  UltraFine tile at work. A display's EDID (vendor, product, serial) identifies
  it wherever it is plugged in. Both UltraFine tiles carry the same EDID key,
  `GSM:5B74:309NTWGC3705`, plus a tile block (2×1) that says which half each
  one is. The laptop panel is `LGD:07C6:0`; setups call it `internal`.
- **Both tiles have one description,** "LG Electronics LG UltraFine
  309NTWGC3705". A `desc:` rule reaches both, and a connector rule after it
  wins for its own connector. So the guard always sends the pair, `desc:`
  first.
- **Runtime rules can't be taken back.** `hl.monitor` works at runtime, but
  there is no way to remove a rule. Only a reload clears them, and a reload
  also throws away Bento's timers and Lua state. Omarchy reloads by itself
  too: lid, package updates, and every edit to `monitors.lua` (auto-reload is
  on). So the layout has to come out of every config load, and a reload is
  the only clean way to change it. A reload freezes the compositor for about
  25–50 ms.
- **The first load after login sees no monitors.** `hl.get_monitors()` is
  empty then, and `config.reloaded` fires during that load too. So the scan
  reads sysfs, and the mode list falls back to the kernel's.
- **Hyprland applies monitors one at a time,** in the order they were
  created, with a separate commit for each. A batch of rules isn't atomic.
- **A new display's first modeset uses whatever rule exists when it
  connects.** `monitor.added` fires after that, so no reaction to the event
  can affect the first modeset.
- **An output that connects disabled can come back at 0×0.** It keeps
  Hyprland's default rule, and a later rule with `preferred` and `auto` can
  turn it on with no mode, stuck there. So Bento lights a tile only with an
  exact `WxH@R` mode and a numeric scale, and sends the guard at every load.
- **`hyprctl configerrors` never reports layout failures.** A bad scale,
  mode or overlap only shows as a notification, and any `hyprctl eval` clears
  the list. Checking has to read the result back from Hyprland.
- **A scale can change without a sign.** When a scale rounded to 1/120 gives
  whole logical pixels, Hyprland uses that one silently. Bento rounds every
  scale the same way before asking, so the check compares like with like.
- **`cursor.default_monitor` is read once per Hyprland process,** so the
  primary display decides where the cursor starts at login only.
- **The UltraFine can't run true 5K here.** Its Thunderbolt link to the TS4
  is 2 × 10 Gb/s, and two native tiles need about 23 Gb/s. Even on a 40 Gb/s
  link, this laptop's display engine (Panther Lake) runs tiled displays
  without port sync on kernels 7.1 and 7.2. Omarchy issue #10691, filed from
  the same model, reports the link and the laptop panel dropping when both
  tiles are forced. What works is one stream on the left tile, scaled by the
  monitor to the whole panel: 3840×2160, 3200×1800 or 2560×1440.
- **Hyprland's mode list can be stale.** After the "not enough bandwidth"
  failure at plug time, Hyprland froze DP-1's list at 3200×1800, 2560×1440 and
  640×480. The kernel now also lists 3840×2160, but Hyprland only re-reads on
  a replug or a new login. A mode that isn't in Hyprland's list becomes a
  custom mode, which may show black.
- **A tiled display can wake up in pieces.** At the work desk, after a
  replug, Hyprland listed both UltraFine tiles at 0×0. Then it settled with
  DP-1 at 3840×2160 (modes 3840×2160, 2560×2880, 3200×1800, 2560×1440 and
  640×480) and DP-2 at 640×480 only, and minutes later DP-2 flipped to 0×0
  with no replug and no event, still listed. Its EDID and description can be
  empty. A panel powered off at boot can also give the left tile a partial
  EDID (128 bytes, no tile block) or none. Anything worked out from a width
  or a mode has to survive a 0.
- **A disable can look ignored.** `hl.monitor({ output = "DP-2", disabled =
  true })` returned ok while the tiles were dead, and DP-2 still showed in
  `hyprctl monitors`. Whether `hyprctl monitors all` lists it as disabled is
  still to be seen live, so the hand tests check both lists.
- **The Studio Display has a tile block too,** but its first connector
  offers the full 5120×2880, so Hyprland treats it as one display and hides
  the second connector. A display only counts as tiled when no connector
  offers the full panel.
- **The temporary `monitors.lua` fights the guard.** It lays the UltraFine
  out itself, with `mode = "preferred"` on each tile, and reloads Hyprland on
  every monitor event. On the day the desk broke, both tiles at 0×0 broke its
  scale arithmetic (a remainder by zero), the whole monitors config failed,
  and the desk froze.
  Bento's tile guard now keeps the right tile off and DP-1 on one stream
  whatever that file says, and the file goes back to Omarchy's template once
  Work is saved (see
  [Moving off the temporary monitors.lua](#moving-off-the-temporary-monitorslua)).
- **There is no primary display in Hyprland.** Omarchy puts its bar and
  notifications on every screen. "Primary" can only mean where the cursor
  and focus start, and where the first page lives.
- **Omarchy polices the laptop's scale.** While docked, its clamshell
  watcher checks every 2 s. If the laptop panel's scale differs from the
  number in `monitors.lua`, it puts that scale back with `position = "auto"`.
  Omarchy's Scale shortcut changes the focused display at runtime, also with
  `position = "auto"`, then rewrites the number in `monitors.lua`.

### Keyboards

- `hl.device` rules are keyed by Hyprland's device name and also apply to
  keyboards plugged in later. So Bento can emit every known keyboard's rule at
  load, and no device events are needed. That's lucky, because Hyprland 0.56
  has neither a device list nor device events in Lua.
- One keyboard has several input devices (the K3 Pro has
  `keychron-keychron-k3-pro` and `-keyboard`), and Hyprland adds `-1`, `-2`
  when names collide. `/proc/bus/input/devices` maps names to USB
  vendor:product. The K3 Pro is `3434:0233`.
- `hl.device` has no delete either. Going back to Omarchy's layout means
  emitting `kb_file = ""` explicitly. Hyprland's source confirms that an
  empty `kb_file` falls back to the global layout; trying it at runtime is one
  of the [hand tests](#testing-by-hand-at-the-desk).

### Audio

- `wpctl` here only takes numeric ids. `wpctl set-default ID` stores
  `default.configured.audio.sink = {"name": "<node.name>"}`. Bento can write
  that same key by name with `pw-metadata`, even before the device connects.
  WirePlumber switches to it about 10 ms after it appears (tested in an
  isolated PipeWire session).
- **Names aren't perfectly stable.** The Shure MV7+ is currently
  `…MV7__11-2700b31…-01.2.analog-stereo`. The `.2` comes from a WirePlumber
  naming race when the mic re-enumerates during resume. Store the device's
  identity (USB ids, serial, profile) and resolve the live name when applying.
- **WirePlumber restarts about 4 s after every resume.** The
  `intel-ipu7-camera` package does it. A default written in the second before
  a restart is lost.
- **The same key holds your own choice.** Omarchy's audio panel and `wpctl`
  write it too, so Bento has to tell its own writes from yours.
- Today no default is configured at all. At work the input is the Sony
  camera's microphone, which wins on priority, not the Shure. Undocked,
  WirePlumber would pick the raw laptop speaker and bypass Omarchy's speaker
  tuning.
- UltraFine audio has no serial, so every UltraFine has the same audio name.
  Audio is fine to apply, but useless for telling desks apart.

### Camera

- **None of the call apps you use asks the system for a camera.** Chrome, the
  Slack app and Meet open `/dev/videoN` directly, not through PipeWire. This
  was checked live during a Meet call: Chrome's capture process held
  `/dev/video32` and didn't load PipeWire at all.
  - Chrome sorts `/dev/videoN`, then applies its own per-profile ranking by
    camera name. Today that ranking is `["Studio Display Camera", "Hardware
    ISP Camera"]`, so at work Chrome sites default to the laptop camera.
    The ranking only applies to sites with no saved camera.
  - Meet keeps one saved camera for everywhere, stored as a hashed
    `/dev/video32`. That was the Opal C1 when you picked it and is the Sony
    today, so Meet changes cameras when plug order changes.
  - The Slack app opens the first camera in `/dev` order, which is the Sony at
    work.
- Your WirePlumber rule `opal-c1-default-camera.conf` only affects PipeWire
  apps, and none of your call apps is one. Meet used the Opal only because it
  happened to be `/dev/video32`.
- Making Meet or the Slack app follow the desk would need root: udev rules to
  reorder `/dev/videoN`, or a v4l2loopback relay.
- **What is realistic without root:**
  1. Tell you, per setup, which camera each app will open, without opening a
     camera. Chrome sites follow Chrome's ranking, the Slack app takes the
     first device, and Meet uses whatever you last picked in Meet.
  2. When Chrome's pick is wrong, open Chrome's camera settings so you can fix
     it once for that desk.
  3. Give the setup's camera to anything Bento itself starts. Nothing does yet.

## The design

### The idea

**The layout comes out of every config load.** At each load,
`hypr/setups.lua` reads what is plugged in from sysfs, chooses a setup, and
emits complete monitor and keyboard rules for it. Changing setup means
recording the choice and reloading. Because a reload clears every rule, no
rule outlives the display it was meant for, and logging in at another desk
gets the right layout on the first modeset.

Dragging the displays with no setup in use works the same way. Bento records
them in the state file as a setup with no name (an arrangement) and Hyprland
reloads; every load after that places the displays from the record, as it
places a setup's, until a display or dock changes.

Runtime rules are used in two places only: guarding tiled displays the moment
they connect, and the second pass when Bento takes over two lit tiles.

### Where things live

| Part | Does | Why there |
|---|---|---|
| `hypr/setups.lua` | Reads what's plugged in (display EDIDs, Thunderbolt units, USB devices) from sysfs. Chooses the setup and emits its monitor rules and keyboard overrides at every load, or with no setup, places the displays where they were dragged. Guards tiled displays whether or not a setup is active. After a hotplug, waits for things to settle and reloads if something relevant changed. Checks the result and falls back when it's wrong. Owns the state file. | Display behaviour lives in Hyprland (principle 7), and every load has to rebuild the layout anyway. A load takes about 3 to 6 ms, the scan included. |
| `hypr/edid.lua`, `hypr/sysfs.lua`, `hypr/json.lua` | EDID keys and tile blocks, the sysfs scan (DRM connectors, Thunderbolt, USB), and JSON for the Lua side. | Plain Lua with no dependencies, tested on their own. |
| `hypr/keyboard.lua` | Each keyboard's own keymap, from the repo's `keyboards.json` and yours. | It stays independent of setups, so a broken `setups.json` can't take out your keymaps. |
| `bin/bento-setup` (bash) | `bento setup …`, "Save current as setup", the pane's apply, and its drags with no setup in use (`arrange`). It talks to `setups.lua` through files: a choice goes in `setup-request.json`, then a `hyprctl reload`, and the answer is in the state file. From stage 2 it also sets audio. | Works without the shell and is easy to try from a terminal. PipeWire calls would block the compositor, so they can't run in Lua. |
| `Service.qml` (shell) | Runs `install.sh` when the shell starts Bento, and starts `bin/bento-cleanup` when the shell lets go of it. Stage 2: tells `bento-setup` when PipeWire devices come and go. | Long-running watchers need a host, and the shell already exists and goes away with Bento. |
| `prefs/Setups.qml`, `prefs/Keyboards.qml`, `pages/SetupsMenu.qml` | The Setups pane, the Keyboard pane's Keyboards group, and the bar menu. `prefs/SetupsStore.qml` reads and writes the files; `prefs/SetupsData.js` holds the logic, snapping included; `prefs/Identify.qml` outlines the screen of the display selected in the pane. | Interface lives in the shell. |

Lua can't ask BlueZ anything, so a Bluetooth device can't identify a desk in
v1. USB devices can, but plugging one in doesn't trigger a choice on its own;
it counts the next time displays change.

### Files

- `~/.config/bento/setups.json`: your setups. The Bento app and `bento setup
  save` write it, keeping `setups.json.prev` for rollback, as with
  `settings.json`. A change that failed its check is kept as
  `setups.json.rejected`. A file you edit by hand is never rolled back (see
  [Checking and falling back](#checking-and-falling-back)).
- `~/.config/bento/keyboards.json`: your keyboards' own keymaps, only where
  they differ from the repo's.
- `keyboards.json` in the repo: built-in models (the Magic Keyboard, the K3
  Pro, the laptop's AT keyboard), so they work for everyone.
- `~/.local/state/bento/setup.json`: the state file. Only `setups.lua` writes
  it, atomically, at every load and after each check. `bento-setup`, the pane
  and the bar menu only read it.
- `~/.local/state/bento/setup-request.json`: a choice or an arrangement from
  `bento setup` or the app, written by `bento-setup` and taken (deleted) by
  the next load.
- `~/.local/state/bento/audio.json` (stage 2): written only by `bento-setup`.
  It will record what Bento wrote to WirePlumber.

Turning Bento off deletes all of `~/.local/state/bento`. `~/.config/bento`
stays unless you purge it (see
[Works as an Omarchy plugin](#works-as-an-omarchy-plugin)).

#### setups.json

This is what `bento setup save` writes at each desk, with Omarchy's scale at
2.

```json
{
  "version": 1,
  "setups": [
    {
      "id": "k3v9",
      "name": "Home",
      "when": [ { "display": "APP:AE3A:748D119E", "label": "StudioDisplay" } ],
      "displays": [
        { "display": "APP:AE3A:748D119E", "label": "StudioDisplay", "native": [5120, 2880], "size": [2560, 1440],
          "at": [0, 0], "transform": 0, "mode": "5120x2880@60", "primary": true },
        { "display": "internal", "label": "Laptop", "native": [2880, 1800], "size": [1440, 900],
          "at": [2560, 540], "transform": 0 }
      ]
    },
    {
      "id": "w81c",
      "name": "Work",
      "when": [ { "display": "GSM:5B74:309NTWGC3705", "label": "LG UltraFine" } ],
      "displays": [
        { "display": "GSM:5B74:309NTWGC3705", "label": "LG UltraFine", "native": [5120, 2880],
          "size": [2560, 1440], "tiles": "single", "at": [0, 0], "transform": 0, "primary": true },
        { "display": "internal", "label": "Laptop", "native": [2880, 1800], "size": [1440, 900],
          "at": [2560, 540], "transform": 0 }
      ],
      "keyboards": { "3434:0233": "pc" }
    },
    { "id": "a000", "name": "Anywhere else", "when": [] }
  ]
}
```

- **`version`** is 1. A file with any other version gives no setups, and
  `problems` says why.
- **`id`** is 4 to 12 lowercase letters and digits, and never changes, so
  renaming or deleting a setup can't confuse the state file. Save makes a
  random one of 4. `name` is only a label; `auto`, `pick`, `save`,
  `arrange`, `why`, `apply`, `status` and `help` can't be names, because
  they're commands.
- **`display`** is an EDID key: the three-letter vendor code, the product
  code, and the serial text from the EDID (else its serial number in hex,
  else `0`), read straight from the EDID bytes. No lookup tables are needed,
  and Lua and bash can't disagree about it. `"internal"` is the laptop panel,
  whatever it is called.
- **`label`** is the name the EDID gives, shown in the pane, the menu and the
  notes.
- **`native`** is the panel's full size, so the pane can draw a display that
  isn't connected. For the UltraFine it's the whole 5120×2880, even though it
  runs at 3840×2160 here.
- **`size`** is the logical size when saved, and **`at`** is Hyprland's
  logical position. Positions adapt from these when a display is missing or
  its size changed.
- **`scale`** is relative to the panel's native size, so the UltraFine at 2
  looks like 2560×1440 whichever mode carries it. Leave it out and the
  display follows Omarchy's scale, taken relative to the panel the same way
  (or as Omarchy's Scale shortcut set it; see [Display rules](#display-rules)).
  Save leaves it out when it's the same as Omarchy's, which is why neither
  display above has one. The laptop only gets its own when Omarchy's scale
  is `auto`.
- **`mode`** is only on a plain external display: the mode it ran when saved.
  Bento asks for it again when the display lists it, and otherwise uses its
  preferred mode. Tiled displays and the laptop have none; Bento works their
  mode out.
- **`transform`** is Hyprland's rotation, 0 to 7, and **`primary`** marks one
  display.
- **`tiles`** only appears on tiled displays, and v1 only has `"single"`: one
  stream on the left tile, the others off. Bento runs every tiled display
  that way whatever it says.
- **`when`** lists the devices that identify the setup: displays (`display`,
  the EDID key), Thunderbolt devices (`thunderbolt`, the unique id in sysfs)
  and USB devices (`usb`, vendor:product), each with a `label`. A setup with
  an empty `when` is the fallback. Bento reads no USB serials, because those
  can wait on the device.
- **`keyboards`** inside a setup overrides a keyboard's own keymap while that
  setup is active. Here the K3 Pro switches to PC at work. Keymaps are
  `apple`, `pc` or `omarchy` (Omarchy's layout, no Bento keymap).
- **Audio and camera** (stages 2 and 3) will be stored as identities (USB
  ids, serial, profile), never as node names or ids. Stage 1 ignores fields
  it doesn't know.

Every field is checked. A bad display is skipped, and so is a bad setup or a
bad device in a `when` (it would match more than it should); the rest still
works. Each problem is a sentence in the state file's `problems`, which the
pane and `bento setup why` show.

#### keyboards.json

The repo's file and yours have the same shape. A keyboard is keyed by its USB
vendor:product, or by any name with its vendor:product pairs in `ids`.
`devices` are Hyprland's names for it, which cover it before it's plugged in:

```json
{
  "3434:0233": { "label": "Keychron K3 Pro", "keymap": "apple",
                 "devices": ["keychron-keychron-k3-pro", "keychron-keychron-k3-pro-keyboard"] },
  "apple-magic-keyboard": { "label": "Apple Magic Keyboard", "keymap": "apple",
                            "ids": ["05ac:029a", "004c:029a"],
                            "devices": ["apple-inc.-magic-keyboard-with-touch-id"] },
  "laptop": { "label": "Laptop keyboard", "keymap": "pc",
              "devices": ["at-translated-set-2-keyboard"] }
}
```

Yours is laid over the repo's field by field, so `{ "3434:0233": { "keymap":
"pc" } }` is all it takes to change one keymap. The Keyboard pane writes only
the differences.

#### The state file

`setup.json` keeps fields it doesn't know, so a later Bento's survive. As
built, it holds:

- `version` (1), `load` (counts the loads), `at`, and `config`, a hash of
  `setups.json` that failed marks are tied to.
- `problems`: sentences about `setups.json` and the keyboards, and why an
  arrangement asked for at this load was refused ("That arrangement can't be
  used: …").
- `devices`: the `fingerprint` of the relevant devices, and the `displays`,
  `thunderbolt` devices and `usb` ids connected. There is one display entry
  per display, with its `connectors`. A tiled display is one entry (`tiled`,
  `left`, `complete`, `native`), and so is one whose left tile has no modes
  yet (its connectors, without `native`). A phantom is one of its display's
  connectors, never an entry.
- `setups`: each setup's `matches`, `score` (devices in its `when`),
  `usable`, `failed` and `note`.
- `active`, and `reason`: `hand`, `auto`, `fallback` or `none`.
- `hand` (`{id, fingerprint}`), the setup chosen by hand and what was
  connected then; `hand_error`, why the last choice by hand was refused.
- `arranged`: the arrangement by hand, `{fingerprint, displays}`, where
  `displays` is in `setups.json`'s format, `[{display, label, native, size,
  scale, at, transform, mode}]`, in the app's order, each under the
  display's own key. `native`, `size`, `scale` and `mode` are there only
  when the request had them; there's never a `tiles` or a `primary`, and
  `label` is the display's own when the request gave none. `null` when there
  is none. See [Arranging by hand](#arranging-by-hand).
- `failed`: `{id, fingerprint, config}` for each setup that failed its check,
  at most 50.
- `retry`, `stopped` and `drift`: fingerprints. `retry` marks the one retry
  after a failure, `stopped` that Bento stopped choosing, and `drift` the one
  reload spent on drift.
- `reloads`: `{at, count, why}` for the reload breaker.
- `laptop_scale` and `external_scale`: Omarchy's scales, which a display
  without its own `scale` follows.
- `tile_scales`: a scale Omarchy's Scale shortcut gave a tile, or a plain
  display at a mode other than its panel's own (see
  [Display rules](#display-rules)).
- `requested`: the rules of the last load (`hash`, `monitors`). Entries with
  `disabled` come only from the tile guard.
- `check`: `{load, state, at, detail}`, where `state` is `pending`, `passed`,
  `failed` or `skipped`.
- `last_failure`: the last check that failed, with the setup it blames. `id`
  is `null` when only the tile guard's part differed, or when an arrangement
  failed; then it also has `arranged: true`.
- `guard_notice`: the last such difference already told, so it's said once.
- `request_load`: the load that took the last `setup-request.json`.
- `keyboards`: each known keyboard, its own keymap, the setup's `override`,
  whether it's `connected`, and its device names.
- `descriptions`: Hyprland's description for each display key seen, so the
  guard's `desc:` rule can go out at login, before Hyprland lists anything.

#### The request file

`setup-request.json` is one of:

- `{"hand": "<id>"}` to use a setup by hand;
- `{"hand": null}` to go back to automatic, which also ends an arrangement;
- `{"arrange": {"displays": [display, …]}}` to place the displays by hand,
  with no setup in use. Each display is written as in a setup in
  `setups.json`: `bento setup arrange` sends what `bento setup save` would
  write for it, at the place asked for and with no `primary`, for example
  `{"display": "internal", "label": "Laptop", "native": [2880, 1800],
  "size": [1440, 900], "at": [2560, 540], "transform": 0}`. `display` is a
  display key, `"internal"` for the laptop. A display with only `display`
  and `at` is taken too, and then has nothing of its own: Omarchy's scale,
  no rotation, and its preferred mode (a tiled display still runs one
  stream).

The load that reads it deletes it, sets `request_load`, and either takes it
or says why not. A choice by hand, or automatic, clears `stopped`; a refused
choice puts the reason in `hand_error` ("There's no setup …", "Not connected:
…"). An arrangement leaves `stopped` alone, because Bento still won't choose
a setup for these devices; a refused one puts the reason in `problems` and
changes nothing else. A request whose `hand` is a string is a choice by hand,
whatever else it says.

### Choosing a setup

- **Relevant devices** are the external displays plus every Thunderbolt or
  USB device named in some setup's `when`. Their sorted ids are the
  fingerprint, and only a change in it can change the setup. A YubiKey, a
  mouse or headphones never do.
- A setup **matches** when every device in its `when` is connected. The best
  match has the most devices; a tie goes to the setup listed first.
- **At every load, Bento takes the first of these:**
  1. the setup chosen by hand, while the fingerprint is the one it was chosen
     with and the setup can still be used;
  2. nothing, when even the fallback failed for this fingerprint (Bento has
     stopped; see [Checking and falling back](#checking-and-falling-back));
  3. the best match that hasn't failed and can be used;
  4. the first fallback (an empty `when`) that hasn't failed. A fallback
     doesn't need its displays connected; the ones that are missing are
     placed around.

  With no setup, tiled displays are still guarded, and Omarchy's
  `monitors.lua` does the rest. Displays the active setup doesn't name get no
  rule from Bento either: Omarchy's catch-all places them.
- **Choosing by hand** holds until a display or dock changes. Then Bento goes
  back to automatic and says so in a quiet notification: "Back to automatic:
  Home". Choosing a setup by hand also clears its failed marks for these
  devices, and ends a stop.
- A setup **can be used** when at least one of its external displays is
  connected, or when it has none. The menu and the pane grey out the others
  ("Not connected: StudioDisplay"). A setup that can be used but doesn't
  match gets a note ("Not matched: CalDigit TS4 missing") and can still be
  chosen by hand. That is the escape hatch for plugging the UltraFine in
  some other way. The other notes are "In use", "Chosen by hand", "Failed
  its check", "When no other setup matches", "Stopped after a failed check",
  "Matches" (while another is chosen by hand) and "Another setup matches
  better". In the menu, a setup's row says only why it can't be used or
  failed its check, or that it's in use. Automatic's note says nothing while
  a setup is chosen by hand, "arranged by hand" while an arrangement holds
  (even after a stop), and otherwise "stopped after a failed check", what it
  uses now, or "nothing matches now". The pane, the bar menu and `bento
  setup pick` say the same.
- A setup that **failed its check** is skipped for that fingerprint and that
  version of `setups.json`. Choosing it by hand tries again.

"Save current as setup" (and `bento setup save`) puts every external display
that's connected in `when`. When another setup has the very same displays, it
adds the Thunderbolt devices connected too, so two rooms with the same monitor
model are told apart by their dock. If the two still look the same, save warns
that the one listed first wins. In the pane, **Identified by** shows the
setup's devices, its displays, the displays connected and the Thunderbolt
devices as chips to tick in or out, and warns when another setup has the same
ones.

**Settling.** After a monitor event, Bento waits until 1.5 s have passed with
no more, but never longer than 8 s after the first. A TS4 brings everything up
within about 4 s. The two UltraFine tiles arrive as two separate hotplugs, at
most 0.6 s apart. After any load, Bento also looks once more 2 s later, in
case the load landed in the middle of a dock coming up. Then it scans again:
when the fingerprint changed, or a tiled display's shape did (a tile woke up,
a phantom came or went), it reloads ("devices changed").

### Arranging by hand

With no setup in use, dragging a display in the Setups pane, or `bento setup
arrange`, places the displays by hand. That is an arrangement: a setup with
no name, in `setups.json`'s format, that only moves the displays.
`setups.lua` keeps it in the state file (`arranged`) with the fingerprint it
was made with, and places the displays from it at every load, the way it
places a setup's.

- **It holds like a choice by hand.** It survives `hyprctl reload`,
  Omarchy's own reloads, Bento's drift reload and logging in again with the
  same displays. It goes quietly at the first load whose fingerprint differs: a
  display or the dock plugged in or out, or a new setup naming a Thunderbolt
  or USB device that's connected. Then Omarchy's `monitors.lua` places the
  displays again, or a setup that matches does. Closing the lid doesn't
  change the fingerprint, so the arrangement stays. One carried over from an
  earlier load has each display checked again, as when it came (though not
  against what's connected or lit), and goes if one no longer passes.
- **Only while no setup is in use.** A setup in use places its displays
  itself, so a drag in the pane edits that setup instead, and `bento setup
  arrange` refuses ("Work is in use · drag it in Preferences"). With a
  fallback (a setup with an empty `when`), a setup is in use unless the
  fallback failed its check with these devices. When a setup comes into use
  while an arrangement is held, the arrangement waits in the state file: it
  goes once that setup passes its check, and comes back if the setup fails
  its check.
- **What a new one must say.** Each display is checked as a setup's is, but
  where a setup does without a wrong field, or skips that display, anything
  wrong refuses the whole arrangement. Every display it names is connected
  and named only once, at two whole numbers; a fraction is refused, not
  rounded. Every display showing a picture now must be in it, so nothing is
  left where it was to overlap. A picture is what `bento setup save` counts:
  a size and a scale, never another display's picture (a mirror), and never
  640×480 except on a plain display Bento knows the size of. A mirror, or a
  display that's connected but dark, may be left out. A refused arrangement
  changes nothing and leaves its reason in `problems`: "That arrangement
  can't be used: it doesn't say where LG UltraFine goes". The other reasons
  are "it names no displays", or that a display "isn't connected", "is in it
  twice", "has a position that isn't two whole numbers", "has no position
  (at)", "doesn't say which display it is", "has a scale that isn't a number
  from 0 to 10" or "has a transform that isn't 0 to 7".
- **What sets it apart from a setup.** It has no name, primary, keymaps or
  `when`, it lives only in the state file, and nothing marks it failed. Each
  display in it is what `bento setup save` would write for it (its label,
  sizes, scale when that isn't Omarchy's, rotation, and a plain external
  display's mode) at the place it was dragged to. So a drop moves displays
  without changing what they run: each keeps its scale and rotation, and a
  plain external display its mode. Other `monitors.lua` settings carry on
  only from a rule written by connector (see An arrangement's rules under
  [Display rules](#display-rules)). Its rules are built as a setup's (see
  [Display rules](#display-rules)): the laptop runs its preferred mode and a
  tiled display one stream, and when a display's size changes later
  (Omarchy's Scale shortcut, say), the places adapt.
- **What ends it,** besides a new fingerprint: choosing a setup by hand (a
  refused choice leaves it); choosing Automatic, in the bar menu or with its
  radio button in the pane, `bento setup auto`, or the pane's **Let Omarchy
  arrange**, which all do the same; a setup that comes into use and passes
  its check; and a failed check, which puts back the one before or none (see
  [Checking and falling back](#checking-and-falling-back)). Automatic stays
  chosen while an arrangement holds, but choosing it again still ends the
  arrangement. Clicking Automatic's row in the pane doesn't: that only shows
  the displays.
- **Saving it.** **Save as setup…** in the pane saves what's connected and
  where it is, as `bento setup save` does. The arrangement is already what
  save writes, so the new setup's displays are the arrangement's, plus
  `tiles` on a tiled display and `primary` on the focused one, and nothing
  moves on screen. The new setup matches at once, so it comes into use at
  the save's own load, its check passes, and the arrangement goes. Not after
  a stop, though: while Bento has stopped choosing for these devices, a save
  doesn't end the stop, so the new setup waits until a display or dock
  changes or you choose it, and the arrangement holds meanwhile ("Saved Work
  · no setup in use"). From then on the setup brings the displays back
  whenever you plug in.

### What happens on a dock plug

1. The first UltraFine tile connects. Straight away, with no settle, the tile
   guard makes sure both tiles are never lit at once (see Display rules).
2. Bento waits for things to settle.
3. It reads what is plugged in. If the relevant devices changed, it reloads.
   If they didn't (the event was Bento turning a tile off), it only looks for
   drift.
4. At load, `setups.lua` chooses Work and emits complete rules: the
   UltraFine's left tile on its best single-stream mode at 0,0, the right tile
   off, the laptop at 2560,540 at Omarchy's scale, and the keyboard overrides.
5. 300 ms later it starts checking the result. If it passed, a quiet
   notification says "Work · LG UltraFine"; clicking it opens the Setups
   pane. From stage 2 the audio follows. If it failed, see
   [Checking and falling back](#checking-and-falling-back).

Undocking works the same way. The displays go, Bento settles and reloads,
and the fallback takes over. The UltraFine's old rules disappear with the
reload, and so does an arrangement by hand: docking again brings back a setup
that matches, or Omarchy's placement, never the arrangement.

`bento setup Home` records the choice and continues from step 4.

### Display rules

- **Every rule is complete:** mode, position, scale and transform. Bento
  addresses displays by connector name, worked out from the EDIDs at each
  load. A rule can't outlive its display, because every relevant change
  reloads.
- **Tiled displays are always guarded, whichever setup is active,
  including none.** The guard is planned first in `setups.lua`, in its own
  `pcall`, before `setups.json` is read. It needs only sysfs and Hyprland's
  monitor list.
  - At every load, in this order: a `desc:` rule turns the whole display
    off; a rule per connector turns off every tile but the left one, and any
    phantom; then the setup's (or the arrangement's) other displays; and last
    the left tile's own rule, with its single-stream mode. The connector rule
    is newer than the `desc:` rule, so it wins for the left tile. If the
    active setup or an arrangement has the display, its position and scale
    apply. Otherwise the position is `auto` and the scale follows Omarchy's.
    The runtime guard below and drift use the same position.
  - At runtime, a `monitor.added` handler acts right away on a connector the
    load didn't already plan for. If the new output is the left tile, Bento
    turns the whole display off by description, then gives this connector
    its single-stream mode, so the other tile connects already off. If it's
    another tile, Bento turns it off by connector, never by description (that
    would turn off a lit left tile too); the left tile can then only come up
    alone, and its own `monitor.added` sets its mode. A left tile with no
    modes yet gets nothing; the settle's reload plans it. A phantom is turned
    off by name.
  - The handler runs before Hyprland sees the next hotplug, so two tiles are
    never lit at different modes.
- **The single-stream mode** is the largest mode in the display's mode list
  that has the panel's shape and is at most 3840 wide, at its highest refresh
  up to 61 Hz. Its scale is worked out from the mode, so the display always
  looks the same size: the setup's (or the arrangement's) scale, else
  Omarchy's number, else about 2560 logical pixels across, each relative to
  the whole panel. With
  Omarchy's scale of 2, that is 3840×2160 at 1.5, 3200×1800 at 1.25, or
  2560×1440 at 1, so the UltraFine is always 2560×1440 logical.
  - Bento takes the mode list from Hyprland whenever Hyprland lists the
    display with modes, which covers every reload, and drops modes with a 0
    in them. At login, before Hyprland lists anything, it takes the kernel's
    modes at 60 Hz (`3840x2160@60.000`), and the check allows 1 Hz either way
    for those.
  - Bento never asks for a mode that isn't in the list, never asks for a
    `0x0` mode, and never asks for `preferred` on a tile.
- **When two tiles are lit, Bento uses two passes.** First it turns the extra
  tiles off and keeps the left tile's current mode. Once `monitor.removed`
  has arrived for each of them (or 500 ms pass), it sets the left tile's new
  mode, even when that's the mode it already runs. This matters when Bento
  takes over a display Omarchy's catch-all had lit on both tiles.
- **Bento never emits a rule for a connector Hyprland hides,** like the
  Studio Display's second one. Save never writes `tiles` for it.
- **The laptop panel** follows Omarchy's scale. Bento reads it from
  `monitors.lua` the way Omarchy's clamshell script does: the laptop's own
  rule, then the catch-all, then `omarchy_monitor_scale`. Since the scales
  always agree, the clamshell watcher never steps in. Only when that number is
  `auto` may a setup carry its own laptop scale. When the laptop's own rule
  has an expression Bento can't work out, Bento leaves the scale out of its
  rule, so that rule keeps deciding. External displays without their own
  scale follow the catch-all's number (`external_scale`), relative to the
  panel as a tile's is and as save reads it: a plain display at a mode other
  than its preferred one keeps the size that number gives it at its
  preferred mode. Bento never sets the laptop `disabled`, so Omarchy's lid
  toggles keep working. When Omarchy's mirror toggle is on, Bento gives the
  laptop no rule and leaves the mirrored display alone.
- **Omarchy's Scale shortcut keeps working.** It rewrites the number in
  `monitors.lua`, Hyprland reloads, and the laptop and every display without
  its own scale take the new number. A display with its own `scale` in the
  active setup or the arrangement keeps it: that scale wins. A display whose
  size changes moves the ones beside it (see Positions adapt below). On a
  tiled display, and on a plain display at a mode other than its panel's
  own, the shortcut sets the scale as is (the left tile's, on a tiled
  display), which fitted to the panel again would come out different: on a
  5K panel at 2560×1440, up from 1 to 1.25 would come back as 0.625, smaller,
  and stick there. So Bento keeps the shortcut's choice for that display
  (`tile_scales`) for as long as Omarchy's number stays the same, unless the
  display has its own `scale`.
- **Omarchy's mirror toggle** names the display it mirrors to. Bento leaves
  that display out of the check, and `bento setup save` leaves any mirrored
  output out of a new setup. An arrangement leaves a mirror out the same way:
  the pane doesn't draw it, `bento setup arrange` doesn't ask where it goes,
  and `setups.lua` doesn't count a monitor Hyprland marks as a mirror among
  the displays showing a picture.
- **A tiled display half woken up.** After a replug Hyprland can list both
  tiles at 0×0, or the right tile at 640×480, or flip it between the two
  with no event, or list it with an empty EDID and description. Bento never
  works a mode or a scale out of a 0 width, and never asks for a `0x0` mode.
  A right tile at 640×480 or 0×0 is a tile to turn off, never a display of
  its own. With no modes from Hyprland it takes the kernel's. A tile whose
  left half has no modes anywhere yet gets no rules until it has.
- **A phantom tile:** a connector next to a tiled display's left tile, on the
  same card and of the same type, with no EDID (or only the display's own key
  without a tile block) and a tile position still free. It is folded into
  that display, turned off by name (a `desc:` rule can't reach an empty
  description), never shown as a display in the pane or `bento setup why`,
  and never saved.
- **The left tile half awake.** A panel powered off at boot can answer on
  its left connector with a partial EDID (no tile block, no modes) or none,
  listed at 0×0, while the right tile has its whole EDID. Then only the
  right tile says it's a tile, and it is never taken for the left one. The
  half-awake connector is the display's left tile: one display in the pane
  and `bento setup why`, never turned off, never given a rule. The display
  waits with no rules, placed around as if missing, and `bento setup save`
  waits for it. When the left tile wakes, the runtime guard drives it on one
  stream and the settle reloads once. A connector with no EDID goes first to
  a display whose left tile is there, as its phantom, so a second tiled
  display missing its left tile never takes it.
- **Positions adapt.** If a display in the setup or the arrangement is
  missing, or its logical size now differs from the saved `size` (after
  Omarchy's Scale shortcut, say), the displays to its right (or below it,
  where they overlap) move by the difference, keeping their order and
  alignment. A tiled display Bento can't drive on one stream, and one whose
  left tile has no modes yet, count as missing. The ★ passes to the first
  display that's connected.
- **Primary** is where the cursor starts at login (`cursor.default_monitor`)
  and where focus goes after a change of setup that passed its check. Bento
  can't move Omarchy's bar. An arrangement has no primary, so Bento sets no
  `cursor.default_monitor` while one holds.
- **An arrangement's rules** are a setup's: the same placing, the same
  place in the load, and for each display it names, the rule a setup with
  that display would get. Displays it doesn't name get no rule. Each rule
  names its output, so, as a setup's does, it wins over a rule for that
  output in `monitors.lua`; what that rule gave a display when you dragged
  (a 144 Hz mode, a scale, a rotation) is in the arrangement, so it carries
  on. A laptop mode other than its preferred one doesn't, as in a setup.
  Hyprland adds a rule to an earlier one for the same output, so the rest of
  a `monitors.lua` rule written by connector (`output = "DP-1"`, as
  Omarchy's template has it), such as `vrr`, `bitdepth` or `cm`, still
  applies. The rest of a rule written by `desc:`, and of the catch-all
  (`output = ""`), doesn't: Bento's rule for that connector wins over them
  whole. As with a setup, that goes for every display named, and an
  arrangement names every lit display, even one you didn't drag. Ending the
  arrangement (Automatic, or a new fingerprint) brings those settings back.

### Checking and falling back

- **What is checked.** After every load that sent monitor rules,
  `setups.lua` compares `hl.get_monitors()` with what it asked for. The first
  read is at 300 ms, then one every 250 ms, at most 13 (3.3 s). Two reads in
  a row that agree and match end it at once; a difference only counts from
  the third read, once two reads agree. Reads before the second pass never
  count as agreeing. It checks only what Bento set: mode (refresh within 0.05 Hz, or 1 Hz
  for a mode taken from the kernel), scale (within 0.001), position,
  rotation, and that the tiles it turned off are off. The mode also has to be
  in that display's mode list, which catches a silent custom mode.
- **What isn't.** The laptop panel is skipped while Omarchy has it off (lid
  closed or disabled) and while it is mirrored, and so is the display the
  mirror toggle names. A disabled laptop can't be Bento's mistake, because
  Bento never disables it.
- **Nothing to judge yet.** When Hyprland shows no monitors, or a display
  Bento asked to light is listed at 0×0 (it hasn't been probed), the check is
  `skipped` ("LG UltraFine has no mode yet") instead of blaming the setup.
- **Passed.** When the setup changed, a quiet notification names it and its
  displays ("Work · LG UltraFine"), and focus moves to its primary display.
- **The tile guard's own part.** When the only difference is something the
  guard asked for (a tile Hyprland keeps listing although it was turned off),
  no setup is to blame: nothing is marked failed and nothing reloads. A
  critical notification, "A display didn't come out right", says it once for
  these devices and this difference (`guard_notice`), however often Omarchy
  reloads. An arrangement stays through it.
- **On failure,** the setup is marked failed for these devices and this
  version of `setups.json`, and a choice by hand is dropped. Bento reloads
  ("check failed"), and the load chooses the next best match, the fallback,
  or no setup at all, with tiled displays still guarded. A critical
  notification names what differed: "Work didn't work", "LG UltraFine: asked
  for 3840×2160, got 3200×1800. Trying again without it."
- **One retry, then stop.** If the setup tried after a failure fails too, or
  the fallback fails after another setup already failed for these devices,
  Bento says it "won't try another setup until something is plugged in or
  out", and chooses nothing more until the devices change or you choose by
  hand.
- **An arrangement that fails,** with no setup in use and one of its own
  rules coming out wrong, marks nothing failed and leaves `failed`, `retry`
  and `stopped` alone. `last_failure` says it was the arrangement (`id`
  null, `arranged` true). On the load that took the new arrangement, the one
  held before comes back; on any later load, the arrangement goes. Then
  Bento reloads ("check failed"). So there are at most two reloads: the new
  arrangement fails and the one before comes back; if that fails too,
  Omarchy's placement. A critical notification says "That arrangement didn't
  work", what differed, and "Back to the arrangement before." or "Back to
  Omarchy's arrangement." When the reload breaker or Omarchy's update hold
  refuses the reload, the state is written anyway, the next load starts
  clean, and it says "The next reload goes back to …" instead.
- Every failure and guard notification opens the Setups pane when clicked
  (`bento preferences setups`).
- **Edits from the pane** follow the Settings rules. The pane writes
  `setups.json` (keeping `.prev`), and `bento-setup apply` reloads and waits
  up to 10 s for the load that read it and its check. Only a setup the change
  touched counts:
  - If it failed, `setups.json.prev` comes back, the failed file is kept as
    `setups.json.rejected`, and Hyprland reloads again. That happens only for
    a file written within 10 s of its `.prev`, as the app writes them. A file
    edited by hand stays as it is, every setup in it counts, and the failure
    is reported. A file that isn't JSON at all is refused before anything
    reloads.
  - Another setup failing, only the tile guard's part, or, with no setup in
    use, the arrangement by hand failing at that reload, is reported but
    rolls nothing back. The last says "The arrangement by hand didn't work:
    …", and keeps the file; `setups.lua` is already going back to the
    arrangement before, or Omarchy's.
  - While Omarchy holds reloads for a package update, nothing is checked: the
    file stays and applies at the reload that ends the hold, and the pane
    says so.
  The footer shows the outcome.
- **Drift.** When a settle finds no relevant change and the last check
  passed, Bento still compares the layout with what it asked for. If they
  differ and no Omarchy toggle explains it, it reloads once for these devices
  ("drift: …"). It never loops.
- Bento doesn't reload while Omarchy's reload guard is paused for a package
  update. Omarchy reloads when the update finishes, and that load applies the
  setup.
- **No state, no automatic reload.** Bento counts its reloads (at most 3 a
  minute) in the state file. If it can't write that file, it doesn't reload
  by itself at all.

### Keyboards

- `keyboard.lua` has no hardcoded table any more. It reads the repo's
  `keyboards.json`, then yours, field by field. If yours can't be read, the
  built-in ones still apply.
- At each load it also reads `/proc/bus/input/devices` and adds the current
  names of every known vendor:product, written the way Hyprland writes them
  (`-1`, `-2` for repeats). Stored names cover keyboards plugged in later.
  The Magic Keyboard's top-row bindings go to the same names.
- `apple` and `pc` are emitted only when `install.sh` compiled them;
  `omarchy` is emitted as `kb_file = ""`. Keymaps are part of Bento's
  modifier layout, so with Mac modifiers off none of this runs.
- `setups.lua` loads after `keyboard.lua` and emits the active setup's
  overrides. An override that can't be applied becomes a problem in the
  state file.
- The Keyboard pane has a **Keyboards** group with one row per known
  keyboard, connected or not, and a choice of Apple, PC or Omarchy. That's
  the keyboard's own keymap, saved to your `keyboards.json`. A row says "Not
  connected", and when the active setup overrides it, "PC in Work". A
  setup's override is chosen in the Setups pane.

### Audio (stage 2)

- **One resolver.** Only `bento-setup` turns an identity into a live node
  name (`pw-dump`, about 25 ms). It writes `default.configured.audio.sink`
  and `.source` by name, which is exactly what `wpctl set-default` writes.
  This works for devices that aren't connected yet; WirePlumber switches
  when they appear.
- **On a setup change,** Bento writes the new setup's devices. One
  exception: if you're on a connected headset (Bluetooth, or a device marked
  as headset or headphones), it leaves that alone and writes the setup's
  device when the headset goes away.
- **Your choice wins.** Bento records what it wrote. Any other value came
  from you (Omarchy's audio panel, `wpctl`) and stays until the next setup
  change. The pane shows it: "Headphones (your choice; Work uses LG
  UltraFine)".
- **Re-asserting.** The shell tells `bento-setup` when PipeWire devices come
  and go or WirePlumber restarts. It writes again only when Bento's own write
  was lost in a restart, or when the setup's device came back under a new
  name (the Shure's `.2`) and the default still points at Bento's write.
- Bento never clears a default, because that erases WirePlumber's history.
- The fallback points at Omarchy's tuned "Laptop Speakers", or the raw
  speaker when the tuning is off.
- WirePlumber remembers the last default after uninstall, as it does for a
  choice made in Omarchy's panel. If WirePlumber had no saved defaults before
  Bento's first write, uninstall offers to reset them.

### Camera (stage 3)

- Each setup has **this desk's camera**, stored as an identity: USB ids and
  serial, or "built-in".
- The pane shows three read-only lines, worked out from
  `/sys/class/video4linux` and Chrome's ranking without opening a camera:
  - **Chrome sites with no saved camera:** the camera Chrome's ranking picks.
    When that isn't this desk's camera, **Choose in Chrome** opens
    `chrome://settings/content/camera`.
  - **Slack app:** the first camera in `/dev` order, "unless you picked one in
    a huddle". When it's wrong, the pane says where to change it in Slack.
  - **Meet:** a fixed note: "the camera you last picked in Meet. Meet
    remembers a device number, so it can switch between desks. Check the
    preview before joining."
- Anything Bento starts that needs a camera gets this desk's camera, by its
  `/dev/v4l/by-id` path.
- Not in v1: WirePlumber's default camera (none of your call apps reads it),
  and anything that needs root.

### The Setups pane

```
 Setups
 ┌──────────────────────────────────────────────────────────────────┐
 │ (●) Automatic        now: Work                                   │
 │ ( ) Work             In use                                      │
 │ ( ) Home             Not connected: StudioDisplay                │
 │ ( ) Anywhere else    When no other setup matches                 │
 └──────────────────────────────────────────────────────────────────┘
   [ Save current as setup… ]

 WORK                                                [Rename] [Delete]

   ┌────────────────────────────┐
   │                            │
   │        LG UltraFine        │
   │   looks like 2560 × 1440   │
   │            ★               │┌──────────┐
   └────────────────────────────┘│  Laptop  │
                                 └──────────┘
   LG UltraFine   Single stream, scaled to the whole panel.
                  Looks like [2560 × 1440 · Omarchy's scale ▾]   [★ Primary]
   Laptop         Scale 2 · Omarchy's scale

 IDENTIFIED BY   [✓ LG UltraFine]  [CalDigit TS4]
                 Used when all of these are connected.
 KEYBOARDS       Keychron K3 Pro   [Its own | Apple | PC● | Omarchy]
                 Its own: Apple

 Changes to the setup in use apply right away. Others are saved for next time.
```

With no setup in use, the pane shows the displays as they are now instead:

```
 Setups
 ┌──────────────────────────────────────────────────────────────────┐
 │ (●) Automatic        arranged by hand                            │
 │ ( ) Home             Not connected: StudioDisplay                │
 └──────────────────────────────────────────────────────────────────┘

 NOW

   [ Save as setup… ]  [ Let Omarchy arrange ]

   ┌────────────────────────────┐
   │                            │
   │        LG UltraFine        │
   │   looks like 2560 × 1440   │
   │                            │┌──────────┐
   └────────────────────────────┘│  Laptop  │
                                 └──────────┘
   LG UltraFine   Single stream, scaled to the whole panel.
   Laptop         Scale 2 · Omarchy's scale

 Drag to arrange. It applies right away and lasts until a display or dock
 changes. Save it to keep it.
```

- **One control for automatic and by hand.** The radio button uses a
  setup, and holds it until a display or dock changes; its note says "Chosen
  by hand". Choosing Automatic clears the hold, and ends an arrangement too:
  while one holds, Automatic is already chosen, but its radio button still
  works and runs `bento setup auto`. Clicking a row only selects it for
  editing, and **Use** uses it. With no setup in use, clicking Automatic's
  row shows the displays as they are now, and never ends an arrangement.
- **Save current as setup…** asks for a name in place and runs `bento setup
  save`. With no setups yet, the pane says what to do: "No setups yet.
  Arrange your displays the way you like them at this desk, then save it…".
  The live view has its own instead, by the displays it saves.
- **Problems** the last load found show in red at the top, one per line.
  One that doesn't already start with `setups.json` gets "setups.json: "
  in front. A refused arrangement isn't about the file, so it shows as
  `setups.lua` wrote it: "That arrangement can't be used: it doesn't say
  where Laptop goes". `bento setup` lists the rest under "Problems in
  setups.json:", and a refused arrangement on a line of its own.
- **Looks like** offers sizes worked out from the panel's native size, for
  scales 1, 1.25, 1.5, 1.75, 2, 2.5 and 3, limited to those that give whole
  pixels on the mode it runs. The first choice is Omarchy's scale. The laptop
  only follows Omarchy's scale, unless that is `auto`.
- **The arrangement** draws each display at its logical size, filled when
  connected and as an outline from `native` when not, with ★ on the primary
  and a warning when two overlap. Nothing is selected when the pane opens.
  Clicking a box or its row selects that display, and clicking between the
  boxes selects none. The drawing leaves room either side for the narrowest
  display, so a box dragged past the end stays in sight.
- **Dragging** a box moves that display, once the pointer passes the
  system's drag distance; the window doesn't scroll instead. The box follows
  the pointer, a tinted ghost shows where it will land, and on release the
  boxes ease into place. The other boxes hold still while you drag. A drop
  that would change nothing springs back, and so does one on a drawing that
  changed under the pointer (Hyprland moved a display meanwhile). There's
  nothing to drag with one display, or while a change is under way.
- **Where a box lands.** All of it is in Hyprland's logical pixels, in whole
  numbers. A rotated display has its rotated size, a tiled display is one
  box, and the outline of a display that isn't connected moves and counts
  like the rest.
  - It goes flush against the side of another display nearest where it was
    dropped: right, left, below or above (a tie goes in that order). It
    shares at least a quarter of the shorter edge, so the pointer can cross,
    and never overlaps a display; touching is fine.
  - Along that edge it lines up with the neighbour's start, centre or end
    when one is within about 8 px on screen (at most a quarter of its own
    shorter side). Otherwise it stays where it was dropped, as far as that
    allows.
  - Displays left on their own move back as a block, nearest first, by the
    shortest move that sets them flush. Dragging the middle of three away
    pulls the third over.
  - Then the whole moves so its top left is at 0,0, as Omarchy's own
    placement starts.
- **Where a drop goes.** In the live view it moves the displays now
  (`bento setup arrange`; see [Arranging by hand](#arranging-by-hand)). The
  footer says "Arranging…", then "Arranged · until a display or dock
  changes" or why not, in red. The boxes stay where they were dropped until
  Hyprland shows the move, at most 1.5 s, and spring back at once on a
  failure. On the setup in use, a drop is an edit like any other: its `at`
  values change and it applies with the check and rollback. On a setup that
  isn't in use, it's only saved.
- **The live view** shows while no setup is in use and no setup is picked.
  It's headed "Now", and shows each display where Hyprland has it, as `bento
  setup save` would save it: lit, not a mirror, not turned off by the tile
  guard, and showing a picture. Its rows have nothing to change, and there's
  no Identified by or Keyboards. **Save as setup…** asks for a name in place
  (its button reads "Save as Work" once there's room) and runs `bento setup
  save`. **Let Omarchy arrange** shows while an arrangement holds and runs
  `bento setup auto`. When there's no list of setups, a line says "Arranged
  by hand until a display or dock changes."; otherwise Automatic's note says
  "arranged by hand". With more than one display the footer reads "Drag to
  arrange. It applies right away and lasts until a display or dock changes.
  Save it to keep it."
- **The outline on the screen.** While a display is selected or dragged, a
  thin accent frame goes round that display's own screen, so you can tell
  which box is which. It shows only while the window is open and in front
  on the Setups pane (it hides while another window or workspace has the
  keyboard), with more than one display, for a display that's lit, and not
  while a change is under way. It sits on the overlay layer
  (`bento-identify`), never takes the pointer or the keyboard, and follows
  the screen when a reload moves it.
- **Identified by** ticks devices in or out of `when`, with "Used when all of
  these are connected", or "Nothing ticked, so … is used when no other setup
  matches".
- **Keyboards** lets this setup give a keyboard another keymap while it's
  on ("Its own" leaves it alone). With Mac modifiers off, there's nothing to
  choose.
- **A setup that isn't in use** can be edited, dragged included, but only
  saved: "Not in use, so changes are saved and checked the next time Home is
  used."
- The setup in use applies on every change, with the check and rollback
  described above. Rename and Delete (with an inline "Delete Work?") are
  saved like any other change.

### The bar menu and notifications

- **Right-click the page dots** for a small menu: Automatic (with "now:
  Work", or "arranged by hand"), then the setups, then **Arrange
  displays…**, which opens the pane. Automatic stays checked while an
  arrangement holds, and choosing it ends the arrangement, as `bento setup
  auto` does; with nothing to end (no setup held by hand, no arrangement),
  it only closes the menu. A setup that can't be used is greyed, with its
  note. Right-click is Omarchy's convention for
  a widget's second action. Opening the menu closes any page preview. The
  menu only appears once you have two setups. If a switch fails, the menu
  stays open and says why.
- **With the dots turned off,** Bento's widget shows Omarchy's own workspace
  numbers, loaded from Omarchy's own widget so they look exactly stock. Once
  you have two setups, right-click the numbers, or the display icon after
  them, for the same menu. If Omarchy's widget can't be loaded, the dots
  stay rather than leaving a hole. Bento no longer swaps widgets in
  `shell.json` for this.
- **Notifications.** A quiet one when a change of setup passed its check
  ("Work · LG UltraFine"), and a quiet "Back to automatic: Home" when a
  choice by hand ends. Failures are critical: "Work didn't work", "That
  arrangement didn't work", or "A display didn't come out right" for the
  tile guard's part. An arrangement that works posts nothing; the pane's
  footer or `bento setup arrange` says so. Clicking any of
  them but "Back to automatic" opens the Bento app at the Setups pane (`bento
  preferences setups`). They go through Omarchy's `omarchy-notification-send`
  where it exists, else `notify-send`.
- **From the keyboard,** `bento setup pick` opens Omarchy's menu, the same
  one Omarchy uses to choose a webcam, with Automatic and every setup that
  can be used. It has no key of its own.

### The command line

```
bento setup                        the setups, the one in use, and why
bento setup Work                   use Work until a display or dock changes (a name or an id)
bento setup auto                   back to automatic
bento setup pick                   choose from Omarchy's menu
bento setup save Desk              save what's connected and how it's arranged; prints the new id
bento setup arrange DISPLAY=X,Y …  place every lit display (key, connector or label) until a display or dock changes
bento setup why                    every relevant device, its identity, and how each setup scored
bento setup apply                  for the app: after it wrote setups.json, reload and check, or put the old one back
bento setup status                 the state file as JSON, for scripts
```

It exits 0 when it worked, 1 when it failed or was refused (the reason goes
to stderr), and 2 for a usage mistake. One setup change runs at a time,
whether it comes from a bar, the app or the command line: they share
`$XDG_RUNTIME_DIR/bento-setup.lock` and wait up to 30 s for it. The words
`auto`, `pick`, `save`, `arrange`, `why`, `apply`, `status` and `help` can't
name a setup.

`bento setup Home` refuses, with the reason, when Home can't be used ("Home ·
Not connected: StudioDisplay"). Otherwise it writes the choice to
`setup-request.json`, reloads, and waits up to 10 s for the load that took it
(`request_load`) and its check: "Home · in use", or "Home · failed its
check: …". When nothing answers, it says "Hyprland didn't answer" or "Bento
isn't running in Hyprland", and drops the request. While Omarchy holds
reloads for an update, a choice is refused ("Omarchy is installing updates;
try again when it's done"); `save` and `apply` keep the file, which applies
when the update finishes.

`bento setup pick` guards against a missing menu. `omarchy-menu-select` waits
forever when no menu plugin is on, so `pick` summons `omarchy.menu` itself and
goes on only when the shell answers "ok". Otherwise it says "Omarchy's menu
isn't available, so here is the list.", prints the setups and how to choose,
and exits 1. It gives up after a minute, and Ctrl+C closes the menu too.

`bento setup save` saves each lit display once: a tiled display at its left
tile, with `tiles: "single"`; a plain external display with the `mode` it
runs (`"2560x1440@59.951"`), which `setups.lua` asks for again. Phantoms,
outputs at 0×0, outputs at 640×480 (unless that's a plain display's real
mode), outputs the guard turned off and mirrors are never saved. A display
that isn't showing a picture yet makes it refuse ("LG UltraFine isn't
showing a picture yet"), and so does one Bento hasn't caught up with ("try
again in a few seconds"). A display with no EDID Bento can read can't be
recognised later, so it is left out with a warning instead of blocking the
save. Save then reloads and checks the new setup; if that one fails, the old
`setups.json` comes back and it says "Not saved: …". It prints only the new
id on stdout.

`bento setup arrange internal=2560,540 "LG UltraFine"=0,0` places the
displays by hand, as a drag in the pane does (see
[Arranging by hand](#arranging-by-hand)). Each argument is a display, `=`,
and the top left corner it gets in Hyprland's layout, in whole logical
pixels. A display is named by its key (`internal` for the laptop), any of
its connectors, or its label, in any case; keys and connectors are tried
before labels. Every display showing a picture is named once, counted the
way `save` counts them. What it sends is a setup with no name: each display
as `save` would write it, at the place asked for and with no `primary`, so
only the places change (see [The request file](#the-request-file)). Under
the lock it refuses while a setup is in use, then writes the request,
reloads, and waits up to 10 s for the load that took it and its check. It
doesn't wait for a rollback after that.

- **Exit 0** when the state holds the arrangement with exactly the places
  that were sent. It prints only "Arranged · until a display or dock
  changes", on stdout, since the app takes anything on stderr for a warning.
- **Exit 2,** with the usage, when there's no argument or one isn't
  `DISPLAY=X,Y`: a name that doesn't start with `-` and has no `=`, and up
  to nine digits a side. That's checked before anything is read.
- **Exit 1,** with the reason, checked in this order:
  - "Bento isn't running in Hyprland";
  - "Work is in use · drag it in Preferences";
  - "Hyprland didn't answer";
  - "No display called 'Dell'", "More than one display is called 'Dell';
    name it by its connector", "Laptop isn't lit, so it can't be placed",
    "Say where LG UltraFine goes only once", and "Say where LG UltraFine
    goes too" ("Say where Laptop, Dell go too" for more than one);
  - "Omarchy is installing updates; try again when it's done", or, when no
    answer comes, "Hyprland didn't answer" (the reload failed, or a newer
    load came but none took the request and finished its check) or "Bento
    isn't running in Hyprland" (no newer load came at all); either way the
    request goes;
  - then, from the load that took it: "That arrangement didn't work · LG
    UltraFine: asked for 0, 0, got 1440, 0" when its check failed (Bento is
    already going back, see
    [Checking and falling back](#checking-and-falling-back)); "Work is in
    use · drag it in Preferences" when a setup came into use after all; and
    "Bento couldn't keep that arrangement" when the state doesn't hold it,
    followed by "· it doesn't say where Laptop goes" or whatever reason
    `setups.lua` gave for refusing it.

While an arrangement holds, `bento setup` says "Automatic · arranged by
hand" where it would say "None in use: …", `why` has a row for it
(Automatic, "arranged by hand"), and `pick`'s Automatic says "arranged by
hand", as the pane and the bar do. `bento setup auto` ends it.

`bento setup why` lists what's connected (each display's key, label and
connectors, with the left tile marked and "a tile is missing" when one is;
Thunderbolt devices; USB devices named in a setup), each setup's score, usable
and failed marks and note, the fingerprint, the setup in use and why ("chosen
by hand, until a display or dock changes"), the last check, a refused choice,
an arrangement ("arranged by hand"), a stop, and the problems the last load
found, a refused arrangement's included.

### Safety

- **Tiled displays are guarded whatever happens to setups:** no setup, a
  broken `setups.json`, a failed check, or an error in the rest of
  `setups.lua`.
- **Layout changes go through a reload.** The only runtime rules are the tile
  guard and the second pass for tiles. A drag is no exception: each drop is
  one full reload, checked like any other, and an arrangement is a record in
  the state file, never a rule left behind in Hyprland.
- **Every change Bento makes is checked,** with one retry and no loops. The
  check ignores what Omarchy's lid and mirror toggles do to the laptop.
  Bento makes at most 3 automatic reloads a minute, none when it can't write
  its state file, and none while Omarchy holds reloads.
- **An arrangement that fails goes back, at most twice:** to the one before,
  then to Omarchy's placement. Nothing is marked failed and Bento doesn't
  stop choosing because of it.
- **A Lua error stays inside its module,** through `bento.lua`'s per-module
  `pcall`. Inside `setups.lua` each part (scan, guard, setups, placing, each
  display's rule, keyboards, state) is caught on its own; a bug goes to
  `~/.local/state/bento/errors` after every rule is in place, and a bug in a
  timer or event shows once as a notification. Problems in `setups.json`
  show in the pane and in `bento setup why`, not in `bento-apply`'s error
  file, so they can't block unrelated settings. `bento-apply` only fails on
  errors that are new since its reload.
- **It stays fast.** A load of `setups.lua` takes about 3 ms and a monitor
  event under 1 ms plus the settle, far inside the time Hyprland allows Lua.
- **Nothing is written to `~/.config/hypr`.** Bento's files are listed in
  [Works as an Omarchy plugin](#works-as-an-omarchy-plugin). From stage 2,
  WirePlumber's remembered default will be the one thing that stays after
  removal. An arrangement lives in `~/.local/state/bento/setup.json`, so
  turning Bento off takes it with the rest of the state, and the cleanup's
  reload gives back Omarchy's placement.
- **Removing Bento gives stock Omarchy, including its tile bug.** Without
  Bento, Omarchy's catch-all drives both UltraFine tiles at `preferred`,
  which is #10691 on this laptop. When the cleanup takes the hook away with a
  tiled display connected, a critical notification gives the
  `monitors.lua` lines that keep it on one stream: by connector, the other
  tiles off and the left tile on Bento's mode and scale, at `auto`.
  `uninstall.sh` prints them. Bento never writes them itself.

### Works as an Omarchy plugin

Bento runs only as an Omarchy plugin (`manifest.json`: a service, an overlay
and a bar widget, kept loaded, and a clone of `omarchy.workspaces`). Turning
it off or removing it in Omarchy gives back stock Omarchy, with nothing left
but your settings.

**Getting in.** When Omarchy enables Bento, it puts Bento in the bar where its
workspace numbers were (enabling `omarchy.workspaces` again turns Bento off),
and the shell starts Bento's Service. The Service runs `install.sh` then, and
again only when Bento's version changes. `install.sh` runs only from the
plugin folder (`~/.config/omarchy/plugins/io.github.benjaminsehl.bento`, or a
checkout linked there) and only while Omarchy has Bento on. Under
`bento.lock` it writes the hook, the state folder, the links and the launcher
entry, and removes the toggles of older Bentos (`omarchy-mac.lua`,
`pages.lua`). Then `bento-apply` adds the Ghostty line (if that setting is on)
and reloads Hyprland; if Hyprland reports errors it didn't have before,
`install.sh` takes its hook out again. If it can't run, a notification says
why.

| What | Where | Taken away |
|---|---|---|
| The Hyprland hook | `~/.local/state/omarchy/toggles/hypr/bento.lua` | By the cleanup, only when its first line says Bento wrote it. Then Hyprland reloads |
| Bento's rules, binds, keymaps, timers | Hyprland, for one load | By that reload |
| State | `~/.local/state/bento/`: keymaps, `errors`, `setup.json`, `setup-request.json`, the `bento-cleanup` copy, `repo` | By the cleanup, whole |
| Commands | `~/.local/bin/bento`, `bento-apply`, `mac-keybindings` | By the cleanup, only links that point into Bento (an older `mac-paste` too) |
| The app in the launcher | `~/.local/share/applications/bento.desktop` | By the cleanup, only when it runs Bento |
| Ghostty keys | One marked `config-file` line in `~/.config/ghostty/config` | By the cleanup: the marker, the line and the blank line before, written through a symlink. Then `omarchy-restart-terminal` has Ghostty reload its config |
| Bento in the bar | `~/.config/omarchy/shell.json` | By Omarchy, which puts its workspace numbers back. The cleanup makes the same edit only when the plugin folder went away without a disable, or `uninstall.sh` ran with the shell down |
| Lock files | `$XDG_RUNTIME_DIR/bento.lock`, `bento-setup.lock` | `bento-setup.lock` by the cleanup; the empty `bento.lock` at logout |
| Your settings | `~/.config/bento/`: `settings.json`, `setups.json`, `keyboards.json`, their `.prev`, `setups.json.rejected` | Only by `uninstall.sh --purge` |

The cleanup is `bin/bento-cleanup`. `install.sh` copies it into
`~/.local/state/bento`, so it outlives the plugin folder.

- **Disable** (`omarchy plugin disable io.github.benjaminsehl.bento`, or the
  shell's plugin list). Omarchy puts its workspace numbers back and lets go
  of the Service, whose last act starts the cleanup, detached. Omarchy
  doesn't reload Hyprland itself, so the cleanup does. First it waits until
  Omarchy gives the same answer twice, a few seconds apart (up to five
  tries), so a shell restart or a disable quickly undone passes by. Only
  "disabled" or "gone" makes it act, never a `shell.json` it can't read.
  Then it takes the installer's lock, asks once more, removes everything in
  the table but your settings, and reloads Hyprland. If Hyprland loads first
  (the shell wasn't running, say), `hypr/bento.lua` reads `shell.json` with
  Omarchy's own rule, loads nothing, and starts the cleanup.
- **Remove** (`omarchy plugin remove io.github.benjaminsehl.bento`). Omarchy
  deletes the plugin folder (for a linked checkout, only the link), and the
  cleanup starts the same way, from its copy. If Hyprland loads first, the
  hook finds no plugin and starts that copy. When the folder is gone but
  `shell.json` still lists Bento, the cleanup takes Bento out of it the way a
  disable would, and asks the shell to reload its config.
- **`uninstall.sh`** does it all at once, for when the shell isn't running or
  you'd rather watch. It asks for the tile hint first, then turns Bento off
  through the shell (`setPluginEnabled … false`), or, with the shell down,
  leaves `shell.json` to the cleanup for the shell's next start. Then it runs
  the cleanup with `--now`, which refuses while the shell still has Bento on.
  It ends with "Bento is off and Omarchy is back", and the plugin folder
  stays until `omarchy plugin remove`.
- **`uninstall.sh --purge`** also deletes `~/.config/bento`.
- **While Omarchy holds reloads** for an update, Bento's last load stays live
  until the reload that ends the hold. The cleanup then rewrites the hook to
  do one thing, start the cleanup at that reload, and keeps
  `~/.local/state/bento` with its copy until then.
- **After an update from an older Bento** in the same session, the shell
  keeps the older Service until it restarts, so restart it
  (`omarchy-restart-shell`) or run `uninstall.sh` before removing.
- **An install from before stub 2** that had the dots off renamed its bar
  entry to `omarchy.workspaces`, which Omarchy counts as disabled. Such an
  install still loads through its old hook, so `hypr/bento.lua` asks the
  shell to enable Bento again (for a minute, every 2 s) instead of cleaning
  up, and the Service writes stub 2.

**What stays:** your settings in `~/.config/bento`, unless you purge them.
From stage 2, WirePlumber's remembered default speakers and microphone stay
too, as they do for a choice made in Omarchy's own panel.

### Moving off the temporary `monitors.lua`

The temporary `~/.config/hypr/monitors.lua` was written before Setups, and it
works against Bento:

- It reloads Hyprland on every `monitor.added` and `monitor.removed`, and
  once more 2 s later while an output is 0×0. Bento turning the right tile
  off is itself a monitor event, so every guard step costs a reload. Each one
  throws away Bento's settle and check halfway, and Bento's reload breaker
  can't count reloads it didn't make.
- It lays the UltraFine out itself, with `mode = "preferred"` on each tile.
  Bento's rules load later and win for the tiles, but the laptop's place
  still comes from this file whenever no setup names the laptop. It works
  that place out for a tile at scale 2 (1920 wide), while Bento runs the tile
  at 1.5 (2560 wide), so at work the laptop lands at 1920,180, inside the
  UltraFine.
- It does arithmetic on sizes that can be 0. That is what froze the desk
  with both tiles at 0×0; the current copy guards that one case.

Bento's tile guard is the interim fix: it keeps the right tile off and DP-1
on one stream whatever the file says, so nothing needs to change there before
stage 1 is checked. Then:

1. **Check stage 1 at work** with the [hand tests](#testing-by-hand-at-the-desk).
2. **Save Work, and Home at home,** while the file is still there: "Save
   current as setup…" in the pane, or `bento setup save Work`. At home the
   file already puts the laptop at 2560,540. At work, with no setup in use
   yet, the pane shows "Now": drag the laptop to the UltraFine's right,
   bottom edges level, then **Save as setup…** right there. (Saving first,
   then setting the laptop's `at` to `[2560, 540]` in
   `~/.config/bento/setups.json` and running `bento setup apply`, works
   too.)
3. **Put `monitors.lua` back to Omarchy's template**
   (`/usr/share/omarchy/config/hypr/monitors.lua`) with
   `omarchy_monitor_scale = 2`. That is Omarchy's own Scale setting, and the
   number Bento follows. The reload-on-hotplug hook goes with the rest;
   Bento's settle replaces it.

Bento never writes that file, so both edits are yours.

### Testing by hand at the desk

These need the real desk, and they assume a saved Work setup (the UltraFine at
0,0, the laptop at 2560,540), except the dragging tests, which need no setup
in use. Hyprland can ignore a disable and keep the tile listed, so every test
compares both lists after it settles:

```bash
hyprctl monitors        # what's lit: the UltraFine once (DP-1), the laptop
hyprctl monitors all    # also what's off: DP-2 listed as disabled, not lit
bento setup why         # one UltraFine, its connectors, the last check
```

**After the guard has run:**

- `hyprctl monitors` lists only DP-1 (3840x2160, scale 1.50, at 0x0) and
  eDP-1 (2880x1800, scale 2.00, at 2560x540). It must not list DP-2.
  `hyprctl monitors all` shows DP-2 as disabled. If DP-2 is still lit, the
  disable was ignored: report it.
- If DP-2 stays in `hyprctl monitors all`, run `cat
  /sys/class/drm/card*-DP-2/status` and `wc -c
  /sys/class/drm/card*-DP-2/edid`. Bento only recognises a phantom the
  kernel reports as connected; if it says disconnected while lit, report it.
- Omarchy's Displays panel shows the UltraFine and the laptop, and no third,
  phantom display. The Setups pane, `bento setup why` and `bento setup save`
  show the UltraFine once.
- The laptop sits at 2560,540, and the cursor crosses freely between the
  UltraFine and the laptop, with no gap and no wall.
- A rule the guard sends from an event shows in `hyprctl monitors` straight
  away, without a reload.

**At the desk:**

- Plug the UltraFine in tile by tile, in both orders; log in docked; reload
  docked; close the lid docked; mirror. Each time: DP-1 at 3840×2160, scale
  1.5, at 0,0; the laptop at 2560,540; DP-2 off in `hyprctl monitors all`;
  never both tiles lit; at most one reload by Bento (`reloads` in
  `~/.local/state/bento/setup.json`); no "didn't work" notification for
  Work.
- Replug until a tile comes up at 0×0 or 640×480. The desk recovers without
  freezing: no config error, the right tile stays off, and DP-1 comes back
  as above.
- Cold boot with the UltraFine off, then log in: `hyprctl monitors all` shows
  no `0x0@` mode and the layout doesn't jump.
- The left tile half awake: boot with the UltraFine off and check `wc -c
  /sys/class/drm/card*-DP-1/edid` (128 bytes or 0). `bento setup why` lists
  one LG UltraFine, Bento leaves both tiles alone, and the laptop sits at
  0,540. Power the panel on: DP-1 comes up at 3840×2160 at 1.5 with one
  reload (`reloads.why` is "devices changed"). If Hyprland fires no
  `monitor.added`, Omarchy's watcher for displays with no mode should still
  get there with its own reload.
- Switch the laptop keyboard to Omarchy in the Keyboard pane and check that
  it types Omarchy's layout at once (`kb_file = ""`), then switch it back.

**Dragging, with no setup in use** (before saving Work, or at a desk no
setup matches). Open the Setups pane; it says "Now". Before the first drag,
`touch /tmp/before-drag`.

- Nothing is outlined when the pane opens. Click the laptop's box: a thin
  accent frame goes round the laptop's own screen, not the UltraFine's.
  Click the UltraFine's row and the frame moves there. A click on the screen
  inside the frame reaches the window under it. Click between the boxes,
  switch pane, press Esc, close the window: each time the frame goes. With
  a box selected, switch workspace or focus another window: the frame goes,
  and comes back when Bento's window is in front again.
- The drag feels right: the box moves only once the pointer passes the drag
  distance, and the window doesn't scroll instead. The ghost shows where it
  will land. Top, centre and bottom alignment catch within a few pixels and
  let go just past that.
- Drag the laptop to the UltraFine's right, bottom edges level. The footer
  says "Arranging…", then "Arranged · until a display or dock changes", with
  one reload and no notification. The frame hides meanwhile and comes back
  on the right screen. `hyprctl monitors` shows DP-1 at 0x0 (3840x2160,
  scale 1.50) and eDP-1 at 2560x540, `hyprctl monitors all` shows DP-2
  disabled, and the cursor crosses at the shared edge. `jq .arranged
  ~/.local/state/bento/setup.json` shows both displays as `bento setup save`
  would write them, with no `primary` and no `tiles`.
- `hyprctl reload`, an Omarchy theme change, and logging out and in keep the
  arrangement. Unplug the TS4: the laptop is fine alone, and `arranged` is
  `null`. Plug it back: Omarchy's placement (the laptop on the left), not
  the arrangement.
- Drag again, then **Let Omarchy arrange**: Omarchy's placement comes back,
  nothing is left over, and the button goes. The same after a drag and
  Automatic in the bar menu, and after a drag and Automatic's radio button
  in the pane. Clicking Automatic's row alone keeps the arrangement. The
  pane lists Automatic only once there's a saved setup, and the bar menu
  only appears with two, so these need two that don't match here (Home and
  a spare saved at home, say; delete the spare after).
- With an arrangement held, use Omarchy's Scale shortcut on the UltraFine,
  then on the laptop: each time the displays change size and still touch,
  with no gap and no overlap. The shortcut rewrites the number in
  `monitors.lua` itself, so then focus the laptop, run
  `omarchy-hyprland-monitor-scaling 2` to put it back to 2, and `touch
  /tmp/before-drag` again.
- Drag again, then **Save as setup…** named Work: Work comes into use at
  once, nothing moves on screen, the pane says In use once, and `arranged`
  is `null`. Work's displays in `~/.config/bento/setups.json` are the
  arrangement's, plus `tiles` and `primary`. Replug: Work comes back by
  itself.
- `hyprctl configerrors` is empty after every drop, and `find ~/.config/hypr
  -newer /tmp/before-drag` prints nothing.
- Two things only the real desk shows, so report what happens. A display
  rotated in `monitors.lua` should keep its rotation after a drop (the
  arrangement asks for the one it had). With Omarchy's mirror on, `bento
  setup arrange` with only the displays the pane shows should work; if it
  says "Bento couldn't keep that arrangement · it doesn't say where LG
  UltraFine goes", Hyprland lists the mirror without marking it as one.
- At home (the Studio Display isn't tiled), disable Bento with an
  arrangement held: Omarchy's placement comes back. Enable it again: the
  arrangement doesn't. Not at work: without Bento, both UltraFine tiles are
  driven at once, which is #10691 (see [Safety](#safety)).

**Clean removal, on the live install:**

- Disable Bento in Omarchy and wait about 15 s. The hook, the links, the
  launcher entry, `~/.local/state/bento` and the Ghostty line are gone,
  Hyprland reloaded, and Omarchy's bindings and workspace numbers are back.
  Nothing in `~/.config/hypr` changed. Enable it again and everything is
  back, Bento's widget in the bar included.
- On an install from before stub 2 with the dots off, disable and enable
  once: `~/.config/hypr` is untouched, and Bento's widget comes back in the
  bar.

## Stages

- **Stage 0: Bento as a clean Omarchy plugin. Built.** Bento runs only as a
  plugin; stub 2, `bin/bento-cleanup` and the Service give back stock
  Omarchy on disable or remove; `uninstall.sh [--purge]`; `bento-apply` no
  longer edits `shell.json`; with dots off, Omarchy's own numbers.
- **Stage 1: displays and keyboards. Built.**
  - `hypr/setups.lua`: scan, tile guard, choice, rules, settle, check and
    fallback, state file;
  - `keyboards.json` and the `keyboard.lua` change;
  - `bin/bento-setup`: `bento setup`, `pick`, `save`, `why`, `status`, and
    the pane's apply;
  - the Setups pane with a static arrangement, scale and primary, and the
    Keyboard pane's Keyboards group;
  - the bar menu and notifications;
  - docs and the README table.

  Still to do by hand: the [hand tests](#testing-by-hand-at-the-desk) at
  work, then [moving Home and Work over](#moving-off-the-temporary-monitorslua).
- **Stage 1b: drag to arrange. Built.**
  - `hypr/setups.lua`: the arrange request, the arrangement as a setup with
    no name, held (`arranged`), placed and built like a setup, and rolled
    back when its check fails;
  - `bin/bento-setup`: `bento setup arrange`, sending what `save` would
    write, and the arrangement in `bento setup`, `why`, `pick` and `apply`;
  - the Setups pane: dragging with snapping in every view, the live view
    ("Now") with **Save as setup…** and **Let Omarchy arrange**, Automatic
    ending an arrangement there and in the bar menu, and the outline on the
    screen (`prefs/Identify.qml`);
  - docs and the README line.

  Still to do by hand: the [dragging tests](#testing-by-hand-at-the-desk)
  at work, with no setup in use.
- **Stage 2: audio.** Identities, applying by name, tracking Bento's own
  writes, the headset exception, the shell's trigger, and the pickers.
- **Stage 3: camera.** The three-line prediction, Choose in Chrome, and the
  camera for anything Bento starts.

## Open questions

The first four are answered:

1. *Should the interim fix go into `monitors.lua` now?* No. Bento's tile
   guard is the interim fix: it keeps the right tile off and DP-1 on one
   stream whatever `monitors.lua` says, with or without a setup.
2. *After stage 1, should `monitors.lua` go back to Omarchy's template with
   your scale of 2?* Yes, once the guard is checked at work and Work is
   saved (see [Moving off the temporary monitors.lua](#moving-off-the-temporary-monitorslua)).
3. *Is the camera plan right: predict and point, nothing that needs root?*
   Yes. Stage 3 builds that.
4. *Should a setup chosen by hand hold until a display or dock changes, or
   until you set it back to Automatic?* Until a display or dock changes.
   That's how it's built.
5. Still open, for the desk: does the single stream fill the whole UltraFine
   panel, or show a split picture? It doesn't change the design.

## What the review changed

The first draft had `bin/bento-setup` choose the setup and Lua replay it. A
review in three lenses (correctness, Bento's principles, UX), with each
serious point checked against Hyprland's source, changed this:

- **Tile safety no longer depends on a setup.** The draft left both UltraFine
  tiles on Omarchy's `preferred` during the settle, at login at another desk,
  with no match, and after an error: the very blackout it warned about.
- **The choice moved into Lua,** so every load decides from what is plugged
  in. That removed the files bash and Lua used to hand state back and forth
  (only a one-way request file is left), and the second settle timer.
- **Switching reloads** instead of stacking runtime rules, which can't be
  removed and would have stuck to whatever was plugged into that port next.
- **Rollback goes to a computed safe state** and marks the failed setup.
  "Put the previous setup back" couldn't work: that setup usually doesn't
  describe the displays that are connected now, and it could loop.
- **The check ignores Omarchy's lid and mirror toggles.** Without that, every
  switch with the lid closed would have rolled back.
- **Displays are identified by raw EDID fields.** Matching on Hyprland's
  description would have meant copying its vendor table into Lua.
- **Modes come from Hyprland's own list,** with the scale tied to the mode,
  and tile changes go in two passes, because Hyprland commits monitor by
  monitor.
- **The Studio Display isn't treated as tiled,** and two-tile 5K is out of v1.
- **The laptop and unscaled displays follow Omarchy's scale** instead of
  fighting its clamshell watcher and Scale shortcut.
- **Audio respects your choice and headsets.** The draft would have undone
  them after every resume.
- **The camera text no longer oversells "Choose in Chrome",** which doesn't
  help Meet or the Slack app.
- **The bar menu survives dots being off,** and every switch posts a
  notification.
