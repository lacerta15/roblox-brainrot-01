-- init.server.luau
-- Server-side game logic for Brainrot Escape Disaster: zones, brainrot spawning,
-- collection/banking, obstacles, the tsunami disaster loop, and the Temple of
-- GigaChad endgame (Sacred Relic escape).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Tour = require(ServerScriptService.Server:WaitForChild("Tour"))

--------------------------------------------------------------------------------
-- Remotes
--------------------------------------------------------------------------------

local remotesFolder = Instance.new("Folder")
remotesFolder.Name = "BrainrotRemotes"
remotesFolder.Parent = ReplicatedStorage

local function makeRemote(name: string): RemoteEvent
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotesFolder
	return remote
end

local UpgradeSpeed = makeRemote("UpgradeSpeed")
local UpgradeBag = makeRemote("UpgradeBag")
local UpgradeMagnet = makeRemote("UpgradeMagnet")
local RebirthRemote = makeRemote("Rebirth")
local TsunamiWarning = makeRemote("TsunamiWarning")
local TsunamiResolved = makeRemote("TsunamiResolved")
local SafeZoneEntered = makeRemote("SafeZoneEntered")
local SafeZoneExited = makeRemote("SafeZoneExited")
local VictoryAchieved = makeRemote("VictoryAchieved")

--------------------------------------------------------------------------------
-- Zone boundaries (by world Z)
--------------------------------------------------------------------------------

local ZONES = {
	SafeZone = { minZ = -math.huge, maxZ = 0 },
	Common = { minZ = 0, maxZ = 100 },
	Rare = { minZ = 100, maxZ = 200 },
	Epic = { minZ = 200, maxZ = 300 },
	Legendary = { minZ = 300, maxZ = 420 },
	Temple = { minZ = 420, maxZ = 500 },
}

local function zoneAt(z: number): string
	if z <= 0 then
		return "SafeZone"
	elseif z < 100 then
		return "Common"
	elseif z < 200 then
		return "Rare"
	elseif z < 300 then
		return "Epic"
	elseif z < 420 then
		return "Legendary"
	else
		return "Temple"
	end
end

--------------------------------------------------------------------------------
-- Brainrot definitions
--------------------------------------------------------------------------------

type BrainrotDef = {
	name: string,
	rarity: string,
	income: number,
	color: Color3,
	zone: string,
}

local BRAINROTS: { BrainrotDef } = {
	{ name = "Skibidi Toilet", rarity = "Common", income = 5, color = Color3.fromRGB(230, 230, 230), zone = "Common" },
	{ name = "Mewing Cat", rarity = "Common", income = 12, color = Color3.fromRGB(200, 180, 140), zone = "Common" },
	{ name = "Grimace Shake", rarity = "Rare", income = 35, color = Color3.fromRGB(140, 60, 200), zone = "Rare" },
	{ name = "Looksmaxxer", rarity = "Rare", income = 80, color = Color3.fromRGB(80, 160, 220), zone = "Rare" },
	{ name = "Baby Gronk", rarity = "Epic", income = 200, color = Color3.fromRGB(220, 170, 40), zone = "Epic" },
	{ name = "GigaChad", rarity = "Legendary", income = 1000, color = Color3.fromRGB(255, 215, 0), zone = "Legendary" },
}

local brainrotsFolder = Instance.new("Folder")
brainrotsFolder.Name = "Brainrots"
brainrotsFolder.Parent = Workspace

local function spawnBrainrot(def: BrainrotDef)
	local bounds = ZONES[def.zone]
	local z = bounds.minZ + math.random() * (bounds.maxZ - bounds.minZ)
	local x = (math.random() - 0.5) * 260

	local part = Instance.new("Part")
	part.Name = def.name
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(4, 4, 4)
	part.Material = Enum.Material.Neon
	part.Color = def.color
	part.Anchored = true
	part.CanCollide = false
	part.Position = Vector3.new(x, 3, z)
	part:SetAttribute("Rarity", def.rarity)
	part:SetAttribute("Income", def.income)
	part:SetAttribute("BrainrotName", def.name)
	part.Parent = brainrotsFolder

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NameTag"
	billboard.Size = UDim2.new(0, 160, 0, 40)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.3
	label.Text = string.format("%s\n$%d/s", def.name, def.income)
	label.Parent = billboard

	return part
