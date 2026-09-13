--[[--------------------------------------------------------------------
  AllBags 1.3.8
  All bags (0-4) in one window. Client 1.12.1 / Lua 5.1 (Emberveil).

  The sort is VIRTUAL: nothing moves inside the bags, only the display order
  in the grid changes. Moving items for real would take dozens of consecutive
  PickupContainerItem calls and falls apart on any network hiccup.
----------------------------------------------------------------------]]

local ADDON   = "AllBags"
local VERSION = "1.3.0"

local FIRST_BAG, LAST_BAG = 0, 4

-- GAP and PAD are set by ApplyMetrics: both depend on which style of frame
-- and which style of slot the player picked.
local SIZE, GAP, PAD = 32, 0, 4
-- 0 means "exactly what the client does": the whole 64 pixel picture drawn
-- at 64 pixels on a 37 pixel cell, so the hole in the art is the cell and
-- the metal hangs outside it. A value above 0 crops the picture to its inner
-- frame and draws it at cell size instead - a tighter grid, no overhang.
local RING_CROP = 0
local STOCK_GAP = 4
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
  frameStyle = "dialog",   -- "dialog" for the stock carved edge, "tooltip" for the thin one
  slotStyle  = "stock",    -- "stock" for Blizzard's container buttons, "plain" for our grid
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
    cfgFrame = "Рамка окна",
    cfgSlot  = "Ячейки",
    slStock  = "штатные",
    bedFlat  = "ровный тёмный",
    slPlain  = "простые",
    frDialog = "штатная",
    frTip    = "простая",
    sortQ    = "По качеству",
    sortN    = "По сумкам",
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
    help     = "команды: /bags [config | vault | types | fav | menu | sort | cols N | value | hover | lang ru/en/auto | on | off | reset]. Внешний вид: frame, slots",
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
    mVault   = "Другие персонажи...",
    mAlts    = "Альты",
    cfgOpen  = "Настройки",
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
    cfgFrame = "Window frame",
    cfgSlot  = "Slots",
    slStock  = "stock",
    bedFlat  = "flat dark",
    slPlain  = "plain",
    frDialog = "stock",
    frTip    = "plain",
    sortQ    = "By quality",
    sortN    = "By bag",
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
    help     = "commands: /bags [config | vault | types | fav | menu | sort | cols N | value | hover | lang ru/en/auto | on | off | reset]. Looks: frame, slots",
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
    mVault   = "Other characters...",
    mAlts    = "Alts",
    cfgOpen  = "Settings",
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
local cfgButton
local coin, freeText
local valStrip, bankStrip
local vaultButton, AnchorChrome
-- One footer line, or two. Coins are wider than "6g 44s 63c" ever was, so on
-- a ten column window the money ran straight into the value on the right.
-- The value moves up a line instead of overlapping, and the window grows by
-- that line only while there is a value to show.
local footerRows = 1
-- Whether each slot is one of Blizzard's own container buttons. The two kinds
-- are drawn differently: the stock one carries the slot art as its normal
-- texture and the item picture in a texture of its own, ours puts the item
-- picture ON the normal texture and paints the cell behind it.
local stockSlot = {}

-- Probed on this client (UiProbe 0.1.1): this atlas draws, and its four
-- quarters are gold, silver, copper and an empty one.
local MONEY_ATLAS = "Interface\\MoneyFrame\\UI-MoneyIcons"
local COIN = 14

-- Blizzard's own widget templates. Also probed: all four exist here, and a
-- caption on a templated button draws - which a caption on a bare button
-- does not, because a bare button has no FontString to write into.
local TMPL_BTN   = "UIPanelButtonTemplate"
local TMPL_CHECK = "UICheckButtonTemplate"
local TMPL_CLOSE = "UIPanelCloseButton"
local TMPL_SLIDER = "OptionsSliderTemplate"
local buttons = {}      -- i -> Button
local hoverIndex = nil  -- cell the cursor is over, for the public helpers below
local countFS  = {}     -- i -> stack count FontString
-- What the last hover worked out, for /bags hover: an empty tooltip cannot be
-- diagnosed from a screenshot.
local lastHover = ""
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
local Dialog, ApplyMetrics, FootY    -- assigned below, used from Refresh above
local StockSlots
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

-- A template this client might not have should not take the window down
-- with it, so every one of them is tried and the plain build is the fallback.
local function Templated(kind, name, parent, template)
  local made
  local ok = pcall(function() made = CreateFrame(kind, name, parent, template) end)
  if ok and made then return made end
  return nil
end

local function TextW(fs)
  if not fs then return 0 end
  local t = fs.GetText and fs:GetText()
  if not t or t == "" then return 0 end
  if fs.GetStringWidth then
    local ok, got = pcall(function() return fs:GetStringWidth() end)
    if ok and type(got) == "number" and got > 0 then return got end
  end
  local plain = string.gsub(t, "|c%x%x%x%x%x%x%x%x", "")
  plain = string.gsub(plain, "|r", "")
  return string.len(plain) * 5
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

-- Money as coin icons, laid out left to right, the way the game does it.
-- The higher denominations disappear when they are zero: "0g 0s 30c" is
-- three lies about how rich you are.
local function DrawMoney(copper, tail)
  if not coin or not moneyText then return end
  copper = copper or 0
  local g = math.floor(copper / 10000)
  local s = math.floor(copper / 100) - g * 100
  local c = copper - math.floor(copper / 100) * 100
  local val = { g, s, c }
  local show = { g > 0, (g > 0 or s > 0), true }

  -- the purse lives on the upper of the two footer lines
  local base = FootY() + 18
  local x = PAD + 2
  moneyText:ClearAllPoints()
  moneyText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, base)
  x = x + TextW(moneyText) + 7

  local k = 1
  while k <= 3 do
    local ci = coin[k]
    if show[k] then
      ci.num:SetText(val[k])
      ci.num:ClearAllPoints()
      ci.num:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, base)
      ci.num:Show()
      x = x + TextW(ci.num) + 1

      ci.icon:ClearAllPoints()
      ci.icon:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, base - 1)
      ci.icon:Show()
      x = x + COIN + 6
    else
      ci.icon:Hide()
      ci.num:Hide()
    end
    k = k + 1
  end

  -- the tail is drawn by Refresh on the lower line now; DrawMoney only ever
  -- gets an empty one, and an empty FontString takes no room anyway
  if tail and tail ~= "" then
    freeText:ClearAllPoints()
    freeText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, base)
    freeText:SetText(tail)
  end
end

