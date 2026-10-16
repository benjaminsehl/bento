<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/icon-dark.svg">
    <img src="docs/images/icon-light.svg" width="72" height="72" alt="Bento">
  </picture>
</p>

<h1 align="center">Bento</h1>

<p align="center">
  <strong>Omarchy, thoughtfully arranged.</strong><br>
  An opinionated window manager experience for Omarchy: pages, Exposé, a drawer
  for minimized windows, gestures that follow your fingers, and keys your hands
  already know.
</p>

<p align="center">
  <a href="https://github.com/tcballard/omarchy-badges"><img src="https://raw.githubusercontent.com/tcballard/omarchy-badges/85f859029e236e784e7b05ada6dbe73506d07a91/badges/v1/built-for-omarchy.svg" alt="Built for Omarchy"></a>
</p>

<p align="center">
  <a href="#whats-in-the-box">What's in the box</a> ·
  <a href="#principles">Principles</a> ·
  <a href="#where-its-going">Where it's going</a> ·
  <a href="#install">Install</a> ·
  <a href="#docs">Docs</a>
</p>

Omarchy is a great base: fast, keyboard-first and beautifully put together.
Bento is one opinionated take on how working in it should *feel*. Each window
has its place, you move between places by gesture, nothing you put away gets
lost, and the system answers your hands without a delay you can notice.

Bento started as Mac keybindings for Omarchy (it was called **omac**). The keys
are still here, but the project is bigger now: it is about the whole
interaction model, meaning how windows, workspaces, gestures and the bar fit
together, with the best of macOS and iPadOS as reference points rather than as
the goal.

![Pages in the Omarchy bar](docs/images/pages.png)

## What's in the box

Every piece can be switched off or tuned in the Bento app: run `bento`, press
⌃⌘, or find **Bento** in the app launcher.

- **Pages.** Workspaces become an ordered row of pages, shown as dots in the
  bar. Hover a dot for a live preview and slide along the dots to flip through
  them. ⌃2 is always the second dot, whatever the workspace id is. Empty pages
  disappear, and you can swipe past either end for a new one. When a page's
  last window closes, the next page slides in.
- **Exposé.** Pinch with thumb and three fingers, or press ⌃↑ or Mission
  Control, to zoom out to every page as a true miniature of your monitor, along
  with the scratchpad and your minimized windows. Click or arrow to anything.
  Spread your fingers to show the desktop.
- **The drawer.** ⌘M minimizes. Swipe down, or press ⌃↓, and minimized windows
  drop in as live cards, like the iPad app switcher. Click one to bring it back,
  or flick it up to close it.
- **Gestures.** Three- or four-finger swipes move between pages and follow your
  fingers: a flick switches, a slow drag peeks. Swipe up for the scratchpad and
  down for the drawer. Scrolling is natural.
- **Keys.** ⌘ sends Ctrl at the keyboard layout, so every app gets its native
  shortcuts and Omarchy lives on ⌃. You also get Mac text editing, a ⌘W that
  closes the tab before the window, ⌘Q, ⌘Tab, Option characters and the Magic
  Keyboard's top row. The full map, with the reasoning, is in
  [`docs/keymap.md`](docs/keymap.md).
- **Ghostty.** Ghostty behaves the way it does on macOS: ⌘C/⌘V (images
  included), tabs, splits, and ⌃ + letter as real control characters.
- **The Bento app.** One window with a pane per area and a row per setting.
  Changes apply as soon as you make them. If Hyprland rejects a change, Bento
  puts the previous settings back, so a bad setting can't leave you with a
  broken desktop.

![Hovering a dot previews the page](docs/images/pages-hover.png)

## Principles

These decide what goes into Bento and what stays out.

1. **Direct manipulation.** If your fingers start it, the screen follows them.
   Animations finish what your hand began, and they are short and
   interruptible.
2. **Places, not numbers.** You think in "the page to the right", not in
   workspace 1004. Positions are stable and ids stay out of sight.
3. **Nothing gets lost.** Minimized, scratchpad, off-screen: everything shows
   up in Exposé, and everything is one gesture away.
4. **Native first.** Apps get the keys they expect. Bento translates only where
   Linux and Mac habits disagree, and it protects terminals.
5. **Opinionated, not locked in.** Strong defaults, each with a switch.
   Removing Bento gives you back stock Omarchy.
6. **Never break the desktop.** Every change is validated and rolled back if
   Hyprland complains. A failing module doesn't take the others down with it.
7. **Readable.** Everything lives in a few Lua and QML files you can search.
   Behaviour lives in Hyprland, and interface in the Omarchy shell.

