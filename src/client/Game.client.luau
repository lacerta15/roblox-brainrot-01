-- Brainrot Escape Disaster — client
--
-- A ScreenGui HUD over the 3D world: the cash counter (rolling up smoothly), cash per second, the bag and
-- its capacity, the rebirth multiplier, the tsunami timer with a flashing warning, the safe/danger zone
-- indicator, deposit and pickup effects, toasts, and the upgrade shop modal (E, the 🛒 button or the
-- UPGRADES stall). It also bobs and spins the brainrots waiting in the field.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local StateEvent = remotes:WaitForChild("State") :: RemoteEvent
local NotifyEvent = remotes:WaitForChild("Notify") :: RemoteEvent
local PickupEvent = remotes:WaitForChild("Pickup") :: RemoteEvent
local DepositEvent = remotes:WaitForChild("Deposit") :: RemoteEvent
local KnockOutEvent = remotes:WaitForChild("KnockOut") :: RemoteEvent
local OpenShopEvent = remotes:WaitForChild("OpenShop") :: RemoteEvent
local BuyUpgradeEvent = remotes:WaitForChild("BuyUpgrade") :: RemoteEvent
local RebirthEvent = remotes:WaitForChild("Rebirth") :: RemoteEvent

-- Mirrors the server's zones (src/server/init.server.luau) for the zone indicator.
local ZONES = {
	{ name = "Common", x0 = 0, color = Color3.fromRGB(205, 205, 205) },
	{ name = "Rare", x0 = 90, color = Color3.fromRGB(70, 150, 255) },
	{ name = "Epic", x0 = 170, color = Color3.fromRGB(175, 85, 255) },
	{ name = "Legendary", x0 = 250, color = Color3.fromRGB(255, 190, 40) },
	{ name = "Mythic", x0 = 330, color = Color3.fromRGB(255, 60, 95) },
	{ name = "Secret", x0 = 410, color = Color3.fromRGB(40, 255, 205) },
}
local RARITY_COLOR = {}
for _, z in ZONES do
	RARITY_COLOR[z.name] = z.color
end
local BRAINROT_INFO = {
	skibidi = { "Skibidi Toilet", "Common" },
	mewcat = { "Mewing Cat", "Common" },
	grimace = { "Grimace Shake", "Rare" },
	looksmaxxer = { "Looksmaxxer", "Rare" },
	fanum = { "Fanum Tax", "Epic" },
	sigma = { "Sigma Boy", "Epic" },
	rizzler = { "Rizzler", "Legendary" },
	kai = { "Kai Cenat", "Mythic" },
	gigachad = { "GigaChad", "Secret" },
}

local GREEN = Color3.fromRGB(100, 255, 130)
local GOLD = Color3.fromRGB(255, 210, 60)
local RED = Color3.fromRGB(255, 70, 70)
local PANEL = Color3.fromRGB(20, 22, 38)

--------------------------------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------------------------------

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

