-- Brainrot Escape Disaster — server
--
-- The map runs along +X. The Safe Zone (X < 0) holds the spawn, every player's base, the depository pad,
-- the upgrade shop and the rebirth altar. The field (0 < X < 480) is split into rarity zones: the farther
-- out, the rarer (and richer) the brainrots. Players walk into a brainrot to bag it, carry the bag back to
-- the depository to bank it on their base, and every banked brainrot pays cash every second. Every minute
-- or so a tsunami sweeps the field from the far end toward the Safe Zone: anyone still outside is wiped
-- out and loses their bag.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local DataStoreService = game:GetService("DataStoreService")

local Tour = require(script:WaitForChild("Tour"))

local rng = Random.new()

--------------------------------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------------------------------

local SAFE_EDGE = 0 -- X of the Safe Zone boundary: X < SAFE_EDGE is safe
local SAFE_START = -100
local FIELD_END = 480
local HALF_WIDTH = 70 -- the map spans Z in [-HALF_WIDTH, HALF_WIDTH]
local GROUND_Y = 0.2

local FIRST_WAVE_DELAY = 40
local WAVE_GAP_MIN, WAVE_GAP_MAX = 45, 70
local WARNING_TIME = 10
local WAVE_BASE_SPEED = 30
local WAVE_SPEED_STEP = 2.5
local WAVE_MAX_SPEED = 55
local WAVE_THICKNESS = 26

local DEPOSIT_POS = Vector3.new(-12, 0, 0)
local DEPOSIT_RADIUS = 8
local SHOP_POS = Vector3.new(-50, 0, 22)
local REBIRTH_POS = Vector3.new(-50, 0, -22)

local BASE_CAPACITY = 3
local BASE_MAGNET = 5
local BASE_SPEED = 16
local REBIRTH_BASE_COST = 25000

local RARITIES = {
	Common = { order = 1, color = Color3.fromRGB(205, 205, 205) },
	Rare = { order = 2, color = Color3.fromRGB(70, 150, 255) },
	Epic = { order = 3, color = Color3.fromRGB(175, 85, 255) },
	Legendary = { order = 4, color = Color3.fromRGB(255, 190, 40) },
	Mythic = { order = 5, color = Color3.fromRGB(255, 60, 95) },
	Secret = { order = 6, color = Color3.fromRGB(40, 255, 205) },
}

-- Field zones, nearest first. `count` is how many brainrots the zone keeps alive at once.
local ZONES = {
	{ rarity = "Common", x0 = 8, x1 = 90, count = 12, floor = Color3.fromRGB(96, 150, 84) },
	{ rarity = "Rare", x0 = 90, x1 = 170, count = 9, floor = Color3.fromRGB(70, 118, 160) },
	{ rarity = "Epic", x0 = 170, x1 = 250, count = 7, floor = Color3.fromRGB(110, 78, 150) },
	{ rarity = "Legendary", x0 = 250, x1 = 330, count = 5, floor = Color3.fromRGB(165, 132, 50) },
	{ rarity = "Mythic", x0 = 330, x1 = 410, count = 4, floor = Color3.fromRGB(150, 50, 70) },
	{ rarity = "Secret", x0 = 410, x1 = 476, count = 2, floor = Color3.fromRGB(30, 120, 110) },
}

local UPGRADES = {
	speed = { name = "Speed", base = 100, growth = 1.7, max = 10 },
	capacity = { name = "Bag Capacity", base = 150, growth = 1.75, max = 12 },
	magnet = { name = "Magnet", base = 250, growth = 1.85, max = 10 },
}
local UPGRADE_ORDER = { "speed", "capacity", "magnet" }

--------------------------------------------------------------------------------------------------------
-- Model building helpers
--------------------------------------------------------------------------------------------------------

local UP = CFrame.Angles(0, 0, math.rad(90)) -- turns a cylinder's X axis upright

local function makePart(parent: Instance, props: { [string]: any }): BasePart
	local p: BasePart
	if props.wedge then
		p = Instance.new("WedgePart")
	else
		p = Instance.new("Part")
		if props.shape then
			(p :: Part).Shape = props.shape
		end
	end
	p.Anchored = true
	p.CanCollide = props.collide == true
	p.CanTouch = false
	p.CanQuery = props.collide == true
	p.CastShadow = props.shadow ~= false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = props.material or Enum.Material.SmoothPlastic
	p.Color = props.color or Color3.new(1, 1, 1)
	p.Size = props.size or Vector3.one
	p.CFrame = props.cf or CFrame.new()
	p.Transparency = props.transparency or 0
	p.Reflectance = props.reflectance or 0
	p.Name = props.name or "Part"
	p.Parent = parent
	return p
end

local function ball(parent, pos: Vector3, d: number, color: Color3, material: Enum.Material?)
	return makePart(parent, { shape = Enum.PartType.Ball, size = Vector3.new(d, d, d), cf = CFrame.new(pos), color = color, material = material })
end

local function block(parent, pos: Vector3, size: Vector3, color: Color3, material: Enum.Material?, rot: CFrame?)
	return makePart(parent, { size = size, cf = CFrame.new(pos) * (rot or CFrame.identity), color = color, material = material })
end

local function cylinder(parent, pos: Vector3, height: number, d: number, color: Color3, material: Enum.Material?)
	return makePart(parent, { shape = Enum.PartType.Cylinder, size = Vector3.new(height, d, d), cf = CFrame.new(pos) * UP, color = color, material = material })
end

local SKIN = Color3.fromRGB(255, 204, 160)
local SKIN_DARK = Color3.fromRGB(150, 100, 70)
local BLACK = Color3.fromRGB(20, 20, 24)
local WHITE = Color3.fromRGB(245, 245, 245)

-- A blocky figure facing -Z. Returns the head's centre so callers can add faces and props.
local function figure(m: Model, s: number, shirt: Color3, pants: Color3, skin: Color3): Vector3
	block(m, Vector3.new(-0.5, 1, 0) * s, Vector3.new(0.95, 2, 0.95) * s, pants)
	block(m, Vector3.new(0.5, 1, 0) * s, Vector3.new(0.95, 2, 0.95) * s, pants)
	block(m, Vector3.new(0, 3, 0) * s, Vector3.new(2, 2, 1) * s, shirt)
	block(m, Vector3.new(-1.5, 3, 0) * s, Vector3.new(0.95, 2, 0.95) * s, skin)
	block(m, Vector3.new(1.5, 3, 0) * s, Vector3.new(0.95, 2, 0.95) * s, skin)
	local head = Vector3.new(0, 4.65, 0) * s
	block(m, head, Vector3.new(1.3, 1.3, 1.3) * s, skin)
	return head
end

local function eyes(m: Model, head: Vector3, s: number, color: Color3, material: Enum.Material?)
	block(m, head + Vector3.new(-0.3, 0.15, -0.66) * s, Vector3.new(0.25, 0.25, 0.05) * s, color, material)
	block(m, head + Vector3.new(0.3, 0.15, -0.66) * s, Vector3.new(0.25, 0.25, 0.05) * s, color, material)
end

local function smirk(m: Model, head: Vector3, s: number)
	block(m, head + Vector3.new(0.08, -0.32, -0.66) * s, Vector3.new(0.55, 0.1, 0.05) * s, BLACK, nil, CFrame.Angles(0, 0, math.rad(-12)))
end

