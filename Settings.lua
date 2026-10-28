local _, ns = ...

local floor, max, min = math.floor, math.max, math.min
local frame, internal, Keys, SIDES, ENEMY, ALLY = ns.frame, ns.internal, ns.Keys, ns.SIDES, ns.ENEMY, ns.ALLY
local MAX_SLOTS, defaults, totems = ns.MAX_SLOTS, ns.defaults, ns.totems
local Update, AlertSpawn, UpdateRegistration = ns.Update, ns.AlertSpawn, ns.UpdateRegistration

local function CopyDefaults(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			CopyDefaults(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end

-- these change when the pulse schedule or swirl must be rebuilt
local RESYNC_KEYS = { [Keys.Latency] = true, [Keys.ShowPulses] = true, [Keys.AllyShowPulses] = true }

-- unlocked, every frame shows as many fake totems as it has icons, so it can be placed and spaced
-- Returns the fake totems that were just added, by side.
local function ApplyTestMode()
	local db = TremorWatchSettings.DB
	local now = internal.Now()
	local fresh = { [ENEMY] = {}, [ALLY] = {} }
	for _, side in ipairs(SIDES) do
		local count = not db[Keys.Locked] and min(db[side.MaxIcons], MAX_SLOTS) or 0
		for i = 1, MAX_SLOTS do
			local guid = side.testGUID .. i
			if i > count then
				totems[guid] = nil
			elseif not totems[guid] then
				totems[guid] = { test = true, friendly = side.friendly, summoned = now, seq = i, seen = now, anchor = now }
				fresh[side][#fresh[side] + 1] = totems[guid]
			end
		end
	end
	return fresh
end

local function ApplyLock()
	local mouse = not TremorWatchSettings.DB[Keys.Locked]
	for _, side in ipairs(SIDES) do
		for _, slot in ipairs(side.slots) do
			slot.host:EnableMouse(mouse)
		end
	end
end

local function ApplyLocation(side)
	local loc = TremorWatchSettings[side.Location]
	side.frame:ClearAllPoints()
	side.frame:SetPoint(loc.Point, _G[loc.RelativeTo] or UIParent, loc.RelativePoint, loc.XOfs, loc.YOfs)
end

local function ApplyLook()
	local db = TremorWatchSettings.DB
	for _, side in ipairs(SIDES) do
		local size = db[side.Size]
		side.frame:SetAlpha(db[side.Alpha])
		for i, slot in ipairs(side.slots) do
			slot.host:SetSize(size, size)
			if i > 1 then
				slot.host:ClearAllPoints()
				slot.host:SetPoint("LEFT", side.slots[i - 1].host, "RIGHT", db[side.IconSpacing], 0)
			end
			slot.countdown:SetFont(STANDARD_TEXT_FONT, max(floor(size * 0.3), 8), "OUTLINE")
			slot.count:SetFont(STANDARD_TEXT_FONT, max(floor(size * 0.22), 8), "OUTLINE")
			slot.highlight:SetSize(size * 64 / 36, size * 64 / 36) -- the icon hole is 36 of the texture's 64 pixels
		end
	end
end

-- puts both frames back at their default positions
function frame:ResetLocation()
	for _, side in ipairs(SIDES) do
		TremorWatchSettings[side.Location] = CopyDefaults({}, defaults[side.Location])
		ApplyLocation(side)
	end
end

function frame:OnSettingsUpdated(key)
	self:StopSwellPreview()
	ApplyLook()
	ApplyLock()
	local fresh = ApplyTestMode()
	if key == nil or key == Keys.ArenaOnly then
		UpdateRegistration()
	end
	-- timing changes restart the pulse schedule so they show immediately
	Update(key == nil or RESYNC_KEYS[key])
	-- unlocking plays the spawn sounds too when sounds are wanted on the fake totems
	if TremorWatchSettings.DB[Keys.TestSounds] then
		for _, side in ipairs(SIDES) do
			for i, totem in ipairs(fresh[side]) do AlertSpawn(totem, i > 1) end
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
		-- the position lives in the saved variables, not in the client's layout cache
		self:SetUserPlaced(false)

		local point, relativeTo, relativePoint, xOfs, yOfs = self:GetPoint()
		local loc = TremorWatchSettings[self.side.Location]
		loc.Point = point
		loc.RelativeTo = relativeTo and relativeTo:GetName() or "UIParent"
		loc.RelativePoint = relativePoint
		loc.XOfs = xOfs
		loc.YOfs = yOfs
	end
end

ns.CopyDefaults, ns.ApplyLocation, ns.OnMouseDown, ns.OnMouseUp = CopyDefaults, ApplyLocation, OnMouseDown, OnMouseUp