local function new(className: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(className)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function corner(r: number)
	return new("UICorner", { CornerRadius = UDim.new(0, r) })
end

local function stroke(color: Color3, t: number, transparency: number?)
	return new("UIStroke", { Color = color, Thickness = t, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

local function label(props: { [string]: any })
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or Enum.Font.FredokaOne
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.TextScaled = props.TextScaled ~= false
	local l = new("TextLabel", props)
	new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2, Transparency = 0.3, Parent = l })
	return l
end

local function tween(inst: Instance, t: number, goal: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end

local function playSound(id: string, volume: number, pitch: number?)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.PlaybackSpeed = pitch or 1
	s.Parent = SoundService
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	task.delay(5, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

--------------------------------------------------------------------------------------------------------
-- The HUD
--------------------------------------------------------------------------------------------------------

local gui = new("ScreenGui", { Name = "BrainrotHUD", ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })

-- Full-screen flash for tsunami warnings, deposits and wipe-outs.
local flash = new("Frame", { Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = RED, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1, Parent = gui })

-- Stats panel (top left)
local stats = new("Frame", {
	Name = "Stats", Position = UDim2.new(0, 16, 0, 64), Size = UDim2.fromOffset(270, 196), BackgroundColor3 = PANEL, BackgroundTransparency = 0.15, ZIndex = 5, Parent = gui,
}, { corner(14), stroke(GOLD, 2, 0.3), new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 170, 210)) }) })
local cashScale = new("UIScale", { Parent = stats })
label({ Text = "💰 CASH", Position = UDim2.fromOffset(14, 8), Size = UDim2.fromOffset(120, 20), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = GOLD, ZIndex = 6, Parent = stats })
local cashLabel = label({ Name = "Cash", Text = "$0", Position = UDim2.fromOffset(14, 28), Size = UDim2.fromOffset(242, 50), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 240, 150), ZIndex = 6, Parent = stats })
local cpsLabel = label({ Name = "PerSecond", Text = "+$0/s", Position = UDim2.fromOffset(14, 80), Size = UDim2.fromOffset(242, 26), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = GREEN, ZIndex = 6, Parent = stats })
local bagLabel = label({ Name = "Bag", Text = "🎒 Bag 0/3", Position = UDim2.fromOffset(14, 112), Size = UDim2.fromOffset(242, 24), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6, Parent = stats })
local bagBar = new("Frame", { Position = UDim2.fromOffset(14, 140), Size = UDim2.fromOffset(242, 12), BackgroundColor3 = Color3.fromRGB(50, 50, 70), ZIndex = 6, Parent = stats }, { corner(6) })
local bagFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(90, 200, 255), ZIndex = 7, Parent = bagBar }, { corner(6) })
local rebirthLabel = label({ Name = "Rebirth", Text = "♻ Rebirth 0  •  x1.0 income", Position = UDim2.fromOffset(14, 160), Size = UDim2.fromOffset(242, 22), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 140, 230), ZIndex = 6, Parent = stats })

-- Tsunami timer and zone indicator (top centre)
local waveBar = new("Frame", {
	Name = "WaveTimer", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 56), Size = UDim2.fromOffset(440, 46),
	BackgroundColor3 = Color3.fromRGB(20, 60, 120), BackgroundTransparency = 0.1, ZIndex = 5, Parent = gui,
}, { corner(23), stroke(Color3.fromRGB(120, 200, 255), 2, 0.2) })
local waveLabel = label({ Text = "🌊 Next tsunami in --s", Size = UDim2.new(1, -24, 1, -10), Position = UDim2.fromOffset(12, 5), ZIndex = 6, Parent = waveBar })
local waveProgress = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 22, 1, -2), Size = UDim2.new(0, 0, 0, 4), BackgroundColor3 = Color3.fromRGB(120, 220, 255), BorderSizePixel = 0, ZIndex = 6, Parent = waveBar }, { corner(2) })

local zonePill = new("Frame", {
	Name = "Zone", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 108), Size = UDim2.fromOffset(300, 32),
	BackgroundColor3 = Color3.fromRGB(30, 140, 70), BackgroundTransparency = 0.15, ZIndex = 5, Parent = gui,
}, { corner(16) })
local zoneLabel = label({ Text = "🛡 SAFE ZONE", Size = UDim2.new(1, -16, 1, -6), Position = UDim2.fromOffset(8, 3), ZIndex = 6, Parent = zonePill })

-- Big centre alert
local alert = label({
	Name = "Alert", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.32), Size = UDim2.fromOffset(760, 90),
	Text = "", TextColor3 = Color3.fromRGB(255, 240, 240), Font = Enum.Font.LuckiestGuy, ZIndex = 20, Visible = false, Parent = gui,
})
local alertSub = label({
	Name = "AlertSub", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.32), Size = UDim2.fromOffset(600, 34),
	Text = "", ZIndex = 20, Visible = false, Parent = gui,
})
alertSub.Position = UDim2.new(0.5, 0, 0.32, 64)

