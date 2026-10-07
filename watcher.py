import glob, time

import records

KINDS = ("metails",)


def handle(payload, pixel):
    if payload != "metails=records":
        return
    time.sleep(2)
    logs = sorted(glob.glob(str(records.WOW / "Logs" / "WoWCombatLog*.txt")))
    if logs:
        records.write(records.build(logs), records.WOW / "Interface" / "AddOns")
