-- SlotItemLevel.lua
local ADDON = ...
local f = CreateFrame("Frame")

------------------------------------------------------------
-- Config
------------------------------------------------------------
local FONT_PATH  = "Fonts\\FRIZQT__.TTF"
local FONT_SIZE  = 14
local FONT_FLAGS = "OUTLINE"

local OFFSET_X = 6
local OFFSET_Y = -1

local RIGHT_MARGIN = 2

------------------------------------------------------------
-- Debug
------------------------------------------------------------
local DEBUG = false
local function dprint(fmt, ...)
  if not DEBUG then return end
  local msg = (select("#", ...) > 0) and string.format(fmt, ...) or tostring(fmt)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99SlotItemLevel|r " .. msg)
end

------------------------------------------------------------
-- Slots to display
------------------------------------------------------------
local WANTED = {
  [INVSLOT_HEAD] = true,
  [INVSLOT_NECK] = true,
  [INVSLOT_SHOULDER] = true,
  [INVSLOT_BACK] = true,
  [INVSLOT_CHEST] = true,
  [INVSLOT_WRIST] = true,
  [INVSLOT_HAND] = true,
  [INVSLOT_WAIST] = true,
  [INVSLOT_LEGS] = true,
  [INVSLOT_FEET] = true,
  [INVSLOT_FINGER1] = true,
  [INVSLOT_FINGER2] = true,
  [INVSLOT_TRINKET1] = true,
  [INVSLOT_TRINKET2] = true,
  [INVSLOT_MAINHAND] = true,
  [INVSLOT_OFFHAND] = true,
}

------------------------------------------------------------
-- State per context
------------------------------------------------------------
local CTX = {
  player = { unit = "player", slotButtons = {}, slotLabels = {} },
  inspect = { unit = nil, slotButtons = {}, slotLabels = {} },
}

local hookedCharacter = false
local hookedInspect = false

------------------------------------------------------------
-- Reliable displayed item level (tooltip truth)
------------------------------------------------------------
local function GetDisplayedItemLevel(itemLink)
  if not itemLink then return nil end

  if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
    local tip = C_TooltipInfo.GetHyperlink(itemLink)
    if tip and tip.lines then
      for _, line in ipairs(tip.lines) do
        local t = line.leftText
        if t then
          local ilvl = t:match("(%d+)")
          if ilvl and t:lower():find("item level", 1, true) then
            return tonumber(ilvl)
          end
        end
      end
    end
  end

  if C_Item and C_Item.GetDetailedItemLevelInfo then
    return C_Item.GetDetailedItemLevelInfo(itemLink)
  end

  return nil
end

------------------------------------------------------------
-- Frame lookup
------------------------------------------------------------
local function GetItemsParent(context)
  if context == "player" then
    if PaperDollItemsFrame then return PaperDollItemsFrame end
    if CharacterFrame and CharacterFrame.PaperDollItemsFrame then
      return CharacterFrame.PaperDollItemsFrame
    end
    if PaperDollFrame and PaperDollFrame.ItemSlotsFrame then
      return PaperDollFrame.ItemSlotsFrame
    end
  elseif context == "inspect" then
    -- These names can vary slightly, so we try multiple.
    if InspectPaperDollItemsFrame then return InspectPaperDollItemsFrame end
    if InspectFrame and InspectFrame.PaperDollItemsFrame then
      return InspectFrame.PaperDollItemsFrame
    end
    if InspectPaperDollFrame and InspectPaperDollFrame.ItemSlotsFrame then
      return InspectPaperDollFrame.ItemSlotsFrame
    end
  end
end

local function GetUnitForContext(context)
  if context == "player" then return "player" end

  -- Inspect context
  if InspectFrame and InspectFrame.unit then
    return InspectFrame.unit
  end
  -- Fallback: inspect traditionally targets the current target
  return "target"
end

------------------------------------------------------------
-- Coloring
------------------------------------------------------------
local function ColorizeIlvlForUnit(unit, slotId, ilvl)
  local quality = GetInventoryItemQuality(unit, slotId)
  if quality then
    local r, g, b = C_Item.GetItemQualityColor(quality)
    return string.format("|cff%02x%02x%02x%d|r", r * 255, g * 255, b * 255, ilvl)
  end
  return tostring(ilvl)
