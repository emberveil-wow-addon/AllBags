--[[--------------------------------------------------------------------
  AllBags — Vault 1.2.0
  Client 1.12.1 / Lua 5.1 (Emberveil).

  What every other character on the account is carrying. The client only ever
  tells an addon about the character being played, so the only way to answer
  "who has the linen cloth" is to write down what we see while we see it and
  keep that between sessions.

  Three sources, three moments:
    * bags   — while playing, whenever they change;
    * bank   — only while the banker's window is open, that is the one moment
               the client hands over bank slots at all;
    * worn   — on login and whenever the player's equipment changes.

  This is a SECOND file of the same addon rather than more code in
  AllBags.lua: the locals limit is per chunk, and that file is at 134 of 200.
  Widget references live in tables here for the same reason.

  One honest limitation, already measured on this server: for bank slots the
  client returns a stack size of ZERO. Icon, quality and link arrive fine, the
  number does not. A remembered bank therefore shows items without counts.
----------------------------------------------------------------------]]

local ADDON   = "AllBags"
local VERSION = "1.2.0"

local FIRST_BAG, LAST_BAG = 0, 4
local BANK_PANEL          = -1
local BANK_PANEL_SLOTS    = 24     -- GetContainerNumSlots(-1) answers 0 here
local FIRST_BANK, LAST_BANK = 5, 10
local GEAR_SLOTS          = 19

local SIZE, GAP  = 32, 0
local COLS       = 10
local ROW_H      = 18
local LIST_W     = 156           -- the character column on the left
local PAD        = 12
local CONTENT_W  = COLS * SIZE + 12   -- right column: cells plus a margin
local TABS_Y     = -112          -- tab row; the skill line above it may wrap
local PICKS_Y    = 134           -- first character button, level with the grid
local GRID_Y     = -136

----------------------------------------------------------------------
-- localisation
----------------------------------------------------------------------

local S = {
  ru = {
    title    = "Другие персонажи",
    tabBags  = "Сумки",
    tabBank  = "Банк",
    tabGear  = "Надето",
    tabAuc   = "Аукцион",
    chars    = "Персонажи",
    nobody   = "пока никого не запомнил",
    noData   = "по этому персонажу тут ничего не записано",
    bankHint = "банк запоминается, когда открываешь его у банкира",
    gearHint = "надетое запоминается при входе и при смене вещей",
    bagsHint = "сумки запоминаются на ходу, пока играешь этим персонажем",
    aucHint  = "лоты запоминаются, когда открываешь свои продажи у аукционера",
    aucSum   = "лотов %d, выкуп %s",
    aucMore  = "показано %d из %d",
    aucNone  = "лотов не выставлено",
    allEmpty = "тут пусто",
    noBuy    = "без выкупа",
    tl1      = "<30м",
    tl2      = "<2ч",
    tl3      = "<8ч",
    tl4      = "<24ч",
    group    = "Группировать",
    groupTip = "Свести одинаковые вещи в одну ячейку. Выключено — как лежит в сумках",
    stacks   = "стопок: %d",
    level    = "%d уровень",
    money    = "Деньги",
    free     = "Место",
    when     = "снято: %s",
    never    = "никогда",
    ago      = "%s назад",
    days     = "%d дн",
    hours    = "%d ч",
    mins     = "%d мин",
    justNow  = "только что",
    here     = "играешь сейчас",
    profs    = "Умения",
    total    = "Всего у аккаунта",
    noCount  = "количество банк не отдаёт",
    close    = "Закрыть",
    forget   = "Забыть",
    forgetTip = "Убрать этого персонажа из хранилища. С Shift — забыть всех, кроме текущего",
    forgot   = "персонаж %s забыт.",
    noSelf   = "текущего персонажа забывать незачем — его снимок и так свежий.",
    forgotAll = "забыто персонажей: %d.",
    mVault   = "Другие персонажи...",
    slot1  = "Голова",   slot2  = "Шея",       slot3  = "Плечи",
    slot4  = "Рубаха",   slot5  = "Грудь",     slot6  = "Пояс",
    slot7  = "Ноги",     slot8  = "Ступни",    slot9  = "Кисти",
    slot10 = "Руки",     slot11 = "Палец",     slot12 = "Палец",
    slot13 = "Аксессуар", slot14 = "Аксессуар", slot15 = "Спина",
    slot16 = "Правая рука", slot17 = "Левая рука", slot18 = "Дальний бой",
    slot19 = "Табард",
    probeHead = "|cffffd700--- хранилище ---|r",
    probeChars = "персонажей: %d, текущий: %s",
    probeOne   = "%s: сумок %d, банк %d, надето %d, лотов %d, снято %s",
    probeApi   = "апи: GetInventoryItemLink %s, GetInventoryItemQuality %s, SetHyperlink %s",
    help     = "/bags vault — окно, /bags vault probe — что записано",
  },
  en = {
    title    = "Other characters",
    tabBags  = "Bags",
    tabBank  = "Bank",
    tabGear  = "Worn",
    tabAuc   = "Auction",
    chars    = "Characters",
    nobody   = "nobody remembered yet",
    noData   = "nothing is written down for this character here",
    bankHint = "the bank is remembered when you open it at a banker",
    gearHint = "worn gear is remembered on login and when it changes",
    bagsHint = "bags are remembered as you go, while playing that character",
    aucHint  = "auctions are remembered when you open your own lots at an auctioneer",
    aucSum   = "%d lots, buyout %s",
    aucMore  = "showing %d of %d",
    aucNone  = "nothing is up for auction",
    allEmpty = "nothing in here",
    noBuy    = "no buyout",
    tl1      = "<30m",
    tl2      = "<2h",
    tl3      = "<8h",
    tl4      = "<24h",
    group    = "Group",
    groupTip = "Merge identical items into one cell. Off - laid out as it lies in the bags",
    stacks   = "stacks: %d",
    level    = "level %d",
    money    = "Money",
    free     = "Free",
    when     = "taken: %s",
    never    = "never",
    ago      = "%s ago",
    days     = "%dd",
    hours    = "%dh",
    mins     = "%dm",
    justNow  = "just now",
    here     = "playing now",
    profs    = "Skills",
    total    = "Account total",
    noCount  = "the bank gives no stack sizes",
    close    = "Close",
    forget   = "Forget",
    forgetTip = "Drop this character from the vault. With Shift, forget everyone but the current one",
    forgot   = "character %s forgotten.",
    noSelf   = "no point forgetting the character being played - its snapshot is the live one.",
    forgotAll = "characters forgotten: %d.",
    mVault   = "Other characters...",
    slot1  = "Head",    slot2  = "Neck",     slot3  = "Shoulder",
    slot4  = "Shirt",   slot5  = "Chest",    slot6  = "Waist",
    slot7  = "Legs",    slot8  = "Feet",     slot9  = "Wrist",
    slot10 = "Hands",   slot11 = "Finger",   slot12 = "Finger",
    slot13 = "Trinket", slot14 = "Trinket",  slot15 = "Back",
    slot16 = "Main hand", slot17 = "Off hand", slot18 = "Ranged",
    slot19 = "Tabard",
    probeHead = "|cffffd700--- vault ---|r",
    probeChars = "characters: %d, current: %s",
    probeOne   = "%s: bags %d, bank %d, worn %d, lots %d, taken %s",
    probeApi   = "api: GetInventoryItemLink %s, GetInventoryItemQuality %s, SetHyperlink %s",
    help     = "/bags vault for the window, /bags vault probe for what is stored",
  },
}

