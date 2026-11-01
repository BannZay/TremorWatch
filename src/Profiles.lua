local _, ns = ...

local sort = table.sort
local frame, Keys, SIDES, defaults = ns.frame, ns.Keys, ns.SIDES, ns.defaults
local LSM, NO_SOUND, DEFAULT_SOUND_NAME, DESTROY_SOUND_NAME = ns.LSM, ns.NO_SOUND, ns.DEFAULT_SOUND_NAME, ns.DESTROY_SOUND_NAME
local CopyDefaults, ApplyLocation, DisplaySoundName, PlayMedia = ns.CopyDefaults, ns.ApplyLocation, ns.DisplaySoundName, ns.PlayMedia

-- Profiles. `TremorWatchProfiles` (saved) = { Profiles = { [name] = settings }, Chars = { ["Name-Realm"] = name } };
-- `TremorWatchSettings` is only the settings table of the profile in use.
local DEFAULT_PROFILE = "Default"
local profiles, currentProfile

local function DeepCopy(src)
	if type(src) ~= "table" then return src end
	local dst = {}
	for k, v in pairs(src) do dst[k] = DeepCopy(v) end
	return dst
end

-- sound names of earlier versions
local OLD_SOUND_NAMES =
{
	["TremorWatch mallet"] = DEFAULT_SOUND_NAME, ["TremorWatch destroyed"] = DESTROY_SOUND_NAME,
	["TremorWatch tick"] = "tick - TremorWatch", ["TremorWatch blip"] = "blip - TremorWatch",
	["TremorWatch rise"] = "rise - TremorWatch", ["TremorWatch ding-dong"] = "ding-dong - TremorWatch",
	["TremorWatch shatter"] = "shatter - TremorWatch", ["TremorWatch fall"] = "fall - TremorWatch",
}
local SOUND_KEYS = { Keys.Sound, Keys.SpawnSound, Keys.DestroySoundName,
	Keys.AllySound, Keys.AllySpawnSound, Keys.AllyDestroySoundName }

-- the on/off toggles of sounds were replaced by choosing no sound
local function MigrateSound(db, toggleKey, soundKey)
	if db[toggleKey] == false then db[soundKey] = NO_SOUND end
	db[toggleKey] = nil
end

-- fills in defaults and drops keys of older versions
local function NormalizeSettings(settings)
	local db = settings.DB
	if type(db) == "table" then
		MigrateSound(db, "playSounds", Keys.Sound)
		MigrateSound(db, "destroySound", Keys.DestroySoundName)
		MigrateSound(db, "allyPlaySounds", Keys.AllySound)
		MigrateSound(db, "allyDestroySound", Keys.AllyDestroySoundName)
	end
	if type(db) == "table" then
		if db.swell then db[Keys.SoundMode] = "swell" end
		if db.allySwell then db[Keys.AllySoundMode] = "swell" end
		db.swell, db.allySwell = nil, nil
		-- the rising sweep swell was replaced by the water drops
		if db[Keys.SwellPreset] == "sweep" then db[Keys.SwellPreset] = "drops" end
		if db[Keys.AllySwellPreset] == "sweep" then db[Keys.AllySwellPreset] = "drops" end
	end
	CopyDefaults(settings, defaults)
	for _, key in ipairs(SOUND_KEYS) do
		local name = settings.DB[key]
		settings.DB[key] = OLD_SOUND_NAMES[name] or (LSM and LSM:Fetch("sound", name, true) and DisplaySoundName(name)) or name
	end
	settings.DB.testMode = nil -- merged into the lock
	settings.DB.fearOnly = nil -- replaced by the highlight
	for _, side in ipairs(SIDES) do
		local loc = settings[side.Location]
		if type(loc.RelativeTo) ~= "string" then loc.RelativeTo = "UIParent" end
	end
	return settings
end

local function CharKey()
	return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function NotifyOptions()
	local registry = LibStub and LibStub("AceConfigRegistry-3.0", true)
	if registry then
		for _, name in ipairs({ "TremorWatch", "TremorWatch Enemy", "TremorWatch Ally", "TremorWatch Profiles" }) do
			registry:NotifyChange(name)
		end
	end
end

ns.NotifyOptions = NotifyOptions

local function ApplyProfile()
	for _, side in ipairs(SIDES) do ApplyLocation(side) end
	frame:OnSettingsUpdated()
	NotifyOptions()
end

-- plays a sound for the options panel
function frame:PreviewSound(name)
	PlayMedia(name)
end

function frame:GetProfileNames()
	local names = {}
	for name in pairs(profiles.Profiles) do names[#names + 1] = name end
	sort(names)
	return names
end

function frame:GetProfile()
	return currentProfile
end

-- makes `name` the profile of this character
function frame:SetProfile(name)
	local settings = profiles.Profiles[name]
	if not settings then return false end
	currentProfile = name
	profiles.Chars[CharKey()] = name
	TremorWatchSettings = NormalizeSettings(settings)
	ApplyProfile()
	return true
end

-- a new profile starts with the defaults; returns false for an empty or taken name
function frame:CreateProfile(name)
	name = strtrim(name or "")
	if name == "" or profiles.Profiles[name] then return false end
	profiles.Profiles[name] = {}
	return self:SetProfile(name)
end

-- replaces the settings of the current profile with those of `name` (the lock state stays)
function frame:CopyProfile(name)
	local from = profiles.Profiles[name]
	if not from or name == currentProfile then return false end
	local locked = TremorWatchSettings.DB[Keys.Locked]
	wipe(TremorWatchSettings)
	for k, v in pairs(DeepCopy(from)) do TremorWatchSettings[k] = v end
	NormalizeSettings(TremorWatchSettings)
	TremorWatchSettings.DB[Keys.Locked] = locked
	ApplyProfile()
	return true
end

-- the profile in use cannot be deleted
function frame:DeleteProfile(name)
	if not profiles.Profiles[name] or name == currentProfile then return false end
	profiles.Profiles[name] = nil
	NotifyOptions()
	return true
end

function frame:ResetProfile()
	wipe(TremorWatchSettings)
	NormalizeSettings(TremorWatchSettings)
	ApplyProfile()
end

-- loads the saved profiles and makes the one of this character the active settings
function ns.InitProfiles()
	if type(TremorWatchProfiles) ~= "table" then TremorWatchProfiles = {} end
	profiles = TremorWatchProfiles
	if type(profiles.Profiles) ~= "table" then profiles.Profiles = {} end
	if type(profiles.Chars) ~= "table" then profiles.Chars = {} end
	if not next(profiles.Profiles) then
		-- settings saved before profiles existed become the default profile
		profiles.Profiles[DEFAULT_PROFILE] = type(TremorWatchSettings) == "table" and TremorWatchSettings or {}
	end
	currentProfile = profiles.Chars[CharKey()]
	if not profiles.Profiles[currentProfile] then
		currentProfile = DEFAULT_PROFILE
		profiles.Profiles[currentProfile] = profiles.Profiles[currentProfile] or {}
	end
	profiles.Chars[CharKey()] = currentProfile
	TremorWatchSettings = NormalizeSettings(profiles.Profiles[currentProfile])
end
