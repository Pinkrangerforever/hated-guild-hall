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
local meHex = "ff4dff88"   -- your name gently pulses: a soft fade between bright and calmer green
local function nameText(name)
  if not name or name == "" then return DIM .. "?|r" end
  if isMe(name) then return "|c" .. meHex .. safe(name) .. "|r" end
  local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classOf(name) or ""]
  return (c and ("|c" .. (c.colorStr or "ffffffff")) or "|cffe8d6b0") .. safe(name) .. "|r"
end
local TANK_ICON = "|TInterface\\Icons\\Ability_Defend:16:16:0:0:64:64:5:59:5:59|t "
local HEAL_ICON = "|TInterface\\Icons\\Spell_Holy_Heal:16:16:0:0:64:64:5:59:5:59|t "
local function names(list)
  local out = {}
  for _, n in ipairs(list or {}) do out[#out + 1] = nameText(n) end
  return #out > 0 and table.concat(out, ", ") or DIM .. "nobody|r"
end

-- ---------- the fight text ----------
local function bossText(b)
  local L, mine = {}, {}
  local function add(s) L[#L + 1] = s end
  local function head(s, ic) add(" "); add((ic or "") .. GOLD .. s:upper() .. "|r") end

  for _, t in ipairs(b.tanks or {}) do
    if isMe(t.n) then mine[#mine + 1] = "Tank: " .. (t.job ~= "" and safe(t.job) or "see the plan") end
  end
  for _, h in ipairs(b.heals or {}) do
    if isMe(h.n) then mine[#mine + 1] = "Heal " .. ((h.t and h.t ~= "") and nameText(h.t) or "the raid") end
    if h.t and h.t ~= "" and isMe(h.t) then mine[#mine + 1] = "Healed by " .. nameText(h.n) end
  end
  for _, set in ipairs({ { b.marks, "Kill / handle" }, { b.floor, "Stand at" } }) do
    for _, m in ipairs(set[1] or {}) do
      for _, n in ipairs(m.who or {}) do
        if isMe(n) then mine[#mine + 1] = set[2] .. " " .. icon(m.m) .. " " .. safe(m.label) .. (m.note ~= "" and (" - " .. safe(m.note)) or "") end
      end
    end
  end
  for _, j in ipairs(b.jobs or {}) do
    if isMe(j.n) then mine[#mine + 1] = safe(j.what) end
  end

  if b.notes and b.notes ~= "" then head("Notes"); add(safe(b.notes)) end
  if b.tanks and #b.tanks > 0 then
    head("Tanks", TANK_ICON)
    for i, t in ipairs(b.tanks) do add((i == 1 and "MT " or i == 2 and "OT " or ("T" .. i .. " ")) .. nameText(t.n) .. (t.job ~= "" and (DIM .. "  -  |r" .. safe(t.job)) or "")) end
  end
  if b.heals and #b.heals > 0 then
    head("Healers", HEAL_ICON)
    for _, h in ipairs(b.heals) do
      add(nameText(h.n) .. DIM .. "  ->  |r" .. ((h.t and h.t ~= "") and nameText(h.t) or "Raid healing") .. (h.c and (GOLD .. "  (this fight)|r") or ""))
    end
  end
  for _, set in ipairs({ { b.marks, "Target markers" }, { b.floor, "Floor markers (where to stand)" } }) do
    if set[1] and #set[1] > 0 then
      head(set[2])
      for _, m in ipairs(set[1]) do
        add(icon(m.m, 18) .. " " .. (m.note ~= "" and (GOLD .. safe(m.note) .. "|r: ") or "") .. names(m.who))
      end
    end
  end
  if b.jobs and #b.jobs > 0 then
    head("Interrupts, CC & other jobs")
    for _, j in ipairs(b.jobs) do add(nameText(j.n) .. DIM .. "  -  |r" .. safe(j.what)) end
  end
  if (b.kill and #b.kill > 0) or (b.killNote and b.killNote ~= "") then
    head("Kill order")
    local seq = {}
    for _, i in ipairs(b.kill or {}) do seq[#seq + 1] = icon(i, 20) end
    if #seq > 0 then add(table.concat(seq, GOLD .. "  >  |r")) end
    if b.killNote and b.killNote ~= "" then add(safe(b.killNote)) end
  end
  if #L == 0 then add(DIM .. "Nothing planned for this fight yet.|r") end
  return table.concat(L, "\n"), mine
end

-- ---------- window ----------
local UI = {}
local current, currentRaid, pushedFrom

local MEDIA = "Interface\\AddOns\\HatedCompanion\\Media\\"
local BANNER_H = 176

-- dark leather panel with a thin gold edge (the website's look)
local function backdrop(f, r, g, b, a)
  f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  f:SetBackdropColor(r or 0.045, g or 0.032, b or 0.022, a or 0.88)
  f:SetBackdropBorderColor(0.72, 0.56, 0.28, 0.9)
end
local function vfade(tex, r, g, b, a1, a2)   -- vertical fade (top a1 -> bottom a2), safe on old and new APIs
  tex:SetColorTexture(1, 1, 1, 1)
  if CreateColor and pcall(tex.SetGradient, tex, "VERTICAL", CreateColor(r, g, b, a2), CreateColor(r, g, b, a1)) then return end
  if tex.SetGradientAlpha then tex:SetGradientAlpha("VERTICAL", r, g, b, a2, r, g, b, a1) else tex:SetColorTexture(r, g, b, (a1 + a2) / 2) end
end
local function panelTitle(p, text)
  local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetPoint("TOPLEFT", 10, -8); fs:SetText(text); fs:SetTextColor(0.93, 0.78, 0.4)
  local line = p:CreateTexture(nil, "ARTWORK")
  line:SetPoint("TOPLEFT", 8, -22); line:SetPoint("TOPRIGHT", -8, -22); line:SetHeight(1)
  line:SetColorTexture(0.72, 0.56, 0.28, 0.45)
  return fs
end

local function canPush()
  if IsInRaid() then return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") end
  return IsInGroup() and UnitIsGroupLeader("player")
end

local Show   -- forward

local function build()
  if UI.frame then return end
  local f = CreateFrame("Frame", "HatedPlanFrame", UIParent, "BackdropTemplate")
  f:SetSize(1120, 730); f:SetPoint("CENTER"); f:SetFrameStrata("HIGH"); f:SetToplevel(true)
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  f:SetResizable(true)
  if f.SetResizeBounds then f:SetResizeBounds(900, 560, 1900, 1200) elseif f.SetMinResize then f:SetMinResize(900, 560); f:SetMaxResize(1900, 1200) end
  local saved = HatedCompanionDB and HatedCompanionDB.planSize
  if saved and saved.w then f:SetSize(saved.w, saved.h) end
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(18, 18); grip:SetPoint("BOTTOMRIGHT", -6, 6); grip:SetFrameLevel(f:GetFrameLevel() + 12)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    HatedCompanionDB = HatedCompanionDB or {}
    HatedCompanionDB.planSize = { w = math.floor(f:GetWidth()), h = math.floor(f:GetHeight()) }
    if current then Show(current, currentRaid) end      -- re-flow the text and screenshot
  end)
  f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 26,
    insets = { left = 7, right = 7, top = 7, bottom = 7 } })
  f:SetBackdropColor(0.035, 0.024, 0.016, 0.97)
  f:SetBackdropBorderColor(1, 0.8, 0.45, 1)
  tinsert(UISpecialFrames, "HatedPlanFrame")   -- Esc closes it
  UI.frame = f

  -- the website banner across the top, fading into the window
  local banner = f:CreateTexture(nil, "ARTWORK")
  banner:SetPoint("TOPLEFT", 7, -7); banner:SetPoint("TOPRIGHT", -7, -7); banner:SetHeight(BANNER_H)
  UI.banner = banner
  banner:SetTexture(MEDIA .. "Banner"); banner:SetTexCoord(0, 1, 0, 171 / 256)
  local fade = f:CreateTexture(nil, "ARTWORK", nil, 2)
  fade:SetPoint("BOTTOMLEFT", banner, "BOTTOMLEFT"); fade:SetPoint("BOTTOMRIGHT", banner, "BOTTOMRIGHT"); fade:SetHeight(70)
  vfade(fade, 0.035, 0.024, 0.016, 0, 1)
  local shade = f:CreateTexture(nil, "ARTWORK", nil, 1)       -- darken the banner a touch so the title reads
  shade:SetAllPoints(banner); shade:SetColorTexture(0, 0, 0, 0.12)
  local rule = f:CreateTexture(nil, "ARTWORK", nil, 3)
  rule:SetPoint("TOPLEFT", banner, "BOTTOMLEFT", 20, 0); rule:SetPoint("TOPRIGHT", banner, "BOTTOMRIGHT", -20, 0); rule:SetHeight(1)
  rule:SetColorTexture(0.85, 0.68, 0.32, 0.6)

  -- the guild crest, overlapping the top-left corner
  local crest = CreateFrame("Frame", nil, f); crest:SetSize(132, 132); crest:SetPoint("TOPLEFT", -22, 26)
  crest:SetFrameLevel(f:GetFrameLevel() + 10)
  local ct = crest:CreateTexture(nil, "OVERLAY"); ct:SetAllPoints(); ct:SetTexture(MEDIA .. "Icon")

  -- title under the banner
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.title:SetPoint("BOTTOMLEFT", banner, "BOTTOMLEFT", 118, 10)
  f.title:SetTextColor(1, 0.84, 0.45); f.title:SetShadowOffset(1, -1); f.title:SetShadowColor(0, 0, 0, 1)
  f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.sub:SetPoint("BOTTOMLEFT", 16, 13)

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4); close:SetFrameLevel(f:GetFrameLevel() + 11)

  local TOP = -(7 + BANNER_H + 8)
  UI.leftAnchorY = TOP

  -- left: bosses
  local left = CreateFrame("Frame", nil, f, "BackdropTemplate")
  left:SetPoint("TOPLEFT", 14, TOP); left:SetPoint("BOTTOMLEFT", 14, 34); left:SetWidth(196)
  UI.left = left
  backdrop(left); panelTitle(left, "BOSSES")
  local ls = CreateFrame("ScrollFrame", nil, left, "UIPanelScrollFrameTemplate")
  ls:SetPoint("TOPLEFT", 6, -28); ls:SetPoint("BOTTOMRIGHT", -26, 6)
  local lc = CreateFrame("Frame", nil, ls); lc:SetSize(160, 10); ls:SetScrollChild(lc)
  UI.list, UI.buttons, UI.heads = lc, {}, {}

  -- middle: the fight
  local mid = CreateFrame("Frame", nil, f, "BackdropTemplate")
  mid:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0); mid:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT", 8, 0); mid:SetWidth(476)
  backdrop(mid)
  UI.mid = mid
  mid.name = mid:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  mid.name:SetPoint("TOPLEFT", 12, -9); mid.name:SetPoint("RIGHT", -12, 0); mid.name:SetJustifyH("LEFT")
  mid.name:SetTextColor(1, 0.84, 0.45)
  local mline = mid:CreateTexture(nil, "ARTWORK")
  mline:SetPoint("TOPLEFT", 8, -30); mline:SetPoint("TOPRIGHT", -8, -30); mline:SetHeight(1); mline:SetColorTexture(0.72, 0.56, 0.28, 0.45)

  -- your jobs, in a softly pulsing gold box
  local mine = CreateFrame("Frame", nil, mid, "BackdropTemplate")
  mine:SetPoint("TOPLEFT", 10, -40); mine:SetPoint("RIGHT", -10, 0)
  mine:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  mine:SetBackdropColor(0.2, 0.14, 0.03, 0.9); mine:SetBackdropBorderColor(1, 0.83, 0.3, 1)
  mine.glow = mine:CreateTexture(nil, "BACKGROUND", nil, -1)
  mine.glow:SetPoint("TOPLEFT", -6, 6); mine.glow:SetPoint("BOTTOMRIGHT", 6, -6)
  mine.glow:SetColorTexture(1, 0.8, 0.25, 0.14)
  local ag = mine:CreateAnimationGroup(); ag:SetLooping("BOUNCE")
  local a = ag:CreateAnimation("Alpha"); a:SetFromAlpha(1); a:SetToAlpha(0.7); a:SetDuration(1.1); a:SetSmoothing("IN_OUT")
  mine.anim = ag
  mine.text = mine:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  mine.text:SetPoint("TOPLEFT", 12, -10); mine.text:SetPoint("RIGHT", -12, 0); mine.text:SetJustifyH("LEFT"); mine.text:SetSpacing(4)
  UI.mine = mine

  local ms = CreateFrame("ScrollFrame", nil, mid, "UIPanelScrollFrameTemplate")
  ms:SetPoint("BOTTOMRIGHT", -28, 42)
  UI.scroll = ms
  local mc = CreateFrame("Frame", nil, ms); mc:SetSize(424, 10); ms:SetScrollChild(mc)
  UI.layout = function()
    local w, h = f:GetWidth(), f:GetHeight()
    local bh = math.max(120, math.min(BANNER_H, (w - 14) * 171 / 1024, h * 0.26))
    banner:SetHeight(bh)
    left:ClearAllPoints(); left:SetPoint("TOPLEFT", 14, -(7 + bh + 8)); left:SetPoint("BOTTOMLEFT", 14, 34)
    local mw = math.max(380, math.floor((w - 14 - 196 - 8 - 8 - 14) * 0.52))
    mid:SetWidth(mw); mc:SetWidth(mw - 52); mc.text:SetWidth(mw - 56)
  end
  f:SetScript("OnSizeChanged", function() UI.layout() end)
  mc.text = mc:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  mc.text:SetPoint("TOPLEFT", 4, 0); mc.text:SetWidth(420); mc.text:SetJustifyH("LEFT"); mc.text:SetSpacing(4)
  UI.body = mc

  local bline = mid:CreateTexture(nil, "ARTWORK")
  bline:SetPoint("BOTTOMLEFT", 8, 38); bline:SetPoint("BOTTOMRIGHT", -8, 38); bline:SetHeight(1); bline:SetColorTexture(0.72, 0.56, 0.28, 0.35)
  local push = CreateFrame("Button", nil, mid, "UIPanelButtonTemplate")
  push:SetSize(140, 24); push:SetPoint("BOTTOMRIGHT", -10, 9); push:SetText("Open for raid")
  push:SetMotionScriptsWhileDisabled(true)
  push:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine("Open for raid", 1, 0.82, 0.3)
    GameTooltip:AddLine(canPush() and "Opens this boss on every raider's screen (raiders with the addon)." or "Be in a raid as leader or assistant to use this.", 1, 1, 1, true); GameTooltip:Show() end)
  push:SetScript("OnLeave", GameTooltip_Hide)
  push:SetScript("OnClick", function() UI.Push() end)
  UI.pushBtn = push
  local sendAll = CreateFrame("Button", nil, mid, "UIPanelButtonTemplate")
  sendAll:SetSize(170, 24); sendAll:SetPoint("BOTTOMLEFT", 10, 9); sendAll:SetText("Send plan to guild")
  sendAll:SetScript("OnClick", function() UI.SendPlan() end)
  UI.sendBtn = sendAll

  -- right: screenshot
  local right = CreateFrame("Button", nil, f, "BackdropTemplate")
  right:SetPoint("TOPLEFT", mid, "TOPRIGHT", 8, 0); right:SetPoint("BOTTOMRIGHT", -14, 34)
  backdrop(right, 0.02, 0.014, 0.01, 0.95); panelTitle(right, "STRATEGY")
  right.tex = right:CreateTexture(nil, "ARTWORK")
  right.none = right:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  right.none:SetPoint("CENTER"); right.none:SetText("No screenshot for this fight")
  right.hint = right:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  right.hint:SetPoint("BOTTOM", 0, 8); right.hint:SetText("Click to enlarge")
  right:SetScript("OnClick", function() if current and current.image then UI.Zoom() end end)
  UI.right = right

  -- big view of the screenshot
  local z = CreateFrame("Button", "HatedPlanZoom", UIParent, "BackdropTemplate")
  z:SetFrameStrata("DIALOG"); z:SetPoint("CENTER"); z:Hide()
  z:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 26,
    insets = { left = 7, right = 7, top = 7, bottom = 7 } })
  z:SetBackdropColor(0, 0, 0, 0.96); z:SetBackdropBorderColor(1, 0.8, 0.45, 1)
  z.tex = z:CreateTexture(nil, "ARTWORK"); z.tex:SetPoint("TOPLEFT", 9, -9); z.tex:SetPoint("BOTTOMRIGHT", -9, 9)
  z:SetScript("OnClick", z.Hide)
  tinsert(UISpecialFrames, "HatedPlanZoom")
  UI.zoom = z
end

local function setImage(holder, tex, img, maxW, maxH)
  local w, h = img.w or 1024, img.h or 512
  local s = math.min(maxW / w, maxH / h)
  tex:SetTexture(IMG_PATH .. img.file)
  tex:SetTexCoord(0, img.u or 1, 0, img.v or 1)
  return w * s, h * s
end

function UI.Zoom()
  local img, z = current.image, UI.zoom
  local w, h = setImage(z, z.tex, img, UIParent:GetWidth() * 0.9, UIParent:GetHeight() * 0.85)
  z:SetSize(w + 18, h + 18); z:Show()
end

local function refreshList()
  local lc, y = UI.list, 0
  for _, b in ipairs(UI.buttons) do b:Hide() end
  for _, h in ipairs(UI.heads) do h:Hide() end
  local bi, hi = 0, 0
  for _, raid in ipairs((HatedPlan and HatedPlan.raids) or {}) do
    hi = hi + 1
    local h = UI.heads[hi]
    if not h then h = lc:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); h:SetJustifyH("LEFT"); h:SetWidth(160); UI.heads[hi] = h end
    h:SetText((raid.name or ""):upper()); h:SetTextColor(0.78, 0.66, 0.45); h:ClearAllPoints(); h:SetPoint("TOPLEFT", 2, -y - 2); h:Show()
    y = y + 20
    for _, b in ipairs(raid.bosses or {}) do
      bi = bi + 1
      local btn = UI.buttons[bi]
      if not btn then
        btn = CreateFrame("Button", nil, lc)
        btn:SetSize(160, 22)
        btn.hl = btn:CreateTexture(nil, "BACKGROUND"); btn.hl:SetAllPoints(); btn.hl:SetColorTexture(1, 0.78, 0.3, 0.16)
        btn.bar = btn:CreateTexture(nil, "ARTWORK"); btn.bar:SetPoint("TOPLEFT"); btn.bar:SetPoint("BOTTOMLEFT"); btn.bar:SetWidth(3)
        btn.bar:SetColorTexture(1, 0.82, 0.35, 1)
        local hov = btn:CreateTexture(nil, "HIGHLIGHT"); hov:SetAllPoints(); hov:SetColorTexture(1, 0.9, 0.6, 0.08)
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        btn.text:SetPoint("LEFT", 10, 0); btn.text:SetPoint("RIGHT", -2, 0); btn.text:SetJustifyH("LEFT")
        btn:SetScript("OnClick", function(self) pushedFrom = nil; Show(self.boss, self.raid) end)
        UI.buttons[bi] = btn
      end
      btn.boss, btn.raid = b, raid.name
      btn.text:SetText(b.name)
      local sel = current and current.id == b.id
      btn.hl:SetShown(sel); btn.bar:SetShown(sel)
      if sel then btn.text:SetTextColor(1, 0.86, 0.5) else btn.text:SetTextColor(0.9, 0.86, 0.78) end
      btn:ClearAllPoints(); btn:SetPoint("TOPLEFT", 0, -y); btn:Show()
      y = y + 23
    end
    y = y + 8
  end
  if bi == 0 then
    hi = hi + 1
    local h = UI.heads[hi] or lc:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); UI.heads[hi] = h
    h:SetWidth(160); h:SetJustifyH("LEFT"); h:ClearAllPoints(); h:SetPoint("TOPLEFT", 0, 0)
    h:SetText("No plan yet. The raid leader can send one in game, or download the addon again from hatedforever.com."); h:Show()
    y = 60
  end
  lc:SetHeight(y)
