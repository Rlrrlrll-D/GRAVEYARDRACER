--!strict
-- ModuleScript: ServerScriptService.RaceScene
-- Визуальная сцена заезда, вынесена из старого RaceManager (веха 4): маркеры
-- чекпоинтов (орбы/черепа) строятся при загрузке; призраки-пейсеры создаются
-- по GameConfig.Race.GhostsEnabled и двигаются шагами stepGhosts, которые
-- дёргает MatchManager в фазе Racing. Никакой логики фаз/победителя здесь нет.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local ModelFactory = require(script.Parent:WaitForChild("ModelFactory"))
local RaceCore = require(script.Parent:WaitForChild("RaceCore"))

local cfg = GameConfig.Race
local MARKER_Y = 11 -- над полотном (террейн ~Y6): череп парит, машина проезжает под ним

local RaceScene = {}

local checkpoints = RaceCore.Checkpoints

-- // Маркеры чекпоинтов -------------------------------------------------------
-- Подсветку "своего" следующего чекпоинта каждый клиент делает сам
-- (UIController), сервер держит маяки одинаковыми.
local markerFolder = Instance.new("Folder")
markerFolder.Name = "RaceMarkers"
markerFolder.Parent = workspace
local ORB_COLOR = Color3.fromRGB(120, 255, 200) -- магический сине-зелёный (в тон "green beacons")
-- Плашка-череп: точный силуэт из SVG пользователя (белый, мягкие края, глазницы/
-- зубы вырезаны насквозь), загружен как image-ассет — без EditableImage/верификации.
local SKULL_IMAGE = "rbxassetid://79551611166203"

-- magic-orb: полая мерцающая сфера + орбитальные светящиеся ленты
local function buildOrb(cp: Vector3, i: number)
	local marker = Instance.new("Part")
	marker.Name = "Checkpoint" .. i
	marker.Shape = Enum.PartType.Ball
	marker.Size = Vector3.new(3.2, 3.2, 3.2)
	marker.Material = Enum.Material.ForceField -- полая мерцающая оболочка, без сплошной заливки
	marker.Color = ORB_COLOR
	marker.Transparency = 0.4
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.CastShadow = false
	marker.Position = Vector3.new(cp.X, MARKER_Y, cp.Z)
	marker.Parent = markerFolder

	-- magic orb: светящиеся ленты ОРБИТАЛЬНО скользят по поверхности сферы
	-- (направленный вихрь, не пятна). Ленты едут вращением орба — дёшево.
	local ORBIT_TILT = 20
	marker.Orientation = Vector3.new(ORBIT_TILT, 0, 0)
	for k = 1, 3 do
		local phi = math.rad(k * 48 - 28) -- разная широта → разные орбиты
		local r = 1.55
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, math.sin(phi) * r, math.cos(phi) * r)
		a0.Parent = marker
		local a1 = Instance.new("Attachment")
		a1.Position = a0.Position * 0.72 -- чуть внутрь → ширина ленты
		a1.Parent = marker
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new(ORB_COLOR)
		trail.LightEmission = 1
		trail.LightInfluence = 0
		trail.Lifetime = 0.9
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.WidthScale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0),
		})
		trail.FaceCamera = true
		trail.Parent = marker
	end

	-- вращение → ленты орбитально скользят (5с оборот)
	local spin = TweenService:Create(
		marker,
		TweenInfo.new(5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
		{ Orientation = Vector3.new(ORBIT_TILT, 360, 0) }
	)
	spin:Play()

	-- лёгкое парение вверх-вниз (Position клиентский highlight не трогает)
	local bob = TweenService:Create(
		marker,
		TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = Vector3.new(cp.X, MARKER_Y + 1.3, cp.Z) }
	)
	bob:Play()
end

