local _, ns = ...

local CC_MAX_AGE = 60 -- longer than most removable effects; older entries missed their removal

local Keys, ENEMY, internal = ns.Keys, ns.ENEMY, ns.internal

-- player auras (all ranks) a tremor totem pulse removes: its effect dispels the fear, charm and sleep mechanics
local REMOVABLE = {}
for _, id in ipairs({
	8122, 8124, 10888, 10890, 27610,                       -- Psychic Scream
	5782, 6213, 6215,                                      -- Fear
	5484, 17928, 50577,                                    -- Howl of Terror
	5246, 20511, 65930,                                    -- Intimidating Shout
	1513, 14326, 14327,                                    -- Scare Beast
	6358,                                                  -- Seduction
	1098, 11725, 11726, 61191,                             -- Enslave Demon
	2637, 18657, 18658,                                    -- Hibernate
	19386, 24132, 24133, 24335, 27068, 49011, 49012,       -- Wyvern Sting
}) do
	REMOVABLE[id] = true
end

local cc = {}           -- guid of an enemy -> { [spellId] = time applied } for removable auras
local ccCount = 0       -- number of auras in `cc`
internal.cc = cc

local function SetCC(guid, spellId, time)
	local auras = cc[guid]
	local had = auras and auras[spellId]
	if time then
		if not auras then
			auras = {}
			cc[guid] = auras
		end
		auras[spellId] = time
		if not had then ccCount = ccCount + 1 end
	elseif had then
		auras[spellId] = nil
		ccCount = ccCount - 1
		if not next(auras) then cc[guid] = nil end
	end
end

local function ClearUnitCC(guid)
	local auras = cc[guid]
	if not auras then return end
	for spellId in pairs(auras) do SetCC(guid, spellId, nil) end
end

local function ExpireCC(now)
	for guid, auras in pairs(cc) do
		for spellId, applied in pairs(auras) do
			if now - applied > CC_MAX_AGE then SetCC(guid, spellId, nil) end
		end
	end
end

-- only the enemy frame glows: an allied totem's pulse frees allies, not the enemies in `cc`
local function UpdateHighlight()
	local enabled = ccCount > 0 and TremorWatchSettings.DB[Keys.Highlight]
	for _, slot in ipairs(ENEMY.slots) do
		local on = enabled and slot.guid
		if on and not slot.highlight:IsShown() then
			slot.highlight:Show()
			slot.glow:Play()
			slot.countdown:SetTextColor(1, 0.3, 0.1)
		elseif not on and slot.highlight:IsShown() then
			slot.glow:Stop()
			slot.highlight:Hide()
			slot.countdown:SetTextColor(1, 1, 1)
		end
	end
end

ns.cc, ns.REMOVABLE, ns.SetCC, ns.ClearUnitCC, ns.ExpireCC, ns.UpdateHighlight = cc, REMOVABLE, SetCC, ClearUnitCC, ExpireCC, UpdateHighlight
ns.HasCC = function() return ccCount > 0 end