end

Show = function(b, raidName)
  build()
  UI.layout()
  current, currentRaid = b, raidName
  local f = UI.frame
  f.title:SetText("BOSS PLAN" .. (raidName and ("   |cffc8b48a" .. safe(raidName) .. "|r") or ""))
  f.sub:SetText((pushedFrom and ("Shown by " .. pushedFrom .. ".  ") or "") ..
    ((HatedPlan and HatedPlan.updated) and ("Plan saved " .. HatedPlan.updated .. (HatedPlan.by and (" by " .. HatedPlan.by) or "")) or ""))
  refreshList()
  UI.pushBtn:SetShown(b ~= nil and (canPush() or iAmLeader()))
  UI.pushBtn:SetEnabled(canPush())
  UI.sendBtn:SetShown(iAmLeader() and HatedPlan ~= nil and HatedPlan.raids ~= nil and #HatedPlan.raids > 0)

  if not b then
    UI.mid.name:SetText(""); UI.mine:Hide(); UI.body.text:SetText(DIM .. "Pick a boss on the left.|r")
    UI.scroll:ClearAllPoints(); UI.scroll:SetPoint("TOPLEFT", 8, -40); UI.scroll:SetPoint("BOTTOMRIGHT", -28, 42)
    UI.right.tex:Hide(); UI.right.none:Show(); UI.right.hint:Hide(); f:Show(); return
  end
  UI.mid.name:SetText(b.name)
  local body, mine = bossText(b)
  local top = -40
  if #mine > 0 then
    UI.mine.text:SetText(ME_COLOR .. "YOUR JOBS|r\n" .. table.concat(mine, "\n"))
    UI.mine:SetHeight(UI.mine.text:GetStringHeight() + 20)
    UI.mine:Show(); UI.mine.anim:Play()
    top = -40 - UI.mine:GetHeight() - 10
  else
    UI.mine:Hide(); UI.mine.anim:Stop()
  end
  UI.scroll:ClearAllPoints(); UI.scroll:SetPoint("TOPLEFT", 8, top); UI.scroll:SetPoint("BOTTOMRIGHT", -28, 42)
  UI.body.text:SetText(body)
  UI.body:SetHeight(UI.body.text:GetStringHeight() + 10)
  UI.scroll:SetVerticalScroll(0)

  local r = UI.right
  if b.image and b.image.file then
    local w, h = setImage(r, r.tex, b.image, r:GetWidth() - 16, r:GetHeight() - 56)
    r.tex:ClearAllPoints(); r.tex:SetPoint("TOP", 0, -30); r.tex:SetSize(w, h); r.tex:Show(); r.none:Hide(); r.hint:Show()
  else
    r.tex:Hide(); r.none:Show(); r.hint:Hide()
  end
  f:Show()
end

local function redraw()
  if not current or not UI.frame or not UI.frame:IsShown() then return end
  local body, mine = bossText(current)
  UI.body.text:SetText(body)
  if #mine > 0 then UI.mine.text:SetText(ME_COLOR .. "YOUR JOBS|r\n" .. table.concat(mine, "\n")) end
end
do
  local t0 = GetTime()
  C_Timer.NewTicker(0.08, function()
    if not current or not UI.frame or not UI.frame:IsShown() then return end
    local k = 0.72 + 0.28 * (0.5 + 0.5 * math.sin((GetTime() - t0) * math.pi * 2 / 2.2))   -- 2.2s breath, 72-100%
    meHex = string.format("ff%02x%02x%02x", math.floor(77 + (180 - 77) * (1 - k)), math.floor(255 * k), math.floor(136 * k + 60 * (1 - k)))
    redraw()
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
