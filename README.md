# HackrLFG

A compact, modern group browser for **WoW Forever**. Every listing is one clean row with the party laid out the same way every time: **Tank, Healer, DPS, DPS, DPS**, each with its class icon and level.

Part of the Hackr family of add-ons, alongside HackrAH.

## Features

- **Fixed role layout.** Every group reads Tank / Healer / DPS / DPS / DPS. Filled slots show the class icon and level on a role colour (Tank blue, Healer green, DPS red). Open slots stay in place, so you can see at a glance what a group is missing.
- **Multi-role players.** Solo players who signed up for more than one role get a split chip (e.g. half blue, half red for Tank or DPS). They always sit in the Tank or Healer slot when they offer one, because those are the hard roles to find.
- **10-player groups.** UBRS and raids get two rows of slots, two full parties, plus a headcount line like `6/10 · 1 Tank · 2 Healers · 3 DPS`.
- **Every listing, not just your level.** Blizzard's finder only searches dungeons in your level range. HackrLFG searches the whole category, or the one dungeon you pick.
- **Dungeon picker.** All dungeons, "Around my level", or any single dungeon, sorted by level with its range shown.
- **Filter box.** Narrow the list by player name, dungeon or zone. Several words must all match; `-word` excludes.
- **Sort by age.** Click AGE for newest first or oldest first.
- **List yourself in one click.** Pick your roles and a dungeon, hit List me. Update or remove your listing from the same panel.
- **Quick actions.** Click a row to whisper the leader. Shift-click a solo player to invite them. Hover for full notes and the member list.

## Usage

Opens next to the Group Finder (`I`), or on its own with:

| Command | What it does |
|---|---|
| `/hlfg` (or `/hackrlfg`, `/gl`) | Show or hide the window |
| `/hlfg auto` | Turn opening with the Group Finder on or off |
| `/hlfg reset` | Move the window back to its default spot |
| `/hlfg help` | List these commands |

## Known limits

- **Notes and titles can't be searched or written by add-ons.** The game hands listing notes to add-ons only as protected tokens. HackrLFG shows them on each row and in the tooltip, but can't filter by them. Add notes to your own listing in Blizzard's Group Finder; HackrLFG's Update button keeps them.
- **Inside dungeons and raids** the game hides some listing details from add-ons. HackrLFG falls back gracefully instead of erroring.

## Install

Install from CurseForge, or copy the `HackrLFG` folder into `World of Warcraft\_forever_\Interface\AddOns\` and restart the game.

## License

MIT. See [LICENSE](LICENSE).
