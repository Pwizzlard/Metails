import lupa, pathlib

L = lupa.LuaRuntime()
L.execute(r"""
now, incombat, chat, resets = 100, false, {}, 0
GetTime = function() return now end
UnitAffectingCombat = function() return incombat end
C_Spell = { GetSpellTexture = function(id) return id == SECRET and "tex?" or "tex" .. id end, GetSpellName = function(id) return id == SECRET and "Spell?" or "Spell" .. id end }
tickers = {}
C_Timer = { NewTicker = function(_, fn) tickers[#tickers + 1] = fn end }
SECRET = setmetatable({}, { __tostring = function() return "SECRET" end })
local function S(v) return incombat and SECRET or v end
AbbreviateNumbers = function(v) return v == SECRET and "~" or tostring(v) end
UnitClass = function() return "Mage", "MAGE" end
UnitGUID = function() return "Player-1" end
RAID_CLASS_COLORS = { MAGE = { r = 0, g = 0, b = 1 } }
GameTooltip_Hide = function() end
IsShiftKeyDown, IsInRaid, IsInGroup = function() return false end, function() return false end, function() return true end
SendChatMessage = function(msg, chan, _, target) chat[#chat + 1] = { msg, chan, target } end
wipe = function(t) for k in pairs(t) do t[k] = nil end end
issecretvalue = function(v) return v == SECRET end
SlashCmdList = {}
Enum = { DamageMeterType = { Dps = 0, DamageDone = 1, DamageTaken = 2, AvoidableDamageTaken = 3, Hps = 4, HealingDone = 5, Absorbs = 6, Interrupts = 7, Dispels = 8, Deaths = 9 },
         DamageMeterSessionType = { Current = 0, Overall = 1, Expired = 2 } }
local function me() return { name = "Sam", sourceGUID = "Player-1", isLocalPlayer = true, totalAmount = S(1500), amountPerSecond = S(150), deathRecapID = 7 } end
local bob = { name = "Bob", sourceGUID = "Player-2", isLocalPlayer = false, totalAmount = 3000, amountPerSecond = 300 }
lastQuery = {}
C_DamageMeter = {
  GetCombatSessionFromType = function(st, mt) lastQuery = { st = st, mt = mt }; if mt == 3 or mt == 6 then return { combatSources = { bob }, durationSeconds = 10 } end; return { combatSources = { bob, me() }, durationSeconds = 10 } end,
  GetCombatSessionFromID = function(id, mt) lastQuery = { id = id, mt = mt }; return { combatSources = { me() }, durationSeconds = 5 } end,
  GetCombatSessionSourceFromType = function(st, mt, guid) return { combatSpells = {
    { spellID = S(133), totalAmount = S(1200), amountPerSecond = S(120), overkillAmount = S(50), combatSpellDetails = { { unitName = "Hogger", amount = 1000 }, { unitName = "Boar", amount = 200 }, { unitName = "", amount = 0 }, { unitName = "Ghost", amount = 0 } } },
    { spellID = 1, totalAmount = 300, amountPerSecond = 30, creatureName = "Kitty", combatSpellDetails = { unitName = "Hogger", amount = 300 } },
    { spellID = 2, totalAmount = 0 } } } end,
  GetCombatSessionSourceFromID = function(id, mt, guid) return { combatSpells = { { spellID = 133, totalAmount = 10, amountPerSecond = 2 } } } end,
  GetAvailableCombatSessions = function() return { { sessionID = 11, name = "Hogger" }, { sessionID = 12, name = "" } } end,
  ResetAllCombatSessions = function() resets = resets + 1 end,
}
C_DeathRecap = {
  GetRecapEvents = function(id) return { { event = "SPELL_DAMAGE", spellId = 10, spellName = "Bite", amount = 500, currentHP = 250, timestamp = 141, overkill = 10 },
                                         { event = "SPELL_HEAL", spellName = "Bandage", amount = 100, currentHP = 750, timestamp = 140 } } end,
  GetRecapMaxHealth = function(id) return 1000 end,
}
local function stub()
  local s = { scripts = {} }
  return setmetatable(s, { __index = function(t, k)
    if k:sub(1, 1) ~= k:sub(1, 1):upper() then return nil end
    if k == "SetScript" then return function(self, n, fn) self.scripts[n] = fn end end
    if k == "GetScript" then return function(self, n) return self.scripts[n] end end
    if k == "IsShown" then return function() return true end end
    if k == "GetPoint" then return function() return "CENTER", nil, "CENTER", 1, 2 end end
    if k == "GetFont" then return function() return "font", 10, "" end end
    if k == "GetCenter" then return function() return 0, 0 end end
    if k == "GetEffectiveScale" then return function() return 1 end end
    if k == "GetWidth" then return function() return 140 end end
    if k == "SetText" then return function(self, v) self.text = v end end
    if k == "SetFormattedText" then return function(self, f, ...) self.text = f:format(...) end end
    if k == "SetValue" then return function(self, v) self.value = v end end
    if k == "SetPoint" then return function(self, ...) self.point = { ... } end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return stub() end end
    return function() end
  end })
end
UIParent, GameTooltip, Minimap = stub(), stub(), stub()
cursor = { 0, 100 }
GetCursorPosition = function() return cursor[1], cursor[2] end
frames = {}
CreateFrame = function(kind, name) local f = stub(); frames[#frames + 1] = f; return f end
function windowsOf() local out = {} for _, f in ipairs(frames) do if f.scripts.OnMouseWheel then out[#out + 1] = f end end return out end
function rowsOf(w) local out = {} for _, f in ipairs(frames) do if rawget(f, "win") == w then out[#out + 1] = f end end return out end
MetailsDB = { segments = {}, overall = { time = 0 }, windows = { { mode = 1, view = 1, scale = 1, pos = { "CENTER", "CENTER", 0, 0 } } } }
""")
L.execute(pathlib.Path(__file__).with_name("Metails.lua").read_text(encoding="utf-8"))
g = L.globals()
ev = g.frames[len(g.frames)]
fire = ev.scripts.OnEvent
fire(ev, "PLAYER_LOGIN")
db = g.MetailsDB
assert db.segments is None and db.overall is None, "old combat-log data is dropped"
win = g.windowsOf()[1]
click = win.scripts.OnMouseUp
slash = g.SlashCmdList.METAILS
rows = g.rowsOf(win)