-- Toasts (bottom centre)
local toastHolder = new("Frame", { Name = "Toasts", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -110), Size = UDim2.fromOffset(520, 220), BackgroundTransparency = 1, ZIndex = 10, Parent = gui }, {
	new("UIListLayout", { VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
})
local toastOrder = 0

local function toast(text: string, color: Color3?)
	toastOrder += 1
	local f = new("Frame", { Size = UDim2.fromOffset(500, 38), BackgroundColor3 = PANEL, BackgroundTransparency = 0.15, LayoutOrder = toastOrder, ZIndex = 10, Parent = toastHolder }, { corner(10), stroke(color or Color3.new(1, 1, 1), 2, 0.2) })
	local l = label({ Text = text, Size = UDim2.new(1, -20, 1, -8), Position = UDim2.fromOffset(10, 4), TextColor3 = color or Color3.new(1, 1, 1), ZIndex = 11, Parent = f })
	local s = new("UIScale", { Scale = 0.6, Parent = f })
	tween(s, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(3.2, function()
		tween(f, 0.4, { BackgroundTransparency = 1 })
		tween(l, 0.4, { TextTransparency = 1 })
		task.wait(0.45)
		f:Destroy()
	end)
	local children = toastHolder:GetChildren()
	if #children > 6 then
		for _, c in children do
			if c:IsA("Frame") then
				c:Destroy()
				break
			end
		end
	end
end

-- Buttons (right side)
local function sideButton(text: string, y: number, color: Color3)
	local b = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, y), Size = UDim2.fromOffset(170, 52), BackgroundColor3 = color,
		Text = text, TextColor3 = Color3.new(1, 1, 1), TextScaled = true, Font = Enum.Font.FredokaOne, AutoButtonColor = true, ZIndex = 5, Parent = gui,
	}, { corner(14), stroke(Color3.new(0, 0, 0), 2, 0.4), new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }) })
	return b
end
local shopButton = sideButton("🛒 SHOP [E]", 64, Color3.fromRGB(40, 150, 255))
local rebirthButton = sideButton("♻ REBIRTH", 124, Color3.fromRGB(220, 60, 180))

label({
	Name = "Controls", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -16), Size = UDim2.fromOffset(460, 22), TextXAlignment = Enum.TextXAlignment.Left,
	Text = "WASD move • Space jump • E shop • walk into brainrots to catch them", TextColor3 = Color3.fromRGB(220, 220, 240), ZIndex = 5, Parent = gui,
})

-- Title card (fades after a few seconds)
local title = label({
	Name = "Title", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(820, 110),
	Text = "BRAINROT ESCAPE DISASTER", Font = Enum.Font.LuckiestGuy, TextColor3 = Color3.fromRGB(255, 230, 90), ZIndex = 30, Parent = gui,
})
new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 255, 140), Color3.fromRGB(255, 120, 220)), Rotation = 90, Parent = title })
local titleSub = label({
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.45, 70), Size = UDim2.fromOffset(640, 30),
	Text = "catch brainrots • bank them at the 💰 pad • outrun the tsunami", ZIndex = 30, Parent = gui,
})
task.delay(4, function()
	tween(title, 1, { TextTransparency = 1 })
	tween(titleSub, 1, { TextTransparency = 1 })
	for _, s in { title:FindFirstChildOfClass("UIStroke"), titleSub:FindFirstChildOfClass("UIStroke") } do
		if s then
			tween(s, 1, { Transparency = 1 })
		end
	end
	task.wait(1.1)
	title.Visible = false
	titleSub.Visible = false
end)

--------------------------------------------------------------------------------------------------------
-- The shop modal
--------------------------------------------------------------------------------------------------------

local UPGRADE_UI = {
	{ key = "speed", icon = "👟", name = "Speed", desc = "Run faster to reach rare zones and escape the wave", stat = function(s) return string.format("WalkSpeed %d → %d", s.speed, s.speed + 3) end },
	{ key = "capacity", icon = "🎒", name = "Bag Capacity", desc = "Carry more brainrots per trip", stat = function(s) return string.format("Bag %d → %d", s.capacity, s.capacity + 1) end },
	{ key = "magnet", icon = "🧲", name = "Magnet", desc = "Catch brainrots from farther away", stat = function(s) return string.format("Range %d → %d studs", s.magnet, s.magnet + 2) end },
}

