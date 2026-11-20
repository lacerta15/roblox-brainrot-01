-- Game.client.luau
-- Client GUI + presentation layer for Brainrot Escape Disaster.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--------------------------------------------------------------------------------
-- Remotes
--------------------------------------------------------------------------------

local remotesFolder = ReplicatedStorage:WaitForChild("BrainrotRemotes")
local UpgradeSpeed = remotesFolder:WaitForChild("UpgradeSpeed")
local UpgradeBag = remotesFolder:WaitForChild("UpgradeBag")
local UpgradeMagnet = remotesFolder:WaitForChild("UpgradeMagnet")
local RebirthRemote = remotesFolder:WaitForChild("Rebirth")
local TsunamiWarning = remotesFolder:WaitForChild("TsunamiWarning")
local TsunamiResolved = remotesFolder:WaitForChild("TsunamiResolved")
local SafeZoneEntered = remotesFolder:WaitForChild("SafeZoneEntered")
local SafeZoneExited = remotesFolder:WaitForChild("SafeZoneExited")
local VictoryAchieved = remotesFolder:WaitForChild("VictoryAchieved")

--------------------------------------------------------------------------------
-- ScreenGui scaffold
--------------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "GameGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

-- Top header: tsunami countdown / warning banner
local header = Instance.new("Frame")
header.Name = "Header"
header.AnchorPoint = Vector2.new(0.5, 0)
header.Position = UDim2.new(0.5, 0, 0, 10)
header.Size = UDim2.new(0, 360, 0, 50)
header.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
header.BackgroundTransparency = 0.2
header.BorderSizePixel = 0
header.Parent = gui

local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 10)
headerCorner.Parent = header

local headerLabel = Instance.new("TextLabel")
headerLabel.Name = "Label"
headerLabel.BackgroundTransparency = 1
headerLabel.Size = UDim2.new(1, 0, 1, 0)
headerLabel.Font = Enum.Font.GothamBold
headerLabel.TextSize = 20
headerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
headerLabel.Text = "Next tsunami in 60s"
headerLabel.Parent = header

-- Top-left HUD card
local hud = Instance.new("Frame")
hud.Name = "HUD"
hud.Position = UDim2.new(0, 10, 0, 10)
hud.Size = UDim2.new(0, 230, 0, 130)
hud.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
hud.BackgroundTransparency = 0.15
hud.BorderSizePixel = 0
hud.Parent = gui

local hudCorner = Instance.new("UICorner")
hudCorner.CornerRadius = UDim.new(0, 10)
hudCorner.Parent = hud

local hudLayout = Instance.new("UIListLayout")
hudLayout.Padding = UDim.new(0, 2)
hudLayout.SortOrder = Enum.SortOrder.LayoutOrder
hudLayout.Parent = hud

local hudPadding = Instance.new("UIPadding")
hudPadding.PaddingTop = UDim.new(0, 8)
hudPadding.PaddingLeft = UDim.new(0, 10)
hudPadding.PaddingRight = UDim.new(0, 10)
hudPadding.Parent = hud

local function makeHudLabel(name: string, order: number, text: string, color: Color3?)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.LayoutOrder = order
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 24)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	label.Text = text
	label.Parent = hud
	return label
end

local cashLabel = makeHudLabel("Cash", 1, "$0", Color3.fromRGB(110, 255, 130))
local incomeLabel = makeHudLabel("Income", 2, "+$0/s", Color3.fromRGB(180, 220, 255))
local bagLabel = makeHudLabel("Bag", 3, "Bag 0/3", Color3.fromRGB(255, 220, 130))
local rebirthLabel = makeHudLabel("Rebirths", 4, "Rebirths 0 (x1.0)", Color3.fromRGB(230, 170, 255))

-- Top-right buttons
local buttonHolder = Instance.new("Frame")
buttonHolder.Name = "Buttons"
buttonHolder.AnchorPoint = Vector2.new(1, 0)
buttonHolder.Position = UDim2.new(1, -10, 0, 10)
buttonHolder.Size = UDim2.new(0, 220, 0, 46)
buttonHolder.BackgroundTransparency = 1
buttonHolder.Parent = gui

