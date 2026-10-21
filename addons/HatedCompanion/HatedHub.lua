--[[ Hated Companion: the hub
  Opening the addon (/hated, or clicking the H on the minimap) shows the hub: one tile per module.
    Boss Strategies   the raid's boss plans (/hated plan)
    Hated TCG         your points (and soon packs and your binder) (/tcg)
  A plan the raid leader opens for the raid still goes straight to Boss Strategies.
]]

local MEDIA = "Interface\\AddOns\\HatedCompanion\\Media\\"
local BG, EDGE = { 0.043, 0.031, 0.022 }, { 0.55, 0.43, 0.22 }
local hub

local function flat(f, r, g, b, a, er, eg, eb, ea)
  f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  f:SetBackdropColor(r, g, b, a); f:SetBackdropBorderColor(er, eg, eb, ea)
end
local function vfade(tex, r, g, b, a1, a2)
  tex:SetColorTexture(1, 1, 1, 1)
  if CreateColor and pcall(tex.SetGradient, tex, "VERTICAL", CreateColor(r, g, b, a2), CreateColor(r, g, b, a1)) then return end
  tex:SetColorTexture(r, g, b, (a1 + a2) / 2)
end

local openPlan   -- the Boss Strategies window (the original /hated)

-- a big clickable tile: art on the left, title and a live line on the right
local function tile(parent, accent, title, sub, onClick)
  local t = CreateFrame("Button", nil, parent, "BackdropTemplate")
  t:SetSize(290, 196)
  flat(t, 0.06, 0.045, 0.03, 0.95, accent[1], accent[2], accent[3], 0.55)
  t.art = t:CreateTexture(nil, "ARTWORK")
  t.glow = t:CreateTexture(nil, "BACKGROUND", nil, 1); t.glow:SetPoint("TOPLEFT", 1, -1); t.glow:SetPoint("BOTTOMRIGHT", -1, 1)
  vfade(t.glow, accent[1], accent[2], accent[3], 0, 0.16)
  t.title = t:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); t.title:SetText(title)
  t.title:SetTextColor(accent[1], accent[2], accent[3]); t.title:SetShadowOffset(1, -1)
  t.sub = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); t.sub:SetText(sub); t.sub:SetJustifyH("LEFT")
  t.live = t:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); t.live:SetJustifyH("LEFT")
  t.go = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); t.go:SetPoint("BOTTOMRIGHT", -12, 10); t.go:SetText("Open  >")
  t.go:SetTextColor(accent[1], accent[2], accent[3])
  local hl = t:CreateTexture(nil, "HIGHLIGHT"); hl:SetPoint("TOPLEFT", 1, -1); hl:SetPoint("BOTTOMRIGHT", -1, 1); hl:SetColorTexture(accent[1], accent[2], accent[3], 0.08)
  t:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1) end)
  t:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.55) end)
  t:SetScript("OnClick", function() hub:Hide(); onClick() end)
  t.accent = accent
  t.recolor = function(r, g, b)
    accent[1], accent[2], accent[3] = r, g, b
    t:SetBackdropBorderColor(r, g, b, 0.55)
    vfade(t.glow, r, g, b, 0, 0.16)
    t.title:SetTextColor(r, g, b); t.go:SetTextColor(r, g, b)
  end
  return t
end