local function Lang()
  local pick = AllBagsDB and AllBagsDB.lang or "auto"
  if pick == "ru" or pick == "en" then return pick end
  if GetLocale and GetLocale() == "ruRU" then return "ru" end
  return "en"
end

local function L(key) return S[Lang()][key] or key end
-- six slots: the probe line grew one when the auction tab arrived
local function Lf(key, a, b, c, d, e, f)
  return string.format(L(key), a, b, c, d, e, f)
end

local function Print(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00" .. ADDON .. ":|r " .. msg)
  end
end

----------------------------------------------------------------------
-- small helpers
----------------------------------------------------------------------

local QUALITY_FALLBACK = {
  [0] = { 0.62, 0.62, 0.62 },
  [1] = { 1.00, 1.00, 1.00 },
  [2] = { 0.12, 1.00, 0.00 },
  [3] = { 0.00, 0.44, 0.87 },
  [4] = { 0.64, 0.21, 0.93 },
  [5] = { 1.00, 0.50, 0.00 },
  [6] = { 0.90, 0.80, 0.50 },
}

-- The colour code a link carries is a second source of quality, for the
-- moments when GetInventoryItemQuality is not registered on this client.
local COLOUR_QUALITY = {
  ["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2, ["0070dd"] = 3,
  ["a335ee"] = 4, ["ff8000"] = 5, ["e6cc80"] = 6,
}

local function QualityColor(q)
  if q and GetItemQualityColor then
    local r, g, b = GetItemQualityColor(q)
    if type(r) == "number" then return r, g, b end
  end
  local c = QUALITY_FALLBACK[q or 1] or QUALITY_FALLBACK[1]
  return c[1], c[2], c[3]
end

local function LinkName(link)
  if type(link) ~= "string" then return nil end
  local _, _, name = string.find(link, "%[(.+)%]")
  return name
end

-- just the item part, "item:2589:0:0:0" -- a whole link with its colour and
-- brackets would triple the size of the saved file for no gain
local function LinkString(link)
  if type(link) ~= "string" then return nil end
  local _, _, s = string.find(link, "|H(item[^|]*)|h")
  return s
end

local function LinkQuality(link)
  if type(link) ~= "string" then return nil end
  local _, _, hex = string.find(link, "|c%x%x(%x%x%x%x%x%x)")
  return hex and COLOUR_QUALITY[string.lower(hex)] or nil
end

-- Everything worth keeping about one item, and nothing else.
local function Entry(link, texture, count, quality)
  if not texture or texture == "" then return nil end
  return {
    n = LinkName(link),
    t = texture,
    q = quality or LinkQuality(link) or 1,
    c = count or 0,
    s = LinkString(link),
  }
end

local function Count(t)
  if type(t) ~= "table" then return 0 end
  local n = 0
  while t[n + 1] ~= nil do n = n + 1 end
  return n
end

-- gear is keyed by slot id and full of holes, so the array walk above lies
local function Filled(t)
  if type(t) ~= "table" then return 0 end
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

-- The class is worth a glance in the character list, and its colour tells it
-- faster than the word does. RAID_CLASS_COLORS is not to be relied on here.
local CLASS_HEX = {
  WARRIOR = "c79c6e", PALADIN = "f58cba", HUNTER = "abd473",
  ROGUE   = "fff569", PRIEST  = "ffffff", SHAMAN = "0070de",
  MAGE    = "69ccf0", WARLOCK = "9482c9", DRUID  = "ff7d0a",
}

local function ClassHex(token)
  return (token and CLASS_HEX[token]) or "9d9d9d"
end

local function Money(copper)
  copper = copper or 0
  local g = math.floor(copper / 10000)
  local s = math.floor(copper / 100) - g * 100
  local c = copper - math.floor(copper / 100) * 100
  local out = ""
  if g > 0 then out = out .. "|cffffd700" .. g .. "g|r " end
  if g > 0 or s > 0 then out = out .. "|cffc7c7cf" .. s .. "s|r " end
  return out .. "|cffeda55f" .. c .. "c|r"
end

local function Ago(stamp)
  if type(stamp) ~= "number" or stamp <= 0 then return L("never") end
  local now = (time and time()) or 0
  local d = now - stamp
  if d < 60 then return L("justNow") end
  if d < 3600 then return Lf("ago", Lf("mins", math.floor(d / 60))) end
  if d < 86400 then return Lf("ago", Lf("hours", math.floor(d / 3600))) end
  return Lf("ago", Lf("days", math.floor(d / 86400)))
end

----------------------------------------------------------------------
-- the store
----------------------------------------------------------------------

local function MyKey()
  local name = (UnitName and UnitName("player")) or "?"
  local realm = (GetRealmName and GetRealmName()) or "?"
  return name .. " - " .. realm
end

local function InitVault()
  if type(AllBagsVault) ~= "table" then AllBagsVault = {} end
  if type(AllBagsVault.chars) ~= "table" then AllBagsVault.chars = {} end
  return AllBagsVault
end

-- The flag lives in the vault's own saved table, not in AllBagsDB: this file
-- must stand on its own, and grouping is the useful default.
local function GroupOn()
  local v = InitVault()
  if v.group == nil then v.group = true end
  return v.group and true or false
end

local function MyRecord()
  local v = InitVault()
  local key = MyKey()
  local rec = v.chars[key]
  if type(rec) ~= "table" then
    rec = { key = key }
    v.chars[key] = rec
  end
  rec.name = (UnitName and UnitName("player")) or "?"
  rec.realm = (GetRealmName and GetRealmName()) or "?"
  return rec
end

-- Sorted list of remembered characters, the one being played first.
local function CharKeys()
  local v = InitVault()
  local keys, n = {}, 0
  for key in pairs(v.chars) do
    n = n + 1
    keys[n] = key
  end
  table.sort(keys)

  local mine = MyKey()
  local out, m = {}, 0
  if v.chars[mine] then m = 1; out[1] = mine end
  local i = 1
  while i <= n do
    if keys[i] ~= mine then m = m + 1; out[m] = keys[i] end
    i = i + 1
  end
  return out, m
end

local function Forget(key)
  local v = InitVault()
  if not key or not v.chars[key] then return false end
  v.chars[key] = nil
  return true
end

local function ForgetOthers()
  local v = InitVault()
  local mine, n = MyKey(), 0
  for key in pairs(v.chars) do
    if key ~= mine then n = n + 1 end
  end
  local keep = v.chars[mine]
  v.chars = {}
  if keep then v.chars[mine] = keep end
  return n
end

----------------------------------------------------------------------
-- taking the snapshots
----------------------------------------------------------------------

local function SnapContainer(bag, forced)
  local size = forced or (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
  if not size or size < 1 then return nil, 0, 0 end

  local t, free = { size = size }, 0
  local slot = 1
  while slot <= size do
    local tex, count, _, quality = GetContainerItemInfo(bag, slot)
    if tex and tex ~= "" then
      t[slot] = Entry(GetContainerItemLink(bag, slot), tex, count, quality)
    else
      free = free + 1
    end
    slot = slot + 1
  end
  return t, free, size
end

local function SnapBags()
  local rec = MyRecord()
  local bags, free, slots = {}, 0, 0
  local bag = FIRST_BAG
  while bag <= LAST_BAG do
    local t, f, s = SnapContainer(bag)
    if t then
      bags[bag] = t
      free = free + f
      slots = slots + s
    end
    bag = bag + 1
  end
  rec.bags = bags
  rec.free, rec.slots = free, slots
  rec.money = (GetMoney and GetMoney()) or rec.money
  rec.bagsAt = (time and time()) or 0
end

-- Only while the banker's window is open: that is the one moment the client
-- hands over bank slots. The panel's size has to be given by hand.
local function SnapBank()
  local rec = MyRecord()
  local bank = {}

  local panel = SnapContainer(BANK_PANEL, BANK_PANEL_SLOTS)
  if panel then bank[BANK_PANEL] = panel end

  local bag = FIRST_BANK
  while bag <= LAST_BANK do
    local t = SnapContainer(bag)
    if t then bank[bag] = t end
    bag = bag + 1
  end

  rec.bank = bank
  rec.bankAt = (time and time()) or 0
end

local function SnapGear()
  local rec = MyRecord()
  local gear = {}
  local s = 1
  while s <= GEAR_SLOTS do
    local tex = GetInventoryItemTexture and GetInventoryItemTexture("player", s)
    if tex and tex ~= "" then
      local link = GetInventoryItemLink and GetInventoryItemLink("player", s)
      local q = GetInventoryItemQuality and GetInventoryItemQuality("player", s)
      local e = Entry(link, tex, 1, q)
      -- an item with no link at all still deserves its icon in the picture
      if not e then e = { t = tex, q = 1, c = 1 } end
      gear[s] = e
    end
    s = s + 1
  end
  rec.gear = gear
  rec.gearAt = (time and time()) or 0
end

-- Professions and the like. The honest signal for "this is a profession, not
-- a weapon skill" is that a profession can be abandoned; where the client
-- does not answer that, the well known profession caps stand in.
-- Languages, weapon and armour proficiencies and class skills have no place
-- in a line about professions. This client keeps isAbandonable to itself, so
-- the group header above a line is the only honest signal, and the names
-- themselves ("Language: Orcish") give away the rest. Cyrillic does not
-- survive string.lower here, so the Russian needles are spelled the way the
-- client spells them and matched against the untouched text.
local SKILL_SKIP = {
  "language", "weapon", "armor", "armour", "class", "defense",
  "Язык", "язык",
  "Оруж", "оруж",
  "Доспех", "доспех",
  "Брон", "брон",
  "Класс", "класс",
  "Защит", "защит",
}

local function SkillSkipped(text)
  if type(text) ~= "string" or text == "" then return false end
  local low = string.lower(text)
  local i = 1
  while SKILL_SKIP[i] do
    local needle = SKILL_SKIP[i]
    if string.find(low, needle, 1, true) or string.find(text, needle, 1, true) then
      return true
    end
    i = i + 1
  end
  return false
end

local function SnapSkills()
  local rec = MyRecord()
  if type(GetNumSkillLines) ~= "function" or type(GetSkillLineInfo) ~= "function" then
    return
  end

  local list, n = {}, 0
  local group = ""
  local i, total = 1, GetNumSkillLines() or 0
  while i <= total do
    local name, header, _, rank, _, _, maxRank, canAbandon = GetSkillLineInfo(i)
    if header then
      group = name or ""          -- everything below belongs to this group
    elseif name and rank and rank > 0 then
      local keep = false
      if canAbandon ~= nil then
        keep = canAbandon and true or false
      else
        keep = (maxRank == 75 or maxRank == 150 or maxRank == 225 or maxRank == 300)
      end
      if keep and (SkillSkipped(group) or SkillSkipped(name)) then keep = false end
      if keep then
        n = n + 1
        list[n] = { n = name, r = rank, m = maxRank or rank }
      end
    end
    i = i + 1
  end
  rec.skills = list
end

-- What this character has up for auction. The owner list is only readable
-- while the auction window is open and only after the client has queried it,
-- which is exactly what AUCTION_OWNED_LIST_UPDATE announces.
local function SnapAuction()
  if type(GetNumAuctionItems) ~= "function"
     or type(GetAuctionItemInfo) ~= "function" then
    return
  end

  local rec = MyRecord()
  local batch, total = GetNumAuctionItems("owner")
  batch = batch or 0

  local list, n = {}, 0
  local i = 1
  while i <= batch do
    local name, tex, count, q, _, _, minBid, _, buyout, bidAmount =
      GetAuctionItemInfo("owner", i)
    if name then
      local link = GetAuctionItemLink and GetAuctionItemLink("owner", i)
      local tl = GetAuctionItemTimeLeft and GetAuctionItemTimeLeft("owner", i)
      local e = Entry(link, tex, count or 1, q)
      if not e then e = { n = name, t = tex, c = count or 1, q = q or 1 } end
      e.n   = e.n or name
      e.bid = minBid
      e.cur = bidAmount
      e.buy = buyout
      e.tl  = tl
      n = n + 1
      list[n] = e
    end
    i = i + 1
  end

  rec.auc = list
  rec.aucTotal = total or n
  rec.aucAt = (time and time()) or 0
end

local function SnapMeta()
  local rec = MyRecord()
  rec.level = (UnitLevel and UnitLevel("player")) or rec.level
  if UnitClass then
    -- two returns, so no "and" shortcut here: it would swallow the token
    local cl, token = UnitClass("player")
    if cl then rec.class = cl end
    if token then rec.ctoken = token end
  end
  rec.money = (GetMoney and GetMoney()) or rec.money
end

----------------------------------------------------------------------
-- the window
----------------------------------------------------------------------

-- Every widget lives in one of these tables. Dozens of separate locals is
-- exactly what filled AllBags.lua up to its limit.
local W = {}          -- named parts of the window
local Cell = {}       -- i -> cell of the bag/bank grid
local Row = {}        -- i -> row of the worn list
local Pick = {}       -- i -> button in the character column
local Auc  = {}       -- i -> row of the auction list

local View = {
  who = nil,          -- key of the character being shown
  tab = "bags",
  built = false,
}

local UpdateView

local function Tip(entry, owner)
  if not GameTooltip or not entry then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  local shown = false
  if entry.s and GameTooltip.SetHyperlink then
    local ok = pcall(function() GameTooltip:SetHyperlink(entry.s) end)
    if ok then shown = true end
  end
  if not shown then
    local r, g, b = QualityColor(entry.q)
    GameTooltip:AddLine(entry.n or "?", r, g, b)
    if entry.c and entry.c > 1 then
      GameTooltip:AddLine("x" .. entry.c, 0.8, 0.8, 0.8)
    end
    if entry.stacks and entry.stacks > 1 then
      GameTooltip:AddLine(Lf("stacks", entry.stacks), 0.6, 0.6, 0.6)
    end
  end
  GameTooltip:Show()
end

local function MakeFont(parent, size, r, g, b)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  if not fs:GetFont() or fs:GetFont() == "" then
    fs:SetFont("Fonts\\FRIZQT__.TTF", size, "")
  else
    pcall(function() fs:SetFont("Fonts\\FRIZQT__.TTF", size, "") end)
  end
  fs:SetJustifyH("LEFT")
  if r then fs:SetTextColor(r, g, b) end
  return fs
end

-- named on purpose: an unnamed button cannot be reached from the outside,
-- and that makes both the test bench and a live /script check impossible
-- A button needs a visible frame. Bare text reads as a label, not as
-- something to click, which is exactly how the first build of this window
-- looked in game.
local function Flat(parent, w, h, label, name, framed)
  local b = CreateFrame("Button", name, parent)
  b:SetWidth(w)
  b:SetHeight(h)
  b:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
  b:SetText(label or "")
  if framed then
    b:SetBackdrop({
      bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tileSize = 16, edgeSize = 10,
      insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    -- SetBackdrop resets the colours, so they go after it
    b:SetBackdropColor(0.1, 0.1, 0.1, 0.85)
    b:SetBackdropBorderColor(0.45, 0.45, 0.45, 0.9)
  end
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  return b
end

-- one cell of the bag or bank grid
local function GetCell(i)
  if Cell[i] then return Cell[i] end

  local b = CreateFrame("Button", "AllBagsVaultCell" .. i, W.grid)
  b:SetWidth(SIZE)
  b:SetHeight(SIZE)
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")

  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(b)
  bg:SetTexture(0.16, 0.16, 0.16, 1)

  local inner = b:CreateTexture(nil, "BORDER")
  inner:SetTexture(0.07, 0.07, 0.07, 1)
  inner:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
  inner:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)

  b:SetNormalTexture("")
  local icon = b.GetNormalTexture and b:GetNormalTexture()
  if icon then
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
  end

  local fs = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  fs:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
  fs:SetJustifyH("RIGHT")
  fs:SetTextColor(1, 1, 1)

  b:SetScript("OnEnter", function(self)
    self = self or this
    Tip(self.entry, self)
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

  Cell[i] = b
  b.bg, b.inner, b.icon, b.count = bg, inner, icon, fs
  return b
end

-- one line of the worn list: icon, slot name, item name
local function GetRow(i)
  if Row[i] then return Row[i] end

  local r = CreateFrame("Button", "AllBagsVaultRow" .. i, W.grid)
  r:SetHeight(ROW_H)
  r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

  local icon = r:CreateTexture(nil, "ARTWORK")
  icon:SetWidth(ROW_H - 2)
  icon:SetHeight(ROW_H - 2)
  icon:SetPoint("LEFT", r, "LEFT", 0, 0)

  local slot = MakeFont(r, 11, 0.55, 0.55, 0.55)
  slot:SetPoint("LEFT", r, "LEFT", ROW_H + 4, 0)
  slot:SetWidth(92)

  local item = MakeFont(r, 12, 1, 1, 1)
  item:SetPoint("LEFT", r, "LEFT", ROW_H + 100, 0)
  item:SetPoint("RIGHT", r, "RIGHT", -4, 0)

  r:SetScript("OnEnter", function(self)
    self = self or this
    Tip(self.entry, self)
  end)
  r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

  Row[i] = r
  r.icon, r.slotFS, r.itemFS = icon, slot, item
  return r
end

-- one lot: icon, name, price, time left
local function GetAucRow(i)
  if Auc[i] then return Auc[i] end

  local r = CreateFrame("Button", "AllBagsVaultAuc" .. i, W.grid)
  r:SetHeight(ROW_H)
  r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

  local icon = r:CreateTexture(nil, "ARTWORK")
  icon:SetWidth(ROW_H - 2)
  icon:SetHeight(ROW_H - 2)
  icon:SetPoint("LEFT", r, "LEFT", 0, 0)

  local name = MakeFont(r, 12, 1, 1, 1)
  name:SetPoint("LEFT", r, "LEFT", ROW_H + 4, 0)
  name:SetWidth(146)

  local price = MakeFont(r, 11, 0.8, 0.8, 0.8)
  price:SetPoint("LEFT", r, "LEFT", ROW_H + 152, 0)
  price:SetWidth(112)

  local tl = MakeFont(r, 11, 0.55, 0.55, 0.55)
  tl:SetPoint("LEFT", r, "LEFT", ROW_H + 266, 0)
  tl:SetWidth(44)
  tl:SetJustifyH("RIGHT")

  r:SetScript("OnEnter", function(self)
    self = self or this
    Tip(self.entry, self)
  end)
  r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

  Auc[i] = r
  r.icon, r.nameFS, r.priceFS, r.tlFS = icon, name, price, tl
  return r
end

local function GetPick(i)
  if Pick[i] then return Pick[i] end
  local b = Flat(W.frame, LIST_W - 8, ROW_H, "", "AllBagsVaultPick" .. i)
  b:SetPoint("TOPLEFT", W.frame, "TOPLEFT", PAD, -(PICKS_Y + (i - 1) * ROW_H))
  local fs = b.GetFontString and b:GetFontString()
  if fs then
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", b, "LEFT", 4, 0)
    fs:SetJustifyH("LEFT")
  end
  b:SetScript("OnClick", function(self)
    self = self or this
    if self.key then
      View.who = self.key
      UpdateView()
    end
  end)
  Pick[i] = b
  return b
end

local function Build()
  if View.built then return end
  View.built = true

  local f = CreateFrame("Frame", "AllBagsVaultFrame", UIParent)
  W.frame = f
  f:SetWidth(LIST_W + PAD * 2 + COLS * SIZE + 12)
  f:SetHeight(560)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  -- The dialog-box background came out see-through on this client: the world
  -- showed straight through the window. The tooltip background with an
  -- explicit colour is what the bag window itself uses, and it is opaque.
  f:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tileSize = 16, edgeSize = 14,
    insets   = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  f:SetBackdropColor(0, 0, 0, 0.94)
  f:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
  f:Hide()

  -- Escape closes it: the list holds names, so the frame needs one
  if type(UISpecialFrames) == "table" then
    local i, seen = 1, false
    while UISpecialFrames[i] do
      if UISpecialFrames[i] == "AllBagsVaultFrame" then seen = true end
      i = i + 1
    end
    if not seen then UISpecialFrames[i] = "AllBagsVaultFrame" end
  end

  -- RegisterForDrag answers on buttons only in this client
  local moving = false
  f:SetScript("OnMouseDown", function(self)
    self = self or this
    if not moving then moving = true; self:StartMoving() end
  end)
  f:SetScript("OnMouseUp", function(self)
    self = self or this
    if moving then
      moving = false
      self:StopMovingOrSizing()
      if AllBagsDB and self.GetLeft then
        AllBagsDB.vx, AllBagsDB.vy = self:GetLeft(), self:GetBottom()
      end
    end
  end)

  W.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  if not W.title:GetFont() or W.title:GetFont() == "" then
    W.title:SetFont("Fonts\\FRIZQT__.TTF", 13, "")
  end
  W.title:SetPoint("TOP", f, "TOP", 0, -16)
  W.title:SetTextColor(1, 0.82, 0)

  -- Two anchor points do not hold a line inside the window on this client:
  -- the skill line ran a good way past the right edge. An explicit width does
  -- hold, and lets the text wrap.
  W.charsFS = MakeFont(f, 11, 0.55, 0.55, 0.55)
  W.charsFS:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 4, TABS_Y)
  W.charsFS:SetWidth(LIST_W - 8)

  -- header of the chosen character
  W.who = MakeFont(f, 13, 1, 0.82, 0)
  W.who:SetPoint("TOPLEFT", f, "TOPLEFT", LIST_W + PAD, -40)
  W.who:SetWidth(CONTENT_W)

  W.meta = MakeFont(f, 11, 0.7, 0.7, 0.7)
  W.meta:SetPoint("TOPLEFT", f, "TOPLEFT", LIST_W + PAD, -58)
  W.meta:SetWidth(CONTENT_W)

  W.skills = MakeFont(f, 11, 0.6, 0.62, 0.55)
  W.skills:SetPoint("TOPLEFT", f, "TOPLEFT", LIST_W + PAD, -76)
  W.skills:SetWidth(CONTENT_W)
  W.skills:SetJustifyV("TOP")

  -- when the snapshot was taken belongs next to the picture, not glued onto
  -- the end of the hint at the bottom
  W.stamp = MakeFont(f, 11, 0.5, 0.5, 0.5)
  W.stamp:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD - 2, 30)
  W.stamp:SetWidth(150)
  W.stamp:SetJustifyH("RIGHT")

  -- tabs
  local tabs = {
    { "bags", "tabBags" }, { "bank", "tabBank" },
    { "gear", "tabGear" }, { "auc", "tabAuc" },
  }
  W.tab = {}
  local i = 1
  while tabs[i] do
    local id, key = tabs[i][1], tabs[i][2]
    local b = Flat(f, 74, 20, "", "AllBagsVaultTab" .. i, true)
    b:SetPoint("TOPLEFT", f, "TOPLEFT", LIST_W + PAD + (i - 1) * 78, TABS_Y)
    b:SetScript("OnClick", function()
      View.tab = id
      UpdateView()
    end)
    b.id, b.key = id, key
    W.tab[i] = b
    i = i + 1
  end

  -- the sheet the cells and rows live on
  W.grid = CreateFrame("Frame", "AllBagsVaultGrid", f)
  W.grid:SetPoint("TOPLEFT", f, "TOPLEFT", LIST_W + PAD, GRID_Y)
  W.grid:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 52)
  W.grid:SetBackdrop({
    bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  W.grid:SetBackdropColor(0, 0, 0, 0.6)

  W.empty = MakeFont(f, 12, 0.5, 0.5, 0.5)
  W.empty:SetPoint("TOPLEFT", W.grid, "TOPLEFT", 10, -10)
  W.empty:SetWidth(CONTENT_W - 20)
  W.empty:Hide()

  W.total = MakeFont(f, 11, 0.62, 0.62, 0.62)
  W.total:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD + 2, 50)
  W.total:SetWidth(LIST_W)
  W.total:SetJustifyH("LEFT")

  W.hint = MakeFont(f, 11, 0.5, 0.5, 0.5)
  W.hint:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD + 2, 30)
  W.hint:SetWidth(LIST_W + CONTENT_W - 160)   -- the stamp owns the right end

  -- what the lots add up to, when the auction tab is the one being looked at
  W.sum = MakeFont(f, 11, 0.75, 0.7, 0.5)
  W.sum:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD - 2, 50)
  W.sum:SetWidth(280)
  W.sum:SetJustifyH("RIGHT")

  W.forget = Flat(f, 90, 20, "", "AllBagsVaultForget", true)
  W.forget:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 12)
  W.forget:SetScript("OnClick", function()
    if IsShiftKeyDown and IsShiftKeyDown() then
      local n = ForgetOthers()
      Print(Lf("forgotAll", n))
      View.who = MyKey()
    else
      local key = View.who
      if key == MyKey() then
        Print(L("noSelf"))
        return
      end
      if Forget(key) then Print(Lf("forgot", key)) end
      View.who = MyKey()
    end
    UpdateView()
  end)
  W.forget:SetScript("OnEnter", function(self)
    self = self or this
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(L("forgetTip"))
    GameTooltip:Show()
  end)
  W.forget:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

  -- Grouping: a bag read as a list of what is in it, not as a map of where
  -- every stack lies. Off gives the honest slot-by-slot picture back.
  W.group = Flat(f, 132, 20, "", "AllBagsVaultGroup", true)
  W.group:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD + 96, 12)
  W.group:SetScript("OnClick", function()
    InitVault().group = not GroupOn()
    UpdateView()
  end)
  W.group:SetScript("OnEnter", function(self)
    self = self or this
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(L("groupTip"))
    GameTooltip:Show()
  end)
  W.group:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

  W.close = Flat(f, 80, 20, "", "AllBagsVaultClose", true)
  W.close:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 12)
  W.close:SetScript("OnClick", function() f:Hide() end)
