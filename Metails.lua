local band, min, max = bit.band, math.min, math.max
local atan2 = math.atan2 or math.atan
local MINE, HOSTILE = COMBATLOG_OBJECT_AFFILIATION_MINE, COMBATLOG_OBJECT_REACTION_HOSTILE
local MODES = {
  { key = "damage",     label = "Damage Done",            rate = true },
  { key = "taken",      label = "Damage Taken",           rate = true },
  { key = "takenby",    label = "Damage Taken by Source", rate = true },
  { key = "healing",    label = "Healing Done",           rate = true },
  { key = "healtaken",  label = "Healing Taken",          rate = true },
  { key = "overheal",   label = "Overhealing" },
  { key = "absorbed",   label = "Damage Prevented" },
  { key = "resources",  label = "Resources Gained",       rate = true },
  { key = "interrupts", label = "Interrupts",             count = true },
  { key = "dispels",    label = "Dispels",                count = true },
  { key = "casts",      label = "Casts",                  count = true },
  { key = "kills",      label = "Killing Blows",          count = true },
  { key = "buffs",      label = "Buff Uptime",            secs = true },
  { key = "debuffs",    label = "Debuff Uptime",          secs = true },
  { key = "ccbreaks",   label = "CC Breaks",              count = true },
  { key = "deaths",     label = "Deaths",                 log = true },
}
local MAXSEGS, RING, WIDTH, ROWH = 12, 12, 230, 17
local TEXTURES = { smooth = "Interface\\TargetingFrame\\UI-StatusBar", flat = "Interface\\Buttons\\WHITE8x8", raid = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" }
local CHANNELS = { say = "SAY", yell = "YELL", party = "PARTY", raid = "RAID", guild = "GUILD", officer = "OFFICER", instance = "INSTANCE_CHAT" }
local db, cur, playerGUID, windows = nil, nil, nil, {}
local list, ring, ringN = {}, {}, 0
local active, onTarget = { buffs = {}, debuffs = {} }, {}

local function fmt(n)
  if n >= 1e6 then return ("%.2fM"):format(n / 1e6) end
  if n >= 1e3 then return ("%.1fk"):format(n / 1e3) end
  return ("%.0f"):format(n)
end

local function icon(id)
  return id and C_Spell.GetSpellTexture(id) or (id and 134400 or 132349)
end

local function add(seg, mode, key, tex, amount, crit, target, overkill)
  local m = seg[mode] or { total = 0, spells = {} }
  seg[mode] = m
  m.total = m.total + amount
  local s = m.spells[key] or { name = key, icon = tex, amount = 0, hits = 0, crits = 0, max = 0 }
  m.spells[key] = s
  s.amount, s.hits = s.amount + amount, s.hits + 1
  if crit then s.crits, s.critAmt = s.crits + 1, (s.critAmt or 0) + amount end
  if amount > s.max then s.max = amount end
  if amount > 0 and amount < (s.min or amount + 1) then s.min = amount end
  if overkill and overkill > 0 then s.overkill = (s.overkill or 0) + overkill end
  if target then
    local t = s.targets or {}
    s.targets = t
    -- ponytail: 40 targets per spell; Overall would otherwise collect every mob name ever hit
    if t[target] or (s.ntargets or 0) < 40 then
      if not t[target] then s.ntargets = (s.ntargets or 0) + 1 end
      t[target] = (t[target] or 0) + amount
    end
  end
  return s
end

local function addMiss(seg, mode, key, tex, kind)
  local s = add(seg, mode, key, tex, 0)
  s.hits = s.hits - 1
  s.miss = s.miss or {}
  s.miss[kind] = (s.miss[kind] or 0) + 1
end

local function both(fn, ...)
  fn(cur, ...)
  fn(db.overall, ...)
end

local function bump(seg, mode, key, dt)
  local s = seg and seg[mode] and seg[mode].spells[key]
  if s then s.amount, seg[mode].total = s.amount + dt, seg[mode].total + dt end
end

local function flushUptime(now)
  for mode, set in pairs(active) do
    for key, b in pairs(set) do
      bump(cur, mode, key, now - b.t); bump(db.overall, mode, key, now - b.t)
      b.t = now
    end
  end
end

local function touch()
  local now = GetTime()
  if not cur or (now - cur.last > 10 and not UnitAffectingCombat("player")) then
    cur = { time = 0, last = now }
    table.insert(db.segments, 1, cur)
    db.segments[MAXSEGS + 1] = nil
    wipe(active.debuffs); wipe(onTarget)
    for name, b in pairs(active.buffs) do b.t = now; add(cur, "buffs", name, b.icon, 0) end
  end
  local dt = now - cur.last
  if not UnitAffectingCombat("player") then dt = min(dt, 2) end
  cur.time, db.overall.time, cur.last = cur.time + dt, db.overall.time + dt, now
end

local function record(mode, key, tex, amount, crit, target, overkill)
  touch()
  both(add, mode, key, tex, amount, crit, target, overkill)
end

local function miss(mode, key, tex, kind)
  touch()
  both(addMiss, mode, key, tex, kind)
end

local function auraOn(mode, key, tex)
  local b = active[mode][key]
  if b then b.n = b.n + 1 return end
  active[mode][key] = { t = GetTime(), icon = tex, n = 1 }
  if cur then add(cur, mode, key, tex, 0) end
  add(db.overall, mode, key, tex, 0)
end

local function auraOff(mode, key)
  local b = active[mode][key]
  if not b then return end
  b.n = b.n - 1
  if b.n > 0 then return end
  flushUptime(GetTime())
  active[mode][key] = nil
end

local function targetDied(guid)
  for name, n in pairs(onTarget[guid] or {}) do
    for _ = 1, n do auraOff("debuffs", name) end
  end
  onTarget[guid] = nil
end

local function logHit(name, tex, amount, overkill)
  ringN = ringN % RING + 1
  local e = ring[ringN] or {}
  ring[ringN] = e
  e.t, e.name, e.icon, e.amount, e.ok = GetTime(), name, tex, amount, overkill
  e.hp = UnitHealth("player") / max(1, UnitHealthMax("player")) * 100
end

local function addDeath(seg, death)
  seg.deaths = seg.deaths or {}
  table.insert(seg.deaths, death)
  if #seg.deaths > 5 then table.remove(seg.deaths, 1) end
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
  both(addDeath, { t = now, log = log })
end

local function cleu(_, ev, _, srcGUID, srcName, srcFlags, _, dstGUID, dstName, dstFlags, _, ...)
  local mine, toMe = band(srcFlags or 0, MINE) > 0, dstGUID == playerGUID
  local pet = mine and srcGUID ~= playerGUID
  if pet and db.opts.pets == "off" then mine = false end
  if not mine and not toMe and ev ~= "SPELL_ABSORBED" and ev ~= "UNIT_DIED" then return end
  local o, spellId, spellName = 4, ...
  if ev:sub(1, 5) == "SWING" then o, spellId, spellName = 1, nil, "Melee"
  elseif ev:sub(1, 13) == "ENVIRONMENTAL" then o, spellId, spellName = 2, nil, (...) end
  spellName = spellName or "Unknown"
  local suffix = ev:match("_([A-Z]+)$")
  if suffix == "SHIELD" or suffix == "SPLIT" then suffix = "DAMAGE" end
  local tex = icon(spellId)
  local key = spellName
  if pet then key = db.opts.pets == "group" and (srcName or "Pet") or spellName .. " (" .. (srcName or "Pet") .. ")" end
  local from = spellName .. " (" .. (srcName or "?") .. ")"
  if suffix == "DAMAGE" then
    local amt, overkill, _, _, _, absorbed, crit = select(o, ...)
    amt, absorbed = amt or 0, absorbed or 0
    if mine then
      record("damage", key, tex, amt + absorbed, crit, dstName, overkill)
      if cur and not cur.name and band(dstFlags or 0, HOSTILE) > 0 then cur.name = dstName end
    end
    if toMe then
      record("taken", from, tex, amt, crit)
      record("takenby", srcName or "?", tex, amt, crit)
      logHit(from, tex, -amt, overkill)
    end
  elseif suffix == "MISSED" then
    local kind, _, missed = select(o, ...)
    if mine and kind == "ABSORB" then record("damage", key, tex, missed or 0, nil, dstName)
    elseif mine then miss("damage", key, tex, kind or "MISS") end
    if toMe then miss("taken", from, tex, kind or "MISS") end
  elseif suffix == "HEAL" then
    local amt, over, _, crit = select(o, ...)
    amt, over = amt or 0, over or 0
    if mine then
      record("healing", key, tex, amt - over, crit, dstName)
      if over > 0 then record("overheal", key, tex, over, crit) end
    end
    if toMe and amt > over then record("healtaken", from, tex, amt - over, crit); logHit(from, tex, amt - over) end
  elseif ev == "SPELL_ABSORBED" then
    local s = type((...)) == "number" and 4 or 1
    local _, _, flags, _, absId, absName, _, amt = select(s, ...)
    if band(flags or 0, MINE) > 0 and (amt or 0) > 0 then record("absorbed", absName or "Absorb", icon(absId), amt) end
  elseif suffix == "ENERGIZE" then
    local amt = select(o, ...)
    if toMe and (amt or 0) > 0 then record("resources", spellName, tex, amt) end
  elseif suffix == "INTERRUPT" and mine then record("interrupts", key, tex, 1)
  elseif (suffix == "DISPEL" or suffix == "STOLEN") and mine then record("dispels", key, tex, 1)
  elseif suffix == "SUCCESS" and srcGUID == playerGUID then record("casts", spellName, tex, 1)
  elseif ev == "PARTY_KILL" and mine then record("kills", dstName or "?", "Interface\\TargetingFrame\\UI-TargetingFrame-Skull", 1)
  elseif ev == "SPELL_AURA_APPLIED" then
    local kind = select(o, ...)
    if toMe and kind == "BUFF" then auraOn("buffs", spellName, tex)
    elseif mine and kind == "DEBUFF" and band(dstFlags or 0, HOSTILE) > 0 then
      auraOn("debuffs", spellName, tex)
      local t = onTarget[dstGUID] or {}
      onTarget[dstGUID] = t
      t[spellName] = (t[spellName] or 0) + 1
    end
  elseif ev == "SPELL_AURA_REMOVED" then
    if toMe then auraOff("buffs", spellName) end
    local t = mine and onTarget[dstGUID]
    if t and t[spellName] then
      t[spellName] = t[spellName] > 1 and t[spellName] - 1 or nil
      auraOff("debuffs", spellName)
    end
  elseif ev == "SPELL_AURA_BROKEN" or ev == "SPELL_AURA_BROKEN_SPELL" then
    if mine and select(ev == "SPELL_AURA_BROKEN" and o or o + 3, ...) == "DEBUFF" then
      record("ccbreaks", spellName .. " (" .. (ev == "SPELL_AURA_BROKEN" and "Melee" or (select(o + 1, ...)) or "?") .. ")", tex, 1)
    end
  elseif ev == "UNIT_DIED" then
    if toMe then died() else targetDied(dstGUID) end
  end
end

local function nviews() return #db.segments + 1 end

local function segAt(i)
  return i == 2 and db.overall or db.segments[i == 1 and 1 or i - 1]
end

local function segLabel(i)
  local seg = segAt(i)
  return i == 2 and "Overall" or seg and seg.name or (i == 1 and "Current" or "Segment")
end

local function collect(cfg)
  local mode = MODES[cfg.mode]
  if cfg.view > nviews() then cfg.view = 1 end
  local seg = segAt(cfg.view)
  local m = seg and seg[mode.key]
  local time = seg and seg.time or 0
  if time <= 0 then time = 1 end
  local tot, top = m and m.total or 0, 0
  wipe(list)
  if mode.log then
    local d = seg and seg.deaths and seg.deaths[#seg.deaths]
    tot = d and #seg.deaths or 0
    if d then
      for i = max(1, #d.log - db.opts.rows + 1), #d.log do
        local e = d.log[i]
        list[#list + 1] = { name = ("%.1fs %s%s"):format(e.t - d.t, e.amount > 0 and "+" or "", e.name), icon = e.icon, amount = math.abs(e.amount), pct = e.hp, overkill = e.ok }
        top = max(top, math.abs(e.amount))
      end
    end
  elseif m then
    for _, s in pairs(m.spells) do list[#list + 1] = s end
    table.sort(list, function(x, y) return x.amount > y.amount end)
    top = list[1] and list[1].amount or 0
  end
  return mode, segLabel(cfg.view), tot, top, time
end

local function rowText(mode, s, tot, time)
  local pct = s.pct or min(100, s.amount / (mode.secs and time or max(tot, 1)) * 100)
  return (mode.secs and ("%.0fs"):format(s.amount) or fmt(s.amount)) .. " (" .. (mode.rate and (fmt(s.amount / time) .. ", ") or "") .. ("%.1f%%)"):format(pct)
end

local function headText(mode, tot, time)
  return mode.secs and ("%.0fs"):format(time) or (fmt(tot) .. (mode.rate and (" (" .. fmt(tot / time) .. "/s)") or ""))
end

local function rowTip(r)
  local s, mode = r.data, r.mode
  GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
  GameTooltip:AddLine(s.name)
  local function line(k, v) GameTooltip:AddDoubleLine(k, v, 1, 1, 1, 1, 1, 1) end
  if mode.log then
    GameTooltip:AddLine(("%.0f%% health after"):format(s.pct), 1, 1, 1)
    if (s.overkill or 0) > 0 then line("Overkill", fmt(s.overkill)) end
  elseif mode.count or mode.secs then line("Count", s.hits)
  else
    line("Hits", s.hits)
    if s.crits > 0 then line("Crits", ("%d (%.0f%%)"):format(s.crits, s.crits / max(s.hits, 1) * 100)) end
    if s.hits > 0 then line("Average", fmt(s.amount / s.hits)) end
    if s.crits > 0 and s.hits > s.crits then line("Normal / crit avg", fmt((s.amount - s.critAmt) / (s.hits - s.crits)) .. " / " .. fmt(s.critAmt / s.crits)) end
    if s.min then line("Min / max", fmt(s.min) .. " / " .. fmt(s.max)) end
    if mode.rate then line("Per second", fmt(s.amount / r.time)) end
    if (s.overkill or 0) > 0 then line("Overkill", fmt(s.overkill)) end
    if s.miss then
      local parts = {}
      for kind, n in pairs(s.miss) do parts[#parts + 1] = kind:sub(1, 1) .. kind:sub(2):lower() .. " " .. n end
      table.sort(parts)
      line("Avoided", table.concat(parts, ", "))
    end
    if s.targets then
      local ts = {}
      for name, amt in pairs(s.targets) do ts[#ts + 1] = { name, amt } end
      table.sort(ts, function(a, b) return a[2] > b[2] end)
      GameTooltip:AddLine(" ")
      for i = 1, min(5, #ts) do line(ts[i][1], fmt(ts[i][2]) .. (" (%.0f%%)"):format(ts[i][2] / max(s.amount, 1) * 100)) end
    end
  end
  GameTooltip:Show()
end

local refresh, applyVisibility

local function report(f, chan, target, n)
  local mode, label, tot, _, time = collect(f.cfg)
  chan = chan or (IsInRaid() and "RAID" or IsInGroup() and "PARTY" or "SAY")
  SendChatMessage(("Metails! %s - %s: %s"):format(mode.label, label, headText(mode, tot, time)), chan, nil, target)
  for i = 1, min(n or 5, #list) do
    SendChatMessage(("%d. %s  %s"):format(i, list[i].name, rowText(mode, list[i], tot, time)), chan, nil, target)
  end
end

local function reset()
  db.segments, db.overall, cur = {}, { time = 0 }, nil
  for _, f in ipairs(windows) do f.cfg.view = 1; refresh(f) end
end

local function openMenu(f)
  MenuUtil.CreateContextMenu(f, function(_, root)
    root:CreateTitle("Metails!")
    local views = root:CreateButton("View")
    for i, mode in ipairs(MODES) do
      views:CreateRadio(mode.label, function() return f.cfg.mode == i end, function() f.cfg.mode = i; refresh(f) end)
    end
    local segs = root:CreateButton("Segment")
    for i = 1, nviews() do
      segs:CreateRadio(segLabel(i), function() return f.cfg.view == i end, function() f.cfg.view = i; refresh(f) end)
    end
    root:CreateButton("Report to chat", function() report(f) end)
    root:CreateCheckbox("Locked", function() return f.cfg.locked end, function() f.cfg.locked = not f.cfg.locked end)
    root:CreateButton("Reset data", reset)
  end)
end

local function onClick(r, btn)
  local f = r.win or r
  if f.dragged then f.dragged = nil return end
  if btn == "LeftButton" then f.cfg.mode = (f.cfg.mode - 1 + (IsShiftKeyDown() and -1 or 1)) % #MODES + 1
  elseif MenuUtil and MenuUtil.CreateContextMenu then openMenu(f) return
  else f.cfg.view = f.cfg.view % nviews() + 1 end
  refresh(f)
end

local function styleText(fs)
  local path, _, flags = fs:GetFont()
  fs:SetFont(path, db.opts.fontsize, flags)
end

local function rowAt(f, i)
  local r = f.rows[i]
  if r then return r end
  r = CreateFrame("StatusBar", nil, f)
  r.win = f
  r:SetSize(210, 16)
  r:SetPoint("TOPLEFT", 19, -(18 + (i - 1) * ROWH))
  r:SetStatusBarTexture(TEXTURES[db.opts.texture])
  r:SetStatusBarColor(f.color.r, f.color.g, f.color.b, 0.8)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(16, 16); r.icon:SetPoint("RIGHT", r, "LEFT", -1, 0)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.left = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.left:SetPoint("LEFT", 3, 0); r.left:SetJustifyH("LEFT")
  r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.right:SetPoint("RIGHT", -3, 0)
  r.left:SetPoint("RIGHT", r.right, "LEFT", -4, 0)
  styleText(r.left); styleText(r.right)
  r:EnableMouse(true)
  r:SetScript("OnEnter", rowTip)
  r:SetScript("OnLeave", GameTooltip_Hide)
  r:SetScript("OnMouseUp", onClick)
  f.rows[i] = r
  return r
end

function refresh(f)
  if not f:IsShown() then return end
  local mode, label, tot, top, time = collect(f.cfg)
  f.title:SetText(mode.label .. " - " .. label)
  f.rate:SetText(headText(mode, tot, time))
  local n = tot > 0 and min(#list, db.opts.rows) or 0
  for i = 1, max(n, #f.rows) do
    local r = rowAt(f, i)
    r:SetShown(i <= n)
    if i <= n then
      local s = list[i]
      r.data, r.mode, r.time = s, mode, time
      r:SetMinMaxValues(0, top)
      r:SetValue(s.amount)
      r.icon:SetTexture(s.icon)
      r.left:SetText(s.name)
      r.right:SetText(rowText(mode, s, tot, time))
    end
  end
  f:SetHeight(18 + n * ROWH + (n == 0 and 0 or 2))
end

local function refreshAll()
  flushUptime(GetTime())
  for _, f in ipairs(windows) do refresh(f) end
end

function applyVisibility()
  local combat, hide = UnitAffectingCombat("player"), db.opts.autohide
  for _, f in ipairs(windows) do
    f:SetShown(not f.cfg.hidden and not (hide == "combat" and combat) and not (hide == "ooc" and not combat))
    refresh(f)
  end
end

local function applyOpts()
  for _, f in ipairs(windows) do
    f:SetBackdropColor(0, 0, 0, db.opts.alpha)
    for _, r in ipairs(f.rows) do r:SetStatusBarTexture(TEXTURES[db.opts.texture]); styleText(r.left); styleText(r.right) end
  end
  applyVisibility()
end

local function newWindow(cfg)
  local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  f.cfg, f.rows = cfg, {}
  f.color = RAID_CLASS_COLORS[select(2, UnitClass("player"))] or { r = 0.6, g = 0.6, b = 0.6 }
  f:SetSize(WIDTH, 18)
  f:SetPoint(cfg.pos[1], UIParent, cfg.pos[2], cfg.pos[3], cfg.pos[4])
  f:SetScale(cfg.scale)
  f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
  f:SetBackdropColor(0, 0, 0, db.opts.alpha)
  f:SetMovable(true); f:EnableMouse(true); f:EnableMouseWheel(true); f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(s) if not cfg.locked then s.dragged = true; s:StartMoving() end end)
  f:SetScript("OnDragStop", function(s) s:StopMovingOrSizing(); local p, _, rp, x, y = s:GetPoint(); cfg.pos = { p, rp, x, y } end)
  f:SetScript("OnMouseUp", onClick)
  f:SetScript("OnMouseWheel", function(s, d) cfg.view = (cfg.view - 1 - d) % nviews() + 1; refresh(s) end)
  f:SetScript("OnEnter", function(s)
    GameTooltip:SetOwner(s, "ANCHOR_TOP")
    GameTooltip:AddLine("Metails!")
    GameTooltip:AddLine("Left-click: next view (shift: previous)\nRight-click: menu   Wheel: segment   Drag: move\n/metails help for commands", 1, 1, 1)
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", GameTooltip_Hide)
  f.header = f:CreateTexture(nil, "BACKGROUND")
  f.header:SetPoint("TOPLEFT"); f.header:SetPoint("TOPRIGHT"); f.header:SetHeight(18)
  f.header:SetColorTexture(f.color.r * 0.45, f.color.g * 0.45, f.color.b * 0.45, 0.9)
  f.close = CreateFrame("Button", nil, f)
  f.close:SetSize(14, 14); f.close:SetPoint("TOPRIGHT", -2, -2)
  f.close:SetNormalFontObject("GameFontNormalSmall"); f.close:SetText("x")
  f.close:SetScript("OnClick", function() cfg.hidden = true; applyVisibility() end)
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.title:SetPoint("TOPLEFT", 4, -3); f.title:SetJustifyH("LEFT")
  f.rate = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.rate:SetPoint("RIGHT", f.close, "LEFT", -3, 0)
  f.title:SetPoint("RIGHT", f.rate, "LEFT", -4, 0)
  windows[#windows + 1] = f
  return f
end

local function defaultWindow(i)
  return { mode = 1, view = 1, scale = 1, pos = { "CENTER", "CENTER", 300 - (i - 1) * 250, -150 } }
end

local function num(v, lo, hi, default)
  return type(v) == "number" and min(max(v, lo), hi) or default
end

BINDING_HEADER_METAILS, BINDING_NAME_METAILS_TOGGLE = "Metails!", "Show or hide Metails!"

function Metails_Toggle()
  local anyShown = false
  for _, f in ipairs(windows) do anyShown = anyShown or not f.cfg.hidden end
  for _, f in ipairs(windows) do f.cfg.hidden = anyShown end
  applyVisibility()
end

local HELP = [[/metails - show or hide the window
/metails report [say|party|raid|guild|name] [lines] - post the current view to chat
/metails new, close - open or close a second window
/metails reset - clear all data
/metails lock - lock or unlock window positions
/metails scale <n>, rows <n>, alpha <0-1>, fontsize <n> - size, rows, opacity, font
/metails texture <smooth|flat|raid> - bar texture
/metails autohide <combat|ooc|off> - hide in combat or out of combat
/metails pets <rows|group|off> - pet rows alongside yours, one row per pet, or ignored
/metails minimap - show or hide the minimap button]]

local minimapBtn
local function minimapPos(b)
  local a = math.rad(db.opts.minimap)
  b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * 80, math.sin(a) * 80)
end

local function buildMinimap()
  local b = CreateFrame("Button", nil, Minimap)
  b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp"); b:RegisterForDrag("LeftButton")
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53); border:SetPoint("TOPLEFT"); border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  local icon = b:CreateTexture(nil, "BACKGROUND")
  icon:SetSize(20, 20); icon:SetPoint("CENTER", 0, 1); icon:SetTexture("Interface\\Icons\\Ability_Warrior_Rampage"); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  b:SetScript("OnClick", function(_, btn)
    if btn == "LeftButton" then Metails_Toggle() elseif MenuUtil and MenuUtil.CreateContextMenu then openMenu(windows[1]) end
  end)
  b:SetScript("OnDragStart", function(s)
    s:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local sc = Minimap:GetEffectiveScale()
      db.opts.minimap = math.deg(atan2(cy / sc - my, cx / sc - mx))
      minimapPos(s)
    end)
  end)
  b:SetScript("OnDragStop", function(s) s:SetScript("OnUpdate", nil) end)
  b:SetScript("OnEnter", function(s)
    GameTooltip:SetOwner(s, "ANCHOR_LEFT")
    GameTooltip:AddLine("Metails!")
    GameTooltip:AddLine("Left-click: show or hide\nRight-click: menu\nDrag: move", 1, 1, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  minimapPos(b)
  b:SetShown(not db.opts.minimapHidden)
  minimapBtn = b
end

local CMD = {}
CMD[""] = Metails_Toggle
CMD.reset = reset
function CMD.minimap() db.opts.minimapHidden = not db.opts.minimapHidden; minimapBtn:SetShown(not db.opts.minimapHidden) end

local function buildOptions()
  local panel = CreateFrame("Frame")
  panel.name = "Metails!"
  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16); title:SetText("Metails!")
  local body = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12); body:SetWidth(580); body:SetJustifyH("LEFT")
  body:SetText("A personal combat meter. Left-click the window for the next view, right-click for the menu, mouse wheel for fight segments, drag to move.\n\n" .. HELP)
  local x = 0
  for _, b in ipairs({ { "Show / hide", Metails_Toggle }, { "New window", CMD.new }, { "Minimap button", CMD.minimap }, { "Reset data", reset } }) do
    local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btn:SetSize(130, 24); btn:SetPoint("TOPLEFT", body, "BOTTOMLEFT", x, -16); btn:SetText(b[1]); btn:SetScript("OnClick", b[2])
    x = x + 136
  end
  if Settings and Settings.RegisterCanvasLayoutCategory then
    Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(panel, panel.name))
  elseif InterfaceOptions_AddCategory then InterfaceOptions_AddCategory(panel) end
end
function CMD.lock() for _, f in ipairs(windows) do f.cfg.locked = not f.cfg.locked end; print("Metails!: " .. (windows[1].cfg.locked and "locked" or "unlocked")) end
function CMD.scale(a) for _, f in ipairs(windows) do f.cfg.scale = num(tonumber(a), 0.5, 3, 1); f:SetScale(f.cfg.scale) end end
function CMD.rows(a) db.opts.rows = num(tonumber(a), 1, 40, 10); refreshAll() end
function CMD.alpha(a) db.opts.alpha = num(tonumber(a), 0, 1, 0.55); applyOpts() end
function CMD.fontsize(a) db.opts.fontsize = num(tonumber(a), 6, 20, 10); applyOpts() end
function CMD.texture(a) if TEXTURES[a] then db.opts.texture = a; applyOpts() else print("Metails!: texture smooth, flat or raid") end end
function CMD.autohide(a) if a == "combat" or a == "ooc" or a == "off" then db.opts.autohide = a; applyVisibility() else print("Metails!: autohide combat, ooc or off") end end
function CMD.pets(a) if a == "rows" or a == "group" or a == "off" then db.opts.pets = a else print("Metails!: pets rows, group or off") end end
function CMD.new() newWindow(defaultWindow(#windows + 1)); db.windows[#windows] = windows[#windows].cfg; refreshAll() end
function CMD.close()
  if #windows == 1 then return end
  table.remove(windows):Hide()
  db.windows[#windows + 1] = nil
end
function CMD.report(a)
  local who, n = a:match("^(%S*)%s*(%d*)$")
  local chan, target = CHANNELS[who:lower()], nil
  if not chan and who ~= "" then chan, target = "WHISPER", who end
  report(windows[1], chan, target, tonumber(n))
end
function CMD.help() print("Metails!\n" .. HELP) end

SLASH_METAILS1 = "/metails"
SlashCmdList.METAILS = function(msg)
  local cmd, arg = msg:match("^(%S*)%s*(.-)$")
  local fn = CMD[cmd:lower()]
  if fn then fn(arg) else CMD.help() end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, e, ...)
  if e == "COMBAT_LOG_EVENT_UNFILTERED" then cleu(CombatLogGetCurrentEventInfo())
  elseif e == "PLAYER_REGEN_ENABLED" then
    if cur then flushUptime(GetTime()); wipe(active.debuffs); wipe(onTarget); cur = nil end
    applyVisibility()
  elseif e == "PLAYER_REGEN_DISABLED" then applyVisibility()
  elseif e == "ENCOUNTER_START" then
    local _, name = ...
    cur = nil; touch(); cur.name, cur.boss = name, true
  elseif e == "ENCOUNTER_END" then
    local _, name, _, _, success = ...
    if cur and cur.boss then cur.name = name .. (success == 1 and "" or " (wipe)") end
  elseif e == "PLAYER_LOGIN" then
    MetailsDB = MetailsDB or {}
    db = MetailsDB
    if type(db.segments) ~= "table" or type(db.overall) ~= "table" or type(db.overall.time) ~= "number" then db.segments, db.overall = {}, { time = 0 } end
    if db.mode then db.windows = { { mode = db.mode, view = db.view, scale = db.scale, pos = db.pos, hidden = db.hidden, locked = db.locked } } end
    db.mode, db.view, db.scale, db.pos, db.hidden, db.locked = nil
    if type(db.windows) ~= "table" or not db.windows[1] then db.windows = { defaultWindow(1) } end
    for i, w in ipairs(db.windows) do
      w.mode = (type(w.mode) == "number" and MODES[w.mode]) and w.mode or 1
      w.view = type(w.view) == "number" and w.view or 1
      w.scale = num(w.scale, 0.5, 3, 1)
      if type(w.pos) ~= "table" or type(w.pos[3]) ~= "number" or type(w.pos[4]) ~= "number" then w.pos = defaultWindow(i).pos end
    end
    local o = type(db.opts) == "table" and db.opts or {}
    db.opts = { rows = num(o.rows, 1, 40, 10), alpha = num(o.alpha, 0, 1, 0.55), fontsize = num(o.fontsize, 6, 20, 10),
                texture = TEXTURES[o.texture] and o.texture or "smooth", autohide = o.autohide or "off", pets = o.pets or "rows",
                minimap = num(o.minimap, -360, 360, 220), minimapHidden = o.minimapHidden == true }
    playerGUID = UnitGUID("player")
    if AuraUtil and AuraUtil.ForEachAura then
      AuraUtil.ForEachAura("player", "HELPFUL", nil, function(name, tex) active.buffs[name] = { t = GetTime(), icon = tex, n = 1 } end)
    end
    for _, w in ipairs(db.windows) do newWindow(w) end
    buildMinimap(); buildOptions()
    applyVisibility()
    C_Timer.NewTicker(0.5, refreshAll)
    for _, name in ipairs({ "COMBAT_LOG_EVENT_UNFILTERED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "ENCOUNTER_START", "ENCOUNTER_END" }) do ev:RegisterEvent(name) end
  end
end)
