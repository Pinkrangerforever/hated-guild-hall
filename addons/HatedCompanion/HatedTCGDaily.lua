--[[ Hated Companion: TCG daily challenges
  Every character gets a board each day (midnight Pacific): one dungeon from its level bracket (250 points) and three
  smaller tasks (25-75). The board is picked here from the date, the character's level and faction, using the tables
  in HatedTCGDailyData.lua - no sync needed. The website picks the same board again when you sync and pays what the
  kill log proves (this window only shows progress).

  The board locks to the character's level at its first kill of the day, so levelling mid-day doesn't change it.
  Shown in the Hated TCG window (/tcg); /tcg daily opens it too.
]]

local D = HatedTCG_DAILY
local TEAL = { 0.35, 1, 0.95 }
local function say(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff5afff2Hated TCG:|r " .. msg) end

-- ---------- the Pacific day (the same arithmetic as the server: daily.ts) ----------
local function daysFromCivil(y, m, d)
  if m <= 2 then y = y - 1 end
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local mp = (m + 9) % 12
  local doy = math.floor((153 * mp + 2) / 5) + d - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
end
local function yearOf(z)
  local y = 1970 + math.floor(z / 365.2425)
  if daysFromCivil(y, 1, 1) > z then y = y - 1 elseif daysFromCivil(y + 1, 1, 1) <= z then y = y + 1 end
  return y
end
local function sundayOnOrAfter(z) return z + (7 - (z + 4) % 7) % 7 end    -- day 0 (1970-01-01) was a Thursday
-- US Pacific: daylight time from the 2nd Sunday of March 2am to the 1st Sunday of November 2am
local function pacificDay(t)
  local y = yearOf(math.floor(t / 86400))
  local on = (sundayOnOrAfter(daysFromCivil(y, 3, 1)) + 7) * 86400 + 10 * 3600
  local off = sundayOnOrAfter(daysFromCivil(y, 11, 1)) * 86400 + 9 * 3600
  local shift = (t >= on and t < off) and -7 * 3600 or -8 * 3600
  return math.floor((t + shift) / 86400), shift
end

-- ---------- the board ----------
local function rng(seed)
  local s = 7
  for i = 1, #seed do s = (s * 31 + seed:byte(i)) % 2147483646 + 1 end
  return function(n) s = (s * 48271) % 2147483647; return s % n end
end
local function board(day, lvl, fac)
  local r = rng("hated-daily-" .. D.version .. "|" .. day .. "|" .. lvl .. "|" .. fac)
  local pool = {}
  for _, d in ipairs(D.dungeons) do if lvl >= d.lo and lvl <= d.hi and (d.fac == "" or d.fac == fac) then pool[#pool + 1] = d end end
  local b = { tasks = {} }
  if #pool > 0 then b.dungeon = pool[r(#pool) + 1] end
  local cand = {}
  for _, t in ipairs(D.tasks) do if lvl >= t.min then cand[#cand + 1] = t end end
  for _ = 1, D.perDay do
    if #cand == 0 then break end
    b.tasks[#b.tasks + 1] = table.remove(cand, r(#cand) + 1)
  end
  return b
end
HatedTCGDaily_PacificDay, HatedTCGDaily_Board = pacificDay, board   -- (also used by the tests)

-- which dungeon we're in (by its instance map id when known, else its name)
local function norm(s) return ((s or ""):lower():gsub("^the ", ""):gsub("[^a-z]", "")) end
function HatedTCGDaily_DungeonKey()
  if not GetInstanceInfo then return "" end
  local name, instType, _, _, _, _, _, instId = GetInstanceInfo()
  if instType ~= "party" then return "" end
  for _, d in ipairs(D.dungeons) do if d.map and d.map == instId then return d.key end end
  local n = norm(name)
  for _, d in ipairs(D.dungeons) do
    if norm(d.name) == n then return d.key end
    for _, a in ipairs(d.alts) do if norm(a) == n then return d.key end end
  end
  return ""
end

-- ---------- progress (today only, per character) ----------
local function state(char, day, lvl, fac)
  HatedCompanionDB = HatedCompanionDB or {}
  local all = HatedCompanionDB.daily or {}; HatedCompanionDB.daily = all
  local s = all[char]
  if not s or s.day ~= day then s = { day = day, lvl = lvl, fac = fac, prog = {}, done = {} }; all[char] = s end
  return s
end
local UI
local function bump(p, k, n) p[k] = (p[k] or 0) + (n or 1) end
local function taskCount(p, t)
  if t.kind == "type" then return p["type:" .. t.param] or 0 end
  return p[t.kind] or 0
end
local function dungeonDone(p, d)
  if not d or (p["boss:" .. d.key] or 0) < d.bosses then return false end
  for k, n in pairs(p) do
    local key, inst = k:match("^bmap:([^:]+):(%d+)$")
    if key == d.key and (not d.map or tonumber(inst) == d.map) and (p["map:" .. inst] or 0) >= D.dungeonTrash then return true end
  end
  return false
end
local function celebrate(text, points)
  say(string.format("|cffffd36aDaily complete:|r %s  |cff5afff2+%d|r (sync on the website to bank it)", text, points))
  if UIErrorsFrame then UIErrorsFrame:AddMessage("Daily complete: " .. text .. "  +" .. points, TEAL[1], TEAL[2], TEAL[3]) end
  if PlaySound and SOUNDKIT then pcall(PlaySound, SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01 or SOUNDKIT.IG_QUEST_LIST_COMPLETE or 878) end
end
local function check(s)
  local b = board(s.day, s.lvl, s.fac)
  if b.dungeon and not s.done.dungeon and dungeonDone(s.prog, b.dungeon) then s.done.dungeon = true; celebrate(b.dungeon.name, D.dungeonPoints) end
  for _, t in ipairs(b.tasks) do
    if not s.done[t.id] and taskCount(s.prog, t) >= t.need then s.done[t.id] = true; celebrate((t.label:gsub("{n}", t.need)), t.points) end
  end
end
-- from HatedTCG.lua, as each kill is logged:
--   m: { t, char, plvl, fac, ctype, cls, first, inst }      b: { t, char, plvl, fac, key, inst, raid }
function HatedTCGDaily_Note(kind, e)
  local day = pacificDay(e.t)
  local s = state(e.char, day, e.plvl, e.fac)
  local p = s.prog
  if kind == "m" then
    bump(p, "any")
    if e.ctype and e.ctype ~= "" then bump(p, "type:" .. e.ctype) end
    if e.cls == "elite" or e.cls == "rareelite" or e.cls == "worldboss" then bump(p, "elite") end
    if e.cls == "rare" or e.cls == "rareelite" then bump(p, "rare") end
    if e.first then bump(p, "first") end
    if e.inst and e.inst > 0 then bump(p, "map:" .. e.inst) end
  elseif kind == "b" and not e.raid and e.key and e.key ~= "" then
    bump(p, "boss:" .. e.key)
    bump(p, "bmap:" .. e.key .. ":" .. (e.inst or 0))
  end
  check(s)
  if UI and UI:IsVisible() then UI.refresh() end
end

-- ---------- the panel (inside the Hated TCG window: HatedTCG.lua places it) ----------
local ICON = {
  dungeon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
  beast = "Interface\\Icons\\Ability_Hunter_Pet_Bear", humanoid = "Interface\\Icons\\INV_Misc_Head_Human_01",
  undead = "Interface\\Icons\\Spell_Shadow_RaiseDead", elemental = "Interface\\Icons\\Spell_Nature_EarthElemental_Totem",
  demon = "Interface\\Icons\\Spell_Shadow_SummonImp", elite = "Interface\\Icons\\Ability_Warrior_Challange",
  rare = "Interface\\Icons\\INV_Misc_Gem_Diamond_01", first = "Interface\\Icons\\INV_Misc_Spyglass_02",
  any = "Interface\\Icons\\Ability_DualWield",
}
local GOLD = { 1, 0.83, 0.42 }
local HOW = {
  type = "Kills of this creature type that give experience (no grey mobs).",
  elite = "Elite, rare elite or world boss kills.",
  rare = "A rare or rare elite creature.",
  first = "Creatures this account has never killed before (on any character).",
  any = "Any kill that gives experience (no grey mobs).",
}
local PAID = "Checked and paid by the website when you sync (up to 7 days later)."
local function flat(fr, r, g, b, a, er, eg, eb, ea)
  fr:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  fr:SetBackdropColor(r, g, b, a); fr:SetBackdropBorderColor(er, eg, eb, ea)
end
local ROW_H, PANEL_W = 46, 396
local function makeRow(panel, i)
  local r = CreateFrame("Button", nil, panel, "BackdropTemplate")
  r:SetSize(PANEL_W, ROW_H); r:SetPoint("TOPLEFT", 0, -22 - (i - 1) * (ROW_H + 4))
  flat(r, 0.02, 0.05, 0.05, 0.75, 0.25, 0.95, 0.85, 0.22)
  r.edge = { 0.25, 0.95, 0.85, 0.22 }
  -- hover: a teal wash from the left, a bright edge and a slightly bigger icon
  r.glow = r:CreateTexture(nil, "BACKGROUND", nil, 2); r.glow:SetPoint("TOPLEFT", 1, -1); r.glow:SetPoint("BOTTOMRIGHT", -1, 1)
  r.glow:SetColorTexture(1, 1, 1, 1)
  if not (CreateColor and pcall(r.glow.SetGradient, r.glow, "HORIZONTAL", CreateColor(0.2, 0.9, 0.85, 0.3), CreateColor(0.2, 0.9, 0.85, 0))) then r.glow:SetColorTexture(0.2, 0.9, 0.85, 0.12) end
  r.glow:SetAlpha(0)
  r.iconBg = r:CreateTexture(nil, "ARTWORK"); r.iconBg:SetSize(36, 36); r.iconBg:SetPoint("LEFT", 6, 0); r.iconBg:SetColorTexture(0, 0, 0, 0.9)
  r.icon = r:CreateTexture(nil, "ARTWORK", nil, 1); r.icon:SetSize(34, 34); r.icon:SetPoint("CENTER", r.iconBg); r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  r.check = r:CreateTexture(nil, "OVERLAY"); r.check:SetSize(20, 20); r.check:SetPoint("BOTTOMRIGHT", r.iconBg, 6, -5)
  r.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
  r.label = r:CreateFontString(nil, "OVERLAY", "GameFontNormal"); r.label:SetPoint("TOPLEFT", r.iconBg, "TOPRIGHT", 10, -3); r.label:SetWidth(270); r.label:SetJustifyH("LEFT")
  r.pts = r:CreateFontString(nil, "OVERLAY"); r.pts:SetFont(STANDARD_TEXT_FONT, 15, "OUTLINE"); r.pts:SetPoint("TOPRIGHT", -10, -6)
  local bar = CreateFrame("StatusBar", nil, r); bar:SetPoint("BOTTOMLEFT", r.iconBg, "BOTTOMRIGHT", 10, 3); bar:SetSize(250, 8)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  local bg = bar:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.07)
  r.bar = bar
  r.count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.count:SetPoint("BOTTOMRIGHT", -10, 6)
  r:SetScript("OnEnter", function(self)
    self.glow:SetAlpha(1); self:SetBackdropBorderColor(TEAL[1], TEAL[2], TEAL[3], 0.9); self.icon:SetSize(36, 36)
    if self.tip then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(self.tip[1], 1, 1, 1)
      for k = 2, #self.tip do local l = self.tip[k]; GameTooltip:AddLine(l[1], l[2] or 0.85, l[3] or 0.85, l[4] or 0.85, true) end
      GameTooltip:Show()
    end
  end)
  r:SetScript("OnLeave", function(self)
    self.glow:SetAlpha(0); self:SetBackdropBorderColor(self.edge[1], self.edge[2], self.edge[3], self.edge[4]); self.icon:SetSize(34, 34)
    GameTooltip:Hide()
  end)
  return r
end
local function fill(r, icon, label, have, need, points, done, tip)
  r:Show()
  r.icon:SetTexture(icon); r.icon:SetDesaturated(done and true or false); r.icon:SetAlpha(done and 0.7 or 1)
  r.check:SetShown(done and true or false)
  r.label:SetText(label); r.label:SetTextColor(done and 0.6 or 1, done and 0.9 or 0.93, done and 0.62 or 0.82)
  r.pts:SetText("+" .. points)
  if done then r.pts:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) else r.pts:SetTextColor(TEAL[1], TEAL[2], TEAL[3]) end
  r.bar:SetMinMaxValues(0, need); r.bar:SetValue(math.min(have, need))
  if done then r.bar:SetStatusBarColor(GOLD[1], GOLD[2], GOLD[3], 0.9) else r.bar:SetStatusBarColor(TEAL[1], TEAL[2], TEAL[3], 0.85) end
  r.count:SetText(done and "|cffffd36aComplete|r" or (math.min(have, need) .. " / " .. need))
  r.edge = done and { GOLD[1], GOLD[2], GOLD[3], 0.45 } or { 0.25, 0.95, 0.85, 0.22 }
  r:SetBackdropBorderColor(r.edge[1], r.edge[2], r.edge[3], r.edge[4])
  r.tip = tip
end

-- the daily panel, built inside parent; returns it (it refreshes itself while shown)
function HatedTCGDaily_Panel(parent)
  local p = CreateFrame("Frame", nil, parent); p:SetSize(PANEL_W, 22 + 4 * (ROW_H + 4))
  local head = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); head:SetPoint("TOPLEFT", 2, -4); head:SetText("DAILY CHALLENGES")
  head:SetTextColor(0.5, 0.8, 0.76)
  p.sub = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); p.sub:SetPoint("TOPRIGHT", -2, -4); p.sub:SetJustifyH("RIGHT")
  p.rows = {}
  for i = 1, 4 do p.rows[i] = makeRow(p, i) end
  function p.refresh()
    local now = time()
    local day, shift = pacificDay(now)
    local char, lvl = UnitName("player"), UnitLevel("player")
    local fac = (UnitFactionGroup("player") or ""):sub(1, 1)
    local s = HatedCompanionDB and HatedCompanionDB.daily and HatedCompanionDB.daily[char]
    if not (s and s.day == day) then s = nil end
    local blvl = s and s.lvl or lvl
    local b = board(day, blvl, fac)
    local prog, done = s and s.prog or {}, s and s.done or {}
    local left = (day + 1) * 86400 - shift - now
    local n, total, earned, i = 0, 0, 0, 0
    if b.dungeon then
      i = 1; total = 1
      local d = b.dungeon
      local downs = math.min(prog["boss:" .. d.key] or 0, d.bosses)
      if done.dungeon then n = n + 1; earned = earned + D.dungeonPoints end
      fill(p.rows[1], ICON.dungeon, "Clear |cffffd36a" .. d.name .. "|r", downs, d.bosses, D.dungeonPoints, done.dungeon, {
        d.name,
        { string.format("Levels %d-%d%s", d.lo, d.hi, d.fac == "H" and "  (Horde)" or d.fac == "A" and "  (Alliance)" or ""), GOLD[1], GOLD[2], GOLD[3] },
        { string.format("Defeat %d of its bosses, plus at least %d other kills inside, on this character today.", d.bosses, D.dungeonTrash) },
        { string.format("Bosses down: %d / %d", downs, d.bosses), TEAL[1], TEAL[2], TEAL[3] },
        { PAID, 0.5, 0.65, 0.62 },
      })
    end
    for _, t in ipairs(b.tasks) do
      i = i + 1; total = total + 1
      if done[t.id] then n = n + 1; earned = earned + t.points end
      local label = (t.label:gsub("{n}", t.need))
      fill(p.rows[i], ICON[t.id] or ICON.any, label, taskCount(prog, t), t.need, t.points, done[t.id], {
        label, { HOW[t.kind] or "" },
        { string.format("Progress: %d / %d", math.min(taskCount(prog, t), t.need), t.need), TEAL[1], TEAL[2], TEAL[3] },
        { PAID, 0.5, 0.65, 0.62 },
      })
    end
    for k = i + 1, 4 do p.rows[k]:Hide() end
    p.sub:SetText(string.format("%s%d/%d done|r  |cff5afff2+%d|r   |cff6f8f8aLv %d%s - new in %dh %dm|r",
      (n == total and total > 0) and "|cffffd36a" or "|cffe8f6f3", n, total, earned, blvl, s and "" or " (locks at first kill)",
      math.floor(left / 3600), math.floor(left % 3600 / 60)))
  end
  p:SetScript("OnShow", p.refresh)
  C_Timer.NewTicker(30, function() if p:IsVisible() then p.refresh() end end)
  UI = p
  return p
end
