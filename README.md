<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/icon-dark.svg">
    <img src="docs/images/icon-light.svg" width="72" height="72" alt="Bento">
  </picture>
</p>

<h1 align="center">Bento</h1>

<p align="center">
  <strong>Omarchy, thoughtfully arranged.</strong><br>
  An opinionated window manager experience for Omarchy: pages, Overview, a
  drawer for minimized windows, and gestures that follow your fingers.
</p>

<p align="center">
  <a href="https://github.com/tcballard/omarchy-badges"><img src="https://raw.githubusercontent.com/tcballard/omarchy-badges/85f859029e236e784e7b05ada6dbe73506d07a91/badges/v1/built-for-omarchy.svg" alt="Built for Omarchy"></a>
</p>

<p align="center">
  <a href="#pages">Pages</a> ·
  <a href="#overview">Overview</a> ·
  <a href="#the-drawer">Drawer</a> ·
  <a href="#tiles">Tiles</a> ·
  <a href="#gestures">Gestures</a> ·
  <a href="#keys">Keys</a> ·
  <a href="#setups">Setups</a> ·
  <a href="#the-bento-app">App</a> ·
  <a href="#install">Install</a>
</p>

Omarchy is a great base: fast, keyboard-first and beautifully put together.
Bento is one opinionated take on how working in it should *feel*. Every window
has a place, you move between places with your hands, nothing you put away
gets lost, and the desktop responds without any delay you can notice.

## Pages

Workspaces become an ordered row of pages, shown as dots in the bar. The page
you're on is a wider, brighter pill. Each monitor has its own row of pages.

![Pages in the Omarchy bar](docs/images/pages.png)

- Hover a dot to see a live preview of that page, and slide along the dots to
  flip through them. Click a dot to go there.
- ⌃1 … ⌃0 go to the Nth dot on this monitor, whatever the workspace id is. ⌃⇧N takes the
  window with you.
- Empty pages disappear. Swipe past either end to get a new one.
- When a page's last window closes, the next page slides in.

![Hovering a dot previews the page](docs/images/pages-hover.png)

## Overview

Pinch with your thumb and three fingers, or press ⌃↑, to zoom out to
everything. Each page shows as a true miniature of your monitor, in dot order.
The scratchpad sits underneath and minimized windows sit above.

![Overview: every page, the scratchpad and minimized windows](docs/images/overview.png)

Click a window to go to it, or a page to go there. The empty frame at either
end starts a new page. Drag a page to reorder it, or to the edge facing
another monitor to move it there. Drag a single window to send just that
window to another page, a new one, or the other monitor. You can also move
around with the arrow keys and pick with ↩. Spread your fingers to zoom back
in. With Overview closed, spreading shows the desktop.

## The drawer

⌘M minimizes. Swipe down, or press ⌃↓, and minimized windows drop in from the
top as live cards. Click a card to bring its window back onto the page you're
on. Flick a card up, middle-click it or press ⌫ to close the window.

![The drawer of minimized windows](docs/images/drawer.png)

## Tiles

Two windows on a page share it half and half. Bring the pointer to the gap
between them and a handle appears beside it; drag the handle to split the page
some other way, and the split stays where you leave it. A drag never makes a
window smaller than the smallest tile size (320 px unless you change it).

## Gestures

| Gesture | Does |
|---|---|
| Two fingers | Scroll. Content follows your fingers |
| Three or four fingers sideways | Move between pages, following your fingers. A flick switches, and a slow drag peeks |
| Three or four fingers up | The scratchpad |
| Three or four fingers down | The drawer |
| Pinch, thumb and three fingers | Overview |
| Spread, thumb and three fingers | Show the desktop |

Gestures finish what your hand began, with short animations you can
interrupt. Each gesture can be switched off, and its finger count changed.

## Keys

The key beside Space talks to apps. ⌘ sends Ctrl at the keyboard layout, so
every app gets its native shortcuts without remapping. The desktop lives on ⌃,
and ⌥ types special characters. On top of that:

- Text editing that works the same everywhere: ⌘←/→ to the ends of the line,
  ⌥←/→ by word, and ⇧ to select.
- A ⌘W that closes the tab first and the window only when no tab is left.
- ⌘Q, ⌘Tab, a launcher on ⌘Space, and screenshots on ⌘⇧3/4/5.
- Terminal keys that stay terminal keys: ⌃C, ⌃D and ⌃R reach the shell.
- Ghostty keys for copy, paste (images included), tabs and splits.

