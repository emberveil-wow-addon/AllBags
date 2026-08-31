--[[--------------------------------------------------------------------
  AllBags 1.1.0
  All bags (0-4) in one window. Client 1.12.1 / Lua 5.1 (Emberveil).

  The sort is VIRTUAL: nothing moves inside the bags, only the display order
  in the grid changes. Moving items for real would take dozens of consecutive
  PickupContainerItem calls and falls apart on any network hiccup.
----------------------------------------------------------------------]]

local ADDON   = "AllBags"
local VERSION = "1.1.0"

local FIRST_BAG, LAST_BAG = 0, 4

local SIZE, GAP, PAD = 32, 0, 4
local HEADER, FOOTER = 26, 20
local MIN_WIDTH = 300   -- exactly what the header needs

-- The window position is stored as ABSOLUTE coordinates of the bottom left
-- corner, not as an anchor pair. StartMoving re-anchors the frame however it
-- likes, so a pair saved through GetPoint could differ from the original on
-- restore and the window drifted into a screen corner. x and y are absent
-- until the first drag: the window then sits in the bottom right corner.
local DEFAULT_MARGIN = 20

local defaults = {
  cols = 10, sort = "quality", lang = "auto", enabled = true, line = 1, border = 6,
  value = true,     -- show what the bags are worth, when the price addon is there
  bank = false,     -- and what the bank held, when it knows that too
  csize = 14,       -- stack figures: the client's own are too small to read
  groups = true,    -- in bag order, start every bag on a fresh row with its name
  order = false,    -- filled by InitDB: what the sort compares, and in what order
  fav   = false,    -- filled by InitDB: item name -> true, marked with alt+click
  types = false,    -- filled by InitDB: item classes in the player's own order
}

-- What a sort can compare. The player arranges these in the settings window;
-- the comparison walks the list from the top and stops at the first
-- difference, so the topmost line is the coarse grouping and the ones below
-- only decide ties.
local SORT_KEYS = { "fav", "quality", "type", "name", "count", "bag" }

-- Sizes for the stack figures. This client will not resize a FontString and
-- will not scale one either -- a scaled frame moves the figure without making
-- it any bigger -- so the only lever left is the ready made font OBJECTS the
-- client ships with. These are the ones the stock bags use for their counts:
-- white, outlined, in the corner of the cell.
local COUNT_FONTS = {
  { o = "NumberFontNormalSmall", n = 12 },
  { o = "NumberFontNormal",      n = 14 },
  { o = "NumberFontNormalLarge", n = 16 },
  { o = "NumberFontNormalHuge",  n = 30 },
}

-- table.getn on 5.0, # on later ones: counting by hand works everywhere and
-- the lists here are five entries long.
local function Count(t)
  if type(t) ~= "table" then return 0 end
  local n = 0
  while t[n + 1] ~= nil do n = n + 1 end
  return n
end

local function DefaultOrder()
  return {
    { k = "fav",     on = true },
    { k = "type",    on = true },
    { k = "quality", on = true },
    { k = "name",    on = true },
    { k = "count",   on = true },
    { k = "bag",     on = false },
  }
end

----------------------------------------------------------------------
-- localisation
----------------------------------------------------------------------

local STRINGS = {
  ru = {
    title    = "Сумки",
    free     = "Место",
    money    = "Деньги",
    sortQ    = "Сортировка: по качеству",
    sortN    = "Сортировка: по сумкам",
    hint     = "ПКМ по рамке — меню",
    hintFull = "ЛКМ взять · ПКМ использовать · Shift+ЛКМ разделить",
    btnOff   = "Откл.",
    mDisable = "Отключить аддон",
    mLine    = "Окантовка окна",
    mThin    = "Тонкая",
    mMed     = "Средняя",
    mThick   = "Толстая",
    lineSet  = "окантовка: %s",
    msgOff   = "аддон отключён — сумки снова открываются штатным окном. Включить обратно: /bags on",
    msgOn    = "аддон включён, сумки открываются общим окном.",
    colsSet  = "столбцов: %d",
    colsErr  = "укажите число от 4 до 20, например: /bags cols 10",
    help     = "команды: /bags [config | types | fav | menu | sort | cols N | border N | value | lang ru/en/auto | on | off | reset]",
    reset    = "позиция сброшена.",
    valueSet = "стоимость сумок: %s",
    on       = "вкл",
    off      = "выкл",
    langSet  = "язык: %s",
    mSort    = "Сортировка",
    mByQ     = "По качеству",
    mByBag   = "По сумкам",
    mCols    = "Столбцов в ряду",
    mLang    = "Язык",
    mAuto    = "Авто",
    mReset   = "Сбросить позицию",
    mClose   = "Закрыть окно",
    tipMenu  = "ПКМ по рамке — меню",
    value    = "Стоимость",
    bank     = "Банк",
    mValue   = "Показывать стоимость",
    mBank    = "Показывать стоимость банка",
    noPriceAddon = "ItemLens не установлен — считать стоимость нечем.",
    loaded   = "%s загружен. ПКМ по рамке — меню, /bags config — настройки.",
    mCfg     = "Настройки",
    cfgTitle = "AllBags — настройки",
    cfgSort  = "Порядок сортировки",
    cfgHint  = "сверху — главное условие; стрелки двигают, квадрат включает",
    kQuality = "по качеству",
    kType    = "по типу предмета",
    kName    = "по названию",
    kCount   = "по размеру стопки",
    kBag     = "по сумке и ячейке",
    cfgSize  = "размер цифр",
    cfgCols  = "столбцов",
    cfgLine  = "толщина сетки",
    cfgGroup = "делить по сумкам, когда сортировка выключена",
    cfgClose = "закрыть",
    kFav     = "избранное",
    cfgTypes = "порядок типов...",
    tTitle   = "AllBags — порядок типов",
    tHint    = "типы запоминаются по мере того, как вещи попадают в сумки",
    tEmpty   = "пока ни одного типа не встречалось",
    favHint  = "Alt+ЛКМ по вещи — пометить звёздочкой",
    favList  = "в избранном: %s",
    favNone  = "избранное пусто. Alt+ЛКМ по вещи, чтобы пометить.",
    favClear = "избранное очищено.",
  },
  en = {
    title    = "Bags",
    free     = "Free",
    money    = "Money",
    sortQ    = "Sort: by quality",
    sortN    = "Sort: by bag",
    hint     = "Right click the frame for the menu",
    hintFull = "LMB take · RMB use · Shift+LMB split",
    btnOff   = "Off",
    mDisable = "Disable addon",
    mLine    = "Window border",
    mThin    = "Thin",
    mMed     = "Medium",
    mThick   = "Thick",
    lineSet  = "border: %s",
    msgOff   = "addon disabled — bags open in the default window again. Turn it back on: /bags on",
    msgOn    = "addon enabled, bags open in the combined window.",
    colsSet  = "columns: %d",
    colsErr  = "give a number from 4 to 20, for example: /bags cols 10",
    help     = "commands: /bags [config | types | fav | menu | sort | cols N | border N | value | lang ru/en/auto | on | off | reset]",
    reset    = "position reset.",
    valueSet = "bag value: %s",
    on       = "on",
    off      = "off",
    langSet  = "language: %s",
    mSort    = "Sorting",
    mByQ     = "By quality",
    mByBag   = "By bag",
    mCols    = "Columns per row",
    mLang    = "Language",
    mAuto    = "Auto",
    mReset   = "Reset position",
    mClose   = "Close window",
    tipMenu  = "Right click the frame for the menu",
    value    = "Value",
    bank     = "Bank",
    mValue   = "Show bag value",
    mBank    = "Show bank value",
    noPriceAddon = "ItemLens is not installed — nothing to count the value with.",
    loaded   = "%s loaded. Right click the frame for the menu, /bags config for settings.",
    mCfg     = "Settings",
    cfgTitle = "AllBags — settings",
    cfgSort  = "Sort order",
    cfgHint  = "top line matters most; arrows move, the box switches on and off",
    kQuality = "by quality",
    kType    = "by item type",
    kName    = "by name",
    kCount   = "by stack size",
    kBag     = "by bag and slot",
    cfgSize  = "figure size",
    cfgCols  = "columns",
    cfgLine  = "grid thickness",
    cfgGroup = "split by bag when sorting is off",
    cfgClose = "close",
    kFav     = "favourites",
    cfgTypes = "type order...",
    tTitle   = "AllBags — type order",
    tHint    = "types are remembered as items turn up in the bags",
    tEmpty   = "no type has turned up yet",
    favHint  = "Alt+LMB an item to star it",
    favList  = "starred: %s",
    favNone  = "nothing is starred. Alt+LMB an item to star it.",
    favClear = "starred items cleared.",
  },
}

local function CurrentLang()
  local pick = AllBagsDB and AllBagsDB.lang or "auto"
  if pick == "ru" or pick == "en" then return pick end
  if GetLocale and GetLocale() == "ruRU" then return "ru" end
  return "en"
end

local function L(key) return STRINGS[CurrentLang()][key] or key end

----------------------------------------------------------------------
-- the price addon
----------------------------------------------------------------------

-- ItemLens is the price addon. Nothing here depends on it being installed:
-- no addon, no value line, no error.
local function PriceApi()
  if type(ItemLens_BagValue) == "function" then
    return ItemLens_BagValue, ItemLens_Format
  end
  return nil
end

local function BankApi()
  if type(ItemLens_BankValue) == "function" then return ItemLens_BankValue end
  return nil
end

----------------------------------------------------------------------
-- state
----------------------------------------------------------------------

