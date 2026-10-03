import lupa, pathlib

L = lupa.LuaRuntime()
L.execute(r"""
bit = { band = function(a, b) return a & b end }
COMBATLOG_OBJECT_AFFILIATION_MINE, COMBATLOG_OBJECT_REACTION_HOSTILE = 1, 64
now, incombat, cleuArgs = 100, true, {}
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
wipe = function(t) for k in pairs(t) do t[k] = nil end end
SlashCmdList, texts = {}, {}
local function stub()
  local s = { scripts = {} }
  return setmetatable(s, { __index = function(t, k)
    if k:sub(1, 1) ~= k:sub(1, 1):upper() then return nil end
    if k == "SetScript" then return function(self, n, fn) self.scripts[n] = fn end end
    if k == "GetScript" then return function(self, n) return self.scripts[n] end end
    if k == "IsShown" then return function() return true end end
    if k == "GetPoint" then return function() return "CENTER", nil, "CENTER", 1, 2 end end
    if k == "SetText" then return function(self, v) self.text = v end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return stub() end end
    return function() end
  end })
end
UIParent, GameTooltip = stub(), stub()
frames = {}
CreateFrame = function(kind, name) local f = stub(); frames[#frames + 1] = f; return f end
""")
L.execute(pathlib.Path(__file__).with_name("Metails.lua").read_text(encoding="utf-8"))
g = L.globals()
ev = g.frames[len(g.frames)]
fire = ev.scripts.OnEvent
fire(ev, "PLAYER_LOGIN")
main = g.MetailsFrame if hasattr(g, "MetailsFrame") else g.frames[1]
mainframe = [f for f in list(g.frames.values()) if "OnMouseWheel" in dict(f.scripts)][0]

ME = ("Player-1", "Sam", 0x511)
PET = ("Pet-7", "Kitty", 0x1111)
MOB = ("Creature-9", "Hogger", 0x10a48)

def cleu(sub, src, dst, *rest):
    g.cleuArgs = L.table(0, sub, False, src[0], src[1], src[2], 0, dst[0], dst[1], dst[2], 0, *rest)
    fire(ev, "COMBAT_LOG_EVENT_UNFILTERED")

cleu("SPELL_DAMAGE", ME, MOB, 133, "Fireball", 4, 1000, 0, 4, 0, 0, 200, True)
cleu("SPELL_MISSED", ME, MOB, 133, "Fireball", 4, "ABSORB", False, 300)
cleu("SWING_DAMAGE", PET, MOB, 50, 0, 1, 0, 0, 0, False)
cleu("SPELL_PERIODIC_DAMAGE", MOB, ME, 10, "Bite", 1, 80, 0, 1, 0, 0, 20, False)
cleu("SPELL_HEAL", ME, ME, 1, "Bandage", 2, 500, 150, 0, False)
cleu("SPELL_ABSORBED", MOB, ME, 10, "Bite", 1, "Player-1", "Sam", 0x511, 0, 17, "Ice Barrier", 16, 120)
cleu("SPELL_INTERRUPT", ME, MOB, 2139, "Counterspell", 64, 5, "Frostbolt", 16)
cleu("SPELL_DISPEL", ME, ME, 475, "Remove Curse", 64, 6, "Curse", 32, "DEBUFF")
cleu("SPELL_CAST_SUCCESS", ME, MOB, 133, "Fireball", 4)
cleu("SPELL_CAST_SUCCESS", PET, MOB, 1, "Claw", 1)

db = g.MetailsDB
seg = db.segments[1]
assert seg.damage.total == 1000 + 200 + 300 + 50, seg.damage.total
assert seg.damage.spells["Melee (Kitty)"].amount == 50
assert seg.damage.spells["Fireball"].crits == 1 and seg.damage.spells["Fireball"].hits == 2
assert seg.taken.total == 80 and seg.taken.spells["Bite (Hogger)"]
assert seg.healing.total == 350 and seg.overheal.total == 150
assert seg.absorbed.spells["Ice Barrier"].amount == 120
assert seg.interrupts.total == 1 and seg.dispels.total == 1
assert seg.casts.total == 1, "pet casts must not count"
assert seg.name == "Hogger"
assert db.overall.damage.total == seg.damage.total

fire(ev, "PLAYER_REGEN_ENABLED")
g.now = 130
cleu("SPELL_DAMAGE", ME, MOB, 133, "Fireball", 4, 10, 0, 4, 0, 0, 0, False)
assert len(db.segments) == 2 and db.segments[1].damage.total == 10
assert db.overall.damage.total == 1560

refresh = mainframe.scripts.OnMouseUp
refresh(mainframe, "LeftButton")
assert db.mode == 2
seg2 = db.segments[1]
cleu("SPELL_AURA_APPLIED", MOB, ME, 1459, "Arcane Intellect", 64, "BUFF")
g.now = 140
cleu("SPELL_AURA_REMOVED", MOB, ME, 1459, "Arcane Intellect", 64, "BUFF")
assert seg2.buffs.spells["Arcane Intellect"].amount == 10 and db.overall.buffs.total == 10
cleu("SPELL_AURA_BROKEN_SPELL", ME, MOB, 118, "Polymorph", 64, 133, "Fireball", 4, "DEBUFF")
cleu("SPELL_AURA_BROKEN", PET, MOB, 118, "Polymorph", 64, "DEBUFF")
assert seg2.ccbreaks.total == 2 and seg2.ccbreaks.spells["Polymorph (Fireball)"] and seg2.ccbreaks.spells["Polymorph (Melee)"]
cleu("SPELL_DAMAGE", MOB, ME, 10, "Bite", 1, 500, 0, 1, 0, 0, 0, False)
g.now = 141
cleu("UNIT_DIED", ("", "", 0), ME)
assert len(seg2.deaths) == 1 and len(db.overall.deaths) == 1
log = seg2.deaths[1].log
assert len(log) == 1 and log[1].amount == -500 and log[1].hp == 25, dict(log[1])
rows = [fr for fr in list(g.frames.values()) if "OnEnter" in dict(fr.scripts) and "OnMouseWheel" not in dict(fr.scripts)]
db.mode = 10
refresh(mainframe, "LeftButton")
assert db.mode == 11 and rows[0].right.text == "500  25%", rows[0].right.text
assert "-1.0s Bite (Hogger)" == rows[0].left.text, rows[0].left.text
db.mode = 8
refresh(mainframe, "LeftButton")
assert rows[0].right.text == "10s  91%", rows[0].right.text
assert mainframe.rate.text == "11s", mainframe.rate.text
fire(ev, "PLAYER_REGEN_ENABLED")
cleu("SPELL_AURA_APPLIED", MOB, ME, 1459, "Arcane Intellect", 64, "BUFF")
g.now = 150
cleu("SPELL_AURA_REMOVED", MOB, ME, 1459, "Arcane Intellect", 64, "BUFF")
assert db.overall.buffs.total == 19, db.overall.buffs.total
g.SlashCmdList.METAILS("reset")
assert len(db.segments) == 0 and db.overall.time == 0
print("ok")