--------------------------------------------------------------------------------------------------------
-- The brainrots
--------------------------------------------------------------------------------------------------------

type BrainrotDef = {
	id: string,
	name: string,
	rarity: string,
	cps: number,
	height: number,
	build: (Model) -> (),
}

local BRAINROTS: { BrainrotDef } = {
	{
		id = "skibidi", name = "Skibidi Toilet", rarity = "Common", cps = 5, height = 4.4,
		build = function(m)
			block(m, Vector3.new(0, 0.6, 0.2), Vector3.new(1.6, 1.2, 1.8), WHITE)
			cylinder(m, Vector3.new(0, 1.9, 0), 1.4, 3, WHITE)
			cylinder(m, Vector3.new(0, 2.62, 0), 0.08, 2.4, Color3.fromRGB(120, 200, 255), Enum.Material.Glass)
			block(m, Vector3.new(0, 3.2, 1.45), Vector3.new(2.6, 2.6, 0.9), WHITE)
			block(m, Vector3.new(0.9, 4.6, 1.45), Vector3.new(0.5, 0.2, 0.3), Color3.fromRGB(190, 190, 200), Enum.Material.Metal)
			local head = Vector3.new(0, 3.35, -0.15)
			ball(m, head, 1.9, SKIN)
			ball(m, head + Vector3.new(-0.42, 0.25, -0.78), 0.42, WHITE)
			ball(m, head + Vector3.new(0.42, 0.25, -0.78), 0.42, WHITE)
			ball(m, head + Vector3.new(-0.42, 0.25, -0.95), 0.2, BLACK)
			ball(m, head + Vector3.new(0.42, 0.25, -0.95), 0.2, BLACK)
			block(m, head + Vector3.new(0, -0.38, -0.88), Vector3.new(0.7, 0.3, 0.1), Color3.fromRGB(140, 30, 40))
		end,
	},
	{
		id = "mewcat", name = "Mewing Cat", rarity = "Common", cps = 9, height = 4.6,
		build = function(m)
			local fur = Color3.fromRGB(255, 155, 55)
			block(m, Vector3.new(0, 1.2, 0.4), Vector3.new(2.4, 1.8, 3.2), fur)
			for _, x in { -0.8, 0.8 } do
				block(m, Vector3.new(x, 0.25, -0.9), Vector3.new(0.6, 0.5, 0.6), WHITE)
				block(m, Vector3.new(x, 0.25, 1.7), Vector3.new(0.6, 0.5, 0.6), WHITE)
			end
			local head = Vector3.new(0, 3.0, -1.0)
			block(m, head, Vector3.new(2.2, 2, 2), fur)
			block(m, head + Vector3.new(-0.7, 1.25, 0), Vector3.new(0.55, 0.6, 0.35), fur, nil, CFrame.Angles(0, 0, math.rad(15)))
			block(m, head + Vector3.new(0.7, 1.25, 0), Vector3.new(0.55, 0.6, 0.35), fur, nil, CFrame.Angles(0, 0, math.rad(-15)))
			-- smug half-closed eyes and a razor-sharp mewing jawline
			block(m, head + Vector3.new(-0.5, 0.25, -1.02), Vector3.new(0.45, 0.14, 0.05), BLACK)
			block(m, head + Vector3.new(0.5, 0.25, -1.02), Vector3.new(0.45, 0.14, 0.05), BLACK)
			block(m, head + Vector3.new(0, -0.85, -0.7), Vector3.new(2.0, 0.35, 0.8), Color3.fromRGB(235, 130, 40), nil, CFrame.Angles(math.rad(-15), 0, 0))
			-- the finger on the lips: "shh, I'm mewing"
			block(m, head + Vector3.new(0, -0.35, -1.12), Vector3.new(0.18, 0.8, 0.18), WHITE)
			block(m, Vector3.new(0, 2.3, 2.3), Vector3.new(0.4, 0.4, 1.8), fur, nil, CFrame.Angles(math.rad(-40), 0, 0))
		end,
	},
	{
		id = "grimace", name = "Grimace Shake", rarity = "Rare", cps = 25, height = 5.4,
		build = function(m)
			local purple = Color3.fromRGB(140, 70, 205)
			cylinder(m, Vector3.new(0, 1.7, 0), 3.4, 2.5, purple)
			cylinder(m, Vector3.new(0, 3.5, 0), 0.3, 2.7, WHITE)
			ball(m, Vector3.new(0, 3.9, 0), 1.9, Color3.fromRGB(205, 165, 255))
			block(m, Vector3.new(0.45, 5.0, 0), Vector3.new(0.3, 2.4, 0.3), Color3.fromRGB(230, 50, 60), nil, CFrame.Angles(0, 0, math.rad(-12)))
			ball(m, Vector3.new(-0.45, 2.4, -1.2), 0.5, WHITE)
			ball(m, Vector3.new(0.45, 2.4, -1.2), 0.5, WHITE)
			ball(m, Vector3.new(-0.45, 2.4, -1.4), 0.24, BLACK)
			ball(m, Vector3.new(0.45, 2.4, -1.4), 0.24, BLACK)
			block(m, Vector3.new(0, 1.7, -1.25), Vector3.new(0.9, 0.18, 0.05), BLACK)
		end,
	},
	{
		id = "looksmaxxer", name = "Looksmaxxer", rarity = "Rare", cps = 40, height = 5.5,
		build = function(m)
			local head = figure(m, 1, Color3.fromRGB(240, 240, 250), Color3.fromRGB(60, 90, 160), SKIN)
			eyes(m, head, 1, Color3.fromRGB(80, 230, 255), Enum.Material.Neon)
			block(m, head + Vector3.new(0, -0.62, -0.1), Vector3.new(1.45, 0.25, 1.2), SKIN) -- the jawline
			block(m, head + Vector3.new(0, 0.75, 0), Vector3.new(1.4, 0.3, 1.4), Color3.fromRGB(240, 210, 80)) -- golden hair
			-- a hand mirror, always checking the angles
			cylinder(m, Vector3.new(1.5, 3.9, -0.8), 0.1, 1.0, Color3.fromRGB(200, 230, 255), Enum.Material.Glass)
			for i = 1, 3 do
				local a = i * 2.1
				ball(m, head + Vector3.new(math.cos(a) * 1.3, 0.6, math.sin(a) * 1.3), 0.25, Color3.fromRGB(255, 255, 180), Enum.Material.Neon)
			end
		end,
	},
	{
		id = "fanum", name = "Fanum Tax", rarity = "Epic", cps = 110, height = 5.5,
		build = function(m)
			local head = figure(m, 1, Color3.fromRGB(255, 120, 30), Color3.fromRGB(40, 40, 50), SKIN_DARK)
			eyes(m, head, 1, BLACK)
			smirk(m, head, 1)
			block(m, head + Vector3.new(0, 0.72, 0), Vector3.new(1.35, 0.25, 1.35), BLACK)
			-- he is taxing your fries
			block(m, Vector3.new(0, 3.2, -1.2), Vector3.new(2.4, 0.2, 1.4), Color3.fromRGB(120, 70, 40))
			block(m, Vector3.new(-0.5, 3.7, -1.2), Vector3.new(0.8, 0.8, 0.8), Color3.fromRGB(220, 40, 40))
			for i = -2, 2 do
				block(m, Vector3.new(-0.5 + i * 0.13, 4.25, -1.2), Vector3.new(0.1, 0.6, 0.1), Color3.fromRGB(255, 210, 60))
			end
			ball(m, Vector3.new(0.6, 3.6, -1.2), 0.8, Color3.fromRGB(200, 140, 60))
		end,
	},
	{
		id = "sigma", name = "Sigma Boy", rarity = "Epic", cps = 160, height = 5.6,
		build = function(m)
			local head = figure(m, 1, Color3.fromRGB(25, 25, 32), Color3.fromRGB(25, 25, 32), SKIN)
			block(m, Vector3.new(0, 3.55, -0.51), Vector3.new(0.5, 0.8, 0.05), WHITE)
			block(m, Vector3.new(0, 3.35, -0.54), Vector3.new(0.2, 0.7, 0.05), Color3.fromRGB(200, 30, 40))
			block(m, head + Vector3.new(0, 0.18, -0.67), Vector3.new(1.25, 0.3, 0.06), BLACK, Enum.Material.Glass) -- shades
			smirk(m, head, 1)
			block(m, head + Vector3.new(0, 0.72, 0.1), Vector3.new(1.35, 0.3, 1.4), Color3.fromRGB(40, 30, 20)) -- slicked hair
		end,
	},
	{
		id = "rizzler", name = "Rizzler", rarity = "Legendary", cps = 450, height = 5.6,
		build = function(m)
			local head = figure(m, 1, Color3.fromRGB(255, 105, 180), Color3.fromRGB(240, 240, 240), SKIN_DARK)
			eyes(m, head, 1, BLACK)
			-- the eyebrow
			block(m, head + Vector3.new(-0.3, 0.42, -0.67), Vector3.new(0.4, 0.1, 0.05), BLACK)
			block(m, head + Vector3.new(0.3, 0.5, -0.67), Vector3.new(0.4, 0.1, 0.05), BLACK, nil, CFrame.Angles(0, 0, math.rad(25)))
			smirk(m, head, 1)
			block(m, head + Vector3.new(0, 0.75, 0), Vector3.new(1.4, 0.35, 1.4), BLACK)
			-- gold chain
			for i = -3, 3 do
				ball(m, Vector3.new(i * 0.22, 3.3 + math.abs(i) * 0.1, -0.55), 0.22, Color3.fromRGB(255, 200, 40), Enum.Material.Neon)
			end
		end,
	},
	{
		id = "kai", name = "Kai Cenat", rarity = "Mythic", cps = 1200, height = 5.9,
		build = function(m)
			local head = figure(m, 1, Color3.fromRGB(210, 35, 45), Color3.fromRGB(30, 30, 40), SKIN_DARK)
			eyes(m, head, 1, WHITE)
			block(m, head + Vector3.new(0, -0.3, -0.66), Vector3.new(0.6, 0.35, 0.05), BLACK) -- shouting at chat
			-- headset
			block(m, head + Vector3.new(0, 0.82, 0), Vector3.new(1.5, 0.2, 0.3), BLACK)
			block(m, head + Vector3.new(-0.75, 0, 0), Vector3.new(0.3, 0.7, 0.7), BLACK)
			block(m, head + Vector3.new(0.75, 0, 0), Vector3.new(0.3, 0.7, 0.7), BLACK)
			block(m, head + Vector3.new(-0.5, -0.4, -0.6), Vector3.new(0.6, 0.1, 0.1), BLACK)
			ball(m, head + Vector3.new(-0.15, -0.4, -0.72), 0.25, Color3.fromRGB(80, 255, 120), Enum.Material.Neon)
			-- a little stream light
			block(m, Vector3.new(0, 5.8, -0.9), Vector3.new(0.9, 0.4, 0.15), Color3.fromRGB(255, 40, 60), Enum.Material.Neon)
		end,
	},
	{
		id = "gigachad", name = "GigaChad", rarity = "Secret", cps = 4000, height = 7.8,
		build = function(m)
			local s = 1.3
			local grey = Color3.fromRGB(200, 200, 205)
			local head = figure(m, s, grey, Color3.fromRGB(40, 40, 45), grey)
			block(m, Vector3.new(0, 3.1, 0) * s, Vector3.new(2.6, 1.6, 1.3) * s, grey) -- the pecs
			block(m, head + Vector3.new(0, -0.7, -0.15) * s, Vector3.new(1.55, 0.5, 1.3) * s, grey) -- the jaw
			block(m, head + Vector3.new(0, 0.12, -0.67) * s, Vector3.new(1.1, 0.12, 0.05) * s, BLACK) -- brow
			eyes(m, head, s, BLACK)
			block(m, head + Vector3.new(0, 0.75, 0.05) * s, Vector3.new(1.4, 0.3, 1.35) * s, BLACK)
			local aura = makePart(m, { shape = Enum.PartType.Ball, size = Vector3.new(9, 9, 9), cf = CFrame.new(0, 4, 0), color = Color3.fromRGB(255, 220, 90), material = Enum.Material.ForceField, transparency = 0.2, shadow = false })
			aura.Name = "Aura"
		end,
	},
}