-- A run of "label 7(gold) 51(silver) 30(copper)" laid out by hand. The
-- client has no way to put a picture inside a line of text: the |T...|t
-- escape that vanilla uses for exactly this came out as raw characters when
-- probed (UiProbe 0.1.6), so every coin has to be a texture of its own,
-- anchored next to a number of its own. That is what a strip is.
local function CoinSplit(copper)
  copper = copper or 0
  local g = math.floor(copper / 10000)
  local s = math.floor(copper / 100) - g * 100
  local c = copper - math.floor(copper / 100) * 100
  return { g, s, c }, { g > 0, (g > 0 or s > 0), true }
end

local function NewStrip(parent, size)
  local st = { num = {}, icon = {} }
  st.label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  pcall(function() st.label:SetFont("Fonts\\FRIZQT__.TTF", size, "") end)
  st.label:SetJustifyH("LEFT")
  st.label:Hide()
  local k = 1
  while k <= 3 do
    local ic = parent:CreateTexture(nil, "OVERLAY")
    ic:SetWidth(COIN)
    ic:SetHeight(COIN)
    ic:SetTexture(MONEY_ATLAS)
    ic:SetTexCoord((k - 1) * 0.25, k * 0.25, 0, 1)
    ic:Hide()
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pcall(function() fs:SetFont("Fonts\\FRIZQT__.TTF", size, "") end)
    fs:SetJustifyH("LEFT")
    fs:Hide()
    st.icon[k], st.num[k] = ic, fs
    k = k + 1
  end
  return st
end

local function StripHide(st)
  if not st then return end
  st.label:Hide()
  local k = 1
  while k <= 3 do
    st.icon[k]:Hide()
    st.num[k]:Hide()
    k = k + 1
  end
end

-- how wide the strip will be once it says this. Measured, never assumed:
-- guessing a text width has been wrong four times in this addon already.
local function StripWidth(st, label, copper)
  st.label:SetText(label or "")
  local w = TextW(st.label)
  if w > 0 then w = w + 6 end
  local val, show = CoinSplit(copper)
  local k = 1
  while k <= 3 do
    if show[k] then
      st.num[k]:SetText(val[k])
      w = w + TextW(st.num[k]) + 1 + COIN + 6
    end
    k = k + 1
  end
  return w
end

-- places it, left to right, and answers where the next thing may start
local function StripPlace(st, parent, label, copper, x, y)
  st.label:SetText(label or "")
  st.label:ClearAllPoints()
  st.label:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, y)
  if TextW(st.label) > 0 then
    st.label:Show()
    x = x + TextW(st.label) + 6
  else
    st.label:Hide()
  end

  local val, show = CoinSplit(copper)
  local k = 1
  while k <= 3 do
    if show[k] then
      st.num[k]:SetText(val[k])
      st.num[k]:ClearAllPoints()
      st.num[k]:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, y)
      st.num[k]:Show()
      x = x + TextW(st.num[k]) + 1

      st.icon[k]:ClearAllPoints()
      st.icon[k]:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, y - 1)
      st.icon[k]:Show()
      x = x + COIN + 6
    else
      st.num[k]:Hide()
      st.icon[k]:Hide()
    end
    k = k + 1
  end
  return x
end

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
  if not i or slotBag[i] == nil then
    lastHover = "index=" .. tostring(i) .. " (nothing behind that cell)"
    if GameTooltip then GameTooltip:Hide() end
    return
  end
  if not GameTooltip then return end
  hoverIndex = i

  -- A window pinned to the right edge pushes an ANCHOR_RIGHT tooltip off the
  -- screen, and this client clamps it back as a panel instead of flipping it
  -- to the other side. So the side is picked from where the cell really is.
  local anchor = "ANCHOR_RIGHT"
  local left = self.GetLeft and self:GetLeft()
  local wide = UIParent and UIParent.GetWidth and UIParent:GetWidth()
  if left and wide and wide > 0 and left > wide * 0.55 then
    anchor = "ANCHOR_LEFT"
  end

  GameTooltip:SetOwner(self, anchor)
  GameTooltip:SetBagItem(slotBag[i], slotIdx[i])

  -- An owner with nothing put into it draws here as an empty box, so the
  -- tooltip is shown only once the client has actually filled it.
  local lines = 0
  if GameTooltip.NumLines then
    local ok, got = pcall(function() return GameTooltip:NumLines() end)
    if ok and type(got) == "number" then lines = got end
  end

  lastHover = string.format("index=%s bag=%s slot=%s anchor=%s lines=%s",
    tostring(i), tostring(slotBag[i]), tostring(slotIdx[i]), anchor,
    tostring(lines))

  if lines > 0 then GameTooltip:Show() else GameTooltip:Hide() end
end

----------------------------------------------------------------------
-- public helpers for other addons
----------------------------------------------------------------------

-- Which bag and slot one of our cells stands for; nil for any other widget.
-- for the stand: the border is applied from places the tests cannot reach
function AllBags_ApplyBorder() if ApplyBorder then ApplyBorder() end end

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

-- The slot picture, in the client's own proportions. Asked the game's own
-- bag window directly (UiProbe 0.1.3, reading ContainerFrame1Item1):
--
--   file=Interface\\Buttons\\UI-Quickslot2  size=64x64  CENTER (0,1)  texcoord=nil
--
-- So the picture is 64 pixels on a 37 pixel cell and is NOT cropped: the
-- second frame we kept seeing is the outer metal, which in the game hangs
-- over the gap between cells instead of being squeezed inside one. The
-- earlier 37x37 reading came from a templated button of our own, which
-- never got the size the container gives its children.
-- The bed an empty cell shows. In the game's own bags that is the brown hide
-- of the bag itself, and the client will not simply hand it over: GetTexture
-- answers for files that do not exist, GetNumRegions says 0 for a window
-- that plainly has art, and GetTexCoord returns nothing at all in this
-- build. What the game's own bag DID admit, asked by name (/up bag):
--
--   ContainerFrame1BackgroundMiddle1: UI-Bag-Components 256x512 TOP crop=nil
--   ContainerFrame1BackgroundMiddle2: UI-Bag-Components 256x256 TOP crop=nil
--   ContainerFrame1BackgroundBottom:  UI-Bag-Components 256x10  TOP crop=nil
--
-- So the whole sheet is drawn uncropped at three sizes, stacked from the top:
-- the holes are painted into the art for a four-column window, which is why
-- no arrangement of it fits a ten-column grid. What we can take from it is a
-- patch of plain hide. The six below were measured off the magnified sheet
-- (UiProbe 0.1.5, /up atlas) by finding the largest squares that carry no
-- metal at all: 1 and 2 are the light hide of the header strip, 3 to 6 are
-- the darker hide from inside the slot holes.
local BED_FILE = "Interface\\ContainerFrame\\UI-Bag-Components"
local BED_SPOTS = {
  { 0.4241, 0.4963, 0.2537, 0.3259 },
  { 0.5333, 0.6037, 0.2519, 0.3222 },
  { 0.5130, 0.5759, 0.4333, 0.4963 },
  { 0.5370, 0.6000, 0.7537, 0.8167 },
  { 0.3815, 0.4426, 0.4352, 0.4963 },
  { 0.5370, 0.5981, 0.5148, 0.5759 },
}
-- 3 is the one that came closest to the game's own empty cell by eye; none
-- of the six is exact, because the hide in the sheet is painted for a
-- four-column window and is lit from above, so any patch of it is a little
-- lighter or darker than the spot the game happens to show. bedShade is the
-- knob for that last bit: it multiplies the patch, so /bags bed 3 0.9 makes
-- the same hide darker without touching its grain.
local bedSpot, bedShade = 3, 1

