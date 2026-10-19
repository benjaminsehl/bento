import QtQuick
import Quickshell.Hyprland

// Hyprland won't focus a window while one of Bento's views has the keyboard,
// and when the view lets go it focuses the window you were on again, taking
// you back to its page. So a dispatch that moves focus waits here until the
// view's window has lost the keyboard: Hyprland has put focus back by then,
// and what's sent next goes through. (Or shortly after, if that never comes.)
//
//   AfterRelease { id: afterRelease; window: someItem.Window.window }
//   afterRelease.dispatch("hl.dsp.focus({ window = ... })")
//   ...and close the view, which lets go of the keyboard.
Item {
  id: root
  visible: false

  // The window of the view that has the keyboard.
  property var window: null

  property var _queue: []

  function dispatch(expr) {
    root._queue.push(expr)
    if (root.window && root.window.active) timer.restart()
    else root.flush()
  }

  function flush() {
    timer.stop()
    var list = root._queue
    root._queue = []
    for (var i = 0; i < list.length; i++) Hyprland.dispatch(list[i])
  }

  Timer { id: timer; interval: 250; onTriggered: root.flush() }
  Connections {
    target: root.window
    function onActiveChanged() { if (!root.window.active && root._queue.length) root.flush() }
  }
}
