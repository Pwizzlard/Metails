# Metails!

A personal combat meter for WoW Forever. It shows you and your pets, and nobody else.

No raid syncing, no comparing yourself to the group, no plugin system. One small window that answers "how did I do?" and gets out of the way.

## How it works

WoW Forever runs on the Midnight client, where addons can no longer read the combat log. Blizzard's own damage meter does the collecting and exposes it through the `C_DamageMeter` API. Metails! is a personal view over that data: it finds your row in each of Blizzard's meters and shows your spells, your targets and your deaths. That means it only ever shows what Blizzard tracks, and it costs almost nothing while you play.

During a fight the client hands addons locked numbers. Metails! still draws them live, straight onto the bars and text, and fills in sorting, percentages and tooltips the moment the numbers unlock.

## Features

- Nine views: damage done, damage taken by spell or by attacker, avoidable damage, healing, absorbs, interrupts, dispels and a death log.
- Per-second rates for damage and healing, overall and per spell.
- Hover a row for per-second, overkill and the top five targets or attackers.
- Pet spells show with the pet's name on the row.
- Fights: the current fight, the previous one, an overall total, and every fight Blizzard still holds, named after the encounter.
- Report any view to say, party, raid, guild or a whisper.
- Open a second window to watch damage and healing at once.
- Hide automatically in or out of combat, change rows, opacity, bar texture and font size.
- Minimap button, a keybind, and an entry under Options, AddOns with the command list and the main buttons.
- Boss records: kill a dungeon or raid boss without dying and your damage, rate, time and spells are saved. Next time that boss starts, a separate movable box shows up to three damage bars on one scale: Best, Previous kill, and Current, live. Previous is left out when it is the same kill as Best. Best and Previous fill by elapsed time at an even pace, so a longer Current bar means you are ahead. Turn it off with `/metails racing off`.
- Real curves from your combat log: Metails turns combat logging on whenever you enter a raid or dungeon and off when you leave. If Python is installed, double-click `autostart.bat` once in the Metails folder: Windows then runs the importer for a second once an hour, so your records are rebuilt without anything running in the background. Without Python you still get the meter and the pace race. It reads the log, builds a per-second damage curve for every boss kill, and writes them into a small `Metails_Records` addon next to Metails. After a reload, the race box plays your record's actual damage second by second instead of an even pace. The kill prints how you did and updates the record if you beat it.

## Views

| View | What it shows |
| --- | --- |
| Damage Done | Your damage by spell, with DPS |
| Damage Taken | Damage you took, by spell |
| Damage Taken by Source | Damage you took, by attacker |
| Avoidable Damage Taken | Damage Blizzard flags as avoidable, by spell |
| Healing Done | Your healing by spell, with HPS |
| Absorbs | Shields you cast, by spell |
| Interrupts | Your interrupts by spell |
| Dispels | Your dispels by spell |
| Deaths | Your most recent death, hit by hit, with your health after each |

## Controls

| Action | Result |
| --- | --- |
| Left-click | Next view (shift for previous) |
| Right-click | Menu: pick a view or fight, report to chat, lock, reset |
| Mouse wheel | Next or previous fight |
| Drag | Move the window |
| Hover a row | Details for that spell |

The minimap button shows or hides the window on left-click, opens the menu on right-click, and can be dragged around the minimap. A keybind to show or hide the window is under Key Bindings, AddOns, Metails!. The same command list and the main buttons live under Options, AddOns, Metails!.

## Commands

```
/metails                      Show or hide the window
/metails report [where] [n]   Post the top n rows (default 5) to say, party, raid, guild, or a player name
/metails new                  Open another window
/metails close                Close the last window
/metails reset                Clear Blizzard's combat data
/metails lock                 Lock or unlock window positions
/metails scale 1.2            Resize the windows
/metails rows 15              Rows per window
/metails alpha 0.4            Background opacity, 0 to 1
/metails fontsize 12          Row font size
/metails texture smooth       Bar texture: smooth, flat or raid
/metails autohide combat      Hide in combat, out of combat (ooc), or off
/metails minimap              Show or hide the minimap button
/metails diag                 Print whether the game is handing over readable numbers
/metails bests                List your boss records
/metails forget Hogger        Delete a boss record
/metails racing off           Turn the race box off (or on)
/metails autolog off          Stop logging automatically in raids and dungeons (or on)
autostart.bat                 Schedule the importer hourly (run again to remove); needs Python
python records.py             Import boss kill curves by hand instead
```

## Install

Grab the latest release from the [releases page](https://github.com/Pwizzlard/Metails/releases) and unzip it into `World of Warcraft\_classic_beta_\Interface\AddOns`. You should end up with `Interface\AddOns\Metails\Metails.toc`. Restart the game client if it was running.

Addon managers that read GitHub releases, like Forever Addon Manager, can install and update it for you.

## Development

The addon is one Lua file with no dependencies. A quick self-check runs outside the game against a fake `C_DamageMeter`:

```
pip install lupa
python test_metails.py
```

To cut a release, bump `## Version` in the TOC and run `python release.py`. It builds the zip and `release.json` and publishes them with the GitHub CLI.

## License

MIT. See [LICENSE](LICENSE).
