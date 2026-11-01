local _, ns = ...

local TREMOR_SPELL_ID = 8143
local PULSE_INTERVAL = 3
local TOTEM_MAX_AGE = 310 -- tremor totem lasts 5 minutes; older entries missed their death event
local FRESH_PULSE = 0.5 -- a pulse found later than this (lag, re-sync) gets no sound
local FLASH_TIME = 1
local SWELL_STEPS, SWELL_STEP = 15, 0.2 -- the swell: short sounds, one per step, the last ends on the pulse; there are steps for the
-- whole 3 s between pulses and the "swell length" setting says how many of the last ones are played
-- sound modes of a pulse: "simple" plays the pulse sound on the pulse, "swell" a rising run of sounds ending on it.
-- Swell presets are { id, name }; the id names the files Sounds/swell/<id>/<step>.wav (tools/gen_sounds.py).
local SWELL_PRESETS = { { "notes", "Rising notes" }, { "heartbeat", "Heartbeat" }, { "drops", "Water drops" },
	{ "ticks", "Clock ticks" }, { "bells", "Bells" }, { "roll", "Drum roll" }, { "sonar", "Sonar ping" }, { "arcade", "Arcade beeps" } }
local DEFAULT_SOUND_NAME = "mallet - TremorWatch" -- sound names read "<name> - <source addon>"
local DEFAULT_SOUND_PATH = "Interface\\AddOns\\TremorWatch\\Sounds\\mallet-alert.mp3"
local DESTROY_SOUND_NAME = "Raid warning - TremorWatch"
local NO_SOUND = "(None)" -- sorts first in the sound lists; stands for no sound at all
local DESTROY_SOUND_PATH = "Sound\\Interface\\RaidWarning.wav"
local ICON = "Interface\\Icons\\spell_nature_tremortotem"
local MAX_SLOTS = 3 -- most icons there are; the "max icons" setting can lower it


local frame = CreateFrame("Frame", "TremorWatchMainFrame", UIParent) -- the enemy frame; also receives the events
local allyFrame = CreateFrame("Frame", "TremorWatchAllyFrame", UIParent)

frame.Keys =
{
	ShowPulses = "showPulses",
	Size = "size",
	Alpha = "alpha",
	ArenaOnly = "arenaOnly",
	TrackAllies = "trackAllies",
	TrackEnemies = "trackEnemies",
	Sound = "sound",
	SoundMode = "soundMode",
	SwellPreset = "swellPreset",
	SwellLength = "swellLength",
	Countdown = "countdown",
	Locked = "locked",
	TestSounds = "testSounds",
	Highlight = "highlight",
	Latency = "latency",
	StaleTimeout = "staleTimeout",
	DestroyFlash = "destroyFlash",
	DestroySoundName = "destroySoundName",
	MaxIcons = "maxIcons",
	IconSpacing = "iconSpacing",
	SpawnSound = "spawnSound",
	AllySpawnSound = "allySpawnSound",
	AllowSounds = "allowSounds",
	AllyAllowSounds = "allyAllowSounds",
	AllySize = "allySize",
	AllyAlpha = "allyAlpha",
	AllyMaxIcons = "allyMaxIcons",
	AllyIconSpacing = "allyIconSpacing",
	Tint = "tint",
	AllyTint = "allyTint",
	AllyShowPulses = "allyShowPulses",
	AllyCountdown = "allyCountdown",
	AllySound = "allySound",
	AllySoundMode = "allySoundMode",
	AllySwellPreset = "allySwellPreset",
	AllySwellLength = "allySwellLength",
	AllyDestroyFlash = "allyDestroyFlash",
	AllyDestroySoundName = "allyDestroySoundName"
}

local Keys = frame.Keys

