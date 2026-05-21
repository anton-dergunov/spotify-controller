# Harmonic

A minimal, distraction-free Spotify playback controller for macOS. Control your music directly from the menu bar — no clutter, just the essentials.

<p align="center">
  <img src="assets/app.jpg" width="315" alt="Harmonic App Demo">
</p>

## Features

- **Menu bar player** — Access Spotify controls directly from your macOS menu bar
- **Quick controls** — Skip tracks, toggle like status, and view current track info at a glance
- **Borderless popover** — Open a clean 300×300 pt player window with full controls
- **Smart Spotify integration** — Uses Spotify's official Web API for reliable track management
- **Minimal design** — Stays out of your way while giving you full control

## Installation

### Download and Install

1. Download the latest `Harmonic-0.1.0.dmg` from [Releases](https://github.com/anton-dergunov/harmonic/releases)
2. Double-click to mount the DMG
3. Drag `Harmonic.app` to your Applications folder
4. Launch from Applications or Spotlight

### First Run

On first launch, you'll need to authorize Spotify access. Click the settings icon in the player window and follow the OAuth flow to connect your Spotify account.

You may also need to grant Accessibility permissions:
- System Settings → Privacy & Security → Automation
- Grant terminal/app access to Spotify

## Build Locally

Requirements:
- macOS 13+
- Xcode 15+
- Swift 5.9+

```bash
make build      # Build release version
make run        # Build and run
make debug      # Build and run debug version
make clean      # Remove build artifacts
```

The built app is located at `.build/release/Harmonic` (or `.build/debug/Harmonic` for debug builds).

## Architecture

- **SwiftUI menu bar app** — Real-time track info, transport controls, and like/unlike toggle
- **Spotify OAuth 2.0** — Official authentication for secure API access
- **System integration** — Runs as a background accessory app with no Dock icon

## Prototypes

The `prototypes/` directory contains experimental tools. See [prototypes/README.md](prototypes/README.md) for details.

## Attribution

App icon by <a href="https://www.flaticon.com/free-icons/lotus" title="lotus icons">Saifali496 - Flaticon</a>

## License

MIT
