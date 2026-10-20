--[[ Hated Companion: TCG points
  Kills earn points toward Hated TCG card packs. The addon only LOGS kills (with the proof the game gives: the
  creature's unique spawn id, its creature id, the zone, levels, the time); the website checks the log when you
  sync and credits the real points to your account. Points are account-wide: every character adds to the same pool.

  Values (the website has the final say):
    a creature type killed for the first time on this account     10
    after that: normal 1, elite 3 (grey mobs give nothing)
    dungeon boss 10, a dungeon's last boss 20
    raid boss 100 the first time, 20 after that

  Kills you or your group damaged count for everyone in the group. The log keeps 7 days; sync on the website
  (Profile > Hated TCG) at least once a week. /reload or log out first so WoW writes the file.

  /tcg   points earned since your last sync
]]

local KEEP_DAYS = 7
local TEAL = { 0.25, 0.95, 0.85 }

local function say(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff3ff2d9Hated TCG:|r " .. msg) end

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
local function append(entry)
  local t = db()
  t.log[#t.log + 1] = entry
  t.seal = fnv(t.seal, entry)
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
local function popup(amount, guid)
  local f
  for _, x in ipairs(pool) do if not x:IsShown() then f = x; break end end
  if not f then
    f = CreateFrame("Frame", nil, UIParent); f:SetSize(160, 40); f:SetFrameStrata("HIGH")
    f.text = f:CreateFontString(nil, "OVERLAY"); f.text:SetFont(STANDARD_TEXT_FONT, 26, "OUTLINE"); f.text:SetPoint("CENTER")
    f.text:SetTextColor(TEAL[1], TEAL[2], TEAL[3]); f.text:SetShadowOffset(2, -2)
    f.sub = f:CreateFontString(nil, "OVERLAY"); f.sub:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE"); f.sub:SetPoint("TOP", f.text, "BOTTOM", 0, -1)
    f.sub:SetTextColor(TEAL[1] * 0.8, TEAL[2] * 0.8, TEAL[3] * 0.8); f.sub:SetText("TCG points")
    local ag = f:CreateAnimationGroup()
    local up = ag:CreateAnimation("Translation"); up:SetOffset(0, 70); up:SetDuration(1.6); up:SetSmoothing("OUT")
    local fade = ag:CreateAnimation("Alpha"); fade:SetFromAlpha(1); fade:SetToAlpha(0); fade:SetStartDelay(0.9); fade:SetDuration(0.7)
    local pop = ag:CreateAnimation("Scale"); pop:SetScaleFrom(0.6, 0.6); pop:SetScaleTo(1, 1); pop:SetDuration(0.18)
    ag:SetScript("OnFinished", function() f:Hide() end)
    f.ag = ag
    pool[#pool + 1] = f
  end
  f.text:SetText("+" .. amount)
  f:ClearAllPoints()
  local unit = guid and plateOf[guid]
  local plate = unit and C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
  if plate and plate:IsShown() then f:SetPoint("BOTTOM", plate, "TOP", 0, 6)
  else f:SetPoint("CENTER", UIParent, "CENTER", math.random(-40, 40), 140) end
  f:Show(); f.ag:Stop(); f.ag:Play()
end

-- ---------- earning ----------
-- the addon's own estimate rides along at the end of each line (the website works the real value out itself)
local function award(key, first, amount, guid)
  if first then db().firsts[key] = true end
  if amount > 0 then popup(amount, guid) end
end

local lastEncounter = { t = 0, name = nil }
local function mobKilled(guid)
  local id = npcId(guid); if not id then return end
  local i = info[guid] or {}
  if i.ctype == "Critter" or i.ctype == "Non-combat Pet" or i.ctype == "Totem" then return end
  local plvl = UnitLevel("player")
  if i.lvl and i.lvl > 0 and i.lvl <= greyLevel(plvl) then return end           -- grey: nothing
  -- a boss's death is credited by the encounter itself, not as a normal mob
  if GetTime() - lastEncounter.t < 4 and i.name and i.name == lastEncounter.name then return end
  local cls = i.cls or "?"
  local _, _, _, _, _, _, _, instId = GetInstanceInfo()
  local zone = (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")) or 0
  local key = "n:" .. id
  local first = not db().firsts[key]
  local elite = cls == "elite" or cls == "rareelite" or cls == "worldboss"
  local amount = first and 10 or (elite and 3 or 1)
  append(table.concat({ "m", time(), UnitName("player"), plvl, id, guid, instId or 0, zone, i.lvl or 0, cls, amount }, ","))
  award(key, first, amount, guid)
end

local function bossKilled(encounterID, name, difficultyID, groupSize)
  local _, instType, _, _, _, _, _, instId = GetInstanceInfo()
  local kind = instType == "raid" and "r" or "d"
  local key = "e:" .. encounterID
  local first = not db().firsts[key]
  local amount = kind == "r" and (first and 100 or 20) or 10
  append(table.concat({ "b", time(), UnitName("player"), UnitLevel("player"), encounterID, kind, instId or 0, difficultyID or 0, groupSize or 0, GetNumGroupMembers(), amount }, ","))
  award(key, first, amount, nil)
end

-- ---------- events ----------
local AFF = bit.bor(COMBATLOG_OBJECT_AFFILIATION_MINE or 1, COMBATLOG_OBJECT_AFFILIATION_PARTY or 2, COMBATLOG_OBJECT_AFFILIATION_RAID or 4)
local DAMAGE = { SWING_DAMAGE = true, RANGE_DAMAGE = true, SPELL_DAMAGE = true, SPELL_PERIODIC_DAMAGE = true, DAMAGE_SHIELD = true, SPELL_BUILDING_DAMAGE = true }
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
pcall(f.RegisterEvent, f, "ENCOUNTER_END")
f:SetScript("OnEvent", function(_, event, a1, a2, a3, a4, a5)
  if event == "COMBAT_LOG_EVENT_UNFILTERED" then
    local _, sub, _, _, _, srcFlags, _, dstGUID = CombatLogGetCurrentEventInfo()
    if DAMAGE[sub] then
      if dstGUID and bit.band(srcFlags or 0, AFF) ~= 0 and npcId(dstGUID) then hit[dstGUID] = GetTime() end
    elseif sub == "UNIT_DIED" and dstGUID and hit[dstGUID] then
      local guid = dstGUID
      if GetTime() - hit[guid] < 120 then C_Timer.After(1.5, function() mobKilled(guid); hit[guid] = nil; info[guid] = nil end) end
    end
  elseif event == "NAME_PLATE_UNIT_ADDED" then
    local g = UnitGUID(a1); if g then plateOf[g] = a1; learn(a1) end
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    local g = UnitGUID(a1); if g and plateOf[g] == a1 then C_Timer.After(2, function() if plateOf[g] == a1 then plateOf[g] = nil end end) end
  elseif event == "PLAYER_TARGET_CHANGED" then learn("target")
  elseif event == "UPDATE_MOUSEOVER_UNIT" then learn("mouseover")
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
    if #keep ~= #t.log then
      local wasOk = not t.tampered
      t.log = keep; t.seal = reseal(t)
      if not wasOk then t.tampered = true end
    end
    -- forget old spawns we were tracking
    C_Timer.NewTicker(60, function() local now = GetTime(); for g, ts in pairs(hit) do if now - ts > 180 then hit[g] = nil; info[g] = nil end end end)
  end
end)

-- ---------- /tcg ----------
SLASH_HATEDTCG1 = "/tcg"
SlashCmdList.HATEDTCG = function()
  local t, sum = db(), 0
  for _, e in ipairs(t.log) do sum = sum + (tonumber(e:match(",(%d+)$")) or 0) end
  say(string.format("your log holds about %d points from the last %d days (%d kills and bosses). Sync on hatedforever.com > your Profile > Hated TCG after a /reload or log out; syncing twice never counts a kill twice.",
    sum, KEEP_DAYS, #t.log))
end