end

----------------------------------------------------------------------
-- drawing
----------------------------------------------------------------------

-- flattens the containers of one source into a straight list of entries,
-- container by container, so the grid can be filled row by row
local function Flatten(store, order)
  local list, n = {}, 0
  local i = 1
  while order[i] do
    local bag = order[i]
    local t = store and store[bag]
    if t and t.size then
      local slot = 1
      while slot <= t.size do
        n = n + 1
        list[n] = t[slot]         -- nil for an empty slot, that is fine
        slot = slot + 1
      end
    end
    i = i + 1
  end
  return list, n
end

local BAG_ORDER  = { 0, 1, 2, 3, 4 }
local BANK_ORDER = { -1, 5, 6, 7, 8, 9, 10 }

-- Merges identical items into one cell and puts the best first. Insertion
-- sort by hand: a bag holds tens of lines, and table.sort with a comparator
-- is the one thing this client has bitten us with before.
local function Group(list, n)
  local out, m, index = {}, 0, {}
  local i = 1
  while i <= n do
    local e = list[i]
    if e then
      local key = (e.n or "?") .. "#" .. tostring(e.q or 1)
      local at = index[key]
      if at then
        local g = out[at]
        g.c = (g.c or 0) + (e.c or 0)
        g.stacks = (g.stacks or 1) + 1
      else
        m = m + 1
        index[key] = m
        out[m] = { n = e.n, t = e.t, q = e.q, c = e.c or 0, s = e.s, stacks = 1 }
      end
    end
    i = i + 1
  end

  local a = 2
  while a <= m do
    local held = out[a]
    local b = a - 1
    while b >= 1 do
      local x = out[b]
      local qx, qh = x.q or 1, held.q or 1
      local after = (qh > qx) or (qh == qx and (held.n or "") < (x.n or ""))
      if not after then break end
      out[b + 1] = x
      b = b - 1
    end
    out[b + 1] = held
    a = a + 1
  end
  return out, m
