# Harmonic

A minimal, distraction-free Spotify playback controller for macOS. Control your music directly from the menu bar — no clutter, just the essentials.

<p align="center">
  <img src="assets/app.jpg" width="315" alt="Harmonic App Demo">
</p>

## Features

- **Menu bar track info** — See artist and song name at a glance without switching apps
- **Like / unlike** — Save or remove the current track from your Liked Songs with one click
- **Skip forward** — Jump ahead in a track directly from the menu bar
- **Player window** — Click the track info to open a full player with cover art, scrub bar, and transport controls
- **Customizable menu bar** — Choose which controls appear in the menu bar strip
- **Keyboard shortcuts** — Global hotkeys to like/unlike (⌥L by default) and toggle the player window; all customizable in settings
- **Launch at Login** — Start Harmonic automatically when you log in
- **Open in Spotify** — Jump to the current track, artist, or album in the Spotify app from the player or right-click menu
- **Copy & search** — Right-click to copy the artist/song to the clipboard or look them up on Google
- **Song logging** — Optionally keep a local log of your listening history

## Installation

### Download and Install

1. Download the latest `Harmonic-0.3.0.dmg` from [Releases](https://github.com/anton-dergunov/harmonic/releases)
2. Double-click to mount the DMG
3. Drag `Harmonic.app` to your Applications folder
4. Launch from Applications or Spotlight

> [!NOTE]
> Since Harmonic is currently distributed as an unsigned macOS app (not notarized by Apple), macOS may show a warning such as:
>
> > “Apple could not verify ‘Harmonic.app’ is free of malware that may harm your Mac or compromise your privacy.”
>
> To open the app:
>
> 1. Open **System Settings → Privacy & Security**
> 2. Scroll down to the security warning for Harmonic
> 3. Click **Open Anyway**
> 4. Confirm by clicking **Open**
>
> After this one-time confirmation, the app will launch normally.

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

## Prototypes

The `prototypes/` directory contains experimental tools. See [prototypes/README.md](prototypes/README.md) for details.

## Attribution

App icon by <a href="https://www.flaticon.com/free-icons/lotus" title="lotus icons">Saifali496 - Flaticon</a>

## License

MIT
