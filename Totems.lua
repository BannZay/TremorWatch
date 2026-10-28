local _, ns = ...

local PULSE_INTERVAL, TOTEM_MAX_AGE, FRESH_PULSE, FLASH_TIME = ns.PULSE_INTERVAL, ns.TOTEM_MAX_AGE, ns.FRESH_PULSE, ns.FLASH_TIME
local TREMOR_SPELL_ID = ns.TREMOR_SPELL_ID

local band, floor, max, min, sort = bit.band, math.floor, math.max, math.min, table.sort
local HOSTILE, FRIENDLY = COMBATLOG_OBJECT_REACTION_HOSTILE, COMBATLOG_OBJECT_REACTION_FRIENDLY
local frame, internal, Keys, SIDES, SideOf = ns.frame, ns.internal, ns.Keys, ns.SIDES, ns.SideOf
local MAX_SLOTS, HasSound, SwellTiming = ns.MAX_SLOTS, ns.HasSound, ns.SwellTiming
local cc, REMOVABLE, SetCC, ClearUnitCC, ExpireCC, UpdateHighlight = ns.cc, ns.REMOVABLE, ns.SetCC, ns.ClearUnitCC, ns.ExpireCC, ns.UpdateHighlight

-- guid -> { summoned, seq, owner, friendly, test, seen, anchor (time of a pulse),
--           synced, swirl (start of the shown swirl), nextSwirl, nextSound (pulse schedule, valid once synced),
--           swellStep (swell steps already played before nextSound) }
local totems = {}
internal.totems = totems
local tracked = 0       -- number of real totems in `totems`
local seqCounter = 0    -- orders totems summoned at the same time
local nextExpiry = 0
local timer = CreateFrame("Frame")
timer:Hide()

local function LogDelay()
	if not TremorWatchSettings.DB[Keys.Latency] then return 0 end
	local _, _, latency = GetNetStats()
	return (latency or 0) / 2000
end

local function RemoveTotem(guid)
	local totem = totems[guid]
	if totem then
		totems[guid] = nil
		if not totem.test then tracked = tracked - 1 end
	end
end

-- latest pulse boundary at or before `now` for a schedule with pulses at `base` + n * PULSE_INTERVAL
local function LastBoundary(base, now)
	return base + floor((now - base) / PULSE_INTERVAL) * PULSE_INTERVAL
end

local function ApplySwirl(slot, start, side)
	if TremorWatchSettings.DB[side.ShowPulses] then
		slot.cooldown:SetCooldown(start, PULSE_INTERVAL)
	else
		slot.cooldown:Hide()
	end
end

local function SetCountdown(slot, text)
	if not text then slot.countdownTenths = nil end
	if text ~= slot.countdownText then
		slot.countdownText = text
		slot.countdown:SetText(text)
	end
end

-- Restarts a totem's pulse schedule. A re-sync of a totem that was already synced plays no sound; a totem
-- that was not on screen before gets its latest pulse played by the Tick if that just happened (a new totem
-- pulses on summon).
local function Resync(totem, now)
	local anchor = totem.anchor
	local swirl = LastBoundary(anchor, now)
	totem.swirl = swirl
	totem.nextSwirl = swirl + PULSE_INTERVAL
	totem.nextSound = LastBoundary(anchor, now)
	totem.swellStep = 0
	if totem.synced then
		totem.nextSound = totem.nextSound + PULSE_INTERVAL
	end
	totem.synced = true
end

local function ByAge(a, b)
	local x, y = totems[a], totems[b]
	if x.summoned ~= y.summoned then return x.summoned < y.summoned end
	return x.seq < y.seq
end