end

local function TimeLeft(tl)
  if type(tl) ~= "number" or tl < 1 or tl > 4 then return "" end
  return L("tl" .. tl)
end

local AUC_ROWS = 20

local function DrawAuc(rec)
  local list = rec and rec.auc
  local n = Count(list)
  local shown, sum = 0, 0

  local i = 1
  while i <= n do
    local e = list[i]
    if type(e.buy) == "number" then sum = sum + e.buy end
    if shown < AUC_ROWS then
      shown = shown + 1
      local r = GetAucRow(shown)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", W.grid, "TOPLEFT", 8, -6 - (shown - 1) * ROW_H)
      r:SetPoint("TOPRIGHT", W.grid, "TOPRIGHT", -8, -6 - (shown - 1) * ROW_H)

      r.entry = e
      r.icon:SetTexture(e.t)
      r.icon:Show()

      local cr, cg, cb = QualityColor(e.q)
      local label = e.n or "?"
      if e.c and e.c > 1 then label = label .. " |cff808080x" .. e.c .. "|r" end
      r.nameFS:SetText(label)
      r.nameFS:SetTextColor(cr, cg, cb)

      if type(e.buy) == "number" and e.buy > 0 then
        r.priceFS:SetText(Money(e.buy))
      elseif type(e.bid) == "number" then
        r.priceFS:SetText("|cff808080" .. L("noBuy") .. "|r " .. Money(e.bid))
      else
        r.priceFS:SetText("")
      end

      r.tlFS:SetText(TimeLeft(e.tl))
      r:Show()
    end
    i = i + 1
  end

  local k = shown + 1
  while Auc[k] do Auc[k]:Hide(); Auc[k].entry = nil; k = k + 1 end
  k = 1
  while Cell[k] do Cell[k]:Hide(); Cell[k].entry = nil; k = k + 1 end
  k = 1
  while Row[k] do Row[k]:Hide(); k = k + 1 end

  local total = rec and rec.aucTotal or n
  local line = Lf("aucSum", n, Money(sum))
  if type(total) == "number" and total > n then
    line = line .. "   |cff808080" .. Lf("aucMore", n, total) .. "|r"
  end
  W.sum:SetText(n > 0 and line or "")
  return n