local frame, header, hintText, moneyText, sortButton, closeButton
local buttons = {}      -- i -> Button
local hoverIndex = nil  -- cell the cursor is over, for the public helpers below
local countFS  = {}     -- i -> stack count FontString
local bgTex    = {}     -- i -> fill acting as the border (quality colour)
local starTex  = {}     -- i -> favourite mark in the corner
local iconTex  = {}     -- i -> item icon
local innerTex = {}     -- i -> dark centre of an empty cell
local slotBag  = {}     -- i -> bag id
local slotIdx  = {}     -- i -> slot inside that bag
local btnIndex = {}     -- Button -> i
local slotList = {}
local slotCount = 0
local dirty, timer = true, 0
local greeted = false
local lastCount, lastCols, lastLine = -1, -1, -1
local lastMode, lastCSize = -1, -1
local ApplyPosition, SavePosition   -- forward declaration for the menu
local SetEnabled                    -- turns the bag hooks on and off
local ApplyBorder                   -- window border thickness
local ApplyCountFont, ApplyCountSize  -- size of the stack figures
local ShowConfig                    -- settings window, built on first use
local ShowTypes                     -- the type order window, same idea
local LABEL_H = 5                   -- gap with a rule between two bags
local bagFS = {}                    -- n -> rule between two bag blocks

local GRID_R, GRID_G, GRID_B = 0.16, 0.16, 0.16   -- grid line colour

local QUALITY_FALLBACK = {
  [0] = { 0.62, 0.62, 0.62 },
  [1] = { 1.00, 1.00, 1.00 },
  [2] = { 0.12, 1.00, 0.00 },
  [3] = { 0.00, 0.44, 0.87 },
  [4] = { 0.64, 0.21, 0.93 },
  [5] = { 1.00, 0.50, 0.00 },
  [6] = { 0.90, 0.80, 0.50 },
}

local function Print(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00" .. ADDON .. ":|r " .. msg)
  end
end

-- Escape closes a window whose name is in UISpecialFrames. The list holds
-- names, not frames, so a frame with no name can never be registered, and the
-- same name must not go in twice.
local function EscClose(name)
  if type(UISpecialFrames) ~= "table" or not name then return end
  local i = 1
  while UISpecialFrames[i] do
    if UISpecialFrames[i] == name then return end
    i = i + 1
  end
  UISpecialFrames[i] = name
end

local function SaveWinPos(f, kx, ky)
  if not f or not f.GetLeft then return end
  local x, y = f:GetLeft(), f:GetBottom()
  if x and y then AllBagsDB[kx], AllBagsDB[ky] = x, y end
end

local function ApplyWinPos(f, kx, ky, dx, dy)
  if not f then return end
  f:ClearAllPoints()
  local x, y = AllBagsDB[kx], AllBagsDB[ky]
  if type(x) == "number" and type(y) == "number" then
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", dx, dy)
  end
end

local function QualityColor(q)
  if q and GetItemQualityColor then
    local r, g, b = GetItemQualityColor(q)
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
      return r, g, b
    end
  end
  local c = QUALITY_FALLBACK[q or 1] or QUALITY_FALLBACK[1]
  return c[1], c[2], c[3]
end

-- item name out of the hyperlink, for a stable sort order
local function ItemName(bag, slot)
  local link = GetContainerItemLink(bag, slot)
  if not link then return "" end
  local _, _, name = string.find(link, "%[(.+)%]")
  return name or ""
end

-- Item class ("Weapon", "Trade Goods", ...) for the type sort. On 1.12
-- GetItemInfo answers name, link, quality, minLevel, type, subType, ... while
-- later builds slip an item level in front of minLevel; the fifth return is
-- therefore a number on those and the class sits one place further along.
-- An item the client has not cached yet answers nothing: the empty string
-- then keeps every such entry together instead of erroring.
local function ItemType(bag, slot)
  if not GetItemInfo then return "" end
  local link = GetContainerItemLink(bag, slot)
  if not link then return "" end
  local _, _, _, _, b, c = GetItemInfo(link)
  if type(b) == "string" then return b end   -- 1.12 layout
  if type(c) == "string" then return c end   -- one level shifted
  return ""
end

local function FormatMoney(copper)
  copper = copper or 0
  local g = math.floor(copper / 10000)
  local s = math.floor(copper / 100) - g * 100
  local c = copper - math.floor(copper / 100) * 100
  local out = ""
  if g > 0 then out = out .. "|cffffd700" .. g .. "g|r " end
  if g > 0 or s > 0 then out = out .. "|cffc7c7cf" .. s .. "s|r " end
  return out .. "|cffeda55f" .. c .. "c|r"
end

----------------------------------------------------------------------
-- collecting and sorting the slots
----------------------------------------------------------------------

-- Item classes come back localised, so there is no fixed list to ship: the
-- addon writes down every class it meets and the player arranges that list in
-- the type window. A class nobody has arranged yet lands after the known ones.
local typeRank = {}

local function NoteType(t)
  if not t or t == "" then return end
  local list = AllBagsDB.types
  if type(list) ~= "table" then list = {}; AllBagsDB.types = list end
  local i = 1
  while list[i] do
    if list[i] == t then return end
    i = i + 1
  end
  list[i] = t
end

local function RankTypes()
  typeRank = {}
  local list = AllBagsDB.types
  local i = 1
  while list and list[i] do
    typeRank[list[i]] = i
    i = i + 1
  end
end

local function IsFav(name)
  if not name or name == "" then return false end
  local f = AllBagsDB.fav
  return (type(f) == "table" and f[name]) and true or false
end

local function CollectSlots()
  slotCount = 0
  local free = 0

  local bag = FIRST_BAG
  while bag <= LAST_BAG do
    local slots = GetContainerNumSlots(bag)
    if slots and slots > 0 then
      local slot = 1
      while slot <= slots do
        local texture, count, locked, quality = GetContainerItemInfo(bag, slot)
        local empty = (texture == nil or texture == "")
        if empty then free = free + 1 end

        slotCount = slotCount + 1
        local e = slotList[slotCount]
        if not e then e = {}; slotList[slotCount] = e end
        e.bag     = bag
        e.slot    = slot
        e.texture = texture
        e.count   = count or 0
        e.locked  = locked
        e.quality = quality or 0
        e.empty   = empty
        e.name    = (not empty) and ItemName(bag, slot) or ""
        e.itype   = (not empty) and ItemType(bag, slot) or ""
        e.fav     = (not empty) and IsFav(e.name) or false
        if not empty then NoteType(e.itype) end

        slot = slot + 1
      end
    end
    bag = bag + 1
  end

  RankTypes()
  return free, slotCount
end

-- One comparison step. -1 puts a first, 1 puts b first, 0 means this key
-- cannot tell the two apart and the next line of the order decides.
local function KeyCmp(key, a, b)
  if key == "fav" then
    if a.fav == b.fav then return 0 end
    return a.fav and -1 or 1                          -- starred items first
  elseif key == "quality" then
    if a.quality == b.quality then return 0 end
    return (a.quality > b.quality) and -1 or 1        -- the best first
  elseif key == "type" then
    if a.itype == b.itype then return 0 end
    -- the player's own order first; anything not on that list keeps to the
    -- end, in alphabetical order among itself
    local ra, rb = typeRank[a.itype], typeRank[b.itype]
    if ra and rb then return (ra < rb) and -1 or 1 end
    if ra then return -1 end
    if rb then return 1 end
    return (a.itype < b.itype) and -1 or 1
  elseif key == "name" then
    if a.name == b.name then return 0 end
    return (a.name < b.name) and -1 or 1
  elseif key == "count" then
    if a.count == b.count then return 0 end
    return (a.count > b.count) and -1 or 1            -- the fullest stack first
  elseif key == "bag" then
    if a.bag ~= b.bag then return (a.bag < b.bag) and -1 or 1 end
    if a.slot == b.slot then return 0 end
    return (a.slot < b.slot) and -1 or 1
  end
  return 0
end

-- Walks the order the player put together in the settings window and stops at
-- the first line that separates the two items. Empty cells always go last.
local function CompareSlots(a, b)
  if a.empty ~= b.empty then return b.empty end
  if a.empty then
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
  end
  local ord = AllBagsDB and AllBagsDB.order
  local i = 1
  while ord and ord[i] do
    if ord[i].on then
      local c = KeyCmp(ord[i].k, a, b)
      if c ~= 0 then return c < 0 end
    end
    i = i + 1
  end
  if a.bag ~= b.bag then return a.bag < b.bag end
  return a.slot < b.slot
end

local function SortSlots()
  if AllBagsDB.sort ~= "quality" then return end
  -- hand written insertion sort: better not to rely on table.sort in this
  -- client, and the list is short (up to ~80 entries)
  local i = 2
  while i <= slotCount do
    local v = slotList[i]
    local j = i - 1
    while j >= 1 and CompareSlots(v, slotList[j]) do
      slotList[j + 1] = slotList[j]
      j = j - 1
    end
    slotList[j + 1] = v
    i = i + 1
  end
end

----------------------------------------------------------------------
-- slot buttons
----------------------------------------------------------------------

-- handlers in this client may get no self: the global this covers that case
local function IndexOf(widget)
  if not widget then return nil end
  local i = btnIndex[widget]
  if i then return i end
  if widget.GetName then
    local n = widget:GetName()
    if n and string.sub(n, 1, 11) == "AllBagsSlot" then
      return tonumber(string.sub(n, 12))
    end
  end
  return nil
end

-- Puts an item link into whatever chat line is open, and says whether it
-- went anywhere. The stock helper is tried first; if this build does not
-- have it, the edit box is written to directly.
local function InsertLink(link)
  if not link or link == "" then return false end

  local box = getglobal("ChatFrameEditBox")
  local open = box and box.IsVisible and box:IsVisible()
  if not open then return false end

  if type(ChatEdit_InsertLink) == "function" then
    local ok, used = pcall(ChatEdit_InsertLink, link)
    if ok and used then return true end
  end
  if box.Insert then
    box:Insert(link)
    return true
  end
  return false
end

local function ButtonClick(self, button)
  self = self or this
  local btn = button or arg1
  local i = IndexOf(self)
  if not i then return end
  local bag, slot = slotBag[i], slotIdx[i]
  if bag == nil then return end

  if btn == "RightButton" then
    UseContainerItem(bag, slot)
    return
  end

  -- Alt is free in this window: left click takes, right click uses, shift
  -- links or splits. So alt is what marks an item as a favourite.
  if IsAltKeyDown and IsAltKeyDown() then
    local name = ItemName(bag, slot)
    if name ~= "" then
      if type(AllBagsDB.fav) ~= "table" then AllBagsDB.fav = {} end
      if AllBagsDB.fav[name] then AllBagsDB.fav[name] = nil
      else AllBagsDB.fav[name] = true end
      dirty = true
    end
    return
  end

  if IsShiftKeyDown and IsShiftKeyDown() then
    -- With the chat line open, shift means "say what this is" -- the same as
    -- shift clicking a stock bag slot. Splitting a stack is what it means the
    -- rest of the time.
    if InsertLink(GetContainerItemLink(bag, slot)) then return end

    local _, count = GetContainerItemInfo(bag, slot)
    if count and count > 1 then
      local half = math.floor(count / 2)
      if half < 1 then half = 1 end
      SplitContainerItem(bag, slot, half)
      return
    end
  end

  PickupContainerItem(bag, slot)
end

local function ButtonEnter(self)
  self = self or this
  local i = IndexOf(self)
  if not i or slotBag[i] == nil then return end
  if not GameTooltip then return end
  hoverIndex = i
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetBagItem(slotBag[i], slotIdx[i])
  GameTooltip:Show()
end

----------------------------------------------------------------------
-- public helpers for other addons
----------------------------------------------------------------------

-- Which bag and slot one of our cells stands for; nil for any other widget.
function AllBags_SlotOf(widget)
  local i = IndexOf(widget)
  if not i then return nil end
  if slotBag[i] == nil then return nil end
  return slotBag[i], slotIdx[i]
end

-- The bag and slot under the cursor right now, or nil when the cursor is not
-- over one of our cells. ItemLens uses this to know the exact stack size.
function AllBags_MouseSlot()
  if hoverIndex == nil then return nil end
  if slotBag[hoverIndex] == nil then return nil end
  return slotBag[hoverIndex], slotIdx[hoverIndex]
end

local function ButtonLeave()
  hoverIndex = nil
  if GameTooltip then GameTooltip:Hide() end
end

-- Grid line thickness in interface units. Whole numbers only: the client
-- rounds fractional insets differently from cell to cell and the grid lines
-- come out uneven. One unit is about 1.4 screen pixels at 1080p, and two
-- neighbouring cells put two of them side by side.
local function LineWidth()
  local w = AllBagsDB and AllBagsDB.line or 1
  if type(w) ~= "number" then w = 1 end
  w = math.floor(w + 0.5)
  if w < 1 then w = 1 end
  if w > 3 then w = 3 end
  return w
end

local function AnchorInset(t, b)
  if not t or not t.ClearAllPoints then return end
  local w = LineWidth()
  t:ClearAllPoints()
  t:SetPoint("TOPLEFT", b, "TOPLEFT", w, -w)
  t:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -w, w)