local BY_ID: { [string]: BrainrotDef } = {}
local BY_RARITY: { [string]: { BrainrotDef } } = {}
for _, def in BRAINROTS do
	BY_ID[def.id] = def
	BY_RARITY[def.rarity] = BY_RARITY[def.rarity] or {}
	table.insert(BY_RARITY[def.rarity], def)
end

local function formatNumber(n: number): string
	n = math.floor(n)
	local suffixes = { "", "K", "M", "B", "T", "Qa" }
	local i = 1
	local v = n
	while v >= 1000 and i < #suffixes do
		v /= 1000
		i += 1
	end
	if i == 1 then
		return tostring(n)
	end
	return string.format(v < 10 and "%.2f%s" or (v < 100 and "%.1f%s" or "%.0f%s"), v, suffixes[i])
end

local function nameTag(adornee: BasePart, def: BrainrotDef, extra: string?)
	local rarity = RARITIES[def.rarity]
	local gui = Instance.new("BillboardGui")
	gui.Name = "Tag"
	gui.Size = UDim2.fromOffset(180, 62)
	gui.StudsOffsetWorldSpace = Vector3.new(0, def.height + 1.6, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.Adornee = adornee
	local function label(text: string, y: number, h: number, color: Color3, font: Enum.Font)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromOffset(0, y)
		l.Size = UDim2.new(1, 0, 0, h)
		l.Text = text
		l.TextColor3 = color
		l.TextScaled = true
		l.Font = font
		l.TextStrokeTransparency = 0.2
		l.Parent = gui
	end
	label(def.name .. (extra or ""), 0, 24, Color3.new(1, 1, 1), Enum.Font.FredokaOne)
	label(string.upper(def.rarity), 24, 18, rarity.color, Enum.Font.GothamBlack)
	label("$" .. formatNumber(def.cps) .. "/s", 42, 18, Color3.fromRGB(110, 255, 120), Enum.Font.GothamBold)
	gui.Parent = adornee
	return gui
end

local function buildBrainrot(def: BrainrotDef, at: CFrame, extraTag: string?): Model
	local m = Instance.new("Model")
	m.Name = def.name
	local root = makePart(m, { name = "Root", size = Vector3.new(1, 1, 1), cf = CFrame.new(), transparency = 1, shadow = false })
	def.build(m)
	local rarity = RARITIES[def.rarity]
	local glow = Instance.new("PointLight")
	glow.Color = rarity.color
	glow.Range = 6 + rarity.order * 2
	glow.Brightness = 0.6 + rarity.order * 0.25
	glow.Parent = root
	if rarity.order >= 4 then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkle.Color = ColorSequence.new(rarity.color)
		sparkle.Rate = 4 + rarity.order * 2
		sparkle.Lifetime = NumberRange.new(1, 1.6)
		sparkle.Speed = NumberRange.new(1, 3)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Size = NumberSequence.new(0.4, 0)
		sparkle.LightEmission = 1
		sparkle.Parent = root
	end
	m.PrimaryPart = root
	m:SetAttribute("BrainrotId", def.id)
	m:SetAttribute("Rarity", def.rarity)
	nameTag(root, def, extraTag)
	m:PivotTo(at)
	return m
end

--------------------------------------------------------------------------------------------------------
-- The world
--------------------------------------------------------------------------------------------------------

local map = Instance.new("Folder")
map.Name = "Map"
map.Parent = workspace

local field = Instance.new("Folder")
field.Name = "Field"
field.Parent = workspace

local basesFolder = Instance.new("Folder")
basesFolder.Name = "Bases"
basesFolder.Parent = workspace

workspace:SetAttribute("SafeEdge", SAFE_EDGE)
workspace:SetAttribute("FieldEnd", FIELD_END)

local function surfaceSign(part: BasePart, face: Enum.NormalId, text: string, color: Color3, bg: Color3?)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.PixelsPerStud = 40
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.LightInfluence = 0
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundColor3 = bg or Color3.new(0, 0, 0)
	l.BackgroundTransparency = bg and 0 or 1
	l.Text = text
	l.TextColor3 = color
	l.TextScaled = true
	l.Font = Enum.Font.FredokaOne
	l.TextStrokeTransparency = 0
	l.Parent = sg
	sg.Parent = part
end

local function buildWorld()
	-- Safe Zone floor
	local safe = makePart(map, { name = "SafeZoneFloor", size = Vector3.new(SAFE_EDGE - SAFE_START, 0.6, HALF_WIDTH * 2), cf = CFrame.new((SAFE_EDGE + SAFE_START) / 2, 0.3, 0), color = Color3.fromRGB(200, 205, 215), material = Enum.Material.Concrete, collide = true })
	safe:SetAttribute("SafeZone", true)
	-- the main lane through the zone
	makePart(map, { size = Vector3.new(SAFE_EDGE - SAFE_START, 0.62, 12), cf = CFrame.new((SAFE_EDGE + SAFE_START) / 2, 0.31, 0), color = Color3.fromRGB(240, 210, 90), material = Enum.Material.SmoothPlastic })
	-- glowing boundary and the shimmering safety curtain
	makePart(map, { name = "SafeLine", size = Vector3.new(1.2, 0.7, HALF_WIDTH * 2), cf = CFrame.new(SAFE_EDGE, 0.35, 0), color = Color3.fromRGB(60, 255, 120), material = Enum.Material.Neon, shadow = false })
	makePart(map, { name = "SafeCurtain", size = Vector3.new(0.4, 26, HALF_WIDTH * 2), cf = CFrame.new(SAFE_EDGE, 13, 0), color = Color3.fromRGB(80, 255, 150), material = Enum.Material.ForceField, transparency = 0.15, shadow = false })

	-- the arch over the lane
	for _, z in { -14, 14 } do
		makePart(map, { size = Vector3.new(3, 22, 3), cf = CFrame.new(SAFE_EDGE - 2, 11, z), color = Color3.fromRGB(40, 200, 110), material = Enum.Material.SmoothPlastic, collide = true })
	end
	local beam = makePart(map, { name = "SafeSign", size = Vector3.new(3, 5, 31), cf = CFrame.new(SAFE_EDGE - 2, 24, 0), color = Color3.fromRGB(30, 160, 90), collide = true })
	surfaceSign(beam, Enum.NormalId.Right, "SAFE ZONE", Color3.new(1, 1, 1))
	surfaceSign(beam, Enum.NormalId.Left, "BRAINROT ESCAPE DISASTER", Color3.fromRGB(255, 240, 120))

	-- field zones
	for _, zone in ZONES do
		local rarity = RARITIES[zone.rarity]
		makePart(map, { name = zone.rarity .. "Zone", size = Vector3.new(zone.x1 - zone.x0, 0.2, HALF_WIDTH * 2), cf = CFrame.new((zone.x0 + zone.x1) / 2, 0.1, 0), color = zone.floor, material = Enum.Material.Grass, collide = true })
		makePart(map, { size = Vector3.new(0.8, 0.3, HALF_WIDTH * 2), cf = CFrame.new(zone.x0, 0.2, 0), color = rarity.color, material = Enum.Material.Neon, shadow = false })
		for _, z in { -HALF_WIDTH + 6, HALF_WIDTH - 6 } do
			local post = makePart(map, { size = Vector3.new(1, 10, 1), cf = CFrame.new(zone.x0 + 2, 5, z), color = Color3.fromRGB(90, 70, 50), material = Enum.Material.Wood, collide = true })
			local board = makePart(map, { size = Vector3.new(0.6, 4, 14), cf = CFrame.new(zone.x0 + 2, 11, z), color = Color3.fromRGB(30, 30, 40), collide = true })
			surfaceSign(board, Enum.NormalId.Left, string.upper(zone.rarity) .. " ZONE", rarity.color)
			surfaceSign(board, Enum.NormalId.Right, string.upper(zone.rarity) .. " ZONE", rarity.color)
			post.Name = "SignPost"
		end
	end

	-- side walls and the far cliff
	for _, z in { -HALF_WIDTH - 1, HALF_WIDTH + 1 } do
		makePart(map, { name = "Wall", size = Vector3.new(FIELD_END - SAFE_START + 20, 14, 2), cf = CFrame.new((FIELD_END + SAFE_START) / 2 + 10, 7, z), color = Color3.fromRGB(120, 110, 100), material = Enum.Material.Rock, collide = true })
	end
	makePart(map, { name = "BackWall", size = Vector3.new(2, 14, HALF_WIDTH * 2), cf = CFrame.new(SAFE_START - 1, 7, 0), color = Color3.fromRGB(120, 110, 100), material = Enum.Material.Rock, collide = true })
	makePart(map, { name = "Ocean", size = Vector3.new(160, 1, 400), cf = CFrame.new(FIELD_END + 90, -0.4, 0), color = Color3.fromRGB(30, 110, 200), material = Enum.Material.Glass, transparency = 0.25 })
	makePart(map, { name = "Cliff", size = Vector3.new(4, 4, HALF_WIDTH * 2), cf = CFrame.new(FIELD_END + 2, 2, 0), color = Color3.fromRGB(200, 185, 130), material = Enum.Material.Sand, collide = true })

	-- palm trees and rocks for scenery (kept out of the middle lane)
	for _ = 1, 34 do
		local x = rng:NextNumber(12, FIELD_END - 10)
		local z = rng:NextNumber(30, HALF_WIDTH - 4) * (rng:NextInteger(0, 1) == 0 and -1 or 1)
		if rng:NextNumber() < 0.6 then
			local h = rng:NextNumber(9, 15)
			makePart(map, { size = Vector3.new(1.2, h, 1.2), cf = CFrame.new(x, h / 2, z) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-8, 8))), color = Color3.fromRGB(130, 90, 55), material = Enum.Material.Wood, collide = true })
			for i = 1, 5 do
				local a = i / 5 * math.pi * 2
				makePart(map, { size = Vector3.new(6, 0.4, 1.8), cf = CFrame.new(x, h, z) * CFrame.Angles(0, a, math.rad(-20)) * CFrame.new(2.6, 0, 0), color = Color3.fromRGB(60, 160, 60), material = Enum.Material.Grass })
			end
		else
			local d = rng:NextNumber(3, 7)
			makePart(map, { shape = Enum.PartType.Ball, size = Vector3.new(d, d * 0.7, d), cf = CFrame.new(x, d * 0.25, z), color = Color3.fromRGB(110, 110, 115), material = Enum.Material.Slate, collide = true })
		end
	end

	-- the depository pad
	local pad = cylinder(map, DEPOSIT_POS + Vector3.new(0, 0.7, 0), 0.4, DEPOSIT_RADIUS * 2, Color3.fromRGB(255, 200, 40), Enum.Material.Neon)
	pad.Name = "DepositPad"
	local ring = cylinder(map, DEPOSIT_POS + Vector3.new(0, 0.62, 0), 0.3, DEPOSIT_RADIUS * 2 + 2, Color3.fromRGB(60, 50, 20))
	ring.Name = "DepositRing"
	local sign = makePart(map, { name = "DepositSign", size = Vector3.new(1, 1, 1), cf = CFrame.new(DEPOSIT_POS + Vector3.new(0, 7, 0)), transparency = 1, shadow = false })
	local bg = Instance.new("BillboardGui")
	bg.Size = UDim2.fromOffset(260, 70)
	bg.LightInfluence = 0
	bg.MaxDistance = 140
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = "💰 DEPOSIT\nstep here to bank your bag"
	t.TextColor3 = Color3.fromRGB(255, 220, 60)
	t.TextScaled = true
	t.Font = Enum.Font.FredokaOne
	t.TextStrokeTransparency = 0
	t.Parent = bg
	bg.Parent = sign
	local coinFx = Instance.new("ParticleEmitter")
	coinFx.Name = "Coins"
	coinFx.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	coinFx.Color = ColorSequence.new(Color3.fromRGB(255, 215, 60))
	coinFx.Rate = 6
	coinFx.Lifetime = NumberRange.new(1, 2)
	coinFx.Speed = NumberRange.new(4, 8)
	coinFx.SpreadAngle = Vector2.new(25, 25)
	coinFx.Size = NumberSequence.new(0.8, 0)
	coinFx.LightEmission = 1
	coinFx.EmissionDirection = Enum.NormalId.Right -- the pad is a cylinder turned upright, so +X is up
	coinFx.Parent = pad
