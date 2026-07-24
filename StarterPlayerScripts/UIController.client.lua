--!strict
-- LocalScript: StarterPlayerScripts.UIController
-- Builds the HUD at runtime and keeps it in sync via Remotes.UpdateStats.
-- Also handles the CameraShake remote for hazard collisions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local updateStats = remotes:WaitForChild("UpdateStats") :: RemoteEvent
local cameraShakeEvent = remotes:WaitForChild("CameraShake") :: RemoteEvent
local raceUpdate = remotes:WaitForChild("RaceUpdate") :: RemoteEvent
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))

local player = Players.LocalPlayer

-- Звон при прохождении чекпоинта (magic-orb). Twinkle08 — free Creator Store.
local SoundService = game:GetService("SoundService")
local checkpointSound = Instance.new("Sound")
checkpointSound.SoundId = "rbxassetid://135385970610304"
checkpointSound.Volume = 0.5
checkpointSound.Parent = SoundService

local finishSound = Instance.new("Sound")
finishSound.SoundId = "rbxassetid://4961240438" -- грозовой раскат: драматичный крип-стинг на финиш
finishSound.Volume = 0.7
finishSound.Parent = SoundService

-- Предзагрузка звуков — чтобы чекпоинт/финиш не молчали при первом срабатывании.
task.spawn(function()
	pcall(function()
		game:GetService("ContentProvider"):PreloadAsync({ checkpointSound, finishSound })
	end)
end)
local lastCheckpointIndex: number? = nil
local playerGui = player:WaitForChild("PlayerGui")

-- // Build UI ------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GraveyardHUD"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local healthBg = Instance.new("Frame")
healthBg.Name = "HealthBackground"
healthBg.Size = UDim2.new(0, 220, 0, 24)
healthBg.Position = UDim2.new(0, 20, 0, 20)
healthBg.BackgroundColor3 = UITheme.PanelBg
healthBg.Parent = screenGui

local healthFill = Instance.new("Frame")
healthFill.Name = "HealthFill"
healthFill.Size = UDim2.new(1, 0, 1, 0)
healthFill.BackgroundColor3 = UITheme.Palette.Red
healthFill.BorderSizePixel = 0
healthFill.Parent = healthBg

local healthLabel = Instance.new("TextLabel")
healthLabel.Size = UDim2.new(1, 0, 1, 0)
healthLabel.BackgroundTransparency = 1
healthLabel.TextColor3 = UITheme.Ink
healthLabel.Font = UITheme.Font
healthLabel.TextScaled = true
healthLabel.Text = "Health"
healthLabel.Parent = healthBg

local speedLabel = Instance.new("TextLabel")
speedLabel.Name = "Speedometer"
speedLabel.Size = UDim2.new(0, 220, 0, 30)
speedLabel.Position = UDim2.new(0, 20, 0, 52)
speedLabel.BackgroundTransparency = 0 -- непрозрачно: красный читается ровно как HealthFill
speedLabel.BackgroundColor3 = UITheme.cycleColor(1) -- красный
speedLabel.TextColor3 = UITheme.Ink
speedLabel.Font = UITheme.Font
speedLabel.TextScaled = true
speedLabel.Text = "0 mph"
speedLabel.Parent = screenGui

local zombieLabel = Instance.new("TextLabel")
zombieLabel.Name = "ZombiesDefeated"
zombieLabel.Size = UDim2.new(0, 220, 0, 30)
zombieLabel.Position = UDim2.new(0, 20, 0, 90)
zombieLabel.BackgroundTransparency = 0
zombieLabel.BackgroundColor3 = UITheme.cycleColor(2) -- тёмно-зелёный
zombieLabel.TextColor3 = UITheme.Ink
zombieLabel.Font = UITheme.Font
zombieLabel.TextScaled = true
zombieLabel.Text = "Zombies Defeated: 0"
zombieLabel.Parent = screenGui

local livesLabel = Instance.new("TextLabel")
livesLabel.Name = "Lives"
livesLabel.Size = UDim2.new(0, 220, 0, 30)
livesLabel.Position = UDim2.new(0, 20, 0, 128)
livesLabel.BackgroundTransparency = 0
livesLabel.BackgroundColor3 = UITheme.cycleColor(3) -- кость (светлая) → тёмный текст
livesLabel.TextColor3 = UITheme.Palette.Red
livesLabel.Font = UITheme.Font
livesLabel.TextScaled = true
livesLabel.Text = "Lives: ♥♥♥"
livesLabel.Parent = screenGui

