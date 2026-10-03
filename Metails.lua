local band, min, max = bit.band, math.min, math.max
local MINE, HOSTILE = COMBATLOG_OBJECT_AFFILIATION_MINE, COMBATLOG_OBJECT_REACTION_HOSTILE
local MODES = {
  { key = "damage",     label = "Damage Done",      rate = true },
  { key = "taken",      label = "Damage Taken",     rate = true },
  { key = "healing",    label = "Healing Done",     rate = true },
  { key = "overheal",   label = "Overhealing" },
  { key = "absorbed",   label = "Damage Prevented" },
  { key = "interrupts", label = "Interrupts",       count = true },
  { key = "dispels",    label = "Dispels",          count = true },
  { key = "casts",      label = "Casts",            count = true },
  { key = "buffs",      label = "Buff Uptime",      secs = true },
  { key = "ccbreaks",   label = "CC Breaks",        count = true },
  { key = "deaths",     label = "Deaths",           log = true },
}
local MAXROWS, MAXSEGS, RING = 10, 12, 12
local db, cur, playerGUID, f, rows
local list, active, ring, ringN = {}, {}, {}, 0

local function fmt(n)
  if n >= 1e6 then return ("%.2fM"):format(n / 1e6) end
  if n >= 1e3 then return ("%.1fk"):format(n / 1e3) end
  return ("%.0f"):format(n)
end

local function icon(id)
  return id and C_Spell.GetSpellTexture(id) or (id and 134400 or 132349)
end

local function add(seg, mode, key, tex, amount, crit)
  local m = seg[mode] or { total = 0, spells = {} }
  seg[mode] = m
  m.total = m.total + amount
  local s = m.spells[key] or { name = key, icon = tex, amount = 0, hits = 0, crits = 0, max = 0 }
  m.spells[key] = s
  s.amount, s.hits = s.amount + amount, s.hits + 1
  if crit then s.crits = s.crits + 1 end
  if amount > s.max then s.max = amount end
end

local function bump(seg, name, dt)
  local s = seg and seg.buffs and seg.buffs.spells[name]
  if s then s.amount, seg.buffs.total = s.amount + dt, seg.buffs.total + dt end
end

local function flushBuffs(now)
  for name, b in pairs(active) do
    bump(cur, name, now - b.t); bump(db.overall, name, now - b.t)
    b.t = now
  end
end

local function touch()
  local now = GetTime()
  if not cur or (now - cur.last > 10 and not UnitAffectingCombat("player")) then
    cur = { time = 0, last = now }
    table.insert(db.segments, 1, cur)
    db.segments[MAXSEGS + 1] = nil
    for name, b in pairs(active) do b.t = now; add(cur, "buffs", name, b.icon, 0) end
  end
  local dt = now - cur.last
  if not UnitAffectingCombat("player") then dt = min(dt, 2) end
  cur.time, db.overall.time, cur.last = cur.time + dt, db.overall.time + dt, now
end

local function record(mode, key, tex, amount, crit)
  if amount <= 0 then return end
  touch()
  add(cur, mode, key, tex, amount, crit)
  add(db.overall, mode, key, tex, amount, crit)
end

local function logHit(name, tex, amount)
  ringN = ringN % RING + 1
  local e = ring[ringN] or {}
  ring[ringN] = e
  e.t, e.name, e.icon, e.amount = GetTime(), name, tex, amount
  e.hp = UnitHealth("player") / max(1, UnitHealthMax("player")) * 100
end

