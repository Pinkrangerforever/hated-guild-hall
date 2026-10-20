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
  return t
end

local function build()
  if hub then return hub end
  local f = CreateFrame("Frame", "HatedHubFrame", UIParent, "BackdropTemplate")
  f:SetSize(640, 352); f:SetPoint("CENTER", 0, 40); f:SetFrameStrata("HIGH"); f:SetToplevel(true)
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton"); f:SetClampedToScreen(true)
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  flat(f, BG[1], BG[2], BG[3], 0.97, 0.75, 0.6, 0.3, 0.9)
  tinsert(UISpecialFrames, "HatedHubFrame")

  -- the banner art, cropped to a strip, fading into the window
  local banner = f:CreateTexture(nil, "ARTWORK")
  banner:SetPoint("TOPLEFT", 1, -1); banner:SetPoint("TOPRIGHT", -1, -1); banner:SetHeight(104)
  banner:SetTexture(MEDIA .. "Banner")
  local A, ART = 638 / 104, 1024 / 171
  local vh = (171 / 256) * ART / A; local v0 = math.max(0, 0.47 * 171 / 256 - vh / 2)
  banner:SetTexCoord(0, 1, v0, v0 + vh)
  local fade = f:CreateTexture(nil, "ARTWORK", nil, 2); fade:SetPoint("BOTTOMLEFT", banner); fade:SetPoint("BOTTOMRIGHT", banner); fade:SetHeight(50)
  vfade(fade, BG[1], BG[2], BG[3], 0, 1)
  local crest = f:CreateTexture(nil, "OVERLAY"); crest:SetSize(96, 96); crest:SetPoint("LEFT", banner, "LEFT", 8, -2); crest:SetTexture(MEDIA .. "Icon")
  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge"); title:SetPoint("LEFT", crest, "RIGHT", 4, 6)
  title:SetText("Hated Companion"); title:SetTextColor(1, 0.85, 0.48); title:SetShadowOffset(1, -1)
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 2, 2); close:SetFrameLevel(f:GetFrameLevel() + 5)

  -- Boss Strategies
  local boss = tile(f, { 1, 0.82, 0.4 }, "Boss Strategies", "Your raid's boss plans: your jobs,\nmarkers, kill order and strategy maps.", function() if openPlan then openPlan("") end end)
  boss:SetPoint("TOPLEFT", 20, -128)
  boss.art:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"); boss.art:SetSize(64, 64); boss.art:SetPoint("LEFT", 18, 6)
  boss.title:SetPoint("TOPLEFT", 96, -26); boss.sub:SetPoint("TOPLEFT", boss.title, "BOTTOMLEFT", 0, -6); boss.sub:SetWidth(180)
  boss.live:SetPoint("BOTTOMLEFT", 18, 12); boss.live:SetWidth(200)
  f.boss = boss

  -- Hated TCG
  local tcg = tile(f, { 0.25, 0.95, 0.85 }, "Hated TCG", "Earn points killing monsters,\nthen open card packs.", function() if HatedTCG_Toggle then HatedTCG_Toggle(true) end end)
  tcg:SetPoint("TOPRIGHT", -20, -128)
  tcg.art:SetTexture(MEDIA .. "CardBack"); tcg.art:SetTexCoord(0, 1, 0, 382 / 512); tcg.art:SetSize(66, 98); tcg.art:SetPoint("LEFT", 16, 6)
  tcg.title:SetPoint("TOPLEFT", 96, -26); tcg.sub:SetPoint("TOPLEFT", tcg.title, "BOTTOMLEFT", 0, -6); tcg.sub:SetWidth(180)
  tcg.live:SetPoint("BOTTOMLEFT", 96, 30); tcg.live:SetWidth(180)
  f.tcg = tcg

  f.refresh = function()
    -- the plan: how many bosses, when it was saved
    local n, raids = 0, 0
    for _, raid in ipairs((HatedPlan and HatedPlan.raids) or {}) do raids = raids + 1; n = n + #(raid.bosses or {}) end
    boss.live:SetText(n > 0 and string.format("|cffc8b48a%d boss%s in %d raid%s|r", n, n == 1 and "" or "es", raids, raids == 1 and "" or "s") or "|cff8f7f62No plan yet|r")
    -- points
    local total, new, synced = 0, 0, false
    if HatedTCG_Summary then total, new, synced = HatedTCG_Summary() end
    tcg.live:SetText(synced and string.format("|cff3ff2d9%s|r |cff9cc7c1points|r", BreakUpLargeNumbers and BreakUpLargeNumbers(total) or total)
      or string.format("|cff3ff2d9+%d|r |cff9cc7c1points to sync|r", new))
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
    HatedHub_Toggle(); return
  end
  if m == "plan" then return prev("") end
  return prev(msg)
end
