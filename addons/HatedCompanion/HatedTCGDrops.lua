--[[ Hated Companion: TCG card drops
  Any kill can drop a card, right there in game: the creature's own card if it has one (Hogger drops Hogger), else a
  card of its tribe (beasts drop Beasts, murlocs Murlocs...) or of its class (from its name: "Druid of the Fang"
  drops druid cards), else a neutral card. A creature with a class also has a 1 in 100 chance at its class's hero.
  The roll comes from the creature's spawn id with the tables in HatedTCGDropData.lua; the website rolls it again
  the same way when you sync and adds the card to your collection. Until then it sits in the binder as unsealed.
]]

local X = HatedTCG_DROPS
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

-- ---------- the reveal: the card pops out of the creature face down, glowing its rarity; click to turn it over ----------
local CW, CH = 150, 206
local cards = {}                                   -- reveal frames (reused)
local live = 0                                     -- how many are on screen (to fan them out)
local function rgb(col) return tonumber(col:sub(3, 4), 16) / 255, tonumber(col:sub(5, 6), 16) / 255, tonumber(col:sub(7, 8), 16) / 255 end

local function makeReveal()
  local f = CreateFrame("Button", nil, UIParent); f:SetSize(CW, CH); f:SetFrameStrata("FULLSCREEN_DIALOG"); f:Hide()
  f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  -- the rarity glow round the card (shaped like the card frame: the card sits centred in it at 124 x 170 of 256)
  f.glow = f:CreateTexture(nil, "BACKGROUND"); f.glow:SetPoint("CENTER"); f.glow:SetSize(CW * 256 / 124, CH * 256 / 170)
  f.glow:SetTexture(ADDON .. "Media\\Glow_minion"); f.glow:SetBlendMode("ADD")
  f.burst = f:CreateTexture(nil, "BACKGROUND", nil, -1); f.burst:SetPoint("CENTER"); f.burst:SetSize(460, 460)
  f.burst:SetTexture("Interface\\Cooldown\\star4"); f.burst:SetBlendMode("ADD"); f.burst:Hide()
  f.back = f:CreateTexture(nil, "ARTWORK"); f.back:SetAllPoints(); f.back:SetTexture(ADDON .. "Media\\CardBack"); f.back:SetTexCoord(0, 1, 0, 382 / 512)
  f.face = HatedTCGBinder_MakeCard(f, CW, CH); f.face:SetAllPoints(); f.face:EnableMouse(false); f.face.glow:Hide(); f.face:Hide()
  f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); f.hint:SetPoint("TOP", f, "BOTTOM", 0, -4); f.hint:SetText("|cffffd36aClick to turn over|r")
  f.title = f:CreateFontString(nil, "OVERLAY"); f.title:SetFont(STANDARD_TEXT_FONT, 17, "OUTLINE"); f.title:SetPoint("BOTTOM", f, "TOP", 0, 6)
  f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); f.sub:SetPoint("TOP", f, "BOTTOM", 0, -4); f.sub:SetWidth(240)

  -- out of the body: up in an arc, growing from small
  local pop = f:CreateAnimationGroup()
  local up = pop:CreateAnimation("Translation"); up:SetDuration(0.55); up:SetSmoothing("OUT")
  local grow = pop:CreateAnimation("Scale"); grow:SetScaleFrom(0.15, 0.15); grow:SetScaleTo(1, 1); grow:SetDuration(0.55); grow:SetSmoothing("OUT")
  local fin = pop:CreateAnimation("Alpha"); fin:SetFromAlpha(0); fin:SetToAlpha(1); fin:SetDuration(0.2)
  pop:SetScript("OnFinished", function() f:ClearAllPoints(); f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", f.tx, f.ty); f.bob:Play() end)
  f.pop, f.up = pop, up
  -- waiting to be clicked: a gentle bob and a breathing glow
  local bob = f:CreateAnimationGroup(); bob:SetLooping("BOUNCE")
  local b1 = bob:CreateAnimation("Translation"); b1:SetOffset(0, 6); b1:SetDuration(0.9); b1:SetSmoothing("IN_OUT")
  f.bob = bob
  local breathe = f.glow:CreateAnimationGroup(); breathe:SetLooping("BOUNCE")
  local a1 = breathe:CreateAnimation("Alpha"); a1:SetFromAlpha(1); a1:SetToAlpha(0.45); a1:SetDuration(0.8)
  f.breathe = breathe
  -- turning over: squeeze to an edge, swap back for face, open out again
  local flipA = f:CreateAnimationGroup()
  local s1 = flipA:CreateAnimation("Scale"); s1:SetScaleFrom(1, 1); s1:SetScaleTo(0.02, 1.06); s1:SetDuration(0.14); s1:SetSmoothing("IN")
  local flipB = f:CreateAnimationGroup()
  local s2 = flipB:CreateAnimation("Scale"); s2:SetScaleFrom(0.02, 1.06); s2:SetScaleTo(1, 1); s2:SetDuration(0.16); s2:SetSmoothing("OUT")
  flipA:SetScript("OnFinished", function()
    f.back:Hide(); f.face:Show(); f.hint:Hide()
    f.burst:Show(); f.spin:Play(); f.title:Show(); f.sub:Show()
    flipB:Play()
    local c = HatedTCG_CARDS[f.dbf]
    if PlaySound and SOUNDKIT then pcall(PlaySound, c[2] >= 4 and (SOUNDKIT.UI_LEGENDARY_LOOT_TOAST or 63971) or (SOUNDKIT.UI_EPICLOOT_TOAST or 31578)) end
    f.leaveAt = GetTime() + 5
  end)
  f.flipA = flipA
  local spin = f.burst:CreateAnimationGroup(); spin:SetLooping("REPEAT")
  local rot = spin:CreateAnimation("Rotation"); rot:SetDegrees(-360); rot:SetDuration(8)
  f.spin = spin
  -- away: drift up and fade
  local out = f:CreateAnimationGroup()
  local o1 = out:CreateAnimation("Translation"); o1:SetOffset(0, 40); o1:SetDuration(0.5)
  local o2 = out:CreateAnimation("Alpha"); o2:SetFromAlpha(1); o2:SetToAlpha(0); o2:SetDuration(0.5)
  out:SetScript("OnFinished", function() f:Hide(); f.bob:Stop(); f.breathe:Stop(); f.spin:Stop(); live = math.max(0, live - 1); f.busy = false end)
  f.out = out

  f:SetScript("OnClick", function()
    if f.out:IsPlaying() or f.flipA:IsPlaying() then return end
    if not f.face:IsShown() then f.bob:Stop(); f.flipA:Play() else f.out:Play() end   -- first click turns it over, the next sends it away
  end)
  f:SetScript("OnUpdate", function()
    if f.leaveAt and GetTime() > f.leaveAt and not f.out:IsPlaying() then f.leaveAt = nil; f.out:Play() end
    if f.flipAt and GetTime() > f.flipAt and not f.face:IsShown() and not f.flipA:IsPlaying() then f.flipAt = nil; f.bob:Stop(); f.flipA:Play() end
  end)
  f:SetScript("OnEnter", function() if not f.face:IsShown() then f.glow:SetAlpha(1); f.breathe:Pause() end end)
  f:SetScript("OnLeave", function() if not f.face:IsShown() then f.breathe:Play() end end)
  return f
end

-- at: where the creature was on screen when it died ({ x, y } from the bottom left), or nil
local function reveal(dbf, why, at)
  local c = HatedTCG_CARDS and HatedTCG_CARDS[dbf]
  if not c or not HatedTCGBinder_MakeCard then return end
  local f
  for _, x in ipairs(cards) do if not x.busy then f = x; break end end
  if not f then f = makeReveal(); cards[#cards + 1] = f end
  f.busy = true; f.dbf = dbf
  local col = RARITY_COLOR[c[2]] or RARITY_COLOR[1]
  local r, g, b = rgb(col)
  f.glow:SetTexture(ADDON .. "Media\\Glow_" .. (c[12] or "minion")); f.glow:SetVertexColor(r, g, b); f.glow:SetAlpha(1)
  f.burst:SetVertexColor(r, g, b, c[2] >= 4 and 0.9 or 0.5); f.burst:Hide()
  f.face:set(dbf, { n = 1 }); f.face.glow:Hide(); f.face:Hide(); f.back:Show(); f.hint:Show()
  f.title:SetText("|c" .. col .. (c[6] == "H" and "Hero card!" or (RARITY_NAME[c[2]] .. " card!")) .. "|r"); f.title:Hide()
  f.sub:SetText(why); f.sub:Hide()
  -- where it ends up: above the creature (fanned out if several are up), kept on screen
  local W, H = UIParent:GetWidth(), UIParent:GetHeight()
  -- (this client won't let addons measure where a nameplate is, so it rises from just in front of you: where the
  -- creature you were fighting usually stands)
  local sx, sy = (at and at[1]) or W / 2, (at and at[2]) or H * 0.4
  local tx = math.min(math.max(sx + live * 40, CW), W - CW)
  local ty = math.min(math.max(sy + 150, CH), H - CH / 2 - 40)
  f.tx, f.ty = tx, ty
  live = live + 1
  f:ClearAllPoints(); f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", sx, sy)
  f.up:SetOffset(tx - sx, ty - sy)
  f.leaveAt = nil; f.flipAt = GetTime() + 45            -- not clicked after 45 seconds: it turns itself over
  f:SetAlpha(1); f:Show(); f.breathe:Play(); f.pop:Stop(); f.pop:Play()
  if PlaySound and SOUNDKIT then pcall(PlaySound, SOUNDKIT.UI_GARRISON_MISSION_COMPLETE_ENCOUNTER_CHANCE or SOUNDKIT.IG_BACKPACK_OPEN or 862) end
end

-- from HatedTCG.lua after each kill is logged. key: the roll's seed (the spawn id, or the boss's own key)
-- at: where the creature was on screen when it died (or nil)
function HatedTCGDrops_OnKill(key, group, cls, kind, creatureName, at)
  if HatedCompanionDB and HatedCompanionDB.tcgDropTest then HatedTCGDrops_ShowTest(key, group, cls, creatureName, at) end
  local drop, hero = roll(key, group, cls, kind)
  for k = 1, 2 do                                   -- (not ipairs: the drop can be nil with a hero after it)
    local dbf; if k == 1 then dbf = drop else dbf = hero end
    local c = dbf and HatedTCG_CARDS and HatedTCG_CARDS[dbf]
    if c then
      local t = HatedTCG_DB(); t.pending = t.pending or {}
      table.insert(t.pending, { dbf = dbf, t = time(), from = creatureName or "" })
      say(string.format("|c%s[%s]|r dropped from %s! It's in your binder, unsealed until you sync on the website.",
        RARITY_COLOR[c[2]] or RARITY_COLOR[1], c[1], creatureName or "a kill"))
      reveal(dbf, "from " .. (creatureName or "a kill") .. "  -  sync to seal it", at)
    end
  end
end
-- test: /tcg droptest <dbf>
function HatedTCGDrops_Test(dbf) reveal(dbf, "a test (not a real drop)") end
-- test: /tcg dropall - every kill shows what it COULD drop (only the visual: nothing is added or synced)
function HatedTCGDrops_ShowTest(key, group, cls, creatureName, at)
  if live >= 3 then return end                   -- don't stack up a long line of reveals while pulling packs of mobs
  local r = rng("hated-droptest|" .. key .. "|" .. time())
  local pool
  if group:sub(1, 2) == "n." then pool = X.named[group:sub(3)]
  else
    local pools = X.neutral
    if group:sub(1, 2) == "t." then pools = X.tribes[group:sub(3)] or pools elseif group:sub(1, 2) == "c." then pools = X.classes[group:sub(3)] or pools end
    pool = {}; for _, p in ipairs(pools) do for _, d in ipairs(p) do pool[#pool + 1] = d end end
  end
  local what = group == "" and "neutral" or group:sub(3):lower()
  if pool and #pool > 0 then reveal(pool[r(#pool) + 1], "TEST from " .. (creatureName or "?") .. " (" .. what .. ")", at) end
  if cls ~= "" and X.heroes[cls] and r(4) == 0 then local h = X.heroes[cls]; reveal(h[r(#h) + 1], "TEST hero from " .. (creatureName or "?"), at) end
end
