--[[ Hated Companion: boss plans
  The website (hatedforever.com > Boss Strategies > Save to my addon) writes Plan\HatedPlan.lua and each boss's
  screenshot as Plan\Boss_<id>.tga. This shows them:
    left    the bosses, by raid
    middle  the fight: your own jobs first (glowing), then notes, tanks, healers, markers, other jobs, kill order
    right   the strategy screenshot (click it to see it bigger)
  The raid leader (or an assistant) can press "Show to raid": the boss's plan is sent over addon messages and opens
  on everyone's screen who has the addon, even if their copy of the plan is older (screenshots come from each
  player's own files).

  /hated        open or close the window
  /hated show   (raid leader / assistant) push the boss you're viewing to the raid
  /hated send   (Raid Leader only) send your whole plan to everyone online in the guild with the addon, and the raid
                if you're in one (text; screenshots stay each player's own files). Players keep it until the next one.
  /hated me X   also highlight assignments for the website name X (/hated me on its own clears it)
]]

local PREFIX = "HATEDPLAN"
local GOLD, DIM = "|cffecc867", "|cff8f7f62"
local ME_COLOR = "|cff4dff88"
local ICON = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:%d|t"
local IMG_PATH = "Interface\\AddOns\\HatedCompanion\\Plan\\"

local function say(msg) DEFAULT_CHAT_FRAME:AddMessage("|cffd6a940Hated Plan:|r " .. msg) end
local function safe(s) return (tostring(s or "")):gsub("|", "||") end
local function icon(i, size) return string.format(ICON, i, size or 16) end

