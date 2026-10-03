# Metails

A personal combat meter for WoW Forever. Tracks only you (and your pets), nobody else.

Modes: Damage Done, Damage Taken, Healing Done, Overhealing, Damage Prevented, Interrupts, Dispels, Casts, Buff Uptime, CC Breaks, Deaths.
Deaths shows the last 30 seconds before your most recent death in the viewed segment, with your health after each hit.
Segments: current fight, overall, and the last 11 fights.

Controls: left-click cycles mode, right-click or mouse wheel cycles segment, drag to move. Hover a row for hits, crits, average, max.

`/metails` toggle, `/metails reset`, `/metails lock`, `/metails scale 1.2`

Install: copy this folder to `Interface\AddOns\Metails`.
Test: `python test_metails.py` (needs `pip install lupa`).
