local min, max = math.min, math.max
local atan2 = math.atan2 or math.atan
local secret = issecretvalue or function() return false end
local function plain(v) return v ~= nil and not secret(v) end
local DMT, DMS = Enum and Enum.DamageMeterType, Enum and Enum.DamageMeterSessionType
local MODES = {}
local function mode(label, t, kind, tip) if t ~= nil then MODES[#MODES + 1] = { label = label, type = t, rate = kind == "rate", by = kind == "by", log = kind == "log", tip = tip or "Targets" } end end
if DMT then
  mode("Damage Done", DMT.DamageDone or DMT.Dps, "rate")
  mode("Damage Taken", DMT.DamageTaken, "rate", "From")
  mode("Damage Taken by Source", DMT.DamageTaken, "by", "Spells")
  mode("Avoidable Damage Taken", DMT.AvoidableDamageTaken, nil, "From")
  mode("Healing Done", DMT.HealingDone or DMT.Hps, "rate")
  mode("Absorbs", DMT.Absorbs)
  mode("Interrupts", DMT.Interrupts)
  mode("Dispels", DMT.Dispels)
  mode("Deaths", DMT.Deaths, "log")
end
local WIDTH, ROWH = 230, 17
local TEXTURES = { smooth = "Interface\\TargetingFrame\\UI-StatusBar", flat = "Interface\\Buttons\\WHITE8x8", raid = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" }
local CHANNELS = { say = "SAY", yell = "YELL", party = "PARTY", raid = "RAID", guild = "GUILD", officer = "OFFICER", instance = "INSTANCE_CHAT" }
local db, windows, history, lastSnap = nil, {}, {}, 0

local function fmt(n)
  if n >= 1e6 then return ("%.2fM"):format(n / 1e6) end
  if n >= 1e3 then return ("%.1fk"):format(n / 1e3) end
  return ("%.0f"):format(n)
end

local BREAKPOINTS = { breakpointData = {
  { breakpoint = 1e6, significandDivisor = 1e4, fractionDivisor = 100, abbreviation = "M", abbreviationIsGlobal = false },
  { breakpoint = 1e3, significandDivisor = 100, fractionDivisor = 10, abbreviation = "k", abbreviationIsGlobal = false },
  { breakpoint = 0, significandDivisor = 1, fractionDivisor = 1, abbreviation = "", abbreviationIsGlobal = false },
} }

local function abbrev(v)
  if v == nil then return "0" end
  if plain(v) then return fmt(v) end
  return AbbreviateNumbers and AbbreviateNumbers(v, BREAKPOINTS) or "?"
end

local function spellName(id)
  local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
  return n or (GetSpellInfo and GetSpellInfo(id)) or ("Spell " .. id)
end

local function icon(id)
  return id and id > 0 and C_Spell.GetSpellTexture(id) or 132349
end

local function views()
  local v = { { label = "Current", type = DMS.Current } }
  if DMS.Expired then v[#v + 1] = { label = "Previous", type = DMS.Expired } end
  v[#v + 1] = { label = "Overall", type = DMS.Overall }
  for i = #history, 1, -1 do v[#v + 1] = history[i] end
  return v
end

local function refreshHistory()
  wipe(history)
  local ok, list = pcall(C_DamageMeter.GetAvailableCombatSessions)
  if not ok or not plain(list) then return end
  for _, s in ipairs(list) do
    if plain(s) and plain(s.sessionID) then history[#history + 1] = { id = s.sessionID, label = plain(s.name) and s.name ~= "" and s.name or ("Fight " .. s.sessionID) } end
  end
end

local function session(v, t)
  local ok, s = pcall(v.id and C_DamageMeter.GetCombatSessionFromID or C_DamageMeter.GetCombatSessionFromType, v.id or v.type, t)
  return ok and plain(s) and s or nil
end

local function spells(v, t, me)
  local ok, s = pcall(v.id and C_DamageMeter.GetCombatSessionSourceFromID or C_DamageMeter.GetCombatSessionSourceFromType, v.id or v.type, t, me.sourceGUID, me.sourceCreatureID)
  return ok and plain(s) and plain(s.combatSpells) and s.combatSpells or nil
end

local function units(sp, out)
  local d = sp.combatSpellDetails
  if not plain(d) then return end
  if d.unitName ~= nil then d = { d } end
  for _, u in ipairs(d) do
    if plain(u) and u.unitName ~= nil and u.amount ~= nil and (secret(u.amount) or (plain(u.unitName) and u.unitName ~= "" and u.amount > 0)) then
      out[#out + 1] = { name = u.unitName, amount = u.amount }
    end
  end
end

local function deathRows(recap, rows)
  local ok, raw = pcall(C_DeathRecap.GetRecapEvents, recap)
  if not ok or not plain(raw) then return end
  local ok2, hp = pcall(C_DeathRecap.GetRecapMaxHealth, recap)
  hp = ok2 and plain(hp) and hp > 0 and hp or 1
  local t0 = raw[1] and plain(raw[1].timestamp) and raw[1].timestamp
  for i = #raw, 1, -1 do
    local e = raw[i]
    if plain(e) and plain(e.amount) then
      local heal = e.event == "SPELL_HEAL" or e.event == "SPELL_PERIODIC_HEAL"
      local name = plain(e.spellName) and e.spellName ~= "" and e.spellName or (e.event == "SWING_DAMAGE" and "Melee" or "Unknown")
      local dt = t0 and plain(e.timestamp) and (e.timestamp - t0) or 0
      rows[#rows + 1] = { name = ("%.1fs %s%s"):format(dt, heal and "+" or "", name), icon = icon(plain(e.spellId) and e.spellId or 0),
                          amount = e.amount, pct = plain(e.currentHP) and e.currentHP / hp * 100 or 0, overkill = plain(e.overkill) and e.overkill }
    end
  end
end

local function snapshot(f)
  local m, v = MODES[f.cfg.mode], views()[f.cfg.view]
  if not v then f.cfg.view = 1; v = views()[1] end
  local s = session(v, m.type)
  if not s or not plain(s.combatSources) then return end
  local me
  for _, src in ipairs(s.combatSources) do
    if plain(src) and plain(src.isLocalPlayer) and src.isLocalPlayer then me = src break end
  end
  local snap = { label = m.label .. " - " .. v.label, total = 0, rate = 0, rows = {}, time = plain(s.durationSeconds) and s.durationSeconds or 0 }
  if me then
    if me.totalAmount ~= nil then snap.total = me.totalAmount end
    if me.amountPerSecond ~= nil then snap.rate = me.amountPerSecond end
    snap.locked = secret(snap.total) or secret(snap.rate)
    if m.log then
      if plain(me.deathRecapID) and C_DeathRecap then deathRows(me.deathRecapID, snap.rows) end
    else
      local byUnit = {}
      for _, sp in ipairs(spells(v, m.type, me) or {}) do
        local amt = plain(sp) and sp.totalAmount or nil
        if amt ~= nil and (secret(amt) or amt > 0) and sp.spellID ~= nil then
          local name = secret(sp.spellID) and C_Spell.GetSpellName(sp.spellID) or spellName(sp.spellID)
          if plain(name) and plain(sp.creatureName) and sp.creatureName ~= "" then name = name .. " (" .. sp.creatureName .. ")" end
          local row = { name = name, icon = secret(sp.spellID) and C_Spell.GetSpellTexture(sp.spellID) or icon(sp.spellID), amount = amt, rate = sp.amountPerSecond,
                        overkill = plain(sp.overkillAmount) and sp.overkillAmount > 0 and sp.overkillAmount or nil, units = {} }
          if secret(amt) then snap.locked = true end
          units(sp, row.units)
          if m.by and not secret(amt) then
            for _, u in ipairs(row.units) do
              local r = byUnit[u.name] or { name = u.name, icon = 132349, amount = 0, units = {} }
              byUnit[u.name] = r
              r.amount = r.amount + u.amount
              r.units[#r.units + 1] = { name = row.name, amount = u.amount }
            end
          else snap.rows[#snap.rows + 1] = row end
        end
      end
      for _, r in pairs(byUnit) do snap.rows[#snap.rows + 1] = r end
      if not snap.locked then
        table.sort(snap.rows, function(a, b) return a.amount > b.amount end)
        if m.by then snap.total = 0; for _, r in ipairs(snap.rows) do snap.total = snap.total + r.amount end end
      end
    end
  end
  f.snap = snap
end

local function rowText(m, s, tot)
  local pct = s.pct or s.amount / max(tot, 1) * 100
  return fmt(s.amount) .. " (" .. (m.rate and s.rate and (fmt(s.rate) .. ", ") or "") .. ("%.1f%%)"):format(pct)
end

local function headText(m, snap)
  return fmt(snap.total) .. (m.rate and (" (" .. fmt(snap.rate) .. "/s)") or "")
end

local tip

local function tipLine(i, left, right)
  local l = tip.lines[i]
  if not l then
    l = { left = tip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), right = tip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") }
    l.left:SetPoint("TOPLEFT", 8, -(22 + (i - 1) * 14)); l.left:SetJustifyH("LEFT")
    l.right:SetPoint("TOPRIGHT", -8, -(22 + (i - 1) * 14)); l.right:SetJustifyH("RIGHT")
    tip.lines[i] = l
  end
  l.left:SetText(left); l.right:SetFormattedText("%s", right)
  l.left:Show(); l.right:Show()
end

local function rowTip(r)
  local s, m = r.data, r.mode
  if not tip then
    tip = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    tip.isTip, tip.lines = true, {}
    tip:SetWidth(220); tip:SetFrameStrata("TOOLTIP"); tip:SetClampedToScreen(true)
    tip:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    tip:SetBackdropColor(0.05, 0.05, 0.05, 0.95); tip:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    tip.title = tip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tip.title:SetPoint("TOPLEFT", 8, -6); tip.title:SetPoint("TOPRIGHT", -8, -6); tip.title:SetJustifyH("LEFT"); tip.title:SetWordWrap(false)
    tip:EnableMouse(false)
    tip:SetScript("OnUpdate", function(s, dt)
      s.t = (s.t or 0) + dt
      if s.t < 0.1 then return end
      s.t = 0
      if not (s.row and s.row:IsMouseOver()) then s:Hide() end
    end)
  end
  tip.row, tip.t = r, 0
  for _, l in ipairs(tip.lines) do l.left:Hide(); l.right:Hide() end
  tip.title:SetText(s.name)
  local n = 0
  local function line(l, v) n = n + 1; tipLine(n, l, v) end
  if m.log and plain(s.pct) then line("Health after", ("%.0f%%"):format(s.pct)) end
  if s.rate ~= nil then line("Per second", abbrev(s.rate)) end
  if s.overkill then line("Overkill", abbrev(s.overkill)) end
  if s.units and #s.units > 0 then
    local unlocked = plain(s.amount)
    for _, u in ipairs(s.units) do unlocked = unlocked and plain(u.amount) end
    if unlocked then table.sort(s.units, function(a, b) return a.amount > b.amount end) end
    line(m.tip, "")
    for i = 1, min(5, #s.units) do
      local u = s.units[i]
      line(u.name, unlocked and (fmt(u.amount) .. (" (%.0f%%)"):format(u.amount / max(s.amount, 1) * 100)) or abbrev(u.amount))
    end
  end
  tip:SetHeight(26 + n * 14)
  tip:ClearAllPoints(); tip:SetPoint("TOPLEFT", r.win, "TOPRIGHT", 4, 0)
  tip:Show()
end

local function hideTip(r) if tip and not r:IsMouseOver() then tip:Hide() end end

local refresh, applyVisibility

local function snapshotAll(force)
  local now = GetTime()
  if not force and now - lastSnap < 0.25 then return end
  lastSnap = now
  for _, f in ipairs(windows) do if f:IsShown() then snapshot(f); refresh(f) end end
end

local function report(f, chan, target, n)
  local m, snap = MODES[f.cfg.mode], f.snap
  if not snap then return end
  if snap.locked then print("Metails!: the numbers are locked until the fight ends.") return end
  chan = chan or (IsInRaid() and "RAID" or IsInGroup() and "PARTY" or "SAY")
  local head = ("Metails! %s: %s"):format(snap.label, headText(m, snap))
  local lines = {}
  for i = 1, min(n or 5, #snap.rows) do lines[i] = ("%d. %s  %s"):format(i, snap.rows[i].name, rowText(m, snap.rows[i], snap.total)) end
  if chan == "SAY" or chan == "YELL" then SendChatMessage(head .. " | " .. table.concat(lines, " | "), chan) return end
  SendChatMessage(head, chan, nil, target)
  for _, l in ipairs(lines) do SendChatMessage(l, chan, nil, target) end
end

local function reset()
  C_DamageMeter.ResetAllCombatSessions()
  for _, f in ipairs(windows) do f.cfg.view = 1; f.snap = nil end
  refreshHistory()
  snapshotAll(true)
end

local function openMenu(f)
  MenuUtil.CreateContextMenu(f, function(_, root)
    root:CreateTitle("Metails!")
    local vs = root:CreateButton("View")
    for i, m in ipairs(MODES) do
      vs:CreateRadio(m.label, function() return f.cfg.mode == i end, function() f.cfg.mode = i; snapshot(f); refresh(f) end)
    end
    local segs = root:CreateButton("Fight")
    for i, v in ipairs(views()) do
      segs:CreateRadio(v.label, function() return f.cfg.view == i end, function() f.cfg.view = i; snapshot(f); refresh(f) end)
    end
    root:CreateButton("Report to chat", function() report(f) end)
    root:CreateCheckbox("Locked", function() return f.cfg.locked end, function() f.cfg.locked = not f.cfg.locked end)
    root:CreateButton("Reset data", reset)
  end)
end

local function hasData(f, i)
  local s = session(views()[f.cfg.view] or views()[1], MODES[i].type)
  if not s or not plain(s.combatSources) then return false end
  for _, src in ipairs(s.combatSources) do
    if plain(src) and plain(src.isLocalPlayer) and src.isLocalPlayer then return plain(src.totalAmount) and src.totalAmount > 0 end
  end
  return false
end

local function onClick(r, btn)
  local f = r.win or r
  if f.dragged then f.dragged = nil return end
  if btn == "LeftButton" then
    local step, i = IsShiftKeyDown() and -1 or 1, f.cfg.mode
    for _ = 1, #MODES do
      i = (i - 1 + step) % #MODES + 1
      if hasData(f, i) then break end
    end
    f.cfg.mode = hasData(f, i) and i or (f.cfg.mode - 1 + step) % #MODES + 1
  elseif MenuUtil and MenuUtil.CreateContextMenu then openMenu(f) return
  else f.cfg.view = f.cfg.view % #views() + 1 end
  snapshot(f); refresh(f)
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
  r:SetScript("OnLeave", hideTip)
  r:SetScript("OnMouseUp", onClick)
  f.rows[i] = r
  return r
end

function refresh(f)
  if not f:IsShown() then return end
  local m, snap = MODES[f.cfg.mode], f.snap
  if not snap then
    local v = views()[f.cfg.view] or views()[1]
    snap = { label = m.label .. " - " .. v.label, total = 0, rate = 0, rows = {} }
  end
  f.title:SetText(snap.label)
  if snap.locked then f.rate:SetFormattedText(m.rate and "%s (%s/s)" or "%s", abbrev(snap.total), abbrev(snap.rate))
  else f.rate:SetText(headText(m, snap)) end
  local n = min(#snap.rows, db.opts.rows)
  local top = snap.rows[1] and snap.rows[1].amount or 0
  for i = 1, max(n, #f.rows) do
    local r = rowAt(f, i)
    r:SetShown(i <= n)
    if i <= n then
      local s = snap.rows[i]
      r.data, r.mode = s, m
      r:SetMinMaxValues(0, top)
      r:SetValue(s.amount)
      r.icon:SetTexture(s.icon)
      r.left:SetText(s.name)
      if snap.locked then r.right:SetFormattedText(m.rate and s.rate ~= nil and "%s (%s)" or "%s", abbrev(s.amount), abbrev(s.rate))
      else r.right:SetText(rowText(m, s, snap.total)) end
    end
  end
  f:SetHeight(18 + n * ROWH + (n == 0 and 0 or 2))
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
  f:SetScript("OnMouseWheel", function(s, d) cfg.view = (cfg.view - 1 - d) % #views() + 1; snapshot(s); refresh(s) end)
  f:SetScript("OnEnter", function(s)
    GameTooltip:SetOwner(s, "ANCHOR_TOP")
    GameTooltip:AddLine("Metails!")
    GameTooltip:AddLine("Left-click: next view (shift: previous)\nRight-click: menu   Wheel: fight   Drag: move\n/metails help for commands", 1, 1, 1)
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
  f.title:SetPoint("TOPLEFT", 4, -3); f.title:SetJustifyH("LEFT"); f.title:SetWordWrap(false)
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
  snapshotAll(true)
end

local HELP = [[/metails - show or hide the window
/metails report [say|party|raid|guild|name] [lines] - post the current view to chat
/metails new, close - open or close a second window
/metails reset - clear Blizzard's combat data
/metails lock - lock or unlock window positions
/metails scale <n>, rows <n>, alpha <0-1>, fontsize <n> - size, rows, opacity, font
/metails texture <smooth|flat|raid> - bar texture
/metails autohide <combat|ooc|off> - hide in combat or out of combat
/metails minimap - show or hide the minimap button
/metails diag - print whether the game is handing over readable numbers]]

local minimapBtn
local function minimapPos(b)
  local a, r = math.rad(db.opts.minimap), Minimap:GetWidth() / 2 + 10
  b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function buildMinimap()
  local b = CreateFrame("Button", nil, Minimap)
  b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp"); b:RegisterForDrag("LeftButton")
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53); border:SetPoint("TOPLEFT"); border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  local ic = b:CreateTexture(nil, "BACKGROUND")
  ic:SetSize(20, 20); ic:SetPoint("CENTER", 0, 1); ic:SetTexture("Interface\\Icons\\Ability_Warrior_Rampage"); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
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
function CMD.lock() for _, f in ipairs(windows) do f.cfg.locked = not f.cfg.locked end; print("Metails!: " .. (windows[1].cfg.locked and "locked" or "unlocked")) end
function CMD.scale(a) for _, f in ipairs(windows) do f.cfg.scale = num(tonumber(a), 0.5, 3, 1); f:SetScale(f.cfg.scale) end end
function CMD.rows(a) db.opts.rows = num(tonumber(a), 1, 40, 10); applyVisibility() end
function CMD.alpha(a) db.opts.alpha = num(tonumber(a), 0, 1, 0.55); applyOpts() end
function CMD.fontsize(a) db.opts.fontsize = num(tonumber(a), 6, 20, 10); applyOpts() end
function CMD.texture(a) if TEXTURES[a] then db.opts.texture = a; applyOpts() else print("Metails!: texture smooth, flat or raid") end end
function CMD.autohide(a) if a == "combat" or a == "ooc" or a == "off" then db.opts.autohide = a; applyVisibility() else print("Metails!: autohide combat, ooc or off") end end
function CMD.new() newWindow(defaultWindow(#windows + 1)); db.windows[#windows] = windows[#windows].cfg; snapshotAll(true) end
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

local events, diagArmed, refused = 0, false, {}
local function probe(where)
  local s = session(views()[1], MODES[1].type)
  local me
  for _, src in ipairs(s and plain(s.combatSources) and s.combatSources or {}) do
    if plain(src) and plain(src.isLocalPlayer) and src.isLocalPlayer then me = src end
  end
  local function tag(v) return v == nil and "nil" or secret(v) and "secret" or "readable" end
  print(("Metails! %s: session %s, you %s, total %s, per second %s, duration %s"):format(where, s and "found" or "none", me and "found" or "none",
    tag(me and me.totalAmount), tag(me and me.amountPerSecond), tag(s and s.durationSeconds)))
  if not me then return end
  local ok, src = pcall(C_DamageMeter.GetCombatSessionSourceFromType, views()[1].type, MODES[1].type, me.sourceGUID, me.sourceCreatureID)
  local list = ok and plain(src) and src.combatSpells or nil
  local first = plain(list) and list[1] or nil
  local fp = plain(first)
  print(("Metails! %s spells: call %s, source %s, list %s with %s entries, first entry %s, its id %s, amount %s, details %s"):format(where, ok and "ok" or ("failed: " .. tostring(src)),
    tag(src), tag(list), plain(list) and tostring(#list) or "?", tag(first), tag(fp and first.spellID), tag(fp and first.totalAmount), tag(fp and first.combatSpellDetails)))
end
function CMD.diag()
  print(("Metails!: %d damage meter events received since login, in combat: %s"):format(events, tostring(UnitAffectingCombat("player"))))
  print("Metails!: events the client refused: " .. (#refused > 0 and table.concat(refused, ", ") or "none"))
  local ok, err = pcall(probe, "outside a handler")
  if not ok then print("Metails! diag error: " .. tostring(err)) end
  diagArmed = true
  print("Metails!: the next damage meter event will print the same check from inside its handler.")
end

local function buildOptions()
  local panel = CreateFrame("Frame")
  panel.name = "Metails!"
  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16); title:SetText("Metails!")
  local body = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12); body:SetWidth(580); body:SetJustifyH("LEFT")
  body:SetText("A personal combat meter. Left-click the window for the next view, right-click for the menu, mouse wheel for fights, drag to move.\n\n" .. HELP)
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

SLASH_METAILS1 = "/metails"
SlashCmdList.METAILS = function(msg)
  if not db then print("Metails!: this game client has no damage meter API.") return end
  local cmd, arg = msg:match("^(%S*)%s*(.-)$")
  local fn = CMD[cmd:lower()]
  if fn then fn(arg) else CMD.help() end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, e)
  if e == "PLAYER_LOGIN" then
    if not DMT or not C_DamageMeter or #MODES == 0 then print("Metails!: this game client has no damage meter API, nothing to show.") return end
    MetailsDB = MetailsDB or {}
    db = MetailsDB
    db.segments, db.overall, db.mode, db.view, db.scale, db.pos, db.hidden, db.locked = nil
    if type(db.windows) ~= "table" or not db.windows[1] then db.windows = { defaultWindow(1) } end
    for i, w in ipairs(db.windows) do
      w.mode = (type(w.mode) == "number" and MODES[w.mode]) and w.mode or 1
      w.view = type(w.view) == "number" and w.view or 1
      w.scale = num(w.scale, 0.5, 3, 1)
      if type(w.pos) ~= "table" or type(w.pos[3]) ~= "number" or type(w.pos[4]) ~= "number" then w.pos = defaultWindow(i).pos end
    end
    local o = type(db.opts) == "table" and db.opts or {}
    db.opts = { rows = num(o.rows, 1, 40, 10), alpha = num(o.alpha, 0, 1, 0.55), fontsize = num(o.fontsize, 6, 20, 10),
                texture = TEXTURES[o.texture] and o.texture or "smooth", autohide = o.autohide or "off",
                minimap = num(o.minimap, -360, 360, 220), minimapHidden = o.minimapHidden == true }
    for _, w in ipairs(db.windows) do newWindow(w) end
    buildMinimap(); buildOptions()
    refreshHistory()
    applyVisibility()
    snapshotAll(true)
    C_Timer.NewTicker(0.5, function() snapshotAll(true) end)
    for _, name in ipairs({ "DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_CURRENT_SESSION_UPDATED", "DAMAGE_METER_RESET", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }) do
      if not pcall(ev.RegisterEvent, ev, name) then refused[#refused + 1] = name end
    end
  elseif e == "DAMAGE_METER_RESET" then
    for _, f in ipairs(windows) do f.snap = nil end
    refreshHistory(); snapshotAll(true)
  elseif e == "PLAYER_REGEN_ENABLED" then refreshHistory(); applyVisibility(); snapshotAll(true)
  elseif e == "PLAYER_REGEN_DISABLED" then applyVisibility(); snapshotAll(true)
  else
    events = events + 1
    if diagArmed then
      diagArmed = false
      local ok, err = pcall(probe, "inside " .. e)
      if not ok then print("Metails! diag error: " .. tostring(err)) end
    end
    snapshotAll()
  end
end)