-- ---------- is this name me? ----------
-- WoW Forever characters have a first and a last name. A website name highlights for you when it's inside either
-- one ("Pink" matches Pinkranger Stormwind and Ryan Ironpink). Extra names can be added with /hated me <name>.
local function myNames()
  local list, seen = {}, {}
  local function add(s)
    for w in (s or ""):lower():gmatch("[^%s%-]+") do
      if not seen[w] then seen[w] = true; list[#list + 1] = w end
    end
  end
  add(UnitName("player"))
  add(UnitFullName and select(1, UnitFullName("player")))
  local db = HatedCompanionDB and HatedCompanionDB.planNames
  if db then for _, n in ipairs(db) do add(n) end end
  return list
end
local function matches(name, words)
  if not name or name == "" then return false end
  for site in name:lower():gmatch("[^%s%-]+") do            -- every word of the website name
    for _, w in ipairs(words) do                             -- against a first name, last name (and extras)
      if site == w then return true end
      if #site >= 3 and w:find(site, 1, true) then return true end
    end
  end
  return false
end
local function isMe(name) return matches(name, myNames()) end
local function wordsOf(charName)
  local list = {}
  for w in (charName or ""):lower():gmatch("[^%s%-]+") do list[#list + 1] = w end
  return list
end
-- the Raid Leader (from the website's plan) is the only one who gets "Send plan to guild"
local function leaderName() return HatedPlan and HatedPlan.leader end
local function iAmLeader()
  local l = leaderName()
  if l and l ~= "" then return isMe(l) end
  return IsGuildLeader and IsGuildLeader() or false
end

-- class colour: from the raid if they're in it, else the website's roster
local function classOf(name)
  if UnitExists(name) then local _, c = UnitClass(name); if c then return c end end
  return HatedPlan and HatedPlan.classes and HatedPlan.classes[name]
end
local function nameText(name)
  if not name or name == "" then return DIM .. "?|r" end
  if isMe(name) then return ME_COLOR .. safe(name) .. "|r" end
  local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classOf(name) or ""]
  return (c and ("|c" .. (c.colorStr or "ffffffff")) or "|cffe8d6b0") .. safe(name) .. "|r"
end
local function names(list)
  local out = {}
  for _, n in ipairs(list or {}) do out[#out + 1] = nameText(n) end
  return #out > 0 and table.concat(out, DIM .. ", |r") or DIM .. "nobody|r"
end
local function anyMe(list) for _, n in ipairs(list or {}) do if isMe(n) then return true end end return false end
local TANK_TEX = "Interface\\Icons\\Ability_Defend"
local HEAL_TEX = "Interface\\Icons\\Spell_Holy_Heal"
local JOB_TEX  = "Interface\\Icons\\Ability_Kick"
local MARK_TEX = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"

-- ---------- the fight, as sections of rows ----------
-- each row: left text, right text, me (highlight), mark (raid icon number) ; sections: title, tex (icon), rows
local function bossSections(b)
  local S, mine = {}, {}
  local function section(title, tex, key) local s = { title = title, tex = tex, key = key or title, rows = {} }; S[#S + 1] = s; return s end

  if b.tanks and #b.tanks > 0 then
    local s = section("Tanks", TANK_TEX)
    for i, t in ipairs(b.tanks) do
      local tag = i == 1 and "Main tank" or i == 2 and "Off tank" or ("Tank " .. i)
      s.rows[#s.rows + 1] = { left = DIM .. tag .. "|r   " .. nameText(t.n), right = (t.job ~= "" and safe(t.job) or DIM .. "-|r"), me = isMe(t.n) }
      if isMe(t.n) then mine[#mine + 1] = tag .. ((t.job ~= "" and (": " .. safe(t.job))) or "") end
    end
  end
  if b.heals and #b.heals > 0 then
    local s = section("Healers", HEAL_TEX)
    for _, h in ipairs(b.heals) do
      local target = (h.t and h.t ~= "") and nameText(h.t) or "|cffc8b48aRaid healing|r"
      s.rows[#s.rows + 1] = { left = nameText(h.n), right = target .. (h.c and "  |cffffd36a(this fight)|r" or ""), me = isMe(h.n) or (h.t ~= "" and isMe(h.t)) }
      if isMe(h.n) then mine[#mine + 1] = "Heal " .. target end
      if h.t and h.t ~= "" and isMe(h.t) then mine[#mine + 1] = "Healed by " .. nameText(h.n) end
    end
  end
  for _, set in ipairs({ { b.marks, "Target markers", "Kill / handle", "Target markers" }, { b.floor, "Floor markers  |cff8f7f62where to stand|r", "Stand at", "Floor markers" } }) do
    if set[1] and #set[1] > 0 then
      local s = section(set[2], set[4] == "Floor markers" and (MARK_TEX .. "6") or (MARK_TEX .. "8"), set[4])
      for _, m in ipairs(set[1]) do
        s.rows[#s.rows + 1] = { mark = m.m, left = (m.note ~= "" and ("|cffecc867" .. safe(m.note) .. "|r") or DIM .. safe(m.label) .. "|r"), right = names(m.who), me = anyMe(m.who) }
        if anyMe(m.who) then mine[#mine + 1] = (m.note ~= "" and safe(m.note) or set[3]) .. " " .. icon(m.m, 14) .. " " .. safe(m.label) end   -- the note replaces "Kill / handle" / "Stand at"
      end
    end
  end
  if b.jobs and #b.jobs > 0 then
    local s = section("Interrupts, CC & jobs", JOB_TEX, "Jobs")
    for _, j in ipairs(b.jobs) do
      s.rows[#s.rows + 1] = { left = nameText(j.n), right = safe(j.what), me = isMe(j.n) }
      if isMe(j.n) then mine[#mine + 1] = safe(j.what) end
    end
  end
  return S, mine
end

-- ---------- window ----------
local UI = {}
local current, currentRaid, pushedFrom

local MEDIA = "Interface\\AddOns\\HatedCompanion\\Media\\"
local BANNER_H = 118
local BG = { 0.043, 0.031, 0.022 }
local EDGE = { 0.55, 0.43, 0.22 }

local function flat(f, r, g, b, a, er, eg, eb, ea)
  f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  f:SetBackdropColor(r or 0.06, g or 0.045, b or 0.03, a or 0.92)
  f:SetBackdropBorderColor(er or EDGE[1], eg or EDGE[2], eb or EDGE[3], ea or 0.55)
end
local function vfade(tex, r, g, b, a1, a2)   -- vertical fade (top a1 -> bottom a2), safe on old and new APIs
  tex:SetColorTexture(1, 1, 1, 1)
  if CreateColor and pcall(tex.SetGradient, tex, "VERTICAL", CreateColor(r, g, b, a2), CreateColor(r, g, b, a1)) then return end
  if tex.SetGradientAlpha then tex:SetGradientAlpha("VERTICAL", r, g, b, a2, r, g, b, a1) else tex:SetColorTexture(r, g, b, (a1 + a2) / 2) end
end
local function hfade(tex, r, g, b, a1, a2)   -- horizontal fade (left a1 -> right a2)
  tex:SetColorTexture(1, 1, 1, 1)
  if CreateColor and pcall(tex.SetGradient, tex, "HORIZONTAL", CreateColor(r, g, b, a1), CreateColor(r, g, b, a2)) then return end
  if tex.SetGradientAlpha then tex:SetGradientAlpha("HORIZONTAL", r, g, b, a1, r, g, b, a2) else tex:SetColorTexture(r, g, b, (a1 + a2) / 2) end
end
local function caption(p, text)       -- small gold caps title for a panel
  local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetPoint("TOPLEFT", 12, -9); fs:SetText(text); fs:SetTextColor(0.85, 0.7, 0.4)
  local line = p:CreateTexture(nil, "ARTWORK")
  line:SetPoint("TOPLEFT", 1, -26); line:SetPoint("TOPRIGHT", -1, -26); line:SetHeight(1)
  hfade(line, EDGE[1], EDGE[2], EDGE[3], 0.7, 0.05)
  return fs
end
-- slim scrollbars: no arrow buttons, a thin gold thumb, mouse wheel scrolling
local function slim(sf)
  local bar = sf.ScrollBar or _G[(sf:GetName() or "") .. "ScrollBar"]
  if not bar then return end
  for _, k in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
    local b = bar[k] or _G[(bar:GetName() or "") .. k]
    if b then b:Hide(); b:SetAlpha(0); b:EnableMouse(false) end
  end
  bar:ClearAllPoints(); bar:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 12, 0); bar:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 12, 0)
  bar:SetWidth(4)
  local thumb = bar:GetThumbTexture()
  if thumb then thumb:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 0.8); thumb:SetSize(4, 40) end
  for _, r in ipairs({ bar:GetRegions() }) do if r ~= thumb and r.SetAlpha and r:GetObjectType() == "Texture" then r:SetAlpha(0) end end
  sf:EnableMouseWheel(true)
end
-- flat leather buttons with a gold edge; primary = filled gold
local function button(parent, text, w, primary)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w, 24)
  if primary then flat(b, 0.42, 0.28, 0.08, 0.95, 0.95, 0.75, 0.35, 0.9) else flat(b, 0.09, 0.065, 0.04, 0.95, EDGE[1], EDGE[2], EDGE[3], 0.8) end
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); b.text:SetPoint("CENTER"); b.text:SetText(text)
  b.text:SetTextColor(primary and 1 or 0.93, primary and 0.88 or 0.8, primary and 0.6 or 0.5)
  local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetPoint("TOPLEFT", 1, -1); hl:SetPoint("BOTTOMRIGHT", -1, 1); hl:SetColorTexture(1, 0.85, 0.5, 0.12)
  b:SetScript("OnDisable", function(self) self:SetAlpha(0.45) end)
  b:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
  b:SetScript("OnMouseDown", function(self) if self:IsEnabled() then self.text:SetPoint("CENTER", 1, -1) end end)
  b:SetScript("OnMouseUp", function(self) self.text:SetPoint("CENTER") end)
  return b
end

local function canPush()
  if IsInRaid() then return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") end
  return IsInGroup() and UnitIsGroupLeader("player")
end

local Show   -- forward
local findBoss -- forward

local function build()
  if UI.frame then return end
  local f = CreateFrame("Frame", "HatedPlanFrame", UIParent, "BackdropTemplate")
  f:SetSize(1180, 720); f:SetPoint("CENTER"); f:SetFrameStrata("HIGH"); f:SetToplevel(true)
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  f:SetResizable(true)
  if f.SetResizeBounds then f:SetResizeBounds(940, 560, 1900, 1200) elseif f.SetMinResize then f:SetMinResize(940, 560); f:SetMaxResize(1900, 1200) end
  local saved = HatedCompanionDB and HatedCompanionDB.planSize
  if saved and saved.w then f:SetSize(math.max(940, saved.w), math.max(560, saved.h)) end
  flat(f, BG[1], BG[2], BG[3], 0.97, 0.75, 0.6, 0.3, 0.9)
  tinsert(UISpecialFrames, "HatedPlanFrame")   -- Esc closes it
  UI.frame = f

  -- banner: the website art, cropped to fit, fading into the window
  local banner = f:CreateTexture(nil, "ARTWORK")
  banner:SetPoint("TOPLEFT", 1, -1); banner:SetPoint("TOPRIGHT", -1, -1); banner:SetHeight(BANNER_H)
  banner:SetTexture(MEDIA .. "Banner")
  local fade = f:CreateTexture(nil, "ARTWORK", nil, 2)
  fade:SetPoint("BOTTOMLEFT", banner); fade:SetPoint("BOTTOMRIGHT", banner); fade:SetHeight(60)
  vfade(fade, BG[1], BG[2], BG[3], 0, 1)
  local lfade = f:CreateTexture(nil, "ARTWORK", nil, 1)      -- darken the left side behind the crest and title
  lfade:SetPoint("TOPLEFT", banner); lfade:SetPoint("BOTTOMLEFT", banner); lfade:SetWidth(420)
  hfade(lfade, 0, 0, 0, 0.75, 0)
  local rule = f:CreateTexture(nil, "ARTWORK", nil, 3)
  rule:SetPoint("TOPLEFT", banner, "BOTTOMLEFT", 0, 0); rule:SetPoint("TOPRIGHT", banner, "BOTTOMRIGHT", 0, 0); rule:SetHeight(1)
  rule:SetColorTexture(0.8, 0.63, 0.3, 0.55)

  local crest = f:CreateTexture(nil, "OVERLAY")
  crest:SetSize(112, 112); crest:SetPoint("LEFT", banner, "LEFT", 10, 0); crest:SetTexture(MEDIA .. "Icon")
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  f.title:SetPoint("BOTTOMLEFT", crest, "RIGHT", 6, 2)
  f.title:SetTextColor(1, 0.85, 0.48); f.title:SetShadowOffset(1, -1); f.title:SetShadowColor(0, 0, 0, 1)
  f.title:SetText("Boss Plan")
  f.raid = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.raid:SetPoint("TOPLEFT", crest, "RIGHT", 8, -4); f.raid:SetTextColor(0.85, 0.78, 0.65)
  f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.sub:SetPoint("BOTTOMLEFT", 14, 11)
  f.ver = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.ver:SetPoint("BOTTOMRIGHT", -24, 11)
  local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  f.ver:SetText("Hated Companion v" .. ((meta and meta("HatedCompanion", "Version")) or "?"))

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2); close:SetFrameLevel(f:GetFrameLevel() + 11)

  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16); grip:SetPoint("BOTTOMRIGHT", -3, 3); grip:SetFrameLevel(f:GetFrameLevel() + 12)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    HatedCompanionDB = HatedCompanionDB or {}
    HatedCompanionDB.planSize = { w = math.floor(f:GetWidth()), h = math.floor(f:GetHeight()) }
    if current then Show(current, currentRaid) end
  end)

  local TOP = -(BANNER_H + 10)

  -- left: bosses
  local left = CreateFrame("Frame", nil, f, "BackdropTemplate")
  left:SetPoint("TOPLEFT", 12, TOP); left:SetPoint("BOTTOMLEFT", 12, 32); left:SetWidth(200)
  flat(left); caption(left, "BOSSES")
  local ls = CreateFrame("ScrollFrame", "HatedPlanList", left, "UIPanelScrollFrameTemplate")
  ls:SetPoint("TOPLEFT", 4, -32); ls:SetPoint("BOTTOMRIGHT", -14, 6); slim(ls)
  local lc = CreateFrame("Frame", nil, ls); lc:SetSize(180, 10); ls:SetScrollChild(lc)
  UI.list, UI.buttons, UI.heads = lc, {}, {}

  -- the boss: one panel, one scrolling page
  local mid = CreateFrame("Frame", nil, f, "BackdropTemplate")
  mid:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0); mid:SetPoint("BOTTOMRIGHT", -12, 32)
  flat(mid)
  UI.mid = mid
  mid.name = mid:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  mid.name:SetPoint("TOPLEFT", 14, -10); mid.name:SetJustifyH("LEFT")
  mid.name:SetTextColor(1, 0.85, 0.48)
  local mline = mid:CreateTexture(nil, "ARTWORK")
  mline:SetPoint("TOPLEFT", 1, -34); mline:SetPoint("TOPRIGHT", -1, -34); mline:SetHeight(1)
  hfade(mline, EDGE[1], EDGE[2], EDGE[3], 0.7, 0.05)

  local push = button(mid, "Open for raid", 130)
  push:SetPoint("TOPRIGHT", -10, -6)
  push:SetScript("OnClick", function() UI.Push() end)
  push:SetMotionScriptsWhileDisabled(true)
  push:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:AddLine("Open for raid", 1, 0.82, 0.3)
    GameTooltip:AddLine(canPush() and "Opens this boss on every raider's screen (raiders with the addon)." or "Be in a raid as leader or assistant to use this.", 1, 1, 1, true); GameTooltip:Show() end)
  push:SetScript("OnLeave", GameTooltip_Hide)
  UI.pushBtn = push
  local sendAll = button(mid, "Send plan to guild", 150, true)
  sendAll:SetPoint("RIGHT", push, "LEFT", -8, 0)
  sendAll:SetScript("OnClick", function() UI.SendPlan() end)
  sendAll:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:AddLine("Send plan to guild", 1, 0.82, 0.3)
    GameTooltip:AddLine("Sends every boss's plan to everyone online in the guild with the addon (and your raid).", 1, 1, 1, true); GameTooltip:Show() end)
  sendAll:SetScript("OnLeave", GameTooltip_Hide)
  UI.sendBtn = sendAll
  local bossBtn = button(mid, "Send boss", 90)
  bossBtn:SetPoint("RIGHT", sendAll, "LEFT", -8, 0)
  bossBtn:SetScript("OnClick", function() UI.SendBoss() end)
  bossBtn:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:AddLine("Send this boss", 1, 0.82, 0.3)
    GameTooltip:AddLine("Sends just this boss's plan to the guild (and your raid's PUGs). Quick: use it for changes between pulls.", 1, 1, 1, true); GameTooltip:Show() end)
  bossBtn:SetScript("OnLeave", GameTooltip_Hide)
  UI.bossBtn = bossBtn
  local editBtn = button(mid, "Edit", 64)
  editBtn:SetPoint("RIGHT", bossBtn, "LEFT", -8, 0)
  editBtn:SetScript("OnClick", function() UI.ToggleEdit() end)
  editBtn:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:AddLine("Edit this boss", 1, 0.82, 0.3)
    GameTooltip:AddLine("Click any row to change it. Changes save straight away; send them with Send boss or Send plan to guild.", 1, 1, 1, true); GameTooltip:Show() end)
  editBtn:SetScript("OnLeave", GameTooltip_Hide)
  UI.editBtn = editBtn

  local ms = CreateFrame("ScrollFrame", "HatedPlanBody", mid, "UIPanelScrollFrameTemplate")
  ms:SetPoint("TOPLEFT", 12, -44); ms:SetPoint("BOTTOMRIGHT", -18, 10); slim(ms)
  if ms.SetClipsChildren then ms:SetClipsChildren(true) end
  UI.scroll = ms
  local mc = CreateFrame("Frame", nil, ms); mc:SetSize(600, 10); ms:SetScrollChild(mc)
  UI.body, UI.rows, UI.hdrs, UI.cards = mc, {}, {}, {}

  -- your jobs: a gold card with a soft breathing glow
  local mine = CreateFrame("Frame", nil, mc, "BackdropTemplate")
  flat(mine, 0.16, 0.11, 0.03, 0.95, 1, 0.8, 0.32, 0.85)
  mine.bar = mine:CreateTexture(nil, "ARTWORK"); mine.bar:SetPoint("TOPLEFT", 1, -1); mine.bar:SetPoint("BOTTOMLEFT", 1, 1); mine.bar:SetWidth(3)
  mine.bar:SetColorTexture(1, 0.82, 0.35, 1)
  mine.glow = mine:CreateTexture(nil, "BACKGROUND", nil, -1)
  mine.glow:SetPoint("TOPLEFT", 1, -1); mine.glow:SetPoint("BOTTOMRIGHT", -1, 1); hfade(mine.glow, 1, 0.78, 0.25, 0.22, 0.03)
  mine.head = mine:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  mine.head:SetPoint("TOPLEFT", 14, -9); mine.head:SetText("YOUR JOBS"); mine.head:SetTextColor(0.45, 1, 0.6)
  mine.text = mine:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  mine.text:SetPoint("TOPLEFT", 14, -26); mine.text:SetPoint("RIGHT", -12, 0); mine.text:SetJustifyH("LEFT"); mine.text:SetSpacing(4)
  UI.mine = mine

  -- the screenshot, top right of the page
  local shot = CreateFrame("Button", nil, mc, "BackdropTemplate")
  flat(shot, 0, 0, 0, 1, EDGE[1], EDGE[2], EDGE[3], 0.6)
  shot.tex = shot:CreateTexture(nil, "ARTWORK"); shot.tex:SetPoint("TOPLEFT", 1, -1); shot.tex:SetPoint("BOTTOMRIGHT", -1, 1)
  shot.hint = shot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  shot.hint:SetPoint("BOTTOMRIGHT", -6, 5); shot.hint:SetText("Click to enlarge"); shot.hint:SetAlpha(0)
  local hb = shot:CreateTexture(nil, "OVERLAY"); hb:SetPoint("BOTTOMLEFT", 1, 1); hb:SetPoint("BOTTOMRIGHT", -1, 1); hb:SetHeight(22)
  vfade(hb, 0, 0, 0, 0, 0.7); hb:SetAlpha(0); shot.hb = hb
  shot:SetScript("OnEnter", function(self) self.hint:SetAlpha(1); self.hb:SetAlpha(1); self:SetBackdropBorderColor(1, 0.82, 0.4, 1) end)
  shot:SetScript("OnLeave", function(self) self.hint:SetAlpha(0); self.hb:SetAlpha(0); self:SetBackdropBorderColor(EDGE[1], EDGE[2], EDGE[3], 0.6) end)
  shot:SetScript("OnClick", function() if current and (current.image or current.pix) then UI.Zoom() end end)
  shot.none = shot:CreateFontString(nil, "OVERLAY", "GameFontDisable"); shot.none:SetPoint("CENTER"); shot.none:SetText("No screenshot for this fight")
  UI.shot = shot

  UI.layout = function()
    local w = f:GetWidth()
    -- crop the banner art to the window's shape, keeping the logo in view
    local A, ART = (w - 2) / BANNER_H, 1024 / 171
    if A >= ART then
      local vh = (171 / 256) * ART / A; local c = 0.47 * 171 / 256
      local v0 = math.max(0, math.min(171 / 256 - vh, c - vh / 2))
      banner:SetTexCoord(0, 1, v0, v0 + vh)
    else
      local uw = A / ART; banner:SetTexCoord(0.5 - uw / 2, 0.5 + uw / 2, 0, 171 / 256)
    end
    mc:SetWidth(math.max(500, w - 12 - 200 - 10 - 12 - 12 - 18 - 6))
  end
  f:SetScript("OnSizeChanged", function() UI.layout() end)

  -- big view of the screenshot
  local z = CreateFrame("Button", "HatedPlanZoom", UIParent, "BackdropTemplate")
  z:SetFrameStrata("DIALOG"); z:SetPoint("CENTER"); z:Hide()
  flat(z, 0, 0, 0, 0.97, 0.85, 0.68, 0.32, 1)
  z.tex = z:CreateTexture(nil, "ARTWORK"); z.tex:SetPoint("TOPLEFT", 4, -4); z.tex:SetPoint("BOTTOMRIGHT", -4, 4)
  z:SetScript("OnClick", z.Hide)
  tinsert(UISpecialFrames, "HatedPlanZoom")
  UI.zoom = z