end

local function buildStall(pos: Vector3, title: string, color: Color3, actionText: string): BasePart
	local stall = Instance.new("Model")
	stall.Name = title
	local counter = makePart(stall, { name = "Counter", size = Vector3.new(8, 3.5, 4), cf = CFrame.new(pos + Vector3.new(0, 1.75 + 0.6, 0)), color = Color3.fromRGB(110, 80, 55), material = Enum.Material.Wood, collide = true })
	for _, dx in { -3.6, 3.6 } do
		makePart(stall, { size = Vector3.new(0.6, 9, 0.6), cf = CFrame.new(pos + Vector3.new(dx, 4.5 + 0.6, 1.6)), color = WHITE, collide = true })
	end
	makePart(stall, { name = "Roof", size = Vector3.new(9, 0.8, 6), cf = CFrame.new(pos + Vector3.new(0, 9.6, 0.6)), color = color, collide = true })
	local board = makePart(stall, { name = "Board", size = Vector3.new(8, 2.4, 0.4), cf = CFrame.new(pos + Vector3.new(0, 11.2, 0.6)), color = Color3.fromRGB(25, 25, 35) })
	surfaceSign(board, Enum.NormalId.Front, title, color)
	surfaceSign(board, Enum.NormalId.Back, title, color)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = title
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter
	stall.Parent = map
	return counter