-- Picks the totems of one frame (the most recent allowed ones, oldest first) and syncs its icons and
-- pulse schedules. Returns true while the frame is in use.
local function UpdateSide(side, now, arenaOk, forceResync)
	local db = TremorWatchSettings.DB
	local picked = side.picked
	local track = arenaOk and db[side.Track]

	wipe(picked)
	for guid, totem in pairs(totems) do
		if SideOf(totem) == side then
			if totem.test or track then
				picked[#picked + 1] = guid
			else
				totem.synced = false
			end
		end
	end
	sort(picked, ByAge)
	local total = #picked
	local maxIcons = min(db[side.MaxIcons], MAX_SLOTS)
	local first = max(total - maxIcons + 1, 1)
	for i = 1, first - 1 do totems[picked[i]].synced = false end

	if total > 0 then
		side.flashUntil = nil
	elseif side.flashUntil and now >= side.flashUntil then
		side.flashUntil = nil
	end

	local lastShown = min(total, maxIcons)
	for i, slot in ipairs(side.slots) do
		local guid = i <= maxIcons and picked[first + i - 1] or nil
		local totem = guid and totems[guid]
		local changed = guid ~= slot.guid
		slot.guid = guid
		if totem then
			if forceResync or not totem.synced then
				Resync(totem, now)
				changed = true
			end
			if changed then ApplySwirl(slot, totem.swirl, side) end
			-- OmniCC and similar addons skip cooldowns marked like this
			slot.cooldown.noCooldownCount = db[side.Countdown] or nil
			if not db[side.Countdown] then SetCountdown(slot, nil) end
			if side.Tint and db[side.Tint] then
				slot.icon:SetVertexColor(side.TintColor[1], side.TintColor[2], side.TintColor[3])
			else
				slot.icon:SetVertexColor(1, 1, 1)
			end
		else
			slot.cooldown:Hide()
			slot.cooldown.noCooldownCount = nil
			SetCountdown(slot, nil)
			slot.icon:SetVertexColor(1, 1, 1)
		end
		slot.icon:SetDesaturated(not totem)
		-- totems beyond the icons show up as a count on the last one
		slot.count:SetText(i == lastShown and total > maxIcons and "+" .. (total - maxIcons) or nil)
		if i > 1 then
			if totem then slot.host:Show() else slot.host:Hide() end
		end
	end
	local active = total > 0 or side.flashUntil
	if active then
		side.frame:Show()
	else
		side.frame:Hide()
	end
	return active
end

-- Syncs both frames, the pulse schedules and the timer.
local function Update(forceResync)
	local db = TremorWatchSettings.DB
	local now = internal.Now()
	local arenaOk = not db[Keys.ArenaOnly] or internal.IsArena()

	local active
	for _, side in ipairs(SIDES) do
		if UpdateSide(side, now, arenaOk, forceResync) then active = true end
	end
	UpdateHighlight()

	if active then
		timer:Show()
	else
		timer:Hide()
	end
end
internal.Update = Update

-- drops totems whose death was never logged; returns true if any was removed
local function ExpireTotems(now)
	if ns.HasCC() then ExpireCC(now) end
	if tracked == 0 then return end
	local staleTimeout = not internal.IsArena() and TremorWatchSettings.DB[Keys.StaleTimeout]
	local target, focus, mouseover = UnitGUID("target"), UnitGUID("focus"), UnitGUID("mouseover")
	local removed
	for guid, totem in pairs(totems) do
		if not totem.test then
			local owner = totem.owner
			if target == guid or focus == guid or mouseover == guid
				or (owner and (target == owner or focus == owner or mouseover == owner)) then
				totem.seen = now
			end
			if now - totem.summoned > TOTEM_MAX_AGE or (staleTimeout and now - totem.seen > staleTimeout) then
				RemoveTotem(guid)
				removed = true
			end
		end
	end
	return removed
end

local pendingDestroy, ProcessPendingDestroy -- see AddTotem

local function Tick()
	local db = TremorWatchSettings.DB
	local now = internal.Now()
	if now >= nextExpiry or nextExpiry - now > 1 then -- or the clock went back
		nextExpiry = now + 1
		if ExpireTotems(now) then Update() else UpdateHighlight() end
	end
	for _, side in ipairs(SIDES) do
		if side.flashUntil and now >= side.flashUntil then Update() end
	end
	if next(pendingDestroy) then ProcessPendingDestroy() end

	for _, side in ipairs(SIDES) do
		local playSound, swellStep, swellAlert
		for _, slot in ipairs(side.slots) do
			local totem = slot.guid and totems[slot.guid]
			if totem then
				if now >= totem.nextSwirl then
					totem.swirl = LastBoundary(totem.nextSwirl, now)
					ApplySwirl(slot, totem.swirl, side)
					totem.nextSwirl = totem.swirl + PULSE_INTERVAL
				end
				if now >= totem.nextSound then
					local pulse = LastBoundary(totem.nextSound, now)
					if now - pulse < FRESH_PULSE and db[side.SoundMode] ~= "swell" and HasSound(db[side.Sound]) and db[side.AllowSounds]
						and (not totem.test or db[Keys.TestSounds]) then
						playSound = true
					end
					totem.nextSound = pulse + PULSE_INTERVAL
					totem.swellStep = 0
				end
				-- The swell is played step by step so that it stops with the totem: a destroyed totem is gone from
				-- `totems` and its remaining steps are never started (a played sound can not be stopped).
				if db[side.SoundMode] == "swell" and db[side.AllowSounds] and (not totem.test or db[Keys.TestSounds]) then
					local step = totem.swellStep
					local steps, stepLength, skip = SwellTiming(side)
					if step < skip then step = skip end
					while step < steps do
						local due = totem.nextSound - (steps - step) * stepLength
						if now < due then break end
						step = step + 1
						if now - due < stepLength then -- later ones are stale
							swellStep = max(swellStep or 0, step)
							if slot.highlight:IsShown() then swellAlert = true end
						end
					end
					totem.swellStep = step
				end
				if db[side.Countdown] then
					local tenths = floor(max(totem.nextSwirl - now, 0) * 10)
					if tenths ~= slot.countdownTenths then -- format only when the shown value changes
						slot.countdownTenths = tenths
						SetCountdown(slot, format("%.1f", tenths / 10))
					end
				end
			end
		end
		-- pulses of several totems of a frame at the same moment share one sound
		if playSound then internal.PlayPulseSound(side) end
		if swellStep then internal.PlaySwellStep(side, swellStep, swellAlert) end
	end
end
internal.Tick = Tick
timer:SetScript("OnUpdate", Tick)

-- A spawn sound replaces the pulse sound of the summon itself (a new totem pulses on summon). `silent` only
-- takes the summon pulse away, for the later totems of a group that spawn together.
local function AlertSpawn(totem, silent)
	local side = SideOf(totem)
	local db = TremorWatchSettings.DB
	if totem.synced and HasSound(db[side.SpawnSound]) and db[side.AllowSounds] then
		if not silent then internal.PlaySpawnSound(side) end
		totem.nextSound = max(totem.nextSound, totem.anchor + PULSE_INTERVAL)
	end
end

-- Destroy alerts wait until the next frame: a shaman who re-casts the totem kills the old one just before the new one is
-- summoned, and that is no destruction worth an alert. guid -> { time, owner, side }
pendingDestroy = {}
local DESTROY_DELAY = 0 -- the new summon is logged in the same frame, so waiting for the next OnUpdate is enough
local destroyTimer = CreateFrame("Frame")
destroyTimer:Hide()

local function AlertDestroy(side)
	local db = TremorWatchSettings.DB
	if HasSound(db[side.DestroySoundName]) and db[side.AllowSounds] then internal.PlayDestroySound(side) end
	if db[side.DestroyFlash] and not side.mainSlot.guid then
		side.flashUntil = internal.Now() + FLASH_TIME
		Update()
	end
end

function ProcessPendingDestroy()
	local now = internal.Now()
	for guid, pending in pairs(pendingDestroy) do
		if now - pending.time >= DESTROY_DELAY or now < pending.time then
			pendingDestroy[guid] = nil
			AlertDestroy(pending.side)
		end
	end
	if not next(pendingDestroy) then destroyTimer:Hide() end
end
internal.ProcessPendingDestroy = ProcessPendingDestroy
destroyTimer:SetScript("OnUpdate", ProcessPendingDestroy)

local function AddTotem(guid, ownerGUID, friendly)
	local now = internal.Now()
	ExpireTotems(now)
	-- a shaman has one tremor totem: a new one replaces the old one, usually after a death event of its own
	local replaced
	if ownerGUID then
		for g, totem in pairs(totems) do
			if totem.owner == ownerGUID then
				RemoveTotem(g)
				replaced = true
			end
		end
		for g, pending in pairs(pendingDestroy) do
			if pending.owner == ownerGUID then
				pendingDestroy[g] = nil
				replaced = true
			end
		end
	end
	RemoveTotem(guid)
	seqCounter = seqCounter + 1
	totems[guid] = { summoned = now, seq = seqCounter, owner = ownerGUID, friendly = friendly, seen = now,
		anchor = now - LogDelay() }
	tracked = tracked + 1
	Update()

	-- a replacement only pulses (the regular pulse sound)
	if not replaced then AlertSpawn(totems[guid]) end
end

-- totem destroyed (or its owner died): alert if an icon was showing it
local function DestroyTotem(guid)
	local totem = totems[guid]
	local side = SideOf(totem)
	local wasShown
	for _, slot in ipairs(side.slots) do
		if slot.guid == guid then wasShown = true end
	end
	RemoveTotem(guid)
	Update()
	if not wasShown then return end
	pendingDestroy[guid] = { time = internal.Now(), owner = totem.owner, side = side }
	destroyTimer:Show()
end

local function ClearTotems()
	wipe(pendingDestroy)
	destroyTimer:Hide()
	for guid, totem in pairs(totems) do
		if not totem.test then RemoveTotem(guid) end
	end
	for guid in pairs(cc) do ClearUnitCC(guid) end
	for _, side in ipairs(SIDES) do side.flashUntil = nil end
	Update()
end

local function Touch(guid, now)
	local totem = totems[guid]
	if totem then totem.seen = now end
end

local function OnCombatLog(timestamp, eventType, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, spellId)
	if eventType == "SPELL_SUMMON" then
		if spellId == TREMOR_SPELL_ID or destName == ns.tremorName then
			-- the totem's reaction is only known once its object exists on the client; the owner's always is.
			-- Totems of both kinds are always tracked; which are shown is up to the "track" settings.
			local destHostile, destFriendly = band(destFlags, HOSTILE) ~= 0, band(destFlags, FRIENDLY) ~= 0
			if destHostile or (not destFriendly and band(sourceFlags, HOSTILE) ~= 0) then
				AddTotem(destGUID, sourceGUID, false)
			elseif destFriendly or band(sourceFlags, FRIENDLY) ~= 0 then
				AddTotem(destGUID, sourceGUID, true)
			end
			return
		end
	end

	-- removable auras on enemies, tracked even before a totem shows up
	if REMOVABLE[spellId] and band(destFlags, HOSTILE) ~= 0 then
		if eventType == "SPELL_AURA_APPLIED" or eventType == "SPELL_AURA_REFRESH" then
			SetCC(destGUID, spellId, internal.Now())
			UpdateHighlight()
		elseif eventType == "SPELL_AURA_REMOVED" or eventType == "SPELL_AURA_BROKEN"
			or eventType == "SPELL_AURA_BROKEN_SPELL" then
			SetCC(destGUID, spellId, nil)
			UpdateHighlight()
		end
	elseif cc[destGUID] and (eventType == "UNIT_DIED" or eventType == "UNIT_DESTROYED") then
		ClearUnitCC(destGUID)
		UpdateHighlight()
	end
	if tracked == 0 then return end

	if eventType == "UNIT_DIED" or eventType == "UNIT_DESTROYED" then
		if totems[destGUID] then
			DestroyTotem(destGUID)
		else
			for guid, totem in pairs(totems) do
				if totem.owner == destGUID then DestroyTotem(guid) end
			end
		end
		return
	end

	-- the totem or its owner showing up in the log keeps the totem from going stale
	local now = internal.Now()
	Touch(sourceGUID, now)
	Touch(destGUID, now)
	for _, totem in pairs(totems) do
		if totem.owner == sourceGUID or totem.owner == destGUID then totem.seen = now end
	end
end
internal.OnCombatLog = OnCombatLog

-- with "arena only" the combat log is only read inside arenas
local function UpdateRegistration()
	if not TremorWatchSettings.DB[Keys.ArenaOnly] or internal.IsArena() then
		frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	else
		frame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
		ClearTotems()
	end
end
internal.UpdateRegistration = UpdateRegistration

ns.totems, ns.Update, ns.AlertSpawn, ns.ClearTotems, ns.UpdateRegistration, ns.OnCombatLog =
	totems, Update, AlertSpawn, ClearTotems, UpdateRegistration, OnCombatLog