end

------------------------------------------------------------
-- Fonts + positioning
------------------------------------------------------------
local function ApplyFontSafe(fs)
  local ok = pcall(function()
    fs:SetFont(FONT_PATH, FONT_SIZE, FONT_FLAGS)
  end)
  if not ok then
    local font, _, flags = GameFontNormal:GetFont()
    fs:SetFont(font, FONT_SIZE, flags or "")
  end
end

local function IsButtonOnLeftSide(context, btn)
  if not btn then return true end
  local ref = GetItemsParent(context) or (btn.GetParent and btn:GetParent()) or CharacterFrame
  if not ref then return true end

  local bx = btn:GetCenter()
  local rx = ref:GetCenter()
  if not bx or not rx then return true end

  return bx < rx
end

local function PositionLabel(context, fs, btn, slotId)
  fs:ClearAllPoints()

  -- Weapon slots: flare outward
  if slotId == INVSLOT_MAINHAND then
    fs:SetPoint("RIGHT", btn, "LEFT", -OFFSET_X, OFFSET_Y)
    fs:SetJustifyH("RIGHT")
    return
  elseif slotId == INVSLOT_OFFHAND then
    fs:SetPoint("LEFT", btn, "RIGHT", 3, OFFSET_Y)
    fs:SetJustifyH("LEFT")
    return
  end

  if IsButtonOnLeftSide(context, btn) then
    fs:SetPoint("LEFT", btn, "RIGHT", OFFSET_X, OFFSET_Y)
    fs:SetJustifyH("LEFT")
  else
    fs:SetPoint("RIGHT", btn, "LEFT", -(OFFSET_X + RIGHT_MARGIN), OFFSET_Y)
    fs:SetJustifyH("RIGHT")
  end
end

local function EnsureLabel(context, btn, slotId)
  local labels = CTX[context].slotLabels
  if labels[btn] then return labels[btn] end

  local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  ApplyFontSafe(fs)
  PositionLabel(context, fs, btn, slotId)
  fs:SetText("")

  labels[btn] = fs
  return fs
end

local function RepositionAllLabels(context)
  local buttons = CTX[context].slotButtons
  local labels = CTX[context].slotLabels
  for slotId, btn in pairs(buttons) do
    local fs = labels[btn]
    if fs then
      ApplyFontSafe(fs)
      PositionLabel(context, fs, btn, slotId)
    else
      EnsureLabel(context, btn, slotId)
    end
  end
end

local function SetSlotText(context, slotId, text)
  local btn = CTX[context].slotButtons[slotId]
  if not btn then return end
  EnsureLabel(context, btn, slotId):SetText(text or "")
end

------------------------------------------------------------
-- Update logic
------------------------------------------------------------
local function UpdateSlot(context, slotId)
  local btn = CTX[context].slotButtons[slotId]
  if not btn then return end

  local unit = GetUnitForContext(context)
  local link = GetInventoryItemLink(unit, slotId)
  if not link then
    SetSlotText(context, slotId, "")
    return
  end

  local ilvl = GetDisplayedItemLevel(link)
  if ilvl then
    SetSlotText(context, slotId, ColorizeIlvlForUnit(unit, slotId, ilvl))
    return
  end

  local item = Item:CreateFromItemLink(link)
  item:ContinueOnItemLoad(function()
    local ilvl2 = GetDisplayedItemLevel(link)
    SetSlotText(context, slotId, ilvl2 and ColorizeIlvlForUnit(unit, slotId, ilvl2) or "")
  end)
end

local function UpdateAll(context, forceLog)
  for slotId in pairs(WANTED) do
    UpdateSlot(context, slotId)
  end

  if forceLog then
    local count = 0
    for _ in pairs(CTX[context].slotButtons) do count = count + 1 end
    dprint("UpdateAll(%s) complete. Slot buttons found: %d", context, count)
  end
end

