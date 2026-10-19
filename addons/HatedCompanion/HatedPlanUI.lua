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
  local function section(title, tex) local s = { title = title, tex = tex, rows = {} }; S[#S + 1] = s; return s end

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
  for _, set in ipairs({ { b.marks, "Target markers", "Kill / handle" }, { b.floor, "Floor markers  |cff8f7f62where to stand|r", "Stand at" } }) do
    if set[1] and #set[1] > 0 then
      local s = section(set[2], MARK_TEX .. "8")
      for _, m in ipairs(set[1]) do
        s.rows[#s.rows + 1] = { mark = m.m, left = (m.note ~= "" and ("|cffecc867" .. safe(m.note) .. "|r") or DIM .. safe(m.label) .. "|r"), right = names(m.who), me = anyMe(m.who) }
        if anyMe(m.who) then mine[#mine + 1] = set[3] .. " " .. icon(m.m, 14) .. " " .. safe(m.label) .. (m.note ~= "" and (" - " .. safe(m.note)) or "") end
      end
    end
  end
  if b.jobs and #b.jobs > 0 then
    local s = section("Interrupts, CC & jobs", JOB_TEX)
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

  -- middle: the fight
  local mid = CreateFrame("Frame", nil, f, "BackdropTemplate")
  mid:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0); mid:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT", 10, 0); mid:SetWidth(480)
  flat(mid)
  UI.mid = mid
  mid.name = mid:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  mid.name:SetPoint("TOPLEFT", 14, -10); mid.name:SetPoint("RIGHT", -14, 0); mid.name:SetJustifyH("LEFT")
  mid.name:SetTextColor(1, 0.85, 0.48)
  local mline = mid:CreateTexture(nil, "ARTWORK")
  mline:SetPoint("TOPLEFT", 1, -34); mline:SetPoint("TOPRIGHT", -1, -34); mline:SetHeight(1)
  hfade(mline, EDGE[1], EDGE[2], EDGE[3], 0.7, 0.05)

  -- your jobs: a gold card with a soft breathing glow
  local mine = CreateFrame("Frame", nil, mid, "BackdropTemplate")
  mine:SetPoint("TOPLEFT", 10, -44); mine:SetPoint("RIGHT", -10, 0)
  flat(mine, 0.16, 0.11, 0.03, 0.95, 1, 0.8, 0.32, 0.85)
  mine.bar = mine:CreateTexture(nil, "ARTWORK"); mine.bar:SetPoint("TOPLEFT", 1, -1); mine.bar:SetPoint("BOTTOMLEFT", 1, 1); mine.bar:SetWidth(3)
  mine.bar:SetColorTexture(1, 0.82, 0.35, 1)
  mine.glow = mine:CreateTexture(nil, "BACKGROUND", nil, -1)
  mine.glow:SetPoint("TOPLEFT", -5, 5); mine.glow:SetPoint("BOTTOMRIGHT", 5, -5); mine.glow:SetColorTexture(1, 0.78, 0.25, 0.12)
  mine.head = mine:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  mine.head:SetPoint("TOPLEFT", 14, -9); mine.head:SetText("YOUR JOBS"); mine.head:SetTextColor(0.45, 1, 0.6)
  mine.text = mine:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  mine.text:SetPoint("TOPLEFT", 14, -26); mine.text:SetPoint("RIGHT", -12, 0); mine.text:SetJustifyH("LEFT"); mine.text:SetSpacing(4)
  UI.mine = mine

  local ms = CreateFrame("ScrollFrame", "HatedPlanBody", mid, "UIPanelScrollFrameTemplate")
  ms:SetPoint("BOTTOMRIGHT", -16, 44); slim(ms)
  UI.scroll = ms
  local mc = CreateFrame("Frame", nil, ms); mc:SetSize(440, 10); ms:SetScrollChild(mc)
  UI.body, UI.rows, UI.hdrs = mc, {}, {}

  local bline = mid:CreateTexture(nil, "ARTWORK")
  bline:SetPoint("BOTTOMLEFT", 1, 38); bline:SetPoint("BOTTOMRIGHT", -1, 38); bline:SetHeight(1); bline:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 0.35)
  local push = button(mid, "Open for raid", 130)
  push:SetPoint("BOTTOMRIGHT", -10, 8)
  push:SetScript("OnClick", function() UI.Push() end)
  push:SetMotionScriptsWhileDisabled(true)
  push:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine("Open for raid", 1, 0.82, 0.3)
    GameTooltip:AddLine(canPush() and "Opens this boss on every raider's screen (raiders with the addon)." or "Be in a raid as leader or assistant to use this.", 1, 1, 1, true); GameTooltip:Show() end)
  push:SetScript("OnLeave", GameTooltip_Hide)
  UI.pushBtn = push
  local sendAll = button(mid, "Send plan to guild", 150, true)
  sendAll:SetPoint("BOTTOMLEFT", 10, 8)
  sendAll:SetScript("OnClick", function() UI.SendPlan() end)
  sendAll:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine("Send plan to guild", 1, 0.82, 0.3)
    GameTooltip:AddLine("Sends every boss's plan to everyone online in the guild with the addon (and your raid).", 1, 1, 1, true); GameTooltip:Show() end)
  sendAll:SetScript("OnLeave", GameTooltip_Hide)
  UI.sendBtn = sendAll

  -- right: screenshot, then notes and kill order
  local right = CreateFrame("Frame", nil, f, "BackdropTemplate")
  right:SetPoint("TOPLEFT", mid, "TOPRIGHT", 10, 0); right:SetPoint("BOTTOMRIGHT", -12, 32)
  flat(right); caption(right, "STRATEGY")
  local shot = CreateFrame("Button", nil, right, "BackdropTemplate")
  shot:SetPoint("TOPLEFT", 10, -36)
  flat(shot, 0, 0, 0, 1, EDGE[1], EDGE[2], EDGE[3], 0.6)
  shot.tex = shot:CreateTexture(nil, "ARTWORK"); shot.tex:SetPoint("TOPLEFT", 1, -1); shot.tex:SetPoint("BOTTOMRIGHT", -1, 1)
  shot.hint = shot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  shot.hint:SetPoint("BOTTOMRIGHT", -6, 5); shot.hint:SetText("Click to enlarge"); shot.hint:SetAlpha(0)
  local hb = shot:CreateTexture(nil, "OVERLAY"); hb:SetPoint("BOTTOMLEFT", 1, 1); hb:SetPoint("BOTTOMRIGHT", -1, 1); hb:SetHeight(22)
  vfade(hb, 0, 0, 0, 0, 0.7); hb:SetAlpha(0); shot.hb = hb
  shot:SetScript("OnEnter", function(self) self.hint:SetAlpha(1); self.hb:SetAlpha(1); self:SetBackdropBorderColor(1, 0.82, 0.4, 1) end)
  shot:SetScript("OnLeave", function(self) self.hint:SetAlpha(0); self.hb:SetAlpha(0); self:SetBackdropBorderColor(EDGE[1], EDGE[2], EDGE[3], 0.6) end)
  shot:SetScript("OnClick", function() if current and current.image then UI.Zoom() end end)
  right.shot = shot
  right.none = right:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  right.none:SetText("No screenshot for this fight")

  local rs = CreateFrame("ScrollFrame", "HatedPlanNotes", right, "UIPanelScrollFrameTemplate")
  rs:SetPoint("BOTTOMRIGHT", -16, 8); slim(rs)
  local rc = CreateFrame("Frame", nil, rs); rc:SetSize(300, 10); rs:SetScrollChild(rc)
  rc.killHead = rc:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); rc.killHead:SetText("KILL ORDER"); rc.killHead:SetTextColor(0.85, 0.7, 0.4)
  rc.kill = rc:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge"); rc.kill:SetJustifyH("LEFT")
  rc.killNote = rc:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); rc.killNote:SetJustifyH("LEFT")
  rc.notesHead = rc:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); rc.notesHead:SetText("NOTES"); rc.notesHead:SetTextColor(0.85, 0.7, 0.4)
  rc.notes = rc:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); rc.notes:SetJustifyH("LEFT"); rc.notes:SetSpacing(4)
  right.scroll, right.body = rs, rc
  UI.right = right

  UI.layout = function()
    local w, h = f:GetWidth(), f:GetHeight()
    -- crop the banner art to the window's shape, keeping the logo in view
    local A, ART = (w - 2) / BANNER_H, 1024 / 171
    if A >= ART then
      local vh = (171 / 256) * ART / A; local c = 0.47 * 171 / 256
      local v0 = math.max(0, math.min(171 / 256 - vh, c - vh / 2))
      banner:SetTexCoord(0, 1, v0, v0 + vh)
    else
      local uw = A / ART; banner:SetTexCoord(0.5 - uw / 2, 0.5 + uw / 2, 0, 171 / 256)
    end
    local avail = w - 12 - 200 - 10 - 10 - 12
    local mw = math.max(400, math.floor(avail * 0.5))
    mid:SetWidth(mw); mc:SetWidth(mw - 40)
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

