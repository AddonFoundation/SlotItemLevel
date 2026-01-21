-- SlotItemLevel.lua
local ADDON = ...
local f = CreateFrame("Frame")

------------------------------------------------------------
-- State
------------------------------------------------------------
local slotButtons = {} -- [slotId] = button
local slotLabels  = {} -- [button] = FontString
local hooked = false

------------------------------------------------------------
-- Font config (BIGGER)
------------------------------------------------------------
local FONT_PATH  = "Fonts\\FRIZQT__.TTF"
local FONT_SIZE  = 14          -- bump to 15/16 if you want
local FONT_FLAGS = "OUTLINE"   -- "" if you don't want outline

local OFFSET_X = 6
local OFFSET_Y = -1

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
-- Frame lookup
------------------------------------------------------------
local function GetItemsParent()
  if PaperDollItemsFrame then return PaperDollItemsFrame end
  if CharacterFrame and CharacterFrame.PaperDollItemsFrame then
    return CharacterFrame.PaperDollItemsFrame
  end
  if PaperDollFrame and PaperDollFrame.ItemSlotsFrame then
    return PaperDollFrame.ItemSlotsFrame
  end
end

------------------------------------------------------------
-- Side detection + coloring
------------------------------------------------------------
local function IsButtonOnLeftSide(btn)
  if not btn then return true end
  local ref = GetItemsParent() or (btn.GetParent and btn:GetParent()) or CharacterFrame
  if not ref then return true end

  local bx = btn:GetCenter()
  local rx = ref:GetCenter()
  if not bx or not rx then return true end

  return bx < rx
end

local function ColorizeIlvl(slotId, ilvl)
  local quality = GetInventoryItemQuality("player", slotId)
  if quality then
    local r, g, b = C_Item.GetItemQualityColor(quality)
    return string.format("|cff%02x%02x%02x%d|r", r * 255, g * 255, b * 255, ilvl)
  end
  return tostring(ilvl)
end

------------------------------------------------------------
-- Label creation + positioning (FONT SAFE)
------------------------------------------------------------
local function ApplyFontSafe(fs)
  -- Always start from an existing font (template provides one)
  -- Then try to apply our custom font; if it fails, keep template font.
  local ok = pcall(function()
    fs:SetFont(FONT_PATH, FONT_SIZE, FONT_FLAGS)
  end)
  if not ok then
    -- Fallback: use the normal template font at a slightly larger size
    local font, _, flags = GameFontNormal:GetFont()
    fs:SetFont(font, FONT_SIZE, flags or "")
  end
end

local function PositionLabel(fs, btn, slotId)
  fs:ClearAllPoints()

  -- Weapon slots: flare outward
  if slotId == INVSLOT_MAINHAND then
    fs:SetPoint("RIGHT", btn, "LEFT", -OFFSET_X, OFFSET_Y) -- left weapon: text left
    fs:SetJustifyH("RIGHT")
    return
  elseif slotId == INVSLOT_OFFHAND then
    fs:SetPoint("LEFT", btn, "RIGHT", OFFSET_X, OFFSET_Y)  -- right weapon: text right
    fs:SetJustifyH("LEFT")
    return
  end

  -- Normal slots: left column -> text right, right column -> text left
  if IsButtonOnLeftSide(btn) then
    fs:SetPoint("LEFT", btn, "RIGHT", OFFSET_X, OFFSET_Y)
    fs:SetJustifyH("LEFT")
  else
    fs:SetPoint("RIGHT", btn, "LEFT", -OFFSET_X, OFFSET_Y)
    fs:SetJustifyH("RIGHT")
  end
end

local function EnsureLabel(btn, slotId)
  if slotLabels[btn] then return slotLabels[btn] end

  -- IMPORTANT: create from a template so it always has a font
  local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  ApplyFontSafe(fs)
  PositionLabel(fs, btn, slotId)
  fs:SetText("") -- safe now

  slotLabels[btn] = fs
  return fs
end

local function RepositionAllLabels()
  for slotId, btn in pairs(slotButtons) do
    local fs = slotLabels[btn]
    if fs then
      ApplyFontSafe(fs)
      PositionLabel(fs, btn, slotId)
    else
      EnsureLabel(btn, slotId)
    end
  end