end

buildWorld()
local shopCounter = buildStall(SHOP_POS, "UPGRADES", Color3.fromRGB(60, 180, 255), "Open Shop")
local rebirthCounter = buildStall(REBIRTH_POS, "REBIRTH", Color3.fromRGB(255, 80, 200), "Rebirth")

-- Lighting extras: a hazy tropical sky, bloom on the neon, a little extra saturation for the brainrot look.
do
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(200, 220, 255)
	atmosphere.Decay = Color3.fromRGB(120, 140, 200)
	atmosphere.Glare = 0.3
	atmosphere.Haze = 1.2
	atmosphere.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.6
	bloom.Size = 30
	bloom.Threshold = 1.6
	bloom.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Saturation = 0.18
	cc.Contrast = 0.06
	cc.Parent = Lighting
end

--------------------------------------------------------------------------------------------------------
-- Remotes
--------------------------------------------------------------------------------------------------------

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local function remote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local StateEvent = remote("State") -- server -> client: the player's whole economy snapshot
local NotifyEvent = remote("Notify") -- server -> client: (text, color?)
local PickupEvent = remote("Pickup") -- server -> client: (id, position)
local DepositEvent = remote("Deposit") -- server -> client: (count, cpsGained, bonus)
local KnockOutEvent = remote("KnockOut") -- server -> client: (lostCount)
local OpenShopEvent = remote("OpenShop") -- server -> client
local BuyUpgradeEvent = remote("BuyUpgrade") -- client -> server: (key)
local RebirthEvent = remote("Rebirth") -- client -> server
remotes.Parent = ReplicatedStorage

--------------------------------------------------------------------------------------------------------
-- Player data
--------------------------------------------------------------------------------------------------------

type PlayerData = {
	cash: number,
	owned: { [string]: number },
	bag: { string },
	levels: { [string]: number },
	rebirths: number,
	plot: number?,
	lastFullNotice: number,
	knockedOut: boolean,
}

local data: { [Player]: PlayerData } = {}

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("BrainrotEscapeDisaster_v1")
	end)
	if ok then
		store = result
	end
end

local function multiplier(d: PlayerData): number
	return 1 + 0.5 * d.rebirths
end

local function cashPerSecond(d: PlayerData): number
	local total = 0
	for id, n in d.owned do
		local def = BY_ID[id]
		if def then
			total += def.cps * n
		end
	end
	return total * multiplier(d)
end

local function capacity(d: PlayerData): number
	return BASE_CAPACITY + d.levels.capacity
end

local function magnetRadius(d: PlayerData): number
	return BASE_MAGNET + d.levels.magnet * 2
end

local function walkSpeed(d: PlayerData): number
	return BASE_SPEED + d.levels.speed * 3
end

local function upgradeCost(key: string, level: number): number
	local u = UPGRADES[key]
	return math.floor(u.base * u.growth ^ level)
end

local function rebirthCost(d: PlayerData): number
	return REBIRTH_BASE_COST * 3 ^ d.rebirths
end

local function ownedCount(d: PlayerData): number
	local n = 0
	for _, c in d.owned do
		n += c
	end
	return n
end

