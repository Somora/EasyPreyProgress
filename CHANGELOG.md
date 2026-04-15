# EasyPreyProgress Changelog
All notable changes to this project will be documented in this file.

## Version 1.1.0 (15/04/2026)
- Added a native in-game options panel for EasyPreyProgress.
- Added `/epp options`, `/epp config`, and `/epp settings` to open the options panel.
- Added settings for showing the bar, zone-only visibility, showing the bar without an active Prey Hunt, hiding the default Blizzard Prey widget, and resetting the bar position.
- Added appearance settings for scale, width, theme, title visibility, percentage text, and trap text.
- Added `Blizzard Gold`, `Dark Minimal`, and `Predator Red` theme presets.
- Added a reset appearance button.
- Polished the options panel layout and theme dropdown spacing.
- Simplified movement: the bar can now be moved by holding `Shift` and dragging, without using a lock or unlock command.
- Removed lock/unlock from the public command flow.
- Removed internal debug and inspection slash commands from the public addon build.

## Version 1.0.1 (08/04/2026)
- Improved Blizzard Prey widget suppression to more reliably hide leftover visual elements.
- Added safer handling for Blizzard widget model scenes tied to Prey Hunt UI remnants.
- Refined stage fallback percentages so Stage 1 starts at `0%` instead of appearing partially completed.
- Simplified the stage line to show only `Stage X/4` for a cleaner and more compact display.
- Improved trap text presentation by placing it on its own line beneath the stage.
- Continued visual polish for the bar, title, spacing, and colors.

## Version 1.0.0 (08/04/2026)
- First public release of EasyPreyProgress.
- Added a compact Prey Hunt progress bar with live stage tracking.
- Added stage-based fallback progress when Blizzard does not provide a live percentage.
- Added nearby trap text detection from the live Prey widget and quest text when available.
- Added automatic prey-zone visibility checks with safer subzone handling.
- Added support for hiding the default Blizzard Prey widget.
- Added Shift-drag repositioning and saved bar position.
- Added stage-aware colors and a polished Blizzard-inspired visual style.
- Added slash commands for visibility, locking, reset, debug output, zone-only mode, and Blizzard widget toggling.
