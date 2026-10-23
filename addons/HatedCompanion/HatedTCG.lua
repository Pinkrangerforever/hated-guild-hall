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
  /tcg daily   the same window (its Daily Challenges section: HatedTCGDaily.lua)
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
  t.recent = t.recent or {}                       -- the window's "Recent" list (kept even after synced kills are cleared)
  table.insert(t.recent, entry); while #t.recent > 10 do table.remove(t.recent, 1) end
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
local function dotsOn() return not (HatedCompanionDB and HatedCompanionDB.tcgDotsOff) end
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
  local new = dotsOn() and isNew(unit)
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
-- for the hub's switch: on / off, applied to every nameplate on screen right away
function HatedTCG_DotsOn() return dotsOn() end
function HatedTCG_SetDots(on)
  HatedCompanionDB = HatedCompanionDB or {}
  HatedCompanionDB.tcgDotsOff = not on or nil
  for i = 1, 40 do local u = "nameplate" .. i; if UnitExists(u) then markPlate(u) end end
end
local function tooltipUnit(tip)
  local _, unit = tip:GetUnit()
  if unit and dotsOn() and isNew(unit) then tip:AddLine(DOT .. " |cff5afff2Never killed on your account: +10 TCG|r") ; tip:Show() end
end
if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tip) if tip == GameTooltip then tooltipUnit(tip) end end)
else
  GameTooltip:HookScript("OnTooltipSetUnit", tooltipUnit)
end

