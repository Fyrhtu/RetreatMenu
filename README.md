# RetreatMenu

[![Release](https://img.shields.io/github/v/release/Fyrhtu/RetreatMenu)](https://github.com/Fyrhtu/RetreatMenu/releases)

Lightweight travel / hearth dropdown for **Project Ascension** (Wrath 3.3.5 / Conquest of Azeroth).

A single draggable **Travel** button that lists stones and runes of retreat, scrolls, hearth replacements, bag items (hearthstone, travel permit, fel gateway, flight whistle), and vanity-collection delivery when an item is not in bags.

Built for **very low memory** — no Ace, no Dewdrop, one Lua file.

**Repository:** https://github.com/Fyrhtu/RetreatMenu

## Creator

Created by **[Fyrhtu](https://github.com/Fyrhtu)**.

## Install

1. Download the release zip, or clone this repo.
2. Copy the `RetreatMenu` folder into:

   ```
   <Ascension>\Launcher\resources\ascension-live\Interface\AddOns\RetreatMenu
   ```

3. Restart the client or `/reload`.

## Usage

| Action | Effect |
|--------|--------|
| **Left-click** (locked) | Open / close travel menu |
| **Right-click** | Unlock / lock position |
| **Drag** (while unlocked) | Move the button (purple edge while unlocked) |
| Menu idle | Auto-closes after **5 seconds** if the mouse is not over the menu or button |
| **Esc** | Closes the menu (UI special frame) |

Slash commands:

- `/retreatmenu` or `/rmenu` — toggle menu / help
- `/retreatmenu reset` — reset button position

## Features

- Spellbook scan for stones / runes / scrolls of retreat
- Bound-location labels (hearth and replacement spells)
- Continent-style grouping where location is known
- Cooldown display on list rows
- Vanity collection: request deliver when item is known but not in bags
- Per-character saved position and lock state

## Requirements

- Ascension client, interface `30300` (3.3.5-era API)
- No dependencies

## License

Released for personal / community use on Ascension. Credit **Fyrhtu** if you redistribute or fork.
