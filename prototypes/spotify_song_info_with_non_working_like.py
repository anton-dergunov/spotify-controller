#!/usr/bin/env python3
"""
spotify_like.py — Spotify Like Tracker & Toggler
-------------------------------------------------
Two-pronged approach:
  TOGGLE: sends Spotify's official keyboard shortcut Alt+Shift+B via CGEvent.
          Works even when Spotify is minimized or in the background.
  READ:   enables Electron's full accessibility tree via AXEnhancedUserInterface,
          then walks it to find the heart button's label.

NO developer account, NO API keys, NO Premium, NO cookies needed.

Requirements:
    pip install pyobjc-framework-Cocoa pyobjc-framework-Quartz

One-time macOS setup:
    System Settings → Privacy & Security → Accessibility
    → Add your terminal (Terminal.app / iTerm2 / Warp)

Usage:
    python3 spotify_like.py             # normal mode
    python3 spotify_like.py --discover  # dump AX tree after unlocking Electron
"""

import os
import sys
import threading
import time

import objc
from AppKit import NSWorkspace
from ApplicationServices import (
    AXIsProcessTrusted,
    AXUIElementCopyAttributeValue,
    AXUIElementCopyAttributeNames,
    AXUIElementCreateApplication,
    AXUIElementSetAttributeValue,
    AXUIElementPerformAction,
    kAXChildrenAttribute,
    kAXDescriptionAttribute,
    kAXErrorSuccess,
    kAXPressAction,
    kAXRoleAttribute,
    kAXTitleAttribute,
)
from Foundation import (
    NSDate,
    NSDistributedNotificationCenter,
    NSObject,
    NSRunLoop,
)
from Quartz import (
    CGEventCreateKeyboardEvent,
    CGEventPost,
    CGEventSetFlags,
    kCGEventFlagMaskAlternate,
    kCGEventFlagMaskShift,
    kCGHIDEventTap,
)

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------

current_track = {
    "uri":    None,
    "name":   "--",
    "artist": "--",
    "album":  "--",
    "liked":  None,
}
_lock = threading.Lock()

# Known labels for the like button in Spotify's AX tree (when unlocked)
LIKE_LABELS   = {"Add to Liked Songs", "Save to Your Library", "Like"}
UNLIKE_LABELS = {"Remove from Liked Songs", "Remove from Your Library", "Unlike"}

# ---------------------------------------------------------------------------
# Spotify process helpers
# ---------------------------------------------------------------------------

def get_spotify_pid():
    for app in NSWorkspace.sharedWorkspace().runningApplications():
        if app.bundleIdentifier() == "com.spotify.client":
            return app.processIdentifier()
    return None


def spotify_running():
    return get_spotify_pid() is not None

# ---------------------------------------------------------------------------
# Unlock Electron accessibility tree
# ---------------------------------------------------------------------------
# By default, Spotify's Electron/CEF shell hides all inner web content from
# the AX tree. Setting AXEnhancedUserInterface = true tells the Chromium
# layer to materialise the full tree. We must re-set this every time the
# process restarts (it's not persisted).

_ax_unlocked_pid = None

def ensure_ax_unlocked():
    global _ax_unlocked_pid
    pid = get_spotify_pid()
    if pid is None:
        return False
    if pid == _ax_unlocked_pid:
        return True
    app = AXUIElementCreateApplication(pid)
    # Try both flags — different Electron/CEF versions respond to different ones
    AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface", True)
    AXUIElementSetAttributeValue(app, "AXManualAccessibility", True)
    _ax_unlocked_pid = pid
    time.sleep(0.3)   # give Chromium time to build the tree
    return True

# ---------------------------------------------------------------------------
# AX tree helpers
# ---------------------------------------------------------------------------

def ax_get(element, attr):
    err, val = AXUIElementCopyAttributeValue(element, attr, None)
    return val if err == kAXErrorSuccess else None


def ax_children(element):
    kids = ax_get(element, kAXChildrenAttribute)
    return list(kids) if kids else []


def ax_role(element):
    return ax_get(element, kAXRoleAttribute) or ""


def ax_desc(element):
    return ax_get(element, kAXDescriptionAttribute) or ""


def ax_title(element):
    return ax_get(element, kAXTitleAttribute) or ""


def walk(element, visitor, depth=0, max_depth=40):
    if depth > max_depth:
        return False
    if visitor(element, depth):
        return True
    for child in ax_children(element):
        if walk(child, visitor, depth + 1, max_depth):
            return True
    return False

# ---------------------------------------------------------------------------
# Read like state from AX tree
# ---------------------------------------------------------------------------

