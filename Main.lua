local _, ns = ...

local frame, Keys, SIDES, TREMOR_SPELL_ID = ns.frame, ns.Keys, ns.SIDES, ns.TREMOR_SPELL_ID
local ApplyLocation, NotifyOptions, OnMouseDown, OnMouseUp = ns.ApplyLocation, ns.NotifyOptions, ns.OnMouseDown, ns.OnMouseUp
local ClearTotems, UpdateRegistration, OnCombatLog = ns.ClearTotems, ns.UpdateRegistration, ns.OnCombatLog

local function Init()
	ns.InitProfiles()
	ns.tremorName = GetSpellInfo(TREMOR_SPELL_ID) or ns.tremorName

	for _, side in ipairs(SIDES) do
		local host = side.frame

		host:SetFrameStrata("MEDIUM")
		host:SetFrameLevel(100)
		host:SetClampedToScreen(true)
		host:SetMovable(true)
		host:SetScript("OnMouseDown", OnMouseDown)
		host:SetScript("OnMouseUp", OnMouseUp)
		for _, slot in ipairs(side.slots) do
			-- the other icons drag the frame
			if slot ~= side.mainSlot then
				slot.host:SetScript("OnMouseDown", function(_, button) OnMouseDown(host, button) end)
				slot.host:SetScript("OnMouseUp", function(_, button) OnMouseUp(host, button) end)
				slot.host:SetFrameLevel(host:GetFrameLevel())
			end
			slot.cooldown:SetFrameLevel(slot.host:GetFrameLevel() + 1)
			slot.overlay:SetFrameLevel(slot.host:GetFrameLevel() + 2)
		end
		host:Hide()
		ApplyLocation(side)
	end
	frame:OnSettingsUpdated()

	frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:RegisterEvent("PLAYER_LOGOUT")
end

frame:SetScript("OnEvent", function(self, event, ...)
	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		OnCombatLog(...)
	elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
		ClearTotems()
		UpdateRegistration()
	elseif event == "PLAYER_LOGIN" then
		self:UnregisterEvent("PLAYER_LOGIN")
		Init()
	elseif event == "PLAYER_LOGOUT" then
		TremorWatchSettings = nil -- it only points into TremorWatchProfiles, which is what gets saved
	end
end)
-- the character is known at login, and its profile depends on it
frame:RegisterEvent("PLAYER_LOGIN")

SLASH_TREMORWATCH1 = "/tremorwatch"
SLASH_TREMORWATCH2 = "/tw"
SlashCmdList["TREMORWATCH"] = function(msg)
	if not TremorWatchSettings then return end
	local origMsg = msg or ""
	msg = strlower(strtrim(origMsg))
	local db = TremorWatchSettings.DB

	if msg == "test" or msg == "lock" or msg == "unlock" then
		if msg == "test" then
			db[Keys.Locked] = not db[Keys.Locked]
		else
			db[Keys.Locked] = msg == "lock"
		end
		frame:OnSettingsUpdated(Keys.Locked)
		NotifyOptions()
	elseif msg == "reset" then
		frame:ResetLocation()
	elseif strsub(msg, 1, 8) == "profile " then
		local name = strtrim(strsub(strtrim(origMsg), 9))
		if not frame:SetProfile(name) then
			print("TremorWatch: no profile \"" .. name .. "\". Profiles: " .. table.concat(frame:GetProfileNames(), ", "))
		end
	elseif frame.optionsFrame then
		-- called twice: the first call may open the panel on the wrong category
		InterfaceOptionsFrame_OpenToCategory(frame.optionsFrame)
		InterfaceOptionsFrame_OpenToCategory(frame.optionsFrame)
	end
end