-- The two kinds of totems each have a frame, a position and their own settings. The enemy keys are the
-- original unprefixed ones. `slots` are the icons of a frame: slot 1 is the frame itself (the drag handle), the
-- others hang to its right.
local ENEMY =
{
	friendly = false, frame = frame, Location = "Location", testGUID = "TremorWatch-test",
	Track = Keys.TrackEnemies, AllowSounds = Keys.AllowSounds, Size = Keys.Size, Alpha = Keys.Alpha, MaxIcons = Keys.MaxIcons,
	IconSpacing = Keys.IconSpacing, ShowPulses = Keys.ShowPulses, Countdown = Keys.Countdown,
	Sound = Keys.Sound, SoundMode = Keys.SoundMode, SwellPreset = Keys.SwellPreset, SwellLength = Keys.SwellLength, SpawnSound = Keys.SpawnSound, DestroyFlash = Keys.DestroyFlash,
	DestroySoundName = Keys.DestroySoundName, Highlight = Keys.Highlight,
	Tint = Keys.Tint, TintColor = {1, 0.6, 0.6}
}
local ALLY =
{
	friendly = true, frame = allyFrame, Location = "LocationAlly", testGUID = "TremorWatch-test-ally",
	Track = Keys.TrackAllies, AllowSounds = Keys.AllyAllowSounds, Size = Keys.AllySize, Alpha = Keys.AllyAlpha, MaxIcons = Keys.AllyMaxIcons,
	IconSpacing = Keys.AllyIconSpacing, ShowPulses = Keys.AllyShowPulses, Countdown = Keys.AllyCountdown,
	Sound = Keys.AllySound, SoundMode = Keys.AllySoundMode, SwellPreset = Keys.AllySwellPreset, SwellLength = Keys.AllySwellLength, SpawnSound = Keys.AllySpawnSound, DestroyFlash = Keys.AllyDestroyFlash,
	DestroySoundName = Keys.AllyDestroySoundName, Tint = Keys.AllyTint, TintColor = {0.6, 1, 0.6}
}
local SIDES = { ENEMY, ALLY }
frame.Sides = { enemy = ENEMY, ally = ALLY }
frame.NoSound = NO_SOUND
frame.SwellPresets = SWELL_PRESETS
frame.SwellStep, frame.MaxSwellLength = SWELL_STEP, SWELL_STEPS * SWELL_STEP

-- steps in a swell, the length of one and how many of the first steps are skipped: the swell plays the last steps
-- that fit the side's chosen length, so a shorter one starts part-way and still ends on the pulse
local function SwellTiming(side)
	local length = tonumber(TremorWatchSettings.DB[side.SwellLength]) or 1.2
	local count = max(1, min(SWELL_STEPS, floor(length / SWELL_STEP + 0.5)))
	return SWELL_STEPS, SWELL_STEP, SWELL_STEPS - count
end

local function SideOf(totem)
	return totem.friendly and ALLY or ENEMY
end

local defaults =
{
	Location = {Point = "RIGHT", RelativeTo = "UIParent", RelativePoint = "RIGHT", XOfs = -263.89, YOfs = 76.33},
	LocationAlly = {Point = "RIGHT", RelativeTo = "UIParent", RelativePoint = "RIGHT", XOfs = -265.67, YOfs = -14.11},
	DB =
	{
		[Keys.ArenaOnly] = true,
		[Keys.Locked] = true,
		[Keys.TestSounds] = false,
		[Keys.Latency] = true,
		[Keys.StaleTimeout] = 60,

		[Keys.TrackEnemies] = true,
		[Keys.AllowSounds] = true,
		[Keys.Size] = 90,
		[Keys.Alpha] = 0.8,
		[Keys.MaxIcons] = MAX_SLOTS,
		[Keys.IconSpacing] = 0,
		[Keys.ShowPulses] = true,
		[Keys.Countdown] = true,
		[Keys.Sound] = "blip - TremorWatch",
		[Keys.SoundMode] = "swell",
		[Keys.SwellPreset] = "bells",
		[Keys.SwellLength] = 3,
		[Keys.SpawnSound] = NO_SOUND,
		[Keys.Highlight] = true,
		[Keys.Tint] = false,
		[Keys.DestroyFlash] = true,
		[Keys.DestroySoundName] = "shatter - TremorWatch",

		[Keys.TrackAllies] = false,
		[Keys.AllyAllowSounds] = false,
		[Keys.AllySize] = 90,
		[Keys.AllyAlpha] = 0.8,
		[Keys.AllyMaxIcons] = MAX_SLOTS,
		[Keys.AllyIconSpacing] = 0,
		[Keys.AllyTint] = true,
		[Keys.AllyShowPulses] = true,
		[Keys.AllyCountdown] = false,
		[Keys.AllySound] = NO_SOUND,
		[Keys.AllySoundMode] = "simple",
		[Keys.AllySwellPreset] = "notes",
		[Keys.AllySwellLength] = 1.2,
		[Keys.AllySpawnSound] = "Friendly tremor up (fast) - TremorWatch",
		[Keys.AllyDestroyFlash] = true,
		[Keys.AllyDestroySoundName] = "Friendly tremor down (fast) - TremorWatch"
	}
}