def get_like_state():
    """
    Returns True (liked), False (not liked), or None (button not found).
    Requires AX tree to be unlocked first.
    """
    ensure_ax_unlocked()
    pid = get_spotify_pid()
    if pid is None:
        return None

    app = AXUIElementCreateApplication(pid)
    result = [None]

    def visitor(elem, depth):
        role = ax_role(elem)
        if "Button" not in role:
            return False
        desc  = ax_desc(elem)
        title = ax_title(elem)
        label = desc or title
        if label in UNLIKE_LABELS:
            result[0] = True   # "Remove from Liked Songs" → IS liked
            return True
        if label in LIKE_LABELS:
            result[0] = False  # "Add to Liked Songs" → NOT liked
            return True
        return False

    walk(app, visitor)
    return result[0]

# ---------------------------------------------------------------------------
# Toggle like via official keyboard shortcut Alt+Shift+B
# ---------------------------------------------------------------------------
# This is Spotify's own documented shortcut. CGEvent sends it directly to
# the Spotify process regardless of which window is focused.

# macOS virtual key code for 'B'
_KEYCODE_B = 11

def send_like_shortcut():
    """
    Send Alt+Shift+B to Spotify's process.
    This is Spotify's official Like/Unlike shortcut (all platforms).
    """
    pid = get_spotify_pid()
    if pid is None:
        print("\n  Spotify is not running.")
        return False

    flags = kCGEventFlagMaskAlternate | kCGEventFlagMaskShift

    # Key down
    event_down = CGEventCreateKeyboardEvent(None, _KEYCODE_B, True)
    CGEventSetFlags(event_down, flags)
    # Key up
    event_up = CGEventCreateKeyboardEvent(None, _KEYCODE_B, False)
    CGEventSetFlags(event_up, flags)

    CGEventPost(kCGHIDEventTap, event_down)
    time.sleep(0.05)
    CGEventPost(kCGHIDEventTap, event_up)
    return True


def toggle_like():
    with _lock:
        uri  = current_track["uri"]
        name = current_track["name"]

    if not uri:
        print("\n  No track playing yet.")
        return

    ok = send_like_shortcut()
    if not ok:
        return

    # Re-read state after toggle
    time.sleep(0.6)
    new_state = get_like_state()

    with _lock:
        if current_track["uri"] == uri:
            current_track["liked"] = new_state

    if new_state is True:
        print(f"\n  ❤️  Liked: {name}")
    elif new_state is False:
        print(f"\n  💔  Unliked: {name}")
    else:
        # AX read failed but shortcut was sent — optimistically flip
        with _lock:
            prev = current_track["liked"]
            guessed = (not prev) if prev is not None else None
            current_track["liked"] = guessed
        print(f"\n  Toggled (like state unconfirmed): {name}")

    print_status()

# ---------------------------------------------------------------------------
# Discovery mode
# ---------------------------------------------------------------------------

def run_discover():
    print()
    print("  Spotify AX Tree Discovery (with Electron unlock)")
    print("  " + "=" * 50)
    print()

    if not AXIsProcessTrusted():
        print("  ERROR: Accessibility not granted.")
        print("  System Settings → Privacy & Security → Accessibility → add your terminal\n")
        sys.exit(1)

    pid = get_spotify_pid()
    if pid is None:
        print("  ERROR: Spotify is not running.\n")
        sys.exit(1)

    print(f"  Spotify PID: {pid}")
    print("  Setting AXEnhancedUserInterface + AXManualAccessibility...")
    ensure_ax_unlocked()
    print("  Waiting 2s for Chromium to build the tree...")
    time.sleep(2)
    print("  Walking tree...\n")

    app = AXUIElementCreateApplication(pid)
    found_labeled = []
    found_buttons = []
    total = [0]

    def visitor(elem, depth):
        total[0] += 1
        role  = ax_role(elem)
        desc  = ax_desc(elem)
        title = ax_title(elem)
        label = desc or title
        indent = "  " * depth

        if label:
            found_labeled.append(f"  {indent}[{role}] desc={desc!r}  title={title!r}")
        if "Button" in role or "button" in role:
            found_buttons.append(f"  {indent}[{role}] desc={desc!r}  title={title!r}")
        return False

    walk(app, visitor, max_depth=40)

    print(f"  Total elements visited: {total[0]}")
    print(f"  Elements with labels:   {len(found_labeled)}")
    print(f"  Button elements:        {len(found_buttons)}")
    print()

    if found_buttons:
        print("  --- BUTTONS ---")
        for line in found_buttons:
            print(line)
        print()

    print("  --- ALL LABELED (first 60) ---")
    for line in found_labeled[:60]:
        print(line)
    if len(found_labeled) > 60:
        print(f"  ... and {len(found_labeled) - 60} more")

    print()
    if not found_buttons and not found_labeled:
        print("  The AX tree appears empty even after unlocking.")
        print("  Spotify may be blocking AXEnhancedUserInterface.")
        print("  The keyboard shortcut (Alt+Shift+B) for toggling will still work.")
        print("  Reading like state may not be possible via AX on this Spotify version.")

