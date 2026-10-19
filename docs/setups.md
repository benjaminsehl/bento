# Setups: design proposal

A setup is a named desk: home, work, the other room at work. Bento picks one
from what is plugged in, or you pick one by hand. A setup arranges the
displays, gives each keyboard its keymap, chooses the default speakers and
microphone, and tells you which camera each call app will open.

This is a proposal. Nothing here is built yet. It was revised after a review
that tried to break it; [What the review changed](#what-the-review-changed)
lists what moved.

## What we found

These facts shaped the design. The research ran read-only on this machine and
against Hyprland 0.56.2, aquamarine 0.15, WirePlumber 0.5.17 and Chromium
source.

### Displays

- **Bento's rules already win.** Bento loads as an Omarchy toggle, after
  `~/.config/hypr/monitors.lua`, and in Hyprland the newest matching monitor
  rule wins. Omarchy's lid and mirror toggles load after Bento, so they still
  win for the laptop panel. That is the right order.
- **Connector names move.** DP-1 was the Studio Display at home and an
  UltraFine tile at work. A display's EDID (vendor, product, serial) identifies
  it wherever it is plugged in. Both UltraFine tiles carry the same EDID, plus
  a tile block that says which half each one is.
- **Runtime rules can't be taken back.** `hl.monitor` works at runtime, but
  there is no way to remove a rule. Only a reload clears them, and a reload
  also throws away Bento's timers and Lua state. Omarchy reloads by itself
  too: lid, package updates, and every edit to `monitors.lua` (auto-reload is
  on). So the layout has to come out of every config load, and a reload is
  the only clean way to change it. A reload freezes the compositor for about
  25–50 ms.
- **Hyprland applies monitors one at a time,** in the order they were
  created, with a separate commit for each. A batch of rules isn't atomic.
- **A new display's first modeset uses whatever rule exists when it
  connects.** `monitor.added` fires after that, so no reaction to the event
  can affect the first modeset.
- **`hyprctl configerrors` never reports layout failures.** A bad scale,
  mode or overlap only shows as a notification, and any `hyprctl eval` clears
  the list. Checking has to read the result back from Hyprland.
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
- **The Studio Display has a tile block too,** but its first connector
  offers the full 5120×2880, so Hyprland treats it as one display and hides
  the second connector. A display only counts as tiled when no connector
  offers the full panel.
- **⚠ The temporary `monitors.lua` can black out the work desk.** It uses
  `mode = "preferred"` on both tiles. After the next replug or login at work,
  DP-1's preferred mode becomes 3840×2160, next to DP-2's tile. That is the
  mixed modeset from #10691 that blanks every screen. Until Setups lands, the
  work branch should switch the right tile off and keep DP-1 on one stream.
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
  emitting `kb_file = ""` explicitly.

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

Runtime rules are used in one place only: guarding tiled displays the moment
they connect.

### Where things live

| Part | Does | Why there |
|---|---|---|
| `hypr/setups.lua` | Reads what's plugged in (display EDIDs, Thunderbolt units, USB devices) from sysfs. Chooses the setup and emits its monitor rules and keyboard overrides at every load. Guards tiled displays whether or not a setup is active. After a hotplug, waits for things to settle and reloads if something relevant changed. Checks the result and falls back when it's wrong. Owns the state file. | Display behaviour lives in Hyprland (principle 7), and every load has to rebuild the layout anyway. The scan takes about 4 ms. |
| `hypr/keyboard.lua` | Each keyboard's own keymap, from the repo's `keyboards.json` and yours. | It stays independent of setups, so a broken `setups.json` can't take out your keymaps. |
| `bin/bento-setup` (bash) | `bento setup …`, "Save current as setup", and the pane's apply. It talks to `setups.lua` through `hyprctl eval` and `hyprctl repl`. From stage 2 it also sets audio. | Works without the shell and is easy to try from a terminal. PipeWire calls would block the compositor, so they can't run in Lua. |
| `Service.qml` (shell) | Stage 2: tells `bento-setup` when PipeWire devices come and go. | Long-running watchers need a host, and the shell already exists and goes away with Bento. |
| `prefs/Setups.qml`, `pages/BarWidget.qml` | The Setups pane and the bar menu. | Interface lives in the shell. |

Lua can't ask BlueZ anything, so a Bluetooth device can't identify a desk in
v1. USB devices can, but plugging one in doesn't trigger a choice on its own;
it counts the next time displays change.

### Files

- `~/.config/bento/setups.json`: your setups. The Bento app writes it, keeping
  `setups.json.prev` for rollback, as with `settings.json`.
- `~/.config/bento/keyboards.json`: your keyboards' own keymaps.
- `keyboards.json` in the repo: built-in models (Magic Keyboard, K3 Pro, the
  laptop's AT keyboard), so they work for everyone.
- `~/.local/state/bento/setup.json`: written only by `setups.lua`, atomically.
  It holds the active setup, the fingerprint of the relevant devices, a setup
  you chose by hand, setups that failed, and the result of the last check.
- `~/.local/state/bento/audio.json` (stage 2): written only by `bento-setup`.
  It records what Bento wrote to WirePlumber.

```json
{
  "setups": [
    {
      "id": "k3v9",
      "name": "Home",
      "when": [ { "display": "APP:…:748D119E", "label": "Studio Display" } ],
      "displays": [
        { "display": "APP:…:748D119E", "label": "Studio Display", "native": [5120, 2880],
          "at": [0, 0], "primary": true },
        { "display": "internal", "at": [2560, 540] }
      ],
      "audio": {
        "output": { "label": "Studio Display Speakers", "usb": "05ac:…", "serial": "…", "profile": "analog-stereo" },
        "input":  { "label": "Shure MV7+", "usb": "14ed:…", "serial": "2700b3171383085d92dc1a196785e3c0", "profile": "mono-fallback" }
      },
      "camera": { "label": "Opal C1", "usb": "…" }
    },
    {
      "id": "w81c",
      "name": "Work",
      "when": [ { "display": "GSM:…:309NTWGC3705", "label": "LG UltraFine" } ],
      "displays": [
        { "display": "GSM:…:309NTWGC3705", "label": "LG UltraFine", "native": [5120, 2880],
          "tiles": "single", "scale": 2, "at": [0, 0], "primary": true },
        { "display": "internal", "at": [2560, 540] }
      ],
      "keyboards": { "3434:0233": "pc" },
      "audio": {
        "output": { "label": "LG UltraFine Display Audio", "usb": "043e:9a68", "profile": "analog-stereo" },
        "input":  { "label": "Shure MV7+", "usb": "14ed:…", "serial": "2700b3171383085d92dc1a196785e3c0", "profile": "mono-fallback" }
      },
      "camera": { "label": "ILCE-6700", "usb": "054c:0ea6", "serial": "D0CAA014BA92" }
    },
    { "id": "a000", "name": "Anywhere else", "when": [],
      "audio": { "output": { "label": "Laptop Speakers", "node": "omarchy_speaker_tuning" } } }
  ]
}
```

- **`id`** never changes, so renaming or deleting a setup can't confuse the
  state file. `name` is only a label.
- **`display`** is an EDID key: the three-letter vendor code, the product code
  and the serial, read straight from the EDID bytes. No lookup tables are
  needed, and Lua and bash can't disagree about it. `"internal"` is the
  laptop panel, whatever it is called.
- **`native`** is the panel's full size, so the pane can draw a display that
  isn't connected. For the UltraFine it's the whole 5120×2880.
- **`at`** is Hyprland's logical position.
- **`scale`** is relative to the panel's native size, so the UltraFine at 2
  looks like 2560×1440 whichever mode carries it. Leave it out and the
  display follows Omarchy's scale, as your `monitors.lua` does today. The
  laptop always follows Omarchy's scale, so it has no `scale`.
- **`tiles`** only appears on tiled displays, and v1 only has `"single"`: one
  stream on the left tile, the others off. Any other value is read as
  `"single"`.
- **`when`** lists the devices that identify the setup: displays (EDID key),
  Thunderbolt devices (unit id) and USB devices (vendor:product, plus serial
  where it has one). A setup with an empty `when` is the fallback.
- **`keyboards`** inside a setup overrides a keyboard's own keymap while that
  setup is active. Here the K3 Pro would switch to PC at work. Keymaps are
  `apple`, `pc` or `omarchy` (Omarchy's layout, no Bento keymap).
- **Audio and camera** are stored as identities (USB ids, serial, profile),
  never as node names or ids. The live name is looked up when applying.

`~/.config/bento/keyboards.json` uses the same keys:

```json
{ "3434:0233": { "label": "Keychron K3 Pro", "keymap": "apple",
                 "devices": ["keychron-keychron-k3-pro", "keychron-keychron-k3-pro-keyboard"] } }
```

### Choosing a setup

- **Relevant devices** are the external displays plus every device named in
  some setup's `when`. Only a change in that set can change the setup. A
  YubiKey, a mouse or headphones never do.
- A setup **matches** when every device in its `when` is connected. The best
  match has the most devices; a tie goes to the setup listed first. If
  nothing matches, the fallback applies. With no fallback, no setup is active:
  tiled displays are still guarded, and Omarchy's `monitors.lua` does the
  rest.
- **Choosing by hand** holds until the relevant devices change. Then Bento
  goes back to automatic and says so: "Back to automatic: Home".
- A setup **can be used** when at least one of its external displays is
  connected, or when it has none. The menu and the pane grey out the others
  ("Not connected: Studio Display"). A setup that can be used but doesn't
  match gets a note ("Not matched: CalDigit TS4 missing") and can still be
  chosen by hand. That is the escape hatch for plugging the UltraFine in
  some other way.
- A setup that **failed its check** is skipped for that set of devices and
  that version of `setups.json`. Choosing it by hand tries again.

"Save current as setup" suggests the smallest `when` that tells this desk
apart from your other setups: displays with serials first. It adds a dock
only when the displays don't tell desks apart, for example two rooms with the
same monitor model. It leaves out things that travel with you. You can tick
any device in or out, and Bento warns if two setups end up with the same
`when`.

**Settling.** After a monitor event, Bento waits until 1.5 s have passed with
no more, but never longer than 8 s after the first. A TS4 brings everything up
within about 4 s. The two UltraFine tiles arrive as two separate hotplugs, at
most 0.6 s apart. After any load, Bento also checks once more 2 s later, in
case the load landed in the middle of a dock coming up.

### What happens on a dock plug

1. The first UltraFine tile connects. Straight away, with no settle, the tile
   guard makes sure both tiles are never lit at once (see Display rules).
2. Bento waits for things to settle.
3. It reads what is plugged in. If the relevant devices changed, it reloads.
   If they didn't (the event was Bento turning a tile off), it stops there.
4. At load, `setups.lua` chooses Work and emits complete rules: the
   UltraFine's left tile on its best single-stream mode at 0,0, the right tile
   off, the laptop at 2560,540 at Omarchy's scale, and the keyboard overrides.
5. About 300 ms later it checks the result. If it passed, a notification
   says "Work · LG UltraFine" with a **Change…** button, and from stage 2 the
   audio follows. If it failed, see [Checking and falling back](#checking-and-falling-back).

Undocking works the same way. The displays go, Bento settles and reloads,
and the fallback takes over. The UltraFine's old rules disappear with the
reload.

`bento setup Home` records the choice and continues from step 4.

### Display rules

- **Every rule is complete:** mode, position, scale and transform. Bento
  addresses displays by connector name, worked out from the EDIDs at each
  load. A rule can't outlive its display, because every relevant change
  reloads.
- **Tiled displays are always guarded, whichever setup is active,
  including none.** The guard runs first in `setups.lua`, in its own `pcall`,
  before `setups.json` is read. It reads only sysfs.
  - At load, every tile except the left one is turned off. The left tile gets
    a single-stream mode. If the active setup has the display, its position
    and scale apply; otherwise the position is `auto`.
  - At runtime, a `monitor.added` handler acts right away. If the new output
    is the left tile, Bento turns the whole display off by description, then
    gives this connector its single-stream mode. The connector rule is newer,
    so it wins for this tile, and the other tile connects already off. If the
    new output is another tile, Bento turns it off; the left tile can then
    only come up alone, and its own `monitor.added` sets its mode.
  - The handler runs before Hyprland sees the next hotplug, so two tiles are
    never lit at different modes.
- **The single-stream mode** is the largest mode in the display's mode list
  that has the panel's shape, up to 3840×2160. Its scale is worked out from
  the mode, so the display always looks the same size. With Omarchy's scale
  of 2, that is 3840×2160 at 1.5, 3200×1800 at 1.25, or 2560×1440 at 1.
  - Bento takes the mode list from Hyprland whenever Hyprland has the display,
    which covers every reload. Only at first start, before Hyprland has
    probed anything, does it read sysfs. After the first `monitor.added` it
    checks against Hyprland's list and corrects the mode if needed.
  - Bento never asks for a mode that isn't in the list, and never asks for
    `preferred` on a tile.
- **When tiles are lit and the target turns some off, Bento uses two
  passes.** First it turns the extra tiles off and keeps the left tile's
  current mode. Once `monitor.removed` arrives (or 500 ms pass), it sets the
  left tile's new mode. This matters when Bento first takes over from
  today's mixed state.
- **Bento never emits a rule for a connector Hyprland hides,** like the
  Studio Display's second one. Save never writes `tiles` for it.
- **The laptop panel** follows Omarchy's scale. Bento reads it from
  `monitors.lua` the way Omarchy's clamshell script does: the laptop's own
  rule, then the catch-all, then `omarchy_monitor_scale`. Since the scales
  always agree, the clamshell watcher never steps in. Only when that number is
  `auto` may a setup carry its own laptop scale. Bento never sets the laptop
  `disabled`, so Omarchy's lid toggles keep working. When Omarchy's mirror
  toggle is on, Bento leaves the mirrored display alone.
- **Omarchy's Scale shortcut keeps working.** It rewrites the number in
  `monitors.lua`, Hyprland reloads, and the laptop and every display without
  its own scale take the new number.
- **Positions adapt.** If a display in the setup is missing, or its logical
  size changed with the scale, the displays after it slide over to close the
  gap, keeping their order and alignment. The ★ passes to the next display.
- **Primary** is where the cursor starts (`cursor:default_monitor`), where
  focus goes when the setup changes, and where a new first page opens. Bento
  can't move Omarchy's bar.

### Checking and falling back

- **What is checked.** After any load that changed the setup or its rules,
  `setups.lua` compares `hl.get_monitors()` with what it asked for. From
  300 ms on, it reads every 250 ms until two reads agree, for at most 3.5 s.
  It checks only what Bento set: mode, scale (within 0.001), position, and
  that the tiles it turned off are off. The mode also has to be in that
  display's mode list, which catches a silent custom mode.
- **What isn't.** The laptop panel is skipped while Omarchy has it off (lid
  closed or disabled) and while it is mirrored. A disabled laptop can't be
  Bento's mistake, because Bento never disables it.
- **On failure,** the setup is marked failed for these devices and this
  version of `setups.json`. Bento reloads, and the load chooses the next best
  match or no setup at all, with tiled displays still guarded. A notification
  names what differed: "LG UltraFine: asked for 3840×2160, got 3200×1800 ·
  Open Setups".
- **One fallback, then stop.** If the fallback fails its check too, Bento
  notifies and makes no more automatic attempts until the devices change.
- **Edits from the pane** follow the Settings rules. `bento-setup` saves
  `setups.json`, reloads, and waits for the check. On failure it restores
  `setups.json.prev` and reloads again. The footer shows the outcome.
- **Drift.** When a settle finds no relevant change, Bento still compares
  the layout with what it asked for. If they differ and no Omarchy toggle
  explains it, it reloads once. It never loops.
- Bento doesn't reload while Omarchy's reload guard is paused for a package
  update. Omarchy reloads when the update finishes, and that load applies the
  setup.

### Keyboards

- `keyboard.lua` loses its hardcoded table. It reads the repo's
  `keyboards.json`, then yours. If yours can't be read, the built-in ones
  still apply.
- At each load it also reads `/proc/bus/input/devices` (about 0.1 ms) and
  adds the current names of every known vendor:product, written the way
  Hyprland writes them. Stored names cover keyboards plugged in later.
- `setups.lua` loads after `keyboard.lua` and emits the active setup's
  overrides. `omarchy` is emitted as `kb_file = ""`. Stage 1 starts by
  checking that this really falls back to Omarchy's layout at runtime,
  because so far that is only read from Hyprland's source.
- The Keyboard pane gets a **Keyboards** group with one row per known
  keyboard, connected or not, and a choice of Apple, PC or Omarchy. When the
  active setup overrides a keyboard, the row says "PC in Work", and changing
  it asks "Everywhere" or "Only in Work".

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
 │ ( ) Work             LG UltraFine                       in use   │
 │ ( ) Home             Not connected: Studio Display               │
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
   LG UltraFine   Looks like [2560 × 1440 · Omarchy's scale ▾]   [★ Primary]
                  Single stream, scaled to the whole panel.
   Laptop         Scale 2 · Omarchy's scale

 IDENTIFIED BY   [✓ LG UltraFine]  [  CalDigit TS4 · work]
 KEYBOARDS       Keychron K3 Pro   [Apple | PC● | Omarchy]   (its own: Apple)
 SOUND           Output [LG UltraFine Display Audio ▾]   Input [Shure MV7+ ▾]
 CAMERA          This desk's camera [ILCE-6700 ▾]
                 Chrome sites with no saved camera: Hardware ISP Camera  [Choose in Chrome]
                 Slack app: ILCE-6700
                 Meet: the camera you last picked in Meet. Check the preview.
```

- **One control for automatic and by hand.** Picking a setup holds it, with
  the subtitle "Chosen by hand · until a display or dock changes". Picking
  Automatic clears the hold.
- **Scale** offers "looks like" sizes worked out from the panel's native size,
  limited to scales Hyprland accepts for the actual mode. The first choice is
  Omarchy's scale.
- **The arrangement.** Stage 1 draws each display at its logical size;
  clicking one selects it for scale and primary. Dragging, with edges
  snapping together, comes in stage 1b.
- **A setup that isn't active** can be edited, but only saved. The footer says
  "Saved. Checked the next time Home is used." Its displays are drawn as
  outlines from `native`, and overlaps are checked without Hyprland.
- The active setup applies on every change, with the check and rollback
  described above.

### The bar menu and notifications

- **Right-click the page dots** for a small menu: Automatic, then the setups,
  then **Arrange displays…**, which opens the pane. Right-click is Omarchy's
  convention for a widget's second action. Opening the menu closes any page
  preview. The menu only appears once you have two setups.
- **With the dots turned off,** Bento's widget stays in the bar as a small
  display icon that opens the same menu. Today `bento-apply` swaps the widget
  out when dots are off; with two or more setups it will keep it next to
  Omarchy's workspaces.
- **A notification on every change of setup:** "Work · LG UltraFine" with a
  **Change…** button. When a hand choice ends: "Back to automatic: Home".
  Failures use a critical notification.
- **From the keyboard,** `bento setup pick` opens the list in Omarchy's menu,
  the same one Omarchy uses to choose a webcam. It can take a key in
  `windows.lua` if you want one.

### The command line

```
bento setup              setups, the active one, and why
bento setup Work         use Work until a display or dock changes
bento setup auto         back to automatic
bento setup pick         choose from a menu
bento setup save Desk    save what's connected and how it's arranged
bento setup why          each relevant device, its identity, and how each setup scored
```

`bento setup Home` refuses, with the reason, when Home can't be used ("Not
connected: Studio Display").

### Safety

- **Tiled displays are guarded whatever happens to setups:** no setup, a
  broken `setups.json`, a failed check, or an error in the rest of
  `setups.lua`.
- **Layout changes go through a reload.** The only runtime rules are the tile
  guard and the second pass for tiles.
- **Every change Bento makes is checked,** with one fallback and no loops. The
  check ignores what Omarchy's lid and mirror toggles do to the laptop.
- **A Lua error stays inside its module,** through `bento.lua`'s per-module
  `pcall`. Problems in `setups.json` show in the pane and in `bento setup
  why`, not in `bento-apply`'s error file, so they can't block unrelated
  settings. `bento-apply` will only fail on errors that are new since its
  reload.
- **Nothing is written to `~/.config/hypr`.** New files are only in
  `~/.config/bento` and `~/.local/state/bento`. WirePlumber's remembered
  default is the one thing that stays after uninstall, and the README's table
  of touched files will say so.
- **Uninstalling gives stock Omarchy, including its tile bug.** Without
  Bento, Omarchy's catch-all drives both UltraFine tiles at `preferred`,
  which is #10691 on this laptop. If a tiled display is connected,
  `uninstall.sh` warns and prints a line you can add to `monitors.lua`.

### Moving off the temporary `monitors.lua`

1. **Now, if you agree:** change the work branch so the right tile is off and
   DP-1 stays on one listed single-stream mode. This removes the blackout risk
   until stage 1 lands.
2. **When stage 1 is installed** and the tile guard has been checked at work,
   `~/.config/hypr/monitors.lua` goes back to Omarchy's template, keeping your
   `omarchy_monitor_scale = 2`, since that is Omarchy's own Scale setting.
   The Home and Work layouts move into `setups.json`, and the
   reload-on-hotplug hook goes away; Bento's settle replaces it.

Bento never writes that file, so both are one-time edits made with your OK.

## Stages

1. **Displays and keyboards.**
   - `hypr/setups.lua`: scan, tile guard, choice, rules, settle, check and
     fallback, state file;
   - `keyboards.json` and the `keyboard.lua` change;
   - `bin/bento-setup`: `bento setup`, `pick`, `save`, and the pane's apply;
   - the Setups pane with a static arrangement, scale and primary;
   - the bar menu and notifications, and the `bento-apply` change for dots off;
   - moving Home and Work over;
   - docs and the README table.

   Tested by hand at work: plug the UltraFine in tile by tile in both orders,
   log in docked, reload docked, close the lid docked, mirror, and switch the
   laptop keyboard to Omarchy's layout at runtime.
2. **Stage 1b: drag to arrange,** with snapping.
3. **Audio.** Identities, applying by name, tracking Bento's own writes, the
   headset exception, the shell's trigger, and the pickers.
4. **Camera.** The three-line prediction, Choose in Chrome, and the camera for
   anything Bento starts.

## Open questions

1. Should the interim fix go into `monitors.lua` now (right tile off, DP-1 on
   one stream)?
2. After stage 1, should `monitors.lua` go back to Omarchy's template with
   your scale of 2?
3. Is the camera plan above right: predict and point, nothing that needs
   root?
4. Should a setup chosen by hand hold until a display or dock changes, or
   until you set it back to Automatic?
5. When you're next at work: does the UltraFine fill the whole panel today,
   or show a split picture? It doesn't change the design, but it tells us
   what the single stream looks like on that panel.

## What the review changed

The first draft had `bin/bento-setup` choose the setup and Lua replay it. A
review in three lenses (correctness, Bento's principles, UX), with each
serious point checked against Hyprland's source, changed this:

- **Tile safety no longer depends on a setup.** The draft left both UltraFine
  tiles on Omarchy's `preferred` during the settle, at login at another desk,
  with no match, and after an error: the very blackout it warned about.
- **The choice moved into Lua,** so every load decides from what is plugged
  in. That removed the files bash and Lua used to hand state back and forth,
  and the second settle timer.
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
