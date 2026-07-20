--!strict
-- Script: ServerScriptService.RaceManager
-- Гонка на GameConfig.Race.Laps кругов по восьмёрке MapLayout.TrackSegments.
-- Соперники — ДРУГИЕ ИГРОКИ: каждому VehicleSpawner выдаёт свою машину,
-- прогресс (чекпоинты/круги) считается отдельно на каждого. Победитель —
-- первый, кто закроет все круги. Призраки-пейсеры добавляются к заезду,
-- если GameConfig.Race.GhostsEnabled = true (выключите для чистого PvP).
-- Старт — по отсчёту, когда первый игрок садится за руль; остальные могут
-- присоединиться к заезду на ходу. После финиша гонка перезапускается.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local MapLayout = require(ReplicatedStorage:WaitForChild("MapLayout"))
local ModelFactory = require(script.Parent:WaitForChild("ModelFactory"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local raceUpdate = remotes:WaitForChild("RaceUpdate") :: RemoteEvent

local cfg = GameConfig.Race
local GHOST_Y = 4.3   -- центр шасси призрака: колёса на уровне дороги (Y≈2)
local MARKER_Y = 5.5  -- высота magic-orb: на уровне проезда, сквозь него едут

-- // Сэмплирование трассы ---------------------------------------------------
local function bezier(seg: {Vector2}, t: number): Vector2
	local p0, p1, p2, p3 = seg[1], seg[2], seg[3], seg[4]
	local u = 1 - t
	return p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
end

local points: {Vector3} = {}
for _, seg in MapLayout.TrackSegments do
	for i = 0, 39 do
		local p = bezier(seg, i / 40)
		table.insert(points, Vector3.new(p.X * MapLayout.Scale, GHOST_Y, p.Y * MapLayout.Scale))
	end
end
local segLengths: {number} = {}
local trackLength = 0
for i = 1, #points do
	local nextPoint = points[i % #points + 1]
	segLengths[i] = (nextPoint - points[i]).Magnitude
	trackLength += segLengths[i]
end

-- Точка и направление на дистанции dist (замкнутый круг)
local function sampleAt(dist: number): (Vector3, Vector3)
	local d = dist % trackLength
	local i = 1
	while d > segLengths[i] do
		d -= segLengths[i]
		i = i % #points + 1
	end
	local a = points[i]
	local b = points[i % #points + 1]
	local dir = (b - a).Unit
	return a + dir * d, dir
end

-- // Чекпоинты и маяки --------------------------------------------------------
-- Подсветку "своего" следующего чекпоинта каждый клиент делает сам
-- (UIController), сервер держит маяки одинаковыми.
local checkpoints: {Vector3} = {}
for _, cp in MapLayout.RaceCheckpoints do
	table.insert(checkpoints, Vector3.new(cp.X * MapLayout.Scale, 0, cp.Y * MapLayout.Scale))
end

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
	glow.Brightness = 0.8
	glow.Range = 8
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

-- // Призраки-пейсеры -----------------------------------------------------------
type Ghost = {
	model: Model,
	speed: number,
	dist: number,
	startDist: number,
	stumbleUntil: number,
	name: string,
}

local ghosts: {Ghost} = {}

local function placeGhost(ghost: Ghost)
	local pos, dir = sampleAt(ghost.dist)
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

-- // Гонщики-игроки ---------------------------------------------------------------
type Racer = {
	seat: VehicleSeat,
	cpIndex: number,
	laps: number,
}

-- Кто сейчас сидит за рулём машины с тегом PlayerVehicle
local function occupiedSeats(): {[Player]: VehicleSeat}
	local result: {[Player]: VehicleSeat} = {}
	for _, v in CollectionService:GetTagged("PlayerVehicle") do
		if v:IsA("Model") then
			local seat = v:FindFirstChild("DriveSeat")
			if seat and seat:IsA("VehicleSeat") and seat.Occupant then
				local character = seat.Occupant.Parent
				local plr = character and Players:GetPlayerFromCharacter(character)
				if plr then
					result[plr] = seat
				end
			end
		end
	end
	return result
end

-- // Главный цикл гонки ----------------------------------------------------------
print(`[RaceManager] Трасса {math.floor(trackLength)} studs, {#checkpoints} чекпоинтов, {#ghosts} призраков.`)

while true do
	-- IDLE: заезд стартует только когда за руль сядет ≥ cfg.MinRacers игроков
	repeat
		local seated = 0
		for _ in occupiedSeats() do
			seated += 1
		end
		raceUpdate:FireAllClients({ Phase = "Idle", Waiting = seated, Needed = cfg.MinRacers })
		if seated >= cfg.MinRacers then
			break
		end
		task.wait(0.5)
	until false

	-- сброс всех машин к старту нового заезда (жизни, ремонт, позиция на грид)
	for _, v in CollectionService:GetTagged("PlayerVehicle") do
		if v:IsA("Model") then
			v:SetAttribute("FullReset", os.clock())
		end
	end

	-- COUNTDOWN
	for c = cfg.CountdownSeconds, 1, -1 do
		raceUpdate:FireAllClients({ Phase = "Countdown", Countdown = c, Laps = cfg.Laps })
		task.wait(1)
	end

	-- RACING
	for _, ghost in ghosts do
		ghost.dist = ghost.startDist
		ghost.stumbleUntil = 0
		placeGhost(ghost)
	end
	local racers: {[Player]: Racer} = {}
	local eliminated: {[Player]: boolean} = {}
	local everRaced = false
	local peakRacers = 0 -- пик числа реальных гонщиков (для победы "последнего выжившего")
	local winnerName: string? = nil
	local winnerPlayer: Player? = nil

	raceUpdate:FireAllClients({
		Phase = "Racing", Go = true,
		Lap = 1, Laps = cfg.Laps, Position = 1, Racers = 1, NextCheckpoint = 1,
	})

	local lastTick = os.clock()
	local lastBroadcast = 0
	while not winnerName do
		task.wait() -- каждый кадр: призраки двигаются плавно (вероятности уже нормированы на dt)
		local now = os.clock()
		local dt = now - lastTick
		lastTick = now

		-- регистрация гонщиков (присоединиться можно и после старта)
		for plr, seat in occupiedSeats() do
			if not eliminated[plr] then
				local racer = racers[plr]
				if racer then
					racer.seat = seat
				else
					racers[plr] = { seat = seat, cpIndex = 1, laps = 0 }
				end
			end
		end
		for plr, racer in racers do
			if plr.Parent == nil or racer.seat.Parent == nil then
				racers[plr] = nil -- игрок вышел или его машину убрали
			end
		end
		-- пик числа реальных гонщиков
		local before = 0
		for _ in racers do
			before += 1
		end
		if before > peakRacers then
			peakRacers = before
		end

		-- выбывшие (кончились жизни): убрать из заезда, показать GAME OVER
		for plr, racer in racers do
			local v = racer.seat.Parent
			if v and v:GetAttribute("Eliminated") then
				racers[plr] = nil
				if not eliminated[plr] then
					eliminated[plr] = true
					raceUpdate:FireClient(plr, { Phase = "Finished", Eliminated = true, PlayerWon = false })
				end
			end
		end

		-- итог по реальным гонщикам
		local active, lastPlr = 0, nil
		for plr in racers do
			active += 1
			lastPlr = plr
		end
		if active > 0 then
			everRaced = true
		end
		if not winnerName then
			if peakRacers >= 2 and active == 1 and lastPlr then
				-- все соперники выбыли → последний выживший побеждает
				winnerName = (lastPlr :: Player).DisplayName
				winnerPlayer = lastPlr
			elseif everRaced and active == 0 then
				break -- все выбыли/ушли — заезд окончен без победителя
			end
		end

		-- призраки: движение + случайные спотыкания
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

		-- игроки: прохождение чекпоинтов по порядку
		for plr, racer in racers do
			local target = checkpoints[racer.cpIndex]
			local seatPos = racer.seat.Position
			local dx, dz = seatPos.X - target.X, seatPos.Z - target.Z
			if math.sqrt(dx * dx + dz * dz) <= cfg.CheckpointRadius then
				racer.cpIndex += 1
				if racer.cpIndex > #checkpoints then
					racer.cpIndex = 1
					racer.laps += 1
					if racer.laps >= cfg.Laps then
						winnerName = plr.DisplayName
						winnerPlayer = plr
					end
				end
			end
		end

		-- персональная трансляция каждому гонщику
		if now - lastBroadcast >= 0.4 and not winnerName then
			lastBroadcast = now
			local progresses: {number} = {}
			local playerProgress: {[Player]: number} = {}
			for plr, racer in racers do
				local p = racer.laps + (racer.cpIndex - 1) / #checkpoints
				playerProgress[plr] = p
				table.insert(progresses, p)
			end
			for _, ghost in ghosts do
				table.insert(progresses, (ghost.dist - ghost.startDist) / trackLength)
			end
			for plr, racer in racers do
				local mine = playerProgress[plr]
				local position = 1
				for _, p in progresses do
					if p > mine then
						position += 1
					end
				end
				raceUpdate:FireClient(plr, {
					Phase = "Racing",
					Lap = math.min(racer.laps + 1, cfg.Laps),
					Laps = cfg.Laps,
					Position = position,
					Racers = #progresses,
					NextCheckpoint = racer.cpIndex,
				})
			end
		end
	end

	-- СТОП после финиша: замораживаем все машины на время экрана победы
	-- (сиденья снова включатся на старте следующего заезда через FullReset)
	for _, v in CollectionService:GetTagged("PlayerVehicle") do
		if v:IsA("Model") then
			local vseat = v:FindFirstChild("DriveSeat")
			if vseat and vseat:IsA("VehicleSeat") then
				vseat.Disabled = true
			end
			for _, p in v:GetDescendants() do
				if p:IsA("BasePart") then
					p.AssemblyLinearVelocity = Vector3.zero
					p.AssemblyAngularVelocity = Vector3.zero
				end
			end
		end
	end

	-- FINISHED: каждому — его результат (выбывшие уже получили GAME OVER)
	for _, plr in Players:GetPlayers() do
		if not eliminated[plr] then
			raceUpdate:FireClient(plr, {
				Phase = "Finished",
				PlayerWon = plr == winnerPlayer,
				Winner = winnerName,
			})
		end
	end
	task.wait(8)
end