local wreckedLabel = Instance.new("TextLabel")
wreckedLabel.Name = "WreckedBanner"
wreckedLabel.Size = UDim2.new(0, 420, 0, 60)
wreckedLabel.Position = UDim2.new(0.5, -210, 0.35, 0)
wreckedLabel.BackgroundTransparency = 0
wreckedLabel.BackgroundColor3 = UITheme.Palette.Red
wreckedLabel.TextColor3 = UITheme.Ink
wreckedLabel.Font = UITheme.Font
wreckedLabel.TextScaled = true
wreckedLabel.Text = "VEHICLE DESTROYED"
wreckedLabel.Visible = false
wreckedLabel.Parent = screenGui

-- // Race HUD --------------------------------------------------------------
local raceLabel = Instance.new("TextLabel")
raceLabel.Name = "RaceStatus"
raceLabel.Size = UDim2.new(0, 380, 0, 30)
raceLabel.Position = UDim2.new(0.5, -190, 0, 10)
raceLabel.BackgroundTransparency = 0.45
raceLabel.BackgroundColor3 = UITheme.PanelBg
raceLabel.TextColor3 = UITheme.Ink
raceLabel.Font = UITheme.Font
raceLabel.TextScaled = true
raceLabel.Text = ""
raceLabel.Parent = screenGui

local raceCenter = Instance.new("TextLabel")
raceCenter.Name = "RaceCenter"
raceCenter.Size = UDim2.new(0, 520, 0, 90)
raceCenter.Position = UDim2.new(0.5, -260, 0.2, 0)
raceCenter.BackgroundTransparency = 1
raceCenter.TextColor3 = Color3.fromRGB(255, 220, 120)
raceCenter.Font = UITheme.Font
raceCenter.TextScaled = true
raceCenter.TextStrokeTransparency = 0.4
raceCenter.Text = ""
raceCenter.Parent = screenGui

-- Стрелка-компас: крутится к СЛЕДУЮЩЕМУ чекпоинту относительно камеры.
-- На старте указывает на чекпоинт №1 — видно, в какую сторону ехать.
local arrowFrame = Instance.new("Frame")
arrowFrame.Name = "CheckpointArrow"
arrowFrame.AnchorPoint = Vector2.new(0.5, 0.5)
arrowFrame.Size = UDim2.new(0, 56, 0, 56)
arrowFrame.Position = UDim2.new(0.5, 0, 0.72, 0)
arrowFrame.BackgroundTransparency = 1
arrowFrame.Visible = false
arrowFrame.Parent = screenGui

for _, side in { -1, 1 } do -- шеврон "∧" из двух планок
	local wing = Instance.new("Frame")
	wing.AnchorPoint = Vector2.new(0.5, 0.5)
	wing.Size = UDim2.new(0, 7, 0, 30)
	wing.Position = UDim2.new(0.5, side * 9, 0.5, 6)
	wing.Rotation = side * 40
	wing.BackgroundColor3 = Color3.fromRGB(224, 214, 170) -- кость (был мятный)
	wing.BorderSizePixel = 0
	wing.Parent = arrowFrame
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 3)
	corner.Parent = wing
end

local arrowDistance = Instance.new("TextLabel")
arrowDistance.Name = "CheckpointDistance"
arrowDistance.AnchorPoint = Vector2.new(0.5, 0)
arrowDistance.Size = UDim2.new(0, 120, 0, 20)
arrowDistance.Position = UDim2.new(0.5, 0, 0.72, 34)
arrowDistance.BackgroundTransparency = 1
arrowDistance.TextColor3 = Color3.fromRGB(224, 214, 170)
arrowDistance.TextStrokeTransparency = 0.6
arrowDistance.Font = UITheme.Font
arrowDistance.TextScaled = true
arrowDistance.Visible = false
arrowDistance.Parent = screenGui

local arrowTargetIndex: number? = nil -- индекс чекпоинта, куда показывает стрелка

type RacePayload = {
	Phase: string,
	Countdown: number?,
	Go: boolean?,
	Lap: number?,
	Laps: number?,
	Position: number?,
	Racers: number?,
	NextCheckpoint: number?,
	PlayerWon: boolean?,
	Winner: string?,
	Eliminated: boolean?,
	Waiting: number?,
	Needed: number?,
}

-- достать плашку-картинку черепа из модели чекпоинта (Image ставит сервер в buildSkull)
local function skullFaceImage(model: Model): ImageLabel?
	local anchor = model.PrimaryPart
	local face = anchor and anchor:FindFirstChild("Face")
	local img = face and face:FindFirstChild("Img")
	return (img and img:IsA("ImageLabel")) and (img :: ImageLabel) or nil