local buttonLayout = Instance.new("UIListLayout")
buttonLayout.FillDirection = Enum.FillDirection.Horizontal
buttonLayout.Padding = UDim.new(0, 8)
buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
buttonLayout.Parent = buttonHolder

local function makeTopButton(name: string, text: string, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.new(0, 106, 1, 0)
	button.BackgroundColor3 = color
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Text = text
	button.Parent = buttonHolder
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button
	return button
end

local shopButton = makeTopButton("ShopButton", "Shop [E]", Color3.fromRGB(60, 120, 220))
local rebirthButton = makeTopButton("RebirthButton", "Rebirth", Color3.fromRGB(180, 70, 220))

--------------------------------------------------------------------------------
-- Shop modal
--------------------------------------------------------------------------------

local shopFrame = Instance.new("Frame")
shopFrame.Name = "ShopFrame"
shopFrame.AnchorPoint = Vector2.new(0.5, 0.5)
shopFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
shopFrame.Size = UDim2.new(0, 360, 0, 360)
shopFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
shopFrame.Visible = false
shopFrame.Parent = gui

local shopCorner = Instance.new("UICorner")
shopCorner.CornerRadius = UDim.new(0, 14)
shopCorner.Parent = shopFrame

local shopTitle = Instance.new("TextLabel")
shopTitle.Name = "Title"
shopTitle.BackgroundTransparency = 1
shopTitle.Size = UDim2.new(1, 0, 0, 40)
shopTitle.Font = Enum.Font.GothamBold
shopTitle.TextSize = 24
shopTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
shopTitle.Text = "Shop"
shopTitle.Parent = shopFrame

local closeButton = Instance.new("TextButton")
closeButton.Name = "Close"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -8, 0, 8)
closeButton.Size = UDim2.new(0, 28, 0, 28)
closeButton.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 18
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.Text = "X"
closeButton.Parent = shopFrame

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 8)
closeCorner.Parent = closeButton

local shopList = Instance.new("UIListLayout")
shopList.Padding = UDim.new(0, 10)
shopList.SortOrder = Enum.SortOrder.LayoutOrder
shopList.Parent = shopFrame

local shopPadding = Instance.new("UIPadding")
shopPadding.PaddingTop = UDim.new(0, 50)
shopPadding.PaddingLeft = UDim.new(0, 16)
shopPadding.PaddingRight = UDim.new(0, 16)
shopPadding.Parent = shopFrame

local function makeShopRow(name: string, order: number, labelText: string, buttonText: string, color: Color3)
	local row = Instance.new("Frame")
	row.Name = name
	row.LayoutOrder = order
	row.BackgroundColor3 = Color3.fromRGB(30, 30, 44)
	row.Size = UDim2.new(1, 0, 0, 60)
	row.Parent = shopFrame

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 10)
	rowCorner.Parent = row

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, 10, 0, 0)
	label.Size = UDim2.new(1, -120, 1, 0)
	label.Font = Enum.Font.Gotham
	label.TextSize = 16
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextWrapped = true
	label.Text = labelText
	label.Parent = row

	local button = Instance.new("TextButton")
	button.Name = "Action"
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -10, 0.5, 0)
	button.Size = UDim2.new(0, 100, 0, 40)
	button.BackgroundColor3 = color
	button.Font = Enum.Font.GothamBold
	button.TextSize = 15
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Text = buttonText
	button.Parent = row

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 8)
	buttonCorner.Parent = button

	return row, label, button
end

local _speedRow, _speedLabel, speedButton = makeShopRow("Speed", 1, "Speed Upgrade\n+4 WalkSpeed", "Buy", Color3.fromRGB(60, 160, 220))
local _bagRow, _bagLabel, bagButton = makeShopRow("Bag", 2, "Bag Capacity Upgrade\n+1 Brainrot slot", "Buy", Color3.fromRGB(220, 170, 60))
local _magnetRow, _magnetLabel, magnetButton = makeShopRow("Magnet", 3, "Magnet Radius Upgrade\n+5 stud pickup range", "Buy", Color3.fromRGB(120, 220, 160))
local _rebirthRow, _rebirthRowLabel, rebirthConfirmButton = makeShopRow("RebirthConfirm", 4, "Rebirth\nReset cash for permanent 1.5x income", "Confirm", Color3.fromRGB(180, 70, 220))

