.pragma library

// What the Bento app shows. Every row maps to one key in defaults.json.
//   type      "bool", "choice" (options) or "number" (min, max, step, unit)
//   requires  [section, key] that must be on for the row to matter
//   header    a quiet heading above a group of rows
var fingers = ["3", "4", "3 and 4"]

var panes = [
  {
    id: "keyboard",
    title: "Keyboard",
    rows: [
      { section: "keyboard", key: "macModifiers", type: "bool", title: "Bento modifier layout",
        detail: "⌘ sends Ctrl, so apps get their usual shortcuts. ⌃ runs the desktop, ⌥ types special characters. Everything below needs this." },
      { section: "keyboard", key: "textEditing", type: "bool", title: "Text editing everywhere", requires: ["keyboard", "macModifiers"],
        detail: "⌘← ⌘→ to the line's ends, ⌥← ⌥→ by word, ⌘⌫, and ⌃A ⌃E ⌃K in every app." },
      { section: "keyboard", key: "appShortcuts", type: "bool", title: "App shortcuts", requires: ["keyboard", "macModifiers"],
        detail: "⌘W closes the tab, then the window. ⌘Q quits, ⌘Tab switches, ⌘Space finds apps, ⌘⇧3 ⌘⇧4 ⌘⇧5 capture the screen." },
      { section: "keyboard", key: "topRow", type: "bool", title: "Top row without fn", requires: ["keyboard", "macModifiers"],
        detail: "The Magic Keyboard's top row does what's printed on it: brightness, Overview, Omarchy's menu, microphone, Do Not Disturb, Spotify and volume. Its F-keys reach apps only with a modifier." },
      { section: "keyboard", key: "dictation", type: "bool", title: "Caps Lock dictation", requires: ["keyboard", "macModifiers"],
        detail: "Hold Caps Lock to dictate, if voxtype is installed." }
    ]
  },
  {
    id: "trackpad",
    title: "Trackpad",
    rows: [
      { section: "trackpad", key: "naturalScroll", type: "bool", title: "Natural scrolling",
        detail: "Content follows your fingers." },
      { section: "trackpad", key: "tapToClick", type: "bool", title: "Tap to click",
        detail: "A light tap clicks, without pressing down." },
      { header: "Gestures" },
      { section: "trackpad", key: "swipe", type: "bool", title: "Swipe between pages",
        detail: "Swipe sideways to move from page to page." },
      { section: "trackpad", key: "swipeFingers", type: "choice", options: fingers, title: "Fingers", requires: ["trackpad", "swipe"],
        detail: "How many fingers swipe between pages." },
      { section: "trackpad", key: "swipeLock", type: "bool", title: "Hold still over the scratchpad", requires: ["trackpad", "swipe"],
        detail: "While the scratchpad is open, sideways swipes don't change the page underneath." },
      { section: "trackpad", key: "pinch", type: "bool", title: "Pinch for Overview",
        detail: "Four fingers together show every window. Apart, they show the desktop." },
      { section: "trackpad", key: "upDown", type: "bool", title: "Swipe up and down",
        detail: "Up shows the scratchpad. Down shows your minimized windows, or puts away what's open." },
      { section: "trackpad", key: "upDownFingers", type: "choice", options: fingers, title: "Fingers", requires: ["trackpad", "upDown"],
        detail: "How many fingers swipe up and down." }
    ]
  },
  {
    id: "pages",
    title: "Pages",
    rows: [
      { section: "pages", key: "dots", type: "bool", title: "Dots in the bar",
        detail: "Your pages as dots instead of numbers. Empty pages simply disappear." },
      { section: "pages", key: "dotSize", type: "number", min: 3, max: 8, step: 1, unit: "px", title: "Dot size", requires: ["pages", "dots"],
        detail: "The size of each dot." },
      { section: "pages", key: "previews", type: "bool", title: "Preview on hover", requires: ["pages", "dots"],
        detail: "Hover a dot to see what's on that page." },
      { section: "pages", key: "previewDelay", type: "number", min: 0, max: 1000, step: 50, unit: "ms", title: "Delay", requires: ["pages", "previews"],
        detail: "How long to hover before the preview shows." },
      { section: "pages", key: "previewWidth", type: "number", min: 160, max: 480, step: 20, unit: "px", title: "Preview size", requires: ["pages", "previews"],
        detail: "The width of the preview." },
      { header: "Moving between pages" },
      { section: "pages", key: "numberKeys", type: "bool", title: "⌃1 to ⌃0 count dots",
        detail: "⌃2 is always the second dot. ⌃⇧2 moves a window there." },
      { section: "pages", key: "numberKey", type: "choice", options: ["⌃", "⌘"], title: "Switch with", requires: ["pages", "numberKeys"],
        detail: "⌘ is handy with a mouse; ⌃ keeps working too. Apps lose their own ⌘1 to ⌘9, like a browser's tabs. Needs the Bento modifier layout." },
      { section: "pages", key: "leftEdge", type: "bool", title: "New page on the left",
        detail: "Swipe left past the first dot for an empty page that becomes the first." },
      { section: "pages", key: "slideOnEmpty", type: "bool", title: "Slide on when a page empties",
        detail: "Close or minimize a page's last window and the next page slides in." },
      { section: "pages", key: "slideAnimation", type: "bool", title: "Slide between pages",
        detail: "Pages slide in from the side instead of switching instantly." }
    ]
  },
  {
    id: "windows",
    title: "Windows",
    rows: [
      { section: "windows", key: "minimize", type: "bool", title: "Minimize with ⌘M",
        detail: "Minimized windows wait in a drawer. Swipe down or press ⌃↓ to bring one back." },
      { section: "windows", key: "overview", type: "bool", title: "Overview",
        detail: "Every page, the scratchpad and your minimized windows at once. Pinch, or press ⌃↑." },
      { header: "Tiles" },
      { section: "windows", key: "dragResize", type: "bool", title: "Drag to resize tiles",
        detail: "Bring the pointer to the gap between two windows for a handle, and drag it to change how the page is split. Pages still start half and half." },
      { section: "windows", key: "minTileSize", type: "number", min: 160, max: 800, step: 40, unit: "px", title: "Smallest tile", requires: ["windows", "dragResize"],
        detail: "A drag can't make a window narrower or shorter than this." }
    ]
  },
  // Drawn by prefs/Setups.qml from setups.json, not from defaults.json.
  { id: "setups", title: "Setups", rows: [] },
  {
    id: "terminal",
    title: "Terminal",
    rows: [
      { section: "terminal", key: "ghostty", type: "bool", title: "Bento keys in Ghostty",
        detail: "⌘C ⌘V copy and paste, ⌥ moves by word, and ⌃ letters send control characters." }
    ]
  },
  { id: "about", title: "About", rows: [] }
]
