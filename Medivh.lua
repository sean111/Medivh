local ADDON_NAME = 'Medivh'

-- Created a frame to handle events
---@class Medivh : Frame
---@field availableSpells table[]
---@field playerFaction string
---@field playerClass string
---@field portalSearch bool
---@field autoSetPortal bool
---@field noResult bool
---@field tempBindingExists bool
---@field spellMatches table[]
---@field spellIndex int

---@type Medivh
local medivh = CreateFrame("Frame")
medivh.availableSpells = {}
medivh.playerFaction = nil
medivh.playerClass = nil
medivh.portalSearch = false
medivh.autoSetPortal = false
medivh.noResult = true
medivh.tempBindingExists = false
medivh.spellMatches = {}
medivh.spellIndex = 1

medivh:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        self:OnPlayerLogin()
    end
end)

function medivh:OnPlayerLogin()
    -- Create available spell list from common & player faction spells
    self.playerFaction = UnitFactionGroup("player")
    _, self.playerClass = UnitClass("player")

    if self.playerClass ~= "MAGE" then
        return
    end

    availableSpells = SpellList["Common"]
    for i = 1, #SpellList[self.playerFaction] do
        availableSpells[#availableSpells + 1] = SpellList[self.playerFaction][i]
    end

    print(ADDON_NAME .. " loaded: use /mv, /pm or /port to start")
    SLASH_MEDIVH1 = "/mv"
    SLASH_MEDIVH2 = "/pm"
    SLASH_MEDIVH3 = "/port"
    SlashCmdList["MEDIVH"] = function(msg)
        self:HandleSlashCommand(msg)
    end
end

function medivh:HandleSlashCommand(msg)
    local command = msg:lower():trim()
    --print("Command: " .. command)
    OpenFrame(command)
    --local spellMatches = medivh:searchSpells(command)
    --for index, match in ipairs(spellMatches) do
    --  local spellInfo, _, icon = C_Spell.GetSpellInfo(match.spellId)
    --  --print(spellInfo.name)
    --
    --end
end

function medivh:searchSpells(text)
    if not text then
        return false
    end

    local matches = {}

    local tokens = { strsplit(" ", text) }
    for index, data in ipairs(availableSpells) do
        local spellId = data.teleport
        if self.portalSearch and data.portal then
            spellId = data.portal
        end

        if IsSpellKnown(spellId) then
            local spellInfo, _, icon = C_Spell.GetSpellInfo(spellId)
            if spellInfo then
                local spellName = spellInfo.name
                local searchSpellName = gsub(spellName, "Teleport: ", "")
                searchSpellName = gsub(searchSpellName, "Portal: ", "")

                if data.alias then
                    searchSpellName = searchSpellName .. " " .. table.concat(data.alias, " ")
                end

                local spellFound = true
                for _, token in ipairs(tokens) do
                    spellFound = spellFound and strmatch(strlower(searchSpellName), token)
                end

                if spellFound then
                    tinsert(matches, { data = data, spellId = spellId })
                end
            end
        end
    end
    if #matches > 1 then
    		table.sort(matches, function(a, b)
    			if a == nil and b == nil then
    				return false
    			end
    			if a == nil then
    				return true
    			end
    			if b == nil then
    				return false
    			end

    			return (a.data.priority or 0) > (b.data.priority or 0)
    				or (a.data.alias and 1 or 0) > (b.data.alias and 1 or 0)
    		end)
    	end
    return matches
end

function medivh:setSearchText()
  if medivh.portalSearch == false then
    MedivhFrame.searchInfo:SetText('Press TAB to match portals')
    MedivhFrameSearch.Instructions:SetText("Search Teleport")
  else
    MedivhFrame.searchInfo:SetText('Press TAB to match teleports')
    MedivhFrameSearch.Instructions:SetText("Search Portal")
  end
end

function medivh:resetSearch(text)
  MedivhFrameSearch:SetText(text or "")
  MedivhFrameSearch:HighlightText(0, strlen(text or ""))

  if text then
    medivh:updateSearch()
  end
end

function medivh:updateSearch()
  medivh:onTextChanged()
end

-- UI
function OpenFrame(text)
  if medivh.playerClass ~= "MAGE" then
    return
  end

  if MedivhFrame:IsShown() then
    return
  end

  medivh.portalSearch = false
  medivh:setSearchText()

  medivh:resetSearch(text)
  MedivhFrame:Show()
  MedivhFrameSearch:Show()
  MedivhFrameSearch:SetFocus()
  MedivhFrameSpellConfirm:Hide()
end


function CloseFrame()
  if InCombatLockdown() then
    return
  end
  medivh:removeTempBinding()
  MedivhFrame:Hide()
end

function medivh:onTextChanged()
  --print("portalSearch: " .. tostring(medivh.portalSearch))
  --print("autoSetPortal: " .. tostring(medivh.autoSetPortal))
  local self = MedivhFrameSearch
  SearchBoxTemplate_OnTextChanged(self);
  local searchText = strtrim(strlower(self:GetText()))
  local first, rest = strsplit(" ", searchText, 2)

  if first == "p" or first == "portal" then
    medivh.portalSearch = true
    medivh.autoSetPortal = true
    searchText = rest or ""
  elseif medivh.portalSearch and medivh.autoSetPortal then
    medivh.portalSearch = false
    medivh.autoSetPortal = false
  end

  MedivhFrame.searchInfo:Show()

  medivh:setSearchText()

  medivh.noResult = true

  if strlen(searchText) > 0 then
    medivh.spellMatches = medivh:searchSpells(searchText)
    local matchCount = #medivh.spellMatches
    if matchCount > 1 then
      medivh:setCycleText(1, matchCount)
      MedivhFrame.cycleHint:Show()
    else
      MedivhFrame.cycleHint:Hide()
    end
    if medivh.spellMatches and medivh.spellMatches[1] then
      local match = medivh.spellMatches[1]
      medivh:activeSpell(match)
      medivh.noResult = false
      medivh.spellIndex = 1
      return
    else
      MedivhFrameSpellName:SetText("No Result")
      MedivhFrameSpellButton:Hide()
    end
  else
    MedivhFrameSpellName:SetText("Enter spell name")
    MedivhFrameSpellButton:Hide()
  end
end

function medivh:activeSpell(spell)
    local spellInfo = C_Spell.GetSpellInfo(spell.spellId)
    --print(spellInfo.name);
    --print(spellInfo.spellID)
    --print(spellInfo.iconID)
    MedivhFrameSpellName:SetText(spellInfo.name)
    MedivhFrameSpellButton.icon:SetTexture(spellInfo.iconID)
    MedivhFrameSpellButton:SetAttribute("type", "spell")
    MedivhFrameSpellButton:SetAttribute("spell", spellInfo.name)
    MedivhFrameSpellButton:Show()
end

function medivh:createTempBinding()
  if medivh.tempBindingExists then
    return
  end

  SetOverrideBindingClick(MedivhFrame, true, "ENTER", "MedivhFrameSpellButton", "LeftButton")
  medivh.tempBindingExists = true
end

function medivh:removeTempBinding()
  if not medivh.tempBindingExists then
    return
  end
  MedivhFrameSpellButton:SetAttribute("type", nil)
  MedivhFrameSpellButton:SetAttribute("spell", nil)
  medivh.tempBindingExists = false
end

function medivh:setCycleText(current, max)
  MedivhFrame.cycleHint:SetText(string.format("Use Up/Down to cycle (%d / %d)", current, max))
end



function OnTabPressed()
  --print("Tab pressed....")
  if medivh.portalSearch == false then
    medivh.portalSearch = true
  else
    medivh.portalSearch = false
    local searchText = strtrim(MedivhFrameSearch:GetText());
    --print("OnTabPressed::searchText: " .. searchText)
    local first, rest = strsplit(" ", searchText, 2)

    if strlower(first) == "p" or strlower(first) == "portal" then
      MedivhFrameSearch:SetText(rest or "")
    end
  end
  medivh.autoSetPortal = false
  medivh:onTextChanged()
end


function OnTextChanged()
  medivh:onTextChanged()
end

function UpdateSearch()
  medivh:onTextChanged()
end

function OnEscapePressed(self)
  self:ClearFocus()
  CloseFrame()
end

function OnEditFocusLost()
end

function OnEnterPressed(self)
  if not MedivhFrame:IsShown() then
    return
  end
  if medivh.noResult then
    return
  end

  local searchText = strtrim(strlower(self:GetText()))

  if strlen(searchText) == 0 then
    CloseFrame()
    return
  end

  medivh:createTempBinding()

  MedivhFrameSearch:Hide()
  MedivhFrame.searchInfo:Hide()
  MedivhFrame.cycleHint:Hide()
  MedivhFrameSpellConfirm:Show()

end

function OnArrowPressed(_self, key)
  local len = #medivh.spellMatches
  if key == "UP" then
    if medivh.spellIndex == 1 then
      medivh.spellIndex = len
    else
      medivh.spellIndex = medivh.spellIndex - 1
    end
  elseif key == "DOWN" then
    if medivh.spellIndex == len then
      medivh.spellIndex = 1
    else
      medivh.spellIndex = medivh.spellIndex + 1
    end
  end
  medivh:activeSpell(medivh.spellMatches[medivh.spellIndex])
  medivh:setCycleText(medivh.spellIndex, len)
end

-- Event registration
medivh:RegisterEvent("PLAYER_LOGIN")
