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
- Appearance options for scale, width, theme, title, percentage text, and trap text
- Theme presets: `Blizzard Gold`, `Dark Minimal`, and `Predator Red`
- Reset buttons for position and appearance
- Optional zone-only visibility
- Optional display without an active Prey Hunt for setup and positioning
- Optional hiding of the default Blizzard Prey widget
- Shift-drag repositioning without lock/unlock commands
- Native in-game options panel
- Saved position and settings

## Slash Commands

- `/epp options` opens the options panel
- `/epp show` forces the addon to stay visible
- `/epp hide` hides the addon
- `/epp reset` restores the default position and settings
- `/epp zone` toggles zone-only visibility
- `/epp blizz` toggles hiding the Blizzard Prey widget

## Options Panel

Open the in-game options panel with `/epp options`.

Available options include:

- Show or hide the bar
- Show the bar without an active Prey Hunt for setup and positioning
- Only show in the active Prey zone
- Hide the default Blizzard Prey widget
- Adjust scale and width
- Select a visual theme
- Show or hide the title, percentage text, and trap text
- Reset position or appearance

## Installation

1. Place the `EasyPreyProgress` addon folder inside your `World of Warcraft/Interface/AddOns/` directory.
2. Start the game or run `/reload`.
3. Enable `EasyPreyProgress` from the AddOns list if needed.

## Notes

- The addon prefers live Blizzard data when available.
- When Blizzard does not expose a true live percentage, the bar falls back to stage-based progress.
- Stage 1 starts at `0%`, followed by `33%`, `66%`, and `100%` for later fallback stages.

## Version

Current release: `1.1.1`