end

local function DrawGrid(list, n, showCounts, grouped)
  local i = 1
  while i <= n do
    local c = GetCell(i)
    local e = list[i]
    local row = math.floor((i - 1) / COLS)
    local col = (i - 1) - row * COLS
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", W.grid, "TOPLEFT", 6 + col * (SIZE + GAP), -6 - row * (SIZE + GAP))

    c.entry = e
    if e then
      c:SetNormalTexture(e.t)
      if c.icon then
        c.icon:ClearAllPoints()
        c.icon:SetPoint("TOPLEFT", c, "TOPLEFT", 1, -1)
        c.icon:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -1, 1)
      end
      if c.inner then c.inner:Hide() end
      if e.q and e.q > 1 then
        local r, g, b = QualityColor(e.q)
        c.bg:SetTexture(r, g, b, 1)
      else
        c.bg:SetTexture(0.16, 0.16, 0.16, 1)
      end
      if showCounts then
        if e.c and e.c > 1 then c.count:SetText(e.c) else c.count:SetText("") end
      elseif grouped and e.stacks and e.stacks > 1 then
        -- the bank hands over no stack sizes at all on this server, so a
        -- merged cell shows how many stacks went into it instead
        c.count:SetText(e.stacks)
      else
        c.count:SetText("")
      end
    else
      c:SetNormalTexture("")
      if c.inner then c.inner:Show() end
      c.bg:SetTexture(0.16, 0.16, 0.16, 1)
      c.count:SetText("")
    end
    c:Show()
    i = i + 1
  end

  local k = n + 1
  while Cell[k] do Cell[k]:Hide(); Cell[k].entry = nil; k = k + 1 end
  k = 1
  while Row[k] do Row[k]:Hide(); k = k + 1 end
  k = 1
  while Auc[k] do Auc[k]:Hide(); Auc[k].entry = nil; k = k + 1 end