-- череп-Каспер: плоская полупрозрачная плашка (силуэт из SVG пользователя —
-- мягкие размытые края, глазницы и промежутки между зубами вырезаны насквозь).
-- Рисуется билбордом (всегда «лицом» к камере). Само изображение (EditableImage)
-- накладывает клиент (UIController) — оно client-side и не реплицируется; сервер
-- держит каркас: невидимый якорь + BillboardGui с пустым ImageLabel + свет + «дух».
local function buildSkull(cp: Vector3, i: number): Model
	local centre = Vector3.new(cp.X, MARKER_Y, cp.Z)

	local skull = Instance.new("Model")
	skull.Name = "Checkpoint" .. i

	local anchor = Instance.new("Part")
	anchor.Name = "Cranium" -- имя сохранено: PrimaryPart для highlight/компаса/парения
	anchor.Shape = Enum.PartType.Ball
	anchor.Size = Vector3.new(0.6, 0.6, 0.6)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Position = centre
	anchor.Parent = skull
	skull.PrimaryPart = anchor

	local glow = Instance.new("PointLight")
	glow.Color = ORB_COLOR
	glow.Brightness = 2.5 -- ярче: череп заметно светится над трассой
	glow.Range = 16
	glow.Parent = anchor

	-- плоская плашка-череп; клиент кладёт EditableImage в ImageLabel "Img"
	local face = Instance.new("BillboardGui")
	face.Name = "Face"
	face.Size = UDim2.fromScale(4.2, 4.7) -- Scale (относительно якоря 0.6): ~2.5 studs, масштабируется с расстоянием как объект (offset давал постоянный экранный размер → казался «наоборот»)
	face.LightInfluence = 0 -- полноярко: «светится», не темнеет ночью
	face.Parent = anchor
	local img = Instance.new("ImageLabel")
	img.Name = "Img"
	img.Size = UDim2.new(1, 0, 1, 0)
	img.BackgroundTransparency = 1
	img.Image = SKULL_IMAGE
	img.ImageTransparency = 0.87 -- почти прозрачный призрак
	img.Parent = face

	-- «дух улетает вверх»: залп дымка при прохождении (эмитит клиент через :Emit)
	local spirit = Instance.new("ParticleEmitter")
	spirit.Name = "Spirit"
	spirit.Texture = "rbxasset://textures/particles/smoke_main.dds"
	spirit.Color = ColorSequence.new(ORB_COLOR)
	spirit.LightEmission = 0.9
	spirit.LightInfluence = 0
	spirit.Rate = 0
	spirit.Enabled = false
	spirit.Lifetime = NumberRange.new(0.8, 1.3)
	spirit.Speed = NumberRange.new(8, 13)
	spirit.SpreadAngle = Vector2.new(18, 18)
	spirit.Acceleration = Vector3.new(0, 16, 0)
	spirit.EmissionDirection = Enum.NormalId.Top
	spirit.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2.2),
		NumberSequenceKeypoint.new(1, 4.5),
	})
	spirit.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	spirit.Parent = anchor

	skull.Parent = markerFolder
	-- парение/изображение/подсветка — на клиенте (UIController skull-bob).
	return skull
end

-- Чекпоинты с совпадающими координатами (перекрёсток восьмёрки: 5-й и 10-й в
-- одной точке) делят ОДИН череп — иначе два маркера накладываются/двоятся.
-- Каждый череп помечается атрибутом cpN для каждого «своего» чекпоинта.
local skullByPos: { [string]: Model } = {}
for i, cp in checkpoints do
	if cfg.CheckpointStyle == "skull" then
		local key = string.format("%d,%d", math.round(cp.X), math.round(cp.Z))
		local existing = skullByPos[key]
		if existing then
			existing:SetAttribute("cp" .. i, true)
		else
			local m = buildSkull(cp, i)
			m:SetAttribute("cp" .. i, true)
			skullByPos[key] = m
		end
	else
		buildOrb(cp, i)
	end
end

-- // Призраки-пейсеры ---------------------------------------------------------
type Ghost = {
	model: Model,
	speed: number,
	dist: number,
	startDist: number,
	stumbleUntil: number,
	name: string,
}

local ghosts: { Ghost } = {}

local function placeGhost(ghost: Ghost)
	local pos, dir = RaceCore.sampleAt(ghost.dist)
	ghost.model:PivotTo(CFrame.lookAt(pos, pos + dir))
end

if cfg.GhostsEnabled then
	for i, spec in cfg.Ghosts do
		local model = ModelFactory.Buggy()
		model.Name = spec.Name
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.Color = spec.Color
				part.Material = Enum.Material.ForceField
			end
		end
		local seat = model:FindFirstChild("DriveSeat")
		if seat and seat:IsA("VehicleSeat") then
			seat.Disabled = true
		end

		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.new(0, 140, 0, 24)
		billboard.StudsOffset = Vector3.new(0, 4, 0)
		billboard.Parent = model.PrimaryPart
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, 0, 1, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.TextScaled = true
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextColor3 = spec.Color
		nameLabel.TextStrokeTransparency = 0.5
		nameLabel.Text = spec.Name
		nameLabel.Parent = billboard

		model.Parent = workspace
		local ghost: Ghost = {
			model = model,
			speed = spec.Speed,
			dist = i * 7,
			startDist = i * 7,
			stumbleUntil = 0,
			name = spec.Name,
		}
		placeGhost(ghost)
		table.insert(ghosts, ghost)
	end
end

RaceScene.GhostCount = #ghosts

-- Вернуть призраков на стартовые позиции (перед отсчётом).
function RaceScene.resetGhosts()
	for _, ghost in ghosts do
		ghost.dist = ghost.startDist
		ghost.stumbleUntil = 0
		placeGhost(ghost)
	end
end

-- Один кадр движения призраков: скорость + случайные «спотыкания».
function RaceScene.stepGhosts(now: number, dt: number)
	for _, ghost in ghosts do
		if now >= ghost.stumbleUntil then
			if math.random() < cfg.StumbleChancePerSecond * dt then
				ghost.stumbleUntil = now + cfg.StumbleDuration
			else
				ghost.dist += ghost.speed * dt
				placeGhost(ghost)
				-- призраки — тренажёр-пейсеры, НЕ побеждают (исход — только реальные игроки)
			end
		end
	end
end

-- Прогресс призраков в кругах (для standings RaceCore).
function RaceScene.ghostProgresses(): { number }
	local out: { number } = {}
	for _, ghost in ghosts do
		table.insert(out, (ghost.dist - ghost.startDist) / RaceCore.TrackLength)
	end
	return out
end

return RaceScene