local function died()
  if UnitIsFeignDeath("player") then return end
  touch()
  local now, log = GetTime(), {}
  for i = 1, RING do
    local e = ring[(ringN + i - 1) % RING + 1]
    if e and now - e.t < 30 then log[#log + 1] = e end
  end
  wipe(ring)
  for _, seg in next, { cur, db.overall } do
    seg.deaths = seg.deaths or {}
    table.insert(seg.deaths, { t = now, log = log })
    if #seg.deaths > 5 then table.remove(seg.deaths, 1) end
  end
end

local function cleu(_, ev, _, srcGUID, srcName, srcFlags, _, dstGUID, dstName, dstFlags, _, ...)
  local mine, toMe = band(srcFlags or 0, MINE) > 0, dstGUID == playerGUID
  if not mine and not toMe and ev ~= "SPELL_ABSORBED" then return end
  local o, spellId, spellName = 4, ...
  if ev:sub(1, 5) == "SWING" then o, spellId, spellName = 1, nil, "Melee"
  elseif ev:sub(1, 13) == "ENVIRONMENTAL" then o, spellId, spellName = 2, nil, (...) end
  spellName = spellName or "Unknown"
  local suffix = ev:match("_([A-Z]+)$")
  if suffix == "SHIELD" or suffix == "SPLIT" then suffix = "DAMAGE" end
  local tex = icon(spellId)
  local key = spellName .. ((mine and srcGUID ~= playerGUID) and (" (" .. (srcName or "Pet") .. ")") or "")
  local from = spellName .. " (" .. (srcName or "?") .. ")"
  if suffix == "DAMAGE" then
    local amt, _, _, _, _, absorbed, crit = select(o, ...)
    amt, absorbed = amt or 0, absorbed or 0
    if mine then
      record("damage", key, tex, amt + absorbed, crit)
      if cur and not cur.name and band(dstFlags or 0, HOSTILE) > 0 then cur.name = dstName end
    end
    if toMe then record("taken", from, tex, amt, crit); logHit(from, tex, -amt) end
  elseif suffix == "MISSED" then
    local missType, _, missed = select(o, ...)
    if mine and missType == "ABSORB" then record("damage", key, tex, missed or 0) end
  elseif suffix == "HEAL" then
    local amt, over, _, crit = select(o, ...)
    amt, over = amt or 0, over or 0
    if mine then
      record("healing", key, tex, amt - over, crit)
      record("overheal", key, tex, over, crit)
    end
    if toMe and amt > over then logHit(from, tex, amt - over) end
  elseif ev == "SPELL_ABSORBED" then
    local s = type((...)) == "number" and 4 or 1
    local _, _, flags, _, absId, absName, _, amt = select(s, ...)
    if band(flags or 0, MINE) > 0 then record("absorbed", absName or "Absorb", icon(absId), amt or 0) end
  elseif suffix == "INTERRUPT" and mine then record("interrupts", key, tex, 1)
  elseif (suffix == "DISPEL" or suffix == "STOLEN") and mine then record("dispels", key, tex, 1)
  elseif suffix == "SUCCESS" and srcGUID == playerGUID then record("casts", spellName, tex, 1)
  elseif ev == "SPELL_AURA_APPLIED" then
    if toMe and select(o, ...) == "BUFF" and not active[spellName] then
      active[spellName] = { t = GetTime(), icon = tex }
      if cur then add(cur, "buffs", spellName, tex, 0) end
      add(db.overall, "buffs", spellName, tex, 0)
    end
  elseif ev == "SPELL_AURA_REMOVED" and toMe and active[spellName] then flushBuffs(GetTime()); active[spellName] = nil
  elseif ev == "SPELL_AURA_BROKEN" or ev == "SPELL_AURA_BROKEN_SPELL" then
    if mine and select(ev == "SPELL_AURA_BROKEN" and o or o + 3, ...) == "DEBUFF" then
      record("ccbreaks", spellName .. " (" .. (ev == "SPELL_AURA_BROKEN" and "Melee" or (select(o + 1, ...)) or "?") .. ")", tex, 1)
    end
  elseif ev == "UNIT_DIED" and toMe then died()
  end
end

local function nviews() return #db.segments + 1 end

local function refresh()
  if not f:IsShown() then return end
  if cur then flushBuffs(GetTime()) end
  local mode = MODES[db.mode]
  if db.view > nviews() then db.view = 1 end
  local seg = db.view == 2 and db.overall or db.segments[db.view == 1 and 1 or db.view - 1]
  f.title:SetText(mode.label .. " - " .. (db.view == 2 and "Overall" or seg and seg.name or "Current"))
  local m = seg and seg[mode.key]
  local time = seg and seg.time or 0
  if time <= 0 then time = 1 end
  local tot, top = m and m.total or 0, 0
  wipe(list)
  if mode.log then
    local d = seg and seg.deaths and seg.deaths[#seg.deaths]
    tot = d and #seg.deaths or 0
    if d then
      for i = max(1, #d.log - MAXROWS + 1), #d.log do
        local e = d.log[i]
        list[#list + 1] = { name = ("%.1fs %s%s"):format(e.t - d.t, e.amount > 0 and "+" or "", e.name), icon = e.icon, amount = math.abs(e.amount), pct = e.hp }
        top = max(top, math.abs(e.amount))
      end
    end
  elseif m then
    for _, s in pairs(m.spells) do list[#list + 1] = s end
    table.sort(list, function(x, y) return x.amount > y.amount end)
    top = list[1] and list[1].amount or 0
  end
  f.rate:SetText(mode.secs and ("%.0fs"):format(time) or (fmt(tot) .. (mode.rate and (" (" .. fmt(tot / time) .. "/s)") or "")))
  local n = tot > 0 and min(#list, MAXROWS) or 0
  for i, r in ipairs(rows) do
    local s = list[i]
    r:SetShown(i <= n)
    if i <= n then
      r.data, r.mode, r.time = s, mode, time
      r:SetMinMaxValues(0, top)
      r:SetValue(s.amount)
      r.icon:SetTexture(s.icon)
      r.left:SetText(s.name)
      local pct = s.pct or min(100, s.amount / (mode.secs and time or tot) * 100)
      r.right:SetText((mode.secs and ("%.0fs"):format(s.amount) or fmt(s.amount)) .. (mode.rate and (" (" .. fmt(s.amount / time) .. ")") or "") .. ("  %.0f%%"):format(pct))
    end
  end
  f:SetHeight(18 + n * 17 + (n == 0 and 0 or 2))
end

local function rowTip(r)
  local s, mode = r.data, r.mode
  GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
  GameTooltip:AddLine(s.name)
  if mode.log then GameTooltip:AddLine(("%.0f%% health after"):format(s.pct), 1, 1, 1)
  elseif mode.count or mode.secs then GameTooltip:AddDoubleLine("Count", s.hits, 1, 1, 1, 1, 1, 1)
  else
    GameTooltip:AddDoubleLine("Hits", s.hits, 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Crits", ("%d (%.0f%%)"):format(s.crits, s.crits / s.hits * 100), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Average", fmt(s.amount / s.hits), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Max", fmt(s.max), 1, 1, 1, 1, 1, 1)
    if mode.rate then GameTooltip:AddDoubleLine("Per second", fmt(s.amount / r.time), 1, 1, 1, 1, 1, 1) end
  end
  GameTooltip:Show()
end

local function onClick(_, btn)
  if f.dragged then f.dragged = nil return end
  if btn == "LeftButton" then db.mode = db.mode % #MODES + 1
  elseif btn == "RightButton" then db.view = db.view % nviews() + 1 end
  refresh()
end

local function build()
  f = CreateFrame("Frame", "MetailsFrame", UIParent, "BackdropTemplate")
  f:SetSize(230, 18)
  f:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
  f:SetScale(db.scale)
  f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
  f:SetBackdropColor(0, 0, 0, 0.55)
  f:SetMovable(true); f:EnableMouse(true); f:EnableMouseWheel(true); f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(s) if not db.locked then s.dragged = true; s:StartMoving() end end)
  f:SetScript("OnDragStop", function(s) s:StopMovingOrSizing(); local p, _, rp, x, y = s:GetPoint(); db.pos = { p, rp, x, y } end)
  f:SetScript("OnMouseUp", onClick)
  f:SetScript("OnMouseWheel", function(_, d) db.view = (db.view - 1 - d) % nviews() + 1; refresh() end)
  f:SetScript("OnEnter", function(s)
    GameTooltip:SetOwner(s, "ANCHOR_TOP")
    GameTooltip:AddLine("Metails")
    GameTooltip:AddLine("Left-click: mode   Right-click/wheel: segment\nDrag: move   /metails for commands", 1, 1, 1)
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", GameTooltip_Hide)
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.title:SetPoint("TOPLEFT", 4, -2); f.title:SetJustifyH("LEFT")
  f.rate = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.rate:SetPoint("TOPRIGHT", -4, -2)
  f.title:SetPoint("RIGHT", f.rate, "LEFT", -4, 0)
  local c = RAID_CLASS_COLORS[select(2, UnitClass("player"))] or { r = 0.6, g = 0.6, b = 0.6 }
  rows = {}
  for i = 1, MAXROWS do
    local r = CreateFrame("StatusBar", nil, f)
    r:SetSize(230 - 20, 16)
    r:SetPoint("TOPLEFT", 19, -(18 + (i - 1) * 17))
    r:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    r:SetStatusBarColor(c.r, c.g, c.b, 0.8)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16); r.icon:SetPoint("RIGHT", r, "LEFT", -1, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.left = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.left:SetPoint("LEFT", 3, 0); r.left:SetJustifyH("LEFT")
    r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.right:SetPoint("RIGHT", -3, 0)
    r.left:SetPoint("RIGHT", r.right, "LEFT", -4, 0)
    r:EnableMouse(true)
    r:SetScript("OnEnter", rowTip)
    r:SetScript("OnLeave", GameTooltip_Hide)
    r:SetScript("OnMouseUp", onClick)
    r:Hide()
    rows[i] = r
  end
  f:SetShown(not db.hidden)
  C_Timer.NewTicker(0.5, refresh)
end

SLASH_METAILS1 = "/metails"
SlashCmdList.METAILS = function(msg)
  local cmd, arg = msg:match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  if cmd == "reset" then db.segments, db.overall, cur, db.view = {}, { time = 0 }, nil, 1; refresh()
  elseif cmd == "lock" then db.locked = not db.locked; print("Metails: " .. (db.locked and "locked" or "unlocked"))
  elseif cmd == "scale" and tonumber(arg) then db.scale = min(max(tonumber(arg), 0.5), 3); f:SetScale(db.scale)
  elseif cmd == "" then db.hidden = f:IsShown(); f:SetShown(not db.hidden); refresh()
  else print("Metails: /metails (toggle), reset, lock, scale <n>") end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, e)
  if e == "PLAYER_LOGIN" then
    MetailsDB = MetailsDB or {}
    db = MetailsDB
    if type(db.segments) ~= "table" or type(db.overall) ~= "table" or type(db.overall.time) ~= "number" then db.segments, db.overall = {}, { time = 0 } end
    db.mode = (type(db.mode) == "number" and MODES[db.mode]) and db.mode or 1
    db.view = type(db.view) == "number" and db.view or 1
    db.scale = type(db.scale) == "number" and min(max(db.scale, 0.5), 3) or 1
    if type(db.pos) ~= "table" or type(db.pos[3]) ~= "number" or type(db.pos[4]) ~= "number" then db.pos = { "CENTER", "CENTER", 300, -150 } end
    playerGUID = UnitGUID("player")
    if AuraUtil and AuraUtil.ForEachAura then
      AuraUtil.ForEachAura("player", "HELPFUL", nil, function(name, tex) active[name] = { t = GetTime(), icon = tex } end)
    end
    build()
    ev:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
  elseif e == "COMBAT_LOG_EVENT_UNFILTERED" then cleu(CombatLogGetCurrentEventInfo())
  elseif cur then flushBuffs(GetTime()); cur = nil end
end)
