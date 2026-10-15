# Pages

An [Omarchy](https://omarchy.org) bar widget that shows workspaces as page dots instead of numbers.

![Pages in the Omarchy bar](preview.png)

![Hovering a dot previews the page](preview-hover.png)

- One dot per page that has windows. The page you're on is a wider, brighter pill.
- Empty pages just disappear. Hyprland removes a workspace once you leave it empty.
- `SUPER + N` goes to the Nth dot, so `SUPER + 2` is always the second dot, whatever its workspace number.
  `SUPER + SHIFT + N` moves the window there, and adding `ALT` moves it without following.
  A number past the last dot opens a new page at the end.
- Click a dot to go to that page.
- Hover a dot to see a live preview of that page: your wallpaper plus each window, captured in place.
  Slide along the dots to flip through previews.
- Works in horizontal and vertical bars.

## Install

```bash
omarchy plugin add https://github.com/benjaminsehl/omarchy-pages.git --enable
```

Then make the number keys follow the dots. This replaces Omarchy's `SUPER + 1…0` workspace bindings:

```bash
~/.config/omarchy/plugins/io.github.benjaminsehl.pages/install.sh
```

Run `uninstall.sh` from the same folder to restore the default bindings.

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

In `PagePreview.qml`, `previewWidth` sets the preview's width (260 px by default).

Run `omarchy restart shell` after editing. Hot reload can keep showing the cached version.

## License

MIT
