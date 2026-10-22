# Keyboards

Each keyboard gets a **style**. A Mac keyboard gets Mac shortcuts. The Dell's
built-in keyboard gets the keys printed on it: Omarchy's shortcuts, plus
Bento's extras on PC keys. Every shortcut lives in one catalogue that people
and agents can change, from the Bento app, a JSON file or `bento keys`.

The plan was approved on 2026-10-20 and isn't built yet. Stage 1 starts with
the spikes in [Spikes first](#spikes-first). It extends
[Setups](setups.md) stage 1, which shipped in 6ffbbec, and replaces that
stage's keyboard `keymap` (see [Replacing `keymap`](#replacing-keymap)).

## The problem

Setups stage 1 gives each keyboard a keymap: `apple`, `pc` or `omarchy`. It
comes from `keyboards.json` (the repo's, then yours), and a setup can override
it. In the repo, the laptop gets `pc`, which puts ⌘ on Alt, ⌃ on Ctrl and ⌥ on
the Windows key. That's Mac muscle memory on keys printed for Windows, and it
doesn't feel right on that keyboard.

Choosing `omarchy` for the laptop doesn't help either, and one of your saved setups does
that. The reason is that **every binding Bento adds or removes still
applies to every keyboard**. With Omarchy's layout the Dell's Ctrl+← still
jumps to the line start, Ctrl+W still runs ⌘W's logic, and Super+W, Super+F
and the others are still unbound.

## What we found

Checked read-only on this machine, against Hyprland 0.56.2.

- **Bindings can be limited to some keyboards.** `HL.BindOptions` has
  `device = { inclusive, list }`, and `KeybindManager` keeps the list as a set
  of device names. Bento already relies on it: the Magic Keyboard's F1–F12
  and its mic key are bound with `device = lib.magic_keyboard`, so other
  keyboards still send plain F-keys and mic mute (`keyboard.lua`).
- **Device names are already solved.** Setups stage 1 matches each keyboard
  in `keyboards.json` by name and by vendor:product, using
  `/proc/bus/input/devices`, and lists every Hyprland device name it goes by
  in `lib.keyboards.list`. The Magic Keyboard's list covers Bluetooth too.
  Those lists are exactly what a `device` filter needs.
- **Mac and Mac-on-PC keyboards look the same to Hyprland.** Both keymaps make
  ⌘ = CTRL, ⌃ = SUPER and ⌥ = MOD5. So the keymaps differ, but the two styles
  share one set of bindings. There are only two sets: *Mac* and *PC*.
- **One keyboard shows up as several devices.** The K3 Pro has
  `keychron-keychron-k3-pro` and `-keyboard`, plus `-system-control` and
  `-consumer-control`. The Keychron M1 **mouse** has a `-keyboard` device too.
  So Bento can't treat whatever isn't listed as Mac. Anything not known to be
  Mac gets the PC set (`inclusive = false`, list = the Mac devices). An
  unknown keyboard then behaves like stock Omarchy, which is the safe default.
- **`hl.unbind(keys)` takes only the keys.** It has no device argument, so
  removing an Omarchy binding removes it for every keyboard. To keep it on PC
  keyboards, Bento has to bind it again, limited to them. Bento already
  re-reads Omarchy's binding files with `hl.bind` wrapped, to mirror Alt onto
  Option, so the same pass can record every Omarchy binding.
- **Hyprland can't limit a binding to an app.** Bindings are per keyboard,
  never per window. `window.active` fires on focus changes, though, so Bento
  can add bindings while a terminal is focused and remove them afterwards
  (see [Ghostty](#ghostty)).
- **`hl.define_submap` exists.** An empty submap lets the Bento app record a
  shortcut without Hyprland running it first.

## Styles

| Style | Keymap | Bindings | For |
|---|---|---|---|
| **Mac** | `apple` (today's) | Mac set | Apple keyboards and Mac-mode Keychrons |
| **Mac on PC keys** | `pc` (today's) | Mac set | Anyone who wants Mac habits on a PC keyboard |
| **PC** | none: Omarchy's layout | PC set | Everything else, the Dell included |

The repo's `keyboards.json` decides the built-in keyboards:

- The Magic Keyboard (USB and Bluetooth ids) is Mac.
- The K3 Pro is Mac, because it's kept in Mac mode (976219a). It can switch to
  Windows mode in hardware, which Bento can't see, so a setup can make it PC.
- **The laptop changes from `pc` to PC style.** That's the fix for the Dell.
  Mac on PC keys is still one click away.

Any keyboard not listed is PC, as it gets Omarchy's layout today.

### Replacing `keymap`

The style replaces the `keymap` that Setups shipped. Each old value has a
style that keeps today's keymap:

| `keymap` (Setups stage 1) | Style | Keymap, unchanged |
|---|---|---|
| `apple` | `mac` | `apple` |
| `pc` | `mac-on-pc` | `pc` |
| `omarchy` | `pc` | none: Omarchy's |

The only thing that changes is the bindings, and only for keyboards that end
up PC. An `omarchy` keyboard used to get Bento's global Mac bindings on
Omarchy's layout, which was the broken case.

Where the field lives:

- **`keyboards.json`**, the repo's and yours, gets a `style` field. The repo's
  file moves to `style`. In yours, `keymap` is still read when there's no
  `style`, mapped as in the table above. The Keyboard pane writes `style`, and
  drops `keymap` from that entry when it saves.
- **`setups.json`**: a setup's `keyboards` map takes `mac`, `mac-on-pc` or
  `pc`. It still accepts `apple`, `pc` and `omarchy`, and `pc` is the one
  value whose meaning changes, so the file says which vocabulary it's using:
  - The first time Bento saves `setups.json` after this change (from the pane
    or `bento setup`), it rewrites every `keyboards` value into styles. It
    adds `"keyboardValues": "style"` at the top level, and keeps the old file
    as `setups.json.prev`, the same way every save does.
  - Until then, without that marker, every value is read the old way, so
    `pc` means Mac on PC keys. With the marker, `pc` means PC style.
  - Nothing rewrites the file at load, so a broken migration can't cost you a
    setup.

  Your saved setup has `"laptop": "omarchy"`, which becomes `pc`: exactly what
  you want at that desk.
- `lib.keyboards.override(id, style)` and `state.keyboards` in `setup.json`
  carry the style. `prefs/SetupsData.js` (`keymaps`, `keymapNames`) and
  `bento-setup` follow.

Because a setup can change a keyboard's style, it changes that keyboard's
bindings too. Setups changes are applied with a reload, and `setups.lua`
gives keyboards their keymaps during the load. So the bindings come from
`hypr/keys.lua`, which runs after `setups.lua` and builds them once, for the
final styles.

### What PC style keeps and adds

PC style starts from stock Omarchy and changes as little as possible. Super
runs the desktop, Ctrl talks to the app, and Alt does what it always does.
Bento adds only the features Omarchy doesn't have:

| Bento feature | Mac style | PC style |
|---|---|---|
| Previous / next page | ⌃← ⌃→ | Super+← Super+→. Omarchy's focus-window keys move to Super+Alt+arrows, as on Mac, which drops Omarchy's move-into-group keys there. Mac style already drops groups ❓ |
| Overview | ⌃↑ | Super+↑ |
| Minimized-windows drawer | ⌃↓ | Super+↓ |
| Minimize | ⌘M | Super+M |
| Nth page dot | ⌃1 … ⌃0 | Super+1 … Super+0 |
| Bento app | ⌃⌘, | Super+Ctrl+, |
| Close tab, then window | ⌘W | Ctrl+W, **off by default** (Super+W already closes the window) |
| Text editing, ⌘Q, ⌘Tab, ⌘Space, ⌘⇧3/4/5 | on | not bound: Linux apps already handle Ctrl+arrows, Home and End, and Omarchy has its own keys |

Page keys, Overview and the drawer follow the **Pages** and **Windows**
switches, as today. They aren't part of a style.

### What belongs to the keyboard, not the style

Some bindings are about one model's hardware, and keep their own device list
whatever the style:

- **The Magic Keyboard's top row** (2cb4a76): plain F1–F12 do what's printed
  on the keys. That covers brightness, Overview on F3, Omarchy's menu,
  microphone mute, Do Not Disturb, Spotify on F7–F9, and volume. The fn codes
  (XF86LaunchA, XF86Search, the mic key) stay as they are. In the catalogue
  these become entries with `keyboard = "apple-magic-keyboard"` instead of a
  style, still behind the *Top row* switch.
- **Caps Lock as F13** comes from Bento's keymaps, so it's push-to-talk only on
  Mac and Mac-on-PC keyboards. A PC keyboard keeps Caps Lock, and Omarchy's F9
  push-to-talk comes back for PC keyboards only. Bento unbinds F9 for every
  keyboard today.

The *Bento modifier layout* switch (`macModifiers`) stays. Off, it makes every
keyboard PC, whatever its style.

## The catalogue

Every shortcut Bento binds becomes data. `keys/catalogue.lua` is in the repo,
so Hyprland can load it with no JSON parser:

```lua
{ id = "pages.next", group = "pages", title = "Next page",
  mac = "ctrl+right", pc = "super+right",          -- as you press them
  run = lib.pages.next },
{ id = "app.close-tab", group = "apps", title = "Close tab, then the window",
  mac = "cmd+w", pc = false,                        -- false: off in that style
  run = close_tab },
{ id = "text.word-left", group = "text", title = "Word left",
  mac = "opt+left", pc = false,
  run = send({ "CTRL", "LEFT" }, { "ALT", "LEFT" }) },
```

- **Keys are written as printed on the keyboard**, never as the swapped names
  Linux sees. Mac style takes `cmd ctrl opt shift`, or ⌘ ⌃ ⌥ ⇧. PC style takes
  `ctrl super alt shift`. Bento translates when it binds: in Mac style, `cmd`
  becomes CTRL, `ctrl` becomes SUPER, and `opt` becomes MOD5.
- `run` stays Lua. Binding a different key is configuration, but a different
  action is code.
- `bin/mac-keybindings` and the docs tables can be generated from the
  catalogue, so they stop drifting from the code.

### Your changes

These go in `~/.config/bento/keys.json`. It holds only what differs from the
catalogue, the same rule as `settings.json`:

```json
{
  "mac": { "pages.next": "ctrl+opt+right", "app.quit": null },
  "pc":  { "app.close-tab": "ctrl+w", "pages.overview": ["super+up", "f3"] }
}
```

- Each entry takes a string, a list of strings (several shortcuts), or `null`
  (off).
- A setup can carry its own `keys` block in the same shape. It's applied last,
  while that setup is active.
- An unknown id or a key that can't be parsed is skipped with a notification,
  and the rest still applies.

### `bento keys`

For agents and terminals. `bento keys` edits the same file the pane does.

```
bento keys list [--style pc] [--json]   every shortcut, with changes marked
bento keys set pages.next "super+alt+right" --style pc
bento keys off app.quit --style mac
bento keys reset [id]
bento keys check                        conflicts, between Bento and Omarchy too
bento keys which "super+right"          what a key does, on each style
```

`check` reports each shortcut with more than one action, in each style. That
includes Omarchy's own bindings and the ones in your `~/.config/hypr`. Bento
runs `check` after every change.

## The Keyboard pane

**Keyboards** comes first. It's the group Setups shipped
(`prefs/Keyboards.qml`, with *Its own · Apple · PC · Omarchy*), redrawn. Each
known keyboard gets a row:

- the keyboard's name, and whether it's connected, or the desk where Bento
  last saw it;
- a drawing of its bottom row of modifier keys, showing what each key does
  in its style;
- a picker: Mac · Mac on PC keys · PC.

When a setup overrides a keyboard's style, the row says "PC at Work", and
changing it asks "Everywhere" or "Only at Work".

**Shortcuts** follows: one list, grouped Apps, Text, Windows, Pages, Capture,
System.

- A toggle at the top shows the list for the **Mac** or **PC** style. It
  starts on the style of the keyboard you last typed on.
- Each group has a switch, which replaces today's switches (*Text editing
  everywhere*, *App shortcuts*, and the rest).
- Each row shows the action and its shortcut. A changed shortcut gets a dot,
  and right-clicking a row resets it.
- **Click a shortcut to record a new one.** Bento switches Hyprland to an empty
  `bento-record` submap so that keys reach the window. You press the new
  shortcut, Esc cancels, and ⌫ turns the shortcut off. Any key ends recording,
  the window losing focus ends it, and so does a 10-second timeout, so you
  can't get stuck in the submap.
- **A conflict shows on the row** before anything is saved: "Super+W also
  closes the window (Omarchy). Use it here anyway?"
- **Search** matches action names. Pressing keys in the search box finds what
  they do.
- At the bottom: Reset all, Open keys.json, and a hint about `bento keys`.

### Recording on the right keyboard

The shortcut you press arrives after its keyboard's keymap. If you record a
Mac shortcut on the Dell, ⌘ isn't where the pane expects. So the recorder reads
the keys in the style of the keyboard you pressed them on, using its `main`
flag in `hyprctl devices`. It writes the shortcut as that style's printed keys,
and it saves into the style the list is showing. If the two styles differ, it
says so: "Recorded on the Dell (PC). Saved for Mac as ⌃⌥→".

## Ghostty

> **Off for now (22 October 2026).** The first version switched its bindings
> on and off on every change of focus, and that crashed Hyprland (see
> [docs/safety.md](safety.md)). PC keyboards get Ghostty's Mac keys until it's
> rebuilt with each binding checking for a terminal itself.

Ghostty's config applies to the whole app and can't tell keyboards apart.
Today it assumes the Mac keyboard: Ctrl+C copies, because that's ⌘C, and
Super+C sends ^C, because that's ⌃C.

On PC keyboards it should behave the Linux way: **Ctrl+C interrupts and
Ctrl+Shift+C copies.** Ghostty can't tell which keyboard a key came from, so
Hyprland translates for PC keyboards, and only while a terminal has focus:

| PC keyboard, in Ghostty | Hyprland sends | Ghostty does (bento.conf) |
|---|---|---|
| Ctrl + letter | Super + letter | the control character |
| Ctrl+Shift+C / V | Ctrl+C / Ctrl+V | copy / paste |
| Ctrl+Shift+T / W / N | Ctrl+T / W / N | new tab / close / new window |

- `window.active` adds these bindings when a terminal gains focus and removes
  them when it loses it, so no other app gets the extra hop.
- They're `repeating`, so holding Ctrl+W keeps deleting.
- Mac keyboards aren't in their device list, so ⌘C still copies.
- If the spike shows the hop is noticeable, the fallback is Ghostty's
  `performable:ctrl+c=copy_to_clipboard`: copy when text is selected, and
  interrupt otherwise, on both keyboards.

## Clean removal

Nothing new lives outside Bento's existing footprint (see the clean-removal
rules in [Setups](setups.md)):

- Bindings live in Hyprland and go away with the config reload that follows
  disable.
- `keys.json` sits next to `settings.json` in `~/.config/bento`, and is removed
  with it.
- The `bento-record` submap has no bindings, and a reload clears it.

Disabling Bento gives every keyboard stock Omarchy, as today.

## Spikes first

Each spike needs a live Hyprland, with a reload to undo it:

1. **Bindings limited to keyboards.** Half of this is already proven: the Magic
   Keyboard's F-keys fire only on that keyboard, while F-keys from the others
   still reach apps. What's left: bind the same key twice, `inclusive` for the
   K3 Pro and `inclusive = false` for the rest. Check that each keyboard fires
   only its own binding, and whether `hl.unbind` removes both.
   *2026-10-20:* both bindings coexist, and one `hl.unbind` removes both, as
   expected. `hyprctl binds -j` doesn't show device lists, so which keyboard
   fires which binding still needs hands on the keys.
2. **Re-adding Omarchy's bindings** from the recorded pass, limited to PC
   keyboards. Check that `~/.config/hypr/bindings.lua` still wins where you
   changed an Omarchy key there. Bento must only bring back a binding that was
   there when it unbound it.
   *2026-10-20:* Lua has no way to list bindings. So Bento reads the files in
   `~/.config/hypr` as text, without running them, and leaves alone every key
   they bind or unbind. Your `bindings.lua` binds only `code:66` (Caps Lock,
   Tonband).
3. **Bindings added on focus**, on `window.active`: Ctrl+C in Ghostty from the
   Dell. Measure the delay, and check that holding Ctrl+W repeats.
   *2026-10-20:* `hl.bind` returns a binding with `set_enabled`, so the
   bindings are made once and switched on and off with focus. If one fires
   outside a terminal anyway, it sends its key on unchanged.
4. **Recording submap**: a FloatingWindow gets Super+→ and Ctrl+Alt+Esc while
   `bento-record` is active.
5. **`main` in `hyprctl devices`** follows the keyboard last typed on. The
   Keychron mouse's keyboard device is the `main` one right now, which suggests
   it doesn't, so the recorder may have to ask instead.

## Stages

1. **Styles.** This stage fixes the everyday problem. It covers:
   - the style per keyboard, replacing `keymap` in `keyboards.json`,
     `setups.json`, `lib.keyboards`, `bento-setup` and the panes, with the
     migration;
   - the Mac and PC binding sets, with Omarchy's bindings kept on PC keyboards;
   - Caps Lock and F9 by style;
   - Ghostty's Linux keys on PC keyboards, brought forward from stage 4:
     without them a PC-style laptop would lose ⌃C in the terminal.

   The Dell becomes Omarchy plus Bento's extras. **Built**: the bindings are
   in `hypr/keys.lua`, after `setups.lua`. `bento-setup` and the app write
   styles, and `"keyboardValues": "style"`, on their first save.
2. **The catalogue and keys.json.** Move every binding into the catalogue,
   and add your changes, `bento keys`, and generating `mac-keybindings` and
   the docs tables.
3. **The Shortcuts list.** Recording, conflicts, search and group switches.
4. **Ghostty on PC keyboards.** Done in stage 1; what's left is the spike 3
   results (repeat and latency on the Dell).
5. **Per-setup keys:** a setup's `keys` block, edited in the Setups pane.

## Open questions

- Should the Dell's Copilot key, if it has one, do something in PC style?
- In PC style, should Super+Space open the app launcher, as ⌘Space does on
  Mac, or stay Omarchy's menu?