local function ApplyBed(t)
  if not t then return end
  local sp = BED_SPOTS[bedSpot]
  if sp then
    t:SetTexture(BED_FILE)
    if t.SetTexCoord then
      pcall(function() t:SetTexCoord(sp[1], sp[2], sp[3], sp[4]) end)
    end
    if t.SetVertexColor then
      pcall(function() t:SetVertexColor(bedShade, bedShade, bedShade) end)
    end
  else
    if t.SetTexCoord then pcall(function() t:SetTexCoord(0, 1, 0, 1) end) end
    if t.SetVertexColor then
      pcall(function() t:SetVertexColor(1, 1, 1) end)
    end
    -- not black: an empty cell in the game reads as dark hide, and flat
    -- black next to the stock bag looks like a hole cut in the window
    t:SetTexture(0.11, 0.08, 0.06, 1)
  end
end

local function ApplyRing(t)
  if not t then return end
  if RING_CROP > 0 then
    t:SetWidth(SIZE)
    t:SetHeight(SIZE)
    if t.SetTexCoord then
      pcall(function()
        t:SetTexCoord(RING_CROP, 1 - RING_CROP, RING_CROP, 1 - RING_CROP)
      end)
    end
  else
    t:SetWidth(64)
    t:SetHeight(64)
    if t.SetTexCoord then pcall(function() t:SetTexCoord(0, 1, 0, 1) end) end
  end
end

local function GetSlotButton(i)
  if buttons[i] then return buttons[i] end

  local name = "AllBagsSlot" .. i

  -- The stock look, built by hand and NOT from
  -- ContainerFrameItemButtonTemplate. The template was tried first and its
  -- art was right, but on this client its own OnEnter runs as well as ours
  -- and wipes the tooltip we had just filled: /bags hover showed our fill
  -- putting 8 lines in and the box still coming up empty, with the owner
  -- reported as nil. Drawing the same three pieces ourselves keeps the look
  -- and leaves nobody else holding a script on the button.
  if StockSlots() then
    local sb = CreateFrame("Button", name, frame)
    stockSlot[i] = true
    sb:SetWidth(SIZE)
    sb:SetHeight(SIZE)
    sb:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    sb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    sb:SetScript("OnClick", ButtonClick)
    sb:SetScript("OnEnter", ButtonEnter)
    sb:SetScript("OnLeave", ButtonLeave)

    -- A flat colour behind everything, so a cell is never a hole in the
    -- window even if a file is missing. The client's own cell has no such
    -- layer, and no UI-Slot-Background either: putting one under the ring is
    -- what gave every empty cell two contours, because the two files do not
    -- keep their art in the same place.
    local fill = sb:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(sb)
    ApplyBed(fill)

    -- the whole cell, no inset: that is what the client's own icon does
    local icon = sb:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, 0)
    icon:SetWidth(SIZE)
    icon:SetHeight(SIZE)
    icon:Hide()

    -- Blizzard's own slot ring, and in Blizzard's own proportions. Their
    -- ItemButtonTemplate is a 37 pixel button carrying a 64 pixel
    -- UI-Quickslot2 centred on it, one pixel low: the hole in the art is
    -- exactly the button, and the metal hangs outside it. Squeezing the same
    -- art into 32 pixels - which is what the first attempt did - turns the
    -- ring into a thin dotted line, and that is why the cells did not look
    -- like the game's own.
    -- Asked the client itself (UiProbe 0.1.2) how its own item button is
    -- built, instead of trusting vanilla's documentation, which was wrong
    -- about this build three times running. Its answer:
    --
    --   normal: Interface/Buttons/UI-Quickslot2  37x37  CENTER/CENTER (0,1)
    --   icon:   37x37  TOPLEFT/TOPLEFT (0,0)
    --   cell:   37x37
    --
    -- So the ring is the SAME size as the cell, not 64 for a 37 cell, and it
    -- sits one pixel HIGH, not one low. Those are the numbers below.
    local ring = sb:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    ring:SetPoint("CENTER", sb, "CENTER", 0, 1)
    ApplyRing(ring)

    local fs = sb:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    fs:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", -3, 3)
    fs:SetJustifyH("RIGHT")

    local star = sb:CreateTexture(nil, "OVERLAY")
    star:SetTexture(1, 0.82, 0, 1)
    star:SetWidth(6)
    star:SetHeight(6)
    star:SetPoint("TOPLEFT", sb, "TOPLEFT", 4, -4)
    star:Hide()

    buttons[i]   = sb
    countFS[i]   = fs
    iconTex[i]   = icon
    bgTex[i]     = ring        -- tinted for quality
    innerTex[i]  = fill
    starTex[i]   = star
    btnIndex[sb] = i
    ApplyCountFont(i)
    return sb
  end

  local b = CreateFrame("Button", name, frame)
  stockSlot[i] = false
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
  AnchorChrome()

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
      if not stockSlot[k] then
        AnchorInset(innerTex[k], buttons[k])
        AnchorInset(iconTex[k], buttons[k])
      end
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
    local icon  = iconTex[i]
    slotBag[i], slotIdx[i] = e.bag, e.slot

    local star = starTex[i]
    if star then
      if e.fav and not e.empty then star:Show() else star:Hide() end
    end

    local stock = stockSlot[i]

    if e.empty then
      if stock then
        -- the ring and the dark bed stay: an empty slot is meant to look
        -- like one, it is only the picture that goes
        if icon then icon:Hide() end
        if bg and bg.SetVertexColor then bg:SetVertexColor(1, 1, 1) end
      else
        b:SetNormalTexture("")
        if inner then inner:Show() end
        if bg then bg:SetTexture(GRID_R, GRID_G, GRID_B, 1) end
      end
      if fs then fs:SetText("") end
      b:SetAlpha(0.9)
    else
      if stock then
        if icon then
          icon:SetTexture(e.texture)
          icon:Show()
        end
      else
        b:SetNormalTexture(e.texture)
        AnchorIcon(b, i)
        if inner then inner:Hide() end
      end

      if fs then
        if e.count > 1 then fs:SetText(e.count) else fs:SetText("") end
      end

      -- Rarity. On our own cell it is the fill behind the picture; on a stock
      -- one there is no room behind anything, so the slot art itself is
      -- tinted - which is how the game's own bags mark quality too.
      local plain = (e.quality and e.quality <= 1)
      if stock then
        if bg and bg.SetVertexColor then
          if plain then
            bg:SetVertexColor(1, 1, 1)
          else
            local r, g, bl = QualityColor(e.quality)
            bg:SetVertexColor(r, g, bl)
          end
        end
      elseif bg then
        -- common and poor quality take the grid colour: otherwise the seam
        -- between two cells is a bright two pixel band and looks thick
        if plain then
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

  -- Upper line of the footer: what the character carries, nothing else.
  moneyText:SetText("|cff9d9d9d" .. L("money") .. "|r")
  DrawMoney(GetMoney and GetMoney() or 0, "")

  -- ItemLens, when installed, knows what a vendor would pay for the contents.
  -- The value takes the right hand corner: putting it next to the money would
  -- run the footer into the hint on a narrow window. Nothing here depends on
  -- ItemLens being present - no addon, no line, no error.
  --
  -- Written with coins, not with the letters g/s/c, and that costs a layout
  -- pass: the client draws no picture inside a line of text (probed), so the
  -- row is measured first and then laid out piece by piece from the left,
  -- ending exactly at the right edge.
  local total, bankTotal, bankStale = nil, nil, false
  local bagValue = PriceApi()
  if AllBagsDB.value and bagValue then
    local t = bagValue()
    if type(t) == "number" then
      total = t
      local bankValue = BankApi()
      if AllBagsDB.bank and bankValue then
        local bt, _, _, fresh = bankValue()
        if type(bt) == "number" then
          bankTotal = bt
          bankStale = not fresh
        end
      end
    end
  end

  -- Lower line: how much room is left, and what the bag is worth. Laid out
  -- left to right from the same margin the money uses, so the two lines read
  -- as a block; the settings button owns the right hand corner and the line
  -- simply stops before it.
  local y = FootY()
  freeText:SetText("|cff9d9d9d" .. L("free") .. "|r " .. free
    .. "|cff808080/" .. slotCount .. "|r")
  freeText:ClearAllPoints()
  freeText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD + 2, y)

  local x = PAD + 2 + TextW(freeText) + 16
  -- On a six column window there is not room for everything, and a line that
  -- runs under the settings button reads as rubbish. Measure first, then drop
  -- the bank, then the value, rather than let them overlap it.
  local room = frame:GetWidth() - PAD - 2
    - ((cfgButton and cfgButton:GetWidth()) or 0) - 10 - x
  if total then
    local w = StripWidth(valStrip, L("value"), total)
    local wb = 0
    if bankTotal then
      wb = StripWidth(bankStrip, L("bank") .. (bankStale and " *" or ""), bankTotal) + 4
    end
    if w + wb > room then wb = 0; bankTotal = nil end
    if w > room then
      StripHide(valStrip)
    else
      x = StripPlace(valStrip, frame, L("value"), total, x, y)
    end
    if bankTotal then
      StripPlace(bankStrip, frame, L("bank") .. (bankStale and " *" or ""),
        bankTotal, x + 4, y)
    else
      StripHide(bankStrip)
    end
  else
    StripHide(valStrip)
    StripHide(bankStrip)
  end
  hintText:SetText("")

  sortButton:SetText(AllBagsDB.sort == "quality" and L("sortQ") or L("sortN"))
  if cfgButton then cfgButton:SetText(L("cfgOpen")) end
