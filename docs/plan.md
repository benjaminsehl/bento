# The polish plan

Goal: every movement in Bento feels designed, from the first keypress to the
last frame of an animation. This is the working plan. Tick things off as they
land and add what we learn.

## The critique, in two lines

- **Gestures are buttons, not handles.** The drawer, the scratchpad and
  Overview all start once your fingers lift. Only page swipes follow your hand.
- **Bento has a spatial model it never commits to.** Overview puts minimized
  windows above and the scratchpad below, but nothing else uses that map.

## The idea: Bento is a box, and you're looking into one compartment

```
                ┌──────── drawer (minimized) ────────┐
   … ◀  page  ◀  page  ▶  page  ▶ …      (sideways)
                └──────── scratchpad ────────────────┘
     Overview = the camera pulling back to see the whole box
```

Every transition is either a camera move or an object moving on this map.

- **Pull down: the drawer comes down from the top, attached to your fingers.**
  Reverse halfway and it goes back. Let go fast and it carries on; let go
  slowly and it settles to whichever side is nearer.
- **Push up: the scratchpad rises from below, the same way.** Up and down are
  one gesture, so you can change your mind within one movement.
- **Pinch: the camera pulls back.** Pinch scale maps directly to zoom. The page
  you're on starts full-screen and shrinks into its slot while the others slide
  in beside it.
- **⌘M: the window visibly travels up into the drawer.** Restoring reverses that
  path.
- **Honest empty states.** Pulling down with nothing minimized gives a few
  pixels of rubber-band resistance and springs back.

## One motion system

- One spring, used everywhere: Overview, the drawer, the page dots, and
  Hyprland's own window and workspace animations, all from one file.
- Release speed counts: a flick carries on, a slow drag settles to the nearer side.
- Anything moving can be caught mid-animation by a new gesture.
- Today there are eight different durations (100 to 240 ms), all with the same
  ease-out curve. They should all collapse into the shared values.

## The little things

- The page-dot pill morphs between dots as you swipe (needs swipe progress
  from Hyprland's native workspace gesture, which we may not be able to get).
- Window open and close use the same spring and come from where they logically
  come from.
- Overview's rounding, shadows and captions match Omarchy's window chrome.
- Fewer settings: pick finger counts once and drop the rest. A setting is a
  decision that wasn't made.

## How it's built (what we found)

- **Hyprland 0.56 Lua gestures stream.** `hl.gesture({ fingers, direction,
  action = { start = fn, update = fn, finish = fn } })`. Each callback gets an
  event table: `phase`, `direction`, `type` (`swipe` / `pinch`), `time_ms`,
  `fingers`, `delta = { x, y }` (per event, not cumulative), `scale` and
  `rotation` for pinches, and `cancelled` on finish. Source:
  `src/managers/input/trackpad/gestures/LuaFunctionGesture.cpp` and
  `src/config/lua/bindings/LuaBindingsConfigRules.cpp` (v0.56.2). There's also
  a `scale` field on the gesture for the delta multiplier.
- **Lua → shell:** `hl.dispatch(hl.dsp.event("bento>>…"))` emits
  `custom>>bento>>…` on Hyprland's event socket. Quickshell's
  `Hyprland.rawEvent` receives it. No process per frame.
- **The native `special` gesture action** (`workspace_name`) follows your
  fingers for a special workspace, in case our own version of the scratchpad
  gesture isn't worth it.
- Callbacks run inside Hyprland with a timeout, so they must stay cheap: add
  up the delta, send one event, return.

## Slices

Each slice is felt on the real trackpad and tuned before moving on.

- [ ] **1. Foundation.** Shared motion values (`motion/Motion.js`, also read by
      the Hyprland Lua) and the gesture stream (Lua → `custom>>bento>>…` →
      shell).
- [ ] **2. Up and down as one gesture.** The drawer and the scratchpad follow
      your fingers, can be reversed mid-gesture, commit on release speed or
      distance, and rubber-band when there's nothing to show.
- [ ] **3. Pinch moves the Overview camera.** Zoom follows the pinch, and the
      current page pulls back from full-screen into its slot.
- [ ] **4. ⌘M and restore travel.** The window flies to and from the drawer.
- [ ] **5. Fewer settings.** Decide finger counts; cut toggles that should
      simply be right.
- [ ] **6. Page-dot morph during swipes** (if Hyprland exposes swipe progress).
- [ ] **7. Window open and close** on the shared spring, from their logical
      origin.
- [ ] **8. Chrome pass.** Overview and drawer rounding, shadows and type match
      Omarchy exactly.

## Tuning notes

Record what each round of trying it on the trackpad teaches us here: distances,
spring stiffness, velocity thresholds, rubber-band resistance.
