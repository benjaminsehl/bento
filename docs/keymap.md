# Key map

Status: **live** on the author's machine (installed from a local checkout), and
changing as it gets used. ❓ marks open questions. Results of the hands-on tests are in `spikes/results-round1.log`.

Keys are written as you press them, by their Mac name, on either keyboard.

## The idea

Swap the keys themselves, below Hyprland, so every app gets the key a Linux app
expects for the Mac shortcut:

| You press | Linux sees | So |
|---|---|---|
| ⌘ (next to Space) | **Ctrl** | ⌘C, ⌘T, ⌘F, ⌘S, ⌘P, ⌘K, ⌘1–9, ⌘-click… are real Ctrl shortcuts. Apps just work |
| ⌃ | **Super** | Omarchy, which lives on Super, ends up on ⌃: ⌃1 workspace 1, ⌃Space launcher |
| ⌥ | **Option** (third-level key, `MOD5`) | Mac special characters, ⌥ arrows |

Everything Omarchy does with Super keeps working, on ⌃. The plugin only adds
the handful of Mac keys apps don't already understand, and protects terminals.

## Hardware on this machine

| Device | Notes |
|---|---|
| Dell XPS 14 (DA14260) built-in keyboard | `at-translated-set-2-keyboard` |
| Apple Magic Keyboard with Touch ID | `apple` driver; Touch ID doesn't work on Linux |
| Dell built-in touchpad | `ven_2c2f:00-2c2f:0034-touchpad` |
| Apple Magic Trackpad | same gestures as the built-in one |
| Apple Studio Display | Omarchy's brightness keys adjust the focused display, Apple ones included |

## Physical layout (system script, opt-in)

Both keyboards end up with Mac modifiers in Mac positions:

```
[⌃] [fn] [⌥] [⌘]  ─── Space ───  [⌘] [⌥]
```

| Keyboard | Key | Becomes |
|---|---|---|
| Dell | Ctrl | ⌃ (sends Super) |
| Dell | Windows | ⌥ (sends Alt → Option) |
| Dell | Alt | ⌘ (sends Ctrl) |
| Dell | Right Alt / Right Ctrl | ⌘ / ⌥ |
| Apple | ⌃ | ⌃ (sends Super) |
| Apple | ⌥ | ⌥ (unchanged) |
| Apple | ⌘, right ⌘ | ⌘ (sends Ctrl) |
| both | Caps Lock | F13 → push-to-talk dictation |

Done with keyd, one config per keyboard, so both live in one place with one undo.
❓ check the Dell's right-hand keys (some XPS models have a Copilot key there).

## Modifier jobs