end

----------------------------------------------------------------------
-- context menu (right click on the window frame)
----------------------------------------------------------------------

local menu, menuTitle
local menuButtons = {}
local menuExtra = {}    -- i -> second, right hand button on that line
local hoverCount, menuIdle, everHovered = 0, 0, false

local ITEM_H, TITLE_H, MPAD = 18, 18, 14
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

  -- the vault lives in its own file; the entry only appears when that file
  -- is there, so the menu never points at nothing
  if type(AllBagsVault_Toggle) == "function" then
    add({ mark = "none", text = L("mVault"),
          action = function() AllBagsVault_Toggle() end })
  end

  add({ mark = "none", text = L("mCols") .. ":", header = true })
  local i = 1
  while COL_CHOICES[i] do
    local n = COL_CHOICES[i]
    add({ mark = "radio", indent = true, on = (AllBagsDB.cols == n), text = "" .. n, keep = true,
          action = function() AllBagsDB.cols = n; lastCols = -1; dirty = true end })
    i = i + 1
  end

  -- The frame style, the slot style and the border thickness used to have
  -- three sections of their own here. Once the stock look won there was
  -- nothing left to choose between, and the menu was the longer for it.
  -- Both old looks are still reachable: /bags frame and /bags slots.

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

-- The choice used to be written as the characters "(*)" and "( )". It is a
-- real tick box now, and the label has to clear it: the box is 18 wide and
-- starts two pixels in, so the text may not begin before thirty - nine
-- spaces at this size. Every box sits at the same two pixels, indented lines
-- included, so they read as one column down the menu; the indent lives in
-- the text alone.
local MARK_PAD = "          "  -- ten spaces: past an 18 pixel box plus air

local function ItemLabel(item)
  local prefix = ""
  if item.mark == "radio" then
    prefix = MARK_PAD
  elseif item.indent then
    prefix = MARK_PAD
  end
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

  -- The mark is Blizzard's own tick box, not a drawn one: the template was
  -- probed on this client and its tick draws, whereas a texture file that is
  -- not in this build would simply show nothing and never say so. The mouse
  -- is switched off on it, or it would swallow the click meant for the line.
  local m = Templated("CheckButton", "AllBagsMenuMark" .. i, b, TMPL_CHECK)
  if m then
    m:SetWidth(18)
    m:SetHeight(18)
    m:SetPoint("LEFT", b, "LEFT", 1, 0)
    pcall(function() m:EnableMouse(false) end)
    m:Hide()
    b.mark = m
  end
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
  -- Blizzard's carved frame, the same one the bag and the vault wear. Its
  -- edge is 32 pixels thick, so the padding inside grows with it - MPAD is
  -- what keeps the first line off the metal.
  menu:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 32,
    insets   = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  menu:SetBackdropColor(0, 0, 0, 0.9)
  menu:SetBackdropBorderColor(1, 1, 1, 1)
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
    if b.mark then
      if item.mark == "radio" then
        b.mark:ClearAllPoints()
        b.mark:SetPoint("LEFT", b, "LEFT", 2, 0)
        pcall(function() b.mark:SetChecked(item.on and 1 or 0) end)
        b.mark:Show()
      else
        b.mark:Hide()
      end
    end
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

