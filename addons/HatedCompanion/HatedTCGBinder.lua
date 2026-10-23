-- Hated TCG: your binder and decks in game.
-- The cards come from the website's "Export Cards to WoW!" code (HTCG3), pasted into the TCG window (/tcg):
-- HatedCompanionDB.tcg.cards[dbf] = { n = copies, h = holo copies }, .decks = { { name, hero = dbf, cards = { dbf, ... } } }.
-- Card art lives in Cards\cNN.blp, 12 cards a sheet; HatedTCG_CARDS (HatedTCGCards.lua) says which sheet and slot.

local ADDON = "Interface\\AddOns\\HatedCompanion\\"
local RARITY = { { 0.92, 0.92, 0.92, "Common" }, { 0.12, 1, 0, "Uncommon" }, { 0, 0.44, 0.87, "Rare" }, { 0.64, 0.21, 0.93, "Epic" }, { 1, 0.5, 0, "Legendary" } }
local CLASSES = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR", "DEMONHUNTER", "DEATHKNIGHT", "NEUTRAL" }
local CLASS_NAME = { DEMONHUNTER = "Demon Hunter", DEATHKNIGHT = "Death Knight" }
local function className(c) return CLASS_NAME[c] or (c and (c:sub(1, 1) .. c:sub(2):lower()) or "") end
local TEAL = { 0.25, 0.95, 0.85 }
local PER_PAGE, COLS = 10, 5
local CW, CH = 150, 206                                 -- a card on the page (the art is 248 x 340)

local function store() return HatedTCG_DB() end
local function card(dbf) return HatedTCG_CARDS and HatedTCG_CARDS[dbf] end

-- point a texture at a card's spot on its sheet
local function setArt(tex, dbf)
  local c = card(dbf); if not c then tex:SetTexture(nil); return end
  local S = HatedTCG_SHEET
  local col, row = c[11] % S.cols, math.floor(c[11] / S.cols)
  tex:SetTexture(string.format("%sCards\\c%02d", ADDON, c[10]))
  tex:SetTexCoord(col * S.w / S.size, (col + 1) * S.w / S.size, row * S.h / S.size, (row + 1) * S.h / S.size)
end

-- one card on screen: rarity glow behind, the art, holo foil on top, a copies badge
local holos = {}
local function makeCard(parent, w, h)
  local b = CreateFrame("Button", nil, parent); b:SetSize(w, h)
  -- the rarity glow: shaped like the card's frame (Media\Glow_<frame>; the card sits centred in it at 124 x 170 of 256)
  b.glow = b:CreateTexture(nil, "BACKGROUND"); b.glow:SetPoint("CENTER"); b.glow:SetSize(w * 256 / 124, h * 256 / 170)
  b.art = b:CreateTexture(nil, "ARTWORK"); b.art:SetAllPoints()
  b.holo = b:CreateTexture(nil, "OVERLAY"); b.holo:SetTexture(ADDON .. "Media\\Holo", "REPEAT", "REPEAT"); b.holo:SetBlendMode("ADD")
  b.holo:SetPoint("TOPLEFT", w * 0.04, -h * 0.03); b.holo:SetPoint("BOTTOMRIGHT", -w * 0.04, h * 0.03); b.holo:SetAlpha(0.45); b.holo:Hide()
  holos[#holos + 1] = b.holo
  b.count = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); b.count:SetPoint("BOTTOM", 0, 2); b.count:SetTextColor(TEAL[1], TEAL[2], TEAL[3])
  b.set = function(self, dbf, own)
    self.dbf = dbf
    local c = card(dbf)
    if not c then self:Hide(); return end
    setArt(self.art, dbf)
    local r = RARITY[c[2]] or RARITY[1]
    self.glow:SetTexture(ADDON .. "Media\\Glow_" .. (c[12] or "minion"))
    self.glow:SetVertexColor(r[1], r[2], r[3]); self.glow:SetAlpha(c[2] >= 4 and 1 or 0.8)
    self.holo:SetShown(own and (own.h or 0) > 0)
    self.count:SetText(own and own.n > 1 and ("x" .. own.n .. ((own.h or 0) > 0 and " |cffff7ad9holo|r" or "")) or ((own and (own.h or 0) > 0) and "|cffff7ad9holo|r" or ""))
    if own and (own.u or 0) > 0 then   -- dropped in game, not synced yet
      self.count:SetText(self.count:GetText() .. (self.count:GetText() ~= "" and "  " or "") .. "|cffffd36a" .. (own.u > 1 and own.u .. " " or "") .. "unsealed|r")
    end
    self:Show()
  end
  return b
