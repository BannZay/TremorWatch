local Keys = TremorWatchMainFrame.Keys
local Sides = TremorWatchMainFrame.Sides

local function SetOption(info, value)
	local key = info.arg or info[#info]
	TremorWatchSettings.DB[key] = value
	TremorWatchMainFrame:OnSettingsUpdated(key)
end

local function GetOption(info)
	local key = info.arg or info[#info]
	return TremorWatchSettings.DB[key]
end

-- disabled while the option `enabledBy` is off (and, when given, while totems of that kind are not tracked or
-- their sounds are not allowed)
local function Disabled(enabledBy, track, allowSounds)
	return function()
		local db = TremorWatchSettings.DB
		return not db[enabledBy] or (track ~= nil and not db[track]) or (allowSounds ~= nil and not db[allowSounds])
	end
end

local LSM = LibStub("LibSharedMedia-3.0", true)

-- the sounds to choose from, "None" first (it sorts before any name)
local function SwellValues()
	local values = {}
	for _, preset in ipairs(TremorWatchMainFrame.SwellPresets) do values[preset[1]] = preset[2] end
	return values
end

local function SoundValues()
	local values = { [TremorWatchMainFrame.NoSound] = TremorWatchMainFrame.NoSound }
	for name in pairs(TremorWatchMainFrame.SoundList()) do values[name] = name end
	return values
end

-- "TremorWatchSound": the LSM30_Sound widget (a speaker button on every list row and next to the selection) with two
-- changes: the list widens to its longest name instead of the fixed 188 px, and the speakers play our sound names
-- (the list values are names, not file paths).
local SOUND_WIDGET = "TremorWatchSound"
local AceGUI = LibStub("AceGUI-3.0", true)
local baseSoundConstructor = AceGUI and AceGUI.WidgetRegistry["LSM30_Sound"]

local function RowSpeakerClick(this)
	local widget = this.frame.obj
	if widget and widget.type == SOUND_WIDGET then
		TremorWatchMainFrame:PreviewSound(this.frame.text:GetText())
	else
		this.originalClick(this)
	end
end

local function WidenSoundList(self)
	local list = self.dropdown
	if not list then return end
	local textWidth = 0
	for _, row in ipairs(list.contentRepo) do
		textWidth = max(textWidth, row.text:GetStringWidth())
		if not row.soundbutton.originalClick then
			row.soundbutton.originalClick = row.soundbutton:GetScript("OnClick")
			row.soundbutton:SetScript("OnClick", RowSpeakerClick)
		end
	end
	-- check mark + speaker + gaps, then the 14 px borders and the scrollbar when the list scrolls
	local inner = max(160, ceil(textWidth) + 40)
	local scrolls = list.slider:IsShown()
	list.scrollframe:SetWidth(inner - (scrolls and 14 or 0))
	list.contentframe:SetWidth(list.scrollframe:GetWidth())
	list:SetWidth(inner + 28)
end

if baseSoundConstructor then
	AceGUI:RegisterWidgetType(SOUND_WIDGET, function()
		local widget = baseSoundConstructor()
		widget.type = SOUND_WIDGET
		local toggle = widget.ToggleDrop -- takes the drop button, whose .obj is the widget
		widget.ToggleDrop = function(this)
			toggle(this)
			WidenSoundList(this.obj)
		end
		widget.frame.dropButton:SetScript("OnClick", widget.ToggleDrop)
		widget.soundbutton:SetScript("OnClick", function(this)
			TremorWatchMainFrame:PreviewSound(this.obj.value)
		end)
		return widget
	end, 1)
end

-- A sound dropdown that plays a sound when its speaker is clicked, in the list as well as on the selection.
local function AddSoundSelect(args, key, name, order, track, allowSounds)
	if not LSM then return end
	args[key] = { type = "select", name = name, values = SoundValues, width = "full", order = order,
		dialogControl = baseSoundConstructor and SOUND_WIDGET or nil,
		disabled = Disabled(track, nil, allowSounds) }
end

-- The main panel holds what is shared by both frames.
local options =
{
	type = "group",
	name = "TremorWatch",
	get = GetOption,
	set = SetOption,
	args =
	{
		[Keys.Locked] = { type = "execute", order = 1,
			name = function() return TremorWatchSettings.DB[Keys.Locked] and "Unlock frame" or "Lock frame" end,
			desc = "Unlocked, a fake totem is shown and the frame can be dragged",
			func = function()
				local db = TremorWatchSettings.DB
				db[Keys.Locked] = not db[Keys.Locked]
				TremorWatchMainFrame:OnSettingsUpdated(Keys.Locked)
			end },
		resetPosition = { type = "execute", name = "Reset positions", order = 2,
			func = function() TremorWatchMainFrame:ResetLocation() end },
		[Keys.ArenaOnly] = { type = "toggle", name = "Show on arena only", order = 3,
			desc = "Ignore tremor totems outside of arenas (the combat log is not read there)" },
		[Keys.StaleTimeout] = { type = "range", name = "Forget unseen totems", min = 10, max = 300, step = 5,
			order = 4,
			desc = "Outside arenas, drop a totem after this many seconds without any sign of it or its shaman" },
		[Keys.Latency] = { type = "toggle", name = "Latency compensation", order = 5,
			desc = "Time pulses from the server's clock: shift them earlier by half your latency" },
		[Keys.TestSounds] = { type = "toggle", name = "Debug sounds", order = 6,
			desc = "The fake totems shown while the frames are unlocked also play their spawn and pulse sounds" },
	}
}

-- The enemy and allied panels hold the same settings, each with its own values: each kind of totem has its own
-- frame, which is positioned (by unlocking) and sized separately.
-- a color picker for a { r, g, b } setting
local function ColorOption(key, name, order, disabled, desc)
	return { type = "color", name = name, order = order, desc = desc, disabled = disabled,
		get = function()
			local c = TremorWatchSettings.DB[key]
			return c.r, c.g, c.b
		end,
		set = function(_, r, g, b)
			TremorWatchSettings.DB[key] = { r = r, g = g, b = b }
			TremorWatchMainFrame:OnSettingsUpdated(key)
		end }
end

-- the side's Tremor Totem nameplates: a health bar color, and an icon with the pulse counter on them; all off while
-- the side is not tracked
local function PlateOptions(side, who)
	local icon, track = side.PlateIcon, side.Track
	local IconOff = Disabled(track, icon)
	local function NoPulseTicks()
		local db = TremorWatchSettings.DB
		return IconOff() or not db[side.PlateCountdown]
	end
	return
	{
		type = "group", inline = true, name = "Nameplate", order = 6,
		args =
		{
			[side.PlateRecolor] = { type = "toggle", name = "Recolor Nameplate", order = 1,
				desc = "Paint the health bar of " .. who .. " Tremor Totem nameplates (works without the icon too)",
				disabled = Disabled(track) },
			[side.PlateBarColor] = ColorOption(side.PlateBarColor, "Health bar color", 2, Disabled(track, side.PlateRecolor)),
			[side.PlateHideName] = { type = "toggle", name = "Hide name", order = 2.2,
				desc = "Hide the name text on " .. who .. " Tremor Totem nameplates",
				disabled = Disabled(track) },
			iconHeader = { type = "header", name = "Icon", order = 2.5 },
			[icon] = { type = "toggle", name = "Add Icon", order = 3, width = "full",
				desc = "A large Tremor icon on the totem's nameplate. It does not take the mouse: hovering or clicking it reaches the nameplate, so a mouseover macro works on it",
				disabled = Disabled(track) },
			[side.PlateStyle] = { type = "select", name = "Style", order = 4, style = "dropdown",
				values = { square = "Square, with swirl", round = "Round, with ring" },
				desc = "Square looks like the TremorWatch frame and shows the pulse swirl; round has a colored ring and no swirl",
				disabled = IconOff },
			[side.PlateSize] = { type = "range", name = "Icon size", min = 16, max = 128, step = 1, order = 5,
				disabled = IconOff },
			[side.PlateOffsetY] = { type = "range", name = "Vertical offset", softMin = -60, softMax = 60, step = 1, order = 6,
				desc = "Keep it near 0 so the icon stays over the nameplate's click area",
				disabled = IconOff },
			[side.PlateOffsetX] = { type = "range", name = "Horizontal offset", softMin = -100, softMax = 100, step = 1, order = 6.5,
				desc = "Keep it near 0 so the icon stays over the nameplate's click area",
				disabled = IconOff },
			[side.PlateGlow] = { type = "toggle", name = "Pulsing glow", order = 7, disabled = IconOff },
			[side.PlateColor] = ColorOption(side.PlateColor, "Glow color", 8, IconOff,
				"Color of the glow and of the round style's ring"),
			pulseHeader = { type = "header", name = "Pulse counter", order = 10 },
			[side.PlateCountdown] = { type = "toggle", name = "Pulse ticks", order = 11, width = "full",
				desc = "Count down to the next pulse on the icon, and flash when it pulses. Needs the totem's summon in the combat log; a plate gets no countdown while several totems of its side can not be told apart (targeting or hovering one tells them apart).",
				disabled = IconOff },
			[side.PlateTicks] = { type = "select", name = "Counter", order = 12, style = "dropdown",
				values = { swipe = "Swipe", rings = "Growing border" },
				desc = "Swipe: the cooldown swirl and countdown text over the icon (swirl in the square style only). Growing border: borders appear one by one around the icon as the pulse comes closer, then the pulse flashes",
				disabled = NoPulseTicks },
			[side.PlateRingColor] = ColorOption(side.PlateRingColor, "Border color", 13,
				function() return NoPulseTicks() or TremorWatchSettings.DB[side.PlateTicks] ~= "rings" end,
				"Color of the growing border"),
		},
	}
end

local function SideOptions(side, title, enemy)
	local track = side.Track
	local who = enemy and "enemy" or "allied"
	-- every sound of the side: spawn and destroyed, then the pulse sounds under their own header
	local sound =
	{
		[side.AllowSounds] = { type = "toggle", name = "Enable", order = 0, width = "full",
			disabled = Disabled(track),
			desc = "Off silences everything on this frame: spawn, pulse and destroyed sounds, whatever their own settings" },
		pulseHeader = { type = "header", name = "Pulses", order = 1.9 },
	}
	AddSoundSelect(sound, side.SpawnSound, "Spawn sound", 1, track, side.AllowSounds)
	AddSoundSelect(sound, side.DestroySoundName, "Destroyed sound", 1.5, track, side.AllowSounds)
	local function NotSwell() return TremorWatchSettings.DB[side.SoundMode] ~= "swell" end
	local function Swell() return TremorWatchSettings.DB[side.SoundMode] == "swell" end
	sound[side.SoundMode] = { type = "select", name = "Sound mode", order = 2, width = "full", style = "dropdown",
		values = { simple = "Simple", swell = "Swell" },
		desc = "Simple: the pulse sound plays on each pulse. Swell: a rising run of short sounds in the second before each pulse, "
			.. "peaking on it; it stops at once when the totem is destroyed",
		disabled = Disabled(track, nil, side.AllowSounds) }
	AddSoundSelect(sound, side.Sound, "Pulse sound", 3, track, side.AllowSounds)
	if sound[side.Sound] then sound[side.Sound].hidden = Swell end
	sound[side.SwellPreset] = { type = "select", name = "Swell sound", order = 3, width = "full", style = "dropdown",
		values = SwellValues, hidden = NotSwell, disabled = Disabled(track, nil, side.AllowSounds) }
	sound[side.SwellLength] = { type = "range", name = "Swell length", order = 3.2, width = "full",
		min = TremorWatchMainFrame.SwellStep, max = TremorWatchMainFrame.MaxSwellLength, step = TremorWatchMainFrame.SwellStep,
		hidden = NotSwell, disabled = Disabled(track, nil, side.AllowSounds),
		desc = "How many seconds before each pulse the swell starts (up to the whole 3 s between pulses). "
			.. "A shorter swell starts higher and louder; it always ends on the pulse" }
	sound.previewSwell = { type = "execute", name = "Preview swell", order = 3.5, hidden = NotSwell,
		func = function() TremorWatchMainFrame:PreviewSwell(side) end,
		disabled = Disabled(track, nil, side.AllowSounds) }
	if enemy then
		sound.previewAlert = { type = "execute", name = "Preview alert", order = 3.6, hidden = NotSwell,
			desc = "The louder swell played while an enemy has a fear, charm or sleep effect the next pulse will remove",
			func = function() TremorWatchMainFrame:PreviewSwell(side, true) end,
			disabled = Disabled(track, nil, side.AllowSounds) }
	end

	local frame =
	{
		[side.MaxIcons] = { type = "range", name = "Max icons", min = 1, max = 3, step = 1, order = 1,
			desc = "Totems shown at once, each with its own icon; more are counted as +N on the last icon" },
		[side.IconSpacing] = { type = "range", name = "Icon spacing", min = 0, max = 50, step = 1, order = 2 },
		[side.Size] = { type = "range", name = "Icon size", min = 10, max = 500, step = 1, order = 3 },
		[side.Alpha] = { type = "range", name = "Alpha", min = 0.05, max = 1, step = 0.05, order = 4 },
	}

	-- what the icon shows
	local icon =
	{
		[side.ShowPulses] = { type = "toggle", name = "Show pulses", order = 2,
			desc = "Swirl counting down to the next pulse" },
		[side.Countdown] = { type = "toggle", name = "Countdown text", order = 3,
			desc = "Seconds to the next pulse on the icon" },
		[side.DestroyFlash] = { type = "toggle", name = "Flash", order = 5,
			desc = "Show a grey icon for a moment when the totem is destroyed" },
		[side.Tint] = { type = "toggle", name = "Tint", order = 6,
			desc = "Color the icon of " .. who .. " totems " .. (enemy and "red" or "green") },
	}
	if enemy then
		icon[side.Highlight] = { type = "toggle", name = "Highlight removals", order = 4,
			desc = "Glow while an enemy has a fear, charm or sleep effect the next pulse will remove" }
	end
	-- the frame and icon settings only matter while the icon is shown
	for _, options in ipairs({ frame, icon }) do
		for _, option in pairs(options) do option.disabled = Disabled(track, side.ShowIcon) end
	end
	icon[side.ShowIcon] = { type = "toggle", name = "Show", order = 1, width = "full",
		disabled = Disabled(track),
		desc = "Off hides this frame's icons; the totems are still tracked for sounds and nameplates" }

	return
	{
		type = "group",
		name = title,
		get = GetOption,
		set = SetOption,
		args =
		{
			[track] = { type = "toggle", name = "Track " .. who .. " totems", order = 1, width = "full",
				desc = "Show tremor totems of " .. (enemy and "enemies" or "allies") },
			display = { type = "group", inline = true, name = "Frame", order = 2, args = frame },
			icon = { type = "group", inline = true, name = "Icon", order = 3, args = icon },
			sound = { type = "group", inline = true, name = "Sound", order = 4, args = sound },
			nameplate = PlateOptions(side, who),
		},
	}
end

-- Profiles: each character uses one profile (by default "Default"), shared by any number of characters.
local function ProfileValues(includeCurrent)
	return function()
		local values = {}
		for _, name in ipairs(TremorWatchMainFrame:GetProfileNames()) do
			if includeCurrent or name ~= TremorWatchMainFrame:GetProfile() then values[name] = name end
		end
		return values
	end
end

local profileOptions =
{
	type = "group",
	name = "Profiles",
	args =
	{
		desc = { type = "description", order = 1, fontSize = "medium",
			name = "Each character uses one profile. Characters that use the same profile share all settings and positions." },
		current = { type = "select", name = "Current profile", order = 2, values = ProfileValues(true),
			get = function() return TremorWatchMainFrame:GetProfile() end,
			set = function(_, name) TremorWatchMainFrame:SetProfile(name) end },
		new = { type = "input", name = "New profile", order = 3,
			desc = "Type a name and press Enter: creates a profile with default settings and switches to it",
			get = function() return "" end,
			set = function(_, name) TremorWatchMainFrame:CreateProfile(name) end },
		copy = { type = "select", name = "Copy from", order = 4, values = ProfileValues(false),
			desc = "Replace the settings of the current profile with those of another profile",
			confirm = true, confirmText = "Replace the settings of the current profile?",
			get = function() return nil end,
			set = function(_, name) TremorWatchMainFrame:CopyProfile(name) end },
		delete = { type = "select", name = "Delete profile", order = 5, values = ProfileValues(false),
			desc = "Delete a profile that is not in use by this character",
			confirm = true, confirmText = "Delete this profile?",
			get = function() return nil end,
			set = function(_, name) TremorWatchMainFrame:DeleteProfile(name) end },
		reset = { type = "execute", name = "Reset profile", order = 6,
			desc = "Set the current profile back to the default settings",
			confirm = true, confirmText = "Reset all settings of the current profile?",
			func = function() TremorWatchMainFrame:ResetProfile() end },
	},
}

local registry = LibStub("AceConfig-3.0")
local dialog = LibStub("AceConfigDialog-3.0")

registry:RegisterOptionsTable("TremorWatch", options)
TremorWatchMainFrame.optionsFrame = dialog:AddToBlizOptions("TremorWatch", "TremorWatch")

registry:RegisterOptionsTable("TremorWatch Enemy", SideOptions(Sides.enemy, "Enemy totems", true))
dialog:AddToBlizOptions("TremorWatch Enemy", "Enemy totems", "TremorWatch")

registry:RegisterOptionsTable("TremorWatch Ally", SideOptions(Sides.ally, "Allied totems", false))
dialog:AddToBlizOptions("TremorWatch Ally", "Allied totems", "TremorWatch")

registry:RegisterOptionsTable("TremorWatch Profiles", profileOptions)
dialog:AddToBlizOptions("TremorWatch Profiles", "Profiles", "TremorWatch")
