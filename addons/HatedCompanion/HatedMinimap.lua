--[[ Hated Companion: minimap button
  A round minimap button with a big gold H. Left-click opens or closes the boss plan (/hated). Drag it around the
  minimap's edge; where you leave it is remembered. /hated minimap hides or shows it.
]]

local btn = CreateFrame("Button", "HatedMinimapButton", Minimap)
btn:SetSize(32, 32)
btn:SetFrameStrata("MEDIUM"); btn:SetFrameLevel(8)
btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btn:RegisterForDrag("LeftButton")
btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local bg = btn:CreateTexture(nil, "BACKGROUND")
bg:SetSize(20, 20); bg:SetPoint("CENTER", 0, 1)
bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
bg:SetVertexColor(0.25, 0.08, 0.06, 1)          -- dark red leather

local h = btn:CreateFontString(nil, "ARTWORK")
h:SetFont(STANDARD_TEXT_FONT, 17, "THICKOUTLINE")
h:SetPoint("CENTER", 0, 1)
h:SetText("H")
h:SetTextColor(1, 0.82, 0.3)                     -- gold
btn.h = h

local border = btn:CreateTexture(nil, "OVERLAY")
border:SetSize(54, 54); border:SetPoint("TOPLEFT")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

local function db() HatedCompanionDB = HatedCompanionDB or {}; return HatedCompanionDB end

local function place()
  local a = math.rad(db().minimapAngle or 200)
  local r = (Minimap:GetWidth() / 2) + 5
  btn:ClearAllPoints()
  btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

btn:SetScript("OnDragStart", function(self)
  self:SetScript("OnUpdate", function()
    local mx, my = Minimap:GetCenter()
    local x, y = GetCursorPosition()
    local s = Minimap:GetEffectiveScale()
    db().minimapAngle = math.deg(math.atan2(y / s - my, x / s - mx))
    place()
  end)
end)
btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

btn:SetScript("OnClick", function(_, mouse) if mouse == "RightButton" and HatedTCG_Toggle then HatedTCG_Toggle() else SlashCmdList.HATEDPLAN("") end end)
btn:SetScript("OnMouseDown", function() h:SetPoint("CENTER", 1, 0) end)
btn:SetScript("OnMouseUp", function() h:SetPoint("CENTER", 0, 1) end)

btn:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine("Hated Companion", 1, 0.82, 0.3)
  GameTooltip:AddLine("Click: boss plan", 1, 1, 1)
  GameTooltip:AddLine("Right-click: Hated TCG", 0.25, 0.95, 0.85)
  GameTooltip:AddLine("Drag: move this button", 0.7, 0.7, 0.7)
  if HatedPlan and HatedPlan.updated then GameTooltip:AddLine("Plan saved " .. HatedPlan.updated, 0.6, 0.55, 0.45) end
  GameTooltip:Show()
end)
btn:SetScript("OnLeave", GameTooltip_Hide)

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
  place()
  btn:SetShown(not db().minimapHidden)
end)

-- /hated minimap toggles it (hooked into the /hated command)
local orig = SlashCmdList.HATEDPLAN
SlashCmdList.HATEDPLAN = function(msg)
  if (msg or ""):lower():match("^%s*minimap%s*$") then
    db().minimapHidden = not db().minimapHidden
    btn:SetShown(not db().minimapHidden)
    DEFAULT_CHAT_FRAME:AddMessage("|cffd6a940Hated Plan:|r minimap button " .. (db().minimapHidden and "hidden (/hated minimap to bring it back)." or "shown."))
    return
  end
  return orig(msg)
end