local function snapshot(d: PlayerData)
	local upgrades = {}
	for _, key in UPGRADE_ORDER do
		local lvl = d.levels[key]
		upgrades[key] = { level = lvl, max = UPGRADES[key].max, cost = lvl < UPGRADES[key].max and upgradeCost(key, lvl) or nil }
	end
	local bagNames = {}
	for _, id in d.bag do
		table.insert(bagNames, id)
	end
	return {
		cash = d.cash,
		cps = cashPerSecond(d),
		bag = bagNames,
		capacity = capacity(d),
		owned = ownedCount(d),
		upgrades = upgrades,
		stats = { speed = walkSpeed(d), capacity = capacity(d), magnet = magnetRadius(d) },
		rebirths = d.rebirths,
		multiplier = multiplier(d),
		rebirthCost = rebirthCost(d),
		nextMultiplier = 1 + 0.5 * (d.rebirths + 1),
	}
end

local function pushState(player: Player)
	local d = data[player]
	if not d then
		return
	end
	StateEvent:FireClient(player, snapshot(d))
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		(ls:FindFirstChild("Cash") :: NumberValue).Value = math.floor(d.cash);
		(ls:FindFirstChild("Rebirths") :: IntValue).Value = d.rebirths
	end
end

local function notify(player: Player, text: string, color: Color3?)
	NotifyEvent:FireClient(player, text, color)
end

local function applyCharacterStats(player: Player)
	local d = data[player]
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if d and hum then
		hum.WalkSpeed = walkSpeed(d)
	end
end

--------------------------------------------------------------------------------------------------------
-- Bases: each player gets a plot in the Safe Zone; banked brainrots stand on its pedestals
--------------------------------------------------------------------------------------------------------

local PLOT_CENTERS = {
	Vector3.new(-35, 0, -46), Vector3.new(-35, 0, 46),
	Vector3.new(-62, 0, -46), Vector3.new(-62, 0, 46),
	Vector3.new(-89, 0, -46), Vector3.new(-89, 0, 46),
}
local PEDESTALS_PER_PLOT = 10
local plotOwners: { [number]: Player } = {}
local plotModels: { [number]: Model } = {}

local function pedestalCFrame(plotIndex: number, slot: number): CFrame
	local c = PLOT_CENTERS[plotIndex]
	local col = (slot - 1) % 2
	local row = math.floor((slot - 1) / 2)
	local facing = c.Z < 0 and 0 or math.pi -- face the main lane
	local x = c.X + (col == 0 and -5 or 5)
	local z = c.Z + (c.Z < 0 and 1 or -1) * (-10 + row * 5)
	return CFrame.new(x, 1.6, z) * CFrame.Angles(0, facing + math.pi, 0)
end

local function buildPlot(index: number): Model
	local c = PLOT_CENTERS[index]
	local m = Instance.new("Model")
	m.Name = "Plot" .. index
	makePart(m, { name = "Floor", size = Vector3.new(22, 0.4, 26), cf = CFrame.new(c + Vector3.new(0, 0.8, 0)), color = Color3.fromRGB(70, 75, 95), material = Enum.Material.SmoothPlastic, collide = true })
	makePart(m, { name = "Border", size = Vector3.new(23, 0.3, 27), cf = CFrame.new(c + Vector3.new(0, 0.7, 0)), color = Color3.fromRGB(120, 255, 170), material = Enum.Material.Neon, shadow = false })
	for slot = 1, PEDESTALS_PER_PLOT do
		local cf = pedestalCFrame(index, slot)
		cylinder(m, cf.Position - Vector3.new(0, 0.3, 0), 0.6, 3.6, Color3.fromRGB(230, 230, 240), Enum.Material.Marble)
	end
	local signPart = makePart(m, { name = "Sign", size = Vector3.new(1, 1, 1), cf = CFrame.new(c + Vector3.new(0, 11, 0)), transparency = 1, shadow = false })
	local bg = Instance.new("BillboardGui")
	bg.Name = "OwnerSign"
	bg.Size = UDim2.fromOffset(240, 64)
	bg.LightInfluence = 0
	bg.MaxDistance = 160
	local l = Instance.new("TextLabel")
	l.Name = "Label"
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Text = "Empty Base"
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextScaled = true
	l.Font = Enum.Font.FredokaOne
	l.TextStrokeTransparency = 0
	l.Parent = bg
	bg.Parent = signPart
	local display = Instance.new("Folder")
	display.Name = "Display"
	display.Parent = m
	m.Parent = basesFolder
	return m
end

for i = 1, #PLOT_CENTERS do
	plotModels[i] = buildPlot(i)
end

local function updatePlotSign(player: Player)
	local d = data[player]
	if not d or not d.plot then
		return
	end
	local label = plotModels[d.plot]:FindFirstChild("Sign"):FindFirstChild("OwnerSign"):FindFirstChild("Label") :: TextLabel
	label.Text = string.format("%s's Base\n$%s/s", player.DisplayName, formatNumber(cashPerSecond(d)))
end

local function refreshBase(player: Player)
	local d = data[player]
	if not d or not d.plot then
		return
	end
	local display = plotModels[d.plot]:FindFirstChild("Display") :: Folder
	display:ClearAllChildren()
	local kinds = {}
	for id, n in d.owned do
		if n > 0 and BY_ID[id] then
			table.insert(kinds, { def = BY_ID[id], n = n })
		end
	end
	table.sort(kinds, function(a, b)
		return a.def.cps > b.def.cps
	end)
	for slot = 1, math.min(#kinds, PEDESTALS_PER_PLOT) do
		local k = kinds[slot]
		local model = buildBrainrot(k.def, pedestalCFrame(d.plot, slot), k.n > 1 and (" x" .. k.n) or nil)
		model.Parent = display
	end
	updatePlotSign(player)
end

--------------------------------------------------------------------------------------------------------
-- The field: brainrots spawn in their rarity zone and wait to be caught
--------------------------------------------------------------------------------------------------------

local zoneCounts: { [string]: number } = {}

local function spawnInZone(zone)
	local pool = BY_RARITY[zone.rarity]
	-- within a zone, cheaper brainrots are a bit more common
	local def = pool[1]
	if #pool > 1 and rng:NextNumber() < 0.4 then
		def = pool[2]
	end
	local pos = Vector3.new(rng:NextNumber(zone.x0 + 4, zone.x1 - 4), GROUND_Y, rng:NextNumber(-HALF_WIDTH + 8, HALF_WIDTH - 8))
	local model = buildBrainrot(def, CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	model:SetAttribute("Zone", zone.rarity)
	model.Parent = field
	zoneCounts[zone.rarity] = (zoneCounts[zone.rarity] or 0) + 1
	model.Destroying:Connect(function()
		zoneCounts[zone.rarity] -= 1
	end)
end

local function fillField(max: number?)
	local spawned = 0
	for _, zone in ZONES do
		while (zoneCounts[zone.rarity] or 0) < zone.count do
			spawnInZone(zone)
			spawned += 1
			if max and spawned >= max then
				return
			end
		end
	end
end

fillField()

--------------------------------------------------------------------------------------------------------
-- The tsunami
--------------------------------------------------------------------------------------------------------

local wave = Instance.new("Model")
wave.Name = "Tsunami"
local waveBody = makePart(wave, { name = "Body", size = Vector3.new(WAVE_THICKNESS, 34, HALF_WIDTH * 2 + 6), cf = CFrame.new(0, 17, 0), color = Color3.fromRGB(35, 120, 225), material = Enum.Material.Glass, transparency = 0.18, reflectance = 0.1 })
makePart(wave, { name = "Crest", shape = Enum.PartType.Cylinder, size = Vector3.new(HALF_WIDTH * 2 + 8, 14, 14), cf = CFrame.new(-WAVE_THICKNESS / 2 + 2, 33, 0) * CFrame.Angles(0, math.rad(90), 0), color = Color3.fromRGB(70, 170, 255), material = Enum.Material.Glass, transparency = 0.15 })
local waveFoam = makePart(wave, { name = "Foam", size = Vector3.new(6, 3, HALF_WIDTH * 2 + 8), cf = CFrame.new(-WAVE_THICKNESS / 2 - 2, 38.5, 0), color = WHITE, material = Enum.Material.SmoothPlastic, transparency = 0.1 })
local waveFront = makePart(wave, { name = "Front", size = Vector3.new(4, 8, HALF_WIDTH * 2 + 6), cf = CFrame.new(-WAVE_THICKNESS / 2 - 1, 4, 0), color = WHITE, material = Enum.Material.SmoothPlastic, transparency = 0.25 })
do
	local spray = Instance.new("ParticleEmitter")
	spray.Name = "Spray"
	spray.Texture = "rbxasset://textures/particles/smoke_main.dds"
	spray.Color = ColorSequence.new(Color3.fromRGB(230, 245, 255))
	spray.Rate = 120
	spray.Lifetime = NumberRange.new(0.8, 1.6)
	spray.Speed = NumberRange.new(10, 22)
	spray.SpreadAngle = Vector2.new(40, 60)
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 8) })
	spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	spray.EmissionDirection = Enum.NormalId.Left
	spray.Enabled = false
	spray.Parent = waveFoam
	local spray2 = spray:Clone()
	spray2.EmissionDirection = Enum.NormalId.Top
	spray2.Parent = waveFront
