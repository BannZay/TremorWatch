local _, ns = ...

-- Marks Tremor Totem nameplates with a large icon, a glow, the pulse swirl and a countdown.
--
-- Everything here is drawn on frames that never take mouse input: hovering or clicking the overlay reaches the
-- nameplate underneath. The nameplate's click area is its own frame rectangle, set by the client; nameplates are
-- protected frames, so they are never resized or moved here. The overlay is centred on the nameplate so the icon
-- sits over that click area (handy with a mouseover macro).
--
-- Nameplates have no GUID. A plate learns one while it is the target or under the mouse; until then a Tremor
-- plate is matched to the only tracked totem of its side (hostile plate: a totem whose shaman is not you or in your
-- group). With several candidates the plate gets no countdown.

local PULSE_INTERVAL, ICON = ns.PULSE_INTERVAL, "Interface\\Icons\\spell_nature_tremortotem"
local GLOW_TEXTURE = "Interface\\Buttons\\UI-ActionButton-Border"
local ROUND_BORDER = "Interface\\AddOns\\TremorWatch\\images\\RoundBorder"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local RING_LAYERS = 5 -- "growing border" pulse counter: borders added around the icon as the pulse comes closer
local SCAN_INTERVAL = 0.1
local FLASH_DURATION = 0.35
-- 3.3.5a nameplate layout (CGNamePlateFrame constructor): regions 1 flash, 2 border, 3 cast border, 4 cast shield,
-- 5 spell icon, 6 mouseover glow, 7 name, 8 level, ...; children 1 health bar, 2 cast bar
local REGION_GLOW, REGION_NAME = 6, 7

local floor, max = math.floor, math.max
local WorldFrame = WorldFrame
local frame, internal, Keys, totems = ns.frame, ns.internal, ns.Keys, ns.totems
local Sides = frame.Sides

local plates = {}       -- every nameplate frame found, in discovery order
local isPlate = {}      -- frame -> true for nameplates, false for other WorldFrame children
local plateGUID = {}    -- nameplate -> guid learned from target/mouseover (cleared when it hides)
local overlays = {}     -- nameplate -> overlay
local knownChildren = 0
local lookDirty = true
local nextScan = 0

local function IsNameplate(f)
	if f:GetName() or f:GetNumRegions() < REGION_NAME then return false end
	local name = select(REGION_NAME, f:GetRegions())
	local bar = f:GetChildren()
	return name and name:GetObjectType() == "FontString" and bar and bar:GetObjectType() == "StatusBar"
end

local function PlateName(plate)
	return (select(REGION_NAME, plate:GetRegions())):GetText()
end