end

local function SetSlotText(slotId, text)
  local btn = slotButtons[slotId]
  if not btn then return end
  EnsureLabel(btn, slotId):SetText(text or "")
end

------------------------------------------------------------
-- Displayed item level (matches tooltip; avoids squish/base-ilvl issues)
------------------------------------------------------------
local function GetDisplayedItemLevel(itemLink)
  if not itemLink then return nil end

  -- 12.x reliable source: whatever the tooltip shows
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

  -- Fallback (may be internal/scaled)
  if C_Item and C_Item.GetDetailedItemLevelInfo then
    return C_Item.GetDetailedItemLevelInfo(itemLink)
  end

  return nil
end



------------------------------------------------------------
-- Update logic
------------------------------------------------------------
local function UpdateSlot(slotId)
  local btn = slotButtons[slotId]
  if not btn then return end

  local link = GetInventoryItemLink("player", slotId)
  if not link then
    SetSlotText(slotId, "")
    return
  end

  local ilvl = GetDisplayedItemLevel(link)
  if ilvl then
    SetSlotText(slotId, ColorizeIlvl(slotId, ilvl))
    return
  end

  -- Async fallback
  local item = Item:CreateFromItemLink(link)
  item:ContinueOnItemLoad(function()
    local ilvl2 = GetDisplayedItemLevel(link)
    SetSlotText(slotId, ilvl2 and ColorizeIlvl(slotId, ilvl2) or "")
  end)
end


local function UpdateAll(forceLog)
  for slotId in pairs(WANTED) do
    UpdateSlot(slotId)
  end

  if forceLog then
    local count = 0
    for _ in pairs(slotButtons) do count = count + 1 end
    dprint("UpdateAll complete. Slot buttons found: %d", count)
  end
end

------------------------------------------------------------
-- Frame scanning
------------------------------------------------------------
local function ScanForSlotButtons(forceLog)
  local parent = GetItemsParent()
  if not parent then
    dprint("PaperDoll items frame not found yet.")
    return
  end

  local children = { parent:GetChildren() }
  dprint("Scanning %d children under %s", #children, parent:GetName() or "<unnamed>")

  local newlyFound = 0
  for _, child in ipairs(children) do
    if child and child.GetID and child.CreateFontString then
      local id = child:GetID()
      if WANTED[id] and not slotButtons[id] then
        slotButtons[id] = child
        EnsureLabel(child, id)
        newlyFound = newlyFound + 1
        dprint("Found slot: id=%d name=%s", id, child:GetName() or "<unnamed>")
      end
    end
  end

  if forceLog then
    local total = 0
    for _ in pairs(slotButtons) do total = total + 1 end
    dprint("Scan complete. New=%d Total=%d", newlyFound, total)
  end
end

------------------------------------------------------------
-- Init / hooks
------------------------------------------------------------
local function EnsureCharacterUILoaded()
  if CharacterFrame then return end
  if C_AddOns and C_AddOns.LoadAddOn then
    C_AddOns.LoadAddOn("Blizzard_CharacterUI")
  else
    LoadAddOn("Blizzard_CharacterUI")
  end
end

local function HookFrames()
  if hooked then return end
  hooked = true

  if CharacterFrame then
    CharacterFrame:HookScript("OnShow", function()
      ScanForSlotButtons(false)
      RepositionAllLabels()
      UpdateAll(false)
    end)
  end

  if PaperDollFrame then
    PaperDollFrame:HookScript("OnShow", function()
      ScanForSlotButtons(false)
      RepositionAllLabels()
      UpdateAll(false)
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
      -- rescan
      slotButtons = {}
      ScanForSlotButtons(true)
      RepositionAllLabels()
      UpdateAll(true)
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
    HookFrames()

    C_Timer.After(0, function()
      ScanForSlotButtons(true)
      RepositionAllLabels()
      UpdateAll(true)
    end)

    C_Timer.After(1, function()
      ScanForSlotButtons(false)
      RepositionAllLabels()
      UpdateAll(false)
    end)

  elseif event == "PLAYER_EQUIPMENT_CHANGED" then
    local slotId = ...
    if WANTED[slotId] then
      UpdateSlot(slotId)
      RepositionAllLabels()
    end
  end
end)

f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
