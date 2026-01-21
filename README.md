# SlotItemLevel

SlotItemLevel displays each equipped item’s item level next to the gear slots on the Character window.

## Features
- Item level shown outside the slot icons (no overlap)
- Automatically positions text:
  - Left column slots → text on the right
  - Right column slots → text on the left
- Weapon slots flare outward (main-hand left, off-hand right)
- Item level color matches item quality
- Lightweight (no OnUpdate loops)

## Commands
- `/sil debug` — toggles debug output (for troubleshooting)

## Compatibility
- Retail 12.x

## Installation
1. Download and unzip into: `World of Warcraft/_retail_/Interface/AddOns/`
2. Ensure the folder is named: `SlotItemLevel`
3. Reload the game: `/reload`

## License
MIT (see LICENSE)