end

-- Найти маркер чекпоинта: череп помечен атрибутом cpN (один череп может обслуживать
-- несколько чекпоинтов при совпадении координат — перекрёсток восьмёрки); орб — по имени.
local function findMarker(index: number): Instance?
	local folder = workspace:FindFirstChild("RaceMarkers")
	if not folder then
		return nil
	end
	for _, m in folder:GetChildren() do
		if m:IsA("Model") and m:GetAttribute("cp" .. index) == true then
			return m
		end
	end
	return folder:FindFirstChild("Checkpoint" .. index)
end

-- Внешний вид плашки-черепа: «свой» следующий (active) — чуть крупнее и плотнее,
-- свет ярче; прочие — сильно полупрозрачные (призрачные), свет спокойный.
local skullBaseSize: { [Instance]: UDim2 } = {} -- исходный размер билборда каждого черепа
local skullHome: { [Model]: CFrame } = {} -- «дом» каждого черепа (парение + сброс после сбора)
local collecting: { [Model]: boolean } = {} -- череп сейчас «улетает» вверх → парение его не трогает
local function applySkullState(model: Model, active: boolean)
	if collecting[model] then return end -- «улетающий» череп не трогаем (иначе перебьёт растворение)
	local img = skullFaceImage(model)
	if img then
		img.ImageTransparency = active and 0.70 or 0.87 -- почти прозрачный призрак
	end
	local anchor = model.PrimaryPart
	if anchor then
		local face = anchor:FindFirstChild("Face")
		if face and face:IsA("BillboardGui") then
			local base = skullBaseSize[face]
			if not base then
				base = face.Size
				skullBaseSize[face] = base
			end
			local k = active and 1.15 or 1.0 -- Size в Scale → масштабируется с расстоянием как объект
			face.Size = UDim2.fromScale(base.X.Scale * k, base.Y.Scale * k)
		end
		local light = anchor:FindFirstChildOfClass("PointLight")
		if light and light:IsA("PointLight") then
			light.Brightness = active and 2.2 or 0.7
			light.Range = active and 12 or 7
		end
	end
end

-- Прошёл чекпоинт: череп ВЗМЫВАЕТ В НЕБО (мировые координаты, вверх) и тает
-- дымком, затем возвращается на место к следующему кругу. Для орба — no-op.
local function collectSkull(index: number)
	local marker = findMarker(index)
	if not (marker and marker:IsA("Model")) then return end
	local model = marker :: Model
	local anchor = model.PrimaryPart
	if not anchor then return end
	local home = skullHome[model] or model:GetPivot()
	collecting[model] = true -- пауза парению на время «улёта»

	local spirit = anchor:FindFirstChild("Spirit")
	if spirit and spirit:IsA("ParticleEmitter") then
		spirit:Emit(30)
	end
	local light = anchor:FindFirstChildOfClass("PointLight")
	if light and light:IsA("PointLight") then
		local restore = light.Brightness
		light.Brightness = 6
		TweenService:Create(light, TweenInfo.new(0.6), { Brightness = restore }):Play()
	end
	local img = skullFaceImage(model)
	if img then
		img.ImageTransparency = 0.1 -- на «улёте» череп проявляется, чтобы растворение было видно
	end
	-- вверх с ускорением (в мировом Y) + растворение
	TweenService:Create(anchor, TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = home.Position + Vector3.new(0, 18, 0) }):Play()
	if img then
		TweenService:Create(img, TweenInfo.new(0.75), { ImageTransparency = 1 }):Play()
	end
	task.delay(1.1, function()
		if anchor.Parent then
			anchor.CFrame = home -- вернуть на место к следующему кругу
			if img then
				img.ImageTransparency = 0.87
			end
		end
		collecting[model] = nil
	end)
end

-- Подсветка СВОЕГО следующего чекпоинта — локально, у каждого игрока своя
local function highlightCheckpoint(index: number?)
	local folder = workspace:FindFirstChild("RaceMarkers")
	if not folder then return end
	for _, marker in folder:GetChildren() do
		if marker:IsA("Model") then
			-- череп активен, если обслуживает текущий чекпоинт (атрибут cpN)
			local active = index ~= nil and marker:GetAttribute("cp" .. index) == true
			applySkullState(marker, active)
		elseif marker:IsA("BasePart") then
			local id = marker.Name:match("%d+")
			local i = id and tonumber(id)
			if i then
				local active = (i == index)
				marker.Transparency = active and 0.5 or 0.78 -- орб: спокойный ободок, ленты — основной визуал
				marker.Size = active and Vector3.new(4, 4, 4) or Vector3.new(3, 3, 3)
			end
		end
	end
