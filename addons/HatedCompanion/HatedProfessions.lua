--[[ Hated Companion: Guild Professions
  Who in the guild can craft what. Every character's recipes are read when its profession window opens, shared
  with guildmates who have the addon (hidden guild addon messages) and kept, so offline crafters show up too.
  Window: /prof, or the Guild Professions tile on the hub. Search a recipe, filter by profession, point at a row
  for its tooltip, Shift-click to link it in chat.

  Saved (HatedCompanionDB.prof):  chars[name] = { t = last change, mine = true/nil,
                                                  profs = { [profession] = { r = rank, m = max, ids = { "i123" / "e456", ... } } } }
  "i<item id>" = a recipe that makes an item; "e<spell id>" = an enchant (Enchanting has no item for most).

  Guild messages (prefix "HatedProf", fields split by "|"):
    Q                               someone just logged in: everyone answers with S lines for their own characters
    S|name|t                        "I have data for <name> as of t"
    W|name                          "send me <name>" (to the owner, via the guild channel; everyone gets the update)
    D|name|t|prof|rank|max|n|of|ids  part n of <of> of a character's recipes for one profession (ids comma separated, base 36)
]]

local PREFIX = "HatedProf"
local GOLD = { 1, 0.82, 0.4 }
local ROW_H = 22
local function say(m) DEFAULT_CHAT_FRAME:AddMessage("|cffffd36aHated Professions:|r " .. m) end

local function DB()
  HatedCompanionDB = HatedCompanionDB or {}
  HatedCompanionDB.prof = HatedCompanionDB.prof or { chars = {} }
  return HatedCompanionDB.prof
end
local function me() local n, r = UnitFullName("player"); return n end
local function short(name) return Ambiguate and Ambiguate(name, "short") or (name:match("^[^-]+") or name) end
local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
local function b36(n) n = math.floor(n); if n <= 0 then return "0" end local s = "" while n > 0 do local d = n % 36; s = B36:sub(d + 1, d + 1) .. s; n = math.floor(n / 36) end return s end