local function setImage(tex, img, maxW, maxH)
  local w, h = img.w or 1024, img.h or 512
  local s = math.min(maxW / w, maxH / h)
  tex:SetTexture(IMG_PATH .. img.file)
  tex:SetTexCoord(0, img.u or 1, 0, img.v or 1)
  return math.floor(w * s), math.floor(h * s)
end

function UI.Zoom()
  local z = UI.zoom
  local w, h = setImage(z.tex, current.image, UIParent:GetWidth() * 0.9, UIParent:GetHeight() * 0.85)
  z:SetSize(w + 8, h + 8); z:Show()
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

-- the middle column: section headers and two-column rows; your rows glow
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
  UI.rows[i] = r
  return r
end
local glowRows = {}
local function renderBody(sections)
  for _, h in ipairs(UI.hdrs) do h:Hide() end
  for _, r in ipairs(UI.rows) do r:Hide() end
  wipe(glowRows)
  local W = UI.body:GetWidth()
  local LW = math.floor(W * 0.42)
  local y, ri = 0, 0
  for si, s in ipairs(sections) do
    local h = header(si)
    h:ClearAllPoints(); h:SetPoint("TOPLEFT", 0, -y); h:SetPoint("RIGHT", UI.body, "RIGHT", 0, 0)
    h.icon:SetTexture(s.tex); if s.tex:find("RaidTargeting") then h.icon:SetTexCoord(0, 1, 0, 1) else h.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    h.text:SetText(s.title:upper()); h:Show()
    y = y + 28
    for k, d in ipairs(s.rows) do
      ri = ri + 1
      local r = row(ri)
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("RIGHT", UI.body, "RIGHT", 0, 0)
      local x = 10
      if d.mark then r.mark:SetTexture(MARK_TEX .. d.mark); r.mark:ClearAllPoints(); r.mark:SetPoint("TOPLEFT", 8, -4); r.mark:Show(); x = 32 else r.mark:Hide() end
      r.left:ClearAllPoints(); r.left:SetPoint("TOPLEFT", x, -6); r.left:SetWidth(LW - x)
      r.right:ClearAllPoints(); r.right:SetPoint("TOPLEFT", LW + 8, -6); r.right:SetWidth(W - LW - 16)
      r.left:SetText(d.left or ""); r.right:SetText(d.right or "")
      local rh = math.max(26, math.max(r.left:GetStringHeight(), r.right:GetStringHeight()) + 12)
      r:SetHeight(rh)
      r.bg:SetColorTexture(1, 1, 1, (k % 2 == 0) and 0.025 or 0)
      r.glow:SetShown(d.me); r.edge:SetShown(d.me)
      if d.me then glowRows[#glowRows + 1] = r end
      r:Show()
      y = y + rh
    end
    y = y + 12
  end
  if #sections == 0 then
    ri = ri + 1
    local r = row(ri); r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, 0); r:SetPoint("RIGHT", UI.body, "RIGHT")
    r.mark:Hide(); r.glow:Hide(); r.edge:Hide(); r.bg:SetColorTexture(0, 0, 0, 0)
    r.left:ClearAllPoints(); r.left:SetPoint("TOPLEFT", 10, -6); r.left:SetWidth(W - 20); r.left:SetText(DIM .. "Nothing planned for this fight yet.|r"); r.right:SetText("")
    r:SetHeight(30); r:Show(); y = 30
  end
  UI.body:SetHeight(y + 6)
