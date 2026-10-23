--[[ Hated Companion: TCG card drops
  Any kill can drop a card, right there in game: the creature's own card if it has one (Hogger drops Hogger), else a
  card of its tribe (beasts drop Beasts, murlocs Murlocs...) or of its class (from its name: "Druid of the Fang"
  drops druid cards), else a neutral card. A creature with a class also has a 1 in 100 chance at its class's hero.
  The roll comes from the creature's spawn id with the tables in HatedTCGDropData.lua; the website rolls it again
  the same way when you sync and adds the card to your collection. Until then it sits in the binder as unsealed.
]]

local X = HatedTCG_DROPS
local unpack = unpack or table.unpack
local ADDON = "Interface\\AddOns\\HatedCompanion\\"
local RARITY_NAME = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }
local RARITY_COLOR = { "ffffffff", "ff1eff00", "ff0070dd", "ffa335ee", "ffff8000" }
local function say(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff5afff2Hated TCG:|r " .. msg) end

-- ---------- what a creature can drop (the same rules as the server: drops.ts) ----------
local function norm(s) return ((s or ""):lower():gsub("[^a-z]", "")) end
local function hasWord(padded, w) return padded:find(" " .. w .. " ", 1, true) ~= nil end
-- returns the drop group ("n.<creature>", "t.<TRIBE>", "c.<CLASS>" or "" for neutral) and the class ("" if none)
local function classify(name, ctype)
  local padded = " " .. (name or ""):lower():gsub("[^a-z']", " ") .. " "
  local cls = ""
  for _, c in ipairs(X.classOrder) do
    for _, w in ipairs(X.classWords[c]) do if hasWord(padded, w) then cls = c; break end end
    if cls ~= "" then break end
  end
  local n = norm(name)
  if X.named[n] then return "n." .. n, cls end
  for _, t in ipairs(X.tribeOrder) do
    for _, w in ipairs(X.tribeWords[t]) do if hasWord(padded, w) then return "t." .. t, cls end end
  end
  if cls ~= "" then return "c." .. cls, cls end
  local tribe = X.ctypeTribe[ctype or ""]
  if tribe then return "t." .. tribe, cls end
  return "", cls
end

local function rng(seed)
  local s = 7
  for i = 1, #seed do s = (s * 31 + seed:byte(i)) % 2147483646 + 1 end
  return function(n) s = (s * 48271) % 2147483647; return s % n end
end
-- kind: normal / elite / rare / worldboss / dungeonboss / raidboss. Returns the dropped card (dbf) or nil, and a hero (dbf) or nil.
local function roll(key, group, cls, kind)
  local r = rng("hated-drop-" .. X.version .. "|" .. key)
  local hero
  if cls ~= "" and X.heroes[cls] and r(X.heroOdds) == 0 then local h = X.heroes[cls]; hero = h[r(#h) + 1] end
  local named = group:sub(1, 2) == "n." and X.named[group:sub(3)]
  local odds = X.odds[kind] or X.odds.normal
  if named then odds = math.min(odds, X.odds.named) end
  if r(odds) ~= 0 then return nil, hero end
  if named then return named[r(#named) + 1], hero end
  local pools = X.neutral
  if group:sub(1, 2) == "t." then pools = X.tribes[group:sub(3)] or X.neutral
  elseif group:sub(1, 2) == "c." then pools = X.classes[group:sub(3)] or X.neutral end
  local pct = (kind == "normal" or kind == "elite") and X.rarityPct.low or X.rarityPct.high
  local x, want = r(100), 5
  for i = 1, 5 do x = x - pct[i]; if x < 0 then want = i; break end end
  -- the creature's group may have no card of that rarity: take the nearest rarity it has
  for step = 0, 4 do
    for _, i in ipairs(step == 0 and { want } or { want - step, want + step }) do
      local p = pools[i]
      if p and #p > 0 then return p[r(#p) + 1], hero end
    end
  end
  return nil, hero
end
HatedTCGDrops_Classify, HatedTCGDrops_Roll = classify, roll   -- (HatedTCG.lua, and the tests)

-- ---------- the reveal: the card flips up in the middle of the screen ----------
local queue, showing = {}, false
local reveal
local function showNext()
  if showing or #queue == 0 then return end
  local dbf, why = unpack(table.remove(queue, 1))
  local c = HatedTCG_CARDS and HatedTCG_CARDS[dbf]
  if not c or not HatedTCGBinder_MakeCard then return showNext() end
  if not reveal then
    reveal = CreateFrame("Frame", "HatedTCGReveal", UIParent); reveal:SetSize(260, 360); reveal:SetPoint("CENTER", 0, 80)
    reveal:SetFrameStrata("FULLSCREEN_DIALOG"); reveal:Hide()
    reveal.burst = reveal:CreateTexture(nil, "BACKGROUND"); reveal.burst:SetPoint("CENTER"); reveal.burst:SetSize(620, 620)
    reveal.burst:SetTexture("Interface\\Cooldown\\star4"); reveal.burst:SetBlendMode("ADD")
    reveal.card = HatedTCGBinder_MakeCard(reveal, 220, 302); reveal.card:SetPoint("CENTER", 0, 10); reveal.card:EnableMouse(false)
    reveal.title = reveal:CreateFontString(nil, "OVERLAY"); reveal.title:SetFont(STANDARD_TEXT_FONT, 20, "OUTLINE"); reveal.title:SetPoint("BOTTOM", reveal, "TOP", 0, 0)
    reveal.sub = reveal:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); reveal.sub:SetPoint("TOP", reveal, "BOTTOM", 0, 2)
    local ag = reveal:CreateAnimationGroup()
    local grow = ag:CreateAnimation("Scale"); grow:SetScaleFrom(0.05, 1); grow:SetScaleTo(1, 1); grow:SetDuration(0.35); grow:SetSmoothing("OUT")   -- the flip
    local fadeIn = ag:CreateAnimation("Alpha"); fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(1); fadeIn:SetDuration(0.25)
    local fadeOut = ag:CreateAnimation("Alpha"); fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(0); fadeOut:SetStartDelay(3.4); fadeOut:SetDuration(0.6)
    ag:SetScript("OnFinished", function() reveal:Hide(); showing = false; C_Timer.After(0.2, showNext) end)
    reveal.ag = ag
    local spin = reveal.burst:CreateAnimationGroup(); spin:SetLooping("REPEAT")
    local rot = spin:CreateAnimation("Rotation"); rot:SetDegrees(-360); rot:SetDuration(8)
    reveal.spin = spin
  end
  showing = true
  reveal.card:set(dbf, { n = 1 })
  local col = RARITY_COLOR[c[2]] or RARITY_COLOR[1]
  local r, g, b = tonumber(col:sub(3, 4), 16) / 255, tonumber(col:sub(5, 6), 16) / 255, tonumber(col:sub(7, 8), 16) / 255
  reveal.burst:SetVertexColor(r, g, b, c[2] >= 4 and 0.9 or 0.55)
  reveal.title:SetText("|c" .. col .. (c[6] == "H" and "Hero card!" or (RARITY_NAME[c[2]] .. " card drop!")) .. "|r")
  reveal.sub:SetText(why)
  reveal:Show(); reveal.spin:Play(); reveal.ag:Stop(); reveal.ag:Play()
  if PlaySound and SOUNDKIT then pcall(PlaySound, c[2] >= 4 and (SOUNDKIT.UI_LEGENDARY_LOOT_TOAST or 63971) or (SOUNDKIT.UI_EPICLOOT_TOAST or 31578)) end
end

-- from HatedTCG.lua after each kill is logged. key: the roll's seed (the spawn id, or the boss's own key)
function HatedTCGDrops_OnKill(key, group, cls, kind, creatureName)
  local drop, hero = roll(key, group, cls, kind)
  for k = 1, 2 do                                   -- (not ipairs: the drop can be nil with a hero after it)
    local dbf; if k == 1 then dbf = drop else dbf = hero end
    local c = dbf and HatedTCG_CARDS and HatedTCG_CARDS[dbf]
    if c then
      local t = HatedTCG_DB(); t.pending = t.pending or {}
      table.insert(t.pending, { dbf = dbf, t = time(), from = creatureName or "" })
      say(string.format("|c%s[%s]|r dropped from %s! It's in your binder, unsealed until you sync on the website.",
        RARITY_COLOR[c[2]] or RARITY_COLOR[1], c[1], creatureName or "a kill"))
      queue[#queue + 1] = { dbf, "from " .. (creatureName or "a kill") .. "  -  sync to seal it" }
      showNext()
    end
  end
end
-- test: /tcg droptest <dbf>
function HatedTCGDrops_Test(dbf) queue[#queue + 1] = { dbf, "a test (not a real drop)" }; showNext() end
