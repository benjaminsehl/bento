import QtQuick
import "Motion.js" as Motion

// One value on Bento's spring. Fingers set it directly (jump); letting go
// hands it to the spring with the fingers' speed (animateTo), so motion
// continues rather than restarting. A new jump catches it wherever it is.
Item {
  id: spring
  visible: false

  property real value: 0
  property real velocity: 0   // units per second
  property real target: 0
  property real stiffness: Motion.spring.stiffness
  property real damping: Motion.spring.damping
  // 1 or -1 keeps the value on that side of zero: it stops dead at zero
  // instead of carrying on through. 0 lets it go anywhere.
  property int side: 0
  readonly property bool running: frames.running

  signal settled(real at)

  function jump(v) {
    frames.stop()
    spring.value = v
    spring.target = v
    spring.velocity = 0
  }

  function animateTo(t, v) {
    spring.target = t
    if (v !== undefined) spring.velocity = v
    if (Math.abs(spring.value - t) < Motion.spring.restDistance && Math.abs(spring.velocity) < Motion.spring.restSpeed) {
      spring.value = t
      spring.velocity = 0
      frames.stop()
      spring.settled(t)
      return
    }
    frames.start()
  }

  function stop() { frames.stop() }

  FrameAnimation {
    id: frames
    onTriggered: {
      // Small fixed steps keep a stiff spring stable at any frame rate.
      var dt = Math.min(frameTime, 1 / 30)
      var steps = Math.max(1, Math.ceil(dt / (1 / 480)))
      var h = dt / steps
      var k = spring.stiffness
      var c = 2 * spring.damping * Math.sqrt(k)
      var x = spring.value, v = spring.velocity, t = spring.target
      for (var i = 0; i < steps; i++) {
        v += (-k * (x - t) - c * v) * h
        x += v * h
        if (spring.side * x < 0) { x = 0; v = 0 }
      }
      if (Math.abs(x - t) < Motion.spring.restDistance && Math.abs(v) < Motion.spring.restSpeed) {
        spring.value = t
        spring.velocity = 0
        frames.stop()
        spring.settled(t)
        return
      }
      spring.value = x
      spring.velocity = v
    }
  }
}
