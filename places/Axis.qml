import QtQuick
import "../motion"
import "../motion/Motion.js" as Motion

// The vertical axis of Bento's map: one value from -1 to 1.
//
//    1   the drawer is down (it lives above the screen)
//    0   neither: just the page
//   -1   the scratchpad is up (it lives below the screen)
//
// Fingers drag the value directly. A gesture stays on one side: it picks the
// side it starts on (or, from rest, the way it first moves), and zero is a
// wall, so pushing an open drawer up closes it and stops there. Letting go
// hands it to the spring, which settles at whichever stop the release would
// coast to. A side with nothing to show gives a little and springs back.
Item {
  id: axis
  visible: false

  // What there is to show. Set by the host.
  property int drawerCount: 0
  property int scratchCount: 0

  readonly property real value: spring.value
  readonly property real drawer: Math.max(0, spring.value)
  readonly property real scratch: Math.max(0, -spring.value)
  readonly property real target: spring.target
  readonly property bool moving: dragging || spring.running
  property bool dragging: false

  // Fired when a gesture or animation comes to rest at a stop.
  signal settled(real at)
  // Fired when fingers first take hold of the value.
  signal grabbed(real from)

  Spring {
    id: spring
    onSettled: function(at) { axis.settled(at) }
  }

  property real _base: 0
  property real _travel: 0
  property real _raw: 0
  property int _side: 0   // this gesture's side: 1 the drawer, -1 the scratchpad, 0 not yet
  property var _samples: []

  function hi() { return axis.drawerCount > 0 ? 1 : 0 }
  function lo() { return axis.scratchCount > 0 ? -1 : 0 }

  // Past the reachable range, the value gives like a rubber band.
  function constrain(raw) {
    var h = hi(), l = lo()
    if (raw > h) return h + Motion.rubber(raw - h, Motion.pull.rubberLimit, Motion.pull.rubberStiffness)
    if (raw < l) return l + Motion.rubber(raw - l, Motion.pull.rubberLimit, Motion.pull.rubberStiffness)
    return raw
  }

  // Fingers: dy is the trackpad's own delta (down is positive), t in ms.
  function begin(dy, t) {
    spring.stop()
    axis._base = spring.value
    axis._side = spring.value > 0.0005 ? 1 : (spring.value < -0.0005 ? -1 : 0)
    axis._travel = 0
    axis._samples = []
    axis.dragging = true
    axis.grabbed(axis._base)
    move(dy, t)
  }

  function move(dy, t) {
    if (!axis.dragging) return
    axis._travel += dy
    var raw = axis._base + axis._travel / Motion.pull.distance
    if (axis._side === 0 && raw !== axis._base) axis._side = raw > axis._base ? 1 : -1
    // At the wall, hold at zero: moving back the other way picks up at once.
    if (axis._side * raw < 0) {
      axis._travel = -axis._base * Motion.pull.distance
      raw = 0
    }
    axis._raw = raw
    spring.jump(constrain(raw))
    var s = axis._samples
    s.push({ t: t, v: axis._raw })
    while (s.length > 2 && t - s[0].t > Motion.pull.velocityWindowMs) s.shift()
  }

  function end(cancelled, t) {
    if (!axis.dragging) return
    axis.dragging = false
    var s = axis._samples
    var speed = 0
    if (s.length >= 2 && s[s.length - 1].t > s[0].t)
      speed = (s[s.length - 1].v - s[0].v) / ((s[s.length - 1].t - s[0].t) / 1000)

    var stop
    if (cancelled) {
      stop = Math.round(axis._base)
    } else {
      var coast = axis._raw + speed * Motion.pull.projection
      stop = Motion.clamp(Math.round(coast), axis._side > 0 ? 0 : lo(), axis._side < 0 ? 0 : hi())
    }
    spring.side = axis._side
    // Past the end, the rubber band soaks up most of the fingers' speed.
    var v = spring.value > hi() || spring.value < lo() ? speed * 0.2 : speed
    spring.animateTo(stop, v)
  }

  // Keys, clicks and anything else that isn't fingers.
  function to(stop) {
    if (axis.dragging) return
    spring.side = 0
    spring.animateTo(Motion.clamp(stop, -1, 1))
  }

  // Follow a change made elsewhere (say, the scratchpad opened from a menu)
  // without animating.
  function sync(stop) {
    if (axis.moving) return
    spring.jump(stop)
  }
}
