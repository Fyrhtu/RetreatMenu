--[[
  RetreatMenu — ultra-light travel/hearth dropdown for Ascension (3.3.5 / CoA).
  Inspired by ProfessionMenu's single draggable button UX. No Ace/Dewdrop.

  Creator: Fyrhtu
  https://github.com/Fyrhtu/RetreatMenu
]]

local ADDON = "RetreatMenu"
local DB

-- Known item IDs (extensible; bag/vanity/name scan fills gaps)
local ITEM_TRAVEL_PERMIT = 977028
local ITEM_HEARTHSTONE = 6948
local ITEM_FEL_GATEWAY = 1903515
local ITEM_SCROLL_STORMWIND = 1175626
local ITEM_SCROLL_ORGRIMMAR = 1175627
-- Flight Master's Whistle: Ascension may use a custom ID; also match by name.
local ITEM_FLIGHT_WHISTLE = 141605

-- Spells that replace the hearthstone (shown with HS; tooltip may advise deleting HS)
local HEARTH_REPLACEMENT_SPELLS = {
	979806, -- Arcane Rune of Retreat
}

-- Seed stone spell IDs (spellbook scan discovers the rest)
local STONE_SPELL_SEEDS = {
	777000, 777001, 777002, 777003, 777008,
	1777066, 1777084, 1777085, 1777086, 1777087, 1777091,
	102181, 777030,
}

-- Location name → continent bucket for submenu grouping
local EK = "Eastern Kingdoms"
local KAL = "Kalimdor"
local OTHER = "Other"

local LOCATION_CONTINENT = {
	-- Eastern Kingdoms
	["stormwind"] = EK, ["ironforge"] = EK, ["undercity"] = EK, ["darnassus"] = KAL, -- darnassus is kal
	["booty bay"] = EK, ["kharanos"] = EK, ["goldshire"] = EK, ["eastvale"] = EK,
	["southshore"] = EK, ["south shore"] = EK, ["light's hope"] = EK, ["lights hope"] = EK,
	["flame crest"] = EK, ["stockade"] = EK, ["menethil"] = EK, ["lakeshire"] = EK,
	["darkshire"] = EK, ["sentinel hill"] = EK, ["tarren mill"] = EK, ["brill"] = EK,
	["sepulcher"] = EK, ["the sepulcher"] = EK, ["aerie peak"] = EK, ["refuge pointe"] = EK,
	["hammerfall"] = EK, ["revantusk"] = EK, ["stoutlager"] = EK, ["chillwind"] = EK,
	["light's hope chapel"] = EK,
	-- Kalimdor
	["orgrimmar"] = KAL, ["thunder bluff"] = KAL, ["thunderbluff"] = KAL,
	["darnassus"] = KAL, ["dolanaar"] = KAL, ["ratchet"] = KAL, ["theramore"] = KAL,
	["astranaar"] = KAL, ["crossroads"] = KAL, ["the crossroads"] = KAL,
	["bloodhoof"] = KAL, ["sen'jin"] = KAL, ["senjin"] = KAL, ["nijel's point"] = KAL,
	["feathermoon"] = KAL, ["gadgetzan"] = KAL, ["cenarion hold"] = KAL,
	["marshall's refuge"] = KAL, ["marshals refuge"] = KAL, ["everlook"] = KAL,
	["valormok"] = KAL, ["splintertree"] = KAL, ["zoram'gar"] = KAL,
	-- Outland / misc (bucket Other)
	["cosmowrench"] = OTHER, ["shattrath"] = OTHER, ["area 52"] = OTHER,
}

local tt = CreateFrame("GameTooltip", "RetreatMenuScanTip", nil, "GameTooltipTemplate")
tt:SetOwner(UIParent, "ANCHOR_NONE")

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffRetreatMenu:|r " .. tostring(msg))
end

local function SafeIsSpellKnown(id)
	if type(CA_IsSpellKnown) == "function" then
		return CA_IsSpellKnown(id)
	end
	if type(IsSpellKnown) == "function" then
		return IsSpellKnown(id)
	end
	return false
end

local function VanityOwned(itemID)
	if type(C_VanityCollection) == "table" and type(C_VanityCollection.IsCollectionItemOwned) == "function" then
		return C_VanityCollection.IsCollectionItemOwned(itemID)
	end
	return false
end

local function VanityDeliver(itemID)
	if type(RequestDeliverVanityCollectionItem) == "function" then
		RequestDeliverVanityCollectionItem(itemID)
		return true
	end
	return false
end