end

-- the big preview beside the window while you point at a card
local zoom
local function showZoom(owner, dbf)
  if not zoom then
    zoom = CreateFrame("Frame", nil, UIParent); zoom:SetSize(300, 412); zoom:SetFrameStrata("TOOLTIP")
    zoom.c = makeCard(zoom, 300, 412); zoom.c:SetPoint("CENTER"); zoom.c:EnableMouse(false)
    zoom.txt = zoom:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); zoom.txt:SetPoint("TOP", zoom, "BOTTOM", 0, -6); zoom.txt:SetWidth(300)
  end
  local own = store().cards and store().cards[dbf]
  zoom.c:set(dbf, own)
  local c = card(dbf)
  zoom.txt:SetText(c and (className(c[7]) .. "  -  " .. (RARITY[c[2]] or RARITY[1])[4] .. (own and ("  -  you own " .. own.n) or "")) or "")
  zoom:ClearAllPoints()
  local x = owner:GetCenter()
  if x and x > GetScreenWidth() / 2 then zoom:SetPoint("RIGHT", owner, "LEFT", -24, 0) else zoom:SetPoint("LEFT", owner, "RIGHT", 24, 0) end
  zoom:Show()
end
local function hideZoom() if zoom then zoom:Hide() end end
HatedTCGBinder_MakeCard = makeCard   -- the in-game drop reveal (HatedTCGDrops.lua) shows the card the same way

local function flat(fr, r, g, b, a, er, eg, eb, ea)
  fr:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  fr:SetBackdropColor(r, g, b, a); fr:SetBackdropBorderColor(er, eg, eb, ea)
end
local function smallButton(parent, text, w)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"); b:SetSize(w or 70, 20); b:SetText(text)
  if b:GetFontString() then b:GetFontString():SetFont(STANDARD_TEXT_FONT, 10) end
  return b
end