local shopOpen = false
local function setShopOpen(open: boolean)
	shopOpen = open
	shopFrame.Visible = open
end

shopButton.MouseButton1Click:Connect(function()
	setShopOpen(not shopOpen)
end)
closeButton.MouseButton1Click:Connect(function()
	setShopOpen(false)
end)

speedButton.MouseButton1Click:Connect(function()
	UpgradeSpeed:FireServer()
end)
bagButton.MouseButton1Click:Connect(function()
	UpgradeBag:FireServer()
end)
magnetButton.MouseButton1Click:Connect(function()
	UpgradeMagnet:FireServer()
end)
rebirthButton.MouseButton1Click:Connect(function()
	setShopOpen(true)
end)
rebirthConfirmButton.MouseButton1Click:Connect(function()
	RebirthRemote:FireServer()
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.E then
		setShopOpen(not shopOpen)
	end
end)

--------------------------------------------------------------------------------
-- Tsunami warning banner
--------------------------------------------------------------------------------

local warningBanner = Instance.new("Frame")
warningBanner.Name = "WarningBanner"
warningBanner.AnchorPoint = Vector2.new(0.5, 0)
warningBanner.Position = UDim2.new(0.5, 0, 0, 66)
warningBanner.Size = UDim2.new(0, 420, 0, 40)
warningBanner.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
warningBanner.Visible = false
warningBanner.Parent = gui

local warningCorner = Instance.new("UICorner")
warningCorner.CornerRadius = UDim.new(0, 8)
warningCorner.Parent = warningBanner

local warningLabel = Instance.new("TextLabel")
warningLabel.BackgroundTransparency = 1
warningLabel.Size = UDim2.new(1, 0, 1, 0)
warningLabel.Font = Enum.Font.GothamBold
warningLabel.TextSize = 18
warningLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
warningLabel.Text = "TSUNAMI INCOMING! GET TO THE SAFE ZONE!"
warningLabel.Parent = warningBanner

local tsunamiActive = false
local tsunamiCountdown = 60

TsunamiWarning.OnClientEvent:Connect(function()
	tsunamiActive = true
	warningBanner.Visible = true
end)

TsunamiResolved.OnClientEvent:Connect(function(nextCountdown: number?)
	tsunamiActive = false
	warningBanner.Visible = false
	tsunamiCountdown = nextCountdown or 60
end)

RunService.Heartbeat:Connect(function(dt)
	if not tsunamiActive then
		tsunamiCountdown = math.max(0, tsunamiCountdown - dt)
	end
	headerLabel.Text = tsunamiActive and "TSUNAMI ACTIVE!" or string.format("Next tsunami in %ds", math.ceil(tsunamiCountdown))
end)

--------------------------------------------------------------------------------
-- Safe zone notifications + victory banner
--------------------------------------------------------------------------------

local function flashNotification(text: string, color: Color3)
	local note = Instance.new("TextLabel")
	note.AnchorPoint = Vector2.new(0.5, 0.5)
	note.Position = UDim2.new(0.5, 0, 0.35, 0)
	note.Size = UDim2.new(0, 400, 0, 50)
	note.BackgroundColor3 = color
	note.BackgroundTransparency = 0.1
	note.Font = Enum.Font.GothamBold
	note.TextSize = 22
	note.TextColor3 = Color3.fromRGB(255, 255, 255)
	note.Text = text
	note.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = note

	local tweenIn = TweenService:Create(note, TweenInfo.new(0.25), { BackgroundTransparency = 0.1 })
	tweenIn:Play()

	task.delay(2, function()
		local tweenOut = TweenService:Create(note, TweenInfo.new(0.5), { TextTransparency = 1, BackgroundTransparency = 1 })
		tweenOut:Play()
		tweenOut.Completed:Wait()
		note:Destroy()
	end)
end

SafeZoneEntered.OnClientEvent:Connect(function()
	flashNotification("Entered the Safe Zone", Color3.fromRGB(60, 180, 90))
end)

SafeZoneExited.OnClientEvent:Connect(function()
	flashNotification("Left the Safe Zone!", Color3.fromRGB(200, 140, 40))
end)

