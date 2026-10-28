local _, ns = ...

local sort = table.sort
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local frame, internal, ENEMY = ns.frame, ns.internal, ns.ENEMY
local NO_SOUND, DEFAULT_SOUND_NAME, DEFAULT_SOUND_PATH = ns.NO_SOUND, ns.DEFAULT_SOUND_NAME, ns.DEFAULT_SOUND_PATH
local DESTROY_SOUND_NAME, DESTROY_SOUND_PATH = ns.DESTROY_SOUND_NAME, ns.DESTROY_SOUND_PATH

if LSM then
	LSM:Register("sound", DEFAULT_SOUND_NAME, DEFAULT_SOUND_PATH)
	LSM:Register("sound", DESTROY_SOUND_NAME, DESTROY_SOUND_PATH)
	-- synthesized sounds (tools/gen_sounds.py)
	for name, file in pairs({
		["tick - TremorWatch"] = "tick", ["blip - TremorWatch"] = "blip",
		["rise - TremorWatch"] = "spawn-rise", ["ding-dong - TremorWatch"] = "spawn-ding",
		["shatter - TremorWatch"] = "shatter", ["fall - TremorWatch"] = "fall",
	}) do
		LSM:Register("sound", name, "Interface\\AddOns\\TremorWatch\\Sounds\\" .. file .. ".wav")
	end
	-- voice lines (Sounds/voice)
	for name, file in pairs({
		["Tremor up - TremorWatch"] = "tremor-up", ["Tremor up (fast) - TremorWatch"] = "tremor-up-fast",
		["Tremor down - TremorWatch"] = "tremor-down", ["Tremor down (fast) - TremorWatch"] = "tremor-down-fast",
		["Friendly tremor up (fast) - TremorWatch"] = "friendly-tremor-up-fast",
		["Friendly tremor down (fast) - TremorWatch"] = "friendly-tremor-down-fast",
	}) do
		LSM:Register("sound", name, "Interface\\AddOns\\TremorWatch\\Sounds\\voice\\" .. file .. ".wav")
	end
end

local function HasSound(name)
	return name ~= nil and name ~= NO_SOUND
end

-- Other addons register sounds as "<addon> <name>" ("CombatTracking Bell"); sounds are listed and saved as
-- "<name> - <addon>" ("Bell - CombatTracking") instead. The addon is recognized by the installed addons' names.
local addonNames
local function DisplaySoundName(name)
	if not addonNames then
		addonNames = {}
		for i = 1, GetNumAddOns() do addonNames[#addonNames + 1] = (GetAddOnInfo(i)) end
		sort(addonNames, function(a, b) return #a > #b end) -- the longest match wins
	end
	for _, addon in ipairs(addonNames) do
		local n = #addon
		if strlower(strsub(name, 1, n)) == strlower(addon) then
			local rest = strmatch(strsub(name, n + 1), "^[%s:_%-]+(.+)$")
			if rest then return rest .. " - " .. addon end
		end
	end
	return name
end

-- display name -> path of all sounds, without the library's own "None"
local function SoundList()
	local list = {}
	if LSM then
		for name, path in pairs(LSM:HashTable("sound")) do
			if name ~= "None" then list[DisplaySoundName(name)] = path end
		end
	end
	return list
end
frame.SoundList = SoundList

local function FindSound(name)
	return LSM and (LSM:Fetch("sound", name, true) or SoundList()[name])
end

-- resolved on every play so sounds registered after load are found
local function PlayMedia(name, fallback)
	if not HasSound(name) then return end
	local path = FindSound(name)
	path = path or fallback
	if path then internal.PlaySound(path) end
end

function internal.PlayPulseSound(side)
	PlayMedia(TremorWatchSettings.DB[(side or ENEMY).Sound], DEFAULT_SOUND_PATH)
end

local SwellTiming, SWELL_PRESETS = ns.SwellTiming, ns.SWELL_PRESETS

-- step 1..steps of the side's swell preset (tools/gen_sounds.py), a rising run of short sounds; the alert
-- version is louder (an enemy under a fear, charm or sleep effect that the pulse will remove)
function internal.PlaySwellStep(side, step, alert)
	local preset = TremorWatchSettings.DB[side.SwellPreset]
	local known
	for _, p in ipairs(SWELL_PRESETS) do known = known or p[1] == preset end
	preset = known and preset or SWELL_PRESETS[1][1]
	internal.PlaySound("Interface\\AddOns\\TremorWatch\\Sounds\\swell\\" .. preset .. "\\" .. (alert and "alert-" or "") .. step .. ".wav")
end

-- plays the whole swell of a side for the options panel
local preview = CreateFrame("Frame")
preview:Hide()
preview:SetScript("OnUpdate", function(self)
	local steps, stepLength, skip = self.steps, self.stepLength, self.skip
	local due = self.start + (self.step - 1 - skip) * stepLength
	while self.step <= steps and GetTime() >= due do
		internal.PlaySwellStep(self.side, self.step, self.alert)
		self.step = self.step + 1
		due = self.start + (self.step - 1 - skip) * stepLength
	end
	if self.step > steps then self:Hide() end
end)

function frame:PreviewSwell(side, alert)
	local steps, stepLength, skip = SwellTiming(side) -- fixed for the whole preview, even if the setting changes meanwhile
	preview.side, preview.alert, preview.start = side, alert, GetTime()
	preview.steps, preview.stepLength, preview.skip, preview.step = steps, stepLength, skip, skip + 1
	preview:Show()
end

-- a changed setting ends a running preview (sounds already started play out, but no further step starts)
function frame:StopSwellPreview()
	preview:Hide()
end

function internal.PlaySpawnSound(side)
	PlayMedia(TremorWatchSettings.DB[(side or ENEMY).SpawnSound])
end

function internal.PlayDestroySound(side)
	PlayMedia(TremorWatchSettings.DB[(side or ENEMY).DestroySoundName], DESTROY_SOUND_PATH)
end

ns.LSM, ns.HasSound, ns.DisplaySoundName, ns.PlayMedia = LSM, HasSound, DisplaySoundName, PlayMedia
