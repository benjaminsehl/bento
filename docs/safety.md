# Staying inside Hyprland's lines

Bento's Lua runs inside Hyprland. Nothing sits between the two: a mistake in
Bento's Lua can take down the compositor, and with it everything on screen.
On 22 October 2026 it did. `keys.lua` kept Hyprland's bind objects so it could
switch the Ghostty bindings on and off whenever a window took focus. Then
`windows.lua` unbound Ctrl+M, which deleted one of those objects, and Hyprland
crashed as the next window opened, on every login. These rules exist so that
can't happen again. They are not suggestions: a change that breaks one doesn't
land.

## Where Bento is allowed in

Omarchy's plugin system only takes QML: a service, an overlay and a bar
widget (`manifest.json`). A crash in those is the shell's, and Omarchy
restarts it. Hyprland has no hook for plugins, so the keys, pages and setups
come in through one small stub that `install.sh` writes to Omarchy's toggles
directory. That stub is the only way Bento's Lua gets into Hyprland, and it
guards the way in:

- **The breaker.** Every Hyprland marks its first two minutes with Bento in
  `~/.local/state/bento/starting`. If a Hyprland finds another one's mark,
  that one stopped while Bento was new to it, so it starts without Bento,
  says so in a notification, and stays that way until `bento resume`. A
  crash costs one login, not every login.
- **Errors stop at Bento.** `bento.lua` runs inside a `pcall`, so a Lua error
  goes to `~/.local/state/bento/errors` and a notification, and the rest of
  your config still loads.
- **Disabling is always enough.** Disable Bento in Omarchy, or move the plugin
  folder away, and the next Hyprland is stock Omarchy. Nothing Bento does may
  outlast that.

## The rules for Bento's Lua

1. **Keep no Hyprland objects.** Whatever `hl.bind`, a window or workspace
   rule, `hl.get_*` or an event gives back belongs to that moment. Don't store
   it for later and don't call methods on it later (`:set_enabled`, …).
   Hyprland can free it underneath you, and a freed object is a crash that
   `pcall` can't catch.
2. **Events only read and dispatch.** An `hl.on` handler may look things up
   and send dispatchers. It never binds, unbinds or adds or changes rules.
3. **One owner per key.** `hl.unbind` takes a key away from every keyboard
   and every module. Bento only unbinds keys that are Omarchy's or that the
   same module bound itself in the same pass, and never one another Bento
   module has bound.
4. **Decide in the binding, not around it.** A key that should act
   differently in a terminal checks inside its own dispatcher, the way
   `lib.send` does, instead of being switched on and off as focus moves.
5. **Never write `~/.config/hypr`.** Your config is yours.

## Before anything that touches `hypr/` lands

- Every tracked `.lua` compiles under Hyprland's Lua (5.5):
  `for f in $(git ls-files '*.lua'); do lua -e "assert(loadfile('$f'))"; done`
- `hyprctl reload` on the live machine, then `hyprctl configerrors` is empty
  and `~/.local/state/bento/errors` is empty.
- Two minutes of ordinary use after that reload: open, focus and close a few
  windows on each keyboard. A crash shows up there, not in a fake `hl`.
- The checks run on Hyprland's real behaviour. A harness with a stand-in `hl`
  is useful, but it can't tell you something won't crash.

## Known exceptions, still to fix

- `hypr/pages.lua` keeps each left-edge workspace rule (`M.edges[...].rule`)
  and calls `:set_enabled(false)` on it from its event handlers. It has
  held up for a week, but it breaks rules 1 and 2 and has to change.