local function build()
  if hub then return hub end
  local f = CreateFrame("Frame", "HatedHubFrame", UIParent, "BackdropTemplate"); f:Hide()   -- created hidden, so the first click opens it
  f:SetSize(950, 392); f:SetPoint("CENTER", 0, 40); f:SetFrameStrata("HIGH"); f:SetToplevel(true)   -- wide enough for three tiles
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton"); f:SetClampedToScreen(true)
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  flat(f, BG[1], BG[2], BG[3], 0.97, 0.75, 0.6, 0.3, 0.9)
  tinsert(UISpecialFrames, "HatedHubFrame")

  -- the banner art, cropped to a strip, fading into the window
  local banner = f:CreateTexture(nil, "ARTWORK")
  banner:SetPoint("TOPLEFT", 1, -1); banner:SetPoint("TOPRIGHT", -1, -1); banner:SetHeight(104)
  banner:SetTexture(MEDIA .. "Banner")
  local A, ART = 948 / 104, 1024 / 171
  local vh = (171 / 256) * ART / A; local v0 = math.max(0, 0.47 * 171 / 256 - vh / 2)
  banner:SetTexCoord(0, 1, v0, v0 + vh)
  local fade = f:CreateTexture(nil, "ARTWORK", nil, 2); fade:SetPoint("BOTTOMLEFT", banner); fade:SetPoint("BOTTOMRIGHT", banner); fade:SetHeight(50)
  vfade(fade, BG[1], BG[2], BG[3], 0, 1)
  local crest = f:CreateTexture(nil, "OVERLAY"); crest:SetSize(96, 96); crest:SetPoint("LEFT", banner, "LEFT", 8, -2); crest:SetTexture(MEDIA .. "Icon")
  -- the title gets its own line under the banner (on the banner it fought the logo), between two gold rules
  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOP", banner, "BOTTOM", 0, -6)
  title:SetText("H A T E D   C O M P A N I O N"); title:SetTextColor(1, 0.85, 0.48); title:SetShadowOffset(1, -1)
  for _, side in ipairs({ -1, 1 }) do
    local rule = f:CreateTexture(nil, "ARTWORK"); rule:SetHeight(1); rule:SetWidth(300)
    if side < 0 then rule:SetPoint("RIGHT", title, "LEFT", -14, 0) else rule:SetPoint("LEFT", title, "RIGHT", 14, 0) end
    rule:SetColorTexture(1, 1, 1, 1)
    local a1, a2 = side < 0 and 0 or 0.7, side < 0 and 0.7 or 0
    if CreateColor and pcall(rule.SetGradient, rule, "HORIZONTAL", CreateColor(0.85, 0.68, 0.32, a1), CreateColor(0.85, 0.68, 0.32, a2)) then else rule:SetColorTexture(0.85, 0.68, 0.32, 0.5) end
  end
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 2, 2); close:SetFrameLevel(f:GetFrameLevel() + 5)

  -- Boss Strategies
  local boss = tile(f, { 1, 0.82, 0.4 }, "Boss Strategies", "Your raid's boss plans: your jobs,\nmarkers, kill order and strategy maps.", function() if openPlan then openPlan("") end end)
  boss:SetPoint("TOPLEFT", 20, -146)
  boss.art:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"); boss.art:SetSize(64, 64); boss.art:SetPoint("LEFT", 18, 6)
  boss.title:SetPoint("TOPLEFT", 96, -26); boss.sub:SetPoint("TOPLEFT", boss.title, "BOTTOMLEFT", 0, -6); boss.sub:SetWidth(180)
  boss.live:SetPoint("BOTTOMLEFT", 18, 12); boss.live:SetWidth(200)
  f.boss = boss

  -- Hated TCG
  local tcg = tile(f, { 0.35, 1, 0.95 }, "Hated TCG", "Earn points killing monsters,\nthen open card packs.", function() if HatedTCG_Toggle then HatedTCG_Toggle(true) end end)
  tcg:SetPoint("TOPRIGHT", -20, -146)
  tcg.art:SetTexture(MEDIA .. "CardBack"); tcg.art:SetTexCoord(0, 1, 0, 382 / 512); tcg.art:SetSize(66, 98); tcg.art:SetPoint("LEFT", 16, 6)
  tcg.title:SetPoint("TOPLEFT", 96, -26); tcg.sub:SetPoint("TOPLEFT", tcg.title, "BOTTOMLEFT", 0, -6); tcg.sub:SetWidth(180)
  tcg.live:SetPoint("BOTTOMLEFT", 96, 30); tcg.live:SetWidth(180)
  f.tcg = tcg

  -- Guild Professions
  local prof = tile(f, { 0.55, 0.85, 1 }, "Guild Professions", "Who in the guild can craft what:\nsearch any recipe or enchant.", function() if HatedProf_Toggle then HatedProf_Toggle() end end)
  prof:SetPoint("TOP", 0, -146)
  prof.art:SetTexture("Interface\\Icons\\Trade_BlackSmithing"); prof.art:SetSize(60, 60); prof.art:SetPoint("LEFT", 18, 6)
  prof.title:SetPoint("TOPLEFT", 96, -26); prof.sub:SetPoint("TOPLEFT", prof.title, "BOTTOMLEFT", 0, -6); prof.sub:SetWidth(180)
  prof.live:SetPoint("BOTTOMLEFT", 18, 12); prof.live:SetWidth(200)
  f.prof = prof

  -- footer: a switch for the TCG nameplate dots, and the addon's version
  -- the switch: a pill track (teal when on, dark leather when off) with a metal knob that slides across
  local sw = CreateFrame("Button", nil, f)
  sw:SetSize(52, 26); sw:SetPoint("BOTTOMLEFT", 20, 10)
  sw.off = sw:CreateTexture(nil, "BACKGROUND"); sw.off:SetAllPoints(); sw.off:SetTexture(MEDIA .. "SwitchOff")
  sw.on = sw:CreateTexture(nil, "BORDER"); sw.on:SetAllPoints(); sw.on:SetTexture(MEDIA .. "SwitchOn")
  sw.knob = sw:CreateTexture(nil, "OVERLAY"); sw.knob:SetSize(26, 26); sw.knob:SetTexture(MEDIA .. "SwitchKnob")
  local hov = sw:CreateTexture(nil, "HIGHLIGHT"); hov:SetAllPoints(); hov:SetTexture(MEDIA .. "SwitchOn"); hov:SetBlendMode("ADD"); hov:SetAlpha(0.15)
  local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); label:SetPoint("LEFT", sw, "RIGHT", 10, 0)
  label:SetText("Show TCG on screen: nameplate dots, tooltip line and +points popups")
  local pos, goal = 1, 1           -- 0 = off (left), 1 = on (right); the knob eases toward the goal
  local function place()
    sw.knob:ClearAllPoints(); sw.knob:SetPoint("CENTER", sw, "LEFT", 13 + pos * 26, 0)
    sw.on:SetAlpha(pos); sw.off:SetAlpha(1 - pos * 0.7)
  end
  sw:SetScript("OnUpdate", function(_, dt)
    if pos == goal then return end
    pos = pos + (goal - pos) * math.min(1, dt * 14)
    if math.abs(goal - pos) < 0.01 then pos = goal end
    place()
  end)
  local function paint(instant)
    local on = not HatedTCG_DotsOn or HatedTCG_DotsOn()
    goal = on and 1 or 0
    if instant then pos = goal end
    place()
    label:SetTextColor(on and 0.9 or 0.6, on and 0.95 or 0.58, on and 0.93 or 0.55)
    if f.tcg then
      if on then f.tcg.recolor(0.35, 1, 0.95) else f.tcg.recolor(0.5, 0.5, 0.5) end
      f.tcg.art:SetDesaturated(not on); f.tcg.art:SetAlpha(on and 1 or 0.6)
      if f.refreshTcgLine then f.refreshTcgLine() end
    end
  end
  sw:SetScript("OnClick", function() if HatedTCG_SetDots then HatedTCG_SetDots(not HatedTCG_DotsOn()) end; paint(); PlaySound(SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON or 1115) end)
  sw:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine("Show TCG on screen", 0.35, 1, 0.95)
    GameTooltip:AddLine("The teal dots and tooltip line on mobs your account has never killed, and the +10 / +1 TCG popups. Turn it off if you only use Boss Strategies: your kills still earn points, so they are all there if you start playing the TCG later.", 1, 1, 1, true); GameTooltip:Show() end)
  sw:SetScript("OnLeave", GameTooltip_Hide)
  local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local ver = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); ver:SetPoint("BOTTOMRIGHT", -14, 14)
  ver:SetText("Hated Companion v" .. ((meta and meta("HatedCompanion", "Version")) or "?"))

  -- the points line on the TCG tile (teal, or grey while the TCG is switched off)
  f.refreshTcgLine = function()
    local total, new, synced = 0, 0, false
    if HatedTCG_Summary then total, new, synced = HatedTCG_Summary() end
    local on = not HatedTCG_DotsOn or HatedTCG_DotsOn()
    local big, small = on and "|cff5afff2" or "|cffa0a0a0", on and "|cff9cc7c1" or "|cff808080"
    tcg.live:SetText(synced and string.format("%s%s|r %spoints|r", big, BreakUpLargeNumbers and BreakUpLargeNumbers(total) or total, small)
      or string.format("%s+%d|r %spoints to sync|r", big, new, small))
  end
  f.refresh = function()
    paint(true)
    -- the plan: how many bosses, when it was saved
    local n, raids = 0, 0
    for _, raid in ipairs((HatedPlan and HatedPlan.raids) or {}) do raids = raids + 1; n = n + #(raid.bosses or {}) end
    boss.live:SetText(n > 0 and string.format("|cffc8b48a%d boss%s in %d raid%s|r", n, n == 1 and "" or "es", raids, raids == 1 and "" or "s") or "|cff8f7f62No plan yet|r")
    -- professions shared so far
    local chars, recipes = 0, 0
    if HatedProf_Summary then chars, recipes = HatedProf_Summary() end
    prof.live:SetText(chars > 0 and string.format("|cff9fd8ff%d crafter%s - %d recipes|r", chars, chars == 1 and "" or "s", recipes) or "|cff6f8a9aOpen a profession window to start|r")
    -- points
    f.refreshTcgLine()
  end
  hub = f
  return f
end

function HatedHub_Toggle()
  local f = build()
  if f:IsShown() then f:Hide() else f.refresh(); f:Show() end
end

-- /hated now opens the hub; "/hated plan" (and anything else /hated already understood) still works
local prev = SlashCmdList.HATEDPLAN
openPlan = function(msg) return prev(msg) end
SlashCmdList.HATEDPLAN = function(msg)
  local m = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if m == "" then
    -- if a plan window is already open, the same command closes it
    if HatedPlanFrame and HatedPlanFrame:IsShown() then HatedPlanFrame:Hide(); return end
    if HatedTCGFrame and HatedTCGFrame:IsShown() then HatedTCGFrame:Hide(); return end
    if HatedProfFrame and HatedProfFrame:IsShown() then HatedProfFrame:Hide(); return end
    HatedHub_Toggle(); return
  end
  if m == "plan" then return prev("") end
  return prev(msg)
end
