# PeaversCastBar

[![AddonSentry](https://addonsentry.io/api/public/repos/peavers-warcraft/PeaversCastBar/badge.svg)](https://addonsentry.io/dashboard/peavers-warcraft/PeaversCastBar)

An ultra-lightweight replacement for the default cast bars — player, target, focus and pet — that can take its width and position straight from Blizzard's Cooldown Manager.

**~80 KB. No bundled libraries. One widget call a frame while casting, and nothing at all when idle.**

Part of the **Peavers Ultra Performance** family: addons that do one job, do it exactly, and stay out of your frame budget.

## Built for performance

Cast bars run every single frame, so this one is measured rather than assumed. Every number below comes from driving the real code through a full cast against instrumented widget stubs:

| | |
|---|---|
| Widget calls per frame while casting | **1** (`SetValue` — the animation itself) |
| Widget calls while idle | **0** — a hidden frame gets no `OnUpdate` at all |
| Countdown text rebuilds | **10/sec**, not once per frame |
| Fill drift from true cast time | **0.000%**, even under stuttering frame times |
| Packaged size | **~80 KB**, no libraries bundled |

How it gets there:

- **The spark costs nothing.** It rides the right edge of the status bar's own fill texture, so the client moves it while resizing the fill. No per-frame anchoring.
- **The countdown only redraws when it changes.** The label shows one decimal, so the string is rebuilt ten times a second instead of once per frame — every `SetText` forces a font string to re-measure.
- **The clock is the clock.** Progress is computed from `GetTime()`, never accumulated frame deltas, so a stutter or a frame drop cannot make the bar drift out of step with the cast.
- **Events are filtered by the client, not by Lua.** Each bar registers with `RegisterUnitEvent`, so an idle raid never wakes the addon up for units it isn't showing.
- **Nothing runs when nothing is casting.** The bars are genuinely hidden, and WoW does not tick hidden frames.

## Features

<!-- peavers:features -->
- Clean, flat cast bars for the player, target, focus and pet, each configured independently
- **Match Cooldown Manager width** — the bar resizes itself whenever the chosen Cooldown Manager row does, so the two line up exactly
- **Attach to the Cooldown Manager** — pin the bar above or below a row so it follows it around Edit Mode
- Distinct colours for casting, channelling, uninterruptible casts and interrupts
- Latency zone on the player bar, marking the tail of the cast where recasting is already safe
- Empowered cast stage markers for Evokers
- Spell icon on either side, spell name, remaining cast time, and a moving spell spark — all optional
- Only the displayed cast's own events can end its bar, so mashing a spell key during a cast never kills the bar underneath it
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