end

local function DrawGear(gear)
  local shown = 0
  local s = 1
  while s <= GEAR_SLOTS do
    local e = gear and gear[s]
    shown = shown + 1
    local r = GetRow(shown)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", W.grid, "TOPLEFT", 8, -6 - (shown - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", W.grid, "TOPRIGHT", -8, -6 - (shown - 1) * ROW_H)

    r.slotFS:SetText(L("slot" .. s))
    r.entry = e
    if e then
      r.icon:SetTexture(e.t)
      r.icon:Show()
      local cr, cg, cb = QualityColor(e.q)
      r.itemFS:SetText(e.n or "?")
      r.itemFS:SetTextColor(cr, cg, cb)
    else
      r.icon:Hide()
      r.itemFS:SetText("—")
      r.itemFS:SetTextColor(0.35, 0.35, 0.35)
    end
    r:Show()
    s = s + 1
  end

  local k = shown + 1
  while Row[k] do Row[k]:Hide(); k = k + 1 end
  k = 1
  while Cell[k] do Cell[k]:Hide(); Cell[k].entry = nil; k = k + 1 end
  k = 1
  while Auc[k] do Auc[k]:Hide(); Auc[k].entry = nil; k = k + 1 end
end

local MAX_SKILLS = 6

local function SkillLine(rec)
  local list = rec and rec.skills
  local n = Count(list)
  if n == 0 then return "" end
  local out = "|cff9d9d9d" .. L("profs") .. "|r "
  local i, shown = 1, 0
  while i <= n and shown < MAX_SKILLS do
    if shown > 0 then out = out .. ",  " end
    out = out .. list[i].n .. " |cff808080" .. list[i].r .. "/" .. list[i].m .. "|r"
    shown = shown + 1
    i = i + 1
  end
  if n > shown then out = out .. " |cff808080...|r" end
  return out