end

local function respawnBrainrot(def: BrainrotDef)
	task.delay(8, function()
		spawnBrainrot(def)
	end)
end

for _, def in ipairs(BRAINROTS) do
	for _ = 1, 6 do
		spawnBrainrot(def)
	end
end

--------------------------------------------------------------------------------
-- Player state
--------------------------------------------------------------------------------

type PlayerState = {
	bag: { BrainrotDef },
	bagCapacity: number,
	magnetRadius: number,
	rebirths: number,
	rebirthMultiplier: number,
	carryingRelic: boolean,
	inSafeZone: boolean,
}

local playerStates: { [Player]: PlayerState } = {}

local BASE_BAG_CAPACITY = 3
local SPEED_UPGRADE_COST = 500
local BAG_UPGRADE_COST = 1500
local MAGNET_UPGRADE_COST = 1000
local REBIRTH_COST = 25000
local REBIRTH_MULTIPLIER_STEP = 0.5

local function setupPlayer(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local cash = Instance.new("NumberValue")
	cash.Name = "Cash"
	cash.Value = 0
	cash.Parent = leaderstats

	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Value = 0
	wins.Parent = leaderstats

	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Value = 0
	rebirths.Parent = leaderstats

	local bagCount = Instance.new("IntValue")
	bagCount.Name = "BagCount"
	bagCount.Value = 0
	bagCount.Parent = player

	local bagCapacity = Instance.new("IntValue")
	bagCapacity.Name = "BagCapacity"
	bagCapacity.Value = BASE_BAG_CAPACITY
	bagCapacity.Parent = player

	local incomePerSecond = Instance.new("NumberValue")
	incomePerSecond.Name = "IncomePerSecond"
	incomePerSecond.Value = 0
	incomePerSecond.Parent = player

	local rebirthMultiplier = Instance.new("NumberValue")
	rebirthMultiplier.Name = "RebirthMultiplier"
	rebirthMultiplier.Value = 1
	rebirthMultiplier.Parent = player

	playerStates[player] = {
		bag = {},
		bagCapacity = BASE_BAG_CAPACITY,
		magnetRadius = 6,
		rebirths = 0,
		rebirthMultiplier = 1,
		carryingRelic = false,
		inSafeZone = false,
	}
end

local function teardownPlayer(player: Player)
	playerStates[player] = nil
end

Players.PlayerAdded:Connect(setupPlayer)
Players.PlayerRemoving:Connect(teardownPlayer)

local function refreshIncome(player: Player)
	local state = playerStates[player]
	if not state then
		return
	end
	local total = 0
	for _, def in ipairs(state.bag) do
		total += def.income
	end
	local income = player:FindFirstChild("IncomePerSecond")
	if income then
		income.Value = total * state.rebirthMultiplier
	end
end

--------------------------------------------------------------------------------
-- Collection logic
--------------------------------------------------------------------------------

local function onBrainrotTouched(part: BasePart, def: BrainrotDef, otherPart: BasePart)
	local character = otherPart.Parent
	if not character then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end
	local state = playerStates[player]
	if not state then
		return
	end
	if #state.bag >= state.bagCapacity then
		return
	end
	if not part.Parent then
		return
	end

	table.insert(state.bag, def)
	local bagCount = player:FindFirstChild("BagCount")
	if bagCount then
		bagCount.Value = #state.bag
	end
	refreshIncome(player)

	part:Destroy()
	respawnBrainrot(def)
end

brainrotsFolder.ChildAdded:Connect(function(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local brainrotName = part:GetAttribute("BrainrotName")
	local def
	for _, d in ipairs(BRAINROTS) do
		if d.name == brainrotName then
			def = d
			break
		end
	end
	if not def then
		return
	end
	part.Touched:Connect(function(otherPart)
		onBrainrotTouched(part, def, otherPart)
	end)
end)

for _, part in ipairs(brainrotsFolder:GetChildren()) do
	local brainrotName = part:GetAttribute("BrainrotName")
	for _, def in ipairs(BRAINROTS) do
		if def.name == brainrotName then
			part.Touched:Connect(function(otherPart)
				onBrainrotTouched(part, def, otherPart)
			end)
		end
	end
end

--------------------------------------------------------------------------------
-- Safe Zone base: banking + per-second income
--------------------------------------------------------------------------------

local safeZoneBase = Instance.new("Part")
safeZoneBase.Name = "SafeZoneBase"
safeZoneBase.Anchored = true
safeZoneBase.CanCollide = true
safeZoneBase.Material = Enum.Material.Neon
safeZoneBase.Color = Color3.fromRGB(80, 220, 255)
safeZoneBase.Size = Vector3.new(30, 1, 30)
safeZoneBase.Position = Vector3.new(0, 0.5, -30)
safeZoneBase.Parent = Workspace

local playersInSafeZone: { [Player]: boolean } = {}

local function bankPlayer(player: Player)
	local state = playerStates[player]
	if not state or #state.bag == 0 then
		return
	end
	local total = 0
	for _, def in ipairs(state.bag) do
		total += def.income
	end
	local cash = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Cash")
	if cash then
		cash.Value += total * state.rebirthMultiplier
	end
	table.clear(state.bag)
	local bagCount = player:FindFirstChild("BagCount")
	if bagCount then
		bagCount.Value = 0
	end
	refreshIncome(player)

	if state.carryingRelic then
		state.carryingRelic = false
		local wins = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Wins")
		if wins then
			wins.Value += 1
		end
		if cash then
			cash.Value += 50000
		end
		VictoryAchieved:FireClient(player)
		VictoryAchieved:FireAllClients()
	end
end

safeZoneBase.Touched:Connect(function(otherPart)
	local character = otherPart.Parent
	if not character then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end
	bankPlayer(player)
end)

Tour.hooks["bank"] = function(arg)
	for player in pairs(playerStates) do
		bankPlayer(player)
	end
	return true
end

--------------------------------------------------------------------------------
-- Zone tracking for Safe Zone entry/exit notifications
--------------------------------------------------------------------------------

RunService.Heartbeat:Connect(function()
	for player, state in pairs(playerStates) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			local inSafeZone = root.Position.Z <= 0
			if inSafeZone ~= state.inSafeZone then
				state.inSafeZone = inSafeZone
				if inSafeZone then
					SafeZoneEntered:FireClient(player)
				else
					SafeZoneExited:FireClient(player)
				end
			end
		end
	end
end)

--------------------------------------------------------------------------------
-- Shop: upgrades + rebirth
--------------------------------------------------------------------------------

local function tryCharge(player: Player, cost: number): boolean
	local cash = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Cash")
	if not cash or cash.Value < cost then
		return false
	end
	cash.Value -= cost
	return true
end

UpgradeSpeed.OnServerEvent:Connect(function(player)
	if not tryCharge(player, SPEED_UPGRADE_COST) then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed += 4
	end
end)

UpgradeBag.OnServerEvent:Connect(function(player)
	local state = playerStates[player]
	if not state then
		return
	end
	if not tryCharge(player, BAG_UPGRADE_COST) then
		return
	end
	state.bagCapacity += 1
	local bagCapacity = player:FindFirstChild("BagCapacity")
	if bagCapacity then
		bagCapacity.Value = state.bagCapacity
	end
end)

UpgradeMagnet.OnServerEvent:Connect(function(player)
	local state = playerStates[player]
	if not state then
		return
	end
	if not tryCharge(player, MAGNET_UPGRADE_COST) then
		return
	end
	state.magnetRadius += 5
end)

RebirthRemote.OnServerEvent:Connect(function(player)
	local state = playerStates[player]
	if not state then
		return
	end
	if not tryCharge(player, REBIRTH_COST) then
		return
	end
	state.rebirths += 1
	state.rebirthMultiplier += REBIRTH_MULTIPLIER_STEP
	state.bagCapacity = BASE_BAG_CAPACITY
	table.clear(state.bag)

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		leaderstats.Rebirths.Value = state.rebirths
	end
	local bagCapacity = player:FindFirstChild("BagCapacity")
	if bagCapacity then
		bagCapacity.Value = state.bagCapacity
	end
	local bagCount = player:FindFirstChild("BagCount")
	if bagCount then
		bagCount.Value = 0
	end
	local rebirthMultiplier = player:FindFirstChild("RebirthMultiplier")
	if rebirthMultiplier then
		rebirthMultiplier.Value = state.rebirthMultiplier
	end
	refreshIncome(player)

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 16
	end
end)

--------------------------------------------------------------------------------
-- 3D Obstacles
--------------------------------------------------------------------------------

local obstaclesFolder = Instance.new("Folder")
obstaclesFolder.Name = "Obstacles"
obstaclesFolder.Parent = Workspace

-- Jump pads
local JUMP_PAD_POSITIONS = {
	Vector3.new(-60, 1, 40),
	Vector3.new(40, 1, 150),
	Vector3.new(-30, 1, 260),
}

for i, position in ipairs(JUMP_PAD_POSITIONS) do
	local pad = Instance.new("Part")
	pad.Name = "JumpPad" .. i
	pad.Anchored = true
	pad.CanCollide = true
	pad.Material = Enum.Material.Neon
	pad.Color = Color3.fromRGB(0, 230, 230)
	pad.Size = Vector3.new(10, 1, 10)
	pad.Position = position
	pad.Parent = obstaclesFolder

	local debounce: { [Player]: boolean } = {}
	pad.Touched:Connect(function(otherPart)
		local character = otherPart.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player or debounce[player] then
			return
		end
		local humanoidRoot = character:FindFirstChild("HumanoidRootPart")
		if not humanoidRoot then
			return
		end
		debounce[player] = true
		humanoidRoot.AssemblyLinearVelocity = Vector3.new(0, 85, 45)
		task.delay(1, function()
			debounce[player] = nil
		end)
	end)
end

-- Speed boosts
local SPEED_BOOST_POSITIONS = {
	Vector3.new(20, 0.5, 70),
	Vector3.new(-40, 0.5, 190),
}

for i, position in ipairs(SPEED_BOOST_POSITIONS) do
	local strip = Instance.new("Part")
	strip.Name = "SpeedBoost" .. i
	strip.Anchored = true
	strip.CanCollide = false
	strip.Material = Enum.Material.Neon
	strip.Color = Color3.fromRGB(255, 230, 0)
	strip.Size = Vector3.new(14, 0.3, 14)
	strip.Position = position
	strip.Parent = obstaclesFolder

	local debounce: { [Player]: boolean } = {}
	strip.Touched:Connect(function(otherPart)
		local character = otherPart.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player or debounce[player] then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		debounce[player] = true
		local original = humanoid.WalkSpeed
		humanoid.WalkSpeed = original + 20
		task.delay(3, function()
			if humanoid and humanoid.Parent then
				humanoid.WalkSpeed = original
			end
			debounce[player] = nil
		end)
	end)
end

-- Grimace Acid Lake (hazard pit) at Z = 250, with stepping stones
local acidLake = Instance.new("Part")
acidLake.Name = "GrimaceAcidLake"
acidLake.Anchored = true
acidLake.CanCollide = false
acidLake.Material = Enum.Material.Neon
acidLake.Color = Color3.fromRGB(150, 40, 200)
acidLake.Transparency = 0.2
acidLake.Size = Vector3.new(200, 1, 30)
acidLake.Position = Vector3.new(0, 0.2, 250)
acidLake.Parent = obstaclesFolder

local STEPPING_STONE_OFFSETS = { -80, -48, -16, 16, 48, 80 }
for i, offsetX in ipairs(STEPPING_STONE_OFFSETS) do
	local stone = Instance.new("Part")
	stone.Name = "SteppingStone" .. i
	stone.Anchored = true
	stone.CanCollide = true
	stone.Material = Enum.Material.Rock
	stone.Color = Color3.fromRGB(90, 80, 70)
	stone.Size = Vector3.new(8, 1.2, 8)
	stone.Position = Vector3.new(offsetX, 0.8, 250)
	stone.Parent = obstaclesFolder
end

local function killAndRespawn(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = 0
	end
end

acidLake.Touched:Connect(function(otherPart)
	local character = otherPart.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	if player then
		killAndRespawn(player)
	end
end)

-- Spinning hazard lasers
local LASER_POSITIONS = {
	Vector3.new(0, 4, 110),
	Vector3.new(0, 4, 320),
}

for i, position in ipairs(LASER_POSITIONS) do
	local pivot = Instance.new("Part")
	pivot.Name = "LaserPivot" .. i
	pivot.Anchored = true
	pivot.CanCollide = false
	pivot.Transparency = 1
	pivot.Size = Vector3.new(1, 1, 1)
	pivot.Position = position
	pivot.Parent = obstaclesFolder

	local beam = Instance.new("Part")
	beam.Name = "Laser" .. i
	beam.Anchored = true
	beam.CanCollide = true
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(255, 20, 20)
	beam.Size = Vector3.new(70, 1.5, 1.5)
	beam.Position = position
	beam.Parent = obstaclesFolder

	task.spawn(function()
		local angle = 0
		while beam.Parent do
			angle += math.rad(90) * RunService.Heartbeat:Wait()
			beam.CFrame = CFrame.new(position) * CFrame.Angles(0, angle, 0)
			local character = nil
			for _, basePart in ipairs(beam:GetTouchingParts()) do
				local parent = basePart.Parent
				local player = parent and Players:GetPlayerFromCharacter(parent)
				if player then
					killAndRespawn(player)
				end
			end
		end
	end)
end

-- Caseoh Boulders across the run
local BOULDER_POSITIONS = {
	Vector3.new(-20, 4, 90),
	Vector3.new(30, 4, 170),
	Vector3.new(-10, 4, 280),
	Vector3.new(15, 4, 360),
}

for i, position in ipairs(BOULDER_POSITIONS) do
	local boulder = Instance.new("Part")
	boulder.Name = "CaseohBoulder" .. i
	boulder.Shape = Enum.PartType.Ball
	boulder.Anchored = true
	boulder.CanCollide = true
	boulder.Material = Enum.Material.Rock
	boulder.Color = Color3.fromRGB(120, 100, 80)
	boulder.Size = Vector3.new(8, 8, 8)
	boulder.Position = position
	boulder.Parent = obstaclesFolder
end

--------------------------------------------------------------------------------
-- Tsunami disaster system
--------------------------------------------------------------------------------

local TSUNAMI_INTERVAL = 60
local TSUNAMI_WARNING_LEAD = 10

local function playSiren()
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://9125568486"
	sound.Volume = 1
	sound.Parent = Workspace
	sound:Play()
	Debris:AddItem(sound, 6)
end

local function playAlarm()
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://9125568016"
	sound.Volume = 1
	sound.Parent = Workspace
	sound:Play()
	Debris:AddItem(sound, 4)
end

local function sweepTsunami()
	local wave = Instance.new("Part")
	wave.Name = "TsunamiWave"
	wave.Anchored = true
	wave.CanCollide = false
	wave.Material = Enum.Material.Neon
	wave.Color = Color3.fromRGB(30, 100, 220)
	wave.Transparency = 0.15
	wave.Size = Vector3.new(320, 40, 10)
	wave.Position = Vector3.new(0, 20, 500)
	wave.Parent = Workspace

	local hitPlayers: { [Player]: boolean } = {}

	local connection
	connection = wave.Touched:Connect(function(otherPart)
		local character = otherPart.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player or hitPlayers[player] then
			return
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root.Position.Z > 0 then
			hitPlayers[player] = true
			killAndRespawn(player)
		end
	end)

	local duration = 6
	local startZ = 500
	local endZ = 0
	local startTime = os.clock()
	local heartbeatConn
	heartbeatConn = RunService.Heartbeat:Connect(function()
		local alpha = math.min(1, (os.clock() - startTime) / duration)
		local z = startZ + (endZ - startZ) * alpha
		wave.Position = Vector3.new(0, 20, z)
		if alpha >= 1 then
			heartbeatConn:Disconnect()
			connection:Disconnect()
			wave:Destroy()
		end
	end)
end

local function runTsunamiCycle()
	playSiren()
	TsunamiWarning:FireAllClients()
	task.wait(TSUNAMI_WARNING_LEAD)
	sweepTsunami()
	task.wait(1)
	TsunamiResolved:FireAllClients(TSUNAMI_INTERVAL)
end

Tour.hooks["tsunami"] = function(arg)
	task.spawn(runTsunamiCycle)
	return true
end

task.spawn(function()
	while true do
		task.wait(TSUNAMI_INTERVAL)
		runTsunamiCycle()
	end
end)

--------------------------------------------------------------------------------
-- Endgame: Temple of GigaChad & Sacred Relic
--------------------------------------------------------------------------------

local temple = Instance.new("Part")
temple.Name = "TempleOfGigaChad"
temple.Anchored = true
temple.CanCollide = true
temple.Material = Enum.Material.Marble
temple.Color = Color3.fromRGB(230, 220, 200)
temple.Size = Vector3.new(60, 40, 60)
temple.Position = Vector3.new(0, 20, 460)
temple.Parent = Workspace

local templeLabel = Instance.new("BillboardGui")
templeLabel.Size = UDim2.new(0, 240, 0, 50)
templeLabel.StudsOffset = Vector3.new(0, 25, 0)
templeLabel.AlwaysOnTop = true
templeLabel.Parent = temple

local templeLabelText = Instance.new("TextLabel")
templeLabelText.BackgroundTransparency = 1
templeLabelText.Size = UDim2.new(1, 0, 1, 0)
templeLabelText.Font = Enum.Font.GothamBlack
templeLabelText.TextSize = 20
templeLabelText.TextColor3 = Color3.fromRGB(255, 215, 0)
templeLabelText.Text = "TEMPLE OF GIGACHAD"
templeLabelText.Parent = templeLabel

local relic = Instance.new("Part")
relic.Name = "SacredRelic"
relic.Shape = Enum.PartType.Ball
relic.Anchored = true
relic.CanCollide = false
relic.Material = Enum.Material.Neon
relic.Color = Color3.fromRGB(255, 215, 0)
relic.Size = Vector3.new(5, 5, 5)
relic.Position = Vector3.new(0, 42, 460)
relic.Parent = Workspace

local relicLabel = Instance.new("BillboardGui")
relicLabel.Size = UDim2.new(0, 180, 0, 36)
relicLabel.StudsOffset = Vector3.new(0, 4, 0)
relicLabel.AlwaysOnTop = true
relicLabel.Parent = relic

local relicLabelText = Instance.new("TextLabel")
relicLabelText.BackgroundTransparency = 1
relicLabelText.Size = UDim2.new(1, 0, 1, 0)
relicLabelText.Font = Enum.Font.GothamBold
relicLabelText.TextSize = 16
relicLabelText.TextColor3 = Color3.fromRGB(255, 255, 255)
relicLabelText.Text = "Sacred Relic"
relicLabelText.Parent = relic

local relicClaimed = false

relic.Touched:Connect(function(otherPart)
	if relicClaimed then
		return
	end
	local character = otherPart.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end
	local state = playerStates[player]
	if not state then
		return
	end

	relicClaimed = true
	state.carryingRelic = true
	playAlarm()
	relic.Transparency = 1
	relic.CanCollide = false
	relicLabel.Enabled = false

	task.spawn(function()
		while relic.Parent and state.carryingRelic do
			local root = character:FindFirstChild("HumanoidRootPart")
			if root then
				relic.Position = root.Position + Vector3.new(0, 3, 0)
			end
			RunService.Heartbeat:Wait()
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	local state = playerStates[player]
	if state and state.carryingRelic then
		state.carryingRelic = false
		relicClaimed = false
		relic.Transparency = 0
		relic.CanCollide = false
		relic.Position = Vector3.new(0, 42, 460)
		relicLabel.Enabled = true
	end
end)

-- If the relic carrier dies before reaching safety, the relic resets to the temple.
local function watchRelicCarrierHealth(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	humanoid.Died:Connect(function()
		local state = playerStates[player]
		if state and state.carryingRelic then
			state.carryingRelic = false
			relicClaimed = false
			relic.Transparency = 0
			relic.CanCollide = false
			relic.Position = Vector3.new(0, 42, 460)
			relicLabel.Enabled = true
		end
	end)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		watchRelicCarrierHealth(player, character)
	end)
end)

--------------------------------------------------------------------------------
-- Cash hook (tour/debug: grant cash directly)
--------------------------------------------------------------------------------

Tour.hooks["cash"] = function(arg)
	local amount = tonumber(arg) or 0
	for player in pairs(playerStates) do
		local cash = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Cash")
		if cash then
			cash.Value += amount
		end
	end
	return true
end
