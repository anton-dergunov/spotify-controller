# spotify-controller

macOS Spotify helper: a **SwiftUI player UI** (menu bar app later) and a **Python CLI** for liked-state control.

## macOS app (SwiftUI)

Place album art at **`cover.jpg`** in this directory (repo root), then:

```bash
make run
```

See [macos/README.md](macos/README.md) and [designs/popover-ui.md](designs/popover-ui.md).

---

## Python CLI

CLI tool that prints whether the song currently playing in the **Spotify desktop app** is in your library / liked.

## Requirements

- macOS with [Spotify](https://www.spotify.com/download/mac/) desktop playing a track
- A Chromium browser where you are signed in at [open.spotify.com](https://open.spotify.com/) (Chrome, Brave, or Edge)
- Python 3.10+

## Setup

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
playwright install chromium
```

Grant **Automation** access for your terminal to **Spotify** and **Google Chrome** when macOS prompts you (System Settings → Privacy & Security → Automation).

Optional fast path: in Chrome, enable **Develop → Allow JavaScript from Apple Events** so an already-open track tab can be read without launching headless Chromium.

## Usage

```bash
python spotify_liked.py              # same as status — prints yes or no
python spotify_liked.py status
python spotify_liked.py toggle       # flip liked state; prints new yes or no
python spotify_liked.py like         # like if needed; prints yes
python spotify_liked.py unlike       # unlike if needed; prints no
```

Stdout is always `yes` or `no`; errors go to stderr.

## How it works

1. Reads the current track ID from the Spotify app via AppleScript.
2. Opens that track on the Spotify web player using your browser login cookies (no Spotify Developer API).
3. Reads the save/like button `aria-checked` state on the track page.

Errors are written to stderr; stdout is only `yes` or `no`.