end

local function AnchorIcon(b, i)
  local t = b.GetNormalTexture and b:GetNormalTexture()
  if not t then return end
  iconTex[i] = t
  AnchorInset(t, b)
end

-- Picks the font object closest to the size the player asked for. The colour
-- is forced to white afterwards: some of these objects come tinted, and the
-- stock bags show a plain white figure.
local function CountFontEntry(n)
  local best, bestd = COUNT_FONTS[1], nil
  local i = 1
  while COUNT_FONTS[i] do
    local d = COUNT_FONTS[i].n - (n or 14)
    if d < 0 then d = -d end
    if bestd == nil or d < bestd then best, bestd = COUNT_FONTS[i], d end
    i = i + 1
  end
  return best
end

ApplyCountFont = function(i)
  local fs = countFS[i]
  if not fs then return end

  local e = CountFontEntry(AllBagsDB and AllBagsDB.csize)
  local obj = getglobal(e.o)
  if obj and fs.SetFontObject then
    fs:SetFontObject(obj)
  else
    -- no such object on this build: ask for the size directly and hope
    local path = fs:GetFont()
    if path and path ~= "" then fs:SetFont(path, e.n, "OUTLINE") end
  end
  fs:SetTextColor(1, 1, 1)
end

ApplyCountSize = function()
  local i = 1
  while countFS[i] do ApplyCountFont(i); i = i + 1 end
end

local function GetSlotButton(i)
  if buttons[i] then return buttons[i] end

  local b = CreateFrame("Button", "AllBagsSlot" .. i, frame)
  b:SetWidth(SIZE)
  b:SetHeight(SIZE)
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")

  -- Fill covering the whole cell. This object is ALWAYS in colour mode: per the
  -- docs a texture will not take a file path again after a solid colour fill.
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(b)
  bg:SetTexture(GRID_R, GRID_G, GRID_B, 1)

  -- Dark centre. Empty cells need it: without one, neighbouring empty cells
  -- merge into a single solid rectangle and the grid disappears.
  local inner = b:CreateTexture(nil, "BORDER")
  inner:SetTexture(0.07, 0.07, 0.07, 1)
  AnchorInset(inner, b)

  -- The icon is the button's own normal texture, always in file mode.
  -- A one pixel inset exposes the fill along the edge: that is the grid line.
  b:SetNormalTexture("")
  local ic = b.GetNormalTexture and b:GetNormalTexture()
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", ButtonClick)
  b:SetScript("OnEnter", ButtonEnter)
  b:SetScript("OnLeave", ButtonLeave)

  local fs = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  fs:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
  fs:SetJustifyH("RIGHT")

  -- The star is a plain gold square in the corner: a file texture that this
  -- client cannot find renders as a red missing-texture block, and a colour
  -- fill can never fail that way.
  local star = b:CreateTexture(nil, "OVERLAY")
  star:SetTexture(1, 0.82, 0, 1)
  star:SetWidth(6)
  star:SetHeight(6)
  star:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
  star:Hide()

  buttons[i]  = b
  countFS[i]  = fs
  starTex[i]  = star
  bgTex[i]    = bg
  innerTex[i] = inner
  iconTex[i]  = ic
  btnIndex[b] = i
  ApplyCountFont(i)
  return b
end

----------------------------------------------------------------------
-- layout and refresh
----------------------------------------------------------------------

-- Bags are told apart by a gap and a thin rule, not by their names: the
-- captions cost a whole text line each and pushed the window past the
-- bottom of the screen on a character with five bags.
local function GetRule(n)
  local t = bagFS[n]
  if t then return t end
  t = frame:CreateTexture(nil, "ARTWORK")
  t:SetTexture(0.30, 0.30, 0.30, 1)
  t:SetHeight(1)
  bagFS[n] = t
  return t
end

-- A rule only makes sense while the grid still follows the bags: once the
-- sort mixes everything together a bag has no block of its own.
local function Grouped()
  return AllBagsDB.groups and AllBagsDB.sort ~= "quality"
end

local function Layout()
  local cols = AllBagsDB.cols

  local width  = PAD * 2 + cols * SIZE + (cols - 1) * GAP
  if width < MIN_WIDTH then width = MIN_WIDTH end   -- or the header will not fit
  local gridW  = cols * SIZE + (cols - 1) * GAP
  local gridX  = math.floor((width - gridW) / 2)

  local y = HEADER          -- how far down the next block starts
  local labels = 0

  if Grouped() then
    local i = 1
    while i <= slotCount do
      local bag = slotList[i].bag
      local n = 0
      while (i + n) <= slotCount and slotList[i + n].bag == bag do n = n + 1 end

      -- every block after the first is opened by a gap with a rule in it
      if labels > 0 then
        labels = labels + 1
        local t = GetRule(labels)
        t:ClearAllPoints()
        t:SetWidth(gridW)
        t:SetPoint("TOPLEFT", frame, "TOPLEFT", gridX, -(y + 2))
        t:Show()
        y = y + LABEL_H
      else
        labels = labels + 1
      end

      local k = 0
      while k < n do
        local b = GetSlotButton(i + k)
        local row = math.floor(k / cols)
        local col = k - row * cols
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", frame, "TOPLEFT",
          gridX + col * (SIZE + GAP),
          -(y + row * (SIZE + GAP)))
        b:Show()
        k = k + 1
      end

      local rows = math.floor((n + cols - 1) / cols)
      y = y + rows * (SIZE + GAP)
      i = i + n
    end
  else
    local rows = math.floor((slotCount + cols - 1) / cols)
    if rows < 1 then rows = 1 end
    local i = 1
    while i <= slotCount do
      local b = GetSlotButton(i)
      local row = math.floor((i - 1) / cols)
      local col = (i - 1) - row * cols
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", frame, "TOPLEFT",
        gridX + col * (SIZE + GAP),
        -(HEADER + row * (SIZE + GAP)))
      b:Show()
      i = i + 1
    end
    y = HEADER + rows * SIZE + (rows - 1) * GAP
  end

  frame:SetWidth(width)
  frame:SetHeight(y + 6 + FOOTER)

  local j = slotCount + 1
  while buttons[j] do
    buttons[j]:Hide()
    slotBag[j], slotIdx[j] = nil, nil
    j = j + 1
  end

  local m = labels + 1
  while bagFS[m] do bagFS[m]:Hide(); m = m + 1 end