end

-- the pixel copy of a screenshot (sent in game): a grid of coloured squares
local PIX = {}
do
  local abc = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  for i = 1, 64 do PIX[abc:byte(i)] = i - 1 end
end
local function fitPix(pix, maxW, maxH)
  local s = math.min(maxW / pix.w, maxH / pix.h)
  return math.floor(pix.w * s), math.floor(pix.h * s)
end
local function rgb12(v) return math.floor(v / 256) / 15, (math.floor(v / 16) % 16) / 15, (v % 16) / 15 end
local pixCache = setmetatable({}, { __mode = "k" })   -- decoded colours, kept out of saved variables
local function decodePix(pix)
  if pixCache[pix] then return pixCache[pix] end
  local cols, data = {}, pix.data or ""
  if pix.v == 2 then
    local pal, ps = {}, pix.pal or ""
    for i = 1, #ps - 1, 2 do pal[#pal + 1] = { rgb12((PIX[ps:byte(i)] or 0) * 64 + (PIX[ps:byte(i + 1)] or 0)) } end
    local i = 1
    while i <= #data do
      if data:byte(i) == 33 then   -- "!" run
        local len, c = (PIX[data:byte(i + 1)] or 0) + 1, pal[(PIX[data:byte(i + 2)] or 0) + 1]
        for _ = 1, len do cols[#cols + 1] = c end
        i = i + 3
      else
        cols[#cols + 1] = pal[(PIX[data:byte(i)] or 0) + 1]; i = i + 1
      end
    end
  else
    for i = 1, #data - 1, 2 do cols[#cols + 1] = { rgb12((PIX[data:byte(i)] or 0) * 64 + (PIX[data:byte(i + 1)] or 0)) } end
  end
  pixCache[pix] = cols
  return cols
end
local function drawPix(holder, pix, W, H)
  holder.pool = holder.pool or {}
  local pool, pw, ph = holder.pool, pix.w or 0, pix.h or 0
  local cols = decodePix(pix)
  if pw * ph > #cols then pw, ph = 0, 0 end
  local cw, ch = W / math.max(pw, 1), H / math.max(ph, 1)
  local n = 0
  for y = 0, ph - 1 do
    for x = 0, pw - 1 do
      n = n + 1
      local tx = pool[n]
      if not tx then tx = holder:CreateTexture(nil, "ARTWORK"); pool[n] = tx end
      local c = cols[n] or { 0, 0, 0 }
      tx:SetColorTexture(c[1] or 0, c[2] or 0, c[3] or 0, 1)
      tx:ClearAllPoints(); tx:SetPoint("TOPLEFT", holder, "TOPLEFT", 1 + x * cw, -1 - y * ch)
      tx:SetSize(cw + 0.6, ch + 0.6)   -- a hair of overlap hides seams
      tx:Show()
    end
  end
  for i = n + 1, #pool do pool[i]:Hide() end
end
local function hidePix(holder) for _, tx in ipairs(holder.pool or {}) do tx:Hide() end end

-- my screenshot file counts only when it's the picture the (sent) plan names; otherwise the plan's copy wins
local function fileFits(img, b)
  if not img then return false end
  if b.shot == nil then return true end                 -- plans from before screenshots were named
  return b.shot ~= "" and img.src ~= nil and img.src == b.shot
end

local function setImage(tex, img, maxW, maxH)
  local w, h = img.w or 1024, img.h or 512
  local s = math.min(maxW / w, maxH / h)
  tex:SetTexture(IMG_PATH .. img.file)
  tex:SetTexCoord(0, img.u or 1, 0, img.v or 1)
  return math.floor(w * s), math.floor(h * s)
end

function UI.Zoom()
  local z = UI.zoom
  local maxW, maxH = UIParent:GetWidth() * 0.9, UIParent:GetHeight() * 0.85
  if current.image then
    hidePix(z); z.tex:Show()
    local w, h = setImage(z.tex, current.image, maxW, maxH)
    z:SetSize(w + 8, h + 8)
  elseif current.pix then
    z.tex:Hide()
    local w, h = fitPix(current.pix, maxW * 0.6, maxH * 0.6)   -- low-res copy: don't blow it up too far
    z:SetSize(w + 2, h + 2); drawPix(z, current.pix, w, h)
  else return end
  z:Show()
end

local function refreshList()
  local lc, y = UI.list, 2
  for _, b in ipairs(UI.buttons) do b:Hide() end
  for _, h in ipairs(UI.heads) do h:Hide() end
  local bi, hi = 0, 0
  for _, raid in ipairs((HatedPlan and HatedPlan.raids) or {}) do
    hi = hi + 1
    local h = UI.heads[hi]
    if not h then h = lc:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); h:SetJustifyH("LEFT"); h:SetWidth(176); UI.heads[hi] = h end
    h:SetText((raid.name or ""):upper()); h:SetTextColor(0.6, 0.52, 0.38); h:ClearAllPoints(); h:SetPoint("TOPLEFT", 8, -y - 4); h:Show()
    y = y + 22
    for _, b in ipairs(raid.bosses or {}) do
      bi = bi + 1
      local btn = UI.buttons[bi]
      if not btn then
        btn = CreateFrame("Button", nil, lc)
        btn:SetSize(178, 24)
        btn.hl = btn:CreateTexture(nil, "BACKGROUND"); btn.hl:SetAllPoints(); hfade(btn.hl, 1, 0.78, 0.3, 0.2, 0.02)
        btn.bar = btn:CreateTexture(nil, "ARTWORK"); btn.bar:SetPoint("TOPLEFT"); btn.bar:SetPoint("BOTTOMLEFT"); btn.bar:SetWidth(2)
        btn.bar:SetColorTexture(1, 0.82, 0.35, 1)
        local hov = btn:CreateTexture(nil, "HIGHLIGHT"); hov:SetAllPoints(); hov:SetColorTexture(1, 0.9, 0.6, 0.06)
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        btn.text:SetPoint("LEFT", 12, 0); btn.text:SetPoint("RIGHT", -4, 0); btn.text:SetJustifyH("LEFT")
        btn:SetScript("OnClick", function(self) pushedFrom = nil; Show(self.boss, self.raid) end)
        UI.buttons[bi] = btn
      end
      btn.boss, btn.raid = b, raid.name
      btn.text:SetText(b.name)
      local sel = current and current.id == b.id
      btn.hl:SetShown(sel); btn.bar:SetShown(sel)
      if sel then btn.text:SetTextColor(1, 0.86, 0.5) else btn.text:SetTextColor(0.82, 0.78, 0.7) end
      btn:ClearAllPoints(); btn:SetPoint("TOPLEFT", 0, -y); btn:Show()
      y = y + 25
    end
    y = y + 10
  end
  if bi == 0 then
    hi = hi + 1
    local h = UI.heads[hi] or lc:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); UI.heads[hi] = h
    h:SetWidth(170); h:SetJustifyH("LEFT"); h:ClearAllPoints(); h:SetPoint("TOPLEFT", 8, -4)
    h:SetText("No plan yet. The raid leader can send one in game, or download the addon again from hatedforever.com."); h:Show()
    y = 60
  end
  lc:SetHeight(y)
