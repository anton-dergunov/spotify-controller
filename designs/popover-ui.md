# Popover player UI (approved mock)

Reference implementation: `macos/Sources/SpotifyController/Views/PlayerPopoverView.swift`  
Interactive canvas prototype: `.cursor/projects/.../canvases/spotify-popover-prototype.canvas.tsx`

## Shell

| Property | Value |
|----------|--------|
| Size | 300 × 300 pt |
| Corner radius | 14 pt |
| Idle | Album cover only (`cover.jpg`), clipped to rounded rect |
| Hover | Fade in controls (see animation) |

## Hover animation

| Phase | Duration | Delay |
|-------|----------|-------|
| Fade in | 240 ms ease | 130 ms |
| Fade out | 180 ms ease | 0 ms |

## Hover background (not flat translucency)

1. Duplicate cover image, **blur ~26 pt**, scale ~1.08× (edges hidden by clip).
2. **Blue tint** overlay on top (~42% opacity accent blue; user-customizable later).
3. White foreground controls above tint.

Swift: blurred `Image` + `Color` tint layer; optional `NSVisualEffectView` when moving to menu bar popover.

## Typography (centered, white / muted white)

| Element | Position | Size | Weight |
|---------|----------|------|--------|
| Artist | Above play | 14 pt | Semibold |
| Song | Below transport | 15 pt | Semibold |
| Album (year) | Below song | 11 pt | Regular, muted |

Sample copy: **Khruangbin** · **Time (You and I)** · **Mordechai (2020)**

## Controls layout

```
[♥ like]                              [⚙ settings]   ← top corners, 40×40 hit, 20px icons
              Artist
   [⏮ skip]      ( ▶ play )      [⏭ skip]          ← skip at L/R; play 56×56 center
              Song title
           Album (year)
──────────────────────────────────────
         scrubber (bottom, full width)
         elapsed              total
```

- **Like**: top-left. **Settings** (gear): top-right.
- **Skip previous / next**: standard media icons at horizontal corners, vertically aligned with play.
- **Play/pause**: center, 56 pt circle, white icon, light white ring fill.
- **Scrubber**: pinned to bottom; 5 pt track; white thumb.

## Customization (future settings)

- Control foreground color (default white)
- Tint color / opacity
- Blur radius

## Menu bar (later)

Same `PlayerPopoverView` inside `MenuBarExtra` popover; menu bar shows artist + song (two lines) and compact actions.
