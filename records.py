import csv, glob, json, os, re, sys
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
WOW = Path(os.environ.get("WOW_FOREVER") or (HERE.parents[2] if HERE.parent.name == "AddOns" else r"C:\Program Files (x86)\World of Warcraft\_classic_beta_"))
DAMAGE = {"SWING_DAMAGE", "RANGE_DAMAGE", "SPELL_DAMAGE", "SPELL_PERIODIC_DAMAGE", "DAMAGE_SHIELD", "DAMAGE_SPLIT"}
FACING = re.compile(r"^-?\d+\.\d{4}$")


def amount_of(f):
    for i in range(len(f) - 3, 10, -1):
        if FACING.match(f[i]) and f[i - 1].isdigit() and "." in f[i - 2] and "." in f[i - 3]:
            return int(f[i + 2])
    return 0


def parse(path):
    kills, enc = [], None
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if "  " not in line:
                continue
            stamp, body = line.rstrip("\n").split("  ", 1)
            f = next(csv.reader([body]))
            ev = f[0]
            if ev == "ENCOUNTER_START":
                enc = {"name": f[2], "t0": ts(stamp), "hits": [], "died": set(), "players": {}}
            elif ev == "ENCOUNTER_END" and enc:
                if f[5] == "1":
                    enc["t1"], enc["date"] = ts(stamp), stamp.split(" ")[0]
                    kills.append(enc)
                enc = None
            elif enc and ev in DAMAGE and len(f) > 8 and int(f[3], 16) & 1:
                amt = amount_of(f)
                if amt > 0:
                    enc["hits"].append((ts(stamp), amt))
                if int(f[3], 16) & 0x400:
                    enc["players"][f[1]] = f[2].split("-")[0]
            elif enc and ev == "UNIT_DIED" and len(f) > 7 and f[5].startswith("Player-"):
                enc["died"].add(f[5])
    return kills


def ts(stamp):
    d, t = stamp.split(" ")[:2]
    t = t.split("-")[0].split("+")[0]
    return datetime.strptime(d + " " + t, "%m/%d/%Y %H:%M:%S.%f").timestamp()


def curve(enc):
    n = int(enc["t1"] - enc["t0"]) + 1
    out = [0] * n
    for t, amt in enc["hits"]:
        out[min(n - 1, max(0, int(t - enc["t0"])))] += amt
    for i in range(1, n):
        out[i] += out[i - 1]
    return out


def build(paths):
    records = {}
    for path in paths:
        for enc in parse(path):
            if not enc["players"]:
                continue
            guid, name = next(iter(enc["players"].items()))
            c = curve(enc)
            rec = {"total": c[-1], "time": round(enc["t1"] - enc["t0"], 1), "rate": round(c[-1] / max(enc["t1"] - enc["t0"], 1), 1),
                   "date": datetime.strptime(enc["date"], "%m/%d/%Y").strftime("%Y-%m-%d"), "at": enc["t1"], "curve": c, "died": guid in enc["died"]}
            e = records.setdefault(name, {}).setdefault(enc["name"], {})
            if not e.get("last") or rec["at"] > e["last"]["at"]:
                e["last"] = rec
            if not rec["died"] and (not e.get("best") or rec["total"] > e["best"]["total"]):
                e["best"] = rec
    return records


def lua(v):
    if isinstance(v, dict):
        return "{" + ",".join("[%s]=%s" % (lua(k), lua(x)) for k, x in v.items()) + "}"
    if isinstance(v, list):
        return "{" + ",".join(lua(x) for x in v) + "}"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    return json.dumps(v)


def write(records, addons):
    out = addons / "Metails_Records"
    out.mkdir(parents=True, exist_ok=True)
    (out / "Metails_Records.toc").write_text("## Interface: 16001\n## Title: Metails! Records\n## Notes: Boss kill curves imported from your combat logs by records.py\n## Author: Pwizzlard\nRecords.lua\n", encoding="utf-8")
    (out / "Records.lua").write_text("MetailsRecords = " + lua(records) + "\n", encoding="utf-8")
    return out


if __name__ == "__main__":
    logs = sorted(glob.glob(str(WOW / "Logs" / "WoWCombatLog*.txt")))
    if not logs:
        sys.exit("No combat logs found. Type /combatlog in game before a raid.")
    records = build(logs)
    out = write(records, WOW / "Interface" / "AddOns")
    kills = sum(len(bosses) for bosses in records.values())
    print(f"{kills} boss records for {', '.join(records) or 'nobody'} written to {out}. Type /reload in game.")
