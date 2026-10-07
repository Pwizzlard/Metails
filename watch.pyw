import glob, os, sys, time, traceback
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import records

LOG = Path(__file__).resolve().parent / "watch.log"


def note(msg):
    with open(LOG, "a", encoding="utf-8") as fh:
        fh.write(time.strftime("%Y-%m-%d %H:%M:%S ") + msg + "\n")


def is_kill(line):
    f = line.split(",")
    return "ENCOUNTER_END" in line and len(f) > 5 and f[5].strip() == "1"


def rebuild():
    logs = sorted(glob.glob(str(records.WOW / "Logs" / "WoWCombatLog*.txt")))
    if not logs:
        return
    recs = records.build(logs)
    records.write(recs, records.WOW / "Interface" / "AddOns")
    note("rebuilt %d boss records" % sum(len(b) for b in recs.values()))


def main():
    note("watching " + str(records.WOW / "Logs"))
    rebuild()
    current, offset = None, 0
    while True:
        try:
            logs = sorted(glob.glob(str(records.WOW / "Logs" / "WoWCombatLog*.txt")), key=os.path.getmtime)
            if logs:
                newest = logs[-1]
                if newest != current:
                    current, offset = newest, os.path.getsize(newest)
                size = os.path.getsize(newest)
                if size > offset:
                    with open(newest, encoding="utf-8", errors="replace") as fh:
                        fh.seek(offset)
                        chunk = fh.read()
                    offset = size
                    if any(is_kill(l) for l in chunk.splitlines()):
                        time.sleep(2)
                        rebuild()
        except Exception:
            note(traceback.format_exc())
        time.sleep(5)


if __name__ == "__main__":
    main()