end

UpdateView = function()
  if not View.built then return end

  W.title:SetText(L("title") .. "  |cff808080v" .. VERSION .. "|r")
  W.charsFS:SetText(L("chars"))
  W.close:SetText("|cffffd700" .. L("close") .. "|r")

  local i = 1
  while W.tab[i] do
    local b = W.tab[i]
    local on = (b.id == View.tab)
    b:SetText((on and "|cffffd700" or "|cff909090") .. L(b.key) .. "|r")
    i = i + 1
  end

  -- the character column
  local keys, n = CharKeys()
  local mine = MyKey()
  if not View.who or not AllBagsVault.chars[View.who] then View.who = keys[1] end

  i = 1
  while i <= n do
    local b = GetPick(i)
    local key = keys[i]
    local rec = AllBagsVault.chars[key]
    b.key = key
    local mark = (key == View.who) and "|cffffd700" or "|cffb0b0b0"
    local tail = ""
    if rec and rec.level then tail = " |cff707070" .. rec.level .. "|r" end
    if rec and rec.class then
      tail = tail .. " |cff" .. ClassHex(rec.ctoken) .. rec.class .. "|r"
    end
    if key == mine then tail = tail .. " |cff40a040*|r" end
    b:SetText(mark .. (rec and rec.name or key) .. "|r" .. tail)
    b:Show()
    i = i + 1
  end
  local k = n + 1
  while Pick[k] do Pick[k]:Hide(); Pick[k].key = nil; k = k + 1 end

  -- what the whole account is worth, under the column of names
  local sum = 0
  for _, r in pairs(AllBagsVault.chars) do
    if type(r.money) == "number" then sum = sum + r.money end
  end
  W.total:SetText("|cff9d9d9d" .. L("total") .. "|r " .. Money(sum))

  -- the character being played cannot be dropped: its snapshot is the live one
  local ownRow = (View.who == mine)
  W.forget:SetText((ownRow and "|cff707070" or "|cffffd700") .. L("forget") .. "|r")

  local rec = View.who and AllBagsVault.chars[View.who]
  if not rec then
    W.who:SetText("")
    W.meta:SetText("")
    W.skills:SetText("")
    W.hint:SetText("")
    W.stamp:SetText("")
    W.sum:SetText("")
    W.empty:SetText(L("nobody"))
    W.empty:Show()
    DrawGrid({}, 0, false)
    return
  end

  local head = rec.name or View.who
  if rec.realm then head = head .. " |cff707070" .. rec.realm .. "|r" end
  if View.who == mine then head = head .. "  |cff40a040" .. L("here") .. "|r" end
  W.who:SetText(head)

  local meta = ""
  if rec.level then meta = Lf("level", rec.level) end
  if rec.class then meta = meta .. (meta ~= "" and ", " or "") .. rec.class end
  if rec.money then meta = meta .. "   |cff9d9d9d" .. L("money") .. "|r " .. Money(rec.money) end
  if rec.slots and rec.slots > 0 then
    meta = meta .. "   |cff9d9d9d" .. L("free") .. "|r " .. (rec.free or 0) .. "|cff808080/" .. rec.slots .. "|r"
  end
  W.meta:SetText(meta)
  W.skills:SetText(SkillLine(rec))

  -- grouping only means something where there are containers
  W.group:SetText((GroupOn() and "|cff40a040[x]|r " or "|cff707070[   ]|r ")
    .. L("group"))
  if View.tab == "bags" or View.tab == "bank" then
    W.group:Show()
  else
    W.group:Hide()
  end

  if View.tab == "auc" then
    W.hint:SetText(L("aucHint"))
    W.stamp:SetText(Lf("when", Ago(rec.aucAt)))
    local lots = DrawAuc(rec)
    if lots == 0 then
      W.empty:SetText(rec.aucAt and L("aucNone") or L("noData"))
      W.empty:Show()
    else
      W.empty:Hide()
    end
    return
  end

  if View.tab == "gear" then
    W.sum:SetText("")
    W.hint:SetText(L("gearHint"))
    W.stamp:SetText(Lf("when", Ago(rec.gearAt)))
    if Count(rec.gear) == 0 and not rec.gearAt then
      W.empty:SetText(L("noData"))
      W.empty:Show()
      DrawGear(nil)
    else
      W.empty:Hide()
      DrawGear(rec.gear)
    end
    return
  end

  local store, order, stamp, counts
  if View.tab == "bank" then
    store, order, stamp, counts = rec.bank, BANK_ORDER, rec.bankAt, false
    W.hint:SetText(L("bankHint") .. "  |cff707070· " .. L("noCount") .. "|r")
  else
    store, order, stamp, counts = rec.bags, BAG_ORDER, rec.bagsAt, true
    W.hint:SetText(L("bagsHint"))
  end
  W.stamp:SetText(Lf("when", Ago(stamp)))

  W.sum:SetText("")

  local list, cells = Flatten(store, order)
  local slots = cells                 -- how many cells the character has here
  if slots == 0 then
    W.empty:SetText(L("noData"))
    W.empty:Show()
  else
    W.empty:Hide()
  end

  local grouped = GroupOn()
  if grouped then
    list, cells = Group(list, cells)
    -- a container that exists but holds nothing is not the same answer as
    -- "nothing written down for this character"
    if cells == 0 and slots > 0 then
      W.empty:SetText(L("allEmpty"))
      W.empty:Show()
    end
  end

  DrawGrid(list, cells, counts, grouped)
