import ctypes, glob, os, sys, time, traceback
from ctypes import wintypes
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import records

u, g = ctypes.windll.user32, ctypes.windll.gdi32
g.GetPixel.restype = ctypes.c_uint32
u.FindWindowW.argtypes = [wintypes.LPCWSTR, wintypes.LPCWSTR]
CELL, ROW, MAXLEN = 4, 64, 60
LOG = Path(__file__).resolve().parent / "watcher.log"


def note(msg):
    with open(LOG, "a", encoding="utf-8") as fh:
        fh.write(time.strftime("%Y-%m-%d %H:%M:%S ") + msg + "\n")


def window():
    return u.FindWindowW("GxWindowClass", None) or u.FindWindowW(None, "World of Warcraft")


def read(h):
    pt = wintypes.POINT(0, 0)
    u.ClientToScreen(h, ctypes.byref(pt))
    dc = u.GetDC(0)
    try:
        def cell(i):
            c = g.GetPixel(dc, pt.x + (i % ROW) * CELL + CELL // 2, pt.y + (i // ROW) * CELL + CELL // 2)
            return None if c == 0xFFFFFFFF else ((c & 255) > 127) * 4 + ((c >> 8 & 255) > 127) * 2 + ((c >> 16 & 255) > 127)
        head = [cell(i) for i in range(5)]
        if None in head or head[:2] != [5, 2]:
            return None
        n = head[3] * 8 + head[4]
        if not 0 < n <= MAXLEN:
            return None
        v = head + [cell(i) for i in range(5, 6 + 3 * n)]
        return None if None in v else v
    finally:
        u.ReleaseDC(0, dc)


def decode(v):
    n = v[3] * 8 + v[4]
    if v[:2] != [5, 2] or len(v) != 6 + 3 * n or v[-1] != sum(v[2:-1]) % 8:
        return None
    return v[2], bytes(v[5 + 3 * i] * 64 + v[6 + 3 * i] * 8 + v[7 + 3 * i] for i in range(n)).decode("utf-8", "replace")


def rebuild():
    logs = sorted(glob.glob(str(records.WOW / "Logs" / "WoWCombatLog*.txt")))
    if not logs:
        note("no combat logs yet")
        return
    recs = records.build(logs)
    records.write(recs, records.WOW / "Interface" / "AddOns")
    note("rebuilt %d boss records" % sum(len(b) for b in recs.values()))


if __name__ == "__main__":
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(2)
    except Exception:
        pass
    note("watching for Metails signals")
    last = None
    while True:
        try:
            h = window()
            v = read(h) if h else None
            d = decode(v) if v else None
            if d is None:
                last = None
            elif d[0] != last:
                last = d[0]
                if d[1] == "metails=records":
                    time.sleep(2)
                    rebuild()
        except Exception:
            note(traceback.format_exc())
        time.sleep(0.2)