Dialog = function()
  return (AllBagsDB and AllBagsDB.frameStyle or "dialog") == "dialog"
end

StockSlots = function()
  return (AllBagsDB and AllBagsDB.slotStyle or "stock") == "stock"
end

-- The stock dialog edge is 32 pixels of carved metal against our 6 of thin
-- line, so the content has to move inwards with it. PAD, HEADER and FOOTER
-- are what the layout measures from, so the style sets them and everything
-- else follows.
-- The stock buttons in the header are 22 tall against the 17 of the old
-- framed ones, so the grid has to start lower in both styles.
ApplyMetrics = function()
  -- 37 is the size the game's own cells are, and at that size the slot art
  -- and the stack figures sit the way they do in the game's bags. The three
  -- pixels of air keep the beds of two cells from touching.
  if StockSlots() then
    -- The game's own bags step by 44 (37 and 7 of air), which is what leaves
    -- room for the metal of the 64 pixel picture to hang out. Seven read as
    -- too much air between the columns on a ten column window, so the air is
    -- 4 and the metal of two neighbours overlaps a little more - which is
    -- what it does in the game's own bag anyway. /bags gap N retunes it.
    SIZE = 37
    if RING_CROP > 0 then GAP = 3 else GAP = STOCK_GAP end
  else
    SIZE, GAP = 32, 0
  end

  if Dialog() then
    PAD, HEADER, FOOTER = 12, 38, 26
  else
    PAD, HEADER, FOOTER = 4, 30, 22
  end
  -- Two lines under the grid, always: the purse on the upper one, what the
  -- bag holds and what it is worth on the lower. The settings button stands
  -- in the right hand corner across both of them, so the footer also has to
  -- be tall enough for it.
  FOOTER = FOOTER + 18
end

-- Where the footer's own baseline sits: clear of the border, whichever
-- border it is. The money used to be pinned at 6 and vanished under the
-- thick edge.
FootY = function()
  if Dialog() then return 14 end
  return 6
end

-- The pieces around the grid are anchored once, so they have to be put back
-- when the style - and with it the padding - changes.
AnchorChrome = function()
  if not frame then return end
  -- the word "Bags" over a window full of bags said nothing, so it is gone
  -- and the vault button stands where it used to
  if header then header:Hide() end
  if hintText then
    hintText:ClearAllPoints()
    hintText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD - 2, FootY())
  end
  if cfgButton then
    cfgButton:ClearAllPoints()
    cfgButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD - 2, FootY() - 4)
  end
  if sortButton then
    sortButton:ClearAllPoints()
    sortButton:SetPoint("TOP", frame, "TOP", 0, Dialog() and -12 or -5)
  end
  -- the cross is deliberately NOT re-anchored here: it is placed once when it
  -- is built, and moving it on every layout made it twitch
  if vaultButton then
    vaultButton:ClearAllPoints()
    vaultButton:SetPoint("TOPLEFT", frame, "TOPLEFT",
      PAD + 2, Dialog() and -12 or -5)
  end
end