end
wave.PrimaryPart = waveBody
local WAVE_PARK = CFrame.new(FIELD_END + 140, -60, 0)
wave:PivotTo(WAVE_PARK)
wave.Parent = workspace

local function setWaveVisible(on: boolean)
	for _, p in wave:GetDescendants() do
		if p:IsA("ParticleEmitter") then
			p.Enabled = on
		end
	end
end

local waveCount = 0
local forceWave = false

workspace:SetAttribute("TsunamiPhase", "calm")
workspace:SetAttribute("WaveNumber", 0)

local function knockOut(player: Player)
	local d = data[player]
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not d or not hum or not hrp or hum.Health <= 0 or d.knockedOut then
		return
	end
	d.knockedOut = true
	local lost = #d.bag
	table.clear(d.bag)
	hrp.AssemblyLinearVelocity = Vector3.new(-90, 70, rng:NextNumber(-20, 20))
	hrp.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-8, 8), 6, rng:NextNumber(-8, 8))
	task.delay(0.15, function()
		if hum.Parent then
			hum.Health = 0
		end
	end)
	KnockOutEvent:FireClient(player, lost)
	pushState(player)
end

local function runWave()
	waveCount += 1
	workspace:SetAttribute("WaveNumber", waveCount)
	local speed = math.min(WAVE_BASE_SPEED + (waveCount - 1) * WAVE_SPEED_STEP, WAVE_MAX_SPEED)
	workspace:SetAttribute("WaveSpeed", speed)
	workspace:SetAttribute("TsunamiPhase", "active")
	local x = FIELD_END + WAVE_THICKNESS
	wave:PivotTo(CFrame.new(x, 17, 0))
	setWaveVisible(true)
	local stopAt = SAFE_EDGE + WAVE_THICKNESS / 2 + 1 -- the wave crashes against the safety curtain
	while x > stopAt do
		local dt = RunService.Heartbeat:Wait()
		x = math.max(x - speed * dt, stopAt)
		wave:PivotTo(CFrame.new(x, 17 + math.sin(os.clock() * 3) * 0.6, 0))
		local front = x - WAVE_THICKNESS / 2
		workspace:SetAttribute("WaveFront", front)
		for _, player in Players:GetPlayers() do
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp and hrp.Position.X > SAFE_EDGE and hrp.Position.X > front then
				knockOut(player)
			end
		end
		-- brainrots in the wave's path are washed away
		for _, item in field:GetChildren() do
			if item:IsA("Model") and item:GetPivot().Position.X > front then
				item:Destroy()
			end
		end
	end
	-- the wave crashes and drains away
	workspace:SetAttribute("TsunamiPhase", "receding")
	for i = 1, 40 do
		wave:PivotTo(CFrame.new(stopAt, 17 - i * 1.1, 0))
		task.wait(0.03)
	end
	setWaveVisible(false)
	wave:PivotTo(WAVE_PARK)
	workspace:SetAttribute("WaveFront", nil)
	for _, d in data do
		d.knockedOut = false
	end
end

local function waitUntil(t: number)
	while workspace:GetServerTimeNow() < t and not forceWave do
		task.wait(0.2)
	end
end

task.spawn(function()
	while true do
		local gap = waveCount == 0 and FIRST_WAVE_DELAY or rng:NextInteger(WAVE_GAP_MIN, WAVE_GAP_MAX)
		local warnAt = workspace:GetServerTimeNow() + gap
		workspace:SetAttribute("TsunamiPhase", "calm")
		workspace:SetAttribute("TsunamiAt", warnAt + WARNING_TIME)
		waitUntil(warnAt)
		forceWave = false
		local hitAt = workspace:GetServerTimeNow() + WARNING_TIME
		workspace:SetAttribute("TsunamiAt", hitAt)
		workspace:SetAttribute("TsunamiPhase", "warning")
		while workspace:GetServerTimeNow() < hitAt do
			task.wait(0.1)
		end
		runWave()
		task.wait(1.5)
		fillField(8) -- the field starts to regrow; the spawner loop finishes it
	end
end)

-- Keep the field stocked between waves.
task.spawn(function()
	while true do
		task.wait(1.5)
		if workspace:GetAttribute("TsunamiPhase") ~= "active" then
			fillField(2)
		end
	end
end)

--------------------------------------------------------------------------------------------------------
-- Catching, banking and income
--------------------------------------------------------------------------------------------------------

local function deposit(player: Player, d: PlayerData)
	local count = #d.bag
	if count == 0 then
		return
	end
	local before = cashPerSecond(d)
	for _, id in d.bag do
		d.owned[id] = (d.owned[id] or 0) + 1
	end
	table.clear(d.bag)
	local gained = cashPerSecond(d) - before
	local bonus = math.floor(gained * 3) -- a banking bonus: three seconds of the new income up front
	d.cash += bonus
	refreshBase(player)
	DepositEvent:FireClient(player, count, gained, bonus)
	pushState(player)
end

local function collect(player: Player, d: PlayerData, item: Model)
	local id = item:GetAttribute("BrainrotId")
	local def = id and BY_ID[id]
	if not def then
		return
	end
	table.insert(d.bag, id)
	PickupEvent:FireClient(player, id, item:GetPivot().Position)
	item:Destroy()
	pushState(player)
end

