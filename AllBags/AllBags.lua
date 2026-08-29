--[[--------------------------------------------------------------------
  AllBags 1.0.2
  All bags (0-4) in one window. Client 1.12.1 / Lua 5.1 (Emberveil).

  The sort is VIRTUAL: nothing moves inside the bags, only the display order
  in the grid changes. Moving items for real would take dozens of consecutive
  PickupContainerItem calls and falls apart on any network hiccup.
----------------------------------------------------------------------]]

local ADDON   = "AllBags"
local VERSION = "1.0.2"

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
}

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
    help     = "команды: /bags [menu | sort | cols N | border N | value | lang ru/en/auto | on | off | reset]",
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
    help     = "commands: /bags [menu | sort | cols N | border N | value | lang ru/en/auto | on | off | reset]",
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

local frame, header, hintText, moneyText, sortButton, closeButton, offButton
local buttons = {}      -- i -> Button
local hoverIndex = nil  -- cell the cursor is over, for the public helpers below
local countFS  = {}     -- i -> stack count FontString
local bgTex    = {}     -- i -> fill acting as the border (quality colour)
local iconTex  = {}     -- i -> item icon
local innerTex = {}     -- i -> dark centre of an empty cell
local slotBag  = {}     -- i -> bag id
local slotIdx  = {}     -- i -> slot inside that bag
local btnIndex = {}     -- Button -> i
local slotList = {}
local slotCount = 0
local dirty, timer = true, 0
local lastCount, lastCols, lastLine = -1, -1, -1
local ApplyPosition, SavePosition   -- forward declaration for the menu
local SetEnabled                    -- turns the bag hooks on and off
local ApplyBorder                   -- window border thickness

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

        slot = slot + 1
      end
    end
    bag = bag + 1
  end

  return free, slotCount
end

-- by quality (descending), then by name; empty slots go last
local function CompareQuality(a, b)
  if a.empty ~= b.empty then return b.empty end
  if a.empty then
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
  end
  if a.quality ~= b.quality then return a.quality > b.quality end
  if a.name ~= b.name then return a.name < b.name end
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
    while j >= 1 and CompareQuality(v, slotList[j]) do
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

  if IsShiftKeyDown and IsShiftKeyDown() then
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

  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  if not fs:GetFont() or fs:GetFont() == "" then
    fs:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
  end
  fs:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
  fs:SetJustifyH("RIGHT")

  buttons[i]  = b
  countFS[i]  = fs
  bgTex[i]    = bg
  innerTex[i] = inner
  iconTex[i]  = ic
  btnIndex[b] = i
  return b
end

----------------------------------------------------------------------
-- layout and refresh
----------------------------------------------------------------------

local function Layout()
  local cols = AllBagsDB.cols
  local rows = math.floor((slotCount + cols - 1) / cols)
  if rows < 1 then rows = 1 end

  local width  = PAD * 2 + cols * SIZE + (cols - 1) * GAP
  if width < MIN_WIDTH then width = MIN_WIDTH end   -- or the header will not fit
  local gridW  = cols * SIZE + (cols - 1) * GAP
  local gridH  = rows * SIZE + (rows - 1) * GAP
  local gridX  = math.floor((width - gridW) / 2)
  local height = HEADER + gridH + 6 + FOOTER

  frame:SetWidth(width)
  frame:SetHeight(height)

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

  local j = slotCount + 1
  while buttons[j] do
    buttons[j]:Hide()
    slotBag[j], slotIdx[j] = nil, nil
    j = j + 1
  end
end

local function Refresh()
  if not frame or not frame:IsShown() then return end

  local free = CollectSlots()
  SortSlots()

  if slotCount ~= lastCount or AllBagsDB.cols ~= lastCols then
    lastCount, lastCols = slotCount, AllBagsDB.cols
    Layout()
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
      if type(unknown) == "number" and unknown > 0 then
        shown = shown .. " |cff808080+" .. unknown .. "?|r"
      end

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
  add({ mark = "radio", indent = true, on = (AllBagsDB.sort == "quality"), text = L("mByQ"), keep = true,
        action = function() AllBagsDB.sort = "quality"; dirty = true end })
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
  menu:Hide()

  menuTitle = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  if not menuTitle:GetFont() or menuTitle:GetFont() == "" then
    menuTitle:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
  end
  menuTitle:SetJustifyH("LEFT")

  menu:SetScript("OnUpdate", function(self, elapsed)
    local e = elapsed or arg1 or 0
    if hoverCount > 0 then
      menuIdle = 0
    else
      menuIdle = menuIdle + e
      local limit = 4
      if everHovered then limit = 1.5 end
      if menuIdle > limit then HideMenu() end
    end
  end)
end

ShowMenu = function()
  BuildMenu()

  local items, n = MenuItems()
  menuTitle:SetText(ADDON .. "  |cff808080v" .. VERSION .. "|r")

  local width = menuTitle:GetStringWidth()
  local i = 1
  while i <= n do
    local b = GetMenuButton(i)
    b:SetText(ItemLabel(items[i]))
    if items[i].header then b:SetTextColor(1, 0.82, 0) else b:SetTextColor(1, 1, 1) end
    local w = b:GetTextWidth()
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
    b:SetWidth(width - MPAD * 2)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", menu, "TOPLEFT", MPAD, y)
    b:SetScript("OnClick", function()
      if item.header then return end
      item.action()
      if item.keep then ShowMenu() else HideMenu() end
    end)
    b:Show()
    y = y - ITEM_H
    i = i + 1
  end

  local j = n + 1
  while menuButtons[j] do menuButtons[j]:Hide(); j = j + 1 end

  menu:SetWidth(width)
  menu:SetHeight(MPAD * 2 + TITLE_H + n * ITEM_H)

  if not menu:IsShown() then
    local cx, cy
    if GetCursorPosition then cx, cy = GetCursorPosition() end
    menu:ClearAllPoints()
    if cx and cy then
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

  sortButton = CreateFrame("Button", "AllBagsSort", frame)
  sortButton:SetWidth(150)
  sortButton:SetHeight(17)
  sortButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -72, -6)
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

  offButton = CreateFrame("Button", "AllBagsOff", frame)
  offButton:SetWidth(44)
  offButton:SetHeight(17)
  offButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -25, -6)
  offButton:SetFont("Fonts\\FRIZQT__.TTF", 11)
  offButton:SetTextColor(1, 0.6, 0.6)
  offButton:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tileSize = 16, edgeSize = 10,
    insets   = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  offButton:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
  offButton:SetBackdropBorderColor(0.5, 0.35, 0.35, 0.9)
  offButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
  offButton:SetScript("OnClick", function() SetEnabled(false) end)

  sortButton:SetScript("OnClick", function()
    AllBagsDB.sort = (AllBagsDB.sort == "quality") and "bag" or "quality"
    dirty = true
    Refresh()
  end)

  frame:SetScript("OnShow", function()
    ApplyPosition()
    header:SetText(L("title"))
    hintText:SetText(L("hint"))
    offButton:SetText(L("btnOff"))
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
end

local function OnEvent(self, ev)
  ev = ev or event
  if ev == "VARIABLES_LOADED" or ev == "PLAYER_LOGIN" then
    InitDB()
    ApplyBorder()
    ApplyPosition()
    HookBagFunctions()
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