local victoryBanner = Instance.new("Frame")
victoryBanner.Name = "VictoryBanner"
victoryBanner.AnchorPoint = Vector2.new(0.5, 0.5)
victoryBanner.Position = UDim2.new(0.5, 0, 0.5, 0)
victoryBanner.Size = UDim2.new(0, 500, 0, 140)
victoryBanner.BackgroundColor3 = Color3.fromRGB(255, 215, 60)
victoryBanner.Visible = false
victoryBanner.ZIndex = 10
victoryBanner.Parent = gui

local victoryCorner = Instance.new("UICorner")
victoryCorner.CornerRadius = UDim.new(0, 16)
victoryCorner.Parent = victoryBanner

local victoryLabel = Instance.new("TextLabel")
victoryLabel.BackgroundTransparency = 1
victoryLabel.Size = UDim2.new(1, 0, 1, 0)
victoryLabel.Font = Enum.Font.GothamBlack
victoryLabel.TextSize = 32
victoryLabel.TextColor3 = Color3.fromRGB(40, 30, 0)
victoryLabel.Text = "VICTORY!\nSacred Relic returned to safety!"
victoryLabel.Parent = victoryBanner

VictoryAchieved.OnClientEvent:Connect(function()
	victoryBanner.Visible = true
	task.delay(5, function()
		victoryBanner.Visible = false
	end)
end)

--------------------------------------------------------------------------------
-- HUD data binding
--------------------------------------------------------------------------------

local leaderstats = player:WaitForChild("leaderstats")
local cashStat = leaderstats:WaitForChild("Cash")
local rebirthsStat = leaderstats:WaitForChild("Rebirths")

local bagCount = player:WaitForChild("BagCount")
local bagCapacity = player:WaitForChild("BagCapacity")
local incomePerSecond = player:WaitForChild("IncomePerSecond")
local rebirthMultiplier = player:WaitForChild("RebirthMultiplier")

local function formatCash(amount: number): string
	return "$" .. string.format("%d", amount)
end

local function refreshHud()
	cashLabel.Text = formatCash(cashStat.Value)
	incomeLabel.Text = string.format("+$%d/s", incomePerSecond.Value)
	bagLabel.Text = string.format("Bag %d/%d", bagCount.Value, bagCapacity.Value)
	rebirthLabel.Text = string.format("Rebirths %d (x%.1f)", rebirthsStat.Value, rebirthMultiplier.Value)
end

cashStat.Changed:Connect(refreshHud)
rebirthsStat.Changed:Connect(refreshHud)
bagCount.Changed:Connect(refreshHud)
bagCapacity.Changed:Connect(refreshHud)
incomePerSecond.Changed:Connect(refreshHud)
rebirthMultiplier.Changed:Connect(refreshHud)
refreshHud()

--------------------------------------------------------------------------------
-- Collectible bobbing animation
--------------------------------------------------------------------------------

local collectiblesFolder = Workspace:WaitForChild("Brainrots")

local bobbers: { [BasePart]: { origin: Vector3, offset: number } } = {}

local function trackCollectible(model: Instance)
	local part = model:IsA("Model") and model.PrimaryPart or (model:IsA("BasePart") and model or nil)
	if not part then
		return
	end
	bobbers[part] = { origin = part.Position, offset = math.random() * math.pi * 2 }
end

for _, child in ipairs(collectiblesFolder:GetChildren()) do
	trackCollectible(child)
end
collectiblesFolder.ChildAdded:Connect(trackCollectible)
collectiblesFolder.ChildRemoved:Connect(function(child)
	local part = child:IsA("Model") and child.PrimaryPart or (child:IsA("BasePart") and child or nil)
	if part then
		bobbers[part] = nil
	end
end)

RunService.Heartbeat:Connect(function()
	local t = os.clock()
	for part, data in pairs(bobbers) do
		if part and part.Parent then
			local bobHeight = math.sin(t * 2 + data.offset) * 0.6
			part.Position = Vector3.new(data.origin.X, data.origin.Y + bobHeight, data.origin.Z)
			part.CFrame = CFrame.new(part.Position) * CFrame.Angles(0, t * 1.2 + data.offset, 0)
		else
			bobbers[part] = nil
		end
	end
end)