end

local function Refresh()
  if not frame or not frame:IsShown() then return end

  local free = CollectSlots()
  SortSlots()

  -- Grouping changes the height as well as the placement, so the mode is part
  -- of what decides whether the grid has to be laid out again.
  local mode = Grouped() and 1 or 0
  if slotCount ~= lastCount or AllBagsDB.cols ~= lastCols or mode ~= lastMode then
    lastCount, lastCols, lastMode = slotCount, AllBagsDB.cols, mode
    Layout()
  end

  if AllBagsDB.csize ~= lastCSize then
    lastCSize = AllBagsDB.csize
    ApplyCountSize()
  end

  if AllBagsDB.line ~= lastLine then
    lastLine = AllBagsDB.line
    local k = 1
    while buttons[k] do
      AnchorInset(innerTex[k], buttons[k])
      AnchorInset(iconTex[k], buttons[k])
      k = k + 1
    end
  end

  local i = 1
  while i <= slotCount do
    local e  = slotList[i]
    local b  = GetSlotButton(i)
    local fs = countFS[i]
    local bg    = bgTex[i]
    local inner = innerTex[i]
    slotBag[i], slotIdx[i] = e.bag, e.slot

    local star = starTex[i]
    if star then
      if e.fav and not e.empty then star:Show() else star:Hide() end
    end

    if e.empty then
      b:SetNormalTexture("")
      if inner then inner:Show() end
      if bg then bg:SetTexture(GRID_R, GRID_G, GRID_B, 1) end
      if fs then fs:SetText("") end
      b:SetAlpha(0.9)
    else
      b:SetNormalTexture(e.texture)
      AnchorIcon(b, i)
      if inner then inner:Hide() end
      if fs then
        if e.count > 1 then fs:SetText(e.count) else fs:SetText("") end
      end
      if bg then
        -- common and poor quality take the grid colour: otherwise the seam
        -- between two cells is a bright two pixel band and looks thick
        if e.quality and e.quality <= 1 then
          bg:SetTexture(GRID_R, GRID_G, GRID_B, 1)
        else
          local r, g, bl = QualityColor(e.quality)
          bg:SetTexture(r, g, bl, 1)
        end
      end
      if e.locked then b:SetAlpha(0.4) else b:SetAlpha(1) end
    end
    i = i + 1
  end

  local footer = "|cff9d9d9d" .. L("money") .. "|r " .. FormatMoney(GetMoney())
    .. "   |cff5a5a5a|||r   |cff9d9d9d" .. L("free") .. "|r "
    .. free .. "|cff808080/" .. slotCount .. "|r"

  moneyText:SetText(footer)

  -- ItemLens, when installed, knows what a vendor would pay for the contents.
  -- The value takes the right hand corner: putting it next to the money would
  -- run the footer into the hint on a narrow window. Nothing here depends on
  -- ItemLens being present — no addon, no line, no error.
  local shown = nil
  local bagValue, money = PriceApi()
  if AllBagsDB.value and bagValue then
    local total, known, unknown = bagValue()
    if type(total) == "number" then
      shown = "|cff9d9d9d" .. L("value") .. "|r "
        .. (money and money(total) or total)
      -- items with no known price are not mentioned any more: the tail of
      -- "+7?" said nothing useful and only made the line noisy

      -- the bank, if the price addon knows it and the player wants it shown
      local bankValue = BankApi()
      if AllBagsDB.bank and bankValue then
        local bankTotal, _, _, fresh = bankValue()
        if type(bankTotal) == "number" then
          shown = shown .. "  |cff5a5a5a|||r  |cff9d9d9d" .. L("bank") .. "|r "
            .. (money and money(bankTotal) or bankTotal)
          if not fresh then shown = shown .. " |cff808080*|r" end
        end
      end
    end
  end
  hintText:SetText(shown or L("hint"))

  sortButton:SetText(AllBagsDB.sort == "quality" and L("sortQ") or L("sortN"))
end

----------------------------------------------------------------------
-- context menu (right click on the window frame)
----------------------------------------------------------------------

local menu, menuTitle
local menuButtons = {}
local menuExtra = {}    -- i -> second, right hand button on that line
local hoverCount, menuIdle, everHovered = 0, 0, false

local ITEM_H, TITLE_H, MPAD = 18, 18, 8
local COL_CHOICES = { 6, 8, 10, 12, 14, 16 }

local function EnterMenu() hoverCount = hoverCount + 1; everHovered = true; menuIdle = 0 end
local function LeaveMenu() hoverCount = hoverCount - 1; if hoverCount < 0 then hoverCount = 0 end end

local function HideMenu() if menu then menu:Hide() end end

local ShowMenu   -- forward declaration: menu entries redraw the menu

local function MenuItems()
  local items, count = {}, 0
  local function add(t) count = count + 1; items[count] = t end

  add({ mark = "none", text = "|cff808080" .. L("hintFull") .. "|r", header = true })
  add({ mark = "none", text = L("mSort") .. ":", header = true })
  -- Settings ride on the "by quality" line, at its right end: that is what
  -- they configure, and a line of their own read as something unrelated.
  add({ mark = "radio", indent = true, on = (AllBagsDB.sort == "quality"), text = L("mByQ"), keep = true,
        action = function() AllBagsDB.sort = "quality"; dirty = true end,
        right = L("mCfg") .. "...", raction = function() ShowConfig() end })
  add({ mark = "radio", indent = true, on = (AllBagsDB.sort ~= "quality"), text = L("mByBag"), keep = true,
        action = function() AllBagsDB.sort = "bag"; dirty = true end })

  add({ mark = "none", text = L("mCols") .. ":", header = true })
  local i = 1
  while COL_CHOICES[i] do
    local n = COL_CHOICES[i]
    add({ mark = "radio", indent = true, on = (AllBagsDB.cols == n), text = "" .. n, keep = true,
          action = function() AllBagsDB.cols = n; lastCols = -1; dirty = true end })
    i = i + 1
  end

  add({ mark = "none", text = L("mLine") .. ":", header = true })
  add({ mark = "radio", indent = true, on = (AllBagsDB.border <= 6), text = L("mThin"), keep = true,
        action = function() AllBagsDB.border = 5; ApplyBorder() end })
  add({ mark = "radio", indent = true, on = (AllBagsDB.border > 6 and AllBagsDB.border < 14), text = L("mMed"), keep = true,
        action = function() AllBagsDB.border = 10; ApplyBorder() end })
  add({ mark = "radio", indent = true, on = (AllBagsDB.border >= 14), text = L("mThick"), keep = true,
        action = function() AllBagsDB.border = 16; ApplyBorder() end })

  add({ mark = "none", text = L("mLang") .. ":", header = true })
  add({ mark = "radio", indent = true, on = (AllBagsDB.lang == "auto"), text = L("mAuto"), keep = true,
        action = function() AllBagsDB.lang = "auto"; dirty = true end })
  add({ mark = "radio", indent = true, on = (AllBagsDB.lang == "ru"), text = "Русский", keep = true,
        action = function() AllBagsDB.lang = "ru"; dirty = true end })
  add({ mark = "radio", indent = true, on = (AllBagsDB.lang == "en"), text = "English", keep = true,
        action = function() AllBagsDB.lang = "en"; dirty = true end })

  if PriceApi() then
    add({ mark = "radio", on = AllBagsDB.value, text = L("mValue"), keep = true,
          action = function() AllBagsDB.value = not AllBagsDB.value; dirty = true end })
    if BankApi() then
      add({ mark = "radio", on = AllBagsDB.bank, text = L("mBank"), keep = true,
            action = function() AllBagsDB.bank = not AllBagsDB.bank; dirty = true end })
    end
  end

  add({ mark = "none", text = L("mReset"),
        action = function()
          AllBagsDB.x, AllBagsDB.y = nil, nil
          AllBagsDB.cfgx, AllBagsDB.cfgy = nil, nil
          AllBagsDB.twx, AllBagsDB.twy = nil, nil
          AllBagsDB.menux, AllBagsDB.menuy = nil, nil
          ApplyPosition()
        end })

  add({ mark = "none", text = L("mClose"), action = function() frame:Hide() end })
  add({ mark = "none", text = "|cffff8080" .. L("mDisable") .. "|r",
        action = function() SetEnabled(false) end })

  return items, count
end

local function ItemLabel(item)
  local prefix = ""
  if item.mark == "radio" then
    prefix = item.on and "|cff40ff40(*)|r " or "|cff808080( )|r "
  elseif item.indent then
    prefix = "     "
  end
  if item.indent and item.mark == "radio" then prefix = "   " .. prefix end
  return prefix .. item.text
end

-- The right hand half of a menu line: its own little button, so the line can
-- carry two separate actions.
local function GetMenuExtra(i)
  if menuExtra[i] then return menuExtra[i] end
  local b = CreateFrame("Button", "AllBagsMenuExtra" .. i, menu)
  b:SetHeight(ITEM_H)
  b:SetFont("Fonts\\FRIZQT__.TTF", 12)
  b:SetTextColor(1, 0.82, 0)
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnEnter", EnterMenu)
  b:SetScript("OnLeave", LeaveMenu)
  menuExtra[i] = b
  return b