def mode(n):
    db.windows[1].mode = n - 1
    click(win, "LeftButton")
    assert db.windows[1].mode == n

assert win.title.text == "Damage Done - Current" and win.rate.text == "1.5k (150.0/s)", (win.title.text, win.rate.text)
assert rows[1].left.text == "Spell133" and rows[1].right.text == "1.2k (120.0, 80.0%)", (rows[1].left.text, rows[1].right.text)
assert rows[2].left.text == "Spell1 (Kitty)" and rows[2].right.text == "300 (30.0, 20.0%)", rows[2].right.text
assert g.lastQuery.mt == 1, "Damage Done uses the DamageDone meter type"
assert rows[1].data.overkill == 50 and len(rows[1].data.units) == 2

mode(3)
assert win.title.text == "Damage Taken by Source - Current", win.title.text
assert rows[1].left.text == "Hogger" and rows[1].right.text == "1.3k (86.7%)", (rows[1].left.text, rows[1].right.text)
assert rows[2].left.text == "Boar" and rows[2].right.text == "200 (13.3%)", rows[2].right.text
assert g.lastQuery.mt == 2

db.windows[1].mode = 3
click(win, "LeftButton")
assert db.windows[1].mode == 5, "empty views are skipped when cycling"
db.windows[1].mode = 7
click(win, "LeftButton")
assert db.windows[1].mode == 8
mode(9)
assert win.title.text == "Deaths - Current" and win.rate.text == "1.5k", win.rate.text
assert rows[1].left.text == "-1.0s +Bandage" and rows[1].right.text == "100 (75.0%)", (rows[1].left.text, rows[1].right.text)
assert rows[2].left.text == "0.0s Bite" and rows[2].right.text == "500 (25.0%)" and rows[2].data.overkill == 10, rows[2].right.text

db.windows[1].mode = 9
click(win, "LeftButton")
assert db.windows[1].mode == 1
click(win, "RightButton")
assert db.windows[1].view == 2 and win.title.text == "Damage Done - Previous" and g.lastQuery.st == 2, win.title.text
click(win, "RightButton")
assert win.title.text == "Damage Done - Overall" and g.lastQuery.st == 1
click(win, "RightButton")
assert win.title.text == "Damage Done - Fight 12" and g.lastQuery.id == 12, win.title.text
assert rows[1].right.text == "10 (2.0, 0.7%)" and win.rate.text == "1.5k (150.0/s)", rows[1].right.text
click(win, "RightButton")
assert win.title.text == "Damage Done - Hogger" and g.lastQuery.id == 11
click(win, "RightButton")
assert db.windows[1].view == 1

