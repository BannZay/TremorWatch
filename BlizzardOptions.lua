local Keys = 
{
	ShowPulses = "showPulses",
	Size = "size",
	Alpha = "alpha",
	Delay = "Delay",
	TestMode = "testMode"
}

local function SetOption(info, value)
	local key = info.arg or info[#info]
	TremorWatchSettings.DB[key] = value
	TremorWatchMainFrame:OnSettingsUpdated(key)
end

local function GetOption(info)
	local key = info.arg or info[#info]
	return TremorWatchSettings.DB[key]
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
	
	options.args[Keys.TestMode] = 
	{
		type = "toggle",
		name = "Test mode",
		desc = "",
		order = 1,
	}
	
	options.args[Keys.ShowPulses] = 
	{
		type = "toggle",
		name = "Show pulses",
		desc = "Show next tremor totem pulse",
		order = 2,
	}
	
	options.args[Keys.Size] = 
	{
		type = "range",
		name = "Frame scale",
		min = 10,
		max = 500,
		step =1,
		order = 3,
	}
	
	options.args[Keys.Alpha] = 
	{
		type = "range",
		name = "Frame alpha",
		min = 0,
		max = 1,
		step =0.05,
		order = 4,
	}
	
	options.args[Keys.Delay] = 
	{
		type = "range",
		name = "Animation delay",
		min = 0,
		max = 2,
		step =0.05,
		order = 5,
	}
	return options
end

LibStub("AceConfig-3.0"):RegisterOptionsTable("TremorWatch", BuildBlizzardOptions())
LibStub("AceConfigDialog-3.0"):AddToBlizOptions("TremorWatch", "TremorWatch")