end

local function GetMenuButton(i)
  if menuButtons[i] then return menuButtons[i] end
  local b = CreateFrame("Button", "AllBagsMenuItem" .. i, menu)
  b:SetHeight(ITEM_H)
  b:SetFont("Fonts\\FRIZQT__.TTF", 12)
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  b:SetScript("OnEnter", EnterMenu)
  b:SetScript("OnLeave", LeaveMenu)
  menuButtons[i] = b
  return b
end

local function BuildMenu()
  if menu then return end

  menu = CreateFrame("Frame", "AllBagsMenu", UIParent)
  menu:SetFrameStrata("FULLSCREEN_DIALOG")
  menu:SetToplevel(true)
  menu:SetClampedToScreen(true)
  menu:EnableMouse(true)
  menu:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tileSize = 16, edgeSize = 14,
    insets   = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  menu:SetBackdropColor(0, 0, 0, 0.94)
  menu:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
  menu:SetScript("OnEnter", EnterMenu)
  menu:SetScript("OnLeave", LeaveMenu)
  menu:SetMovable(true)
  menu:Hide()

  -- The menu can be pulled aside: RegisterForDrag stays silent on frames in
  -- this client, so the mouse events do the work. Dragging also keeps the
  -- idle timer at bay, or the menu would close under the cursor.
  local dragging = false
  menu:SetScript("OnMouseDown", function()
    if not dragging then dragging = true; menuIdle = 0; menu:StartMoving() end
  end)
  menu:SetScript("OnMouseUp", function()
    if dragging then
      dragging = false
      menuIdle = 0
      menu:StopMovingOrSizing()
      SaveWinPos(menu, "menux", "menuy")
    end
  end)

  menuTitle = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  if not menuTitle:GetFont() or menuTitle:GetFont() == "" then
    menuTitle:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
  end
  menuTitle:SetJustifyH("LEFT")

  -- The menu used to close itself a second and a half after the cursor left
  -- it. It has since become the place where the settings live, and a panel
  -- that runs away while you read it is no use: it now waits for the cross,
  -- for escape, for a second right click on the window, or for a menu entry
  -- that is not a switch.
  local close = CreateFrame("Button", "AllBagsMenuClose", menu)
  close:SetWidth(16)
  close:SetHeight(16)
  close:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -6, -6)
  close:SetFont("Fonts\\FRIZQT__.TTF", 13)
  close:SetText("X")
  close:SetTextColor(1, 0.35, 0.35)
  close:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
  close:SetScript("OnClick", function() HideMenu() end)
  close:SetScript("OnEnter", EnterMenu)
  close:SetScript("OnLeave", LeaveMenu)

  EscClose("AllBagsMenu")
end

ShowMenu = function()
  BuildMenu()

  local items, n = MenuItems()
  menuTitle:SetText(ADDON .. "  |cff808080v" .. VERSION .. "|r")

  local width = menuTitle:GetStringWidth() + 24   -- room for the close cross
  local extraW = {}
  local i = 1
  while i <= n do
    local b = GetMenuButton(i)
    b:SetText(ItemLabel(items[i]))
    -- A button centres its own caption, which left the whole menu ragged:
    -- the line is pinned to the left edge instead.
    local fs = b.GetFontString and b:GetFontString()
    if fs then
      fs:ClearAllPoints()
      fs:SetPoint("LEFT", b, "LEFT", 4, 0)
      fs:SetJustifyH("LEFT")
    end
    if items[i].header then b:SetTextColor(1, 0.82, 0) else b:SetTextColor(1, 1, 1) end
    local w = b:GetTextWidth() or 0
    if items[i].right then
      -- the second button is built here, before the widths are added up, so
      -- its real width is known rather than guessed from a byte count
      local e = GetMenuExtra(i)
      e:SetText(items[i].right)
      local ew = e:GetTextWidth()
      if not ew or ew < 10 then ew = 90 end
      ew = ew + 10
      extraW[i] = ew
      w = w + ew + 16
    end
    if w > width then width = w end
    i = i + 1
  end
  width = width + MPAD * 2 + 12

  menuTitle:ClearAllPoints()
  menuTitle:SetPoint("TOPLEFT", menu, "TOPLEFT", MPAD + 2, -MPAD)

  local y = -(MPAD + TITLE_H)
  i = 1
  while i <= n do
    local item = items[i]
    local b = GetMenuButton(i)
    -- a line that carries a second button gives up that much of its own width,
    -- so the two never sit on top of each other and swallow each other's click
    b:SetWidth(width - MPAD * 2 - (extraW[i] and (extraW[i] + 6) or 0))
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", menu, "TOPLEFT", MPAD, y)
    b:SetScript("OnClick", function()
      if item.header then return end
      item.action()
      if item.keep then ShowMenu() else HideMenu() end
    end)
    b:Show()

    if item.right then
      local e = GetMenuExtra(i)
      e:SetWidth(extraW[i] or 90)
      if e.SetFrameLevel and menu.GetFrameLevel then
        local lvl = menu:GetFrameLevel()
        if type(lvl) == "number" then e:SetFrameLevel(lvl + 5) end
      end
      e:ClearAllPoints()
      e:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -MPAD, y)
      local act = item.raction
      e:SetScript("OnClick", function() HideMenu(); if act then act() end end)
      e:Show()
    elseif menuExtra[i] then
      menuExtra[i]:Hide()
    end

    y = y - ITEM_H
    i = i + 1
  end

  local j = n + 1
  while menuButtons[j] do menuButtons[j]:Hide(); j = j + 1 end
  j = n + 1
  while menuExtra[j] do menuExtra[j]:Hide(); j = j + 1 end

  menu:SetWidth(width)
  menu:SetHeight(MPAD * 2 + TITLE_H + n * ITEM_H)

  if not menu:IsShown() then
    -- once it has been dragged somewhere it stays there; before that it opens
    -- under the cursor, where the right click happened
    menu:ClearAllPoints()
    local sx, sy = AllBagsDB.menux, AllBagsDB.menuy
    local cx, cy
    if GetCursorPosition then cx, cy = GetCursorPosition() end
    if type(sx) == "number" and type(sy) == "number" then
      menu:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", sx, sy)
    elseif cx and cy then
      menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx, cy)
    else
      menu:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, 0)
    end
    everHovered, hoverCount, menuIdle = false, 0, 0
  end
  menu:Show()
end

local function ToggleMenu()
  if menu and menu:IsShown() then HideMenu() else ShowMenu() end
end

----------------------------------------------------------------------
-- window
----------------------------------------------------------------------

ApplyBorder = function()
  if not frame then return end
  local e = AllBagsDB and AllBagsDB.border or 6
  if type(e) ~= "number" or e < 2 then e = 6 end
  if e > 24 then e = 24 end

  local inset = math.floor(e / 2)
  if inset < 1 then inset = 1 end

  frame:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tileSize = 16, edgeSize = e,
    insets   = { left = inset, right = inset, top = inset, bottom = inset },
  })
  -- SetBackdrop resets the colours, so set them again
  frame:SetBackdropColor(0, 0, 0, 0.9)
  frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
end

ApplyPosition = function()
  if not frame then return end
  frame:ClearAllPoints()

  local x, y = AllBagsDB.x, AllBagsDB.y
  if type(x) == "number" and type(y) == "number" then
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
  else
    frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -DEFAULT_MARGIN, DEFAULT_MARGIN)
  end
end

SavePosition = function()
  if not frame then return end

  local left, bottom = frame:GetLeft(), frame:GetBottom()
  if type(left) ~= "number" or type(bottom) ~= "number" then return end

  AllBagsDB.x, AllBagsDB.y = left, bottom

  -- normalise the anchor to the same form used on restore: the window then
  -- grows upwards when the row count changes and the bottom edge stays put
  frame:ClearAllPoints()
  frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
end

