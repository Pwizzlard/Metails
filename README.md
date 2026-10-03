# Metails!

A personal combat meter for WoW Forever. It tracks you and your pets, and nobody else.

No raid syncing, no comparing yourself to the group, no plugin system. One small window that answers "how did I do?" and gets out of the way.

## Features

- Sixteen views: damage, healing, damage taken by spell or by attacker, healing taken, overhealing, damage prevented, resources gained, interrupts, dispels, casts, killing blows, buff and debuff uptime, CC breaks and a death log.
- Per-second rates for damage and healing, overall and per spell.
- Hover a row for hits, crits, normal and crit averages, min and max, overkill, dodges and parries, and the top five targets.
- Pets merge into your totals with their name on the row, or grouped into one row per pet, or ignored.
- Absorbed damage counts as damage done, so shields don't shrink your numbers.
- Fight segments: the current fight, an overall total, and the last eleven fights. Boss fights are named after the boss and marked as wipes when they are.
- Report any view to say, party, raid, guild or a whisper.
- Open a second window to watch damage and healing at once.
- Hide automatically in or out of combat, change rows, opacity, bar texture and font size.
- Tiny footprint. No libraries, no per-event allocations, and everything it saves is validated on load.

## Views

| View | What it shows |
| --- | --- |
| Damage Done | Damage by spell, with DPS |
| Damage Taken | Damage you took, by spell and attacker |
| Damage Taken by Source | Damage you took, by attacker |
| Healing Done | Effective healing by spell, with HPS |
| Healing Taken | Healing you received, by spell and healer |
| Overhealing | Wasted healing by spell |
| Damage Prevented | Damage your absorbs soaked, by shield |
| Resources Gained | Mana, rage, energy and other power gained, by spell |
| Interrupts | Successful interrupts by spell |
| Dispels | Dispels and spell steals by spell |
| Casts | Spells you cast, by count |
| Killing Blows | Enemies you or your pet finished off |
| Buff Uptime | Buffs on you, in seconds and percent of fight time |
| Debuff Uptime | Your debuffs on enemies, in seconds and percent of fight time |
| CC Breaks | Crowd control you broke, and what broke it |
| Deaths | The last 30 seconds before your most recent death, with your health after each hit |

## Controls

| Action | Result |
| --- | --- |
| Left-click | Next view (shift for previous) |
| Right-click | Menu: pick a view or segment, report to chat, lock, reset |
| Mouse wheel | Next or previous fight segment |
| Drag | Move the window |
| Hover a row | Details for that spell |

A keybind to show or hide the window is under Key Bindings, AddOns, Metails!.

## Commands

```
/metails                      Show or hide the window
/metails report [where] [n]   Post the top n rows (default 5) to say, party, raid, guild, or a player name
/metails new                  Open another window
/metails close                Close the last window
/metails reset                Clear all data
/metails lock                 Lock or unlock window positions
/metails scale 1.2            Resize the windows
/metails rows 15              Rows per window
/metails alpha 0.4            Background opacity, 0 to 1
/metails fontsize 12          Row font size
/metails texture smooth       Bar texture: smooth, flat or raid
/metails autohide combat      Hide in combat, out of combat (ooc), or off
/metails pets rows            Pet rows alongside yours, grouped per pet, or off
```

## Install

Grab the latest release from the [releases page](https://github.com/Pwizzlard/Metails/releases) and unzip it into `World of Warcraft\_classic_beta_\Interface\AddOns`. You should end up with `Interface\AddOns\Metails\Metails.toc`.

Addon managers that read GitHub releases, like Forever Addon Manager, can install and update it for you.

## Development

The addon is one Lua file with no dependencies. A quick self-check runs outside the game:

```
pip install lupa
python test_metails.py
```

To cut a release, bump `## Version` in the TOC and run `python release.py`. It builds the zip and `release.json` and publishes them with the GitHub CLI.

## License

MIT. See [LICENSE](LICENSE).
