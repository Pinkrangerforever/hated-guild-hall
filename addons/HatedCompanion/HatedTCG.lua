--[[ Hated Companion: TCG points
  Kills earn points toward Hated TCG card packs. The addon only LOGS kills (with the proof the game gives: the
  creature's unique spawn id, its creature id, the zone, levels, the time); the website checks the log when you
  sync and credits the real points to your account. Points are account-wide: every character adds to the same pool.

  Values (the website has the final say):
    a creature type killed for the first time on this account     10
    after that: normal 1, elite 3 (grey mobs give nothing), no daily limit
    dungeon boss 10, a dungeon's last boss 20
    raid boss 100 the first time, 20 after that

  Kills you or your group damaged count for everyone in the group. The log keeps 30 days; sync on the website
  (Profile > Hated TCG) at least once a month. /reload or log out first so WoW writes the file.

  /tcg   the Hated TCG window: your points (paste the code from the website to show your account total)
]]

local KEEP_DAYS = 30
local MAX_LOG = 60000          -- lines kept at most (the oldest go first)
local TEAL = { 0.35, 1, 0.95 }    -- bright teal

local function say(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff5afff2Hated TCG:|r " .. msg) end
local function dbg(msg) if HatedCompanionDB and HatedCompanionDB.tcgDebug then DEFAULT_CHAT_FRAME:AddMessage("|cff7fb5adTCG debug:|r " .. msg) end end

-- ---------- the log (account-wide, sealed) ----------
-- Each entry is one line of text. A running checksum ("seal") is kept with it; if the file is edited by hand the
-- seal no longer matches, the log is marked as tampered, and the website holds that sync for an officer.
local function fnv(h, s)
  for i = 1, #s do
    h = bit.bxor(h, s:byte(i))
    h = (h * 16777619) % 4294967296
  end
  return h
end
local function db()
  HatedCompanionDB = HatedCompanionDB or {}
  local t = HatedCompanionDB.tcg
  if not t then
    t = { v = 1, log = {}, firsts = {}, salt = tostring(math.random(100000000, 999999999)) .. tostring(time()) }
    t.seal = fnv(2166136261, t.salt)
    HatedCompanionDB.tcg = t
  end
  return t
end
local function reseal(t)
  local h = fnv(2166136261, t.salt)
  for _, e in ipairs(t.log) do h = fnv(h, e) end
  return h
end
local TCGUI   -- the window (below), refreshed when points come in
local function append(entry)
  local t = db()
  t.log[#t.log + 1] = entry
  t.seal = fnv(t.seal, entry)
  if TCGUI and TCGUI:IsShown() then TCGUI.refresh() end
end

-- ---------- what we know about creatures (from nameplates, target, mouseover) ----------
local info, plateOf, hit = {}, {}, {}
local function npcId(guid)
  local kind, _, _, _, _, id = strsplit("-", guid or "")
  if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
  return tonumber(id)
end
local function learn(unit)
  local guid = UnitGUID(unit)
  if not guid or not npcId(guid) then return end
  info[guid] = { lvl = UnitLevel(unit), cls = UnitClassification(unit), ctype = UnitCreatureType(unit), name = UnitName(unit) }
end

-- grey (no reward) level, the classic formula
local function greyLevel(p)
  if p <= 5 then return 0 elseif p <= 39 then return p - 5 - math.floor(p / 10) elseif p <= 59 then return p - 1 - math.floor(p / 5) else return p - 9 end
end

-- ---------- the popup: teal "+10" rising from the mob ----------
local pool = {}
local popupRaw
local function popup(amount, guid)
  local ok, err = pcall(popupRaw, amount, guid)
  if not ok then dbg("popup failed: " .. tostring(err)) end
end
popupRaw = function(amount, guid)
  local f
  for _, x in ipairs(pool) do if not x:IsShown() then f = x; break end end
  if not f then
    f = CreateFrame("Frame", nil, UIParent); f:SetSize(160, 40); f:SetFrameStrata("HIGH")
    f.text = f:CreateFontString(nil, "OVERLAY"); f.text:SetFont(STANDARD_TEXT_FONT, 26, "OUTLINE"); f.text:SetPoint("CENTER")
    f.text:SetTextColor(TEAL[1], TEAL[2], TEAL[3]); f.text:SetShadowOffset(2, -2)
    local ag = f:CreateAnimationGroup()
    local up = ag:CreateAnimation("Translation"); up:SetOffset(0, 70); up:SetDuration(1.6); up:SetSmoothing("OUT")
    local fade = ag:CreateAnimation("Alpha"); fade:SetFromAlpha(1); fade:SetToAlpha(0); fade:SetStartDelay(0.9); fade:SetDuration(0.7)
    local pop = ag:CreateAnimation("Scale"); pop:SetScaleFrom(0.6, 0.6); pop:SetScaleTo(1, 1); pop:SetDuration(0.18)
    ag:SetScript("OnFinished", function() f:Hide() end)
    f.ag = ag
    pool[#pool + 1] = f
  end
  f.text:SetText("+" .. amount .. " TCG")
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "CENTER", math.random(-60, 60), 120 + math.random(0, 40))
  f:Show(); f.ag:Stop(); f.ag:Play()
end

-- ---------- earning ----------
-- the addon's own estimate rides along at the end of each line (the website works the real value out itself)
-- ---------- "never killed" marker: a teal dot on the nameplate and in the tooltip ----------
local DOT_TEX = "Interface\\AddOns\\HatedCompanion\\Media\\Dot"   -- a small teal gem (colours baked in)
local DOT = "|T" .. DOT_TEX .. ":14:14|t"
local function isNew(unit)
  if not unit or not UnitExists(unit) or UnitIsPlayer(unit) or not UnitCanAttack("player", unit) then return false end
  local id = npcId(UnitGUID(unit)); if not id then return false end
  local ctype = UnitCreatureType(unit)
  if ctype == "Critter" or ctype == "Non-combat Pet" or ctype == "Totem" then return false end
  local lvl = UnitLevel(unit)
  if lvl and lvl > 0 and lvl <= greyLevel(UnitLevel("player")) then return false end
  return not db().firsts["n:" .. id]
end
local dots, dotFor = {}, {}           -- our dot frames; unit token -> dot
-- Nameplates are restricted: an addon may not measure them or draw onto Blizzard's frame. So, like quest-helper
-- addons do, each dot is our own little frame made a child of the nameplate and anchored to it; WoW positions it.
local function freeDot() for _, d in ipairs(dots) do if not d.unit then return d end end
  local d = CreateFrame("Frame", nil, UIParent); d:SetSize(13, 13)
  d.tex = d:CreateTexture(nil, "OVERLAY"); d.tex:SetAllPoints(); d.tex:SetTexture(DOT_TEX)
  dots[#dots + 1] = d; return d end
local function releaseDot(unit)
  local d = dotFor[unit]; if not d then return end
  d.unit = nil; d:Hide(); d:ClearAllPoints(); d:SetParent(UIParent); dotFor[unit] = nil
end
local function markPlate(unit)
  local new = isNew(unit)
  dbg("nameplate " .. tostring(unit) .. " (" .. tostring(UnitName(unit)) .. "): " .. (new and "never killed - dot" or "no dot"))
  if not new then releaseDot(unit); return end
  local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
  if not plate or (plate.IsForbidden and plate:IsForbidden()) then dbg("no usable nameplate for " .. unit); return end
  local d = dotFor[unit] or freeDot()
  d.unit = unit; dotFor[unit] = d
  local ok, err = pcall(function()
    d:SetParent(plate); d:SetFrameLevel(plate:GetFrameLevel() + 20)
    d:ClearAllPoints()
    local name = plate.UnitFrame and plate.UnitFrame.name
    if name then d:SetPoint("RIGHT", name, "LEFT", -3, 0) else d:SetPoint("BOTTOM", plate, "TOP", 0, -4) end
    d:Show()
  end)
  if not ok then dbg("couldn't attach the dot: " .. tostring(err)); releaseDot(unit) end
end
local function unmarkPlate(unit) releaseDot(unit) end
local function refreshPlates() for unit in pairs(dotFor) do markPlate(unit) end end
local function tooltipUnit(tip)
  local _, unit = tip:GetUnit()
  if unit and isNew(unit) then tip:AddLine(DOT .. " |cff5afff2Never killed on your account: +10 TCG|r") ; tip:Show() end
end
if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tip) if tip == GameTooltip then tooltipUnit(tip) end end)
else
  GameTooltip:HookScript("OnTooltipSetUnit", tooltipUnit)
end

local function award(key, first, amount, guid)
  if first then db().firsts[key] = true; C_Timer.After(0.1, refreshPlates) end
  if amount > 0 then popup(amount, guid) end
end

local lastEncounter = { t = 0, name = nil }
local function mobKilled(guid)
  local id = npcId(guid); if not id then return end
  local i = info[guid] or {}
  if i.ctype == "Critter" or i.ctype == "Non-combat Pet" or i.ctype == "Totem" then dbg("skipped: " .. tostring(i.ctype)); return end
  local plvl = UnitLevel("player")
  if i.lvl and i.lvl > 0 and i.lvl <= greyLevel(plvl) then dbg("skipped: grey (level " .. i.lvl .. ")"); return end
  -- a boss's death is credited by the encounter itself, not as a normal mob
  if GetTime() - lastEncounter.t < 4 and i.name and i.name == lastEncounter.name then dbg("skipped: boss (encounter credit)"); return end
  local cls = i.cls or "?"
  local _, _, _, _, _, _, _, instId = GetInstanceInfo()
  local zone = (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")) or 0
  local key = "n:" .. id
  local first = not db().firsts[key]
  local elite = cls == "elite" or cls == "rareelite" or cls == "worldboss"
  local amount = first and 10 or (elite and 3 or 1)
  append(table.concat({ "m", time(), UnitName("player"), plvl, id, guid, instId or 0, zone, i.lvl or 0, cls, amount, ((i.name or ""):gsub(",", "")) }, ","))
  dbg(string.format("logged %s (npc %d) for %d points; log has %d lines", tostring(i.name), id, amount, #db().log))
  award(key, first, amount, guid)
end

local function bossKilled(encounterID, name, difficultyID, groupSize)
  local _, instType, _, _, _, _, _, instId = GetInstanceInfo()
  local kind = instType == "raid" and "r" or "d"
  local key = "e:" .. encounterID
  local first = not db().firsts[key]
  local amount = kind == "r" and (first and 100 or 20) or 10
  append(table.concat({ "b", time(), UnitName("player"), UnitLevel("player"), encounterID, kind, instId or 0, difficultyID or 0, groupSize or 0, GetNumGroupMembers(), amount, ((name or ""):gsub(",", "")) }, ","))
  award(key, first, amount, nil)
end

-- ---------- events ----------
-- This client doesn't let addons read the combat log, so kills are spotted the way WoW awards credit: a mob we saw
-- alive (on a nameplate or as the target) dies while our group holds its tag (UnitIsTapDenied is false).
local seenAlive, counted = {}, {}
local lastCombat = 0
local function watch(unit)
  local guid = UnitGUID(unit)
  if not guid or not npcId(guid) or counted[guid] then return end
  if not UnitIsDead(unit) then
    if not seenAlive[guid] then seenAlive[guid] = GetTime(); learn(unit) end
    return
  end
  if not seenAlive[guid] then return end                         -- an old corpse we never saw alive
  counted[guid] = true
  if UnitIsTapDenied(unit) then dbg("a mob died that another player tagged: " .. tostring(UnitName(unit))); return end
  if not UnitAffectingCombat("player") and GetTime() - lastCombat > 8 and not IsInGroup() then
    dbg("a mob died while you weren't fighting: " .. tostring(UnitName(unit))); return
  end
  learn(unit)
  local wait = IsInInstance() and 1.5 or 0      -- in an instance it might be a boss: give the encounter credit a moment
  dbg("mob died: " .. tostring(UnitName(unit)) .. (wait > 0 and " (checking for a boss first)" or ""))
  if wait > 0 then C_Timer.After(wait, function() mobKilled(guid); info[guid] = nil end) else mobKilled(guid); info[guid] = nil end
end
local WATCHED = { target = true, focus = true, mouseover = true }
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
f:RegisterEvent("UNIT_HEALTH")
f:RegisterEvent("UNIT_FLAGS")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(f.RegisterEvent, f, "ENCOUNTER_END")
f:SetScript("OnEvent", function(_, event, a1, a2, a3, a4, a5)
  if event == "UNIT_HEALTH" or event == "UNIT_FLAGS" then
    if a1 and (WATCHED[a1] or a1:find("^nameplate")) then watch(a1) end
  elseif event == "PLAYER_REGEN_ENABLED" then lastCombat = GetTime()
  elseif event == "NAME_PLATE_UNIT_ADDED" then
    local g = UnitGUID(a1); if g then plateOf[g] = a1; learn(a1) end
    watch(a1); markPlate(a1)
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    unmarkPlate(a1)
    local g = UnitGUID(a1); if g and plateOf[g] == a1 then C_Timer.After(2, function() if plateOf[g] == a1 then plateOf[g] = nil end end) end
  elseif event == "PLAYER_TARGET_CHANGED" then learn("target"); watch("target")
  elseif event == "UPDATE_MOUSEOVER_UNIT" then learn("mouseover"); watch("mouseover")
  elseif event == "ENCOUNTER_END" then
    local encounterID, name, difficultyID, groupSize, success = a1, a2, a3, a4, a5
    if success == 1 then lastEncounter = { t = GetTime(), name = name }; bossKilled(encounterID, name, difficultyID, groupSize) end
  elseif event == "PLAYER_LOGIN" then
    local t = db()
    -- check the seal, then drop entries older than the website accepts
    if reseal(t) ~= t.seal then
      t.tampered = true
      say("|cffff5a4ayour TCG log was edited outside the game.|r Points in it will be held for an officer to review when you sync.")
    end
    local cutoff, keep = time() - KEEP_DAYS * 86400, {}
    for _, e in ipairs(t.log) do local ts = tonumber(e:match("^%a,(%d+),")); if ts and ts >= cutoff then keep[#keep + 1] = e end end
    while #keep > MAX_LOG do table.remove(keep, 1) end
    if #keep ~= #t.log then
      local wasOk = not t.tampered
      t.log = keep; t.seal = reseal(t)
      if not wasOk then t.tampered = true end
    end
    -- forget mobs we stopped seeing a while ago
    C_Timer.NewTicker(120, function() local now = GetTime(); for g, ts in pairs(seenAlive) do if now - ts > 900 then seenAlive[g] = nil; counted[g] = nil; info[g] = nil end end end)
  end
end)

-- ---------- the Hated TCG window ----------
-- The website is the bank: it shows a code after each sync ("HTCG:points:lifetime:last kill time:check"). Pasted
-- here, the window shows the account total plus whatever has been earned in game since that sync.
local function entryOf(e)
  local f = { strsplit(",", e) }
  if f[1] == "m" then return { boss = false, t = tonumber(f[2]), char = f[3], amount = tonumber(f[11]) or 0, name = (f[12] and f[12] ~= "") and f[12] or ("Creature " .. (f[5] or "?")) }
  elseif f[1] == "b" then return { boss = true, raid = f[6] == "r", t = tonumber(f[2]), char = f[3], amount = tonumber(f[11]) or 0, name = (f[12] and f[12] ~= "") and f[12] or "Boss" } end
end
local function sinceSync()
  local t = db(); local last = (t.server and t.server.lastT) or 0; local sum, n = 0, 0
  for _, e in ipairs(t.log) do local ts = tonumber(e:match("^%a,(%d+),")); if ts and ts > last then sum = sum + (tonumber(e:match(",(%d+),[^,]*$")) or 0); n = n + 1 end end
  return sum, n
end
local function checkCode(code)
  local p, l, lt, h = (code or ""):match("HTCG:(%d+):(%d+):(%d+):(%d+)")
  if not p then return nil end
  local body, x = p .. ":" .. l .. ":" .. lt, 7
  for i = 1, #body do x = (x * 31 + body:byte(i)) % 1000003 end
  if x ~= tonumber(h) then return nil end
  return { points = tonumber(p), lifetime = tonumber(l), lastT = tonumber(lt), at = time() }
end

local function flat(fr, r, g, b, a, er, eg, eb, ea)
  fr:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  fr:SetBackdropColor(r, g, b, a); fr:SetBackdropBorderColor(er, eg, eb, ea)
end
local function build()
  if TCGUI then return TCGUI end
  local w = CreateFrame("Frame", "HatedTCGFrame", UIParent, "BackdropTemplate"); w:Hide()   -- created hidden, so the first click opens it
  w:SetSize(420, 470); w:SetPoint("CENTER", 260, 0); w:SetFrameStrata("HIGH"); w:SetToplevel(true)
  w:SetMovable(true); w:EnableMouse(true); w:RegisterForDrag("LeftButton"); w:SetClampedToScreen(true)
  w:SetScript("OnDragStart", w.StartMoving); w:SetScript("OnDragStop", w.StopMovingOrSizing)
  flat(w, 0.035, 0.055, 0.06, 0.97, 0.25, 0.95, 0.85, 0.7)
  tinsert(UISpecialFrames, "HatedTCGFrame")
  local glow = w:CreateTexture(nil, "BACKGROUND", nil, 1); glow:SetPoint("TOPLEFT", 1, -1); glow:SetPoint("TOPRIGHT", -1, -1); glow:SetHeight(120)
  glow:SetColorTexture(1, 1, 1, 1)
  if CreateColor and pcall(glow.SetGradient, glow, "VERTICAL", CreateColor(0.1, 0.5, 0.48, 0), CreateColor(0.1, 0.5, 0.48, 0.35)) then else glow:SetColorTexture(0.1, 0.5, 0.48, 0.15) end
  local close = CreateFrame("Button", nil, w, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 2, 2)
  local back = CreateFrame("Button", nil, w, "UIPanelButtonTemplate"); back:SetSize(64, 20); back:SetPoint("TOPRIGHT", -30, -8); back:SetText("< Hub")
  back:SetScript("OnClick", function() w:Hide(); if HatedHub_Toggle then HatedHub_Toggle() end end)
  local title = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOPLEFT", 16, -14); title:SetText("Hated TCG")
  title:SetTextColor(0.75, 1, 0.96)

  w.total = w:CreateFontString(nil, "OVERLAY"); w.total:SetFont(STANDARD_TEXT_FONT, 40, "OUTLINE"); w.total:SetPoint("TOP", 0, -44)
  w.total:SetTextColor(TEAL[1], TEAL[2], TEAL[3])
  w.totalLbl = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); w.totalLbl:SetPoint("TOP", w.total, "BOTTOM", 0, -2)
  w.detail = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); w.detail:SetPoint("TOP", w.totalLbl, "BOTTOM", 0, -6); w.detail:SetWidth(380)

  local rl = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); rl:SetPoint("TOPLEFT", 16, -148); rl:SetText("RECENT"); rl:SetTextColor(0.5, 0.8, 0.76)
  w.rows = {}
  for i = 1, 10 do
    local r = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r:SetPoint("TOPLEFT", 16, -150 - i * 18); r:SetWidth(300); r:SetJustifyH("LEFT")
    local a = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); a:SetPoint("TOPRIGHT", -16, -150 - i * 18); a:SetTextColor(TEAL[1], TEAL[2], TEAL[3])
    w.rows[i] = { r, a }
  end

  -- paste the website's code
  local box = CreateFrame("EditBox", nil, w, "InputBoxTemplate")
  box:SetPoint("BOTTOMLEFT", 22, 46); box:SetSize(270, 24); box:SetAutoFocus(false); box:SetMaxLetters(80)
  box:SetScript("OnEscapePressed", box.ClearFocus)
  local hint = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); hint:SetPoint("BOTTOMLEFT", box, "TOPLEFT", -4, 4)
  hint:SetText("Paste the code from your website Profile > Hated TCG:")
  local ok = CreateFrame("Button", nil, w, "UIPanelButtonTemplate"); ok:SetSize(90, 24); ok:SetPoint("LEFT", box, "RIGHT", 8, 0); ok:SetText("Update")
  local function apply()
    local s = checkCode(box:GetText())
    if not s then say("that code doesn't look right - copy it again from the website."); return end
    db().server = s; box:SetText(""); box:ClearFocus(); w.refresh()
    say(string.format("account total updated: %d points.", s.points))
  end
  ok:SetScript("OnClick", apply); box:SetScript("OnEnterPressed", apply)
  local soon = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); soon:SetPoint("BOTTOM", 0, 16)
  soon:SetText("Card packs and your binder are coming - spend points on hatedforever.com.")

  w.refresh = function()
    local t = db(); local new, n = sinceSync()
    if t.server then
      w.total:SetText(BreakUpLargeNumbers and BreakUpLargeNumbers(t.server.points + new) or (t.server.points + new))
      w.totalLbl:SetText("points on your account")
      w.detail:SetText(string.format("%d at your last sync (%s)%s", t.server.points, date("%b %d", t.server.at),
        new > 0 and string.format("  +  about %d earned since (%d kills)", new, n) or ""))
    else
      w.total:SetText("+" .. new)
      w.totalLbl:SetText("points earned in game, not synced yet")
      w.detail:SetText("Sync on the website, then paste the code below to see your whole account here.")
    end
    -- newest first
    local shown = 0
    for i = #t.log, 1, -1 do
      if shown >= 10 then break end
      local e = entryOf(t.log[i])
      if e then
        shown = shown + 1
        local row = w.rows[shown]
        row[1]:SetText(string.format("|cff7fb5ad%s|r  %s%s|r  |cff6f8f8a%s|r", date("%b %d %H:%M", e.t), e.boss and "|cffffd36a" or "|cffe8f6f3", e.name, e.char or ""))
        row[2]:SetText(e.amount > 0 and ("+" .. e.amount) or "")
      end
    end
    for i = shown + 1, 10 do w.rows[i][1]:SetText(i == 1 and "|cff6f8f8aNothing yet - go kill something!|r" or ""); w.rows[i][2]:SetText("") end
  end
  TCGUI = w
  return w
end

function HatedTCG_Toggle(open)
  local w = build()
  if w:IsShown() and not open then w:Hide() else w.refresh(); w:Show() end
end
-- for the hub: (account total, earned since the last sync, whether a sync code has been pasted)
function HatedTCG_Summary()
  local t = db(); local new = sinceSync()
  if t.server then return t.server.points + new, new, true end
  return new, new, false
end

-- ---------- /tcg ----------
SLASH_HATEDTCG1 = "/tcg"
SlashCmdList.HATEDTCG = function(msg)
  if (msg or ""):lower():match("debug") then
    HatedCompanionDB = HatedCompanionDB or {}; HatedCompanionDB.tcgDebug = not HatedCompanionDB.tcgDebug
    say("debug " .. (HatedCompanionDB.tcgDebug and "on: kills are reported in chat (/tcg debug again to stop)." or "off.")); return
  end
  if (msg or ""):lower():match("test") then popup(10, nil); say("that was a test popup (no points)."); return end
  HatedTCG_Toggle()
end