local function BuildFrame()
  frame = CreateFrame("Frame", "AllBagsFrame", UIParent)
  frame:SetFrameStrata("HIGH")
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetWidth(400)
  frame:SetHeight(300)
  frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -DEFAULT_MARGIN, DEFAULT_MARGIN)
  ApplyBorder()
  frame:Hide()

  local moving = false
  frame:SetScript("OnMouseDown", function(self, button)
    local btn = button or arg1
    if btn == "RightButton" then
      ToggleMenu()
      return
    end
    if (btn == nil or btn == "LeftButton") and not moving then
      moving = true
      frame:StartMoving()
    end
  end)
  frame:SetScript("OnMouseUp", function()
    if moving then
      moving = false
      frame:StopMovingOrSizing()
      SavePosition()
    end
  end)
  frame:SetScript("OnDragStart", function()
    if not moving then moving = true; frame:StartMoving() end
  end)
  frame:SetScript("OnDragStop", function()
    if moving then moving = false; frame:StopMovingOrSizing(); SavePosition() end
  end)

  header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  if not header:GetFont() or header:GetFont() == "" then
    header:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
  end
  header:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 2, -7)
  header:SetWidth(120)
  header:SetJustifyH("LEFT")
  header:SetTextColor(1, 0.82, 0)

  hintText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  if not hintText:GetFont() or hintText:GetFont() == "" then
    hintText:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
  end
  hintText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD - 2, 7)
  hintText:SetJustifyH("RIGHT")
  hintText:SetTextColor(0.6, 0.6, 0.6)

  moneyText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  if not moneyText:GetFont() or moneyText:GetFont() == "" then
    moneyText:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
  end
  moneyText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD + 2, 6)
  moneyText:SetJustifyH("LEFT")

  closeButton = CreateFrame("Button", "AllBagsClose", frame)
  closeButton:SetWidth(18)
  closeButton:SetHeight(18)
  closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
  closeButton:SetFont("Fonts\\FRIZQT__.TTF", 14)
  closeButton:SetText("X")
  closeButton:SetTextColor(1, 0.35, 0.35)
  closeButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
  closeButton:SetScript("OnClick", function() frame:Hide() end)

  -- A settings button used to sit here between the sort switch and the close
  -- cross. It crowded a header that is only 300 wide: settings live on the
  -- sort line of the right click menu instead.

  sortButton = CreateFrame("Button", "AllBagsSort", frame)
  sortButton:SetWidth(150)
  sortButton:SetHeight(17)
  -- Centred, not pinned to the right: the close cross owns that corner and
  -- the switch pressed against it looked like part of the cross.
  sortButton:SetPoint("TOP", frame, "TOP", 0, -6)
  sortButton:SetFont("Fonts\\FRIZQT__.TTF", 11)
  sortButton:SetTextColor(1, 1, 1)
  sortButton:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tileSize = 16, edgeSize = 10,
    insets   = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  sortButton:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
  sortButton:SetBackdropBorderColor(0.45, 0.45, 0.45, 0.9)
  sortButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")

  -- The "Off" button used to sit here, one step from the close cross, and a
  -- miss disabled the whole addon. Turning it off lives in the right click
  -- menu only, where nobody lands by accident.

  sortButton:SetScript("OnClick", function()
    AllBagsDB.sort = (AllBagsDB.sort == "quality") and "bag" or "quality"
    dirty = true
    Refresh()
  end)

  frame:SetScript("OnShow", function()
    ApplyPosition()
    header:SetText(L("title"))
    hintText:SetText(L("hint"))
    dirty = true
    Refresh()
  end)

  frame:SetScript("OnUpdate", function(self, elapsed)
    local e = elapsed or arg1 or 0
    timer = timer + e
    if timer >= 0.5 then timer = 0; dirty = true end
    if dirty then dirty = false; Refresh() end
  end)
end

----------------------------------------------------------------------
-- show / hide and hooks over the default bag functions
----------------------------------------------------------------------

----------------------------------------------------------------------
-- settings window (/bags config)
----------------------------------------------------------------------

local KEY_LABEL = {
  fav = "kFav", quality = "kQuality", type = "kType", name = "kName",
  count = "kCount", bag = "kBag",
}

local cfg                  -- the window, built the first time it is asked for
local cfgRows = {}         -- n -> { up, down, box, label }
local cfgNum  = {}         -- field -> FontString with the current number
local cfgFS   = {}         -- name -> caption that has to follow the language
local cfgBox               -- the "split by bag" checkbox
local cfgSortBox           -- sorting on or off, the same switch as the header
local CfgRefresh

-- Both side windows remember where they were left, the same way the main one
-- does: absolute left and bottom, because StartMoving re-anchors the frame and
-- a saved anchor pair could put it somewhere else on the next login.
local function CfgButton(parent, w, h, text)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(w)
  b:SetHeight(h)
  b:SetFont("Fonts\\FRIZQT__.TTF", 11)
  b:SetText(text)
  b:SetTextColor(1, 1, 1)
  b:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tileSize = 16, edgeSize = 8,
    insets   = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  b:SetBackdropColor(0.12, 0.12, 0.12, 0.9)
  b:SetBackdropBorderColor(0.45, 0.45, 0.45, 0.9)
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
  return b
end

-- Every caption is given a width and a justification: left to itself a
-- FontString centres on its anchor and the column comes out ragged.
local function CfgText(parent, x, y, w, size, r, g, b, just)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetFont("Fonts\\FRIZQT__.TTF", size, "")
  fs:SetTextColor(r, g, b)
  fs:SetWidth(w)
  fs:SetHeight(size + 4)
  fs:SetJustifyH(just or "LEFT")
  fs:SetJustifyV("MIDDLE")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  return fs
end

-- Moves one criterion up or down the list. The order is what the comparison
-- walks, so the top line is the coarse grouping.
local function MoveKey(n, dir)
  local ord = AllBagsDB.order
  local m = n + dir
  if not ord or not ord[n] or not ord[m] then return end
  ord[n], ord[m] = ord[m], ord[n]
  dirty = true
  CfgRefresh()
end

local CFG_W = 320
local CFG_LEFT, CFG_RIGHT = 14, 14

local function CfgStepper(y, key, field, lo, hi, step)
  cfgFS[field] = CfgText(cfg, CFG_LEFT, y, CFG_W - CFG_LEFT - 96, 11, 0.82, 0.82, 0.82)

  local minus = CfgButton(cfg, 18, 18, "-")
  minus:SetPoint("TOPLEFT", cfg, "TOPLEFT", CFG_W - 90, y - 1)

  cfgNum[field] = CfgText(cfg, CFG_W - 68, y, 34, 12, 1, 0.82, 0, "CENTER")

  local plus = CfgButton(cfg, 18, 18, "+")
  plus:SetPoint("TOPLEFT", cfg, "TOPLEFT", CFG_W - 32 - CFG_RIGHT + 10, y - 1)

  local function bump(d)
    local v
    if field == "csize" then
      -- the figure size is not a free number: it steps between the font
      -- objects the client actually has
      local cur, k = 1, 1
      local now = CountFontEntry(AllBagsDB.csize)
      while COUNT_FONTS[k] do
        if COUNT_FONTS[k].o == now.o then cur = k end
        k = k + 1
      end
      cur = cur + d
      if cur < 1 then cur = 1 elseif not COUNT_FONTS[cur] then cur = cur - 1 end
      v = COUNT_FONTS[cur].n
    else
      v = (AllBagsDB[field] or lo) + d * step
      if v < lo then v = lo elseif v > hi then v = hi end
    end
    AllBagsDB[field] = v
    lastCols = -1
    dirty = true
    Refresh()
    CfgRefresh()
  end

  minus:SetScript("OnClick", function() bump(-1) end)
  plus:SetScript("OnClick", function() bump(1) end)
  cfgFS[field].key = key
end

local function BuildConfig()
  cfg = CreateFrame("Frame", "AllBagsConfig", UIParent)
  cfg:SetFrameStrata("FULLSCREEN_DIALOG")
  cfg:SetToplevel(true)
  cfg:SetClampedToScreen(true)
  cfg:SetMovable(true)
  cfg:EnableMouse(true)
  cfg:SetWidth(CFG_W)
  cfg:SetHeight(300)
  cfg:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets   = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  cfg:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
  cfg:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
  cfg:Hide()
  EscClose("AllBagsConfig")

  -- RegisterForDrag answers on buttons only in this client, so the window is
  -- dragged by hand from the mouse events.
  local moving = false
  cfg:SetScript("OnMouseDown", function()
    if not moving then moving = true; cfg:StartMoving() end
  end)
  cfg:SetScript("OnMouseUp", function()
    if moving then
      moving = false
      cfg:StopMovingOrSizing()
      SaveWinPos(cfg, "cfgx", "cfgy")
    end
  end)

  cfgFS.title = CfgText(cfg, CFG_LEFT, -10, CFG_W - CFG_LEFT * 2 - 20, 13, 1, 0.82, 0)
  cfgFS.hint  = CfgText(cfg, CFG_LEFT, -28, CFG_W - CFG_LEFT * 2, 10, 0.55, 0.55, 0.55)
  cfgSortBox = CfgButton(cfg, 16, 16, "")
  cfgSortBox:SetPoint("TOPLEFT", cfg, "TOPLEFT", CFG_LEFT, -47)
  cfgSortBox:SetScript("OnClick", function()
    AllBagsDB.sort = (AllBagsDB.sort == "quality") and "bag" or "quality"
    dirty = true
    CfgRefresh()
    Refresh()
  end)
  cfgFS.sort = CfgText(cfg, CFG_LEFT + 24, -48, CFG_W - CFG_LEFT * 2 - 24, 11, 0.75, 0.75, 0.75)

  local close = CfgButton(cfg, 18, 18, "X")
  close:SetPoint("TOPRIGHT", cfg, "TOPRIGHT", -6, -6)
  close:SetTextColor(1, 0.35, 0.35)
  close:SetScript("OnClick", function() cfg:Hide() end)

  local y = -66
  local i = 1
  while i <= Count(SORT_KEYS) do
    local n = i
    local row = {}

    row.up = CfgButton(cfg, 16, 16, "^")
    row.up:SetPoint("TOPLEFT", cfg, "TOPLEFT", CFG_LEFT, y)
    row.up:SetScript("OnClick", function() MoveKey(n, -1) end)

    row.down = CfgButton(cfg, 16, 16, "v")
    row.down:SetPoint("TOPLEFT", cfg, "TOPLEFT", CFG_LEFT + 18, y)
    row.down:SetScript("OnClick", function() MoveKey(n, 1) end)

    row.box = CfgButton(cfg, 16, 16, "")
    row.box:SetPoint("TOPLEFT", cfg, "TOPLEFT", CFG_LEFT + 42, y)
    row.box:SetScript("OnClick", function()
      local e = AllBagsDB.order and AllBagsDB.order[n]
      if not e then return end
      e.on = not e.on
      dirty = true
      CfgRefresh()
    end)

    row.label = CfgText(cfg, CFG_LEFT + 66, y - 1, CFG_W - CFG_LEFT - 80, 12, 1, 1, 1)
    cfgRows[i] = row

    y = y - 20
    i = i + 1
  end

  y = y - 4
  local types = CfgButton(cfg, CFG_W - CFG_LEFT * 2 - 42, 18, "")
  types:SetPoint("TOPLEFT", cfg, "TOPLEFT", CFG_LEFT + 42, y)
  types:SetScript("OnClick", function() ShowTypes() end)
  cfg.types = types

  y = y - 22
  cfgFS.favhint = CfgText(cfg, CFG_LEFT, y, CFG_W - CFG_LEFT * 2, 10, 0.55, 0.55, 0.55)

  y = y - 18
  CfgStepper(y, "cfgSize", "csize", 8, 24, 1)
  y = y - 22
  CfgStepper(y, "cfgCols", "cols", 4, 20, 1)
  y = y - 22
  CfgStepper(y, "cfgLine", "line", 0, 6, 1)
  y = y - 26

  cfgBox = CfgButton(cfg, 16, 16, "")
  cfgBox:SetPoint("TOPLEFT", cfg, "TOPLEFT", CFG_LEFT, y)
  cfgBox:SetScript("OnClick", function()
    AllBagsDB.groups = not AllBagsDB.groups
    dirty = true
    CfgRefresh()
    Refresh()
  end)
  cfgFS.group = CfgText(cfg, CFG_LEFT + 24, y - 1, CFG_W - CFG_LEFT - 38, 11, 0.85, 0.85, 0.85)
  y = y - 30

  local done = CfgButton(cfg, 90, 20, "")
  done:SetPoint("TOP", cfg, "TOP", 0, y + 2)
  done:SetScript("OnClick", function() cfg:Hide() end)
  cfg.done = done

  cfg:SetHeight(-y + 24)