end

local function Show()
  Build()
  if not View.who then View.who = MyKey() end
  local f = W.frame
  f:ClearAllPoints()
  if AllBagsDB and type(AllBagsDB.vx) == "number" and type(AllBagsDB.vy) == "number" then
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", AllBagsDB.vx, AllBagsDB.vy)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
  UpdateView()
  f:Show()
end

local function Toggle()
  Build()
  if W.frame:IsShown() then W.frame:Hide() else Show() end
end

----------------------------------------------------------------------
-- diagnostics
----------------------------------------------------------------------

local function Probe()
  local v = InitVault()
  local keys, n = CharKeys()
  Print(L("probeHead"))
  Print(Lf("probeChars", n, MyKey()))
  local i = 1
  while i <= n do
    local rec = v.chars[keys[i]]
    local bags, bank = 0, 0
    for _, t in pairs(rec.bags or {}) do bags = bags + (t.size or 0) end
    for _, t in pairs(rec.bank or {}) do bank = bank + (t.size or 0) end
    Print(Lf("probeOne", keys[i], bags, bank, Filled(rec.gear),
      Count(rec.auc), Ago(rec.bagsAt)))
    i = i + 1
  end
  Print(Lf("probeApi",
    tostring(GetInventoryItemLink ~= nil),
    tostring(GetInventoryItemQuality ~= nil),
    tostring(GameTooltip ~= nil and GameTooltip.SetHyperlink ~= nil)))
end

----------------------------------------------------------------------
-- events
----------------------------------------------------------------------

local dirty, timer = false, 0

local driver = CreateFrame("Frame", "AllBagsVaultDriver")
driver:SetScript("OnEvent", function(self, ev)
  ev = ev or event

  if ev == "VARIABLES_LOADED" or ev == "PLAYER_LOGIN" or ev == "PLAYER_ENTERING_WORLD" then
    InitVault()
    SnapMeta()
    SnapSkills()
    SnapGear()
    dirty = true
    return
  end

  if ev == "BAG_UPDATE" or ev == "PLAYER_MONEY" then
    dirty = true                      -- flushed by the timer below
    return
  end

  if ev == "UNIT_INVENTORY_CHANGED" then
    if arg1 == nil or arg1 == "player" then SnapGear() end
    return
  end

  if ev == "BANKFRAME_OPENED" or ev == "PLAYERBANKSLOTS_CHANGED"
     or ev == "PLAYERBANKBAGSLOTS_CHANGED" then
    SnapBank()
    if W.frame and W.frame:IsShown() then UpdateView() end
    return
  end

  if ev == "AUCTION_OWNED_LIST_UPDATE" then
    -- readable only while the auction window is open, and only once the
    -- client has asked for the owner list, which is what this event says
    SnapAuction()
    if W.frame and W.frame:IsShown() then UpdateView() end
    return
  end

  if ev == "SKILL_LINES_CHANGED" then
    SnapSkills()
    return
  end

  if ev == "PLAYER_LEVEL_UP" then
    SnapMeta()
    return
  end

  if ev == "PLAYER_LOGOUT" then
    SnapBags()
    SnapGear()
    SnapMeta()
    return
  end
end)

-- Bags change in bursts -- looting a stack fires the event several times --
-- so the snapshot waits a moment instead of running on every one of them.
driver:SetScript("OnUpdate", function(self, elapsed)
  local e = elapsed or arg1 or 0
  if not dirty then return end
  timer = timer + e
  if timer < 2 then return end
  timer = 0
  dirty = false
  SnapBags()
  SnapMeta()
  if W.frame and W.frame:IsShown() and View.who == MyKey() then UpdateView() end
end)

local EVENTS = {
  "VARIABLES_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT",
  "BAG_UPDATE", "PLAYER_MONEY", "UNIT_INVENTORY_CHANGED",
  "BANKFRAME_OPENED", "PLAYERBANKSLOTS_CHANGED", "PLAYERBANKBAGSLOTS_CHANGED",
  "SKILL_LINES_CHANGED", "PLAYER_LEVEL_UP",
  "AUCTION_OWNED_LIST_UPDATE",
}

local ev = 1
while EVENTS[ev] do
  local name = EVENTS[ev]
  pcall(function() driver:RegisterEvent(name) end)
  ev = ev + 1
end

----------------------------------------------------------------------
-- what the rest of the addon can call
----------------------------------------------------------------------

function AllBagsVault_Toggle() Toggle() end
function AllBagsVault_Show() Show() end
function AllBagsVault_Probe() Probe() end
function AllBagsVault_Snapshot()
  SnapBags()
  SnapGear()
  SnapMeta()
  SnapSkills()
end

-- its own way in, for the moments when the main window is not open
SLASH_ALLBAGSVAULT1 = "/vault"
SLASH_ALLBAGSVAULT2 = "/bagsvault"
SlashCmdList["ALLBAGSVAULT"] = function(msg)
  msg = string.lower(msg or "")
  msg = string.gsub(msg, "^%s+", "")
  msg = string.gsub(msg, "%s+$", "")
  if msg == "probe" then
    Probe()
  elseif msg == "help" then
    Print(L("help"))
  else
    Toggle()
  end
end