task.spawn(function()
	while true do
		task.wait(0.1)
		local items = field:GetChildren()
		for player, d in data do
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hrp and hum and hum.Health > 0 then
				local pos = hrp.Position
				-- the depository
				local toPad = Vector3.new(pos.X - DEPOSIT_POS.X, 0, pos.Z - DEPOSIT_POS.Z).Magnitude
				if toPad <= DEPOSIT_RADIUS and #d.bag > 0 then
					deposit(player, d)
				end
				-- catching
				if pos.X > SAFE_EDGE then
					local radius = magnetRadius(d)
					for _, item in items do
						if item.Parent == field and item:IsA("Model") then
							local ip = item:GetPivot().Position
							if Vector3.new(ip.X - pos.X, 0, ip.Z - pos.Z).Magnitude <= radius then
								if #d.bag >= capacity(d) then
									if os.clock() - d.lastFullNotice > 3 then
										d.lastFullNotice = os.clock()
										notify(player, "🎒 Bag full! Run back to the Safe Zone and deposit.", Color3.fromRGB(255, 170, 60))
									end
									break
								end
								collect(player, d, item)
							end
						end
					end
				end
			end
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(1)
		for player, d in data do
			d.cash += cashPerSecond(d)
			pushState(player)
		end
	end
end)

--------------------------------------------------------------------------------------------------------
-- Upgrades and rebirth
--------------------------------------------------------------------------------------------------------

BuyUpgradeEvent.OnServerEvent:Connect(function(player: Player, key: any)
	local d = data[player]
	if not d or type(key) ~= "string" or not UPGRADES[key] then
		return
	end
	local lvl = d.levels[key]
	if lvl >= UPGRADES[key].max then
		notify(player, UPGRADES[key].name .. " is maxed out!", Color3.fromRGB(255, 220, 90))
		return
	end
	local cost = upgradeCost(key, lvl)
	if d.cash < cost then
		notify(player, "Not enough cash for " .. UPGRADES[key].name .. " ($" .. formatNumber(cost) .. ")", Color3.fromRGB(255, 90, 90))
		return
	end
	d.cash -= cost
	d.levels[key] = lvl + 1
	applyCharacterStats(player)
	notify(player, "⬆ " .. UPGRADES[key].name .. " upgraded to level " .. (lvl + 1) .. "!", Color3.fromRGB(110, 255, 140))
	pushState(player)
end)

local function rebirth(player: Player)
	local d = data[player]
	if not d then
		return
	end
	local cost = rebirthCost(d)
	if d.cash < cost then
		notify(player, "Rebirth needs $" .. formatNumber(cost) .. "!", Color3.fromRGB(255, 90, 90))
		return
	end
	d.rebirths += 1
	d.cash = 0
	table.clear(d.owned)
	table.clear(d.bag)
	for _, key in UPGRADE_ORDER do
		d.levels[key] = 0
	end
	refreshBase(player)
	applyCharacterStats(player)
	notify(player, string.format("♻ REBIRTH %d! Income multiplier is now x%.1f", d.rebirths, multiplier(d)), Color3.fromRGB(255, 120, 230))
	pushState(player)
end

RebirthEvent.OnServerEvent:Connect(rebirth)

shopCounter:FindFirstChildOfClass("ProximityPrompt").Triggered:Connect(function(player)
	OpenShopEvent:FireClient(player, "shop")
end)
rebirthCounter:FindFirstChildOfClass("ProximityPrompt").Triggered:Connect(function(player)
	OpenShopEvent:FireClient(player, "rebirth")
end)

--------------------------------------------------------------------------------------------------------
-- Joining and leaving
--------------------------------------------------------------------------------------------------------

local function newData(): PlayerData
	return {
		cash = 0,
		owned = {},
		bag = {},
		levels = { speed = 0, capacity = 0, magnet = 0 },
		rebirths = 0,
		plot = nil,
		lastFullNotice = 0,
		knockedOut = false,
	}
end

local function load(player: Player): PlayerData
	local d = newData()
	if store then
		local ok, saved = pcall(function()
			return (store :: DataStore):GetAsync("p_" .. player.UserId)
		end)
		if ok and type(saved) == "table" then
			d.cash = tonumber(saved.cash) or 0
			d.rebirths = tonumber(saved.rebirths) or 0
			if type(saved.owned) == "table" then
				for id, n in saved.owned do
					if BY_ID[id] and tonumber(n) then
						d.owned[id] = tonumber(n) :: number
					end
				end
			end
			if type(saved.levels) == "table" then
				for _, key in UPGRADE_ORDER do
					d.levels[key] = math.clamp(tonumber(saved.levels[key]) or 0, 0, UPGRADES[key].max)
				end
			end
		end
	end
	return d
end

local function save(player: Player)
	local d = data[player]
	if not d or not store then
		return
	end
	pcall(function()
		(store :: DataStore):SetAsync("p_" .. player.UserId, { cash = d.cash, owned = d.owned, levels = d.levels, rebirths = d.rebirths })
	end)
end

local function onCharacter(player: Player, char: Model)
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	applyCharacterStats(player)
	local d = data[player]
	if d then
		d.knockedOut = false
	end
	hum.Died:Connect(function()
		local dd = data[player]
		if dd and #dd.bag > 0 then
			table.clear(dd.bag)
			pushState(player)
		end
	end)
end

local function onPlayerAdded(player: Player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local cash = Instance.new("NumberValue")
	cash.Name = "Cash"
	cash.Parent = ls
	local rb = Instance.new("IntValue")
	rb.Name = "Rebirths"
	rb.Parent = ls
	ls.Parent = player

	local d = load(player)
	data[player] = d
	for i = 1, #PLOT_CENTERS do
		if not plotOwners[i] then
			plotOwners[i] = player
			d.plot = i
			break
		end
	end
	refreshBase(player)

	player.CharacterAdded:Connect(function(char)
		onCharacter(player, char)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
	pushState(player)
	notify(player, "Catch brainrots in the field, bank them at the 💰 pad, and RUN when the tsunami comes!", Color3.fromRGB(120, 220, 255))
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in Players:GetPlayers() do
	task.spawn(onPlayerAdded, p)
end

Players.PlayerRemoving:Connect(function(player)
	save(player)
	local d = data[player]
	if d and d.plot then
		plotOwners[d.plot] = nil
		local m = plotModels[d.plot];
		(m:FindFirstChild("Display") :: Folder):ClearAllChildren();
		((m:FindFirstChild("Sign") :: BasePart):FindFirstChild("OwnerSign"):FindFirstChild("Label") :: TextLabel).Text = "Empty Base"
	end
	data[player] = nil
end)

game:BindToClose(function()
	if RunService:IsStudio() then
		return
	end
	for _, p in Players:GetPlayers() do
		save(p)
	end
end)

-- Periodic autosave
task.spawn(function()
	while true do
		task.wait(90)
		for _, p in Players:GetPlayers() do
			save(p)
		end
	end
end)

--------------------------------------------------------------------------------------------------------
-- Tour hooks (see Tour.luau and TOUR.json)
--------------------------------------------------------------------------------------------------------

Tour.hooks.tsunami = function()
	forceWave = true
end
Tour.hooks.cash = function(amount)
	for player, d in data do
		d.cash += amount
		pushState(player)
	end
end
Tour.hooks.bank = function(n)
	for player, d in data do
		for _ = 1, n do
			local def = BRAINROTS[rng:NextInteger(1, #BRAINROTS)]
			table.insert(d.bag, def.id)
		end
		deposit(player, d)
	end
end

print("[Brainrot Escape Disaster] server ready —", #BRAINROTS, "brainrots,", #ZONES, "zones")