end

local function renderRight(b)
  local r = UI.right
  local W = r:GetWidth() - 20
  local top = -36
  if b and b.image and b.image.file then
    local w, h = setImage(r.shot.tex, b.image, W, (r:GetHeight() - 40) * 0.6)
    r.shot:SetSize(w + 2, h + 2); r.shot:ClearAllPoints(); r.shot:SetPoint("TOP", 0, -36); r.shot:Show(); r.none:Hide()
    top = -36 - h - 14
  else
    r.shot:Hide(); r.none:ClearAllPoints(); r.none:SetPoint("TOP", 0, -60); r.none:Show()
    top = -90
  end
  local rs, rc = r.scroll, r.body
  rs:ClearAllPoints(); rs:SetPoint("TOPLEFT", 10, top); rs:SetPoint("BOTTOMRIGHT", -16, 8)
  rc:SetWidth(W - 10)
  local y = 0
  local function place(fs, gap) fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", 0, -y); fs:SetWidth(W - 14); fs:Show(); y = y + fs:GetStringHeight() + (gap or 6) end
  local hasKill = b and b.kill and #b.kill > 0
  local hasKillNote = b and b.killNote and b.killNote ~= ""
  if hasKill or hasKillNote then
    place(rc.killHead, 6)
    if hasKill then
      local seq = {}
      for _, i in ipairs(b.kill) do seq[#seq + 1] = icon(i, 26) end
      rc.kill:SetText(table.concat(seq, "  |cffb8862e>|r  ")); place(rc.kill, 8)
    else rc.kill:Hide() end
    if hasKillNote then rc.killNote:SetText(safe(b.killNote)); place(rc.killNote, 12) else rc.killNote:Hide() end
    y = y + 6
  else rc.killHead:Hide(); rc.kill:Hide(); rc.killNote:Hide() end
  if b and b.notes and b.notes ~= "" then
    place(rc.notesHead, 6); rc.notes:SetText(safe(b.notes)); place(rc.notes, 6)
  else rc.notesHead:Hide(); rc.notes:Hide() end
  rc:SetHeight(y + 4); rs:SetVerticalScroll(0)
end

Show = function(b, raidName)
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

  local top = -44
  if not b then
    UI.mid.name:SetText(""); UI.mine:Hide()
    renderBody({})
  else
    UI.mid.name:SetText(b.name)
    local sections, mine = bossSections(b)
    if #mine > 0 then
      UI.mine.text:SetText(table.concat(mine, "\n"))
      UI.mine:SetHeight(UI.mine.text:GetStringHeight() + 36)
      UI.mine:Show()
      top = -44 - UI.mine:GetHeight() - 12
    else
      UI.mine:Hide()
    end
    UI.scroll:ClearAllPoints(); UI.scroll:SetPoint("TOPLEFT", 10, top); UI.scroll:SetPoint("BOTTOMRIGHT", -16, 46)
    renderBody(sections)
  end
  UI.scroll:ClearAllPoints(); UI.scroll:SetPoint("TOPLEFT", 10, top); UI.scroll:SetPoint("BOTTOMRIGHT", -16, 46)
  UI.scroll:SetVerticalScroll(0)
  renderRight(b)
  f:Show()
end

-- your rows and the jobs card breathe softly while the window is open
do
  local t0 = GetTime()
  C_Timer.NewTicker(0.05, function()
    if not UI.frame or not UI.frame:IsShown() then return end
    local k = 0.5 + 0.5 * math.sin((GetTime() - t0) * math.pi * 2 / 2.4)
    for _, r in ipairs(glowRows) do r.glow:SetAlpha(0.45 + 0.55 * k) end
    if UI.mine:IsShown() then UI.mine.glow:SetAlpha(0.35 + 0.65 * k) end
  end)
end

local function findBoss(id)
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
local function pump()
  if #queue == 0 then
    sending = false
    if progress then say(progress .. " sent."); progress = nil end
    return
  end
  sending = true
  local m = queue[1]
  local r = C_ChatInfo.SendAddonMessage(PREFIX, m[1], m[2])
  -- newer clients return a result code and throttle bursts: wait and retry the same piece
  local ok = (r == nil or r == true or r == 0 or (Enum and Enum.SendAddonMessageResult and r == Enum.SendAddonMessageResult.Success))
  if ok then table.remove(queue, 1) end
  C_Timer.After(ok and 0.12 or 1, pump)
end
local function send(kind, payload, channels)
  channels = channels or { IsInRaid() and "RAID" or "PARTY" }
  local data = table.concat(ser(payload, {}))
  local id, CH = tostring(math.random(100000, 999999)), 220
  local n = math.ceil(#data / CH)
  for _, channel in ipairs(channels) do
    for i = 1, n do queue[#queue + 1] = { kind .. id .. "|" .. i .. "|" .. n .. "|" .. data:sub((i - 1) * CH + 1, i * CH), channel } end
  end
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
      r.bosses[#r.bosses + 1] = c
    end
    copy.raids[#copy.raids + 1] = r
  end
  local channels = { "GUILD" }
  if IsInRaid() then channels[2] = "RAID" end     -- PUGs in the raid get it too
  local _, n = send("P", copy, channels)
  progress = "Plan (saved " .. (HatedPlan.updated or "?") .. ")"
  say(string.format("sending the plan to everyone online in the guild%s with the addon (about %d seconds).", IsInRaid() and " and the raid" or "", math.ceil(n * 0.15)))
end

-- use a plan received in game when it's newer than the one the website saved, keeping my own screenshots
local filePlan
local function adopt(plan)
  local imgs = {}
  for _, raid in ipairs((filePlan and filePlan.raids) or {}) do
    for _, b in ipairs(raid.bosses or {}) do if b.image then imgs[b.id] = b.image end end
  end
  for _, raid in ipairs(plan.raids or {}) do
    for _, b in ipairs(raid.bosses or {}) do b.image = imgs[b.id] end
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
    if type(synced) == "table" and HatedCompanionDB.syncedOver == ((HatedPlan and HatedPlan.updated) or "") then adopt(synced) end
    return
  end
  if prefix ~= PREFIX or (channel ~= "RAID" and channel ~= "PARTY" and channel ~= "GUILD") then return end
  local short = Ambiguate(sender or "", "short")
  local ok = false
  if channel == "GUILD" then
    -- guild plans only from the Raid Leader (the website names them in the plan); without a plan yet, from the guild master
    if msg:sub(1, 1) ~= "P" then return end
    local l = leaderName()
    if l and l ~= "" then ok = matches(l, wordsOf(short))
    else
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
  if not ok then return end
  local kind, id, i, n, part = msg:match("^([BP])(%d+)|(%d+)|(%d+)|(.*)$")
  if not id then return end
  i, n = tonumber(i), tonumber(n)
  if n > 3000 then return end
  if kind == "P" and short == UnitName("player") then return end     -- my own plan coming back
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

  if type(t.boss) ~= "table" then return end
  -- prefer my own copy's screenshot info; the text is the sender's (newest) version
  local mineB = findBoss(t.boss.id)
  if mineB and mineB.image and not t.boss.image then t.boss.image = mineB.image end
  if type(t.classes) == "table" then HatedPlan = HatedPlan or { raids = {} }; HatedPlan.classes = HatedPlan.classes or t.classes end
  pushedFrom = short
  Show(t.boss, t.raid)
  PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
end)

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
