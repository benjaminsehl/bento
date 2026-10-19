# Pages, Overview and the drawer

Bento shows Omarchy's workspaces as pages: an ordered row you swipe through, shown as dots in the bar.
Every part can be switched off or tuned in the Bento app (`bento`, or ⌃⌘,).

![Pages in the Omarchy bar](images/pages.png)

![Hovering a dot previews the page](images/pages-hover.png)

## Pages

- One dot per page with windows. The page you're on is a wider, brighter pill.
- Each monitor has its own pages. Its bar shows only its own dots, and the number keys, ⌃← / ⌃→, swipes and
  Overview stay on the monitor you're using.
- Empty pages disappear: Hyprland removes a workspace once you leave it empty.
- Hover a dot for a live preview of that page: your wallpaper plus each window, in place.
  Slide along the dots to flip through previews. Click a dot to go there.
- ⌃1 … ⌃0 go to the Nth dot on this monitor, whatever its workspace number. ⌃⇧N moves the window there and follows it;
  ⌃⇧⌥N moves it without following. A number past the last dot opens a new page at the end.
- Set *Switch with* to ⌘ and ⌘1 … ⌘0 switch pages too, which is easier with a mouse than a trackpad. ⌃N still
  works, moving a window stays on ⌃⇧N, and apps lose their own ⌘1 … ⌘9 (a browser's tabs, say).
- Close or minimize a page's last window and the next page slides in. On the rightmost page you stay on the empty screen.

The code is `pages/BarWidget.qml` and `pages/PagePreview.qml` for the bar, and `hypr/pages.lua` for the keys and the left edge.

## New pages, at both ends

- **Swipe past the last dot** for an empty page at the end. Hyprland does this itself
  (`gestures:workspace_swipe_create_new`, on by default).
- **Swipe past the first dot** for an empty page that becomes dot #1. Hyprland can't create workspaces off
  the left end, so `hypr/pages.lua` keeps one empty, persistent workspace just left of the first page. The bar hides
  it until you're on it. Open a window there and it becomes a real page, and a new empty one is placed to its left.

Workspace ids can't go below 1, so new sessions start at workspace 1001 to leave room on the left. If a monitor
still runs out of room (one plugged in later starts at 1), its pages move up by a thousand ids, onto ids no other
monitor has. Monitors share one set of ids, so a new page takes the nearest id that isn't another monitor's page.
The ids never show: dots and ⌃N count positions.

## Overview

Pinch thumb and three fingers together, press ⌃↑, or press F3 on an Apple keyboard to zoom out to everything.
Spread the fingers, press Esc or click the background to zoom back in.

- Every page is a miniature of your monitor, in dot order, with its windows exactly where Hyprland put them.
  The page you're on is outlined.
- The scratchpad is a miniature too, centred at the bottom.
- Minimized windows have no place on screen, so they sit in a small shelf centred at the top.
- Click a window to go to it; a minimized window comes back onto the page you're on. Click a page to go there,
  or the scratchpad to open it. The empty frame at either end starts a new page there.
- Arrow keys move the selection and ↩ picks it. Only the selected window shows its title.

Spreading thumb and three fingers with Overview closed shows the desktop (the empty page left of the first one);
again brings the windows back.

libinput only processes gestures of up to four fingers, so five-finger gestures can't work.

The code is `overview/Overview.qml`, opened through `Overlay.qml` (`bento overview`).

## The drawer

⌘M sends a window to the hidden `special:minimized` workspace. Swipe three or four fingers down, or press ⌃↓,
and those windows drop from the top as live cards. Click a card to bring the window
back; drag it up, middle-click or press ⌫ to close it. Fingers up or Esc closes the drawer.

The code is `drawer/Drawer.qml` (`bento drawer`).