slash("report party 3")
chat = list(g.chat.values())
assert len(chat) == 3 and chat[0][2] == "PARTY" and chat[0][1] == "Metails! Damage Done - Current: 1.5k (150.0/s)", chat[0][1]
assert chat[1][1] == "1. Spell133  1.2k (120.0, 80.0%)", chat[1][1]
slash("report say")
assert list(g.chat.values())[-1][2] == "SAY" and " | 1. Spell133" in list(g.chat.values())[-1][1]
slash("report Bob 1")
assert list(g.chat.values())[-1][2] == "WHISPER" and list(g.chat.values())[-1][3] == "Bob"

g.now = 101
fire(ev, "DAMAGE_METER_COMBAT_SESSION_UPDATED")
assert win.title.text == "Damage Done - Current"

g.incombat = True
g.now = 110
g.tickers[1]()
assert win.rate.text == "~ (~/s)", win.rate.text
assert rows[1].left.text == "Spell?" and rows[1].right.text == "~ (~)" and g.issecretvalue(rows[1].value), (rows[1].left.text, rows[1].right.text)
assert rows[2].left.text == "Spell1 (Kitty)" and rows[2].right.text == "300 (30.0)", rows[2].right.text
rows[1].scripts.OnEnter(rows[1])
tip = [fr for fr in list(g.frames.values()) if fr.isTip][0]
assert tip.title.text == "Spell?" and tip.lines[1].left.text == "Per second" and tip.lines[1].right.text == "~", (tip.title.text, tip.lines[1].right.text)
assert tip.lines[2].left.text == "Targets" and tip.lines[3].left.text == "Hogger" and tip.lines[3].right.text == "1.0k", (tip.lines[3].left.text, tip.lines[3].right.text)
rows[1].scripts.OnLeave(rows[1])
win.scripts.OnEnter(win)
assert tip.title.text == "Metails!" and tip.lines[1].left.text == "Left-click" and tip.lines[6].left.text == "/metails help", tip.lines[1].left.text
win.scripts.OnLeave(win)
n_chat = len(g.chat)
slash("report party")
assert len(g.chat) == n_chat, "locked snapshot must not be reported"
slash("diag")
fire(ev, "DAMAGE_METER_CURRENT_SESSION_UPDATED")
g.incombat = False
g.now = 120
g.tickers[1]()
assert rows[1].right.text == "1.2k (120.0, 80.0%)", rows[1].right.text
rows[1].scripts.OnEnter(rows[1])
assert tip.title.text == "Spell133" and tip.lines[1].right.text == "120.0" and tip.lines[2].left.text == "Overkill" and tip.lines[2].right.text == "50"
assert tip.lines[3].left.text == "Targets" and tip.lines[4].left.text == "Hogger" and tip.lines[4].right.text == "1.0k (83%)", tip.lines[4].right.text

slash("new")
assert len(db.windows) == 2 and len(g.windowsOf()) == 2
slash("close")
assert len(db.windows) == 1
slash("rows 3")
slash("alpha 0.2")
assert db.opts.rows == 3 and db.opts.alpha == 0.2
g.Metails_Toggle()
assert db.windows[1].hidden is True
g.Metails_Toggle()
assert db.windows[1].hidden is False

mm = [fr for fr in list(g.frames.values()) if "OnDragStart" in dict(fr.scripts) and "OnMouseWheel" not in dict(fr.scripts)][0]
assert db.opts.minimap == 220 and abs((mm.point[4] ** 2 + mm.point[5] ** 2) ** 0.5 - 80) < 1e-6, "button sits 10px outside the minimap ring"
mm.scripts.OnDragStart(mm)
mm.scripts.OnUpdate(mm)
mm.scripts.OnDragStop(mm)
assert abs(db.opts.minimap - 90) < 1e-6 and mm.scripts.OnUpdate is None, db.opts.minimap
slash("minimap")
assert db.opts.minimapHidden is True

slash("reset")
assert g.resets == 1 and db.windows[1].view == 1
print("ok")
