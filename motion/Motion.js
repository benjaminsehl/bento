.pragma library

// Bento's motion, in one place. Everything that moves reads from here, so it
// all moves the same way. Tuning notes live in docs/plan.md.

// The spring every settle uses. Stiffness is per unit of travel (a full open
// is 1); a damping ratio just under 1 lands without a visible bounce.
var spring = {
  stiffness: 340,
  damping: 0.9,
  // Close enough to stop: position and speed, in units of travel.
  restDistance: 0.0008,
  restSpeed: 0.02,
}

// Pulling things in with fingers: the drawer from above, the scratchpad from
// below.
var pull = {
  // Finger travel for a full open, in the trackpad's pointer units.
  distance: 240,
  // A release coasts this many seconds at its speed; whichever stop is nearest
  // to where it would coast to wins. Small: drags settle where they are,
  // flicks carry on.
  projection: 0.16,
  // Pulling past the end, or at nothing: how far it gives, in units of travel,
  // and how stiff that feels (higher gives sooner).
  rubberLimit: 0.12,
  rubberStiffness: 0.55,
  // Velocity is measured over this much of the end of a gesture.
  velocityWindowMs: 80,
}

// Pinching Overview open. The trackpad reports how far the fingers have come
// together as a scale: 1 where they started, smaller as they close. This is
// the scale for a full zoom out; it's taken as a ratio, so every bit of the
// pinch moves the camera as much as any other. The rest is pull's.
var zoom = {
  fullScale: 0.6,
}

// iOS-style rubber band: gives easily at first, then ever less, never past
// `limit`.
function rubber(overshoot, limit, stiffness) {
  var x = Math.abs(overshoot)
  var r = (1 - 1 / ((x * stiffness / limit) + 1)) * limit
  return overshoot < 0 ? -r : r
}

function clamp(x, lo, hi) { return Math.min(hi, Math.max(lo, x)) }
function lerp(a, b, t) { return a + (b - a) * t }