local dim = new("Frame", { Name = "ShopDim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Visible = false, ZIndex = 40, Parent = gui })
local modal = new("Frame", {
	Name = "Shop", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(640, 470), BackgroundColor3 = PANEL, ZIndex = 41, Parent = dim,
}, { corner(18), stroke(Color3.fromRGB(120, 200, 255), 3) })
local modalScale = new("UIScale", { Parent = modal })
label({ Text = "🛒 BRAINROT UPGRADES", Position = UDim2.fromOffset(24, 14), Size = UDim2.new(1, -110, 0, 44), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(140, 210, 255), ZIndex = 42, Parent = modal })
local shopCash = label({ Text = "$0", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -80, 0, 22), Size = UDim2.fromOffset(160, 30), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = GOLD, ZIndex = 42, Parent = modal })
local closeButton = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 16), Size = UDim2.fromOffset(44, 44), BackgroundColor3 = Color3.fromRGB(200, 50, 60),
	Text = "✕", TextColor3 = Color3.new(1, 1, 1), TextScaled = true, Font = Enum.Font.GothamBlack, ZIndex = 42, Parent = modal,
}, { corner(12) })

local cards = {}
for i, u in UPGRADE_UI do
	local card = new("Frame", {
		Position = UDim2.fromOffset(20, 70 + (i - 1) * 92), Size = UDim2.new(1, -40, 0, 82), BackgroundColor3 = Color3.fromRGB(34, 38, 62), ZIndex = 42, Parent = modal,
	}, { corner(12) })
	label({ Text = u.icon, Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(60, 60), ZIndex = 43, Parent = card })
	local nameL = label({ Text = u.name, Position = UDim2.fromOffset(80, 8), Size = UDim2.fromOffset(300, 28), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 43, Parent = card })
	local descL = label({ Text = u.desc, Position = UDim2.fromOffset(80, 36), Size = UDim2.fromOffset(330, 18), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(190, 190, 215), Font = Enum.Font.GothamMedium, ZIndex = 43, Parent = card })
	local statL = label({ Text = "", Position = UDim2.fromOffset(80, 56), Size = UDim2.fromOffset(330, 18), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = GREEN, Font = Enum.Font.GothamBold, ZIndex = 43, Parent = card })
	local buy = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(150, 56), BackgroundColor3 = Color3.fromRGB(60, 190, 90),
		Text = "$0", TextColor3 = Color3.new(1, 1, 1), TextScaled = true, Font = Enum.Font.FredokaOne, ZIndex = 43, Parent = card,
	}, { corner(12), new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }) })
	buy.Activated:Connect(function()
		BuyUpgradeEvent:FireServer(u.key)
		local s = buy:FindFirstChildOfClass("UIScale") or new("UIScale", { Parent = buy })
		s.Scale = 0.85
		tween(s, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		playSound("rbxasset://sounds/electronicpingshort.wav", 0.4, 1.4)
	end)
	cards[u.key] = { name = nameL, desc = descL, stat = statL, buy = buy, def = u }
end

local rebirthCard = new("Frame", {
	Position = UDim2.fromOffset(20, 70 + 3 * 92), Size = UDim2.new(1, -40, 0, 104), BackgroundColor3 = Color3.fromRGB(70, 30, 70), ZIndex = 42, Parent = modal,
}, { corner(12), stroke(Color3.fromRGB(255, 120, 230), 2, 0.3) })
label({ Text = "♻", Position = UDim2.fromOffset(10, 18), Size = UDim2.fromOffset(60, 60), ZIndex = 43, Parent = rebirthCard })
label({ Text = "REBIRTH", Position = UDim2.fromOffset(80, 8), Size = UDim2.fromOffset(300, 28), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 150, 235), ZIndex = 43, Parent = rebirthCard })
local rebirthDesc = label({ Text = "", Position = UDim2.fromOffset(80, 38), Size = UDim2.fromOffset(330, 54), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, TextColor3 = Color3.fromRGB(230, 200, 230), Font = Enum.Font.GothamMedium, ZIndex = 43, Parent = rebirthCard })
rebirthDesc.TextScaled = true
local rebirthBuy = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(150, 60), BackgroundColor3 = Color3.fromRGB(220, 60, 180),
	Text = "$25K", TextColor3 = Color3.new(1, 1, 1), TextScaled = true, Font = Enum.Font.FredokaOne, ZIndex = 43, Parent = rebirthCard,
}, { corner(12), new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }) })

