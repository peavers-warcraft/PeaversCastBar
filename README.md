# PeaversCastBar

[![AddonSentry](https://addonsentry.io/api/public/repos/peavers-warcraft/PeaversCastBar/badge.svg)](https://addonsentry.io/dashboard/peavers-warcraft/PeaversCastBar)

A World of Warcraft addon that replaces the default cast bars for player, target, focus and pet — and can take its width and position straight from Blizzard's Cooldown Manager.

## Features

<!-- peavers:features -->
- Clean, flat cast bars for the player, target, focus and pet, each configured independently
- **Match Cooldown Manager width** — the bar resizes itself whenever the chosen Cooldown Manager row does, so the two line up exactly
- **Attach to the Cooldown Manager** — pin the bar above or below a row so it follows it around Edit Mode
- Distinct colours for casting, channelling, uninterruptible casts and interrupts
- Latency zone on the player bar, marking the tail of the cast where recasting is already safe
- Empowered cast stage markers for Evokers
- Spell icon on either side, spell name, remaining cast time, and a moving spell spark — all optional
- Hands each unit's default Blizzard cast bar back the moment you turn that unit off, with no reload
- Vehicle-aware: the player bar follows your casts when you are driving something
- Full appearance control, and optional sync with the shared Peavers global appearance profile
<!-- /peavers:features -->

## Usage

<!-- peavers:usage -->
Open the settings with `/pcb`. The player and target bars are on out of the box; focus and pet are opt-in.

To move a bar, press **Unlock bars to drag** on any unit's page (or `/pcb unlock`) — cast bars only exist while something is being cast, so unlocking parks a preview bar on screen for every enabled unit. Drag them where you want and press **Lock bars**.

To line a bar up with your Cooldown Manager, tick **Match Cooldown Manager width** and pick a row. Add **Attach to the Cooldown Manager** if you also want the bar to follow the row when you move it in Edit Mode.

### Slash Commands

- `/pcb` - Open settings
- `/pcb unlock` - Show every bar so it can be dragged
- `/pcb lock` - Finish positioning
- `/pcb reset` - Restore every setting to its default
<!-- /peavers:usage -->

## Installation

### Recommended: PeaversUpdater

Download and install [PeaversUpdater](https://github.com/peavers-warcraft/PeaversUpdater/releases/latest), the desktop updater for the whole Peavers collection. It installs PeaversCastBar together with its required dependencies and delivers updates before they reach CurseForge.

### Alternative: CurseForge

1. Download from [CurseForge](https://www.curseforge.com/wow/addons/peaverscastbar)
2. Ensure [PeaversCommons](https://www.curseforge.com/wow/addons/peaverscommons) is also installed
3. Ensure [PeaversConfig](https://www.curseforge.com/wow/addons/peaversconfig) is also installed
4. Enable the addon on the character selection screen

---

*Part of the [Peavers](https://peavers.io) addon collection · [Report an issue](https://github.com/peavers-warcraft/PeaversCastBar/issues) · [Support development on Patreon](https://www.patreon.com/Peavers)*