end

-- Черепа-чекпоинты видны только во время гонки (отсчёт/заезд), а не в
-- «ожидании игроков» и не после финиша. markersVisible=nil — первый вызов всегда срабатывает.
local markersVisible: boolean? = nil
local function setMarkersVisible(visible: boolean)
	if markersVisible == visible then return end
	markersVisible = visible
	local folder = workspace:FindFirstChild("RaceMarkers")
	if not folder then return end
	for _, m in folder:GetChildren() do
		if m:IsA("Model") then
			local anchor = m.PrimaryPart
			if anchor then
				local face = anchor:FindFirstChild("Face")
				if face and face:IsA("BillboardGui") then face.Enabled = visible end
				local light = anchor:FindFirstChildOfClass("PointLight")
				if light then light.Enabled = visible end
			end
		elseif m:IsA("BasePart") then
			m.LocalTransparencyModifier = visible and 0 or 1 -- орб: скрыть локально
			for _, e in m:GetChildren() do
				if e:IsA("Trail") or e:IsA("ParticleEmitter") then e.Enabled = visible end
			end
		end
	end
end

-- Парение черепов-чекпоинтов — локально у каждого клиента (server держит их
-- статичными). Первый кадр фиксирует «дом» (GetPivot), дальше — синусоида по Y.
-- Череп в процессе «улёта» (collecting) не парит — им управляет collectSkull.
RunService.Heartbeat:Connect(function()
	local folder = workspace:FindFirstChild("RaceMarkers")
	if not folder then return end
	local t = os.clock()
	for _, m in folder:GetChildren() do
		if m:IsA("Model") and m.PrimaryPart and not collecting[m] then
			local home = skullHome[m]
			if not home then
				home = m:GetPivot()
				skullHome[m] = home
			end
			local id = m.Name:match("%d+")
			local phase = (id and tonumber(id) or 0) * 0.7
			local y = math.sin(t * 1.3 + phase) * 0.9
			m:PivotTo(home + Vector3.new(0, y, 0))
		end
	end
end)

