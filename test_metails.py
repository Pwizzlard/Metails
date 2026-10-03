import lupa, pathlib

L = lupa.LuaRuntime()
L.execute(r"""
bit = { band = function(a, b) return a & b end }
COMBATLOG_OBJECT_AFFILIATION_MINE, COMBATLOG_OBJECT_REACTION_HOSTILE = 1, 64
now, incombat, cleuArgs, chat = 100, true, {}, {}
GetTime = function() return now end
UnitAffectingCombat = function() return incombat end
CombatLogGetCurrentEventInfo = function() return table.unpack(cleuArgs) end
C_Spell = { GetSpellTexture = function(id) return "tex" .. id end }
C_Timer = { NewTicker = function() end }
UnitGUID = function() return "Player-1" end
UnitClass = function() return "Mage", "MAGE" end
RAID_CLASS_COLORS = { MAGE = { r = 0, g = 0, b = 1 } }
GameTooltip_Hide = function() end
UnitHealth, UnitHealthMax, UnitIsFeignDeath = function() return 250 end, function() return 1000 end, function() return false end
IsShiftKeyDown, IsInRaid, IsInGroup = function() return false end, function() return false end, function() return true end
SendChatMessage = function(msg, chan, _, target) chat[#chat + 1] = { msg, chan, target } end
wipe = function(t) for k in pairs(t) do t[k] = nil end end
SlashCmdList = {}
local function stub()
  local s = { scripts = {} }
  return setmetatable(s, { __index = function(t, k)
    if k:sub(1, 1) ~= k:sub(1, 1):upper() then return nil end
    if k == "SetScript" then return function(self, n, fn) self.scripts[n] = fn end end
    if k == "GetScript" then return function(self, n) return self.scripts[n] end end
    if k == "IsShown" then return function() return true end end
    if k == "GetPoint" then return function() return "CENTER", nil, "CENTER", 1, 2 end end
    if k == "GetFont" then return function() return "font", 10, "" end end
    if k == "SetText" then return function(self, v) self.text = v end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return stub() end end
    return function() end
  end })
end
UIParent, GameTooltip = stub(), stub()
frames = {}
CreateFrame = function(kind, name) local f = stub(); frames[#frames + 1] = f; return f end
function windowsOf() local out = {} for _, f in ipairs(frames) do if f.scripts.OnMouseWheel then out[#out + 1] = f end end return out end
function rowsOf(w) local out = {} for _, f in ipairs(frames) do if rawget(f, "win") == w then out[#out + 1] = f end end return out end
MetailsDB = { mode = 3, view = 1, scale = 1, pos = { "CENTER", "CENTER", 0, 0 } }
""")
L.execute(pathlib.Path(__file__).with_name("Metails.lua").read_text(encoding="utf-8"))
g = L.globals()
ev = g.frames[len(g.frames)]
fire = ev.scripts.OnEvent
fire(ev, "PLAYER_LOGIN")
db = g.MetailsDB
assert db.mode is None and db.windows[1].mode == 3, "old settings migrate into windows[1]"
win = g.windowsOf()[1]
click = win.scripts.OnMouseUp
slash = g.SlashCmdList.METAILS

ME = ("Player-1", "Sam", 0x511)
PET = ("Pet-7", "Kitty", 0x1111)
MOB = ("Creature-9", "Hogger", 0x10a48)
NONE = ("", "", 0)

def cleu(sub, src, dst, *rest):
    g.cleuArgs = L.table(0, sub, False, src[0], src[1], src[2], 0, dst[0], dst[1], dst[2], 0, *rest)
    fire(ev, "COMBAT_LOG_EVENT_UNFILTERED")

def mode(n):
    db.windows[1].mode = n - 1
    click(win, "LeftButton")
    assert db.windows[1].mode == n

cleu("SPELL_DAMAGE", ME, MOB, 133, "Fireball", 4, 1000, 50, 4, 0, 0, 200, True)
cleu("SPELL_MISSED", ME, MOB, 133, "Fireball", 4, "ABSORB", False, 300)
cleu("SPELL_MISSED", ME, MOB, 133, "Fireball", 4, "DODGE", False, 0)
cleu("SWING_DAMAGE", PET, MOB, 50, 0, 1, 0, 0, 0, False)
cleu("SPELL_PERIODIC_DAMAGE", MOB, ME, 10, "Bite", 1, 80, 0, 1, 0, 0, 20, False)
cleu("SWING_MISSED", MOB, ME, "PARRY", False, 0)
cleu("SPELL_HEAL", ME, ME, 1, "Bandage", 2, 500, 150, 0, False)
cleu("SPELL_ABSORBED", MOB, ME, 10, "Bite", 1, "Player-1", "Sam", 0x511, 0, 17, "Ice Barrier", 16, 120)
cleu("SPELL_ENERGIZE", ME, ME, 12051, "Evocation", 64, 300, 0, 0)
cleu("SPELL_INTERRUPT", ME, MOB, 2139, "Counterspell", 64, 5, "Frostbolt", 16)
cleu("SPELL_DISPEL", ME, ME, 475, "Remove Curse", 64, 6, "Curse", 32, "DEBUFF")
cleu("SPELL_CAST_SUCCESS", ME, MOB, 133, "Fireball", 4)
cleu("SPELL_CAST_SUCCESS", PET, MOB, 1, "Claw", 1)
cleu("PARTY_KILL", ME, MOB)