local function MakeSlot(side, host)
	local slot = { host = host }
	slot.icon = host:CreateTexture(nil, "BORDER")
	slot.icon:SetTexture(ICON)
	slot.icon:SetAllPoints()
	slot.cooldown = CreateFrame("Cooldown", nil, host, "CooldownFrameTemplate")
	slot.cooldown:SetAllPoints()
	slot.cooldown:SetReverse(false)

	-- texts sit on their own frame so they are drawn above the cooldown swirl
	slot.overlay = CreateFrame("Frame", nil, host)
	slot.overlay:SetAllPoints()
	slot.countdown = slot.overlay:CreateFontString(nil, "OVERLAY")
	slot.countdown:SetPoint("CENTER")
	slot.count = slot.overlay:CreateFontString(nil, "OVERLAY")
	slot.count:SetPoint("BOTTOMRIGHT", -2, 2)

	-- glowing border while the next pulse will remove a fear, charm or sleep from an enemy
	slot.highlight = slot.overlay:CreateTexture(nil, "ARTWORK")
	slot.highlight:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	slot.highlight:SetBlendMode("ADD")
	slot.highlight:SetVertexColor(1, 0.3, 0.1)
	slot.highlight:SetPoint("CENTER")
	slot.highlight:Hide()
	slot.glow = slot.highlight:CreateAnimationGroup()
	slot.glow:SetLooping("BOUNCE")
	local glowAlpha = slot.glow:CreateAnimation("Alpha")
	glowAlpha:SetChange(-0.6)
	glowAlpha:SetDuration(0.4)

	side.slots[#side.slots + 1] = slot
	return slot
end

for _, side in ipairs(SIDES) do
	side.slots = {}
	side.picked = {}        -- guids of the totems allowed on this frame, oldest first
	side.flashUntil = nil
	side.frame.side = side
	side.mainSlot = MakeSlot(side, side.frame)
	for i = 2, MAX_SLOTS do
		local host = CreateFrame("Frame", nil, side.frame)
		host:SetPoint("LEFT", side.slots[i - 1].host, "RIGHT", 2, 0) -- spacing is set in ApplyLook
		host:Hide()
		MakeSlot(side, host)
	end
	-- the main slot's parts stay reachable on the frame
	local main = side.mainSlot
	side.frame.icon, side.frame.cooldown, side.frame.countdown = main.icon, main.cooldown, main.countdown
	side.frame.count, side.frame.highlight = main.count, main.highlight
	side.frame.Slots = side.slots
end

-- Hooks the in-game tests replace: clock, arena check, sound output.
local internal = {}
frame.Internal = internal
internal.Now = GetTime
internal.IsArena = function() return select(2, IsInInstance()) == "arena" end
internal.PlaySound = PlaySoundFile

ns.frame, ns.allyFrame, ns.Keys, ns.ENEMY, ns.ALLY, ns.SIDES, ns.SideOf = frame, allyFrame, Keys, ENEMY, ALLY, SIDES, SideOf
ns.defaults, ns.internal = defaults, internal
ns.TREMOR_SPELL_ID, ns.PULSE_INTERVAL, ns.TOTEM_MAX_AGE, ns.FRESH_PULSE, ns.FLASH_TIME =
	TREMOR_SPELL_ID, PULSE_INTERVAL, TOTEM_MAX_AGE, FRESH_PULSE, FLASH_TIME
ns.DEFAULT_SOUND_NAME, ns.DEFAULT_SOUND_PATH, ns.DESTROY_SOUND_NAME, ns.DESTROY_SOUND_PATH, ns.NO_SOUND =
	DEFAULT_SOUND_NAME, DEFAULT_SOUND_PATH, DESTROY_SOUND_NAME, DESTROY_SOUND_PATH, NO_SOUND
ns.MAX_SLOTS, ns.SwellTiming, ns.SWELL_PRESETS = MAX_SLOTS, SwellTiming, SWELL_PRESETS
ns.tremorName = "Tremor Totem" -- replaced by the localized spell name at login