end

CfgRefresh = function()
  if not cfg then return end
  cfgFS.title:SetText(L("cfgTitle"))
  cfgFS.hint:SetText(L("cfgHint"))
  cfgFS.sort:SetText(L("cfgSort") .. ":")

  local sorting = (AllBagsDB.sort == "quality")
  cfgSortBox:SetText(sorting and "x" or "")
  cfgSortBox:SetBackdropBorderColor(sorting and 1 or 0.4, sorting and 0.82 or 0.4,
                                    sorting and 0 or 0.4, 1)
  cfgFS.sort:SetTextColor(sorting and 0.85 or 0.45, sorting and 0.85 or 0.45,
                          sorting and 0.85 or 0.45)
  cfgFS.group:SetText(L("cfgGroup"))
  cfgFS.favhint:SetText(L("favHint"))
  cfg.types:SetText(L("cfgTypes"))
  cfg.done:SetText(L("cfgClose"))

  local ord = AllBagsDB.order or {}
  local i = 1
  while cfgRows[i] do
    local e = ord[i]
    local row = cfgRows[i]
    if e then
      row.label:SetText(L(KEY_LABEL[e.k] or e.k))
      row.box:SetText(e.on and "x" or "")
      if e.on then
        row.label:SetTextColor(1, 1, 1)
        row.box:SetBackdropBorderColor(1, 0.82, 0, 1)
      else
        row.label:SetTextColor(0.45, 0.45, 0.45)
        row.box:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.9)
      end
      if i == 1 then row.up:Disable() else row.up:Enable() end
      if ord[i + 1] then row.down:Enable() else row.down:Disable() end
    else
      row.label:SetText("")
      row.box:SetText("")
    end
    i = i + 1
  end

  cfgBox:SetText(AllBagsDB.groups and "x" or "")
  cfgBox:SetBackdropBorderColor(AllBagsDB.groups and 1 or 0.4,
                                AllBagsDB.groups and 0.82 or 0.4,
                                AllBagsDB.groups and 0 or 0.4, 1)

  local f = 1
  local fields = { "csize", "cols", "line" }
  while fields[f] do
    local k = fields[f]
    if cfgFS[k] then cfgFS[k]:SetText(L(cfgFS[k].key)) end
    if cfgNum[k] then cfgNum[k]:SetText("" .. (AllBagsDB[k] or 0)) end
    f = f + 1
  end
end

----------------------------------------------------------------------
-- type order window
----------------------------------------------------------------------

local tw                   -- the window
local twRows = {}          -- n -> { up, down, label }
local twFS = {}            -- captions that follow the language
local TW_ROWS = 16         -- more classes than this client has
local TwRefresh

local function MoveType(n, dir)
  local list = AllBagsDB.types
  local m = n + dir
  if type(list) ~= "table" or not list[n] or not list[m] then return end
  list[n], list[m] = list[m], list[n]
  dirty = true
  TwRefresh()
end

local function BuildTypes()
  tw = CreateFrame("Frame", "AllBagsTypes", UIParent)
  tw:SetFrameStrata("FULLSCREEN_DIALOG")
  tw:SetToplevel(true)
  tw:SetClampedToScreen(true)
  tw:SetMovable(true)
  tw:EnableMouse(true)
  tw:SetWidth(CFG_W)
  tw:SetHeight(200)
  tw:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets   = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  tw:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
  tw:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
  tw:Hide()
  EscClose("AllBagsTypes")

  local moving = false
  tw:SetScript("OnMouseDown", function()
    if not moving then moving = true; tw:StartMoving() end
  end)
  tw:SetScript("OnMouseUp", function()
    if moving then
      moving = false
      tw:StopMovingOrSizing()
      SaveWinPos(tw, "twx", "twy")
    end
  end)

  twFS.title = CfgText(tw, CFG_LEFT, -10, CFG_W - CFG_LEFT * 2 - 20, 13, 1, 0.82, 0)
  twFS.hint  = CfgText(tw, CFG_LEFT, -28, CFG_W - CFG_LEFT * 2, 10, 0.55, 0.55, 0.55)

  local close = CfgButton(tw, 18, 18, "X")
  close:SetPoint("TOPRIGHT", tw, "TOPRIGHT", -6, -6)
  close:SetTextColor(1, 0.35, 0.35)
  close:SetScript("OnClick", function() tw:Hide() end)

  local y = -48
  local i = 1
  while i <= TW_ROWS do
    local n = i
    local row = {}
    row.up = CfgButton(tw, 16, 16, "^")
    row.up:SetPoint("TOPLEFT", tw, "TOPLEFT", CFG_LEFT, y)
    row.up:SetScript("OnClick", function() MoveType(n, -1) end)

    row.down = CfgButton(tw, 16, 16, "v")
    row.down:SetPoint("TOPLEFT", tw, "TOPLEFT", CFG_LEFT + 18, y)
    row.down:SetScript("OnClick", function() MoveType(n, 1) end)

    row.label = CfgText(tw, CFG_LEFT + 42, y - 1, CFG_W - CFG_LEFT - 56, 12, 1, 1, 1)
    twRows[i] = row
    row.y = y
    y = y - 20
    i = i + 1
  end

  local done = CfgButton(tw, 90, 20, "")
  done:SetPoint("TOP", tw, "TOP", 0, 0)
  done:SetScript("OnClick", function() tw:Hide() end)
  tw.done = done
end

TwRefresh = function()
  if not tw then return end
  twFS.title:SetText(L("tTitle"))
  tw.done:SetText(L("cfgClose"))

  local list = AllBagsDB.types
  local n = Count(list)
  twFS.hint:SetText(n > 0 and L("tHint") or L("tEmpty"))

  local i = 1
  while twRows[i] do
    local row = twRows[i]
    if i <= n and i <= TW_ROWS then
      row.label:SetText(list[i])
      row.label:Show(); row.up:Show(); row.down:Show()
      if i == 1 then row.up:Disable() else row.up:Enable() end
      if i < n and i < TW_ROWS then row.down:Enable() else row.down:Disable() end
    else
      row.label:SetText("")
      row.label:Hide(); row.up:Hide(); row.down:Hide()
    end
    i = i + 1
  end

  -- the window is only as tall as the list it holds
  local shown = n
  if shown > TW_ROWS then shown = TW_ROWS end
  if shown < 1 then shown = 1 end
  local bottom = -48 - shown * 20 - 8
  tw.done:ClearAllPoints()
  tw.done:SetPoint("TOP", tw, "TOP", 0, bottom)
  tw:SetHeight(-bottom + 26)
end

ShowTypes = function()
  if not tw then BuildTypes() end
  TwRefresh()
  if tw:IsShown() then
    tw:Hide()
  else
    ApplyWinPos(tw, "twx", "twy", CFG_W + 20, 60)
    tw:Show()
  end
end

ShowConfig = function()
  if not cfg then BuildConfig() end
  CfgRefresh()
  if cfg:IsShown() then
    cfg:Hide()
  else
    HideMenu()          -- the menu is what usually opens this, and it overlaps
    ApplyWinPos(cfg, "cfgx", "cfgy", 0, 60)
    cfg:Show()
  end
end

local orig = {}
local hookedCount = 0
local hooksDone = false

local function CloseDefaultBags()
  local o = orig.CloseAllBags
  if o and o ~= CloseAllBags then o() end
end


local function ShowBags()
  if not AllBagsDB.enabled then return end
  CloseDefaultBags()
  frame:Show()
end

local function HideBags()
  HideMenu()
  frame:Hide()
end

local function ToggleBags()
  if frame:IsShown() then HideBags() else ShowBags() end
end

-- The bag key (B by default) calls FrameXML functions, not the game API.
-- Hook them when present: whatever key is bound, a click on a bag button and
-- the merchant auto-open then all lead into this window.
local function CallOriginal(name, a1)
  local o = orig[name]
  if not o then return end
  if name == "ToggleBackpack" and o == ToggleBackpack then return end
  if name == "OpenBackpack"   and o == OpenBackpack   then return end
  if name == "OpenAllBags"    and o == OpenAllBags    then return end
  if name == "ToggleBag"      and o == ToggleBag      then return end
  if name == "CloseAllBags"   and o == CloseAllBags   then return end
  if name == "CloseBackpack"  and o == CloseBackpack  then return end
  o(a1)