That's for Mac keyboards. Each keyboard has a style in the Keyboard pane:
Mac, Mac on PC keys (the same keys on a Ctrl/Win/Alt row), or PC. A PC
keyboard, like a laptop's, keeps Omarchy's own keys and gets Bento's extras
on Super: Super+←/→ for pages, Super+↑ for Overview, Super+↓ for the drawer
and Super+M to minimize. In Ghostty, Ctrl+C interrupts and Ctrl+Shift+C
copies, as on Linux.

Every key, what it replaced and why is in [`docs/keymap.md`](docs/keymap.md).

## Setups

A setup is a desk: how the displays are arranged there, and which style each
keyboard gets. Arrange your displays the way you like them, then save the desk
in the Bento app's Setups pane, or with `bento setup save Work`. From then on,
plugging in brings it back.

- Displays are known by their EDID, whatever port or dock they're on. When
  one is missing, the others close up the gap.
- Every change is checked against what Hyprland shows. When a setup doesn't
  come out as saved, a notification says what differed, and Bento tries the
  next best one. If that fails too, it stops until something is plugged in or
  out. It never loops.
- Once you have two setups, right-click the page dots to choose one by hand.
  It holds until a display or dock changes. `bento setup pick` does the same
  from the keyboard.
- With no setup in use, drag the displays in the Setups pane: they snap
  together and move at once, keeping their scale and rotation. That lasts
  until a display or dock changes, or you choose Automatic; save it as a
  setup to keep it. From a terminal,
  `bento setup arrange internal=2560,540 "LG UltraFine"=0,0` does the same.
- A setup can give a keyboard another style, like PC at work. Each keyboard
  has its own in the Keyboard pane.
- Tiled 5K displays such as the LG UltraFine run on one stream, scaled to
  the whole panel, so a dock that can't carry two streams doesn't leave them
  split or black. That works with or without a setup.

The details are in [`docs/setups.md`](docs/setups.md).

## The Bento app

One window, with a pane per area and a row per setting. Run `bento`, press ⌃⌘,
or find **Bento** in the app launcher.

![The Bento app](docs/images/app-trackpad.png)

Changes apply as soon as you make them. If Hyprland rejects a change, Bento
puts the previous settings back, so a bad setting can't leave you with a broken
desktop. Only what differs from [`defaults.json`](defaults.json) is saved, in
`~/.config/bento/settings.json`.

## Principles

1. **Direct manipulation.** If your fingers start it, the screen follows them.
2. **Places, not numbers.** You think in "the page to the right", not in
   workspace 1004.
3. **Nothing gets lost.** Minimized, scratchpad or off to the side, everything
   shows up in Overview and is one gesture away.
4. **Native first.** Apps get the keys they expect. Bento only translates where
   it has to, and it leaves terminals alone.
5. **Opinionated, not locked in.** Strong defaults, each with a switch.
   Removing Bento gives you back stock Omarchy.
6. **Never break the desktop.** Every change is checked and rolled back if
   Hyprland complains, and a failing module doesn't take the others down.
7. **Readable.** A few Lua and QML files you can search. Behaviour lives in
   Hyprland, and interface in the Omarchy shell.

## Where it's going

Bento's aim is a desktop that feels designed as a whole, from the first
keypress to the last frame of an animation. These are directions, not promises:

- **Gestures that follow your fingers all the way.** Overview and the drawer
  should follow your fingers continuously, the way page swipes already do.
- **Window arrangement as a first-class idea.** Snap, split and resize with
  gestures and keys that make sense together, and layouts that remember where
  things go.
- **A real app switcher.** App icons, live previews and per-app window
  cycling.
- **Overview as a workbench.** Drag windows between pages, reorder pages, and
  drop a window into the drawer.
- **One feel for motion.** Shared timing and easing across pages, Overview, the
  drawer and the bar.

Ideas and rough edges are welcome as issues.

## Install

Bento needs Omarchy 4 or newer (the release that configures Hyprland in Lua).

```bash
omarchy plugin add https://github.com/benjaminsehl/bento --enable
```

Bento runs only as an Omarchy plugin. The plugin runs
[`install.sh`](install.sh) each time the shell starts Bento. The first run
hooks Bento into Hyprland, and later runs find everything in place and do
nothing. If something stops it, a desktop notification says why.

To work on a checkout, link it as the plugin and enable it. `install.sh`
refuses to run from any other folder, because Omarchy's disable and remove
are what take Bento out again:

```bash
ln -s ~/path/to/bento ~/.config/omarchy/plugins/io.github.benjaminsehl.bento
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.benjaminsehl.bento
```

After that, editing the files and running `hyprctl reload` is the whole
update; QML changes need `omarchy-restart-shell`. Re-run `install.sh` after
changing `xkb/`. On the Magic Keyboard, the top row does what's printed on it
without fn.