| You press | Job |
|---|---|
| ⌘ | Talk to the app (native) |
| ⌃ + number, arrow, Space, Tab, Esc | Desktops and Omarchy (Omarchy's own Super keys) |
| ⌃ + letter | Shell keys in terminals; ⌃A ⌃E ⌃K line editing everywhere |
| ⌃⌥ | Window tiling |
| ⌃⌘ | Omarchy menus, panels, toggles (Omarchy's own Super+Ctrl keys; macOS's ⌃⌘F, ⌃⌘Q, ⌃⌘Space) |
| ⌃⇧ | Omarchy: move window to workspace, app launchers (Omarchy's own) |
| ⌥ | Option characters; ⌥ arrows and ⌥⌫ edit text |

## ⌘ — apps

Native: apps get Ctrl + the same key, which is what Linux apps use. Nothing to
bind for ⌘A B C D E F G H I J K L N O P R S T U V X Y Z, ⌘⇧ + letter
(⌘⇧T, ⌘⇧P, ⌘⇧F, ⌘⇧N…), ⌘1–9, ⌘, ⌘/ ⌘− ⌘= ⌘0, ⌘-click.

Where Linux apps read Ctrl differently, the plugin translates:

| Keys | Does | Linux would | Plugin sends |
|---|---|---|---|
| ⌘↑ / ⌘↓ | Start / end of the text field or document | scroll a line | Ctrl+Home / Ctrl+End |
| ⌘← / ⌘→ | Start / end of the line | jump a word | Home / End |
| ⇧ + the above | Select to there | — | same + Shift |
| ⌘⌫ | Delete to line start | delete a word | Shift+Home, Backspace |
| ⌘Z / ⌘⇧Z | Undo / redo | undo / redo in most apps | native; Ctrl+Y where an app needs it ❓ |
| ⌘[ / ⌘] | Back / forward | — (apps vary) | Alt+← / Alt+→ |
| ⌘⇧[ / ⌘⇧] | Previous / next tab | — | Ctrl+Shift+Tab / Ctrl+Tab |
| ⌘W | Close tab; the window once no tab is left (omac's logic) | close tab; nothing in some apps | Ctrl+W, then closes the window if nothing closed |
| ⌘Q | **Quit**: close every window of the app | quit, in some apps | — (Hyprland closes them; apps still ask to save) |
| ⌘M | Minimize the window | — | — (Hyprland: hidden "minimized" workspace) |
| ⌘Tab / ⌘⇧Tab | Next / previous window, raised | next / previous tab | — (Hyprland cycles windows) |
| ⌘\` | Next window of the same app | — | — (Hyprland) |
| ⌘Space | App launcher (Spotlight) | — | — (Omarchy's apps menu) |
| ⌘↩ | Terminal (Ghostty) | Ctrl+Return in apps (send, insert line) | — (shadows Ctrl+Return; your call) |
| ⌘⇧↩ | Browser | — | — |
| ⌘⇧3 / ⌘⇧4 | Screenshot of screen / area or window | — | — (Omarchy capture) |
| ⌃⌘⇧3 / ⌃⌘⇧4 | Same, to clipboard only | — | — |
| ⌘⇧5 | Capture menu: screenshot, recording, OCR, colour | — | — |
| ⌥⌘Esc | Force quit the window | — | — (Hyprland kill) |

As on a Mac, a capture also shows a thumbnail you can click to mark it up.

## ⌃ — desktops and Omarchy

Omarchy's Super bindings, unchanged, now on ⌃:

| Keys | Does |
|---|---|
| ⌃1–9 | Workspace N (macOS: Switch to Desktop N) |
| ⌃⇧ arrows | Swap window in that direction |
| ⌃⇧1–9 | Move window to workspace N |
| ⌃⇧⌥1–9 | Move window to workspace N, stay here |
| ⌃Space | Omarchy menu |
| ⌃Esc | System menu (lock, suspend, restart…) |
| ⌃↩ / ⌃⇧↩ | Terminal / browser (Omarchy's; ⌘↩ ⌘⇧↩ do the same) |
| ⌃, family | Notifications: dismiss, dismiss all, open last, history |
| ⌃/ , ⌃⌫ family, ⌃− ⌃=, ⌃Home | Scaling, transparency/gaps, resize, window width |
| ⌃-drag / ⌃-right-drag | Move / resize window |
| ⌃-scroll | Scroll through workspaces |
| ⌃⇧ + letter | Omarchy's app launchers: ⌃⇧X X, ⌃⇧M Spotify, ⌃⇧/ 1Password, and the rest; harmless to keep |

Changed, to match macOS:

| Keys | Does | Omarchy had |
|---|---|---|
| ⌃← / ⌃→ | Previous / next workspace (macOS Spaces) | focus window → ⌃⌥← → |
| ⌃↑ | Overview (Mission Control) once the overview plugin lands; scratchpad until then | focus window up → ⌃⌥↑ |
| ⌃↓ | Show / hide minimized windows (App Exposé) | focus window down → ⌃⌥↓ |
| ⌃Tab / ⌃⇧Tab | Next / previous tab in the app | next / previous workspace (⌃→ ⌃← now) |

### ⌃ + letter

macOS uses plain ⌃ + letter for shell and line-editing keys, so that's what it
does here; Omarchy's ⌃ + letter window actions move to ⌃⌥ (next section).

| Where | ⌃ + letter |
|---|---|
| Ghostty | Real control characters: ⌃C interrupt, ⌃D end of input, ⌃R history search, ⌃L clear, ⌃A/⌃E line start/end, ⌃W/⌃U delete, ⌃Z suspend… |
| Other apps | ⌃A / ⌃E start / end of line, ⌃K delete to end of line (the common macOS text keys). Others do nothing |

Omarchy keys this frees or moves:

| Was | Now |
|---|---|
| ⌃C ⌃V ⌃X universal copy / paste / cut | ⌘C ⌘V ⌘X (native) |
| ⌃W close window | ⌘W |
| ⌃K keybindings menu | ⌃⌘K |
| ⌃F ⌃T ⌃O ⌃L ⌃S | ⌃⌥F ⌃⌥T ⌃⌥O ⌃⌥L ⌃⌥S |
| ⌃J ⌃P ⌃G split, pseudo-tile, groups | dropped (not used) |

## ⌃⌥ — windows

| Keys | Does | Omarchy had |
|---|---|---|
| ⌃⌥ arrows | Focus window in that direction | ⌃ arrows |
| ⌃⌥F | Full screen | ⌃F |
| ⌃⌥↩ | Full width / maximize (Rectangle's key) | ⌃⌥F (Omarchy's tmux key ⌃⌥↩ is dropped) |
| ⌃⌥T | Float / tile | ⌃T |
| ⌃⌥O | Pop out (float and pin on top) | ⌃O |
| ⌃⌥L | Workspace layout | ⌃L |
| ⌃⌥S | Show / hide scratchpad | ⌃S |
| ⌃⌥⇧S | Send window to scratchpad | ⌃⌥S |

The **scratchpad** is a hidden workspace that slides over the current one;
the same key hides it again.

## ⌃⌘ — Omarchy utilities

Omarchy's Super+Ctrl keys, unchanged: ⌃⌘A/B/W/D/P audio, bluetooth, network,
display, power panels; ⌃⌘C capture; ⌃⌘V clipboard history; ⌃⌘X dictation
toggle; ⌃⌘N nightlight; ⌃⌘I idle lock; ⌃⌘R reminders; ⌃⌘T activity; ⌃⌘Z zoom;
⌃⌘S share; ⌃⌘O toggles; ⌃⌘H hardware; ⌃⌘L lock.

These match macOS already, or change to:

| Keys | Does | Omarchy had |
|---|---|---|
| ⌃⌘F | Full screen (macOS key) | tiled full screen → ⌃⌥⌘F |
| ⌃⌘Q | Lock screen (macOS key) | calculator → no key (⌘Space "calc") |
| ⌃⌘Space | Emoji picker (macOS key) | wallpaper picker → no key (Omarchy menu → Style) |
| ⌃⌘K | Keybindings menu, in Mac symbols | Herdr keybindings → dropped |

## Text editing with ⌥

| Keys | Does | Plugin sends |
|---|---|---|
| ⌥← / ⌥→ | Previous / next word | Ctrl+← / Ctrl+→ (Ghostty: word jump) |
| ⌥⇧← / ⌥⇧→ | Select by word | + Shift |
| ⌥↑ / ⌥↓ | Move line up / down in VS Code | Alt+↑ / Alt+↓ |
| ⌥⌫ | Delete previous word | Ctrl+Backspace (Ghostty: ⌃W) |
| fn⌫ | Delete forward | (Apple keyboard does this already) |

## Option characters

Layout **English (Macintosh, ABC)** (`us` variant `mac`, ships with Linux), with
both ⌥ keys as Option. Standard US Mac: "…" is ⌥;.

| Keys | Types | Keys | Types |
|---|---|---|---|
| ⌥; | … | ⌥− / ⌥⇧− | – / — |
| ⌥[ / ⌥⇧[ | “ / ” | ⌥] / ⌥⇧] | ‘ / ’ |
| ⌥2 | ™ | ⌥G / ⌥R | © / ® |
| ⌥8 / ⌥⇧8 | • / ° | ⌥= / ⌥⇧= | ≠ / ± |
| ⌥, / ⌥. | ≤ / ≥ | ⌥/ | ÷ |
| ⌥5 | ∞ | ⌥⇧2 | € |
| ⌥3 / ⌥4 | £ / ¢ | ⌥6 / ⌥7 | § / ¶ |
| ⌥P / ⌥W | π / ∑ | ⌥X / ⌥V | ≈ / √ |

Accent keys come too (⌥E ´, ⌥U ¨, ⌥I ˆ, ⌥N ˜, ⌥\` \`, then the letter).

Underneath: Option is the "third level" key (`MOD5`), so apps see characters,
not Alt, as on a Mac. Omarchy binds ~90 keys with Alt (⌃⌥ window keys, ⌃⇧⌥
silent moves, ⌥Tab, ⌥ volume steps…). The plugin mirrors every Omarchy Alt
binding onto Option automatically, by re-reading Omarchy's binding files with
Alt replaced by `MOD5`, so Omarchy updates carry over.

In Ghostty ⌥ types characters too (no ⌥-as-Meta; not used).

## Ghostty

The default terminal (`omarchy install terminal ghostty`). It gets a config
file from the plugin, so it behaves like Ghostty on macOS:

| Keys | Does |
|---|---|
| ⌘C / ⌘V | Copy / paste (images too, for Claude Code) |
| ⌘T / ⌘W / ⌘N | New tab / close / new window |
| ⌘1–9, ⌘⇧[ ⌘⇧] | Go to tab N, previous / next tab |
| ⌘D / ⌘⇧D | Split right / down |
| ⌘K | Clear the screen |
| ⌘F | Find |
| ⌘+ ⌘− ⌘0 | Font size |
| ⌘← ⌘→ / ⌥← ⌥→ | Line start / end, word left / right |
| ⌃ + letter | Control characters (see ⌃ + letter) |

Hyprland passes ⌃ + letter straight to Ghostty rather than running an Omarchy
shortcut. foot and other terminals aren't supported.

❓ Later: VS Code's built-in terminal needs the same idea in its
`keybindings.json` (⌃C there would otherwise reach Omarchy, not the shell).

## Function keys

| Keyboard | Top row without fn | With fn | How |
|---|---|---|---|
| Apple Magic Keyboard | **Mac**: brightness, Mission Control, Spotlight, dictation, Do Not Disturb, media, volume | F1–F12 | `hid_apple fnmode=1` in the system script (Omarchy's installer set 2, F-keys first) |
| Dell XPS built-in | F1–F12 | media | Firmware Fn Lock; already right, nothing to change |

Magic Keyboard top row (codes from the test):

| Key | Sends | Does |
|---|---|---|
| F1 / F2 | brightness | Brightness of the focused display |
| F3 | `KEY_SCALE` (XF86LaunchA) | Overview once the plugin lands; scratchpad until then |
| F4 | `KEY_SEARCH` (XF86Search) | App launcher |
| F5 | `KEY_MICMUTE` (XF86AudioMicMute) | Dictation toggle, on the Magic Keyboard only (the Dell's mic key stays mic mute) |
| F6 | `KEY_SLEEP` (XF86Sleep) | Do Not Disturb. Tested: it doesn't suspend the machine |
| F7–F12 | media, volume | as labelled |

F9 stops being Omarchy's push-to-talk (Caps Lock takes over), so VS Code's
breakpoint key is free.

## Trackpad gestures

Both trackpads. Finger counts as on a Mac set to four-finger Spaces.

| Gesture | Does | Mac |
|---|---|---|
| Two fingers | Scroll, natural direction | same |
| Click with two / three fingers | Right-click / middle-click | same / — |
| Tap | Nothing: press to click | tap to click off |
| Pinch two fingers | Zoom in the app | same |
| Three fingers up | Show / hide the scratchpad, following your fingers | — |
| Three or four fingers sideways | Switch workspace, following your fingers | Swipe between Spaces |
| Four fingers up | Overview (overview plugin phase; scratchpad until then) | Mission Control |
| Four fingers down | Show / hide minimized windows | App Exposé |
| Pinch thumb + three fingers | App launcher; when the desktop is showing, bring the windows back | Launchpad |
| Spread thumb + three fingers | Show desktop (empty workspace); again to come back | Show Desktop |

Tested: Hyprland's `pinchin`/`pinchout` names are the other way round from the
gesture (spread fires `pinchin`), so the bindings swap them. Five-finger
gestures aren't reported by these trackpads.

Not possible: Force Touch, look-up, Notification Centre edge swipe, two-finger
back/forward in Chrome ❓ (Chrome may support it with a flag; not tested yet).

## System script (opt-in, sudo)

Separate from the plugin. Shows what it will change first, and has an undo.

1. keyd: modifier swap per keyboard, Caps Lock → F13 (see Physical layout).
2. `hid_apple fnmode=1`.

## Dropped

Omarchy actions left without a key on purpose (the checker's allowlist):

- Pseudo-tile, split toggle, all window-group bindings.
- Herdr keybindings.
- Calculator and wallpaper-picker keys (still in menus).
- F9 push-to-talk (Caps Lock now).
- Universal copy/paste/cut on ⌃C ⌃V ⌃X (⌘ does it natively).

Any other Omarchy action losing its key is a checker failure.

## Spikes left

1. **Option layout**: `us(mac)` with both Alts as Option; `MOD5` bindings fire;
   characters type in Chrome, VS Code, Ghostty; Alt sent by Hyprland (⌥↑ in
   VS Code) still reads as Alt.
2. **Mirroring Omarchy's Alt bindings** onto `MOD5` by re-reading its files.
3. **Ghostty**: `super+letter` → control characters and `ctrl+…` → Mac actions,
   including inside Claude Code and tmux.

## Later

- **Overview (Mission Control)**: a Hyprland overview plugin on four fingers up,
  ⌃↑ and the Magic Keyboard's F3. Its own phase after the key map works.
- VS Code integrated terminal keys.