local function FindItemInBags(itemID)
	if not itemID then return nil end
	for bag = 0, 4 do
		local slots = GetContainerNumSlots(bag) or 0
		for slot = 1, slots do
			local link = GetContainerItemLink(bag, slot)
			if link then
				local id = tonumber(link:match("item:(%d+)"))
				if id == itemID then
					return bag, slot
				end
			end
		end
	end
	return nil
end

local function FindItemByName(name)
	if not name then return nil end
	local want = string.lower(name)
	for bag = 0, 4 do
		local slots = GetContainerNumSlots(bag) or 0
		for slot = 1, slots do
			local link = GetContainerItemLink(bag, slot)
			if link then
				local n = link:match("%[(.-)%]")
				if n and string.lower(n) == want then
					local id = tonumber(link:match("item:(%d+)"))
					return id, bag, slot, n
				end
			end
		end
	end
	return nil
end

local function ItemCooldownText(itemID)
	if not itemID or type(GetItemCooldown) ~= "function" then return "" end
	local start, duration, enable = GetItemCooldown(itemID)
	if not start or not duration or duration <= 0 or enable == 0 then return "" end
	local left = (start + duration) - GetTime()
	if left <= 0 then return "" end
	if left >= 60 then
		return string.format(" |cff00ffff(%dm)|r", math.ceil(left / 60))
	end
	return string.format(" |cff00ffff(%ds)|r", math.ceil(left))
end

local function SpellCooldownText(spellID)
	if not spellID or type(GetSpellCooldown) ~= "function" then return "" end
	local start, duration, enable = GetSpellCooldown(spellID)
	if type(start) == "table" then
		-- modern API compatibility
		duration = start.duration
		enable = start.isEnabled and 1 or 0
		start = start.startTime
	end
	if not start or not duration or duration <= 0 or enable == 0 then return "" end
	local left = (start + duration) - GetTime()
	if left <= 0 then return "" end
	if left >= 60 then
		return string.format(" |cff00ffff(%dm)|r", math.ceil(left / 60))
	end
	return string.format(" |cff00ffff(%ds)|r", math.ceil(left))
end

local function TooltipLines(setter)
	tt:Hide()
	tt:SetOwner(UIParent, "ANCHOR_NONE")
	tt:ClearLines()
	-- pcall: bad SetSpell args must not hard-error
	local ok = pcall(setter, tt)
	if not ok then
		tt:Hide()
		return {}
	end
	-- Force layout so NumLines/GetText are populated (hidden tooltips can lag a frame).
	tt:Show()
	local lines = {}
	local n = tt:NumLines() or 0
	for i = 1, n do
		local fs = _G["RetreatMenuScanTipTextLeft" .. i]
		if fs then
			local t = fs:GetText()
			if t and t ~= "" then lines[#lines + 1] = t end
		end
	end
	-- Also check right side (rarely used for this text)
	for i = 1, n do
		local fs = _G["RetreatMenuScanTipTextRight" .. i]
		if fs then
			local t = fs:GetText()
			if t and t ~= "" then lines[#lines + 1] = t end
		end
	end
	tt:Hide()
	return lines
end

-- On 3.3.5 / Ascension: GameTooltip:SetSpell(slot, bookType) is slot-based.
-- Spell IDs must use SetHyperlink("spell:ID") or SetSpellByID if present.
local function TooltipSetSpellID(tip, spellID)
	if not spellID then return end
	if type(tip.SetSpellByID) == "function" then
		tip:SetSpellByID(spellID)
	else
		tip:SetHyperlink("spell:" .. tostring(spellID))
	end
end

local function TooltipSetSpellBookSlot(tip, slot)
	if not slot then return end
	tip:SetSpell(slot, BOOKTYPE_SPELL)
end

local function ParseReturnLocation(lines)
	if type(lines) ~= "table" then return nil end
	for _, line in ipairs(lines) do
		if type(line) == "string" then
			-- "Returns you to Teldrassil. Speak to an Innkeeper..."
			-- "Returns you to Goldshire in Elwynn Forest."
			local loc = line:match("[Rr]eturns you to%s+(.+)")
			if loc then
				-- cut at sentence end or "Speak to"
				loc = loc:gsub("[%.%!].*$", "")
				loc = loc:gsub("%s*[Ss]peak to.*$", "")
				loc = loc:gsub("%s+$", ""):gsub("^%s+", "")
				if loc ~= "" then
					return loc
				end
			end
		end
	end
	return nil
end

--- Best-effort hearth bind location for the "Bound:" header.
local function GetHearthBindLocation(hearthSpellEntries)
	-- 1) Hearth-replacement spells first (often the only hearth on Ascension)
	if type(hearthSpellEntries) == "table" then
		for _, e in ipairs(hearthSpellEntries) do
			if e.location and e.location ~= "" and e.location ~= "your home" then
				return e.location
			end
			-- Re-scan tooltip: book slot first (character-specific bind)
			local lines
			if e.bookIndex then
				lines = TooltipLines(function(t) TooltipSetSpellBookSlot(t, e.bookIndex) end)
			end
			if (not lines or #lines == 0) and e.id then
				lines = TooltipLines(function(t) TooltipSetSpellID(t, e.id) end)
			end
			local loc = ParseReturnLocation(lines)
			if loc then return loc end
		end
	end

	-- 2) Physical hearthstone in bags (bind is on the item instance)
	local bag, slot = FindItemInBags(ITEM_HEARTHSTONE)
	if bag then
		local lines = TooltipLines(function(t)
			t:SetBagItem(bag, slot)
		end)
		local loc = ParseReturnLocation(lines)
		if loc then return loc end
	end

	-- 3) Generic item link last (often lacks character bind location)
	local lines = TooltipLines(function(t)
		t:SetHyperlink("item:" .. ITEM_HEARTHSTONE)
	end)
	local loc = ParseReturnLocation(lines)
	if loc then return loc end

	return "your home"
