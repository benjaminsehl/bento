# Pages

An [Omarchy](https://omarchy.org) bar widget that shows workspaces as page dots instead of numbers.

![Pages in the Omarchy bar](preview.png)

- One dot per page that has windows. The page you're on is a wider, brighter pill.
- Empty pages just disappear. Hyprland removes a workspace once you leave it empty.
- Click a dot to go to that page.
- Works in horizontal and vertical bars.

## Install

```bash
omarchy plugin add https://github.com/benjaminsehl/omarchy-pages.git --enable
```

To replace the built-in numbers, disable `omarchy.workspaces`. You can also swap the id
`omarchy.workspaces` for `io.github.benjaminsehl.pages` in `~/.config/omarchy/shell.json`.

## New pages

Turn on Hyprland's workspace swipe, for example in `~/.config/hypr/input.lua`:

```lua
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
```

Swiping past the last page opens an empty desktop, which becomes a new page once you open a window there.
This relies on `gestures:workspace_swipe_create_new`, which is on by default.

## Tweaks

Edit the top of `BarWidget.qml`:

- `dotSize`: the dot diameter in px
- `slot`: the space each dot takes up in px

Run `omarchy restart shell` after editing. Hot reload can keep showing the cached version.

## License

MIT