------------------------------------------------------------
-- Scanning
------------------------------------------------------------
local function ScanForSlotButtons(context, forceLog)
  local parent = GetItemsParent(context)
  if not parent then
    dprint("[%s] items frame not found yet.", context)
    return
  end

  local children = { parent:GetChildren() }
  if forceLog then
    dprint("[%s] Scanning %d children under %s", context, #children, parent:GetName() or "<unnamed>")
  end

  local buttons = CTX[context].slotButtons
  local newlyFound = 0

  for _, child in ipairs(children) do
    if child and child.GetID and child.CreateFontString then
      local id = child:GetID()
      if WANTED[id] and not buttons[id] then
        buttons[id] = child
        EnsureLabel(context, child, id)
        newlyFound = newlyFound + 1
      end
    end
  end

  if forceLog then
    local total = 0
    for _ in pairs(buttons) do total = total + 1 end
    dprint("[%s] Scan complete. New=%d Total=%d", context, newlyFound, total)
  end
end

------------------------------------------------------------
-- UI loading + hooks
------------------------------------------------------------
local function EnsureCharacterUILoaded()
  if CharacterFrame then return end
  if C_AddOns and C_AddOns.LoadAddOn then
    C_AddOns.LoadAddOn("Blizzard_CharacterUI")
  else
    LoadAddOn("Blizzard_CharacterUI")
  end
end

local function EnsureInspectUILoaded()
  if InspectFrame then return end
  if C_AddOns and C_AddOns.LoadAddOn then
    C_AddOns.LoadAddOn("Blizzard_InspectUI")
  else
    LoadAddOn("Blizzard_InspectUI")
  end
end

local function HookCharacterFrames()
  if hookedCharacter then return end
  hookedCharacter = true

  if CharacterFrame then
    CharacterFrame:HookScript("OnShow", function()
      ScanForSlotButtons("player", false)
      RepositionAllLabels("player")
      UpdateAll("player", false)
    end)
  end

  if PaperDollFrame then
    PaperDollFrame:HookScript("OnShow", function()
      ScanForSlotButtons("player", false)
      RepositionAllLabels("player")
      UpdateAll("player", false)
    end)
  end
end

local function HookInspectFrames()
  if hookedInspect then return end
  hookedInspect = true

  if InspectFrame then
    InspectFrame:HookScript("OnShow", function()
      ScanForSlotButtons("inspect", false)
      RepositionAllLabels("inspect")
      UpdateAll("inspect", false)
    end)
  end
end

------------------------------------------------------------
-- Slash command
------------------------------------------------------------
SLASH_SLOTITEMLEVEL1 = "/sil"
SlashCmdList["SLOTITEMLEVEL"] = function(msg)
  msg = (msg or ""):lower()
  if msg == "debug" then
    DEBUG = not DEBUG
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99SlotItemLevel|r debug = " .. tostring(DEBUG))

    C_Timer.After(0, function()
      CTX.player.slotButtons = {}
      CTX.player.slotLabels = {}
      CTX.inspect.slotButtons = {}
      CTX.inspect.slotLabels = {}

      ScanForSlotButtons("player", true)
      RepositionAllLabels("player")
      UpdateAll("player", true)

      EnsureInspectUILoaded()
      HookInspectFrames()
      ScanForSlotButtons("inspect", true)
      RepositionAllLabels("inspect")
      UpdateAll("inspect", true)
    end)
  else
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99SlotItemLevel|r commands: /sil debug")
  end
end

------------------------------------------------------------
-- Events
------------------------------------------------------------
f:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    EnsureCharacterUILoaded()
    HookCharacterFrames()

    -- initial draw for player
    C_Timer.After(0, function()
      ScanForSlotButtons("player", true)
      RepositionAllLabels("player")
      UpdateAll("player", true)
    end)
    C_Timer.After(1, function()
      ScanForSlotButtons("player", false)
      RepositionAllLabels("player")
      UpdateAll("player", false)
    end)

    -- prep inspect (doesn't do anything until Inspect UI is actually opened)
    EnsureInspectUILoaded()
    HookInspectFrames()

  elseif event == "PLAYER_EQUIPMENT_CHANGED" then
    local slotId = ...
    if WANTED[slotId] then
      UpdateSlot("player", slotId)
      RepositionAllLabels("player")
    end

  elseif event == "INSPECT_READY" then
    -- Inspect info arrived; refresh if inspect UI is open
    if InspectFrame and InspectFrame:IsShown() then
      ScanForSlotButtons("inspect", false)
      RepositionAllLabels("inspect")
      UpdateAll("inspect", false)
    end
  end
end)

f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
f:RegisterEvent("INSPECT_READY")