end

-- ---------- the page: building blocks ----------
local function header(i)
  local h = UI.hdrs[i]
  if h then return h end
  h = CreateFrame("Frame", nil, UI.body)
  h:SetHeight(24)
  h.bg = h:CreateTexture(nil, "BACKGROUND"); h.bg:SetAllPoints(); hfade(h.bg, 0.55, 0.42, 0.2, 0.28, 0.02)
  h.bar = h:CreateTexture(nil, "ARTWORK"); h.bar:SetPoint("TOPLEFT"); h.bar:SetPoint("BOTTOMLEFT"); h.bar:SetWidth(2); h.bar:SetColorTexture(0.95, 0.75, 0.35, 1)
  h.icon = h:CreateTexture(nil, "ARTWORK"); h.icon:SetSize(18, 18); h.icon:SetPoint("LEFT", 8, 0)
  h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormal"); h.text:SetPoint("LEFT", h.icon, "RIGHT", 7, 0)
  h.text:SetTextColor(1, 0.84, 0.48)
  UI.hdrs[i] = h
  return h
end
local function row(i)
  local r = UI.rows[i]
  if r then return r end
  r = CreateFrame("Frame", nil, UI.body)
  r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
  r.glow = r:CreateTexture(nil, "BACKGROUND", nil, 1); r.glow:SetAllPoints(); hfade(r.glow, 1, 0.8, 0.3, 0.32, 0.04)
  r.edge = r:CreateTexture(nil, "ARTWORK"); r.edge:SetPoint("TOPLEFT"); r.edge:SetPoint("BOTTOMLEFT"); r.edge:SetWidth(2); r.edge:SetColorTexture(0.4, 1, 0.55, 1)
  r.mark = r:CreateTexture(nil, "ARTWORK"); r.mark:SetSize(18, 18)
  r.left = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); r.left:SetJustifyH("LEFT"); r.left:SetWordWrap(true)
  r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); r.right:SetJustifyH("LEFT"); r.right:SetWordWrap(true)
  r.hov = r:CreateTexture(nil, "BACKGROUND", nil, 2); r.hov:SetAllPoints(); r.hov:SetColorTexture(0.4, 1, 0.55, 0.08); r.hov:Hide()
  r:SetScript("OnEnter", function(self) if self.onClick then self.hov:Show() end end)
  r:SetScript("OnLeave", function(self) self.hov:Hide() end)
  r:SetScript("OnMouseUp", function(self, btn) if self.onClick and btn == "LeftButton" then self.onClick() end end)
  UI.rows[i] = r
  return r