-- ---------- reading your own professions ----------
local function saveProf(prof, rank, max, ids)
  if not prof or prof == "" or prof == "UNKNOWN" or #ids == 0 then return end
  local name = me(); if not name then return end
  local c = DB().chars[name] or { profs = {} }
  c.mine = true; c.class = select(2, UnitClass("player"))
  local old = c.profs[prof]
  -- add to what we had (a filter in the profession window can hide recipes; you never forget one)
  local set, list = {}, {}
  for _, id in ipairs(old and old.ids or {}) do if not set[id] then set[id] = true; list[#list + 1] = id end end
  local changed = not old or old.r ~= rank
  for _, id in ipairs(ids) do if not set[id] then set[id] = true; list[#list + 1] = id; changed = true end end
  c.profs[prof] = { r = rank, m = max, ids = list }
  if changed then say(string.format("saved %d %s recipes for %s - shared with the guild.", #list, prof, name)) end
  if changed then c.t = time(); DB().chars[name] = c; if HatedProf_Share then HatedProf_Share(name) end end
  DB().chars[name] = c
end

-- newer clients: C_TradeSkillUI (recipe ids are spell ids; link the item made when there is one)
local function scanModern()
  local T = C_TradeSkillUI
  local info = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
  local prof, rank, max
  if info and info.professionName then prof, rank, max = info.professionName, info.skillLevel, info.maxSkillLevel
  elseif T.GetTradeSkillLine then local _, n, r, m = T.GetTradeSkillLine(); prof, rank, max = n, r, m end
  if T.IsTradeSkillLinked and T.IsTradeSkillLinked() then return end          -- someone else's linked profession
  if T.IsTradeSkillGuild and T.IsTradeSkillGuild() then return end
  local ids = {}
  for _, rid in ipairs(T.GetAllRecipeIDs() or {}) do
    local r = T.GetRecipeInfo(rid)
    if r and r.learned and r.type ~= "header" then
      local link = T.GetRecipeItemLink and T.GetRecipeItemLink(rid)
      local item = link and link:match("item:(%d+)")
      ids[#ids + 1] = item and ("i" .. item) or ("e" .. rid)
    end
  end
  saveProf(prof, rank or 0, max or 0, ids)
end

local function scanTradeSkill()
  if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then return scanModern() end
  if not GetTradeSkillLine or not GetNumTradeSkills then return end
  local prof, rank, max = GetTradeSkillLine()
  -- expand collapsed headers so every recipe is listed
  if ExpandTradeSkillSubClass then pcall(ExpandTradeSkillSubClass, 0) end
  local ids = {}
  for i = 1, GetNumTradeSkills() do
    local _, kind = GetTradeSkillInfo(i)
    if kind ~= "header" and kind ~= "subheader" then
      local link = GetTradeSkillItemLink(i)
      local item = link and link:match("item:(%d+)")
      local ench = link and link:match("enchant:(%d+)")
      if item then ids[#ids + 1] = "i" .. item elseif ench then ids[#ids + 1] = "e" .. ench end
    end
  end
  saveProf(prof, rank, max, ids)
end

local function scanCraft()                     -- Enchanting (and Beast Training, which we skip) in Classic
  if not GetCraftDisplaySkillLine or not GetNumCrafts then return end
  local prof, rank, max = GetCraftDisplaySkillLine()
  if not prof then return end
  if ExpandCraftSkillLine then pcall(ExpandCraftSkillLine, 0) end
  local ids = {}
  for i = 1, GetNumCrafts() do
    local _, _, kind = GetCraftInfo(i)
    if kind ~= "header" then
      local link = GetCraftItemLink(i)
      local ench = link and link:match("enchant:(%d+)")
      local item = link and link:match("item:(%d+)")
      if ench then ids[#ids + 1] = "e" .. ench elseif item then ids[#ids + 1] = "i" .. item end
    end
  end
  saveProf(prof, rank, max, ids)
end

-- ---------- sharing with the guild ----------
local queue, sending = {}, false
local function send(msg)
  if not IsInGuild() then return end
  queue[#queue + 1] = msg
  if sending then return end
  sending = true
  local tick
  tick = C_Timer.NewTicker(0.3, function()              -- gently, so the guild channel never throttles us
    local m = table.remove(queue, 1)
    if not m then sending = false; tick:Cancel(); return end
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then C_ChatInfo.SendAddonMessage(PREFIX, m, "GUILD") else SendAddonMessage(PREFIX, m, "GUILD") end
  end)
end

-- send one character's recipes (every profession), split to fit the 255-character message limit
function HatedProf_Share(name)
  local c = DB().chars[name]; if not c or not c.profs then return end
  for prof, p in pairs(c.profs) do
    local parts, cur = {}, {}
    local len = 0
    for _, id in ipairs(p.ids) do
      local tok = id:sub(1, 1) .. b36(tonumber(id:sub(2)) or 0)
      if len + #tok + 1 > 170 then parts[#parts + 1] = table.concat(cur, ","); cur, len = {}, 0 end
      cur[#cur + 1] = tok; len = len + #tok + 1
    end
    if #cur > 0 then parts[#parts + 1] = table.concat(cur, ",") end
    for i, chunk in ipairs(parts) do
      send(table.concat({ "D", name, c.t or 0, prof, p.r or 0, p.m or 0, i, #parts, chunk }, "|"))
    end
  end
end

local pending = {}
local function onMessage(msg, sender)
  local parts = { strsplit("|", msg) }
  local kind = parts[1]
  local db = DB()
  if kind == "Q" then
    -- answer with what we have of our own characters, a little later and at a random moment (not all at once)
    C_Timer.After(2 + math.random() * 8, function()
      for name, c in pairs(db.chars) do if c.mine and c.t then send("S|" .. name .. "|" .. c.t) end end
    end)
  elseif kind == "S" then
    local name, t = parts[2], tonumber(parts[3]) or 0
    local have = db.chars[name]
    if not (have and have.mine) and (not have or (have.t or 0) < t) then send("W|" .. name) end
  elseif kind == "W" then
    local c = db.chars[parts[2]]
    if c and c.mine then
      c.askedAt = c.askedAt or 0
      if time() - c.askedAt > 20 then c.askedAt = time(); HatedProf_Share(parts[2]) end   -- one send covers everyone who asked
    end
  elseif kind == "D" then
    local name, t, prof, r, m, n, of, ids = parts[2], tonumber(parts[3]) or 0, parts[4], tonumber(parts[5]), tonumber(parts[6]), tonumber(parts[7]), tonumber(parts[8]), parts[9] or ""
    local have = db.chars[name]
    if have and have.mine then return end                               -- we know our own characters best
    if have and (have.t or 0) > t then return end
    local key = name .. "|" .. t .. "|" .. prof
    local p = pending[key] or { got = 0, ids = {} }
    for tok in ids:gmatch("[^,]+") do p.ids[#p.ids + 1] = tok:sub(1, 1) .. (tonumber(tok:sub(2), 36) or 0) end
    p.got = p.got + 1; pending[key] = p
    if p.got >= of then
      pending[key] = nil
      local c = db.chars[name] or { profs = {} }
      if (c.t or 0) < t then c.t = t end
      c.from = sender
      c.profs[prof] = { r = r, m = m, ids = p.ids }
      db.chars[name] = c
      if HatedProfFrame and HatedProfFrame:IsShown() then HatedProfFrame.dirty = true end
    end
  end
end

local ev = CreateFrame("Frame")
-- WoW versions name these differently: register every one this client knows, quietly skip the rest
for _, name in ipairs({ "PLAYER_LOGIN", "CHAT_MSG_ADDON", "GET_ITEM_INFO_RECEIVED",
    "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "CRAFT_SHOW", "CRAFT_UPDATE" }) do
  pcall(ev.RegisterEvent, ev, name)
end
local scanTimer
ev:SetScript("OnEvent", function(_, e, a1, a2, a3, a4)
  if e == "PLAYER_LOGIN" then
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) elseif RegisterAddonMessagePrefix then RegisterAddonMessagePrefix(PREFIX) end
    C_Timer.After(25, function()                                        -- after login settles: say hello, offer ours
      send("Q")
      for name, c in pairs(DB().chars) do if c.mine and c.t then send("S|" .. name .. "|" .. c.t) end end
    end)
  elseif e == "CHAT_MSG_ADDON" then
    if a1 == PREFIX and a3 == "GUILD" then
      local from = short(a4 or "")
      if from ~= me() then onMessage(a2, from) end
    end
  elseif e == "TRADE_SKILL_SHOW" or e == "TRADE_SKILL_UPDATE" or e == "TRADE_SKILL_LIST_UPDATE" or e == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
    if scanTimer then scanTimer:Cancel() end
    scanTimer = C_Timer.NewTimer(0.6, function() local ok, err = pcall(scanTradeSkill); if not ok then say("couldn't read this profession: " .. tostring(err)) end end)
  elseif e == "CRAFT_SHOW" or e == "CRAFT_UPDATE" then
    if scanTimer then scanTimer:Cancel() end
    scanTimer = C_Timer.NewTimer(0.6, function() local ok, err = pcall(scanCraft); if not ok then say("couldn't read this profession: " .. tostring(err)) end end)
  elseif e == "GET_ITEM_INFO_RECEIVED" then
    if HatedProfFrame and HatedProfFrame:IsShown() then HatedProfFrame.dirty = true end
  end
end)

-- ---------- the window ----------
-- newer clients moved these into C_Item / C_Spell
local ItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local function SpellLink(id) local f = (C_Spell and C_Spell.GetSpellLink) or GetSpellLink; return f and f(id) end
local function recipeInfo(id)                -- name, icon, colour, link
  local kind, n = id:sub(1, 1), tonumber(id:sub(2))
  if kind == "i" then
    local name, link, q, _, _, _, _, _, _, icon = ItemInfo(n)
    if not name then return nil end
    local r, g, b = 1, 1, 1
    if q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then r, g, b = ITEM_QUALITY_COLORS[q].r, ITEM_QUALITY_COLORS[q].g, ITEM_QUALITY_COLORS[q].b end
    return name, icon, r, g, b, link, "item:" .. n
  else
    local name, _, icon
    if C_Spell and C_Spell.GetSpellInfo then local s = C_Spell.GetSpellInfo(n); if s then name, icon = s.name, s.iconID end
    else name, _, icon = GetSpellInfo(n) end
    if not name then return nil end
    return name, icon, 0.75, 0.9, 1, SpellLink(n) or name, "enchant:" .. n
  end
end

local function onlineSet()
  local on = {}
  if not IsInGuild() then return on end
  for i = 1, GetNumGuildMembers() do
    local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
    if name and online then on[short(name)] = true end
  end
  return on
end

local function flat(fr, r, g, b, a, er, eg, eb, ea)
  fr:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  fr:SetBackdropColor(r, g, b, a); fr:SetBackdropBorderColor(er, eg, eb, ea)
end
local function button(parent, text, w)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"); b:SetSize(w or 80, 20); b:SetText(text)
  if b:GetFontString() then b:GetFontString():SetFont(STANDARD_TEXT_FONT, 10) end
  return b
end

local W
local function build()
  if W then return W end
  local w = CreateFrame("Frame", "HatedProfFrame", UIParent, "BackdropTemplate"); w:Hide()
  w:SetSize(780, 540); w:SetPoint("CENTER"); w:SetFrameStrata("HIGH"); w:SetToplevel(true)
  w:SetMovable(true); w:EnableMouse(true); w:RegisterForDrag("LeftButton"); w:SetClampedToScreen(true)
  w:SetScript("OnDragStart", w.StartMoving); w:SetScript("OnDragStop", w.StopMovingOrSizing)
  flat(w, 0.06, 0.045, 0.03, 0.97, 0.75, 0.6, 0.3, 0.9)
  tinsert(UISpecialFrames, "HatedProfFrame")
  local close = CreateFrame("Button", nil, w, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 2, 2)
  local title = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOPLEFT", 16, -14)
  title:SetText("Guild Professions"); title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
  local back = button(w, "< Hub", 64); back:SetPoint("TOPRIGHT", -30, -12)
  back:SetScript("OnClick", function() w:Hide(); if HatedHub_Toggle then HatedHub_Toggle() end end)


  local sl = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); sl:SetPoint("TOPLEFT", 18, -48); sl:SetText("Search")
  local search = CreateFrame("EditBox", nil, w, "InputBoxTemplate"); search:SetSize(300, 22); search:SetPoint("TOPLEFT", 22, -62); search:SetAutoFocus(false)
  search:SetScript("OnTextChanged", function() w.offset = 0; w.refresh() end)
  search:SetScript("OnEscapePressed", search.ClearFocus); w.search = search

  -- profession filter: one button per profession anyone has
  w.profBtns = {}
  local pl = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); pl:SetPoint("TOPLEFT", 340, -48); pl:SetText("Profession")
  w.profRow = CreateFrame("Frame", nil, w); w.profRow:SetPoint("TOPLEFT", 336, -60); w.profRow:SetSize(420, 46)

  local h1 = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); h1:SetPoint("TOPLEFT", 18, -112); h1:SetText("Recipe"); h1:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
  local h2 = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); h2:SetPoint("TOPLEFT", 300, -112); h2:SetText("Can craft it"); h2:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

  -- rows: as many as fit; made on demand when the window is resized bigger
  w.rows = {}
  local function makeRow(i)
    local r = CreateFrame("Button", nil, w); r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 14, -128 - (i - 1) * ROW_H); r:SetPoint("RIGHT", w, "RIGHT", -16, 0)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0)
    local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.1)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(18, 18); r.icon:SetPoint("LEFT", 4, 0)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.name:SetPoint("LEFT", 28, 0); r.name:SetWidth(255); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
    r.who = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.who:SetPoint("LEFT", 286, 0); r.who:SetPoint("RIGHT", -6, 0); r.who:SetJustifyH("LEFT"); r.who:SetWordWrap(false)
    r:RegisterForClicks("AnyUp")
    r:SetScript("OnEnter", function(self)
      if not self.hyper then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); pcall(GameTooltip.SetHyperlink, GameTooltip, self.hyper)
      if self.all then GameTooltip:AddLine(" "); GameTooltip:AddLine("Can craft it: " .. self.all, 1, 0.82, 0.4, true) end
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", GameTooltip_Hide)
    r:SetScript("OnClick", function(self) if IsShiftKeyDown() and self.link and ChatEdit_InsertLink then ChatEdit_InsertLink(self.link) end end)
    return r
  end
  w.fit = function()                                   -- how many rows fit between the headers and the footer
    w.visible = math.max(3, math.floor((w:GetHeight() - 128 - 50) / ROW_H))
    for i = #w.rows + 1, w.visible do w.rows[i] = makeRow(i) end
    for i, r in ipairs(w.rows) do if i > w.visible then r:Hide() end end
  end
  -- footer: two lines under the list (the count, then the help)
  w.count = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); w.count:SetPoint("BOTTOMLEFT", 18, 28); w.count:SetPoint("RIGHT", w, "RIGHT", -30, 0); w.count:SetJustifyH("LEFT")
  local help = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); help:SetPoint("BOTTOMLEFT", 18, 12); help:SetPoint("RIGHT", w, "RIGHT", -30, 0); help:SetJustifyH("LEFT")
  help:SetText("Mouse wheel: scroll   -   Shift+click: link in chat   -   Open your profession windows to share your recipes   -   Drag the corner to resize")
  -- resizable from the bottom-right corner
  w:SetResizable(true)
  if w.SetResizeBounds then w:SetResizeBounds(620, 380, 1600, 1200) elseif w.SetMinResize then w:SetMinResize(620, 380) end
  local grip = CreateFrame("Button", nil, w); grip:SetSize(16, 16); grip:SetPoint("BOTTOMRIGHT", -4, 4)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"); grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight"); grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function() w:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function() w:StopMovingOrSizing(); w.fit(); w.refresh() end)
  w:SetScript("OnSizeChanged", function() if w.refresh then w.fit(); w.refresh() end end)
  w:EnableMouseWheel(true)
  w:SetScript("OnMouseWheel", function(_, d) w.offset = math.max(0, (w.offset or 0) - d * 3); w.refresh() end)
  w:SetScript("OnShow", function() if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() elseif GuildRoster then GuildRoster() end end)
  local acc = 0
  w:SetScript("OnUpdate", function(_, e) acc = acc + e; if acc > 1 and w.dirty then acc = 0; w.dirty = false; w.refresh() end end)

  w.refresh = function()
    local db = DB(); local on = onlineSet(); local myName = me()
    -- recipes -> who can make them
    local byId, profs = {}, {}
    for name, c in pairs(db.chars) do
      do
        for prof, p in pairs(c.profs or {}) do
          profs[prof] = true
          if not w.prof or w.prof == prof then
            for _, id in ipairs(p.ids) do
              local e = byId[id]; if not e then e = { id = id, who = {} }; byId[id] = e end
              e.who[#e.who + 1] = name
            end
          end
        end
      end
    end
    -- profession buttons
    local names = {}; for p in pairs(profs) do names[#names + 1] = p end; table.sort(names); table.insert(names, 1, "All")
    for i, p in ipairs(names) do
      local b = w.profBtns[i]
      if not b then b = button(w.profRow, p, 102); w.profBtns[i] = b; b:SetPoint("TOPLEFT", ((i - 1) % 4) * 104, -math.floor((i - 1) / 4) * 22) end
      b:SetText(p); b.p = p; b:Show()
      b:SetScript("OnClick", function(self) w.prof = self.p ~= "All" and self.p or nil; w.offset = 0; w.refresh() end)
      b:SetEnabled((w.prof or "All") ~= p)
    end
    for i = #names + 1, #w.profBtns do w.profBtns[i]:Hide() end
    -- search + sort by name
    local q = (w.search:GetText() or ""):lower()
    local list, waiting = {}, 0
    for id, e in pairs(byId) do
      local name, icon, r, g, b, link, hyper = recipeInfo(id)
      if not name then waiting = waiting + 1; name = "..." end
      if q == "" or name:lower():find(q, 1, true) then
        e.name, e.icon, e.r, e.g, e.b, e.link, e.hyper = name, icon, r or 1, g or 1, b or 1, link, hyper
        list[#list + 1] = e
      end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    w.offset = math.min(w.offset or 0, math.max(0, #list - w.visible))
    for i, row in ipairs(w.rows) do
      local e = i <= w.visible and list[w.offset + i]
      if e then
        row.icon:SetTexture(e.icon or 134400); row.name:SetText(e.name); row.name:SetTextColor(e.r, e.g, e.b)
        table.sort(e.who, function(a, b) local ao, bo = on[a] or a == myName, on[b] or b == myName; if ao ~= bo then return ao end return a < b end)
        local shown = {}
        for _, n in ipairs(e.who) do
          shown[#shown + 1] = (n == myName and "|cff40ff40You|r") or (on[n] and ("|cffffffff" .. n .. "|r")) or ("|cff8a8a8a" .. n .. "|r")
        end
        row.who:SetText(table.concat(shown, ", ")); row.all = table.concat(e.who, ", ")
        row.link, row.hyper = e.link, e.hyper; row:Show()
      else row:Hide() end
    end
    local chars = 0; for _ in pairs(db.chars) do chars = chars + 1 end
    w.count:SetText(#list == 0 and "No recipes yet. Open your profession windows to add yours; guildmates with the addon share theirs when they log in."
      or string.format("%d recipes  -  %d characters  -  online in white%s", #list, chars, waiting > 0 and "  -  loading item names..." or ""))
    if waiting > 0 then w.dirty = true end
  end
  w.fit()
  W = w
  return w
end

function HatedProf_Toggle()
  local w = build()
  if w:IsShown() then w:Hide() else w.offset = 0; w.refresh(); w:Show() end
end
-- for the hub tile: (characters with recipes, recipes known across the guild)
function HatedProf_Summary()
  local chars, ids = 0, {}
  for _, c in pairs(DB().chars) do chars = chars + 1; for _, p in pairs(c.profs or {}) do for _, id in ipairs(p.ids) do ids[id] = true end end end
  local n = 0; for _ in pairs(ids) do n = n + 1 end
  return chars, n
end

SLASH_HATEDPROF1 = "/prof"
SLASH_HATEDPROF2 = "/professions"
SlashCmdList.HATEDPROF = function() HatedProf_Toggle() end
