--[[ Hated Companion: TCG daily challenges
  Every character gets a board each day (midnight Pacific): one dungeon from its level bracket (250 points) and three
  smaller tasks (25-75). The board is picked here from the date, the character's level and faction, using the tables
  in HatedTCGDailyData.lua - no sync needed. The website picks the same board again when you sync and pays what the
  kill log proves (this window only shows progress).

  The board locks to the character's level at its first kill of the day, so levelling mid-day doesn't change it.
  /tcg daily   the daily window
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
  if UI and UI:IsShown() then UI.refresh() end
end

-- ---------- the window ----------
local function flat(fr, r, g, b, a, er, eg, eb, ea)
  fr:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  fr:SetBackdropColor(r, g, b, a); fr:SetBackdropBorderColor(er, eg, eb, ea)
end
local function build()
  if UI then return UI end
  local w = CreateFrame("Frame", "HatedTCGDailyFrame", UIParent, "BackdropTemplate"); w:Hide()
  w:SetSize(400, 330); w:SetPoint("CENTER", -230, 0); w:SetFrameStrata("HIGH"); w:SetToplevel(true)
  w:SetMovable(true); w:EnableMouse(true); w:RegisterForDrag("LeftButton"); w:SetClampedToScreen(true)
  w:SetScript("OnDragStart", w.StartMoving); w:SetScript("OnDragStop", w.StopMovingOrSizing)
  flat(w, 0.035, 0.055, 0.06, 0.97, 0.25, 0.95, 0.85, 0.7)
  tinsert(UISpecialFrames, "HatedTCGDailyFrame")
  local close = CreateFrame("Button", nil, w, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 2, 2)
  local title = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOPLEFT", 16, -14); title:SetText("Daily Challenges")
  title:SetTextColor(0.75, 1, 0.96)
  w.sub = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); w.sub:SetPoint("TOPLEFT", 16, -38); w.sub:SetWidth(368); w.sub:SetJustifyH("LEFT")
  w.rows = {}
  for i = 1, 4 do
    local y = -66 - (i - 1) * 56
    local r = CreateFrame("Frame", nil, w, "BackdropTemplate"); r:SetPoint("TOPLEFT", 12, y); r:SetSize(376, 50)
    flat(r, 0, 0, 0, 0.35, 0.25, 0.95, 0.85, 0.25)
    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontNormal"); r.label:SetPoint("TOPLEFT", 10, -8); r.label:SetWidth(280); r.label:SetJustifyH("LEFT")
    r.pts = r:CreateFontString(nil, "OVERLAY", "GameFontNormal"); r.pts:SetPoint("TOPRIGHT", -10, -8)
    local bar = CreateFrame("StatusBar", nil, r); bar:SetPoint("BOTTOMLEFT", 10, 9); bar:SetSize(290, 10)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8"); bar:SetStatusBarColor(TEAL[1], TEAL[2], TEAL[3], 0.85)
    local bg = bar:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.08)
    r.bar = bar
    r.count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.count:SetPoint("BOTTOMRIGHT", -10, 7)
    w.rows[i] = r
  end
  w.foot = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); w.foot:SetPoint("BOTTOMLEFT", 16, 12); w.foot:SetWidth(368); w.foot:SetJustifyH("LEFT")
  w.foot:SetText("Progress here is the addon's count; the website checks your kills and pays when you sync (up to 7 days later).")

  local function setRow(r, label, have, need, points, done)
    r:Show()
    r.label:SetText((done and "|cff5aff7a\226\156\147|r " or "") .. label)
    r.label:SetTextColor(done and 0.6 or 1, done and 1 or 0.93, done and 0.65 or 0.8)
    r.pts:SetText("|cff5afff2+" .. points .. "|r")
    r.bar:SetMinMaxValues(0, need); r.bar:SetValue(math.min(have, need))
    r.count:SetText(done and "done" or (math.min(have, need) .. " / " .. need))
  end
  w.refresh = function()
    local now = time()
    local day, shift = pacificDay(now)
    local char, lvl = UnitName("player"), UnitLevel("player")
    local fac = (UnitFactionGroup("player") or ""):sub(1, 1)
    local s = HatedCompanionDB and HatedCompanionDB.daily and HatedCompanionDB.daily[char]
    if not (s and s.day == day) then s = nil end
    local b = board(day, s and s.lvl or lvl, fac)
    local left = (day + 1) * 86400 - shift - now
    w.sub:SetText(string.format("%s, level %d%s   |cff7fb5adNew board in %dh %dm|r", char, s and s.lvl or lvl,
      s and "" or " (locks at your first kill today)", math.floor(left / 3600), math.floor(left % 3600 / 60)))
    local p, done = s and s.prog or {}, s and s.done or {}
    local i = 0
    if b.dungeon then
      i = 1
      local d = b.dungeon
      setRow(w.rows[1], string.format("Clear |cffffd36a%s|r (defeat %d bosses)", d.name, d.bosses), math.min(p["boss:" .. d.key] or 0, d.bosses), d.bosses, D.dungeonPoints, done.dungeon)
    end
    for _, t in ipairs(b.tasks) do
      i = i + 1
      setRow(w.rows[i], (t.label:gsub("{n}", t.need)), taskCount(p, t), t.need, t.points, done[t.id])
    end
    for k = i + 1, 4 do w.rows[k]:Hide() end
  end
  w:SetScript("OnShow", function() w.refresh() end)
  C_Timer.NewTicker(30, function() if w:IsShown() then w.refresh() end end)
  UI = w
  return w
end
function HatedTCGDaily_Toggle(open)
  local w = build()
  if w:IsShown() and not open then w:Hide() else w:Show() end
end
