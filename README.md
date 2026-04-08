# EasyPreyProgress

EasyPreyProgress is a compact World of Warcraft addon that shows a clean progress bar for your active Prey Hunt.

It is designed to stay readable during normal gameplay, avoid unnecessary clutter, and surface the most useful hunt information at a glance.

## Features

- Compact Blizzard-inspired Prey Hunt progress bar
- Live percentage tracking when Blizzard provides it
- Stage fallback display when no live percentage is available
- Simple `Stage X/4` readout
- Nearby trap text when detected
- Stage-based bar coloring
- Optional zone-only visibility
- Optional hiding of the default Blizzard Prey widget
- Shift-drag repositioning while unlocked
- Saved position and settings

## Slash Commands

- `/epp unlock` enables moving the bar
- `/epp lock` locks the bar in place
- `/epp show` forces the addon to stay visible
- `/epp hide` hides the addon
- `/epp reset` restores the default position and settings
- `/epp zone` toggles zone-only visibility
- `/epp blizz` toggles hiding the Blizzard Prey widget

## Installation

1. Place the `EasyPreyProgress` addon folder inside your `World of Warcraft/Interface/AddOns/` directory.
2. Start the game or run `/reload`.
3. Enable `EasyPreyProgress` from the AddOns list if needed.

## Notes

- The addon prefers live Blizzard data when available.
- When Blizzard does not expose a true live percentage, the bar falls back to stage-based progress.
- Stage 1 starts at `0%`, followed by `33%`, `66%`, and `100%` for later fallback stages.

## Version

Current release: `1.0.0`