end

local function ContinentForLocation(loc)
	if not loc then return OTHER end
	local l = string.lower(loc)
	for key, cont in pairs(LOCATION_CONTINENT) do
		if string.find(l, key, 1, true) then
			return cont
		end
	end
	-- Heuristic: many "X in Zone" patterns
	if string.find(l, "kalimdor", 1, true) then return KAL end
	if string.find(l, "eastern", 1, true) then return EK end
	return OTHER
end

local function LocationFromSpellName(name)
	if not name then return nil end
	local loc = name:match(":%s*(.+)$")
	return loc
end

--------------------------------------------------------------------------
-- Spellbook discovery
--------------------------------------------------------------------------
local function ScanSpellbook()
	local stones, runes, hearths, other = {}, {}, {}, {}
	local seen = {}

	local function knownSpell(spellID)
		if not spellID then return false end
		if type(CA_IsSpellKnown) == "function" and CA_IsSpellKnown(spellID) then return true end
		if type(IsSpellKnown) == "function" and IsSpellKnown(spellID) then return true end
		if type(IsPlayerSpell) == "function" and IsPlayerSpell(spellID) then return true end
		return false
	end

	local function bucketEntry(entry)
		local lower = string.lower(entry.name or "")
		if string.find(lower, "stone of retreat", 1, true) then
			stones[#stones + 1] = entry
		elseif string.find(lower, "arcane rune of retreat", 1, true) then
			hearths[#hearths + 1] = entry
		elseif string.find(lower, "rune of retreat", 1, true) then
			runes[#runes + 1] = entry
		elseif string.find(lower, "hearth", 1, true) then
			hearths[#hearths + 1] = entry
		end
	end

	local function fillLocation(entry)
		local lines
		-- Prefer spellbook slot tooltip (has character bind text on Ascension).
		if entry.bookIndex then
			lines = TooltipLines(function(t) TooltipSetSpellBookSlot(t, entry.bookIndex) end)
		end
		if (not lines or #lines == 0) and entry.id then
			lines = TooltipLines(function(t) TooltipSetSpellID(t, entry.id) end)
		end
		local tloc = lines and ParseReturnLocation(lines)
		if tloc then
			entry.location = tloc
		elseif not entry.location then
			entry.location = LocationFromSpellName(entry.name)
		end
		entry.continent = ContinentForLocation(entry.location or entry.name)
	end

	-- 1) Spellbook first (slot tooltips carry bind location for vanity retreat spells)
	local numTabs = GetNumSpellTabs and GetNumSpellTabs() or 0
	for tab = 1, numTabs do
		local _, _, offset, numSpells = GetSpellTabInfo(tab)
		offset = offset or 0
		numSpells = numSpells or 0
		for i = offset + 1, offset + numSpells do
			local spellName = GetSpellName(i, BOOKTYPE_SPELL)
			if spellName then
				local lower = string.lower(spellName)
				if string.find(lower, "retreat", 1, true)
					or string.find(lower, "hearth", 1, true) then
					local link = GetSpellLink and GetSpellLink(i, BOOKTYPE_SPELL)
					local sid = link and tonumber(link:match("spell:(%d+)"))
					if not seen[spellName] and not (sid and seen[sid]) then
						if sid then seen[sid] = true end
						seen[spellName] = true
						local entry = {
							kind = "spell",
							id = sid,
							name = spellName,
							icon = GetSpellTexture(i, BOOKTYPE_SPELL) or select(3, GetSpellInfo(spellName)),
							bookIndex = i,
						}
						fillLocation(entry)
						entry.cd = function()
							if entry.id then return SpellCooldownText(entry.id) end
							local s, d = GetSpellCooldown(i, BOOKTYPE_SPELL)
							if not s or not d or d <= 0 then return "" end
							local left = (s + d) - GetTime()
							if left <= 0 then return "" end
							if left >= 60 then return string.format(" |cff00ffff(%dm)|r", math.ceil(left / 60)) end
							return string.format(" |cff00ffff(%ds)|r", math.ceil(left))
						end
						bucketEntry(entry)
					end
				end
			end
		end
	end

	-- 2) Seeds only for known spells not already found in the book
	local function considerSeed(spellID)
		if not spellID or seen[spellID] or not knownSpell(spellID) then return end
		local name = GetSpellInfo(spellID)
		if not name or seen[name] then return end
		seen[spellID] = true
		seen[name] = true
		local entry = {
			kind = "spell",
			id = spellID,
			name = name,
			icon = select(3, GetSpellInfo(spellID)) or "Interface\\Icons\\INV_Misc_Rune_01",
		}
		fillLocation(entry)
		entry.cd = function() return SpellCooldownText(spellID) end
		bucketEntry(entry)
	end
	for _, id in ipairs(STONE_SPELL_SEEDS) do
		considerSeed(id)
	end
	for _, id in ipairs(HEARTH_REPLACEMENT_SPELLS) do
		considerSeed(id)
	end

	local function byName(a, b)
		return (a.name or "") < (b.name or "")
	end
	table.sort(stones, byName)
	table.sort(runes, byName)
	table.sort(hearths, byName)
	return stones, runes, hearths, other
end

--------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------
local mainBtn, menuFrame, menuButtons = nil, nil, {}
local unlocked = false
local AUTO_CLOSE_SEC = 5
local menuAwayTime = 0
local HideMenu -- forward decl (auto-close OnUpdate calls it)

local function IsMouseOverMenuUI()
	if menuFrame and menuFrame:IsShown() and menuFrame:IsMouseOver() then
		return true
	end
	-- Keep open while hovering the launcher button too.
	if mainBtn and mainBtn:IsMouseOver() then
		return true
	end
	return false
end

local function StopMenuAutoClose()
	menuAwayTime = 0
	if menuFrame then
		menuFrame:SetScript("OnUpdate", nil)
	end
end

local function StartMenuAutoClose()
	menuAwayTime = 0
	if not menuFrame then return end
	menuFrame:SetScript("OnUpdate", function(self, elapsed)
		if not self:IsShown() then
			StopMenuAutoClose()
			return
		end
		if IsMouseOverMenuUI() then
			menuAwayTime = 0
			return
		end
		menuAwayTime = menuAwayTime + elapsed
		if menuAwayTime >= AUTO_CLOSE_SEC then
			HideMenu()
		end
	end)
end

HideMenu = function()
	StopMenuAutoClose()
	if menuFrame then menuFrame:Hide() end
end

local function ClearMenuButtons()
	for _, b in ipairs(menuButtons) do
		b:Hide()
		b:SetAttribute("type", nil)
		b:SetAttribute("spell", nil)
		b:SetAttribute("item", nil)
		b:SetScript("OnClick", nil)
		b:SetScript("PreClick", nil)
	end
end

local function AcquireButton(i)
	if menuButtons[i] then return menuButtons[i] end
	local b = CreateFrame("Button", "RetreatMenuBtn" .. i, menuFrame, "SecureActionButtonTemplate")
	b:SetHeight(20)
	-- 3.3.5 SecureActionButtons have no SetTextFontObject; use our own FontString.
	b:RegisterForClicks("AnyUp")
	local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fs:SetPoint("LEFT", 22, 0)
	fs:SetPoint("RIGHT", -4, 0)
	fs:SetJustifyH("LEFT")
	b.text = fs
	local tex = b:CreateTexture(nil, "ARTWORK")
	tex:SetSize(16, 16)
	tex:SetPoint("LEFT", 2, 0)
	b.icon = tex
	local hi = b:CreateTexture(nil, "HIGHLIGHT")
	hi:SetAllPoints()
	hi:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	hi:SetBlendMode("ADD")
	menuButtons[i] = b
	return b
end

local function AddTitle(y, text, idx)
	local b = AcquireButton(idx)
	b:SetPoint("TOPLEFT", 4, y)
	b:SetPoint("TOPRIGHT", -4, y)
	b:SetHeight(18)
	b.icon:Hide()
	b.text:SetPoint("LEFT", 4, 0)
	b.text:SetText("|cffffff00" .. text)
	b:SetAttribute("type", nil)
	b:EnableMouse(false)
	b:Show()
	return y - 18, idx + 1
end

local function AddSubtitle(y, text, idx)
	local b = AcquireButton(idx)
	b:SetPoint("TOPLEFT", 4, y)
	b:SetPoint("TOPRIGHT", -4, y)
	b:SetHeight(16)
	b.icon:Hide()
	b.text:SetPoint("LEFT", 8, 0)
	b.text:SetText("|cffaaaaaa" .. text)
	b:SetAttribute("type", nil)
	b:EnableMouse(false)
	b:Show()
	return y - 16, idx + 1
end

local function AddSpellLine(y, entry, idx, tooltipExtra)
	local b = AcquireButton(idx)
	b:SetPoint("TOPLEFT", 4, y)
	b:SetPoint("TOPRIGHT", -4, y)
	b:SetHeight(20)
	b.icon:Show()
	b.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_Rune_01")
	b.text:SetPoint("LEFT", 22, 0)
	local cd = entry.cd and entry.cd() or ""
	b.text:SetText((entry.name or "?") .. cd)
	b:EnableMouse(true)
	if entry.id then
		b:SetAttribute("type", "spell")
		b:SetAttribute("spell", entry.id)
	else
		b:SetAttribute("type", "spell")
		b:SetAttribute("spell", entry.name)
	end
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if entry.id then
			TooltipSetSpellID(GameTooltip, entry.id)
		elseif entry.bookIndex then
			TooltipSetSpellBookSlot(GameTooltip, entry.bookIndex)
		else
			GameTooltip:SetText(entry.name or "")
		end
		if tooltipExtra then
			GameTooltip:AddLine(tooltipExtra, 0.4, 1, 0.4, true)
		end
		if entry.location then
			GameTooltip:AddLine("Destination: " .. entry.location, 1, 1, 0.6, true)
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:SetScript("PostClick", function() HideMenu() end)
	b:Show()
	return y - 20, idx + 1
end

local function AddItemLine(y, itemID, name, icon, idx, opts)
	opts = opts or {}
	local b = AcquireButton(idx)
	b:SetPoint("TOPLEFT", 4, y)
	b:SetPoint("TOPRIGHT", -4, y)
	b:SetHeight(20)
	local n, _, _, _, _, _, _, _, _, ic = GetItemInfo(itemID)
	name = name or n or ("item:" .. tostring(itemID))
	icon = icon or ic or "Interface\\Icons\\INV_Misc_QuestionMark"
	b.icon:Show()
	b.icon:SetTexture(icon)
	b.text:SetPoint("LEFT", 22, 0)
	local inBags = FindItemInBags(itemID) ~= nil
	local vanity = VanityOwned(itemID)
	local suffix = ItemCooldownText(itemID)
	if not inBags and vanity then
		suffix = suffix .. " |cff88ff88(vanity)|r"
	elseif not inBags and not vanity then
		suffix = suffix .. " |cff888888(missing)|r"
	end
	b.text:SetText(name .. suffix)
	b:EnableMouse(true)

	if inBags then
		b:SetAttribute("type", "item")
		b:SetAttribute("item", name)
		b:SetScript("PreClick", nil)
	else
		b:SetAttribute("type", nil)
		b:SetAttribute("item", nil)
		b:SetScript("PreClick", function()
			if vanity then
				if VanityDeliver(itemID) then
					Print("Delivering " .. name .. " from Vanity Collection…")
				else
					Print("Vanity deliver API unavailable.")
				end
			else
				Print(name .. " not in bags or vanity.")
			end
		end)
	end
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink("item:" .. itemID)
		if opts.hearthTip then
			GameTooltip:AddLine(opts.hearthTip, 0.4, 1, 0.4, true)
		end
		if not inBags and vanity then
			GameTooltip:AddLine("Click to deliver from Vanity Collection, then use again.", 0.6, 0.8, 1, true)
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:SetScript("PostClick", function()
		if inBags then HideMenu() end
	end)
	b:Show()
	return y - 20, idx + 1
end

local function BuildMenu()
	if InCombatLockdown() then
		Print("Can't refresh menu in combat.")
		if menuFrame and menuFrame:IsShown() then return end
	end
	if not menuFrame then
		menuFrame = CreateFrame("Frame", "RetreatMenuDrop", UIParent)
		menuFrame:SetFrameStrata("DIALOG")
		menuFrame:SetClampedToScreen(true)
		menuFrame:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 12, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		menuFrame:SetBackdropColor(0, 0, 0, 0.92)
		menuFrame:EnableMouse(true)
		tinsert(UISpecialFrames, "RetreatMenuDrop")
	end
	ClearMenuButtons()

	local stones, runes, hearthSpells = ScanSpellbook()
	local y, idx = -6, 1
	local width = 280

	-- 1) Travel Permit (level < 9)
	local level = UnitLevel("player") or 1
	if level < 9 then
		local has = FindItemInBags(ITEM_TRAVEL_PERMIT) or VanityOwned(ITEM_TRAVEL_PERMIT)
		if has or FindItemByName("Travel Permit") then
			y, idx = AddTitle(y, "Starter", idx)
			y, idx = AddItemLine(y, ITEM_TRAVEL_PERMIT, "Travel Permit", nil, idx)
		end
	end

	-- 2) Hearthstone / replacements
	y, idx = AddTitle(y, "Hearth", idx)
	local hsName = GetItemInfo(ITEM_HEARTHSTONE) or "Hearthstone"

	local hasHS = FindItemInBags(ITEM_HEARTHSTONE) ~= nil
	local replNames = {}
	for _, e in ipairs(hearthSpells) do
		replNames[#replNames + 1] = e.name
	end
	-- also check seed replacements even if scan missed
	for _, sid in ipairs(HEARTH_REPLACEMENT_SPELLS) do
		if SafeIsSpellKnown(sid) or (type(IsSpellKnown) == "function" and IsSpellKnown(sid)) then
			local n = GetSpellInfo(sid)
			if n then
				local found = false
				for _, e in ipairs(hearthSpells) do if e.name == n then found = true break end end
				if not found then
					local e = {
						kind = "spell", id = sid, name = n,
						icon = select(3, GetSpellInfo(sid)),
						cd = function() return SpellCooldownText(sid) end,
					}
					local lines = TooltipLines(function(t) TooltipSetSpellID(t, sid) end)
					e.location = ParseReturnLocation(lines)
					hearthSpells[#hearthSpells + 1] = e
					replNames[#replNames + 1] = n
				end
			end
		end
	end

	-- Bound location: bag HS instance first, then replacement spell tooltips
	local hearthLoc = GetHearthBindLocation(hearthSpells)
	y, idx = AddSubtitle(y, "Bound: " .. hearthLoc, idx)

	local hearthTip
	if hasHS and #replNames > 0 then
		hearthTip = "You can safely delete your hearthstone; the spell |cffffffff"
			.. table.concat(replNames, "|r / |cffffffff")
			.. "|r replaces the function of your hearthstone."
	end

	if hasHS or VanityOwned(ITEM_HEARTHSTONE) then
		y, idx = AddItemLine(y, ITEM_HEARTHSTONE, hsName, "Interface\\Icons\\INV_Misc_Rune_01", idx, { hearthTip = hearthTip })
	end
	for _, e in ipairs(hearthSpells) do
		local tip = hearthTip
		if e.location then
			-- refresh bind text from spell
		end
		y, idx = AddSpellLine(y, e, idx, tip)
	end
	if not hasHS and #hearthSpells == 0 then
		y, idx = AddSubtitle(y, "(no hearthstone or replacement known)", idx)
	end

	-- 3) Hearth-duplicating items
	local gateName = GetItemInfo(ITEM_FEL_GATEWAY) or "Fel-Infused Gateway"
	if FindItemInBags(ITEM_FEL_GATEWAY) or VanityOwned(ITEM_FEL_GATEWAY) or FindItemByName("Fel-Infused Gateway") then
		y, idx = AddTitle(y, "Portals & Gateways", idx)
		y, idx = AddItemLine(y, ITEM_FEL_GATEWAY, gateName, nil, idx)
	end

	-- 4) Faction scroll
	local faction = UnitFactionGroup("player")
	local scrollID = (faction == "Alliance") and ITEM_SCROLL_STORMWIND or ITEM_SCROLL_ORGRIMMAR
	local scrollName = GetItemInfo(scrollID)
	if not scrollName then
		scrollName = (faction == "Alliance") and "Scroll of Retreat: Stormwind" or "Scroll of Retreat: Orgrimmar"
	end
	if FindItemInBags(scrollID) or VanityOwned(scrollID) or FindItemByName(scrollName) then
		y, idx = AddTitle(y, "Scroll of Retreat", idx)
		y, idx = AddItemLine(y, scrollID, scrollName, nil, idx)
	end

	-- 5) Stones by continent
	if #stones > 0 then
		y, idx = AddTitle(y, "Stones of Retreat", idx)
		local byCont = { [EK] = {}, [KAL] = {}, [OTHER] = {} }
		for _, e in ipairs(stones) do
			local c = e.continent or OTHER
			if not byCont[c] then byCont[c] = {} end
			table.insert(byCont[c], e)
		end
		for _, cont in ipairs({ EK, KAL, OTHER }) do
			local list = byCont[cont]
			if list and #list > 0 then
				table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
				y, idx = AddSubtitle(y, cont, idx)
				for _, e in ipairs(list) do
					y, idx = AddSpellLine(y, e, idx)
				end
			end
		end
	end

	-- 6) Runes by continent (EK / Kalimdor focus)
	if #runes > 0 then
		y, idx = AddTitle(y, "Runes of Retreat", idx)
		local byCont = { [EK] = {}, [KAL] = {}, [OTHER] = {} }
		for _, e in ipairs(runes) do
			local c = e.continent or OTHER
			if not byCont[c] then byCont[c] = {} end
			table.insert(byCont[c], e)
		end
		for _, cont in ipairs({ EK, KAL, OTHER }) do
			local list = byCont[cont]
			if list and #list > 0 then
				table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
				y, idx = AddSubtitle(y, cont, idx)
				for _, e in ipairs(list) do
					y, idx = AddSpellLine(y, e, idx)
				end
			end
		end
	end

	-- 7) Flight Master's Whistle
	y, idx = AddTitle(y, "Travel", idx)
	local whistleID = ITEM_FLIGHT_WHISTLE
	local wName = "Flight Master's Whistle"
	local wid, _, _ = FindItemByName(wName)
	if wid then whistleID = wid end
	-- try GetItemInfo
	if not GetItemInfo(whistleID) then
		-- name-only vanity unknown: still show if in bags by name
		local id2 = FindItemByName(wName)
		if id2 then whistleID = id2 end
	end
	if FindItemInBags(whistleID) or VanityOwned(whistleID) or FindItemByName(wName) then
		y, idx = AddItemLine(y, whistleID, wName, "Interface\\Icons\\Ability_Hunter_BeastCall", idx)
	else
		-- last resort: scan bags for "Whistle" + flight
		local found
		for bag = 0, 4 do
			for slot = 1, GetContainerNumSlots(bag) or 0 do
				local link = GetContainerItemLink(bag, slot)
				if link then
					local n = link:match("%[(.-)%]")
					if n and string.find(string.lower(n), "flight", 1, true) and string.find(string.lower(n), "whistle", 1, true) then
						local id = tonumber(link:match("item:(%d+)"))
						y, idx = AddItemLine(y, id, n, nil, idx)
						found = true
						break
					end
				end
			end
			if found then break end
		end
		if not found then
			y, idx = AddSubtitle(y, "Flight Master's Whistle (not found)", idx)
		end
	end

	local height = math.max(40, -y + 10)
	menuFrame:SetWidth(width)
	menuFrame:SetHeight(height)
	menuFrame:ClearAllPoints()
	menuFrame:SetPoint("TOPLEFT", mainBtn, "BOTTOMLEFT", 0, -2)
	menuFrame:Show()
	StartMenuAutoClose()
