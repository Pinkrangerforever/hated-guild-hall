--[[ Hated Companion
  Records the guild bank for the Hated guild website (hatedforever.com > Guild Bank > Import).

  When the guild bank opens it:
    1. asks the server for every tab you can see, then records each tab's items (link, name, count, quality)
       and the bank's gold;
    2. reads the money log (deposits, withdrawals, repairs) and adds the transactions it hasn't seen before
       to a running history. WoW only keeps the last ~25 money transactions and gives each a rough age
       ("3 days ago"), so the history is built up scan by scan: open the bank now and then so nothing
       scrolls out of the log between scans.

  WoW writes the data to WTF\Account\<ACCOUNT>\SavedVariables\HatedCompanion.lua when you /reload or log out.
  That file is what the website's Import button reads.

  /hc        show the last scan
  /hc scan   scan again (with the guild bank open)
]]

local ADDON = "Hated Companion"
local SLOTS_PER_TAB = 98            -- MAX_GUILDBANK_SLOTS_PER_TAB
local MONEY_LOG_TAB = 9             -- QueryGuildBankLog(MAX_GUILDBANK_TABS + 1) is the money log

HatedCompanionDB = HatedCompanionDB or {}

local function say(msg) DEFAULT_CHAT_FRAME:AddMessage("|cffd6a940" .. ADDON .. ":|r " .. msg) end
local function money(copper)
  copper = copper or 0
  return string.format("%dg %ds %dc", math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

-- one record per guild (alts in other guilds don't mix)
local function guildDB()
  local guild = GetGuildInfo("player")
  if not guild then return nil end
  local db = HatedCompanionDB
  db.version = 1
  if not db.installId then   -- tells this copy's log entries apart from anyone else's
    db.installId = string.format("%s-%d-%d", (UnitName("player") or "x"), time(), math.random(100000, 999999))
  end
  db.guilds = db.guilds or {}
  db.guilds[guild] = db.guilds[guild] or { moneyLog = {}, nextId = 1 }
  return db.guilds[guild], guild
end

-- ---------- the bank's items ----------
local function scanItems()
  local g, guild = guildDB(); if not g then return end
  local tabs = {}
  local total = 0
  for tab = 1, (GetNumGuildBankTabs() or 0) do
    local name, icon, isViewable = GetGuildBankTabInfo(tab)
    if isViewable then
      local items = {}
      for slot = 1, SLOTS_PER_TAB do
        local link = GetGuildBankItemLink(tab, slot)
        if link then
          local _, count, _, _, quality = GetGuildBankItemInfo(tab, slot)
          items[#items + 1] = {
            slot = slot,
            itemId = tonumber(link:match("item:(%d+)")),
            name = link:match("%[(.-)%]"),
            link = link,
            count = count or 1,
            quality = quality,
          }
          total = total + 1
        end
      end
      tabs[#tabs + 1] = { index = tab, name = name, icon = icon, items = items }
    end
  end
  g.bank = {
    scannedAt = time(),
    scannedBy = UnitName("player"),
    realm = GetRealmName(),
    guild = guild,
    money = GetGuildBankMoney(),
    tabs = tabs,
  }
  return #tabs, total
end

-- ---------- the money log ----------
-- Each scan sees the latest ~25 transactions, oldest first. The overlap with what we already have is found by
-- lining the new list up against the end of the history; only what comes after the overlap is new.
local function sig(e) return e.type .. "|" .. (e.name or "") .. "|" .. (e.amount or 0) end
local function scanMoneyLog()
  local g = guildDB(); if not g then return 0 end
  local now = time()
  local seen = {}
  local n = GetNumGuildBankMoneyTransactions() or 0
  for i = n, 1, -1 do   -- the log's last index is its oldest entry
    local kind, name, amount, years, months, days, hours = GetGuildBankMoneyTransaction(i)
    if kind then
      local age = (((years or 0) * 365 + (months or 0) * 30 + (days or 0)) * 24 + (hours or 0)) * 3600
      seen[#seen + 1] = { type = kind, name = name, amount = amount, t = now - age }
    end
  end
  local log = g.moneyLog
  -- the longest run at the end of the history that matches the start of what we see now
  local overlap = 0
  for k = math.min(#log, #seen), 1, -1 do
    local ok = true
    for j = 1, k do
      if sig(log[#log - k + j]) ~= sig(seen[j]) then ok = false; break end
    end
    if ok then overlap = k; break end
  end
  local added = 0
  for j = overlap + 1, #seen do
    local e = seen[j]
    e.id = HatedCompanionDB.installId .. "-" .. g.nextId
    g.nextId = g.nextId + 1
    log[#log + 1] = e
    added = added + 1
  end
  g.moneyScannedAt = now
  return added
end

-- ---------- driving the scan ----------
local f = CreateFrame("Frame")
local pending = false

local function fullScan()
  if pending then return end
  pending = true
  for tab = 1, (GetNumGuildBankTabs() or 0) do
    local _, _, isViewable = GetGuildBankTabInfo(tab)
    if isViewable then
      -- the server only sends a tab's items once it's asked; space the requests out a little
      C_Timer.After(0.25 * tab, function() QueryGuildBankTab(tab) end)
    end
  end
  C_Timer.After(0.2, function() QueryGuildBankLog(MONEY_LOG_TAB) end)
  -- give the server a moment to answer everything, then record it
  C_Timer.After(3 + 0.25 * (GetNumGuildBankTabs() or 0), function()
    pending = false
    if not GetGuildInfo("player") then return end
    local tabs, items = scanItems()
    local added = scanMoneyLog()
    say(string.format("scanned %d tab%s (%d stacks, %s in the bank); %d new money transaction%s. /reload or log out to save for the website.",
      tabs or 0, tabs == 1 and "" or "s", items or 0, money(GetGuildBankMoney()), added, added == 1 and "" or "s"))
  end)
end

-- the money log can also arrive on its own (e.g. after a deposit while the bank is open)
local function onLog()
  if pending then return end
  local added = scanMoneyLog()
  if added > 0 then say(string.format("%d new money transaction%s recorded.", added, added == 1 and "" or "s")) end
end

local function safeRegister(event) pcall(f.RegisterEvent, f, event) end
safeRegister("GUILDBANKFRAME_OPENED")
safeRegister("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
safeRegister("GUILDBANKLOG_UPDATE")
f:SetScript("OnEvent", function(_, event, arg)
  if event == "GUILDBANKFRAME_OPENED" then
    fullScan()
  elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
    if Enum and Enum.PlayerInteractionType and arg == Enum.PlayerInteractionType.GuildBanker then fullScan() end
  elseif event == "GUILDBANKLOG_UPDATE" then
    onLog()
  end
end)

-- ---------- /hc ----------
SLASH_HATEDCOMPANION1 = "/hc"
SLASH_HATEDCOMPANION2 = "/hatedcompanion"
SlashCmdList.HATEDCOMPANION = function(msg)
  msg = (msg or ""):lower()
  if msg == "scan" then
    if GuildBankFrame and GuildBankFrame:IsShown() then fullScan() else say("open the guild bank first.") end
    return
  end
  local g, guild = guildDB()
  if not g then say("you're not in a guild.") return end
  if not g.bank then say("no scan yet: open the guild bank.") return end
  local deposits = 0
  for _, e in ipairs(g.moneyLog) do if e.type == "deposit" then deposits = deposits + 1 end end
  say(string.format("%s: last scan %s by %s, %d tab%s, %s. Money history: %d entries (%d deposits).",
    guild, date("%Y-%m-%d %H:%M", g.bank.scannedAt), g.bank.scannedBy or "?", #g.bank.tabs, #g.bank.tabs == 1 and "" or "s",
    money(g.bank.money), #g.moneyLog, deposits))
end
