local ScaleSettingKey = "scale"
local AlphaSettingKey = "alpha"
local LockSettingKey = "lock"
local DelaySettingKey = "Delay"

local function SetOption(info, value)
	local key = info.arg or info[#info]
	if key == LockSettingKey then
		TremorWatchMainFrame:SetLocked(value)
	elseif key == ScaleSettingKey then
		TremorWatchMainFrame:ResizeAndSave(value)
	elseif key == AlphaSettingKey then
		TremorWatchMainFrame:SetAlpha(value)
	else
		TremorWatchSettings[key] = value
	end
end

local function GetOption(info)
	local key = info.arg or info[#info]
	if key == LockSettingKey then
		return TremorWatchMainFrame:IsLocked()
	elseif key == ScaleSettingKey then
		return TremorWatchMainFrame:GetSize()
	elseif key == AlphaSettingKey then
		return TremorWatchMainFrame:GetAlpha()
	else
		return TremorWatchSettings[key]
	end
end

local function BuildBlizzardOptions()
	local options = 
	{
		type = "group",
		name = "TremorWatch",
		plugins = {},
		get = GetOption,
		set = SetOption,
		args = {}
	}
	
	options.args[LockSettingKey] = 
	{
		type = "toggle",
		name = "Lock",
		desc = "Lock frame",
		order = 1,
	}
	
	options.args[ScaleSettingKey] = 
	{
		type = "range",
		name = "Frame scale",
		min = 10,
		max = 300,
		step =1,
		order = 2,
	}
	
	options.args[AlphaSettingKey] = 
	{
		type = "range",
		name = "Frame alpha",
		min = 0,
		max = 1,
		step =0.05,
		order = 3,
	}
	
	options.args[DelaySettingKey] = 
	{
		type = "range",
		name = "Animation delay",
		min = 0,
		max = 2,
		step =0.05,
		order = 4,
	}
	return options
end

LibStub("AceConfig-3.0"):RegisterOptionsTable("TremorWatch", BuildBlizzardOptions())
LibStub("AceConfigDialog-3.0"):AddToBlizOptions("TremorWatch", "TremorWatch")