seg = db.segments[1]
fb = seg.damage.spells["Fireball"]
assert seg.damage.total == 1000 + 200 + 300 + 50, seg.damage.total
assert fb.hits == 2 and fb.crits == 1 and fb.miss.DODGE == 1 and fb.overkill == 50 and fb.min == 300 and fb.max == 1200, dict(fb)
assert fb.targets.Hogger == 1500 and fb.critAmt == 1200
assert seg.damage.spells["Melee (Kitty)"].amount == 50
assert seg.taken.total == 80 and seg.taken.spells["Bite (Hogger)"] and seg.taken.spells["Melee (Hogger)"].miss.PARRY == 1
assert seg.takenby.spells.Hogger.amount == 80
assert seg.healing.total == 350 and seg.overheal.total == 150 and seg.healing.spells.Bandage.targets.Sam == 350
assert seg.healtaken.spells["Bandage (Sam)"].amount == 350
assert seg.absorbed.spells["Ice Barrier"].amount == 120
assert seg.resources.spells.Evocation.amount == 300
assert seg.interrupts.total == 1 and seg.dispels.total == 1 and seg.kills.spells.Hogger.hits == 1
assert seg.casts.total == 1, "pet casts must not count"
assert seg.name == "Hogger"
assert db.overall.damage.total == seg.damage.total

fire(ev, "PLAYER_REGEN_ENABLED")
g.now = 130
cleu("SPELL_DAMAGE", ME, MOB, 133, "Fireball", 4, 10, 0, 4, 0, 0, 0, False)
assert len(db.segments) == 2 and db.segments[1].damage.total == 10
assert db.overall.damage.total == 1560

seg2 = db.segments[1]
cleu("SPELL_AURA_APPLIED", MOB, ME, 1459, "Arcane Intellect", 64, "BUFF")
cleu("SPELL_AURA_APPLIED", ME, MOB, 122, "Frost Nova", 16, "DEBUFF")
g.now = 140
cleu("SPELL_AURA_REMOVED", MOB, ME, 1459, "Arcane Intellect", 64, "BUFF")
cleu("UNIT_DIED", NONE, MOB)
assert seg2.buffs.spells["Arcane Intellect"].amount == 10 and db.overall.buffs.total == 10
assert seg2.debuffs.spells["Frost Nova"].amount == 10, dict(seg2.debuffs.spells["Frost Nova"])
cleu("SPELL_AURA_BROKEN_SPELL", ME, MOB, 118, "Polymorph", 64, 133, "Fireball", 4, "DEBUFF")
cleu("SPELL_AURA_BROKEN", PET, MOB, 118, "Polymorph", 64, "DEBUFF")
assert seg2.ccbreaks.total == 2 and seg2.ccbreaks.spells["Polymorph (Fireball)"] and seg2.ccbreaks.spells["Polymorph (Melee)"]
cleu("SPELL_DAMAGE", MOB, ME, 10, "Bite", 1, 500, 10, 1, 0, 0, 0, False)
g.now = 141
cleu("UNIT_DIED", NONE, ME)
assert len(seg2.deaths) == 1 and len(db.overall.deaths) == 1
log = seg2.deaths[1].log
assert len(log) == 1 and log[1].amount == -500 and log[1].hp == 25 and log[1].ok == 10, dict(log[1])

mode(16)
rows = g.rowsOf(win)
assert rows[1].right.text == "500 (25.0%)" and rows[1].left.text == "-1.0s Bite (Hogger)", (rows[1].right.text, rows[1].left.text)
mode(13)
assert rows[1].right.text == "10s (90.9%)" and win.rate.text == "11s", (rows[1].right.text, win.rate.text)
mode(1)
assert win.title.text == "Damage Done - Hogger", win.title.text
click(win, "RightButton")
assert db.windows[1].view == 2 and win.title.text == "Damage Done - Overall", win.title.text
db.windows[1].view = 1

slash("report party 3")
chat = list(g.chat.values())
assert len(chat) == 2 and chat[0][2] == "PARTY" and chat[0][1].startswith("Metails! Damage Done - Hogger: 10"), (chat[0][1], chat[0][2])
assert chat[1][1] == "1. Fireball  10 (1, 100.0%)", chat[1][1]
slash("report Bob")
assert list(g.chat.values())[-1][2] == "WHISPER" and list(g.chat.values())[-1][3] == "Bob"

slash("pets group")
cleu("SWING_DAMAGE", PET, MOB, 7, 0, 1, 0, 0, 0, False)
assert seg2.damage.spells.Kitty.amount == 7
slash("pets off")
cleu("SWING_DAMAGE", PET, MOB, 7, 0, 1, 0, 0, 0, False)
assert seg2.damage.total == 17, seg2.damage.total

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

fire(ev, "PLAYER_REGEN_ENABLED")
fire(ev, "ENCOUNTER_START", 7, "Edwin VanCleef", 1, 5)
cleu("SPELL_DAMAGE", ME, MOB, 133, "Fireball", 4, 10, 0, 4, 0, 0, 0, False)
fire(ev, "ENCOUNTER_END", 7, "Edwin VanCleef", 1, 5, 0)
assert db.segments[1].name == "Edwin VanCleef (wipe)" and db.segments[1].boss is True

fire(ev, "PLAYER_REGEN_ENABLED")
cleu("SPELL_AURA_APPLIED", MOB, ME, 1459, "Arcane Intellect", 64, "BUFF")
g.now = 150
cleu("SPELL_AURA_REMOVED", MOB, ME, 1459, "Arcane Intellect", 64, "BUFF")
assert db.overall.buffs.total == 19, db.overall.buffs.total
slash("reset")
assert len(db.segments) == 0 and db.overall.time == 0
print("ok")