# ---------------------------------------------------------------------------
# Display
# ---------------------------------------------------------------------------

def liked_str(liked):
    if liked is True:  return "❤️  liked"
    if liked is False: return "🖤  not liked"
    return "❓  unknown"


def print_status():
    with _lock:
        t = current_track.copy()
    w = 51
    name   = t["name"][:w-2]
    artist = f"{t['artist']} · {t['album']}"[:w-2]
    like   = liked_str(t["liked"])
    print()
    print(f"  ┌{'─'*w}┐")
    print(f"  │  {name:<{w-2}}│")
    print(f"  │  {artist:<{w-2}}│")
    print(f"  │  {like:<{w-2}}│")
    print(f"  └{'─'*w}┘")
    print("  [L] toggle like   [Q] quit")

# ---------------------------------------------------------------------------
# NSDistributedNotification listener (track change detection)
# ---------------------------------------------------------------------------

class SpotifyObserver(NSObject):
    def handleNotification_(self, notification):
        info = notification.userInfo()
        if not info or info.get("Player State", "") != "Playing":
            return

        track_uri = info.get("Track ID", "")
        name      = str(info.get("Name",   "--"))
        artist    = str(info.get("Artist", "--"))
        album     = str(info.get("Album",  "--"))

        with _lock:
            same = (track_uri == current_track["uri"])
        if same:
            return

        with _lock:
            current_track["uri"]    = track_uri
            current_track["name"]   = name
            current_track["artist"] = artist
            current_track["album"]  = album
            current_track["liked"]  = None

        print(f"\n  ▶  {name} — {artist}")
        threading.Thread(target=_fetch_and_show, daemon=True).start()


def _fetch_and_show():
    time.sleep(0.8)
    with _lock:
        uri = current_track["uri"]
    if not uri:
        return
    liked = get_like_state()
    with _lock:
        if current_track["uri"] == uri:
            current_track["liked"] = liked
    print_status()

# ---------------------------------------------------------------------------
# Notification listener loop
# ---------------------------------------------------------------------------

def start_listener():
    observer = SpotifyObserver.alloc().init()
    center   = NSDistributedNotificationCenter.defaultCenter()
    center.addObserver_selector_name_object_(
        observer,
        objc.selector(observer.handleNotification_, signature=b"v@:@"),
        "com.spotify.client.PlaybackStateChanged",
        None,
    )
    print("  Listening for track changes...\n")
    loop = NSRunLoop.currentRunLoop()
    while True:
        loop.runUntilDate_(NSDate.dateWithTimeIntervalSinceNow_(0.3))

# ---------------------------------------------------------------------------
# Keyboard
# ---------------------------------------------------------------------------

def keyboard_loop():
    import tty, termios
    fd  = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        while True:
            ch = sys.stdin.read(1).lower()
            if ch == "l":
                threading.Thread(target=toggle_like, daemon=True).start()
            elif ch == "q":
                print("\n\n  Bye!\n")
                os._exit(0)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    if "--discover" in sys.argv:
        run_discover()
        return

    print()
    print("  Spotify Like Tracker")
    print("  (CGEvent shortcut + AX tree, no API keys needed)")
    print()

    if not AXIsProcessTrusted():
        print("  ❌ Accessibility permission not granted.")
        print("  System Settings → Privacy & Security → Accessibility")
        print("  → Add your terminal and enable it, then re-run.\n")
        sys.exit(1)

    pid = get_spotify_pid()
    if pid is None:
        print("  ⚠️  Spotify is not running. Please open it.\n")
    else:
        print(f"  ✅ Spotify found (PID {pid})")
        ensure_ax_unlocked()

    print("  ✅ Accessibility OK")
    print()
    print("  Note: like state shown as ❓ means the AX tree read failed.")
    print("  Toggling with [L] still works via keyboard shortcut regardless.")
    print()

    threading.Thread(target=keyboard_loop, daemon=True).start()
    start_listener()


if __name__ == "__main__":
    main()