-- анимация-«пружинка» центрального баннера (GO/победа/финиш)
local raceCenterScale = Instance.new("UIScale")
raceCenterScale.Parent = raceCenter
local function popCenter()
	raceCenterScale.Scale = 0.35
	TweenService:Create(
		raceCenterScale,
		TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
end

raceUpdate.OnClientEvent:Connect(function(data: RacePayload)
	if data.Phase == "Idle" then
		local waiting = data.Waiting or 0
		local needed = data.Needed or 1
		if needed > 1 and waiting > 0 and waiting < needed then
			raceLabel.Text = string.format("Waiting for racers… %d/%d — press READY", waiting, needed)
		elseif needed > 1 then
			raceLabel.Text = string.format("Press READY to race — need %d racers", needed)
		else
			raceLabel.Text = "Press READY to start the race"
		end
		raceCenter.Text = ""
		highlightCheckpoint(nil)
		arrowTargetIndex = nil
		setMarkersVisible(false) -- в ожидании гонки черепов не видно
	elseif data.Phase == "Countdown" then
		raceLabel.Text = string.format("Race: %d laps — follow the green beacons", data.Laps or 3)
		raceCenter.TextColor3 = Color3.fromRGB(255, 220, 120)
		raceCenter.Text = tostring(data.Countdown)
		setMarkersVisible(true) -- гонка начинается → черепа появляются
		arrowTargetIndex = 1 -- ещё на отсчёте показываем, куда стартовать
		highlightCheckpoint(1)
		lastCheckpointIndex = nil -- сброс, чтобы старт не звенел ложно
	elseif data.Phase == "Racing" then
		setMarkersVisible(true) -- на случай подключения в середине заезда
		if data.Go then
			raceCenter.Text = "GO!"
			task.delay(1.5, function()
				if raceCenter.Text == "GO!" then
					raceCenter.Text = ""
				end
			end)
		end
		raceLabel.Text = string.format("Lap %d/%d   ·   Position %d/%d",
			data.Lap or 1, data.Laps or 3, data.Position or 1, data.Racers or 4)
		if data.NextCheckpoint then
			if lastCheckpointIndex ~= nil and data.NextCheckpoint ~= lastCheckpointIndex then
				checkpointSound:Play() -- прошёл чекпоинт → магический звон
				collectSkull(lastCheckpointIndex) -- дух улетает вверх с пройденного черепа (орб — no-op)
			end
			lastCheckpointIndex = data.NextCheckpoint
			highlightCheckpoint(data.NextCheckpoint)
			arrowTargetIndex = data.NextCheckpoint
		end
	elseif data.Phase == "Finished" then
		arrowTargetIndex = nil
		setMarkersVisible(false) -- заезд окончен → прячем до следующего
		popCenter()
		finishSound:Play()
		if data.Eliminated then
			raceCenter.TextColor3 = UITheme.Palette.Red
			raceCenter.Text = "GAME OVER — OUT OF LIVES"
		elseif data.PlayerWon then
			raceCenter.TextColor3 = Color3.fromRGB(255, 210, 70) -- золото
			raceCenter.Text = "YOU WIN!"
		else
			raceCenter.TextColor3 = UITheme.Palette.Red
			raceCenter.Text = string.upper(data.Winner or "GHOST") .. " WINS"
		end
	end
end)

-- // Компас на следующий чекпоинт -------------------------------------------
local function checkpointPosition(index: number): Vector3?
	local marker = findMarker(index)
	if marker then
		if marker:IsA("BasePart") then
			return marker.Position
		elseif marker:IsA("Model") then
			local pp = (marker :: Model).PrimaryPart
			return pp and pp.Position or (marker :: Model):GetPivot().Position
		end
	end
	return nil
end

RunService.RenderStepped:Connect(function()
	local index = arrowTargetIndex
	local camera = workspace.CurrentCamera
	local target = index and checkpointPosition(index)
	if not target or not camera then
		arrowFrame.Visible = false
		arrowDistance.Visible = false
		return
	end

	local camCF = camera.CFrame
	local forward = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
	local toTarget = Vector3.new(target.X - camCF.Position.X, 0, target.Z - camCF.Position.Z)
	if forward.Magnitude < 0.05 or toTarget.Magnitude < 1 then
		return -- камера смотрит вертикально или чекпоинт под нами — оставляем как есть
	end
	forward = forward.Unit
	local dir = toTarget.Unit
	-- знаковый угол между взглядом камеры и целью в плоскости XZ;
	-- Rotation у GUI растёт по часовой, поэтому минус
	local crossY = forward.Z * dir.X - forward.X * dir.Z
	local dot = forward.X * dir.X + forward.Z * dir.Z
	arrowFrame.Rotation = -math.deg(math.atan2(crossY, dot))
	arrowDistance.Text = string.format("%d studs", math.floor(toTarget.Magnitude))
	arrowFrame.Visible = true
	arrowDistance.Visible = true
end)

-- // Live updates ---------------------------------------------------------
type StatsPayload = {
	Health: number,
	MaxHealth: number,
	Speed: number,
	Fuel: number,
	Lives: number?,
	ZombiesDefeated: number,
}

updateStats.OnClientEvent:Connect(function(stats: StatsPayload)
	local ratio = math.clamp(stats.Health / math.max(stats.MaxHealth, 1), 0, 1)
	TweenService:Create(healthFill, TweenInfo.new(0.2), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()
	healthLabel.Text = string.format("Health: %d / %d", stats.Health, stats.MaxHealth)
	speedLabel.Text = string.format("%d mph", math.floor(stats.Speed))
	zombieLabel.Text = string.format("Zombies Defeated: %d", stats.ZombiesDefeated)
	local lives = stats.Lives or 3
	livesLabel.Text = lives > 0 and ("Lives: " .. string.rep("♥", lives)) or "Lives: OUT"

	if stats.Health <= 0 then
		if lives > 0 then
			wreckedLabel.Text = string.format("VEHICLE DESTROYED — %d left", lives)
			wreckedLabel.TextColor3 = UITheme.Ink
		else
			wreckedLabel.Text = "GAME OVER"
			wreckedLabel.TextColor3 = UITheme.Ink
		end
		wreckedLabel.Visible = true
		task.delay(4.5, function()
			wreckedLabel.Visible = false
		end)
	end
end)

-- // Camera shake on hazard hits ------------------------------------------
cameraShakeEvent.OnClientEvent:Connect(function(intensity: number, duration: number)
	task.spawn(function()
		local camera = workspace.CurrentCamera
		local startTime = os.clock()
		while os.clock() - startTime < duration do
			local offset = Vector3.new(
				(math.random() - 0.5) * intensity,
				(math.random() - 0.5) * intensity,
				0
			)
			camera.CFrame = camera.CFrame * CFrame.new(offset)
			RunService.RenderStepped:Wait()
		end
	end)
end)