local function award(key, first, amount, guid)
  if first then db().firsts[key] = true; C_Timer.After(0.1, refreshPlates) end
  if amount > 0 and dotsOn() then popup(amount, guid) end   -- points always count; the hub switch only hides the visuals
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
  local ctype = (HatedTCG_DAILY and HatedTCG_DAILY.ctype[i.ctype or ""]) or ""
  local fac = (UnitFactionGroup("player") or ""):sub(1, 1)
  local now = time()
  local grp, ncls = "", ""
  if HatedTCGDrops_Classify then grp, ncls = HatedTCGDrops_Classify(i.name, ctype) end
  append(table.concat({ "m", now, UnitName("player"), plvl, id, guid, instId or 0, zone, i.lvl or 0, cls, amount, ((i.name or ""):gsub(",", "")), ctype, fac, grp, ncls }, ","))
  if HatedTCGDaily_Note then HatedTCGDaily_Note("m", { t = now, char = UnitName("player"), plvl = plvl, fac = fac, ctype = ctype, cls = cls, first = first, inst = instId or 0 }) end
  -- a card drop (only kills with a real spawn id can drop: the website rolls them again from it)
  if HatedTCGDrops_OnKill and guid:match("^%a+%-0%-%d+%-%d+%-%d+%-%d+%-%x+$") then
    local kind = cls == "worldboss" and "worldboss" or (cls == "rare" or cls == "rareelite") and "rare" or cls == "elite" and "elite" or "normal"
    HatedTCGDrops_OnKill(guid, grp, ncls, kind, i.name, i.at)
  end
  dbg(string.format("logged %s (npc %d) for %d points; log has %d lines", tostring(i.name), id, amount, #db().log))
  award(key, first, amount, guid)
end

local function bossKilled(encounterID, name, difficultyID, groupSize)
  local _, instType, _, _, _, _, _, instId = GetInstanceInfo()
  local kind = instType == "raid" and "r" or "d"
  local key = "e:" .. encounterID
  local first = not db().firsts[key]
  local amount = kind == "r" and (first and 100 or 20) or 10
  local dkey = kind == "d" and HatedTCGDaily_DungeonKey and HatedTCGDaily_DungeonKey() or ""
  local fac = (UnitFactionGroup("player") or ""):sub(1, 1)
  local now = time()
  local grp, ncls = "", ""
  if HatedTCGDrops_Classify then grp, ncls = HatedTCGDrops_Classify(name, "") end
  append(table.concat({ "b", now, UnitName("player"), UnitLevel("player"), encounterID, kind, instId or 0, difficultyID or 0, groupSize or 0, GetNumGroupMembers(), amount, ((name or ""):gsub(",", "")), dkey, fac, grp, ncls }, ","))
  if HatedTCGDrops_OnKill then
    local t = db(); t.bossDrops = t.bossDrops or {}
    local bucket = kind == "r" and math.floor((now - 4 * 86400) / (7 * 86400)) or math.floor(now / 3600)
    local lock = encounterID .. ":" .. UnitName("player") .. ":" .. bucket
    if not t.bossDrops[lock] then
      t.bossDrops[lock] = now
      HatedTCGDrops_OnKill("b|" .. encounterID .. "|" .. UnitName("player") .. "|" .. now, grp, ncls, kind == "r" and "raidboss" or "dungeonboss", name)
    end
  end
  if HatedTCGDaily_Note then HatedTCGDaily_Note("b", { t = now, char = UnitName("player"), plvl = UnitLevel("player"), fac = fac, key = dkey, inst = instId or 0, raid = kind == "r" }) end
  award(key, first, amount, nil)
end

-- ---------- events ----------
-- This client doesn't let addons read the combat log, so kills are spotted the way WoW awards credit: a mob we saw
-- alive (on a nameplate or as the target) dies while our group holds its tag (UnitIsTapDenied is false).
local seenAlive, counted, engaged = {}, {}, {}
-- did you (or your group) fight it? on its threat list, or it was attacking one of you
local function groupUnits()
  local list = { "player", "pet" }
  if IsInRaid() then for i = 1, GetNumGroupMembers() do list[#list + 1] = "raid" .. i; list[#list + 1] = "raidpet" .. i end
  elseif IsInGroup() then for i = 1, GetNumSubgroupMembers() do list[#list + 1] = "party" .. i; list[#list + 1] = "partypet" .. i end end
  return list
end
local function fightingUs(unit)
  for _, u in ipairs(groupUnits()) do
    if UnitExists(u) then
      local ok, s = pcall(UnitThreatSituation, u, unit)
      if ok and s ~= nil then return true end
      if UnitIsUnit(unit .. "target", u) then return true end
    end
  end
  return false
end
local function watch(unit)
  local guid = UnitGUID(unit)
  if not guid or not npcId(guid) or counted[guid] then return end
  if not UnitIsDead(unit) then
    if not seenAlive[guid] then seenAlive[guid] = GetTime(); learn(unit) end
    if not engaged[guid] and fightingUs(unit) then engaged[guid] = true end
    return
  end
  if not seenAlive[guid] then return end                         -- an old corpse we never saw alive
  counted[guid] = true
  if UnitIsTapDenied(unit) then dbg("skipped " .. tostring(UnitName(unit)) .. ": another player tagged it"); return end
  if not engaged[guid] then dbg("skipped " .. tostring(UnitName(unit)) .. ": it died without fighting you or your group"); return end
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
f:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
f:RegisterEvent("UNIT_TARGET")
pcall(f.RegisterEvent, f, "ENCOUNTER_END")
f:SetScript("OnEvent", function(_, event, a1, a2, a3, a4, a5)
  if event == "UNIT_HEALTH" or event == "UNIT_FLAGS" or event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_TARGET" then
    if a1 and (WATCHED[a1] or a1:find("^nameplate")) then watch(a1) end
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
    C_Timer.NewTicker(120, function() local now = GetTime(); for g, ts in pairs(seenAlive) do if now - ts > 900 then seenAlive[g] = nil; counted[g] = nil; engaged[g] = nil; info[g] = nil end end end)
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
  for _, e in ipairs(t.log) do local ts = tonumber(e:match("^%a,(%d+),")); if ts and ts > last then sum = sum + (tonumber((select(11, strsplit(",", e)))) or 0); n = n + 1 end end
  return sum, n
end
-- ---------- the export code: your kills since the last sync, packed small, to paste on the website ----------
-- HTCG4~<first kill time>~<edited? 0/1>~<character names>~<creature ids>~<entries>~<check>
-- ("~", not "|": WoW reads "|" + some letters as UI codes and drops them from the edit box - a name like Raphaello broke the old HTCG2 code)
-- entries (base 36, ";" between):  m<time step>,<creature #>,<mob level>,<class>,<character #>,<character level>
--                                  b<time step>,<encounter id>,<r|d>,<character #>,<character level>
local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
local function b36(n)
  n = math.floor(tonumber(n) or 0); if n <= 0 then return "0" end
  local s = ""; while n > 0 do local d = n % 36; s = B36:sub(d + 1, d + 1) .. s; n = math.floor(n / 36) end
  return s
end
local CLS = { normal = "n", elite = "e", rare = "r", rareelite = "R", worldboss = "w", trivial = "t", minus = "m" }
-- HTCG5~<first kill time>~<scrambled block>~<check>. The block (the kills, each with its full spawn id) is scrambled
-- with a key so the code can't be read or hand-edited; the website unscrambles it and the server checks every spawn id.
-- (The addon's code is public, so this stops casual editing, not a determined reader: the real checks are server-side.)
-- Unscrambled block:  <edited 0/1>~<character names>~<creature ids>~<server ids>~<entries ";">
--   m<time step>,<creature #>,<mob level>,<class>,<character #>,<char level>,<spawn: C|V><server #>.<instance>.<map>.<spawn hex>
--   b<time step>,<encounter id>,<r|d>,<character #>,<character level>
-- HTCG6 (3.7+, daily challenges) adds: character names as <name>.<H|A>; m entries ,<creature type letter>;
--   b entries ,<instance map id>,<dungeon key> (HatedTCGDailyData.lua)
-- HTCG7 (3.8+, card drops) adds to m and b entries: ,<drop group>,<class> (HatedTCGDrops.lua)
local SCRAMBLE_KEY = "hated-forever-tcg-5"
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local function scramble(plain, salt)
  local s = 7
  local seed = SCRAMBLE_KEY .. salt
  for i = 1, #seed do s = (s * 31 + seed:byte(i)) % 2147483646 + 1 end
  local bytes = {}
  for i = 1, #plain do
    s = (s * 48271) % 2147483647
    bytes[i] = (plain:byte(i) + s % 256) % 256
  end
  local out = {}
  for i = 1, #bytes, 3 do
    local a, b, c = bytes[i], bytes[i + 1], bytes[i + 2]
    local v = a * 65536 + (b or 0) * 256 + (c or 0)
    local q = { math.floor(v / 262144) % 64, math.floor(v / 4096) % 64, math.floor(v / 64) % 64, v % 64 }
    local keep = c and 4 or (b and 3 or 2)
    for k = 1, keep do out[#out + 1] = B64:sub(q[k] + 1, q[k] + 1) end
  end
  return table.concat(out)
end
local function exportCode()
  local t = db(); local since = (t.server and t.server.lastT) or 0
  local chars, charIx, npcs, npcIx, srvs, srvIx, out, prev, first, n = {}, {}, {}, {}, {}, {}, {}, nil, nil, 0
  local function ci(c, fac) if not charIx[c] then chars[#chars + 1] = (c:gsub("[|~,;.]", "")) .. "." .. (fac or ""); charIx[c] = #chars - 1 end return charIx[c] end
  local function si(v) if not srvIx[v] then srvs[#srvs + 1] = b36(v); srvIx[v] = #srvs - 1 end return srvIx[v] end
  for _, e in ipairs(t.log) do
    local f = { strsplit(",", e) }
    local ts = tonumber(f[2])
    if ts and ts > since then
      if not first then first = ts; prev = ts end
      local step = ts - prev; prev = ts
      local dt = step < 0 and ("-" .. b36(-step)) or b36(step)   -- usually forwards; a minus if the log is ever out of order
      if f[1] == "m" then
        local id = tonumber(f[5]) or 0
        if not npcIx[id] then npcs[#npcs + 1] = b36(id); npcIx[id] = #npcs - 1 end
        -- the spawn id: Creature-0-<server>-<instance>-<map>-<npc>-<spawn hex>
        local g = ""
        local kind, _, srv, inst, map, _, spawn = strsplit("-", f[6] or "")
        if (kind == "Creature" or kind == "Vehicle") and tonumber(srv) and tonumber(inst) and tonumber(map) and spawn and spawn:match("^%x+$") then
          g = (kind == "Vehicle" and "V" or "C") .. b36(si(tonumber(srv))) .. "." .. b36(inst) .. "." .. b36(map) .. "." .. spawn
        end
        out[#out + 1] = "m" .. dt .. "," .. b36(npcIx[id]) .. "," .. b36(f[9]) .. "," .. (CLS[f[10]] or "x") .. "," .. b36(ci(f[3] or "?", f[14])) .. "," .. b36(f[4]) .. "," .. g .. "," .. ((f[13] or ""):match("^%u?$") or "") .. "," .. ((f[15] or ""):match("^[%a%.]*$") or "") .. "," .. ((f[16] or ""):match("^%u*$") or "")
      elseif f[1] == "b" then
        out[#out + 1] = "b" .. dt .. "," .. b36(f[5]) .. "," .. (f[6] == "r" and "r" or "d") .. "," .. b36(ci(f[3] or "?", f[14])) .. "," .. b36(f[4]) .. "," .. b36(f[7]) .. "," .. ((f[13] or ""):match("^%l*$") or "") .. "," .. ((f[15] or ""):match("^[%a%.]*$") or "") .. "," .. ((f[16] or ""):match("^%u*$") or "")
      end
      n = n + 1
    end
  end
  if n == 0 then return nil, 0 end
  local plain = table.concat({ t.tampered and 1 or 0, table.concat(chars, ","), table.concat(npcs, ","), table.concat(srvs, ","), table.concat(out, ";") }, "~")
  local body = "HTCG7~" .. first .. "~" .. scramble(plain, tostring(first))
  local h = 7; for i = 1, #body do h = (h * 31 + body:byte(i)) % 1000003 end
  return body .. "~" .. h, n
end

local exporter
local function showExport()
  local code, n = exportCode()
  if not code then say("nothing new to export since your last sync - go kill something!"); return end
  if not exporter then
    local x = CreateFrame("Frame", "HatedTCGExport", UIParent, "BackdropTemplate"); x:Hide()
    x:SetSize(480, 300); x:SetPoint("CENTER", 0, 60); x:SetFrameStrata("DIALOG"); x:EnableMouse(true)
    x:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    x:SetBackdropColor(0.035, 0.055, 0.06, 0.98); x:SetBackdropBorderColor(TEAL[1], TEAL[2], TEAL[3], 0.8)
    tinsert(UISpecialFrames, "HatedTCGExport")
    local close = CreateFrame("Button", nil, x, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 2, 2)
    x.title = x:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); x.title:SetPoint("TOPLEFT", 16, -14); x.title:SetTextColor(0.75, 1, 0.96)
    x.help = x:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); x.help:SetPoint("TOPLEFT", 16, -40); x.help:SetWidth(448); x.help:SetJustifyH("LEFT")
    x.help:SetText("1.  Press |cff5afff2Ctrl+C|r to copy the code below (it's already selected).\n2.  On hatedforever.com, open your |cff5afff2Profile > Hated TCG|r, paste it into |cff5afff2Paste from game|r and click Sync.\n3.  Back here, paste the website's code into |cff5afff2Import from website|r (or use |cff5afff2Export Cards to WoW!|r on your profile any time).")
    local sf = CreateFrame("ScrollFrame", "HatedTCGExportScroll", x, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 16, -96); sf:SetPoint("BOTTOMRIGHT", -34, 44)
    local bg = x:CreateTexture(nil, "ARTWORK"); bg:SetPoint("TOPLEFT", sf, -4, 4); bg:SetPoint("BOTTOMRIGHT", sf, 24, -4); bg:SetColorTexture(0, 0, 0, 0.5)
    local box = CreateFrame("EditBox", nil, sf); box:SetMultiLine(true); box:SetMaxLetters(0); box:SetAutoFocus(false)
    box:SetFontObject("ChatFontSmall"); box:SetWidth(420); box:SetHeight(150)
    box:SetScript("OnEscapePressed", function() x:Hide() end)
    box:SetScript("OnTextChanged", function(self, user) if user then self:SetText(x.code or ""); self:HighlightText() end end)   -- read only
    box:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    sf:SetScrollChild(box)
    x.box = box
    local sel = CreateFrame("Button", nil, x, "UIPanelButtonTemplate"); sel:SetSize(120, 22); sel:SetPoint("BOTTOMLEFT", 16, 12); sel:SetText("Select all")
    sel:SetScript("OnClick", function() box:SetFocus(); box:HighlightText() end)
    x.size = x:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); x.size:SetPoint("BOTTOMRIGHT", -16, 18)
    exporter = x
  end
  exporter.code = code
  exporter.title:SetText(string.format("Export %d kill%s", n, n == 1 and "" or "s"))
  exporter.size:SetText(string.format("%.1f KB", #code / 1024))
  exporter.box:SetText(code); exporter:Show(); exporter.box:SetFocus(); exporter.box:HighlightText()
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
  w:SetSize(420, 660); w:SetPoint("CENTER", 260, 0); w:SetFrameStrata("HIGH"); w:SetToplevel(true)
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

  -- today's daily challenges (HatedTCGDaily.lua)
  if HatedTCGDaily_Panel then w.daily = HatedTCGDaily_Panel(w); w.daily:SetPoint("TOPLEFT", 12, -138) end
  local RECENT, top = 6, -372
  local rl = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); rl:SetPoint("TOPLEFT", 16, top); rl:SetText("RECENT"); rl:SetTextColor(0.5, 0.8, 0.76)
  w.rows = {}
  for i = 1, RECENT do
    local r = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r:SetPoint("TOPLEFT", 16, top - 2 - i * 18); r:SetWidth(300); r:SetJustifyH("LEFT")
    local a = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); a:SetPoint("TOPRIGHT", -16, top - 2 - i * 18); a:SetTextColor(TEAL[1], TEAL[2], TEAL[3])
    w.rows[i] = { r, a }
  end

  -- paste the website's code
  local box = CreateFrame("EditBox", nil, w, "InputBoxTemplate")
  box:SetPoint("BOTTOMLEFT", 22, 46); box:SetSize(270, 24); box:SetAutoFocus(false); box:SetMaxLetters(0)   -- the card code is long
  box:SetScript("OnEscapePressed", box.ClearFocus)
  local hint = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); hint:SetPoint("BOTTOMLEFT", box, "TOPLEFT", -4, 4)
  hint:SetText("2.  Import from website (from Export Cards to WoW! on your profile):")
  local exp = CreateFrame("Button", nil, w, "UIPanelButtonTemplate"); exp:SetSize(150, 24); exp:SetPoint("BOTTOMLEFT", 16, 102); exp:SetText("Export points")
  exp:SetScript("OnClick", showExport)
  local ehint = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); ehint:SetPoint("BOTTOMLEFT", exp, "TOPLEFT", 2, 4)
  ehint:SetText("1.  Copy your new kills to the website (Profile > Hated TCG):")
  local ok = CreateFrame("Button", nil, w, "UIPanelButtonTemplate"); ok:SetSize(90, 24); ok:SetPoint("LEFT", box, "RIGHT", 8, 0); ok:SetText("Import")
  local function apply()
    local s, cards, decks = nil, nil, nil
    if HatedTCG_ReadCode then s, cards, decks = HatedTCG_ReadCode(box:GetText()) end    -- HTCG3: points + cards + decks
    if not s then s = checkCode(box:GetText()) end                                       -- HTCG: points only (after a sync)
    if not s then say("that code doesn't look right - copy it again from the website."); return end
    local d = db(); d.server = s
    if cards then
      d.cards, d.decks = cards, decks
      local n = 0; for _, o in pairs(cards) do n = n + o.n end
      say(string.format("binder updated: %d cards, %d deck%s. Open it with the Binder button or /binder.", n, #decks, #decks == 1 and "" or "s"))
    end
    -- the website has counted everything up to s.lastT: drop those lines so exports (and this file) stay small
    local keep, edited = {}, d.tampered
    for _, e in ipairs(d.log) do local ts = tonumber(e:match("^%a,(%d+),")); if not ts or ts > s.lastT then keep[#keep + 1] = e end end
    if #keep ~= #d.log then d.log = keep; d.seal = reseal(d); if edited then d.tampered = true end end
    if d.pending then local p = {}; for _, x in ipairs(d.pending) do if x.t > s.lastT then p[#p + 1] = x end end; d.pending = p end
    if d.bossDrops then for k, at in pairs(d.bossDrops) do if at < time() - 8 * 86400 then d.bossDrops[k] = nil end end end
    box:SetText(""); box:ClearFocus(); w.refresh()
    say(string.format("account total updated: %d points.", s.points))
  end
  ok:SetScript("OnClick", apply); box:SetScript("OnEnterPressed", apply)
  local binder = CreateFrame("Button", nil, w, "UIPanelButtonTemplate"); binder:SetSize(170, 24); binder:SetPoint("BOTTOM", 0, 12)
  binder:SetText("Binder & Decks")
  binder:SetScript("OnClick", function() w:Hide(); if HatedTCGBinder_Toggle then HatedTCGBinder_Toggle("binder") end end)

  w.refresh = function()
    local t = db(); local new, n = sinceSync()
    if w.daily then w.daily.refresh() end
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
    local recent = t.recent or t.log
    for i = #recent, 1, -1 do
      if shown >= #w.rows then break end
      local e = entryOf(recent[i])
      if e then
        shown = shown + 1
        local row = w.rows[shown]
        row[1]:SetText(string.format("|cff7fb5ad%s|r  %s%s|r  |cff6f8f8a%s|r", date("%b %d %H:%M", e.t), e.boss and "|cffffd36a" or "|cffe8f6f3", e.name, e.char or ""))
        row[2]:SetText(e.amount > 0 and ("+" .. e.amount) or "")
      end
    end
    for i = shown + 1, #w.rows do w.rows[i][1]:SetText(i == 1 and "|cff6f8f8aNothing yet - go kill something!|r" or ""); w.rows[i][2]:SetText("") end
  end
  TCGUI = w
  return w
end

function HatedTCG_DB() return db() end          -- the binder (HatedTCGBinder.lua) keeps its cards and decks here too

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
  if (msg or ""):lower():match("^%s*test%s*$") then popup(10, nil); say("that was a test popup (no points)."); return end
  if (msg or ""):lower():match("daily") then HatedTCG_Toggle(true); return end
  if (msg or ""):lower():match("^dropall") then
    HatedCompanionDB = HatedCompanionDB or {}; HatedCompanionDB.tcgDropTest = not HatedCompanionDB.tcgDropTest
    say(HatedCompanionDB.tcgDropTest and "drop test ON: every kill shows a card it could drop (just the visual - nothing is added). /tcg dropall again to stop." or "drop test off."); return
  end
  local dt = (msg or ""):match("^droptest%s*(%d*)")   -- /tcg droptest [card number] [holo]
  if dt and HatedTCGDrops_Test then HatedTCGDrops_Test(tonumber(dt) or 1066, (msg or ""):lower():match("holo") ~= nil); return end
  HatedTCG_Toggle()
end