end
local glowRows, HI, RI = {}, 0, 0
local editSections   -- set by the edit module below
-- a section (header + rows) at x, y with width w; returns its height. A row with only `left` spans the width;
-- `big` makes the left text large (kill order icons).
local function drawSection(s, x, y, w)
  HI = HI + 1
  local h = header(HI)
  h:ClearAllPoints(); h:SetPoint("TOPLEFT", x, -y); h:SetWidth(w)
  h.icon:SetTexture(s.tex)
  if s.tex:find("RaidTargeting") then h.icon:SetTexCoord(0, 1, 0, 1) else h.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
  h.text:SetText(s.title:upper()); h:Show()
  local yy = y + 28
  local LW = s.split and math.floor(w * s.split) or math.floor(w * 0.45)
  for k, d in ipairs(s.rows) do
    RI = RI + 1
    local r = row(RI)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", x, -yy); r:SetWidth(w)
    local lx = 10
    if d.mark then r.mark:SetTexture(MARK_TEX .. d.mark); r.mark:ClearAllPoints(); r.mark:SetPoint("TOPLEFT", 8, -4); r.mark:Show(); lx = 32 else r.mark:Hide() end
    r.left:SetFontObject(d.big and "GameFontHighlightLarge" or "GameFontHighlight")
    r.left:ClearAllPoints(); r.left:SetPoint("TOPLEFT", lx, -6)
    if d.right then
      r.left:SetWidth(LW - lx); r.right:ClearAllPoints(); r.right:SetPoint("TOPLEFT", LW + 6, -6); r.right:SetWidth(w - LW - 14)
      r.right:SetText(d.right); r.right:Show()
    else
      r.left:SetWidth(w - lx - 10); r.right:Hide()
    end
    r.left:SetText(d.left or "")
    local rh = math.max(26, math.max(r.left:GetStringHeight(), d.right and r.right:GetStringHeight() or 0) + 12)
    r:SetHeight(rh)
    r.bg:SetColorTexture(1, 1, 1, (k % 2 == 0) and 0.025 or 0)
    r.glow:SetShown(d.me and true or false); r.edge:SetShown(d.me and true or false)
    if d.me then glowRows[#glowRows + 1] = r end
    r.onClick = d.onClick; r:EnableMouse(d.onClick ~= nil); r.hov:Hide()
    r:Show()
    yy = yy + rh
  end
  return yy - y
end

local function renderPage(b)
  for _, h in ipairs(UI.hdrs) do h:Hide() end
  for _, r in ipairs(UI.rows) do r:Hide() end
  wipe(glowRows); HI, RI = 0, 0
  local W = UI.body:GetWidth()
  local GAP = 14

  if not b then
    UI.mine:Hide(); UI.shot:Hide()
    local s = { title = "Boss plan", tex = MARK_TEX .. "8", rows = { { left = DIM .. "Pick a boss on the left.|r" } } }
    UI.body:SetHeight(drawSection(s, 0, 0, W) + 10)
    return
  end
  local sections, mine = bossSections(b)
  local editKill, editNotes
  if UI.editing and editSections then sections, editKill, editNotes = editSections(b) end
  local byTitle = {}
  for _, s in ipairs(sections) do byTitle[s.key or s.title] = s end

  -- top: your jobs, tanks, healers (left) | screenshot (right)
  local LW = math.floor((W - GAP) * 0.46)
  local RW = W - LW - GAP
  local yl = 0
  if #mine > 0 then
    UI.mine:ClearAllPoints(); UI.mine:SetPoint("TOPLEFT", 0, 0); UI.mine:SetWidth(LW)
    UI.mine.text:SetText(table.concat(mine, "\n"))
    UI.mine:SetHeight(UI.mine.text:GetStringHeight() + 36); UI.mine:Show()
    yl = UI.mine:GetHeight() + GAP
  else UI.mine:Hide() end
  for _, key in ipairs({ "Tanks", "Healers" }) do
    if byTitle[key] then yl = yl + drawSection(byTitle[key], 0, yl, LW) + GAP end
  end

  local yr = 0
  local shot = UI.shot
  shot:ClearAllPoints(); shot:SetPoint("TOPLEFT", LW + GAP, 0)
  local maxH = math.max(220, UI.scroll:GetHeight() * 0.62)
  if b.image and b.image.file then
    hidePix(shot)
    local w, h = setImage(shot.tex, b.image, RW, maxH)
    shot:SetSize(w + 2, h + 2); shot.tex:Show(); shot.none:Hide(); shot:EnableMouse(true)
    yr = h + 2 + GAP
  elseif b.pix and b.pix.data then
    -- no screenshot file for this one yet: the low-res copy that came with the plan
    shot.tex:Hide(); shot.none:Hide()
    local w, h = fitPix(b.pix, RW, maxH)
    shot:SetSize(w + 2, h + 2); drawPix(shot, b.pix, w, h); shot:EnableMouse(true)
    yr = h + 2 + GAP
  else
    hidePix(shot)
    shot.none:SetText((b.shot and b.shot ~= "") and "New screenshot - ask the raid leader to send the plan again,\nor download the addon from hatedforever.com" or "No screenshot for this fight")
    shot:SetSize(RW, 120); shot.tex:Hide(); shot.none:Show(); shot:EnableMouse(false)
    yr = 120 + GAP
  end
  shot:Show()

  -- below: everything else as cards in columns (each card goes to the shortest column)
  local cards = {}
  if editKill then cards[#cards + 1] = editKill
  elseif (b.kill and #b.kill > 0) or (b.killNote and b.killNote ~= "") then
    local rows = {}
    if b.kill and #b.kill > 0 then
      local seq = {}
      for _, i in ipairs(b.kill) do seq[#seq + 1] = icon(i, 24) end
      rows[#rows + 1] = { left = table.concat(seq, "  |cffb8862e>|r  "), big = true }
    end
    if b.killNote and b.killNote ~= "" then rows[#rows + 1] = { left = safe(b.killNote) } end
    cards[#cards + 1] = { title = "Kill order", tex = MARK_TEX .. "8", rows = rows }
  end
  for _, key in ipairs({ "Target markers", "Floor markers", "Jobs" }) do if byTitle[key] then cards[#cards + 1] = byTitle[key] end end
  if editNotes then cards[#cards + 1] = editNotes
  elseif b.notes and b.notes ~= "" then cards[#cards + 1] = { title = "Notes", tex = "Interface\\Icons\\INV_Misc_Note_01", rows = { { left = safe(b.notes) } } } end

  local top = math.max(yl, yr)
  if #cards > 0 then
    local sep = UI.sep or UI.body:CreateTexture(nil, "ARTWORK"); UI.sep = sep
    sep:ClearAllPoints(); sep:SetPoint("TOPLEFT", 0, -(top - GAP / 2)); sep:SetSize(W, 1); hfade(sep, EDGE[1], EDGE[2], EDGE[3], 0.6, 0.05); sep:Show()
    top = top + 4
  elseif UI.sep then UI.sep:Hide() end
  local ncol = W >= 900 and 3 or 2
  local CW = math.floor((W - GAP * (ncol - 1)) / ncol)
  local colY = {}
  for c = 1, ncol do colY[c] = top end
  for _, card in ipairs(cards) do
    local c = 1
    for k = 2, ncol do if colY[k] < colY[c] then c = k end end
    colY[c] = colY[c] + drawSection(card, (c - 1) * (CW + GAP), colY[c], CW) + GAP
  end
  local bottom = top
  for c = 1, ncol do bottom = math.max(bottom, colY[c]) end
  UI.body:SetHeight(bottom + 6)
end

Show = function(b, raidName, keepScroll)
  local scrollY = keepScroll and UI.scroll and UI.scroll:GetVerticalScroll() or 0
  build()
  UI.layout()
  current, currentRaid = b, raidName
  local f = UI.frame
  f.raid:SetText(raidName or "")
  f.sub:SetText((pushedFrom and ("|cffecc867Shown by " .. safe(pushedFrom) .. "|r   ") or "") ..
    ((HatedPlan and HatedPlan.updated) and ("Plan saved " .. HatedPlan.updated .. (HatedPlan.by and (" by " .. HatedPlan.by) or "")) or ""))
  refreshList()
  UI.pushBtn:SetShown(b ~= nil and (canPush() or iAmLeader()))
  UI.pushBtn:SetEnabled(canPush())
  UI.sendBtn:SetShown(iAmLeader() and HatedPlan ~= nil and HatedPlan.raids ~= nil and #HatedPlan.raids > 0)
  UI.mid.name:SetText(b and b.name or "")
  f:Show()
  local lead = iAmLeader() and b ~= nil and findBoss(b.id) ~= nil
  if not lead then UI.editing = false end
  UI.editBtn:SetShown(lead); UI.bossBtn:SetShown(lead)
  UI.editBtn.text:SetText(UI.editing and "Done" or "Edit")
  UI.mid.name:SetText((b and b.name or "") .. (UI.editing and "  |cff4dff88editing|r" or ""))
  renderPage(b)
  UI.scroll:SetVerticalScroll(math.min(scrollY, UI.scroll:GetVerticalScrollRange() or 0))
end

-- your rows and the jobs card breathe softly while the window is open
do
  local t0 = GetTime()
  C_Timer.NewTicker(0.05, function()
    if not UI.frame or not UI.frame:IsShown() then return end
    local k = 0.5 + 0.5 * math.sin((GetTime() - t0) * math.pi * 2 / 2.4)
    for _, r in ipairs(glowRows) do r.glow:SetAlpha(0.45 + 0.55 * k) end
    if UI.mine:IsShown() then UI.mine.glow:SetAlpha(0.4 + 0.6 * k) end
  end)
end

findBoss = function(id)
  for _, raid in ipairs((HatedPlan and HatedPlan.raids) or {}) do
    for _, b in ipairs(raid.bosses or {}) do if b.id == id then return b, raid.name end end
  end
end

-- ---------- sending a boss to the raid ----------
-- tiny serializer (no loadstring on anything that arrives over the network)
local function ser(v, out)
  local t = type(v)
  if t == "string" then out[#out + 1] = "s" .. #v .. ":" .. v
  elseif t == "number" then out[#out + 1] = "n" .. v .. ";"
  elseif t == "boolean" then out[#out + 1] = v and "T" or "F"
  elseif t == "table" then
    out[#out + 1] = "{"
    for k, x in pairs(v) do ser(k, out); ser(x, out) end
    out[#out + 1] = "}"
  end
  return out
end
local function de(s, i, depth)
  depth = depth or 0
  if depth > 20 then error("too deep") end
  local c = s:sub(i, i)
  if c == "s" then
    local colon = s:find(":", i, true); local len = tonumber(s:sub(i + 1, colon - 1))
    return s:sub(colon + 1, colon + len), colon + len + 1
  elseif c == "n" then
    local semi = s:find(";", i, true); return tonumber(s:sub(i + 1, semi - 1)), semi + 1
  elseif c == "T" then return true, i + 1
  elseif c == "F" then return false, i + 1
  elseif c == "{" then
    local t = {}; i = i + 1
    while s:sub(i, i) ~= "}" do
      if i > #s then error("cut short") end
      local k; k, i = de(s, i, depth + 1)
      local v; v, i = de(s, i, depth + 1)
      t[k] = v
    end
    return t, i + 1
  end
  error("bad data")
end

local queue, sending, progress = {}, false, nil
local sentCount, totalCount, lastPct = 0, 0, 0
local function pump()
  if #queue == 0 then
    sending = false
    if progress then say(progress .. " sent."); progress = nil end
    sentCount, totalCount, lastPct = 0, 0, 0
    return
  end
  sending = true
  local m = queue[1]
  local r = C_ChatInfo.SendAddonMessage(PREFIX, m[1], m[2])
  -- newer clients return a result code and throttle bursts: wait and retry the same piece
  local ok = (r == nil or r == true or r == 0 or (Enum and Enum.SendAddonMessageResult and r == Enum.SendAddonMessageResult.Success))
  if ok then
    table.remove(queue, 1); sentCount = sentCount + 1
    local pct = totalCount > 0 and math.floor(sentCount / totalCount * 4) * 25 or 0
    if progress and pct > lastPct and pct < 100 then lastPct = pct; say(progress .. " " .. pct .. "% sent...") end
  end
  C_Timer.After(ok and 0.12 or 1, pump)
end
local function send(kind, payload, channels)
  channels = channels or { IsInRaid() and "RAID" or "PARTY" }
  local data = table.concat(ser(payload, {}))
  local id, CH = tostring(math.random(100000, 999999)), 232
  local n = math.ceil(#data / CH)
  for _, channel in ipairs(channels) do
    for i = 1, n do queue[#queue + 1] = { kind .. id .. "|" .. i .. "|" .. n .. "|" .. data:sub((i - 1) * CH + 1, i * CH), channel } end
  end
  totalCount = totalCount + n * #channels
  if not sending then pump() end
  return channels[1] == "RAID" and "raid" or channels[1] == "GUILD" and "guild" or "party", n * #channels
end

function UI.Push()
  if not current then return end
  if not canPush() then say("only the raid leader or an assistant can show a plan to the raid."); return end
  local who = send("B", { boss = current, raid = currentRaid, classes = HatedPlan and HatedPlan.classes })
  say("showing " .. current.name .. " to the " .. who .. ".")
end

-- the whole plan (every raid and boss, text only: screenshots stay each player's own files)
function UI.SendPlan()
  if not HatedPlan or not HatedPlan.raids or #HatedPlan.raids == 0 then say("no plan to send: update the addon on hatedforever.com first."); return end
  if not iAmLeader() then say("only the Raid Leader can send the plan."); return end
  if not IsInGuild() then say("you're not in a guild."); return end
  local copy = { updated = HatedPlan.updated, by = HatedPlan.by, leader = HatedPlan.leader, classes = HatedPlan.classes, raids = {} }
  for _, raid in ipairs(HatedPlan.raids) do
    local r = { name = raid.name, bosses = {} }
    for _, b in ipairs(raid.bosses or {}) do
      local c = {}; for k, v in pairs(b) do if k ~= "image" then c[k] = v end end
      if c.pix then local px = {}; for k, v in pairs(c.pix) do if k ~= "cols" then px[k] = v end end; c.pix = px end
      r.bosses[#r.bosses + 1] = c
    end
    copy.raids[#copy.raids + 1] = r
  end
  local channels = { "GUILD" }
  if IsInRaid() then                                -- PUGs in the raid get it too (only sent twice when there are any)
    for i = 1, GetNumGroupMembers() do
      local u = "raid" .. i
      if UnitExists(u) and not UnitIsInMyGuild(u) then channels[2] = "RAID"; break end
    end
  end
  local _, n = send("P", copy, channels)
  progress = "Plan (saved " .. (HatedPlan.updated or "?") .. ")"
  say(string.format("sending the plan to everyone online in the guild%s with the addon (%d pieces; WoW limits addon messages, so this can take a minute or two).", channels[2] and " and your raid's PUGs" or "", n))
end

-- use a plan received in game when it's newer than the one the website saved, keeping my own screenshots
local filePlan
local function adopt(plan)
  local imgs = {}
  for _, raid in ipairs((filePlan and filePlan.raids) or {}) do
    for _, b in ipairs(raid.bosses or {}) do if b.image then imgs[b.id] = b.image end end
  end
  for _, raid in ipairs(plan.raids or {}) do
    for _, b in ipairs(raid.bosses or {}) do
      local img = imgs[b.id]
      b.image = fileFits(img, b) and img or nil       -- an older (or unknown) picture gives way to the sent one
    end
  end
  HatedPlan = plan
  if current then current = findBoss(current.id) or current end
end

local incoming, done = {}, {}
local ev = CreateFrame("Frame")
ev:RegisterEvent("CHAT_MSG_ADDON"); ev:RegisterEvent("PLAYER_LOGIN"); ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:SetScript("OnEvent", function(_, event, prefix, msg, channel, sender)
  if event == "GROUP_ROSTER_UPDATE" then
    if UI.pushBtn and current then UI.pushBtn:SetShown(canPush() or iAmLeader()); UI.pushBtn:SetEnabled(canPush()) end
    return
  end
  if event == "PLAYER_LOGIN" then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    filePlan = HatedPlan
    local synced = HatedCompanionDB and HatedCompanionDB.syncedPlan
    -- use the plan the raid leader sent, unless the plan file has been replaced since it arrived
    local fileStamp = (HatedPlan and HatedPlan.updated) or ""
    if type(synced) == "table" and (HatedCompanionDB.syncedOver == fileStamp or (synced.updated or "") > fileStamp) then adopt(synced) end
    return
  end
  if prefix ~= PREFIX or (channel ~= "RAID" and channel ~= "PARTY" and channel ~= "GUILD") then return end
  local short = Ambiguate(sender or "", "short")
  local ok, why = false, nil
  if channel == "GUILD" then
    -- guild plans only from the Raid Leader (the website names them in the plan); without a plan yet, from the guild master
    local k1 = msg:sub(1, 1)
    if k1 ~= "P" and k1 ~= "U" then return end
    local l = leaderName()
    if l and l ~= "" then ok = matches(l, wordsOf(short)); why = "only the Raid Leader (" .. l .. ") can send plans"
    else
      why = "without a plan yet, only the guild master's plans are taken"
      for gi = 1, GetNumGuildMembers() do
        local gname, _, rankIndex = GetGuildRosterInfo(gi)
        if gname and Ambiguate(gname, "short") == short then ok = rankIndex == 0; break end
      end
    end
  elseif IsInRaid() then
    -- in a raid, the leader / assistants may send plans or pop windows open on people's screens
    for i = 1, GetNumGroupMembers() do
      local name, rank = GetRaidRosterInfo(i)
      if name and Ambiguate(name, "short") == short then ok = (rank or 0) > 0; break end
    end
  else
    ok = UnitIsGroupLeader(short)
  end
  if not ok then
    if why and msg:match("^[PU]%d+|1|") and short ~= UnitName("player") then say("ignored a plan from " .. short .. ": " .. why .. ".") end
    return
  end
  local kind, id, i, n, part = msg:match("^([BPU])(%d+)|(%d+)|(%d+)|(.*)$")
  if not id then return end
  i, n = tonumber(i), tonumber(n)
  if n > 3000 then return end
  if (kind == "P" or kind == "U") and short == UnitName("player") then return end     -- my own plan coming back
  if done[kind .. id] then return end                                 -- already got it on another channel
  local key = short .. kind .. id
  local box = incoming[key]
  if not box then
    box = { parts = {}, got = 0 }; incoming[key] = box
    if kind == "P" then say(short .. " is sending the newest raid plan...") end
  end
  if not box.parts[i] then box.parts[i] = part; box.got = box.got + 1 end
  if box.got < n then return end
  incoming[key] = nil
  done[kind .. id] = true
  local okDe, t = pcall(de, table.concat(box.parts), 1)
  if not okDe or type(t) ~= "table" then return end

  if kind == "P" then
    if type(t.raids) ~= "table" then return end
    HatedCompanionDB = HatedCompanionDB or {}
    HatedCompanionDB.syncedPlan = t           -- kept across /reload and log-outs
    HatedCompanionDB.syncedOver = (filePlan and filePlan.updated) or ""
    adopt(t)
    say("plan updated from " .. short .. " (saved " .. tostring(t.updated) .. "). /hated to view.")
    if UI.frame and UI.frame:IsShown() then Show(current, currentRaid) end
    return
  end

  if kind == "U" then
    if type(t.boss) ~= "table" or not t.boss.id then return end
    HatedPlan = HatedPlan or { raids = {} }
    HatedPlan.raids = HatedPlan.raids or {}
    local old, oldRaid = findBoss(t.boss.id)
    if old then
      t.boss.image, t.boss.pix = old.image, old.pix          -- the screenshot stays what I have
      for _, raid in ipairs(HatedPlan.raids) do
        for bi, bb in ipairs(raid.bosses or {}) do if bb == old then raid.bosses[bi] = t.boss end end
      end
    else
      local into
      for _, raid in ipairs(HatedPlan.raids) do if raid.name == t.raid then into = raid end end
      if not into then into = { name = t.raid or "Raid", bosses = {} }; HatedPlan.raids[#HatedPlan.raids + 1] = into end
      into.bosses[#into.bosses + 1] = t.boss
    end
    if type(t.classes) == "table" then HatedPlan.classes = t.classes end
    if t.leader then HatedPlan.leader = t.leader end
    if (t.updated or "") > (HatedPlan.updated or "") then HatedPlan.updated, HatedPlan.by = t.updated, t.by end
    HatedCompanionDB = HatedCompanionDB or {}
    HatedCompanionDB.syncedPlan = HatedPlan
    HatedCompanionDB.syncedOver = (filePlan and filePlan.updated) or ""
    say(short .. " updated " .. tostring(t.boss.name) .. ". /hated to view.")
    if UI.frame and UI.frame:IsShown() then
      if current and current.id == t.boss.id then current = t.boss end
      Show(current, currentRaid, true)
    end
    return
  end

  if type(t.boss) ~= "table" then return end
  -- prefer my own copy's screenshot info; the text is the sender's (newest) version
  local mineB = findBoss(t.boss.id)
  t.boss.image = nil
  local fileImg = mineB and mineB.image
  if not fileImg and filePlan then
    for _, raid in ipairs(filePlan.raids or {}) do for _, fb in ipairs(raid.bosses or {}) do if fb.id == t.boss.id then fileImg = fb.image end end end
  end
  if fileFits(fileImg, t.boss) then t.boss.image = fileImg end
  if type(t.classes) == "table" then HatedPlan = HatedPlan or { raids = {} }; HatedPlan.classes = HatedPlan.classes or t.classes end
  pushedFrom = short
  Show(t.boss, t.raid)
  PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
end)

-- ---------- editing the plan in game (Raid Leader) ----------
-- Edits change the plan in memory and are saved straight away (the addon's saved settings, kept across /reload and
-- log-outs). "Send boss" sends just the boss you're on; "Send plan to guild" sends everything.
local MARK_ORDER = { 8, 7, 1, 5, 6, 4, 3, 2 }            -- Skull, Cross, Star, Moon, Square, Triangle, Diamond, Circle
local MARK_LABEL = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
local function nowStamp() return date("!%Y-%m-%d %H:%M") end   -- UTC, the same format the website writes

local function persist()
  HatedCompanionDB = HatedCompanionDB or {}
  HatedCompanionDB.syncedPlan = HatedPlan
  HatedCompanionDB.syncedOver = (filePlan and filePlan.updated) or ""
end
local function edited(b)
  b.edited = true
  HatedPlan.updated, HatedPlan.by, HatedPlan.edited = nowStamp(), UnitName("player"), true
  persist()
  Show(current, currentRaid, true)
end

-- who can be picked: the plan's roster, everyone in the group right now, and anyone already in this fight
local function candidates(b)
  local set, list = {}, {}
  local function add(n) if n and n ~= "" and not set[n] then set[n] = true; list[#list + 1] = n end end
  for n in pairs((HatedPlan and HatedPlan.classes) or {}) do add(n) end
  if IsInRaid() then for i = 1, GetNumGroupMembers() do add((GetRaidRosterInfo(i))) end
  elseif IsInGroup() then add(UnitName("player")); for i = 1, GetNumSubgroupMembers() do add(UnitName("party" .. i)) end end
  for _, t in ipairs(b.tanks or {}) do add(t.n) end
  for _, h in ipairs(b.heals or {}) do add(h.n) end
  for _, j in ipairs(b.jobs or {}) do add(j.n) end
  table.sort(list, function(a, c) return a:lower() < c:lower() end)
  return list
end

-- a small menu at the cursor: items { text, func, checked, keep (stay open), title (heading) }
local menu, catcher
local function closeMenu() if menu then menu:Hide() end; if catcher then catcher:Hide() end end
local function openMenu(items, refresh)
  if not menu then
    catcher = CreateFrame("Button", nil, UIParent); catcher:SetAllPoints(UIParent); catcher:SetFrameStrata("FULLSCREEN")
    catcher:SetScript("OnClick", closeMenu)
    menu = CreateFrame("Frame", "HatedPlanMenu", UIParent, "BackdropTemplate")
    menu:SetFrameStrata("FULLSCREEN_DIALOG"); menu:SetClampedToScreen(true)
    flat(menu, 0.05, 0.035, 0.025, 0.98, 0.8, 0.63, 0.3, 0.9)
    menu.btns = {}
    tinsert(UISpecialFrames, "HatedPlanMenu")
    menu:SetScript("OnHide", function() if catcher then catcher:Hide() end end)
  end
  menu.items, menu.refresh = items, refresh
  local y, w = 6, 160
  for i, it in ipairs(items) do
    local bt = menu.btns[i]
    if not bt then
      bt = CreateFrame("Button", nil, menu)
      bt:SetHeight(20)
      bt.hl = bt:CreateTexture(nil, "HIGHLIGHT"); bt.hl:SetAllPoints(); bt.hl:SetColorTexture(1, 0.85, 0.5, 0.15)
      bt.check = bt:CreateTexture(nil, "ARTWORK"); bt.check:SetSize(14, 14); bt.check:SetPoint("LEFT", 6, 0)
      bt.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
      bt.text = bt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); bt.text:SetPoint("LEFT", 24, 0); bt.text:SetJustifyH("LEFT")
      bt:SetScript("OnClick", function(self)
        local item = self.item
        if item.title then return end
        if not item.keep then closeMenu() end
        if item.func then item.func() end
        if item.keep and menu.refresh then openMenu(menu.refresh(), menu.refresh) end
      end)
      menu.btns[i] = bt
    end
    bt.item = it
    bt.text:SetText(it.text)
    if it.title then bt.text:SetTextColor(1, 0.84, 0.48); bt.hl:SetAlpha(0) else bt.text:SetTextColor(0.92, 0.88, 0.8); bt.hl:SetAlpha(1) end
    bt.check:SetShown(it.checked and true or false)
    bt:ClearAllPoints(); bt:SetPoint("TOPLEFT", 4, -y); bt:SetPoint("RIGHT", menu, "RIGHT", -4, 0); bt:Show()
    w = math.max(w, bt.text:GetStringWidth() + 40)
    y = y + 20
  end
  for i = #items + 1, #menu.btns do menu.btns[i]:Hide() end
  menu:SetSize(w, y + 6)
  if not menu:IsShown() then
    local x, cy = GetCursorPosition(); local s = UIParent:GetEffectiveScale()
    menu:ClearAllPoints(); menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s + 4, cy / s - 4)
  end
  catcher:Show(); menu:Show()
end

-- a text box: single line (Enter saves) or several lines (notes)
local editor
local function editText(title, value, multi, done)
  if not editor then
    editor = CreateFrame("Frame", "HatedPlanEditor", UIParent, "BackdropTemplate")
    editor:SetFrameStrata("FULLSCREEN_DIALOG"); editor:SetPoint("CENTER", 0, 80); editor:EnableMouse(true)
    flat(editor, 0.05, 0.035, 0.025, 0.98, 0.85, 0.68, 0.32, 1)
    editor.title = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal"); editor.title:SetPoint("TOPLEFT", 14, -12)
    editor.title:SetTextColor(1, 0.84, 0.48)
    local sf = CreateFrame("ScrollFrame", "HatedPlanEditorScroll", editor, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 14, -34); sf:SetPoint("BOTTOMRIGHT", -30, 44)
    local box = CreateFrame("EditBox", nil, sf)
    box:SetMultiLine(true); box:SetAutoFocus(true); box:SetFontObject("ChatFontNormal"); box:SetWidth(380)
    box:SetScript("OnEscapePressed", function() editor:Hide() end)
    box:SetScript("OnEnterPressed", function(self) if editor.multi and not IsShiftKeyDown() then self:Insert("\n") else editor.ok:Click() end end)
    sf:SetScrollChild(box)
    local bg = editor:CreateTexture(nil, "ARTWORK"); bg:SetPoint("TOPLEFT", sf, -4, 4); bg:SetPoint("BOTTOMRIGHT", sf, 24, -4); bg:SetColorTexture(0, 0, 0, 0.45)
    editor.box = box
    editor.ok = button(editor, "Save", 90, true); editor.ok:SetPoint("BOTTOMRIGHT", -14, 12)
    editor.ok:SetScript("OnClick", function() local v = editor.box:GetText():gsub("^%s+", ""):gsub("%s+$", ""); editor:Hide(); if editor.done then editor.done(v) end end)
    local cancel = button(editor, "Cancel", 80); cancel:SetPoint("RIGHT", editor.ok, "LEFT", -8, 0)
    cancel:SetScript("OnClick", function() editor:Hide() end)
    editor.hint = editor:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); editor.hint:SetPoint("BOTTOMLEFT", 14, 18)
    tinsert(UISpecialFrames, "HatedPlanEditor")
  end
  closeMenu()
  editor.multi, editor.done = multi, done
  editor:SetSize(430, multi and 280 or 120)
  editor.box:SetMultiLine(multi and true or false)
  editor.title:SetText(title)
  editor.hint:SetText(multi and "Shift+Enter saves" or "Enter saves, Esc cancels")
  editor.box:SetText(value or ""); editor.box:HighlightText(); editor:Show(); editor.box:SetFocus()
end

local function pickName(b, title, exclude, done)
  local items = { { text = title, title = true } }
  local skip = {}
  for _, n in ipairs(exclude or {}) do skip[n] = true end
  for _, n in ipairs(candidates(b)) do
    if not skip[n] then items[#items + 1] = { text = nameText(n), func = function() done(n) end } end
  end
  items[#items + 1] = { text = DIM .. "Someone else...|r", func = function() editText("Name", "", false, function(v) if v ~= "" then done(v) end end) end }
  openMenu(items)
end

local function markEntry(list, num, create)
  for i, m in ipairs(list) do if m.m == num then return m, i end end
  if not create then return nil end
  local m = { m = num, label = MARK_LABEL[num], note = "", who = {} }
  list[#list + 1] = m
  local rank = {}; for i, v in ipairs(MARK_ORDER) do rank[v] = i end
  table.sort(list, function(a, c) return (rank[a.m] or 9) < (rank[c.m] or 9) end)
  return m
end
local function tidyMarks(list)
  for i = #list, 1, -1 do local m = list[i]; if #(m.who or {}) == 0 and (m.note or "") == "" then table.remove(list, i) end end
end

-- the sections in edit mode: every row clickable, empty sections shown, "+ add" rows
editSections = function(b)
  b.tanks, b.heals, b.marks, b.floor, b.jobs, b.kill = b.tanks or {}, b.heals or {}, b.marks or {}, b.floor or {}, b.jobs or {}, b.kill or {}
  local S = {}
  local function section(title, tex, key) local s = { title = title .. "  |cff4dff88(click to edit)|r", tex = tex, key = key, rows = {} }; S[#S + 1] = s; return s end
  local function addRow(s, text, fn) s.rows[#s.rows + 1] = { left = "|cff7fbf7f+ " .. text .. "|r", onClick = fn } end

  local s = section("Tanks", TANK_TEX, "Tanks")
  for i, t in ipairs(b.tanks) do
    local tag = i == 1 and "Main tank" or i == 2 and "Off tank" or ("Tank " .. i)
    s.rows[#s.rows + 1] = { left = DIM .. tag .. "|r   " .. nameText(t.n), right = (t.job ~= "" and safe(t.job) or DIM .. "set a job|r"), onClick = function()
      local it = {
        { text = nameText(t.n), title = true },
        { text = "Set job...", func = function() editText(t.n .. "'s job", t.job, false, function(v) t.job = v; edited(b) end) end },
        { text = "Change player...", func = function() pickName(b, "Tank", nil, function(n) t.n = n; edited(b) end) end },
      }
      if i > 1 then it[#it + 1] = { text = "Move up", func = function() b.tanks[i], b.tanks[i - 1] = b.tanks[i - 1], b.tanks[i]; edited(b) end } end
      it[#it + 1] = { text = "|cffff7b6aRemove|r", func = function() table.remove(b.tanks, i); edited(b) end }
      openMenu(it)
    end }
  end
  addRow(s, "Add tank", function() local ex = {}; for _, t in ipairs(b.tanks) do ex[#ex + 1] = t.n end
    pickName(b, "Add a tank", ex, function(n) b.tanks[#b.tanks + 1] = { n = n, job = "" }; edited(b) end) end)

  s = section("Healers", HEAL_TEX, "Healers")
  for i, h in ipairs(b.heals) do
    local target = (h.t and h.t ~= "") and nameText(h.t) or "|cffc8b48aRaid healing|r"
    s.rows[#s.rows + 1] = { left = nameText(h.n), right = target, onClick = function()
      local items = { { text = nameText(h.n) .. " heals", title = true } }
      for _, t in ipairs(b.tanks) do items[#items + 1] = { text = nameText(t.n), checked = h.t == t.n, func = function() h.t = t.n; h.c = true; edited(b) end } end
      items[#items + 1] = { text = "Raid healing", checked = (h.t or "") == "", func = function() h.t = ""; h.c = true; edited(b) end }
      items[#items + 1] = { text = "Change player...", func = function() pickName(b, "Healer", nil, function(n) h.n = n; edited(b) end) end }
      items[#items + 1] = { text = "|cffff7b6aRemove|r", func = function() table.remove(b.heals, i); edited(b) end }
      openMenu(items)
    end }
  end
  addRow(s, "Add healer", function() local ex = {}; for _, h in ipairs(b.heals) do ex[#ex + 1] = h.n end
    pickName(b, "Add a healer", ex, function(n) b.heals[#b.heals + 1] = { n = n, t = (b.tanks[1] and b.tanks[1].n) or "", c = true }; edited(b) end) end)

  for _, set in ipairs({ { "marks", "Target markers", MARK_TEX .. "8" }, { "floor", "Floor markers", MARK_TEX .. "6" } }) do
    local list = b[set[1]]
    s = section(set[2], set[3], set[2])
    for _, num in ipairs(MARK_ORDER) do
      local m = markEntry(list, num, false)
      s.rows[#s.rows + 1] = { mark = num,
        left = (m and m.note ~= "" and ("|cffecc867" .. safe(m.note) .. "|r")) or (DIM .. MARK_LABEL[num] .. "|r"),
        right = (m and #m.who > 0) and names(m.who) or (DIM .. "-|r"),
        onClick = function()
          local function items()
            local me = markEntry(list, num, false)
            local it = { { text = icon(num, 14) .. " " .. MARK_LABEL[num], title = true },
              { text = (me and me.note ~= "" and ("Note: " .. safe(me.note)) or "Set a note...") , func = function()
                editText(MARK_LABEL[num] .. ": what's it for?", me and me.note or "", false, function(v)
                  local e = markEntry(list, num, true); e.note = v; tidyMarks(list); edited(b) end) end } }
            for _, n in ipairs(candidates(b)) do
              local has = false
              if me then for _, w in ipairs(me.who) do if w == n then has = true end end end
              it[#it + 1] = { text = nameText(n), checked = has, keep = true, func = function()
                local e = markEntry(list, num, true)
                if has then for k = #e.who, 1, -1 do if e.who[k] == n then table.remove(e.who, k) end end else e.who[#e.who + 1] = n end
                tidyMarks(list); edited(b)
              end }
            end
            return it
          end
          openMenu(items(), items)
        end }
    end
  end

  s = section("Interrupts, CC & jobs", JOB_TEX, "Jobs")
  for i, j in ipairs(b.jobs) do
    s.rows[#s.rows + 1] = { left = nameText(j.n), right = (j.what ~= "" and safe(j.what) or DIM .. "set the job|r"), onClick = function()
      openMenu({
        { text = nameText(j.n), title = true },
        { text = "Edit job...", func = function() editText("Job for " .. j.n, j.what, false, function(v) j.what = v; edited(b) end) end },
        { text = "Change player...", func = function() pickName(b, "Who", nil, function(n) j.n = n; edited(b) end) end },
        { text = "|cffff7b6aRemove|r", func = function() table.remove(b.jobs, i); edited(b) end },
      })
    end }
  end
  addRow(s, "Add job", function() pickName(b, "Who does it?", nil, function(n)
    editText("Job for " .. n, "", false, function(v) b.jobs[#b.jobs + 1] = { n = n, what = v }; edited(b) end) end) end)

  -- kill order and notes
  local seq = {}
  for _, i in ipairs(b.kill) do seq[#seq + 1] = icon(i, 24) end
  local kill = { title = "Kill order  |cff4dff88(click to edit)|r", tex = MARK_TEX .. "8", key = "Kill", rows = {
    { left = #seq > 0 and table.concat(seq, "  |cffb8862e>|r  ") or (DIM .. "click to build the kill order|r"), big = #seq > 0, onClick = function()
      local function items()
        local it = { { text = "Add to the kill order", title = true } }
        for _, num in ipairs(MARK_ORDER) do it[#it + 1] = { text = icon(num, 14) .. " " .. MARK_LABEL[num], keep = true, func = function() b.kill[#b.kill + 1] = num; edited(b) end } end
        if #b.kill > 0 then
          it[#it + 1] = { text = "Remove the last one", keep = true, func = function() table.remove(b.kill); edited(b) end }
          it[#it + 1] = { text = "|cffff7b6aClear|r", func = function() wipe(b.kill); edited(b) end }
        end
        return it
      end
      openMenu(items(), items)
    end },
    { left = (b.killNote or "") ~= "" and safe(b.killNote) or (DIM .. "+ kill order note|r"), onClick = function()
      editText("Kill order note", b.killNote or "", false, function(v) b.killNote = v; edited(b) end) end },
  } }
  local notes = { title = "Notes  |cff4dff88(click to edit)|r", tex = "Interface\\Icons\\INV_Misc_Note_01", key = "Notes", rows = {
    { left = (b.notes or "") ~= "" and safe(b.notes) or (DIM .. "click to write notes|r"), onClick = function()
      editText(b.name .. ": notes", b.notes or "", true, function(v) b.notes = v; edited(b) end) end } } }
  return S, kill, notes
end

-- send just this boss (text; each player keeps their own screenshot)
function UI.SendBoss()
  if not current or not iAmLeader() then return end
  local c = {}
  for k, v in pairs(current) do if k ~= "image" and k ~= "pix" then c[k] = v end end
  local channels = { "GUILD" }
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do local u = "raid" .. i; if UnitExists(u) and not UnitIsInMyGuild(u) then channels[2] = "RAID"; break end end
  end
  if not IsInGuild() then channels = { IsInRaid() and "RAID" or "PARTY" } end
  local _, n = send("U", { boss = c, raid = currentRaid, updated = HatedPlan.updated, by = HatedPlan.by, leader = HatedPlan.leader, classes = HatedPlan.classes }, channels)
  progress = current.name
  say(string.format("sending %s to the guild (%d piece%s).", current.name, n, n == 1 and "" or "s"))
end

function UI.ToggleEdit()
  if not iAmLeader() then return end
  UI.editing = not UI.editing
  closeMenu()
  Show(current, currentRaid, true)
end

-- ---------- /hated ----------
SLASH_HATEDPLAN1 = "/hated"
SLASH_HATEDPLAN2 = "/hplan"
SlashCmdList.HATEDPLAN = function(msg)
  local extra = (msg or ""):match("^%s*[Mm][Ee]%s*(.*)$")
  if extra then
    HatedCompanionDB = HatedCompanionDB or {}
    if extra == "" then HatedCompanionDB.planNames = nil; say("highlighting names matching your character's first or last name.")
    else HatedCompanionDB.planNames = { extra }; say("also highlighting \"" .. extra .. "\".") end
    if UI.frame and UI.frame:IsShown() and current then Show(current, currentRaid) end
    return
  end
  msg = (msg or ""):lower()
  if msg == "show" then UI.Push(); return end
  if msg == "send" or msg == "sync" then UI.SendPlan(); return end
  if UI.frame and UI.frame:IsShown() then UI.frame:Hide(); return end
  pushedFrom = nil
  if current then Show(current, currentRaid); return end
  local first, rname
  for _, raid in ipairs((HatedPlan and HatedPlan.raids) or {}) do
    if raid.bosses and raid.bosses[1] then first, rname = raid.bosses[1], raid.name; break end
  end
  Show(first, rname)
end