<details>
<summary>What Bento touches</summary>

| Path | What it is |
|---|---|
| `~/.local/state/omarchy/toggles/hypr/bento.lua` | A few lines that load `hypr/bento.lua` from the plugin folder, or start the cleanup once the folder is gone |
| `~/.local/state/bento/` | Compiled keymaps, errors from the last reload, what Setups found and chose (`setup.json`, and briefly `setup-request.json`), a copy of `bin/bento-cleanup`, and where the checkout is (`repo`) |
| `~/.local/bin/bento`, `bento-apply`, `mac-keybindings` | Links into `bin/` |
| `~/.local/share/applications/bento.desktop` | The Bento app, in the launcher |
| `~/.config/bento/settings.json` | Your settings |
| `~/.config/bento/setups.json`, `keyboards.json` | Your setups and keyboard styles, once you save one; the app keeps the version before as `.prev`, and a setups change that failed as `setups.json.rejected` |
| `~/.config/ghostty/config` | One `config-file` line for Bento's Ghostty keys (if on) |
| `~/.config/omarchy/shell.json` | Only to take Bento out, the way Omarchy's disable does, when the plugin folder went away without one |
| `$XDG_RUNTIME_DIR/bento.lock`, `bento-setup.lock`, `bento-spotify-starting` | Empty lock files, and a marker while F8 starts Spotify. The cleanup removes `bento-setup.lock`; the folder is emptied at logout |

Omarchy itself edits `shell.json` when you enable or disable Bento: Bento
takes the place of its workspace numbers in the bar, and disabling puts them
back. With the dots off, Bento shows those same numbers itself, so it doesn't
touch `shell.json` for that. Nothing is written to `~/.config/hypr` or
`/usr/share/omarchy`.

</details>

## Remove

Disabling or removing Bento in Omarchy gives back stock Omarchy by itself:

```bash
omarchy plugin remove io.github.benjaminsehl.bento
```

Once Omarchy has settled, Bento's cleanup takes away its hook, links, launcher
entry, state and Ghostty line, and reloads Hyprland, so Omarchy's own bindings
and workspace numbers are back. If Omarchy is holding Hyprland reloads for an
update, the hook stays until the reload that ends the hold, and does only
that. If Bento kept a tiled display on one stream, a notification gives the
`~/.config/hypr/monitors.lua` lines that keep it that way (Bento never writes
there itself). Your settings, setups and keyboard styles stay in `~/.config/bento`.

The uninstaller does the same by hand, for when the shell isn't running or
you'd rather watch it happen. `--purge` deletes `~/.config/bento` too:

```bash
~/.config/omarchy/plugins/io.github.benjaminsehl.bento/uninstall.sh [--purge]
omarchy plugin remove io.github.benjaminsehl.bento
```

If you updated from an older Bento in this session, restart the shell
(`omarchy-restart-shell`) or run `uninstall.sh` before `omarchy plugin
remove`: the shell keeps the older Bento's Service until it restarts.

## Docs

- [`docs/keymap.md`](docs/keymap.md): every key and gesture, and why.
- [`docs/pages.md`](docs/pages.md): pages, Overview and the drawer in detail.
- [`docs/setups.md`](docs/setups.md): setups, per-desk display layouts and keyboard styles, and tiled displays.
- [`defaults.json`](defaults.json) and [`prefs/Schema.js`](prefs/Schema.js): every setting.
- [`docs/screenshots.sh`](docs/screenshots.sh): retakes the screenshots in this README.

| Part | Lives in |
|---|---|
| Keys, gestures, page logic | `hypr/*.lua`, loaded by `hypr/bento.lua` through an Omarchy toggle |
| Keyboard layout | `xkb/symbols/bento`, compiled by `install.sh` |
| Bar dots and previews | `pages/` (an Omarchy shell bar widget) |
| Overview, the drawer, the Bento app | `overview/`, `drawer/`, `prefs/`, behind one overlay (`Overlay.qml`) |
| Settings and applying them | `defaults.json`, `Settings.qml`, `hypr/settings.lua`, `bin/bento-apply` |
| Setups and keyboards | `hypr/setups.lua` (with `edid.lua`, `sysfs.lua`, `json.lua`), `hypr/keyboard.lua`, `keyboards.json`, `bin/bento-setup`, `prefs/Setups*`, `prefs/Identify.qml`, `prefs/Keyboards.qml`, `pages/SetupsMenu.qml` |
| Plugging in and out of Omarchy | `manifest.json`, `Service.qml`, `install.sh`, `bin/bento-cleanup`, `uninstall.sh` |

MIT licensed.