-- Health bar recolor: barColor[plate] = { r, g, b = the client's color, sr, sg, sb = the color set here }. The
-- client's color is kept because it tells hostile plates apart; a bar no longer showing our color was recolored by
-- the client, whose new color is then taken.
local barColor = {}

local function Near(a, b) return math.abs(a - b) < 0.01 end

-- the color the client gave the plate's health bar
local function ClientBarColor(plate)
	local r, g, b = (plate:GetChildren()):GetStatusBarColor()
	local c = barColor[plate]
	if c and Near(r, c.sr) and Near(g, c.sg) and Near(b, c.sb) then return c.r, c.g, c.b end
	return r, g, b
end

-- called every frame: the client may set its own color again at any time
local function RecolorBar(plate, color)
	local bar = plate:GetChildren()
	local c = barColor[plate]
	local cr, cg, cb = bar:GetStatusBarColor()
	if c and c.sr == color.r and c.sg == color.g and c.sb == color.b
		and Near(cr, c.sr) and Near(cg, c.sg) and Near(cb, c.sb) then return end
	local r, g, b = ClientBarColor(plate)
	barColor[plate] = { r = r, g = g, b = b, sr = color.r, sg = color.g, sb = color.b }
	bar:SetStatusBarColor(color.r, color.g, color.b)
end

local function RestoreBar(plate)
	if not barColor[plate] then return end
	local r, g, b = ClientBarColor(plate)
	barColor[plate] = nil
	local bar = plate:GetChildren()
	bar:SetStatusBarColor(r, g, b)
end

-- "Hide name": the name text is hidden, not cleared, so the plate is still matched by its name
local nameHidden = {} -- plate -> true while its name text is hidden here

local function HideName(plate)
	local name = select(REGION_NAME, plate:GetRegions())
	if name:IsShown() then name:Hide() end -- called every frame: the client may show it again
	nameHidden[plate] = true
end

local function RestoreName(plate)
	if not nameHidden[plate] then return end
	nameHidden[plate] = nil
	local name = select(REGION_NAME, plate:GetRegions())
	name:Show()
end

-- red health bar: the unit can be attacked (hostile NPCs, enemy players and their totems)
local function IsHostilePlate(plate)
	local r, g, b = ClientBarColor(plate)
	return r > 0.5 and g < 0.5 and b < 0.5
end

local function IsMeOrGroupMember(guid)
	if guid == UnitGUID("player") then return true end
	for i = 1, GetNumRaidMembers() do
		if UnitGUID("raid" .. i) == guid then return true end
	end
	for i = 1, GetNumPartyMembers() do
		if UnitGUID("party" .. i) == guid then return true end
	end
	return false
end

local function OnPlateHide(plate)
	plateGUID[plate] = nil
	RestoreBar(plate) -- the frame is given to another unit next
	RestoreName(plate)
	local overlay = overlays[plate]
	if overlay then overlay:Hide() end
end

local function DiscoverPlates()
	local count = WorldFrame:GetNumChildren()
	if count == knownChildren then return end
	knownChildren = count
	local children = { WorldFrame:GetChildren() }
	for i = 1, #children do
		local f = children[i]
		if isPlate[f] == nil then
			isPlate[f] = IsNameplate(f) and true or false
			if isPlate[f] then
				plates[#plates + 1] = f
				f:HookScript("OnHide", OnPlateHide)
			end
		end
	end
end

local function SetPlateGUID(plate, guid)
	for other, g in pairs(plateGUID) do
		if g == guid then plateGUID[other] = nil end
	end
	plateGUID[plate] = guid
end

-- the target's plate is the only one at full alpha while there is a target; the mouseover plate shows its glow
local function LearnGUIDs(tremorPlates)
	local target, mouseover = UnitGUID("target"), UnitGUID("mouseover")
	for i = 1, #tremorPlates do
		local plate = tremorPlates[i]
		if target and totems[target] and plate:GetAlpha() == 1 then
			SetPlateGUID(plate, target)
		elseif mouseover and totems[mouseover] and (select(REGION_GLOW, plate:GetRegions())):IsShown() then
			SetPlateGUID(plate, mouseover)
		end
	end
end

local function FindTotem(plate, hostile)
	local guid = plateGUID[plate]
	if guid then return totems[guid] end

	local found
	for g, totem in pairs(totems) do
		if not totem.test and IsMeOrGroupMember(totem.owner) ~= hostile then
			local taken
			for other, og in pairs(plateGUID) do
				if og == g and other ~= plate and other:IsShown() then taken = true end
			end
			if not taken then
				if found then return nil end
				found = totem
			end
		end
	end
	return found
end

local function CreateOverlay(plate)
	local overlay = CreateFrame("Frame", nil, plate)
	overlay:EnableMouse(false)
	overlay:Hide()

	overlay.glowFrame = CreateFrame("Frame", nil, overlay)
	overlay.glowFrame:EnableMouse(false)
	overlay.glowFrame:SetAllPoints()
	overlay.glow = overlay.glowFrame:CreateTexture(nil, "BACKGROUND")
	overlay.glow:SetTexture(GLOW_TEXTURE)
	overlay.glow:SetBlendMode("ADD")
	overlay.glow:SetPoint("CENTER")
	overlay.pulse = overlay.glowFrame:CreateAnimationGroup()
	overlay.pulse:SetLooping("BOUNCE")
	local fade = overlay.pulse:CreateAnimation("Alpha")
	fade:SetChange(-0.75)
	fade:SetDuration(0.35)

	-- square style: the icon as on the main frame, with the swirl
	overlay.icon = overlay:CreateTexture(nil, "ARTWORK")
	overlay.icon:SetTexture(ICON)
	overlay.icon:SetAllPoints()

	-- round style: a round icon in a border, inside a colored ring (no swirl: it is square)
	overlay.ring = overlay:CreateTexture(nil, "BORDER")
	overlay.ring:SetTexture(ROUND_BORDER)
	overlay.ring:SetBlendMode("ADD")
	overlay.ring:SetPoint("CENTER")
	overlay.roundIcon = overlay:CreateTexture(nil, "ARTWORK")
	SetPortraitToTexture(overlay.roundIcon, ICON)
	overlay.roundIcon:SetTexCoord(0.075, 0.925, 0.075, 0.925)
	overlay.roundIcon:SetAllPoints()
	overlay.roundBorder = overlay:CreateTexture(nil, "OVERLAY")
	overlay.roundBorder:SetTexture(ROUND_BORDER)
	overlay.roundBorder:SetAllPoints()

	-- growing border layers: a round border each for the round style, four edges each for the square one
	overlay.layerFrame = CreateFrame("Frame", nil, overlay)
	overlay.layerFrame:EnableMouse(false)
	overlay.layerFrame:SetAllPoints()
	overlay.layers = {}
	for i = 1, RING_LAYERS do
		local layer = { edges = {} }
		layer.round = overlay.layerFrame:CreateTexture(nil, "ARTWORK")
		layer.round:SetTexture(ROUND_BORDER)
		layer.round:SetPoint("CENTER")
		for e = 1, 4 do
			layer.edges[e] = overlay.layerFrame:CreateTexture(nil, "ARTWORK")
			layer.edges[e]:SetTexture(WHITE)
		end
		overlay.layers[i] = layer
	end

	overlay.cooldown = CreateFrame("Cooldown", nil, overlay, "CooldownFrameTemplate")
	overlay.cooldown:EnableMouse(false)
	overlay.cooldown:SetAllPoints()
	overlay.cooldown.noCooldownCount = true -- OmniCC and similar addons skip it

	-- texts and the pulse flash sit on their own frame so they are drawn above the swirl
	overlay.top = CreateFrame("Frame", nil, overlay)
	overlay.top:EnableMouse(false)
	overlay.top:SetAllPoints()
	overlay.flash = overlay.top:CreateTexture(nil, "OVERLAY")
	overlay.flash:SetTexture(GLOW_TEXTURE)
	overlay.flash:SetBlendMode("ADD")
	overlay.flash:SetPoint("CENTER")
	overlay.flash:SetAlpha(0)
	overlay.countdown = overlay.top:CreateFontString(nil, "OVERLAY")
	overlay.countdown:SetPoint("CENTER")

	overlay.look = -1
	overlays[plate] = overlay
	return overlay
end

local lookVersion = 0

-- shows one growing-border layer in the overlay's style at `alpha` (hidden at 0)
local function SetLayerAlpha(overlay, layer, alpha)
	local key = overlay.round and alpha or -alpha -- the style is part of what is shown
	if layer.alpha == key then return end
	layer.alpha = key
	local shown = alpha > 0
	if shown and overlay.round then
		layer.round:SetAlpha(alpha)
		layer.round:Show()
	else
		layer.round:Hide()
	end
	for _, edge in ipairs(layer.edges) do
		if shown and not overlay.round then
			edge:SetAlpha(alpha)
			edge:Show()
		else
			edge:Hide()
		end
	end
end

local function ApplyLook(overlay, plate, db)
	local side = overlay.side
	local size = db[side.PlateSize]
	local color = db[side.PlateColor]
	overlay:SetSize(size, size)
	overlay:ClearAllPoints()
	overlay:SetPoint("CENTER", plate, "CENTER", 0, db[side.PlateOffsetY])
	local round = db[side.PlateStyle] == "round"
	overlay.round = round
	for _, part in ipairs({ overlay.ring, overlay.roundIcon, overlay.roundBorder }) do
		if round then part:Show() else part:Hide() end
	end
	if round then
		overlay.icon:Hide()
		overlay.cooldown:Hide()
		overlay.ring:SetSize(size * 1.25, size * 1.25)
		overlay.ring:SetVertexColor(color.r, color.g, color.b)
		overlay.glow:SetSize(size * 1.9, size * 1.9)
	else
		overlay.icon:Show()
		overlay.glow:SetSize(size * 64 / 36, size * 64 / 36) -- the icon hole is 36 of the texture's 64 pixels
	end
	overlay.totem, overlay.swirl = nil, nil -- re-applies the swirl on the next update
	overlay.glow:SetVertexColor(color.r, color.g, color.b)

	-- growing border: white layers instead of the swirl, the countdown text and the round style's colored ring;
	-- the first layer hugs the icon, each next one is a gap further out
	overlay.rings = db[side.PlateTicks] == "rings"
	if overlay.rings then
		overlay.cooldown:Hide()
		overlay.ring:Hide()
	end
	local gap = max(1, floor(size * 0.045 + 0.5))
	local thickness = max(1, floor(size * 0.02 + 0.5))
	local ringColor = db[side.PlateRingColor]
	for i, layer in ipairs(overlay.layers) do
		local d = thickness + (i - 1) * gap
		local outer = size + 2 * d
		layer.round:SetSize(outer, outer)
		layer.round:SetVertexColor(ringColor.r, ringColor.g, ringColor.b)
		local top, bottom, left, right = layer.edges[1], layer.edges[2], layer.edges[3], layer.edges[4]
		for _, edge in ipairs(layer.edges) do
			edge:ClearAllPoints()
			edge:SetVertexColor(ringColor.r, ringColor.g, ringColor.b)
		end
		top:SetPoint("TOPLEFT", overlay, "TOPLEFT", -d, d)
		top:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", d, d)
		top:SetHeight(thickness)
		bottom:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", -d, -d)
		bottom:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", d, -d)
		bottom:SetHeight(thickness)
		left:SetPoint("TOPLEFT", overlay, "TOPLEFT", -d, d)
		left:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", -d, -d)
		left:SetWidth(thickness)
		right:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", d, d)
		right:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", d, -d)
		right:SetWidth(thickness)
		layer.alpha = nil
		SetLayerAlpha(overlay, layer, 0)
	end
	overlay.flash:SetSize(size * 2.4, size * 2.4)
	overlay.countdown:SetFont(STANDARD_TEXT_FONT, max(floor(size * 0.38), 8), "THICKOUTLINE")
	if overlay.rings then overlay.countdown:SetText(nil) end -- only after SetFont: SetText errors on a font string without a font
	if db[side.PlateGlow] then
		overlay.pulse:Play()
	else
		overlay.pulse:Stop()
	end
	overlay.look = lookVersion
end

local function ShowOverlay(plate, hostile, side, db)
	local overlay = overlays[plate] or CreateOverlay(plate)
	overlay.hostile = hostile
	-- a reused plate may now show a totem of the other side, whose look differs
	if overlay.side ~= side then
		overlay.side = side
		overlay.look = -1
	end
	overlay:SetFrameLevel(plate:GetFrameLevel() + 10)
	overlay.cooldown:SetFrameLevel(overlay:GetFrameLevel() + 1)
	overlay.top:SetFrameLevel(overlay:GetFrameLevel() + 2)
	if not overlay:IsShown() then
		overlay.totem, overlay.swirl = nil, nil
		overlay:Show()
		overlay.look = -1
	end
	if overlay.look ~= lookVersion then ApplyLook(overlay, plate, db) end
end

-- swirl, countdown and pulse flash of one overlay
local function UpdateTicks(overlay, plate, now, db)
	local totem = db[overlay.side.PlateCountdown] and FindTotem(plate, overlay.hostile)
	if not totem then
		overlay.cooldown:Hide()
		overlay.countdown:SetText(nil)
		overlay.flash:SetAlpha(0)
		for _, layer in ipairs(overlay.layers) do SetLayerAlpha(overlay, layer, 0) end
		overlay.totem, overlay.swirl = nil, nil
		return
	end

	local anchor = totem.anchor
	local swirl = anchor + floor((now - anchor) / PULSE_INTERVAL) * PULSE_INTERVAL
	if overlay.totem ~= totem or overlay.swirl ~= swirl then
		-- a pulse happened since the last update of the same totem
		if overlay.totem == totem then overlay.flashStart = swirl end
		overlay.totem, overlay.swirl = totem, swirl
		if not overlay.round and not overlay.rings then overlay.cooldown:SetCooldown(swirl, PULSE_INTERVAL) end
	end
	if overlay.rings then
		-- the interval is cut in RING_LAYERS + 1 slices: none in the first, then layer i fades in during slice i + 1,
		-- so the outermost one is complete on the pulse
		local progress = (now - swirl) / PULSE_INTERVAL * (RING_LAYERS + 1)
		for i, layer in ipairs(overlay.layers) do
			local alpha = progress - i
			SetLayerAlpha(overlay, layer, alpha < 0 and 0 or alpha > 1 and 1 or alpha)
		end
	else
		overlay.countdown:SetFormattedText("%.1f", max(swirl + PULSE_INTERVAL - now, 0))
	end

	local age = overlay.flashStart and now - overlay.flashStart or FLASH_DURATION
	overlay.flash:SetAlpha(age < FLASH_DURATION and 1 - age / FLASH_DURATION or 0)
end

local tremorPlates = {}
local plateSide = {} -- Tremor plate -> the side whose settings it uses (enemy for a hostile plate)

local function Scan(now)
	local db = TremorWatchSettings.DB
	local enabled = not db[Keys.ArenaOnly] or internal.IsArena()
	DiscoverPlates()
	wipe(tremorPlates)
	wipe(plateSide)
	for i = 1, #plates do
		local plate = plates[i]
		local shown = false
		if enabled and plate:IsShown() and PlateName(plate) == ns.tremorName then
			local hostile = IsHostilePlate(plate)
			local side = hostile and Sides.enemy or Sides.ally
			-- the icon, the recolor and the hidden name are separate options; a plate is a Tremor plate here if
			-- any is on and its side is tracked
			if db[side.Track] and (db[side.PlateIcon] or db[side.PlateRecolor] or db[side.PlateHideName]) then
				tremorPlates[#tremorPlates + 1] = plate
				plateSide[plate] = side
				if db[side.PlateIcon] then
					ShowOverlay(plate, hostile, side, db)
				elseif overlays[plate] then
					overlays[plate]:Hide()
				end
				shown = true
			end
		end
		if not shown then
			if overlays[plate] then overlays[plate]:Hide() end
			-- a plate showing another unit keeps no GUID of a totem, nor our bar color or hidden name
			plateGUID[plate] = nil
			RestoreBar(plate)
			RestoreName(plate)
		end
	end
	LearnGUIDs(tremorPlates)
end

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function()
	if not TremorWatchSettings then return end
	local now = internal.Now()
	if lookDirty or now >= nextScan or nextScan - now > 1 then
		lookDirty = false
		nextScan = now + SCAN_INTERVAL
		Scan(now)
	end
	local db = TremorWatchSettings.DB
	for i = 1, #tremorPlates do
		local plate = tremorPlates[i]
		local side = plateSide[plate]
		local overlay = overlays[plate]
		if overlay and overlay:IsShown() then UpdateTicks(overlay, plate, now, db) end
		if db[side.PlateRecolor] then RecolorBar(plate, db[side.PlateBarColor]) else RestoreBar(plate) end
		if db[side.PlateHideName] then HideName(plate) else RestoreName(plate) end
	end
end)

-- any option change re-applies the look on the next frame
hooksecurefunc(frame, "OnSettingsUpdated", function()
	lookVersion = lookVersion + 1
	lookDirty = true
end)

-- `/tw plates`: what the scan sees, for finding out in real play why a plate is not marked
local function Report()
	local db = TremorWatchSettings.DB
	local lines = {}
	local tracked = 0
	for _, totem in pairs(totems) do
		if not totem.test then tracked = tracked + 1 end
	end
	local enemy, ally = Sides.enemy, Sides.ally
	lines[#lines + 1] = format("icon %s/%s, recolor %s/%s, countdown %s/%s (enemy/ally), arena only %s (in arena %s), combat log %s",
		tostring(db[enemy.PlateIcon]), tostring(db[ally.PlateIcon]), tostring(db[enemy.PlateRecolor]),
		tostring(db[ally.PlateRecolor]), tostring(db[enemy.PlateCountdown]), tostring(db[ally.PlateCountdown]),
		tostring(db[Keys.ArenaOnly]), tostring(internal.IsArena()), tostring(frame:IsEventRegistered("COMBAT_LOG_EVENT_UNFILTERED")))
	lines[#lines + 1] = format("tremor name \"%s\", WorldFrame children %d, nameplates found %d, tracked totems %d",
		tostring(ns.tremorName), WorldFrame:GetNumChildren(), #plates, tracked)
	for i = 1, #plates do
		local plate = plates[i]
		if plate:IsShown() then
			local r, g, b = ClientBarColor(plate)
			local overlay = overlays[plate]
			lines[#lines + 1] = format("  \"%s\" color %.2f %.2f %.2f, hostile %s, guid %s, overlay %s, totem %s",
				tostring(PlateName(plate)), r, g, b, tostring(IsHostilePlate(plate)), tostring(plateGUID[plate]),
				tostring(overlay and overlay:IsShown() or false),
				tostring(overlay and overlay:IsShown() and FindTotem(plate, overlay.hostile) ~= nil or false))
		end
	end
	return lines
end

internal.Nameplates = { Scan = Scan, FindTotem = FindTotem, Report = Report, Overlays = overlays, PlateGUID = plateGUID,
	Plates = plates }