end

local function ToggleMenu()
	if menuFrame and menuFrame:IsShown() then
		HideMenu()
	else
		BuildMenu()
	end
end

local function UpdateUnlockVisual()
	if not mainBtn or not mainBtn.unlockBorder then return end
	if DB and DB.unlocked then
		mainBtn.unlockBorder:Show()
	else
		mainBtn.unlockBorder:Hide()
	end
end

local function CreateMainButton()
	mainBtn = CreateFrame("Button", "RetreatMenuFrame", UIParent)
	mainBtn:SetSize(56, 56)
	mainBtn:SetMovable(true)
	mainBtn:EnableMouse(true)
	mainBtn:RegisterForDrag("LeftButton")
	mainBtn:SetClampedToScreen(true)
	mainBtn:SetFrameStrata("MEDIUM")

	-- Purple edge glow when unlocked (~4px around the button).
	-- Four solid edge textures (ChatFrameBackground works on 3.3.5).
	local border = CreateFrame("Frame", nil, mainBtn)
	border:SetPoint("TOPLEFT", -4, 4)
	border:SetPoint("BOTTOMRIGHT", 4, -4)
	border:SetFrameLevel((mainBtn:GetFrameLevel() or 1) + 1)
	local pr, pg, pb, pa = 0.65, 0.25, 0.95, 0.95
	local function edgeBar(orient)
		local tex = border:CreateTexture(nil, "OVERLAY")
		tex:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
		tex:SetVertexColor(pr, pg, pb, pa)
		if orient == "top" then
			tex:SetHeight(4)
			tex:SetPoint("TOPLEFT", border, "TOPLEFT", 0, 0)
			tex:SetPoint("TOPRIGHT", border, "TOPRIGHT", 0, 0)
		elseif orient == "bottom" then
			tex:SetHeight(4)
			tex:SetPoint("BOTTOMLEFT", border, "BOTTOMLEFT", 0, 0)
			tex:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", 0, 0)
		elseif orient == "left" then
			tex:SetWidth(4)
			tex:SetPoint("TOPLEFT", border, "TOPLEFT", 0, 0)
			tex:SetPoint("BOTTOMLEFT", border, "BOTTOMLEFT", 0, 0)
		else -- right
			tex:SetWidth(4)
			tex:SetPoint("TOPRIGHT", border, "TOPRIGHT", 0, 0)
			tex:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", 0, 0)
		end
	end
	edgeBar("top")
	edgeBar("bottom")
	edgeBar("left")
	edgeBar("right")
	border:Hide()
	mainBtn.unlockBorder = border

	local icon = mainBtn:CreateTexture(nil, "ARTWORK")
	icon:SetSize(48, 48)
	icon:SetPoint("CENTER")
	icon:SetTexture("Interface\\Icons\\INV_Misc_Rune_01")
	mainBtn.icon = icon

	local text = mainBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	text:SetPoint("CENTER", 0, -2)
	text:SetText("|cffffffffTravel|r")
	mainBtn.text = text

	local hl = mainBtn:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(icon)
	hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	hl:SetBlendMode("ADD")

	mainBtn:SetScript("OnDragStart", function(self)
		if DB and DB.unlocked then
			self:StartMoving()
		end
	end)
	mainBtn:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, rp, x, y = self:GetPoint()
		DB.pos = { p, "UIParent", rp, x, y }
	end)
	mainBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	mainBtn:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			DB.unlocked = not DB.unlocked
			UpdateUnlockVisual()
			Print(DB.unlocked and "Frame unlocked (drag to move)." or "Frame locked.")
			return
		end
		-- While unlocked, left-click is for dragging; don't open the menu.
		if DB and DB.unlocked then
			return
		end
		ToggleMenu()
	end)
	mainBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("RetreatMenu")
		if DB and DB.unlocked then
			GameTooltip:AddLine("Unlocked — drag to move", 0.75, 0.45, 1.0)
			GameTooltip:AddLine("Right-click: lock position", 0.8, 0.8, 0.8)
		else
			GameTooltip:AddLine("Left-click: open travel list", 1, 1, 1)
			GameTooltip:AddLine("Right-click: unlock to drag", 0.8, 0.8, 0.8)
		end
		GameTooltip:Show()
	end)
	mainBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

	if DB.pos then
		mainBtn:ClearAllPoints()
		mainBtn:SetPoint(DB.pos[1], UIParent, DB.pos[3], DB.pos[4], DB.pos[5])
	else
		mainBtn:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
	end
	UpdateUnlockVisual()
	mainBtn:Show()
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		RetreatMenuDB = RetreatMenuDB or {}
		DB = RetreatMenuDB
		if DB.unlocked == nil then DB.unlocked = false end
	elseif event == "PLAYER_LOGIN" then
		if not DB then RetreatMenuDB = RetreatMenuDB or {}; DB = RetreatMenuDB end
		CreateMainButton()
		-- Warm item cache names
		GetItemInfo(ITEM_HEARTHSTONE)
		GetItemInfo(ITEM_TRAVEL_PERMIT)
		GetItemInfo(ITEM_FEL_GATEWAY)
		GetItemInfo(ITEM_SCROLL_STORMWIND)
		GetItemInfo(ITEM_SCROLL_ORGRIMMAR)
	end
end)

SLASH_RETREATMENU1 = "/retreatmenu"
SLASH_RETREATMENU2 = "/rmenu"
SlashCmdList["RETREATMENU"] = function(msg)
	msg = string.lower(msg or "")
	if msg == "reset" then
		DB.pos = nil
		if mainBtn then
			mainBtn:ClearAllPoints()
			mainBtn:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
		end
		Print("Position reset.")
	elseif msg == "scan" then
		local s, r, h = ScanSpellbook()
		Print(string.format("Stones: %d  Runes: %d  Hearth spells: %d", #s, #r, #h))
		for _, e in ipairs(s) do Print("  stone: " .. e.name) end
		for _, e in ipairs(r) do Print("  rune: " .. e.name) end
		for _, e in ipairs(h) do Print("  hearth: " .. e.name) end
	else
		ToggleMenu()
	end
end