end

SetEnabled = function(on)
  AllBagsDB.enabled = on and true or false
  if not AllBagsDB.enabled then
    HideMenu()
    frame:Hide()
    Print(L("msgOff"))
  else
    Print(L("msgOn"))
  end
end

local function HookBagFunctions()
  -- Called on both VARIABLES_LOADED and PLAYER_LOGIN. Without this latch the
  -- second pass would store the already hooked function into orig, and it would
  -- then call itself until the stack overflows.
  if hooksDone then return hookedCount end
  hooksDone = true

  local hooked = 0
  local function take(name, original)
    if type(original) ~= "function" then return false end
    if orig[name] then return false end
    orig[name] = original
    hooked = hooked + 1
    return true
  end

  if take("ToggleBackpack", ToggleBackpack) then
    ToggleBackpack = function()
      if AllBagsDB.enabled then ToggleBags() else CallOriginal("ToggleBackpack") end
    end
  end

  if take("OpenBackpack", OpenBackpack) then
    OpenBackpack = function()
      if AllBagsDB.enabled then ShowBags() else CallOriginal("OpenBackpack") end
    end
  end

  if take("OpenAllBags", OpenAllBags) then
    OpenAllBags = function()
      if AllBagsDB.enabled then ToggleBags() else CallOriginal("OpenAllBags") end
    end
  end

  if take("ToggleBag", ToggleBag) then
    ToggleBag = function(id)
      -- Only the backpack itself opens our window. The side bags and above
      -- all the bank bags (5 to 10) must keep their own windows: clicking a
      -- bag inside the bank used to open the combined window instead of the
      -- bag, which made the bank unusable.
      if AllBagsDB.enabled and (id == 0 or id == nil) then
        ToggleBags()
      else
        CallOriginal("ToggleBag", id)
      end
    end
  end

  if take("CloseAllBags", CloseAllBags) then
    CloseAllBags = function()
      HideBags()
      CallOriginal("CloseAllBags")
    end
  end

  if take("CloseBackpack", CloseBackpack) then
    CloseBackpack = function()
      HideBags()
      CallOriginal("CloseBackpack")
    end
  end

  hookedCount = hooked
  return hooked
end

----------------------------------------------------------------------
-- slash commands
----------------------------------------------------------------------

local function HandleSlash(msg)
  msg = string.lower(msg or "")
  msg = string.gsub(msg, "^%s+", "")
  msg = string.gsub(msg, "%s+$", "")

  if msg == "" or msg == "toggle" then
    if AllBagsDB.enabled then ToggleBags() else Print(L("msgOff")) end

  elseif msg == "menu" then
    ToggleMenu()

  elseif msg == "config" or msg == "cfg" or msg == "options" then
    ShowConfig()

  elseif msg == "types" then
    ShowTypes()

  elseif msg == "font" then
    -- what the client really put on a stack figure, for when a size looks wrong
    local fs = countFS[1]
    if not fs then
      Print("open the bags first")
    else
      local path, size, flags = fs:GetFont()
      local e = CountFontEntry(AllBagsDB.csize)
      Print("csize " .. tostring(AllBagsDB.csize) .. " -> " .. e.o
        .. " -> " .. tostring(path) .. " / " .. tostring(size)
        .. " / " .. tostring(flags))
    end

  elseif msg == "fav" or msg == "fav clear" then
    if msg == "fav clear" then
      AllBagsDB.fav = {}
      dirty = true
      Print(L("favClear"))
    else
      local list, n = "", 0
      for k in pairs(AllBagsDB.fav or {}) do
        n = n + 1
        list = (n == 1) and k or (list .. ", " .. k)
      end
      if n == 0 then Print(L("favNone")) else Print(string.format(L("favList"), list)) end
    end

  elseif msg == "off" then
    SetEnabled(false)

  elseif msg == "on" then
    SetEnabled(true)

  elseif msg == "value" then
    AllBagsDB.value = not AllBagsDB.value
    dirty = true
    Print(string.format(L("valueSet"), AllBagsDB.value and L("on") or L("off")))
    if AllBagsDB.value and not PriceApi() then
      Print("|cff808080" .. L("noPriceAddon") .. "|r")
    end

  elseif msg == "sort" then
    AllBagsDB.sort = (AllBagsDB.sort == "quality") and "bag" or "quality"
    dirty = true
    Print(AllBagsDB.sort == "quality" and L("sortQ") or L("sortN"))

  elseif string.sub(msg, 1, 4) == "cols" then
    local _, _, n = string.find(msg, "^cols%s+(%d+)$")
    n = tonumber(n)
    if n and n >= 4 and n <= 20 then
      AllBagsDB.cols = n
      lastCols = -1
      dirty = true
      Print(string.format(L("colsSet"), n))
    else
      Print(L("colsErr"))
    end

  elseif string.sub(msg, 1, 6) == "border" then
    local _, _, v = string.find(msg, "^border%s+(%d+)$")
    v = tonumber(v)
    if v and v >= 2 and v <= 24 then
      AllBagsDB.border = v
      ApplyBorder()
      Print(string.format(L("lineSet"), tostring(v)))
    else
      Print("/bags border 5 | 10 | 16  (2-24)")
    end

  elseif string.sub(msg, 1, 4) == "lang" then
    local _, _, which = string.find(msg, "^lang%s+(%a+)$")
    if which == "ru" or which == "en" or which == "auto" then
      AllBagsDB.lang = which
      dirty = true
      Print(string.format(L("langSet"), which))
    else
      Print("lang: ru | en | auto")
    end

  elseif msg == "reset" then
    AllBagsDB.x, AllBagsDB.y = nil, nil
    ApplyPosition()
    Print(L("reset"))

  elseif msg == "debug" then
    Print("v" .. VERSION .. ", перехвачено функций сумок: " .. hookedCount
      .. ", слотов: " .. slotCount .. ", столбцов: " .. AllBagsDB.cols)

  else
    Print(L("help"))
  end
end

----------------------------------------------------------------------
-- events
----------------------------------------------------------------------

local function InitDB()
  if type(AllBagsDB) ~= "table" then AllBagsDB = {} end
  for k, v in pairs(defaults) do
    if AllBagsDB[k] == nil then AllBagsDB[k] = v end
  end

  -- The sort order is a list, not a plain value, and an older save has none
  -- or is a version short of a key. Whatever is already there and still valid
  -- keeps its place; anything missing is put back where it belongs by default.
  local ord = AllBagsDB.order
  if type(ord) ~= "table" then ord = {}; AllBagsDB.order = ord end

  local keep, n = {}, 0
  local i = 1
  while ord[i] do
    local e = ord[i]
    if type(e) == "table" and e.k then
      local known, j = false, 1
      while SORT_KEYS[j] do
        if SORT_KEYS[j] == e.k then known = true end
        j = j + 1
      end
      local dup, m = false, 1
      while m <= n do
        if keep[m].k == e.k then dup = true end
        m = m + 1
      end
      if known and not dup then
        n = n + 1
        keep[n] = { k = e.k, on = (e.on and true or false) }
      end
    end
    i = i + 1
  end

  -- put back anything the save did not have, in the order the defaults use
  local def = DefaultOrder()
  local d = 1
  while def[d] do
    local have, m = false, 1
    while m <= n do
      if keep[m].k == def[d].k then have = true end
      m = m + 1
    end
    if not have then
      -- insert it at its default place, so a new key does not simply land last
      local at = d
      if at > n + 1 then at = n + 1 end
      local q = n
      while q >= at do keep[q + 1] = keep[q]; q = q - 1 end
      keep[at] = { k = def[d].k, on = def[d].on }
      n = n + 1
    end
    d = d + 1
  end
  AllBagsDB.order = keep

  if type(AllBagsDB.fav) ~= "table" then AllBagsDB.fav = {} end
  if type(AllBagsDB.types) ~= "table" then AllBagsDB.types = {} end

  -- snap the figure size onto one of the sizes the client can actually draw
  if type(AllBagsDB.csize) ~= "number" then AllBagsDB.csize = defaults.csize end
  AllBagsDB.csize = CountFontEntry(AllBagsDB.csize).n
  if type(AllBagsDB.groups) ~= "boolean" then AllBagsDB.groups = defaults.groups end
end

local function OnEvent(self, ev)
  ev = ev or event
  if ev == "VARIABLES_LOADED" or ev == "PLAYER_LOGIN" then
    InitDB()
    ApplyBorder()
    ApplyPosition()
    HookBagFunctions()
    if not greeted then
      greeted = true
      Print(string.format(L("loaded"), ADDON .. " " .. VERSION))
    end
  end
  dirty = true
end

InitDB()
BuildFrame()

local loader = CreateFrame("Frame", "AllBagsLoader")
loader:SetScript("OnEvent", OnEvent)
loader:RegisterEvent("VARIABLES_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:RegisterEvent("BAG_UPDATE")
loader:RegisterEvent("BAG_CLOSED")
loader:RegisterEvent("ITEM_LOCK_CHANGED")
loader:RegisterEvent("PLAYER_MONEY")
loader:RegisterEvent("UNIT_INVENTORY_CHANGED")

SLASH_ALLBAGS1 = "/allbags"
SLASH_ALLBAGS2 = "/bags"
SlashCmdList["ALLBAGS"] = HandleSlash