ApplyBorder = function()
  if not frame then return end
  ApplyMetrics()

  if Dialog() then
    -- Probed on this client: the stock dialog BORDER draws, the stock dialog
    -- BACKGROUND comes out transparent whatever the tiling. So the carved
    -- frame is Blizzard's and the fill stays ours.
    frame:SetBackdrop({
      bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 16, edgeSize = 32,
      insets   = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)
    frame:SetBackdropBorderColor(1, 1, 1, 1)
    AnchorChrome()
    return
  end

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
  AnchorChrome()
end

-- Other characters. The button sits by the title, not by the close cross: a
-- header button in that corner is one miss away from closing the window,
-- which is why the old settings button had to go. It appears only when
-- AllBagsVault.lua is loaded, so it never points at nothing - and it cannot
-- be built inside BuildFrame, which runs before that file is loaded.
local function AddVaultButton()
  if vaultButton or not frame then return end
  if type(AllBagsVault_Toggle) ~= "function" then return end

  -- An icon here came out invisible: this client has no such file, and a
  -- missing texture draws nothing at all rather than complaining. A word on
  -- a stock button always renders, so that is what the button is.
  local vb = Templated("Button", "AllBagsVaultOpen", frame, TMPL_BTN)
  if vb then
    vb:SetWidth(56)
    vb:SetHeight(22)
  else
    vb = CreateFrame("Button", "AllBagsVaultOpen", frame)
    vb:SetWidth(44)
    vb:SetHeight(17)
    vb:SetFont("Fonts\\FRIZQT__.TTF", 11)
    vb:SetTextColor(1, 0.82, 0)
    vb:SetBackdrop({
      bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tileSize = 16, edgeSize = 10,
      insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    vb:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    vb:SetBackdropBorderColor(0.45, 0.45, 0.45, 0.9)
    vb:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
  end
  vaultButton = vb
  vb:SetText(L("mAlts"))
  -- The left hand corner, where the word "Bags" used to be: a header button
  -- by the close cross is one miss away from shutting the window, and the
  -- title itself said nothing a window full of bags did not already say.
  vb:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 2, -6)
  vb:SetScript("OnClick", function() AllBagsVault_Toggle() end)
  vb:SetScript("OnEnter", function()
    if not GameTooltip then return end
    GameTooltip:SetOwner(this or vb, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:AddLine(L("mVault"), 1, 0.82, 0)
    GameTooltip:AddLine("/bags vault", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  vb:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  if AnchorChrome then AnchorChrome() end
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

  local function Foot(size)
    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if not fs:GetFont() or fs:GetFont() == "" then
      fs:SetFont("Fonts\\FRIZQT__.TTF", size, "")
    end
    fs:SetJustifyH("LEFT")
    return fs
  end

  moneyText = Foot(12)
  moneyText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD + 2, 6)

  -- three coins out of one atlas: gold, silver, copper
  coin = {}
  local k = 1
  while k <= 3 do
    local ic = frame:CreateTexture(nil, "OVERLAY")
    ic:SetWidth(COIN)
    ic:SetHeight(COIN)
    ic:SetTexture(MONEY_ATLAS)
    ic:SetTexCoord((k - 1) * 0.25, k * 0.25, 0, 1)
    ic:Hide()
    coin[k] = { icon = ic, num = Foot(12) }
    coin[k].num:Hide()
    k = k + 1
  end

  freeText = Foot(12)

  -- the value line gets coins of its own, on its own row
  valStrip  = NewStrip(frame, 11)
  bankStrip = NewStrip(frame, 11)

  -- Blizzard's own cross where it exists, and the hand-drawn letter where it
  -- does not. The stock one brings its own art and its own size.
  closeButton = Templated("Button", "AllBagsClose", frame, TMPL_CLOSE)
  if closeButton then
    closeButton.allbagsStock = true
  else
    closeButton = CreateFrame("Button", "AllBagsClose", frame)
    closeButton:SetWidth(18)
    closeButton:SetHeight(18)
    closeButton:SetFont("Fonts\\FRIZQT__.TTF", 14)
    closeButton:SetText("X")
    closeButton:SetTextColor(1, 0.35, 0.35)
    closeButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
  end
  -- The stock cross is a 32 pixel button whose art is NOT centred in it: on
  -- the screen the cross itself sits about six pixels above the button's
  -- middle, so pinned at -3 it rode visibly higher than the header buttons
  -- next to it (measured off a screenshot: cross centre 425, button text
  -- centre 433). Six pixels down puts them on one line.
  if closeButton.allbagsStock then
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -9)
  else
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
  end
  closeButton:SetScript("OnClick", function() frame:Hide() end)


  -- A settings button used to sit here between the sort switch and the close
  -- cross. It crowded a header that is only 300 wide: settings live on the
  -- sort line of the right click menu instead.

  -- A caption on a bare button has nothing to write into, which is why two
  -- of these came out blank once. On a templated button the FontString is
  -- part of the template, and it draws - probed on this client.
  sortButton = Templated("Button", "AllBagsSort", frame, TMPL_BTN)
  if sortButton then
    sortButton:SetWidth(150)
    sortButton:SetHeight(22)
  else
    sortButton = CreateFrame("Button", "AllBagsSort", frame)
    sortButton:SetWidth(150)
    sortButton:SetHeight(17)
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
  end
  -- Centred, not pinned to the right: the close cross owns that corner and
  -- the switch pressed against it looked like part of the cross.
  sortButton:SetPoint("TOP", frame, "TOP", 0, -6)

  -- Settings, in the right hand corner of the footer. It used to live only in
  -- the right click menu, which is fine once you know the menu is there.
  cfgButton = Templated("Button", "AllBagsConfigOpen", frame, TMPL_BTN)
  if cfgButton then
    cfgButton:SetWidth(92)
    cfgButton:SetHeight(22)
  else
    cfgButton = CreateFrame("Button", "AllBagsConfigOpen", frame)
    cfgButton:SetWidth(80)
    cfgButton:SetHeight(18)
    cfgButton:SetFont("Fonts\\FRIZQT__.TTF", 11)
    cfgButton:SetTextColor(1, 0.82, 0)
    cfgButton:SetBackdrop({
      bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tileSize = 16, edgeSize = 10,
      insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    cfgButton:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    cfgButton:SetBackdropBorderColor(0.45, 0.45, 0.45, 0.9)
    cfgButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
  end
  cfgButton:SetText(L("cfgOpen"))
  cfgButton:SetScript("OnClick", function() ShowConfig() end)

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
local cfgSlider = {}       -- field -> Blizzard slider, when the template took
local cfgSetting = false   -- guard: writing a value back must not re-apply it
local cfgFS   = {}         -- name -> caption that has to follow the language
local cfgBox               -- the "split by bag" checkbox
local cfgSortBox           -- sorting on or off, the same switch as the header
local CfgRefresh

-- Both side windows remember where they were left, the same way the main one
-- does: absolute left and bottom, because StartMoving re-anchors the frame and
-- a saved anchor pair could put it somewhere else on the next login.
-- The stock button art is drawn for something at least twenty pixels tall;
-- a 16 pixel one comes out squashed, so the little arrows and boxes keep the
-- thin frame and only the real buttons get the template.
local function CfgButton(parent, w, h, text)
  local b = nil
  if h >= 20 then b = Templated("Button", nil, parent, TMPL_BTN) end
  if b then
    b:SetWidth(w)
    b:SetHeight(h)
    b:SetText(text)
    return b
  end

  b = CreateFrame("Button", nil, parent)
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

-- The cross that closes a window: Blizzard's own where it exists, our small
-- framed letter where it does not.
local function CfgClose(parent)
  local c = Templated("Button", nil, parent, TMPL_CLOSE)
  if c then
    c.allbagsStock = true
    return c
  end
  return CfgButton(parent, 18, 18, "X")
end

-- A tick box. Blizzard's own where it exists: it brings the tick, the
-- highlight and the pressed state, and it answers SetChecked instead of
-- having a letter written into it.
local function CfgCheck(parent)
  local c = Templated("CheckButton", nil, parent, TMPL_CHECK)
  if c then
    c:SetWidth(22)
    c:SetHeight(22)
    c.allbagsStock = true
    return c
  end
  return CfgButton(parent, 16, 16, "")
end

-- One way to tick a box whichever kind it turned out to be.
local function SetTick(box, on, bright)
  if not box then return end
  if box.allbagsStock then
    pcall(function() box:SetChecked(on and 1 or 0) end)
    return
  end
  box:SetText(on and "x" or "")
  if box.SetBackdropBorderColor then
    if bright then
      box:SetBackdropBorderColor(1, 0.82, 0, 1)
    else
      box:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.9)
    end
  end
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

-- A caption that belongs to a tick box. Anchored to the box itself, not to
-- the window, so the two are on one line whatever height the box turns out
-- to be - the stock box is 22 tall, our fallback 16, and pinning both to the
-- window by hand is what left them sitting at different heights. The gap is
-- eight: the stock art has its own frame around the tick, and text pressed
-- against it read as if it were inside the box.
local function CfgBoxLabel(box, w, size, r, g, b)
  local fs = cfg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetFont("Fonts\\FRIZQT__.TTF", size, "")
  fs:SetTextColor(r, g, b)
  fs:SetWidth(w)
  fs:SetHeight(size + 4)
  fs:SetJustifyH("LEFT")
  fs:SetJustifyV("MIDDLE")
  fs:SetPoint("LEFT", box, "RIGHT", 8, 0)
  return fs
end

-- Moves one criterion up or down the list.-- Moves one criterion up or down the list. The order is what the comparison
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
-- the carved frame eats twelve pixels of its own, so the columns start
-- further in than they did behind the thin tooltip border
local CFG_LEFT, CFG_RIGHT = 18, 18

-- A number the player drags instead of clicking up one at a time. The
-- template is Blizzard's own and it draws on this client (probed with
-- UiProbe): it brings the groove, the knob and three labels of its own,
-- named $parentText, $parentLow and $parentHigh. The middle one is blanked
-- because the value keeps its own column on the right, where it always was.
local function CfgStepper(y, key, field, lo, hi, step)
  cfgFS[field] = CfgText(cfg, CFG_LEFT, y, CFG_W - CFG_LEFT - 190, 11, 0.82, 0.82, 0.82)
  cfgNum[field] = CfgText(cfg, CFG_W - CFG_RIGHT - 30, y, 30, 12, 1, 0.82, 0, "RIGHT")

  -- csize is not a free number: it steps between the font objects the client
  -- actually has, so whatever the widget says is snapped to the nearest one
  local function Apply(v)
    if field == "csize" then
      local best, bestd, k = nil, nil, 1
      while COUNT_FONTS[k] do
        local d = COUNT_FONTS[k].n - v
        if d < 0 then d = -d end
        if not bestd or d < bestd then best, bestd = COUNT_FONTS[k].n, d end
        k = k + 1
      end
      v = best or v
    else
      if v < lo then v = lo elseif v > hi then v = hi end
    end
    if AllBagsDB[field] == v then return end
    AllBagsDB[field] = v
    lastCols = -1
    dirty = true
    Refresh()
    CfgRefresh()
  end

  local name = "AllBagsCfgSlider" .. field
  local sl = Templated("Slider", name, cfg, TMPL_SLIDER)
  if sl then
    sl:SetWidth(120)
    sl:SetHeight(16)
    sl:SetPoint("TOPLEFT", cfg, "TOPLEFT", CFG_W - CFG_RIGHT - 158, y - 4)
    pcall(function() sl:SetOrientation("HORIZONTAL") end)
    sl:SetMinMaxValues(lo, hi)
    sl:SetValueStep(step)
    sl:SetValue(AllBagsDB[field] or lo)
    local t = getglobal(name .. "Text");  if t then t:SetText("") end
    local l = getglobal(name .. "Low");   if l then l:SetText(lo) end
    local h = getglobal(name .. "High");  if h then h:SetText(hi) end
    -- CfgRefresh writes the value back into the slider, and that fires this
    -- again: without the guard the two call each other until the stack ends
    sl:SetScript("OnValueChanged", function()
      if cfgSetting then return end
      local self = this or sl
      Apply(math.floor(self:GetValue() + 0.5))
    end)
    cfgSlider[field] = sl
  else
    -- no template on this client after all: the old pair of buttons
    local minus = CfgButton(cfg, 18, 18, "-")
    minus:SetPoint("TOPLEFT", cfg, "TOPLEFT", CFG_W - 90, y - 1)
    local plus = CfgButton(cfg, 18, 18, "+")
    plus:SetPoint("TOPLEFT", cfg, "TOPLEFT", CFG_W - 32 - CFG_RIGHT + 10, y - 1)
    minus:SetScript("OnClick", function()
      Apply((AllBagsDB[field] or lo) - step)
    end)
    plus:SetScript("OnClick", function()
      Apply((AllBagsDB[field] or lo) + step)
    end)
  end

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
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 32,
    insets   = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  cfg:SetBackdropColor(0, 0, 0, 0.9)
  cfg:SetBackdropBorderColor(1, 1, 1, 1)
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

  cfgFS.title = CfgText(cfg, CFG_LEFT, -16, CFG_W - CFG_LEFT * 2 - 20, 13, 1, 0.82, 0)
  cfgFS.hint  = CfgText(cfg, CFG_LEFT, -34, CFG_W - CFG_LEFT * 2, 10, 0.55, 0.55, 0.55)
  cfgSortBox = CfgCheck(cfg)
  cfgSortBox:SetPoint("TOPLEFT", cfg, "TOPLEFT", CFG_LEFT, -53)
  cfgSortBox:SetScript("OnClick", function()
    AllBagsDB.sort = (AllBagsDB.sort == "quality") and "bag" or "quality"
    dirty = true
    CfgRefresh()
    Refresh()
  end)
  cfgFS.sort = CfgBoxLabel(cfgSortBox, CFG_W - CFG_LEFT * 2 - 34, 11, 0.75, 0.75, 0.75)

  local close = CfgClose(cfg)
  -- the stock cross draws about six pixels above its own middle, so it is
  -- pinned lower than the corner suggests
  close:SetPoint("TOPRIGHT", cfg, "TOPRIGHT", -4, -10)
  close:SetTextColor(1, 0.35, 0.35)
  close:SetScript("OnClick", function() cfg:Hide() end)

  local y = -74
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

    row.box = CfgCheck(cfg)
    row.box:SetPoint("TOPLEFT", cfg, "TOPLEFT", CFG_LEFT + 42, y)
    row.box:SetScript("OnClick", function()
      local e = AllBagsDB.order and AllBagsDB.order[n]
      if not e then return end
      e.on = not e.on
      dirty = true
      CfgRefresh()
    end)

    row.label = CfgBoxLabel(row.box, CFG_W - CFG_LEFT - 90, 12, 1, 1, 1)
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
  y = y - 26

  cfgBox = CfgCheck(cfg)
  cfgBox:SetPoint("TOPLEFT", cfg, "TOPLEFT", CFG_LEFT, y)
  cfgBox:SetScript("OnClick", function()
    AllBagsDB.groups = not AllBagsDB.groups
    dirty = true
    CfgRefresh()
    Refresh()
  end)
  cfgFS.group = CfgBoxLabel(cfgBox, CFG_W - CFG_LEFT - 48, 11, 0.85, 0.85, 0.85)
  y = y - 34

  local done = CfgButton(cfg, 90, 22, "")
  done:SetPoint("TOP", cfg, "TOP", 0, y + 4)
  done:SetScript("OnClick", function() cfg:Hide() end)
  cfg.done = done

  cfg:SetHeight(-y + 34)
end

CfgRefresh = function()
  if not cfg then return end
  cfgFS.title:SetText(L("cfgTitle"))
  cfgFS.hint:SetText(L("cfgHint"))
  cfgFS.sort:SetText(L("cfgSort") .. ":")

  local sorting = (AllBagsDB.sort == "quality")
  SetTick(cfgSortBox, sorting, sorting)
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
      SetTick(row.box, e.on, e.on)
      if e.on then
        row.label:SetTextColor(1, 1, 1)
      else
        row.label:SetTextColor(0.45, 0.45, 0.45)
      end
      if i == 1 then row.up:Disable() else row.up:Enable() end
      if ord[i + 1] then row.down:Enable() else row.down:Disable() end
    else
      row.label:SetText("")
      SetTick(row.box, false, false)
    end
    i = i + 1
  end

  SetTick(cfgBox, AllBagsDB.groups, AllBagsDB.groups)

  local f = 1
  local fields = { "csize", "cols" }
  while fields[f] do
    local k = fields[f]
    if cfgFS[k] then cfgFS[k]:SetText(L(cfgFS[k].key)) end
    if cfgNum[k] then cfgNum[k]:SetText("" .. (AllBagsDB[k] or 0)) end
    if cfgSlider[k] then
      cfgSetting = true
      pcall(function() cfgSlider[k]:SetValue(AllBagsDB[k] or 0) end)
      cfgSetting = false
    end
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
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 32,
    insets   = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  tw:SetBackdropColor(0, 0, 0, 0.9)
  tw:SetBackdropBorderColor(1, 1, 1, 1)
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

  twFS.title = CfgText(tw, CFG_LEFT, -16, CFG_W - CFG_LEFT * 2 - 20, 13, 1, 0.82, 0)
  twFS.hint  = CfgText(tw, CFG_LEFT, -34, CFG_W - CFG_LEFT * 2, 10, 0.55, 0.55, 0.55)

  local close = CfgClose(tw)
  close:SetPoint("TOPRIGHT", tw, "TOPRIGHT", -4, -10)
  close:SetTextColor(1, 0.35, 0.35)
  close:SetScript("OnClick", function() tw:Hide() end)

  local y = -56
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

  local done = CfgButton(tw, 90, 22, "")
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
  local bottom = -56 - shown * 20 - 10
  tw.done:ClearAllPoints()
  tw.done:SetPoint("TOP", tw, "TOP", 0, bottom)
  tw:SetHeight(-bottom + 36)
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

  elseif msg == "frame" then
    AllBagsDB.frameStyle = (AllBagsDB.frameStyle == "dialog") and "tooltip" or "dialog"
    ApplyBorder()
    lastCols = -1
    dirty = true
    Print(L("cfgFrame") .. ": " ..
      (AllBagsDB.frameStyle == "dialog" and L("frDialog") or L("frTip")))

  elseif msg == "slots" then
    AllBagsDB.slotStyle = StockSlots() and "plain" or "stock"
    Print(L("cfgSlot") .. ": " ..
      (StockSlots() and L("slStock") or L("slPlain")) .. " — /reload")

  elseif msg == "hover" then
    Print("hover: " .. (lastHover == "" and "-" or lastHover))
    local b = hoverIndex and buttons[hoverIndex]
    if b then
      Print("cell: stock=" .. tostring(stockSlot[hoverIndex] and true or false)
        .. ", name=" .. tostring(b.GetName and b:GetName()))
    end
    if GameTooltip then
      local own = GameTooltip.GetOwner and GameTooltip:GetOwner()
      Print("tooltip: shown=" .. tostring(GameTooltip:IsShown())
        .. ", owner=" .. tostring(own and own.GetName and own:GetName()))
    end

  elseif msg == "config" or msg == "cfg" or msg == "options" then
    ShowConfig()

  elseif msg == "types" then
    ShowTypes()

  elseif msg == "vault" or msg == "vault probe" or msg == "chars" then
    if type(AllBagsVault_Toggle) ~= "function" then
      Print("AllBagsVault.lua не загружен")
    elseif msg == "vault probe" then
      AllBagsVault_Probe()
    else
      AllBagsVault_Toggle()
    end

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

  -- Hidden: the two windows, side by side in numbers. The bag cells and the
  -- vault cells are built from the same recipe, yet on screen the vault ones
  -- came out with black around the picture - so instead of squinting at a
  -- screenshot again, ask both windows what their pieces actually are.
  -- Note: no select() and no GetRegions() here. This client is Lua 5.0 era
  -- (select does not exist) and GetNumRegions already lied once, answering 0
  -- for a window full of art. Each window reports the pieces it holds itself.
  elseif msg == "cmp" then
    local function Part(label, t)
      if not t then Print("  " .. label .. ": " .. L("no")); return end
      local file, w, h, pt, x, y = nil, 0, 0, nil, nil, nil
      pcall(function() file = t.GetTexture and t:GetTexture() end)
      pcall(function() w, h = t:GetWidth(), t:GetHeight() end)
      pcall(function() pt, _, _, x, y = t:GetPoint(1) end)
      Print("  " .. label .. ": " .. tostring(file) .. " " .. tostring(w) .. "x"
        .. tostring(h) .. " " .. tostring(pt) .. " (" .. tostring(x) .. ","
        .. tostring(y) .. ")" .. (t:IsShown() and "" or " |cff808080hidden|r"))
    end

    local b = buttons[1]
    Print("|cffffd700bag cell|r: " .. (b and (b:GetWidth() .. "x" .. b:GetHeight()) or L("no"))
      .. ", " .. L("cfgCols") .. " " .. AllBagsDB.cols)
    Part("bed", innerTex[1])
    Part("icon", iconTex[1])
    Part("ring", bgTex[1])

    if type(AllBagsVault_CellInfo) == "function" then
      AllBagsVault_CellInfo()
    else
      Print("|cffffd700vault cell|r: " .. L("no"))
    end

  -- Hidden: the air between stock cells, live.
  elseif string.sub(msg, 1, 3) == "gap" then
    local _, _, raw = string.find(msg, "^gap%s+(%d+)$")
    local n = tonumber(raw)
    if n and n >= 0 and n <= 12 then
      STOCK_GAP = n
      ApplyMetrics()
      lastCols = -1
      dirty = true
      Refresh()
      Print("gap: " .. GAP .. ", " .. L("cfgCols") .. " " .. AllBagsDB.cols)
    else
      Print("gap: 0 .. 12, /bags gap 4")
    end

  -- Hidden: try the measured patches of hide under the empty cells, live.
  -- /bags bed 0 goes back to the flat brown.
  elseif string.sub(msg, 1, 3) == "bed" then
    local _, _, raw, sh = string.find(msg, "^bed%s+(%d+)%s*([%d%.]*)$")
    local n = tonumber(raw)
    if n and n >= 0 and n <= 6 then
      bedSpot = n
      bedShade = tonumber(sh) or 1
      if bedShade < 0.3 then bedShade = 0.3 end
      if bedShade > 2 then bedShade = 2 end
      local i = 1
      while buttons[i] do
        if stockSlot[i] then ApplyBed(innerTex[i]) end
        i = i + 1
      end
      if n == 0 then
        Print("bed: " .. L("bedFlat"))
      else
        Print("bed: " .. n .. ", shade " .. bedShade)
      end
    else
      Print("bed: 0 .. 6 [+ 0.3 .. 2], /bags bed 3 0.9")
    end

  -- Hidden: retune the slot ring crop live, without a reload. Kept because
  -- only a human eye can tell whether a texture landed where it should.
  elseif string.sub(msg, 1, 4) == "crop" then
    local _, _, raw = string.find(msg, "^crop%s+([%d%.]+)$")
    local n = tonumber(raw)
    if n and n >= 0 and n < 0.5 then
      RING_CROP = n
      ApplyMetrics()
      local i = 1
      while buttons[i] do
        if stockSlot[i] then ApplyRing(bgTex[i]) end
        i = i + 1
      end
      lastCols = -1
      dirty = true
      Refresh()
      Print("crop: " .. n .. ", size " .. SIZE .. ", gap " .. GAP)
    else
      Print("crop: 0 .. 0.49, /bags crop 0.22")
    end

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
    AddVaultButton()
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