local shopOpen = false
local function setShop(open: boolean)
	if open == shopOpen then
		return
	end
	shopOpen = open
	if open then
		dim.Visible = true
		modalScale.Scale = 0.7
		tween(modalScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		playSound("rbxasset://sounds/electronicpingshort.wav", 0.3, 0.9)
	else
		tween(modalScale, 0.15, { Scale = 0.7 }).Completed:Once(function()
			if not shopOpen then
				dim.Visible = false
			end
		end)
	end
end

closeButton.Activated:Connect(function()
	setShop(false)
end)
shopButton.Activated:Connect(function()
	setShop(not shopOpen)
end)
rebirthButton.Activated:Connect(function()
	setShop(true)
end)
rebirthBuy.Activated:Connect(function()
	RebirthEvent:FireServer()
end)

ContextActionService:BindAction("ToggleShop", function(_, state)
	if state == Enum.UserInputState.Begin then
		setShop(not shopOpen)
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.E, Enum.KeyCode.ButtonY)

OpenShopEvent.OnClientEvent:Connect(function()
	setShop(true)
end)

--------------------------------------------------------------------------------------------------------
-- State from the server
--------------------------------------------------------------------------------------------------------

local state = nil
local shownCash = 0
local targetCash = 0

local function renderState()
	if not state then
		return
	end
	cpsLabel.Text = "+$" .. formatNumber(state.cps) .. "/s"
	local bagCount = #state.bag
	bagLabel.Text = string.format("🎒 Bag %d/%d   •   🏠 %d banked", bagCount, state.capacity, state.owned)
	bagLabel.TextColor3 = bagCount >= state.capacity and Color3.fromRGB(255, 170, 60) or Color3.new(1, 1, 1)
	tween(bagFill, 0.2, { Size = UDim2.fromScale(math.clamp(bagCount / math.max(state.capacity, 1), 0, 1), 1) })
	bagFill.BackgroundColor3 = bagCount >= state.capacity and Color3.fromRGB(255, 150, 50) or Color3.fromRGB(90, 200, 255)
	rebirthLabel.Text = string.format("♻ Rebirth %d  •  x%.1f income", state.rebirths, state.multiplier)
	shopCash.Text = "$" .. formatNumber(state.cash)

	for key, card in cards do
		local u = state.upgrades[key]
		card.name.Text = string.format("%s  Lv %d/%d", card.def.name, u.level, u.max)
		if u.cost then
			card.stat.Text = card.def.stat(state.stats)
			card.buy.Text = "$" .. formatNumber(u.cost)
			card.buy.BackgroundColor3 = state.cash >= u.cost and Color3.fromRGB(60, 190, 90) or Color3.fromRGB(90, 90, 105)
		else
			card.stat.Text = "MAXED"
			card.buy.Text = "MAX"
			card.buy.BackgroundColor3 = Color3.fromRGB(200, 160, 40)
		end
	end
	rebirthDesc.Text = string.format("Reset cash, brainrots and upgrades for a permanent x%.1f income multiplier.", state.nextMultiplier)
	rebirthBuy.Text = "$" .. formatNumber(state.rebirthCost)
	rebirthBuy.BackgroundColor3 = state.cash >= state.rebirthCost and Color3.fromRGB(220, 60, 180) or Color3.fromRGB(90, 90, 105)
	rebirthButton.BackgroundColor3 = state.cash >= state.rebirthCost and Color3.fromRGB(255, 80, 210) or Color3.fromRGB(150, 60, 130)
end

StateEvent.OnClientEvent:Connect(function(s)
	state = s
	targetCash = s.cash
	if shownCash > targetCash then
		shownCash = targetCash -- spending snaps down; earning rolls up
	end
	renderState()
end)

NotifyEvent.OnClientEvent:Connect(function(text: string, color: Color3?)
	toast(text, color)
end)

--------------------------------------------------------------------------------------------------------
-- Effects
--------------------------------------------------------------------------------------------------------

local fxFolder = Instance.new("Folder")
fxFolder.Name = "ClientFx"
fxFolder.Parent = workspace

local function burst(pos: Vector3, color: Color3, size: number)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = Vector3.one
	p.Position = pos + Vector3.new(0, 2.5, 0)
	p.Transparency = 0.1
	p.Parent = fxFolder
	tween(p, 0.45, { Size = Vector3.one * size, Transparency = 1 })
	task.delay(0.5, function()
		p:Destroy()
	end)
end

local function flashScreen(color: Color3, peak: number, duration: number)
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = peak
	tween(flash, duration, { BackgroundTransparency = 1 })
end

local function floatText(text: string, color: Color3, from: UDim2)
	local l = label({ Text = text, AnchorPoint = Vector2.new(0.5, 0.5), Position = from, Size = UDim2.fromOffset(520, 56), TextColor3 = color, Font = Enum.Font.LuckiestGuy, ZIndex = 25, Parent = gui })
	local s = new("UIScale", { Scale = 0.4, Parent = l })
	tween(s, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(l, 1.6, { Position = from - UDim2.fromOffset(0, 90) }, Enum.EasingStyle.Sine)
	task.delay(1.0, function()
		tween(l, 0.6, { TextTransparency = 1 })
		local st = l:FindFirstChildOfClass("UIStroke")
		if st then
			tween(st, 0.6, { Transparency = 1 })
		end
	end)
	task.delay(1.7, function()
		l:Destroy()
	end)
end

local function coinShower(count: number)
	local target = stats.AbsolutePosition + Vector2.new(80, 50)
	local view = workspace.CurrentCamera.ViewportSize
	for i = 1, math.min(count, 18) do
		local coin = new("TextLabel", {
			Text = "🪙", BackgroundTransparency = 1, TextScaled = true, Size = UDim2.fromOffset(34, 34), AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(view.X / 2 + math.random(-160, 160), view.Y / 2 + math.random(-60, 100)), ZIndex = 26, Parent = gui,
		})
		task.delay(i * 0.04, function()
			tween(coin, 0.7, { Position = UDim2.fromOffset(target.X, target.Y), Size = UDim2.fromOffset(18, 18) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.wait(0.72)
			coin:Destroy()
		end)
	end
	task.delay(0.8, function()
		cashScale.Scale = 1.08
		tween(cashScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
end

PickupEvent.OnClientEvent:Connect(function(id: string, pos: Vector3)
	local info = BRAINROT_INFO[id]
	if not info then
		return
	end
	local color = RARITY_COLOR[info[2]] or Color3.new(1, 1, 1)
	burst(pos, color, 9)
	toast(string.format("✨ Caught %s! (%s)", info[1], info[2]), color)
	playSound("rbxasset://sounds/electronicpingshort.wav", 0.5, 1.3)
	if info[2] == "Legendary" or info[2] == "Mythic" or info[2] == "Secret" then
		floatText(string.upper(info[2]) .. "! " .. info[1], color, UDim2.fromScale(0.5, 0.42))
		flashScreen(color, 0.75, 0.6)
	end
end)

DepositEvent.OnClientEvent:Connect(function(count: number, gained: number, bonus: number)
	flashScreen(Color3.fromRGB(120, 255, 140), 0.7, 0.6)
	floatText(string.format("+%d BANKED!  +$%s/s", count, formatNumber(gained)), GREEN, UDim2.fromScale(0.5, 0.45))
	if bonus > 0 then
		task.delay(0.25, function()
			floatText("+$" .. formatNumber(bonus) .. " bonus", GOLD, UDim2.new(0.5, 0, 0.45, 56))
		end)
	end
	coinShower(4 + count * 2)
	playSound("rbxasset://sounds/electronicpingshort.wav", 0.7, 0.8)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		burst(hrp.Position - Vector3.new(0, 2, 0), GOLD, 16)
	end
end)

KnockOutEvent.OnClientEvent:Connect(function(lost: number)
	flashScreen(Color3.fromRGB(40, 120, 255), 0.15, 2.5)
	alert.Visible = true
	alertSub.Visible = true
	alert.Text = "🌊 WIPED OUT! 🌊"
	alert.TextColor3 = Color3.fromRGB(140, 200, 255)
	alertSub.Text = lost > 0 and string.format("The tsunami took your bag (%d brainrot%s). Stay in the Safe Zone!", lost, lost == 1 and "" or "s") or "Stay in the Safe Zone when the wave comes!"
	playSound("rbxasset://sounds/uuhhh.mp3", 0.6)
	task.delay(3, function()
		if workspace:GetAttribute("TsunamiPhase") ~= "warning" then
			alert.Visible = false
			alertSub.Visible = false
		end
	end)
end)

--------------------------------------------------------------------------------------------------------
-- Per-frame: cash roll-up, tsunami timer, warning flash, zone indicator, field brainrot animation
--------------------------------------------------------------------------------------------------------

local blur = Instance.new("BlurEffect")
blur.Size = 0
blur.Parent = Lighting

local fieldFolder = workspace:WaitForChild("Field")
local basePivots: { [Model]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local lastPhase = "calm"
local lastBeep = -1

RunService.RenderStepped:Connect(function(dt)
	local now = workspace:GetServerTimeNow()

	-- cash rolls up toward the server's figure
	shownCash += (targetCash - shownCash) * math.clamp(dt * 8, 0, 1)
	if math.abs(targetCash - shownCash) < 1 then
		shownCash = targetCash
	end
	cashLabel.Text = "$" .. formatNumber(shownCash)

	-- where am I?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local x = hrp and hrp.Position.X or -50
	local safeEdge = workspace:GetAttribute("SafeEdge") or 0
	local safe = x < safeEdge
	if safe then
		zoneLabel.Text = "🛡 SAFE ZONE"
		zonePill.BackgroundColor3 = Color3.fromRGB(30, 140, 70)
	else
		local zone = ZONES[1]
		for _, z in ZONES do
			if x >= z.x0 then
				zone = z
			end
		end
		zoneLabel.Text = string.format("⚠ %s ZONE  •  %d studs out", string.upper(zone.name), math.floor(x - safeEdge))
		zonePill.BackgroundColor3 = zone.color:Lerp(Color3.new(0, 0, 0), 0.45)
	end

	-- the tsunami
	local phase = workspace:GetAttribute("TsunamiPhase") or "calm"
	local at = workspace:GetAttribute("TsunamiAt") or now
	local left = math.max(0, at - now)
	if phase == "calm" then
		waveLabel.Text = string.format("🌊 Next tsunami in %ds", math.ceil(left))
		waveBar.BackgroundColor3 = Color3.fromRGB(20, 60, 120)
		waveProgress.Size = UDim2.new(math.clamp(1 - left / 70, 0, 1), -44, 0, 4)
	elseif phase == "warning" then
		waveLabel.Text = string.format("⚠ TSUNAMI INCOMING IN %ds — RUN! ⚠", math.ceil(left))
		local pulse = (math.sin(now * 12) + 1) / 2
		waveBar.BackgroundColor3 = Color3.fromRGB(150, 20, 20):Lerp(Color3.fromRGB(255, 60, 40), pulse)
		waveProgress.Size = UDim2.new(math.clamp(1 - left / 10, 0, 1), -44, 0, 4)
		-- the flashing screen: strong when you are out in the open, a gentle pulse when safe
		flash.BackgroundColor3 = RED
		flash.BackgroundTransparency = safe and (0.93 - pulse * 0.04) or (0.82 - pulse * 0.2)
		alert.Visible = true
		alertSub.Visible = true
		alert.Text = safe and "🌊 TSUNAMI INCOMING! 🌊" or "⚠ TSUNAMI! RUN TO THE SAFE ZONE! ⚠"
		alert.TextColor3 = Color3.fromRGB(255, 230, 230):Lerp(RED, pulse)
		alertSub.Text = safe and "You're safe here. Wait for the wave to pass." or string.format("%d studs to safety • %ds left", math.floor(x - safeEdge), math.ceil(left))
		alert.Rotation = safe and 0 or math.sin(now * 40) * 1.5
		local beep = math.ceil(left)
		if beep ~= lastBeep then
			lastBeep = beep
			playSound("rbxasset://sounds/electronicpingshort.wav", safe and 0.25 or 0.6, 0.5)
		end
	else
		local front = workspace:GetAttribute("WaveFront")
		waveLabel.Text = front and string.format("🌊 TSUNAMI! wave at %d studs", math.max(0, math.floor(front - safeEdge))) or "🌊 The wave is crashing..."
		waveBar.BackgroundColor3 = Color3.fromRGB(20, 90, 200)
		waveProgress.Size = UDim2.new(1, -44, 0, 4)
		if not safe then
			flash.BackgroundColor3 = Color3.fromRGB(30, 90, 220)
			flash.BackgroundTransparency = 0.8 + math.sin(now * 10) * 0.05
		end
		if phase ~= lastPhase then
			alert.Visible = true
			alertSub.Visible = true
			alert.Text = "🌊 HERE IT COMES! 🌊"
			alert.TextColor3 = Color3.fromRGB(140, 200, 255)
			alert.Rotation = 0
			alertSub.Text = safe and "Watch it crash against the Safe Zone!" or "Too late... brace yourself!"
		end
		-- camera shake while the wave is close
		if front and hrp then
			local dist = math.abs(front - x)
			if dist < 80 then
				local cam = workspace.CurrentCamera
				local k = (1 - dist / 80) * 0.35
				cam.CFrame = cam.CFrame * CFrame.new(math.random(-100, 100) / 100 * k, math.random(-100, 100) / 100 * k, 0)
			end
		end
	end
	if phase ~= lastPhase then
		if phase == "calm" then
			alert.Visible = false
			alertSub.Visible = false
			alert.Rotation = 0
			tween(flash, 0.5, { BackgroundTransparency = 1 })
			toast("🌊 The wave has passed. The field is regrowing — go catch some brainrots!", Color3.fromRGB(120, 200, 255))
		elseif phase == "warning" then
			toast("⚠ A tsunami is coming! Get back behind the green line!", RED)
		elseif phase == "receding" then
			task.delay(1.2, function()
				if workspace:GetAttribute("TsunamiPhase") ~= "warning" then
					alert.Visible = false
					alertSub.Visible = false
				end
			end)
		end
		lastPhase = phase
	end
	blur.Size = (phase == "warning" and not safe) and 2 or 0

	-- the field's brainrots bob and turn
	local t = os.clock()
	for _, m in fieldFolder:GetChildren() do
		if m:IsA("Model") then
			local base = basePivots[m]
			if not base then
				base = m:GetPivot()
				basePivots[m] = base
			end
			local phaseOffset = (base.Position.X + base.Position.Z) * 0.1
			m:PivotTo(base * CFrame.new(0, 0.6 + math.sin(t * 2.2 + phaseOffset) * 0.5, 0) * CFrame.Angles(0, t * 0.8 + phaseOffset, 0))
		end
	end
end)

gui.Parent = playerGui