## Where it's going

Bento's aim is a desktop that feels designed as a whole, from the first
keypress to the last pixel of an animation. These are directions, not promises:

- **Gestures that track all the way.** Exposé and the drawer should follow your
  fingers continuously, the way page swipes already do, instead of opening once
  the gesture ends. This probably needs a small Hyprland plugin.
- **Window arrangement as a first-class idea.** Snap, split and resize with
  gestures and keys that make sense together. Bento layouts would remember
  where things go.
- **A real app switcher.** ⌘Tab with app icons, live previews and per-app
  window cycling.
- **Exposé as a workbench.** Drag windows between pages, reorder pages, and
  drag a window into the drawer to minimize it.
- **Motion with one feel.** Shared timing and easing across pages, Exposé, the
  drawer and the bar, so everything moves as one system.
- **Fewer rough edges in apps.** VS Code's integrated terminal keys, browser
  back and forward on two fingers, and anything else that breaks the illusion.

Ideas and rough edges are welcome as issues.

## Install

Bento needs Omarchy 4 or newer (the release that configures Hyprland in Lua).

```bash
omarchy plugin add https://github.com/benjaminsehl/bento --enable
```

The plugin runs [`install.sh`](install.sh) each time the shell starts. The
first run hooks Bento into Hyprland, and later runs find everything in place
and do nothing. If something stops it, a desktop notification says why.

`install.sh` also works from any checkout of this repo and points everything at
that checkout, so to update you edit the files and run `hyprctl reload`.
Re-run `install.sh` after changing `xkb/`.

The Magic Keyboard's Mac top row (media keys without fn) is a separate,
root-level change: `sudo system/apple-fnmode.sh`.

### Coming from omac

Bento is omac renamed. `install.sh` removes omac's hooks, links and launcher
entry, moves `~/.config/omac` to `~/.config/bento`, and moves the page dots in
the bar to the new plugin id. Afterwards, disable the old plugin:

```bash
omarchy plugin disable io.github.benjaminsehl.omac
```

<details>
<summary>What the installer touches</summary>

| Path | What it is |
|---|---|
| `~/.local/state/omarchy/toggles/hypr/bento.lua` | One line that loads `hypr/bento.lua` from the checkout |
| `~/.local/state/bento/` | Compiled keymaps, and errors from the last reload |
| `~/.local/bin/bento`, `bento-apply`, `mac-keybindings` | Links into `bin/` |
| `~/.local/share/applications/bento.desktop` | The Bento app, in the launcher |
| `~/.config/bento/settings.json` | Your settings: only what differs from [`defaults.json`](defaults.json) |
| `~/.config/omarchy/shell.json` | Page dots in place of Omarchy's workspace numbers (if on) |
| `~/.config/ghostty/config` | One `config-file` line for Bento's Ghostty keys (if on) |

Nothing is written to `~/.config/hypr` or `/usr/share/omarchy`.

</details>

## Remove

Run the uninstaller first, or the plugin hooks Bento back in the next time the
shell starts:

```bash
~/.config/omarchy/plugins/io.github.benjaminsehl.bento/uninstall.sh
omarchy plugin remove io.github.benjaminsehl.bento
```

This puts Omarchy's own bindings and workspace numbers back. Your settings stay
in `~/.config/bento`.

## Docs

- [`docs/keymap.md`](docs/keymap.md): every key and gesture, what it replaced, and why.
- [`docs/pages.md`](docs/pages.md): pages, Exposé and the drawer in detail.
- [`defaults.json`](defaults.json) and [`prefs/Schema.js`](prefs/Schema.js): every setting.

### How it fits together

| Part | Lives in |
|---|---|
| Keys, gestures, page logic | `hypr/*.lua`, loaded by `hypr/bento.lua` through an Omarchy toggle |
| Keyboard layout (⌘/⌃ swap, Option) | `xkb/symbols/bento`, compiled by `install.sh` |
| Bar dots and previews | `pages/` (an Omarchy shell bar widget) |
| Exposé, the drawer, the Bento app | `expose/`, `drawer/`, `prefs/`, behind one overlay (`Overlay.qml`) |
| Settings and applying them | `defaults.json`, `Settings.qml`, `hypr/settings.lua`, `bin/bento-apply` |

## Credits

Bento is a fork of [omac](https://github.com/nchudleigh/omac) by **Neil
Chudleigh**, which got Mac navigation working on Omarchy in the first place.
omac in turn started from [Macifier](https://github.com/omeganter/macifier) by
**Alvaro Antolinez**.

MIT licensed.
