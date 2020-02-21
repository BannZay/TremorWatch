TremorWatchMainFrame = CreateFrame("Frame", "TremorWatchMainFrame",UIParent)
TremorWatchMainFrame.cooldown = CreateFrame("Cooldown", nil, TremorWatchMainFrame, "CooldownFrameTemplate")
TremorWatchSettings = TremorWatchSettings or { Location = {Point = "Top", RelativeTo = nil, RelativePoint = "Top", XOfs = 0, YOfs = 0}, Size = 40, Delay = 0.4}

local function _wait(delay, func, ...)
	if(type(delay)~="number" or type(func)~="function") then
		return false;
	end

	if (delay <= 0) then
		func(...)
	else
		if(waitFrame == nil) then
			waitTable = {}
			waitFrame = CreateFrame("Frame","WaitFrame", UIParent);
			waitFrame:SetScript("onUpdate",function (self,elapse)
				local count = #waitTable;
				local i = 1;
				while(i<=count) do
					local waitRecord = tremove(waitTable,i);
					local d = tremove(waitRecord,1);
					local f = tremove(waitRecord,1);
					local p = tremove(waitRecord,1);
					if(d>elapse) then
					  tinsert(waitTable,i,{d-elapse,f,p});
					  i = i + 1;
					else
					  count = count - 1;
					  f(unpack(p));
					end
				end
			end);
		end
		
		tinsert(waitTable,{delay,func,{...}});
		return true;
	end
end

local function ScheduleResetCooldown(guid)
	if (TremorWatchMainFrame.GUID == guid or guid == -1 and not TremorWatchMainFrame:IsLocked()) then
		TremorWatchMainFrame.cooldown:SetCooldown(GetTime() - TremorWatchSettings.Delay, 3)
		_wait(3, ScheduleResetCooldown, guid)
	end
end

local function COMBAT_LOG_EVENT_UNFILTERED(timestamp, eventType, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, destId)
	if not TremorWatchMainFrame:IsScanEnabled() then return end
	
	local isHostile = bit.band(destFlags, COMBATLOG_OBJECT_REACTION_HOSTILE) == COMBATLOG_OBJECT_REACTION_HOSTILE
	if not isHostile then return end
	
	local tremorSpellId = 8143
	name, rank, icon, castTime, minRange, maxRange, spellId = GetSpellInfo(tremorSpellId)
	
	if destName == name then
		if eventType == "UNIT_DIED" then
			TremorWatchMainFrame:Hide()
		elseif eventType == "SPELL_SUMMON" then
			TremorWatchMainFrame:Show()
			TremorWatchMainFrame.GUID = destGUID
			_wait(TremorWatchSettings.Delay, ScheduleResetCooldown, destGUID)
		end
	end	
end

local function OnMouseDown(self, button)
	if button == "LeftButton" then
		self:StartMoving()
	end
end

local function OnMouseUp(self, button)
	if button == "LeftButton" then
		self:StopMovingOrSizing()
		
		Point, RelativeTo, RelativePoint, XOfs, YOfs = self:GetPoint()
		TremorWatchSettings.Location.Point = Point
		TremorWatchSettings.Location.RelativeTo = RelativeTo
		TremorWatchSettings.Location.RelativePoint = RelativePoint
		TremorWatchSettings.Location.XOfs = XOfs
		TremorWatchSettings.Location.YOfs = YOfs
	end
end

local function Init()
	TremorWatchMainFrame:SetFrameStrata('MEDIUM')
	TremorWatchMainFrame:SetFrameLevel(100)
	TremorWatchMainFrame:SetPoint(TremorWatchSettings.Location.Point, TremorWatchSettings.Location.RelativeTo,
	TremorWatchSettings.Location.RelativePoint, TremorWatchSettings.Location.XOfs, TremorWatchSettings.Location.YOfs)
	TremorWatchMainFrame:SetSize(TremorWatchSettings.Size, TremorWatchSettings.Size)
	TremorWatchMainFrame:SetScript("OnMouseDown", OnMouseDown)
	TremorWatchMainFrame:SetScript("OnMouseUp", OnMouseUp)
	TremorWatchMainFrame:SetClampedToScreen(true)
	TremorWatchMainFrame.t = TremorWatchMainFrame:CreateTexture(nil,BORDER)
	TremorWatchMainFrame.t:SetTexture("Interface\\Icons\\spell_nature_tremortotem")
	TremorWatchMainFrame.t:SetAllPoints()
	TremorWatchMainFrame:SetAlpha(0.8)
	TremorWatchMainFrame:SetMovable(true)
	TremorWatchMainFrame:Hide()
	TremorWatchMainFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	TremorWatchMainFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	TremorWatchMainFrame.cooldown:SetReverse(false)
end

local eventHandlers =
{
	["VARIABLES_LOADED"] = Init,
	["COMBAT_LOG_EVENT_UNFILTERED"] = function(event, ...) COMBAT_LOG_EVENT_UNFILTERED(...) end,
	["ZONE_CHANGED_NEW_AREA"] = function() TremorWatchMainFrame:Hide() end,
}
TremorWatchMainFrame:RegisterEvent("VARIABLES_LOADED")
TremorWatchMainFrame:SetScript("OnEvent", function(self, ...) eventHandlers[event](...) end)

function TremorWatchMainFrame:IsLocked()
	return not TremorWatchMainFrame:IsMouseEnabled()
end

function TremorWatchMainFrame:SetLocked(locked)
	TremorWatchMainFrame:EnableMouse(not locked)
	
	if locked then
		TremorWatchMainFrame:Hide()
	else
		TremorWatchMainFrame:Show()
		ScheduleResetCooldown(-1)
	end
end

function TremorWatchMainFrame:ResizeAndSave(size)
	TremorWatchMainFrame:SetSize(size, size)
	TremorWatchSettings.Size = size
end

function TremorWatchMainFrame:IsScanEnabled()
	return not TremorWatchMainFrame:IsMouseEnabled()
end