local W
local function build()
  if W then return W end
  local w = CreateFrame("Frame", "HatedTCGBinder", UIParent, "BackdropTemplate"); w:Hide()
  w:SetSize(880, 640); w:SetPoint("CENTER"); w:SetFrameStrata("HIGH"); w:SetToplevel(true)
  w:SetMovable(true); w:EnableMouse(true); w:RegisterForDrag("LeftButton"); w:SetClampedToScreen(true)
  w:SetScript("OnDragStart", w.StartMoving); w:SetScript("OnDragStop", w.StopMovingOrSizing)
  flat(w, 0.035, 0.055, 0.06, 0.97, 0.25, 0.95, 0.85, 0.7)
  tinsert(UISpecialFrames, "HatedTCGBinder")
  w:SetScript("OnHide", hideZoom)
  local close = CreateFrame("Button", nil, w, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 2, 2)
  local title = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOPLEFT", 16, -14); title:SetText("Hated TCG"); title:SetTextColor(0.75, 1, 0.96)
  w.tabBinder = smallButton(w, "Binder", 90); w.tabBinder:SetPoint("LEFT", title, "RIGHT", 16, 0)
  w.tabDecks = smallButton(w, "Decks", 90); w.tabDecks:SetPoint("LEFT", w.tabBinder, "RIGHT", 6, 0)
  local back = smallButton(w, "< Points", 80); back:SetPoint("TOPRIGHT", -30, -12)
  back:SetScript("OnClick", function() w:Hide(); if HatedTCG_Toggle then HatedTCG_Toggle(true) end end)
  w.empty = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); w.empty:SetPoint("CENTER"); w.empty:SetWidth(560)
  w.empty:SetText("No cards here yet.\n\nOpen packs on |cff5afff2hatedforever.com|r (Hated TCG > Card Shop), then click |cff5afff2Export Cards to WoW!|r (Points & Sync)\nand paste the code into |cff5afff2Import from website|r in the TCG window (/tcg).")

  -- ---------- binder page ----------
  local bp = CreateFrame("Frame", nil, w); bp:SetPoint("TOPLEFT", 0, -44); bp:SetPoint("BOTTOMRIGHT"); w.binder = bp
  bp.filters = {}
  local prev
  for i, cl in ipairs({ "ALL", unpack(CLASSES) }) do
    local f = smallButton(bp, cl == "ALL" and "All" or className(cl), cl == "ALL" and 40 or (#className(cl) > 7 and 78 or 62))
    if prev then f:SetPoint("LEFT", prev, "RIGHT", 2, 0) else f:SetPoint("TOPLEFT", 14, -4) end
    f:SetScript("OnClick", function() w.cls = cl; w.page = 1; w.refresh() end)
    f.cls = cl; bp.filters[i] = f; prev = f
  end
  bp.types = {}
  local tprev
  for i, ty in ipairs({ { "ALL", "All types" }, { "M", "Minions" }, { "S", "Spells" }, { "W", "Weapons" }, { "H", "Heroes" } }) do
    local f = smallButton(bp, ty[2], 78)
    if tprev then f:SetPoint("LEFT", tprev, "RIGHT", 2, 0) else f:SetPoint("TOPLEFT", 14, -26) end
    f:SetScript("OnClick", function() w.typ = ty[1]; w.page = 1; w.refresh() end)
    f.typ = ty[1]; bp.types[i] = f; tprev = f
  end
  bp.cards = {}
  for i = 1, PER_PAGE do
    local c = makeCard(bp, CW, CH)
    c:SetPoint("TOPLEFT", 40 + ((i - 1) % COLS) * (CW + 18), -62 - math.floor((i - 1) / COLS) * (CH + 26))
    c:SetScript("OnEnter", function(self) showZoom(self, self.dbf) end); c:SetScript("OnLeave", hideZoom)
    bp.cards[i] = c
  end
  bp.prevB = smallButton(bp, "< Prev", 70); bp.prevB:SetPoint("BOTTOMLEFT", 16, 14)
  bp.nextB = smallButton(bp, "Next >", 70); bp.nextB:SetPoint("BOTTOMRIGHT", -16, 14)
  bp.pageT = bp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); bp.pageT:SetPoint("BOTTOM", 0, 18)
  bp.prevB:SetScript("OnClick", function() w.page = math.max(1, (w.page or 1) - 1); w.refresh() end)
  bp.nextB:SetScript("OnClick", function() w.page = (w.page or 1) + 1; w.refresh() end)
  w:EnableMouseWheel(true)
  w:SetScript("OnMouseWheel", function(_, d) if w.view == "binder" then w.page = math.max(1, (w.page or 1) - d); w.refresh() end end)

  -- ---------- decks page ----------
  local dp = CreateFrame("Frame", nil, w); dp:SetPoint("TOPLEFT", 0, -44); dp:SetPoint("BOTTOMRIGHT"); w.decks = dp
  dp.list = {}
  for i = 1, 18 do
    local b = CreateFrame("Button", nil, dp, "BackdropTemplate"); b:SetSize(230, 28); b:SetPoint("TOPLEFT", 14, -4 - (i - 1) * 30)
    flat(b, 0, 0, 0, 0.45, 0.25, 0.95, 0.85, 0.25)
    b.t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); b.t:SetPoint("LEFT", 8, 0); b.t:SetWidth(150); b.t:SetJustifyH("LEFT")
    b.n = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); b.n:SetPoint("RIGHT", -8, 0)
    b:SetScript("OnClick", function(self) w.deck = self.i; w.refresh() end)
    dp.list[i] = b
  end
  dp.hero = makeCard(dp, 190, 261); dp.hero:SetPoint("TOPLEFT", 270, -6)
  dp.hero:SetScript("OnEnter", function(self) showZoom(self, self.dbf) end); dp.hero:SetScript("OnLeave", hideZoom)
  dp.name = dp:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); dp.name:SetPoint("TOP", dp.hero, "BOTTOM", 0, -10); dp.name:SetWidth(220)
  dp.info = dp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); dp.info:SetPoint("TOP", dp.name, "BOTTOM", 0, -4); dp.info:SetWidth(220)
  dp.rows = {}
  for i = 1, 30 do
    local r = CreateFrame("Button", nil, dp, "BackdropTemplate"); r:SetSize(170, 17)
    r:SetPoint("TOPLEFT", 490 + math.floor((i - 1) / 15) * 180, -6 - ((i - 1) % 15) * 19)
    flat(r, 0, 0, 0, 0.5, 0, 0, 0, 0)
    r.cost = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); r.cost:SetPoint("LEFT", 4, 0); r.cost:SetTextColor(0.55, 0.65, 1)
    r.t = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.t:SetPoint("LEFT", 24, 0); r.t:SetWidth(122); r.t:SetJustifyH("LEFT")
    r.x = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); r.x:SetPoint("RIGHT", -4, 0)
    r:SetScript("OnEnter", function(self) showZoom(self, self.dbf) end); r:SetScript("OnLeave", hideZoom)
    dp.rows[i] = r
  end
  dp.none = dp:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); dp.none:SetPoint("CENTER", 120, 0); dp.none:SetWidth(520)
  dp.none:SetText("No decks yet.\n\nBuild them on |cff5afff2hatedforever.com|r (Hated TCG > Decks), then export your cards to WoW again.")

  w.tabBinder:SetScript("OnClick", function() w.view = "binder"; w.refresh() end)
  w.tabDecks:SetScript("OnClick", function() w.view = "decks"; w.refresh() end)

  -- the holo foil drifts across holo cards
  local t = 0
  w:SetScript("OnUpdate", function(_, e)
    t = (t + e * 0.12) % 1
    for _, h in ipairs(holos) do if h:IsVisible() then h:SetTexCoord(t, t + 0.8, t * 0.5, t * 0.5 + 1.1) end end
  end)

  w.refresh = function()
    local s = store(); local own = s.cards or {}
    if s.pending and #s.pending > 0 then          -- card drops waiting for a sync count as owned, marked unsealed
      local merged = {}
      for k, v in pairs(own) do merged[k] = v end
      for _, p in ipairs(s.pending) do
        local o = merged[p.dbf]
        merged[p.dbf] = { n = (o and o.n or 0) + 1, h = o and o.h or 0, u = (o and o.u or 0) + 1 }
      end
      own = merged
    end
    w.view = w.view or "binder"
    w.tabBinder:SetEnabled(w.view ~= "binder"); w.tabDecks:SetEnabled(w.view ~= "decks")
    bp:SetShown(w.view == "binder"); dp:SetShown(w.view == "decks")
    local any = next(own) ~= nil
    w.empty:SetShown(not any and w.view == "binder")
    if w.view == "binder" then
      local list, total, have = {}, 0, 0
      for dbf, c in pairs(HatedTCG_CARDS or {}) do
        total = total + 1
        if own[dbf] then
          have = have + 1
          if (not w.cls or w.cls == "ALL" or c[7] == w.cls) and (not w.typ or w.typ == "ALL" or c[6] == w.typ) then list[#list + 1] = dbf end
        end
      end
      local order = {}; for i, cl in ipairs(CLASSES) do order[cl] = i end
      table.sort(list, function(a, b)
        local A, B = card(a), card(b)
        if A[2] ~= B[2] then return A[2] > B[2] end                              -- Legendary first, Common last
        if A[7] ~= B[7] then return (order[A[7]] or 99) < (order[B[7]] or 99) end
        if (A[3] or 0) ~= (B[3] or 0) then return (A[3] or 0) < (B[3] or 0) end
        return A[1] < B[1]
      end)
      local pages = math.max(1, math.ceil(#list / PER_PAGE))
      w.page = math.min(math.max(1, w.page or 1), pages)
      for i = 1, PER_PAGE do
        local dbf = list[(w.page - 1) * PER_PAGE + i]
        if dbf then bp.cards[i]:set(dbf, own[dbf]) else bp.cards[i]:Hide() end
      end
      for _, f in ipairs(bp.filters) do f:SetEnabled(f.cls ~= (w.cls or "ALL")) end
      for _, f in ipairs(bp.types) do f:SetEnabled(f.typ ~= (w.typ or "ALL")) end
      bp.pageT:SetText(string.format("Page %d / %d   -   %d / %d cards collected", w.page, pages, have, total))
      bp.prevB:SetEnabled(w.page > 1); bp.nextB:SetEnabled(w.page < pages)
      bp.pageT:SetShown(any); bp.prevB:SetShown(any); bp.nextB:SetShown(any)
    else
      local decks = s.decks or {}
      dp.none:SetShown(#decks == 0)
      w.deck = math.min(w.deck or 1, math.max(1, #decks))
      for i, b in ipairs(dp.list) do
        local d = decks[i]
        if d then
          b.i = i; b.t:SetText(d.name); b.n:SetText(#d.cards .. "/30")
          b:SetBackdropBorderColor(TEAL[1], TEAL[2], TEAL[3], i == w.deck and 0.9 or 0.25); b:Show()
        else b:Hide() end
      end
      local d = decks[w.deck]
      dp.hero:SetShown(d ~= nil); dp.name:SetShown(d ~= nil); dp.info:SetShown(d ~= nil)
      for _, r in ipairs(dp.rows) do r:Hide() end
      if d then
        dp.hero:set(d.hero, own[d.hero])
        local h = card(d.hero)
        dp.name:SetText(d.name)
        dp.info:SetText((h and className(h[7]) or "") .. "  -  " .. #d.cards .. " / 30 cards" .. (#d.cards == 30 and "  |cff5afff2ready|r" or ""))
        local n, rows = {}, {}
        for _, id in ipairs(d.cards) do if not n[id] then rows[#rows + 1] = id end; n[id] = (n[id] or 0) + 1 end
        table.sort(rows, function(a, b) local A, B = card(a), card(b); if not A or not B then return a < b end
          if (A[3] or 0) ~= (B[3] or 0) then return (A[3] or 0) < (B[3] or 0) end return A[1] < B[1] end)
        for i, id in ipairs(rows) do
          local r, c = dp.rows[i], card(id)
          if r and c then
            local col = RARITY[c[2]] or RARITY[1]
            r.dbf = id; r.cost:SetText(c[3] or 0); r.t:SetText(c[1]); r.t:SetTextColor(col[1], col[2], col[3]); r.x:SetText(n[id] > 1 and ("x" .. n[id]) or ""); r:Show()
          end
        end
      end
    end
  end
  W = w
  return w
end

function HatedTCGBinder_Toggle(view)
  local w = build()
  if view then w.view = view end
  if w:IsShown() and not view then w:Hide() else w.refresh(); w:Show() end
end

-- "HTCG3:<points>:<lifetime>:<last t>:<cards>:<decks>:<check>" from the website -> account + cards + decks (nil if it doesn't check out)
function HatedTCG_ReadCode(code)
  code = (code or ""):match("^%s*(.-)%s*$")                -- trim the ends only: deck names have spaces
  local body, h = code:match("^HTCG3:(.*):(%d+)$")
  if not body then return nil end
  local x = 7; for i = 1, #body do x = (x * 31 + body:byte(i)) % 1000003 end
  if x ~= tonumber(h) then return nil end
  local p, l, lt, cards, decks = body:match("^(%d+):(%d+):(%d+):([^:]*):(.*)$")
  if not p then return nil end
  local own = {}
  for e in cards:gmatch("[^,]+") do
    local id, rest = e:match("^(%w+)(.*)$")
    local n = tonumber(rest:match("%*(%w+)") or "1", 36) or 1
    local holo = tonumber(rest:match("!(%w+)") or "0", 36) or 0
    if id then own[tonumber(id, 36)] = { n = n, h = holo } end
  end
  local list = {}
  for d in decks:gmatch("[^;]+") do
    local name, hero, ids = d:match("^(.-)~(%w*)~(.*)$")
    if name then
      local cs = {}
      for id in ids:gmatch("[^.]+") do cs[#cs + 1] = tonumber(id, 36) end
      list[#list + 1] = { name = name, hero = tonumber(hero, 36), cards = cs }
    end
  end
  return { points = tonumber(p), lifetime = tonumber(l), lastT = tonumber(lt), at = time() }, own, list
end

SLASH_HATEDBINDER1 = "/binder"
SlashCmdList.HATEDBINDER = function() HatedTCGBinder_Toggle() end
