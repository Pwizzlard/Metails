# Metails

A personal combat meter for WoW Forever. It tracks you and your pets, and nobody else.

No raid syncing, no comparing yourself to the group, no plugin system. One small window that answers "how did I do?" and gets out of the way.

## Features

- Eleven views in one window: damage, healing, damage taken, overhealing, damage prevented, interrupts, dispels, casts, buff uptime, CC breaks and a death log.
- Per-second rates for damage and healing, both overall and per spell.
- Pet and guardian damage merges into your totals, labelled with the pet's name.
- Absorbed damage counts as damage done, so shields don't shrink your numbers.
- Fight segments: the current fight, an overall total, and the last eleven fights, each named after the first enemy you hit.
- Hover any row for hits, crits, average and biggest hit.
- Tiny footprint. No libraries, no per-event allocations, and everything it saves is validated on load.

## Views

| View | What it shows |
| --- | --- |
| Damage Done | Damage by spell, with DPS |
| Damage Taken | Damage you took, by spell and attacker |
| Healing Done | Effective healing by spell, with HPS |
| Overhealing | Wasted healing by spell |
| Damage Prevented | Damage your absorbs soaked, by shield |
| Interrupts | Successful interrupts by spell |
| Dispels | Dispels and spell steals by spell |
| Casts | Spells you cast, by count |
| Buff Uptime | Buffs on you, in seconds and percent of fight time |
| CC Breaks | Crowd control you broke, and what broke it |
| Deaths | The last 30 seconds before your most recent death, with your health after each hit |

## Controls

| Action | Result |
| --- | --- |
| Left-click | Next view |
| Right-click or mouse wheel | Next fight segment |
| Drag | Move the window |
| Hover a row | Details for that spell |

## Commands

```
/metails            Show or hide the window
/metails reset      Clear all data
/metails lock       Lock or unlock the window position
/metails scale 1.2  Resize the window
```

## Install

Grab the latest release from the [releases page](https://github.com/Pwizzlard/Metails/releases) and unzip it into `World of Warcraft\_classic_beta_\Interface\AddOns`. You should end up with `Interface\AddOns\Metails\Metails.toc`.

Addon managers that read GitHub releases, like Forever Addon Manager, can install and update it for you.

## Development

The addon is two files with no dependencies. A quick self-check runs outside the game:

```
pip install lupa
python test_metails.py
```

To cut a release, bump `## Version` in the TOC and run `python release.py`. It builds the zip and `release.json` and publishes them with the GitHub CLI.

## License

MIT. See [LICENSE](LICENSE).
