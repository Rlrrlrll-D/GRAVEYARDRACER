--!strict
-- ModuleScript: ServerScriptService.RaceScene
-- Визуальная сцена заезда, вынесена из старого RaceManager (веха 4): маркеры
-- чекпоинтов (орбы/черепа) строятся при загрузке; призраки-соперники выпускаются
-- на конкретный заезд (spawnGhosts) и двигаются шагами stepGhosts, которые
-- дёргает MatchManager в фазе Racing. Никакой логики фаз здесь нет — исход
-- заезда считает RaceCore, сюда он только спрашивает, кто из призраков впереди.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
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
-- Цвет и форма черепа-чекпоинта живут у КЛИЕНТА (UIController: SKULL_COLOR + меш из
-- ReplicatedStorage.SkullOutline) — здесь они больше не нужны, сервер держит лишь якорь.
-- Прежний ассет-силуэт, если понадобится вернуть: rbxassetid://79551611166203

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

-- череп-Каспер: плоская плашка-силуэт (SVG юзера — мягкие края, глазницы и
-- промежутки между зубами вырезаны насквозь), нарисованная билбордом, то есть всегда
-- лицом к камере. Плюс ореол из копий той же плашки — см. подробности ниже.
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

	-- ВИД ЧЕРЕПА СОБИРАЕТ КЛИЕНТ, здесь только невидимый якорь.
	--
	-- Юзер: «ты можешь сделать плашку неоновой как стрелки?». Может, но силуэт для
	-- этого обязан быть ДЕТАЛЬЮ: Material = Neon есть у детали, у ImageLabel его нет,
	-- а блюм берёт только то, что ярче единицы (BloomEffect.Threshold = 1.5 в этом
	-- плейсе) — пиксель UI ярче 1.0 не бывает. Поэтому плашка теперь меш, собранный
	-- из силуэта (ReplicatedStorage.SkullOutline) через EditableMesh.
	--
	-- А строит его КЛИЕНТ (UIController), потому что меш из EditableMesh НЕ
	-- реплицируется: собери его сервер — игроки увидели бы пустое место. Сервер
	-- держит якорь, теги и атрибуты (по ним работают логика гонки, компас и подсветка),
	-- клиент навешивает вид.
	-- ЧЕРЕП ДЕРЖИМ У ВСЕХ КЛИЕНТОВ ЦЕЛИКОМ. Радиус стриминга опущен до 300
	-- (2026-09-04, оптимизация под телефон), и дальний чекпоинт стал уезжать из
	-- клиента НЕ ЦЕЛИКОМ, а огрызком: замер сразу после правки поймал Checkpoint5 с
	-- одной деталью вместо двух и пивотом в (0, 0, 0). По пивоту работают компас и
	-- подсветка — стрелка показывала бы в центр карты, а не на чекпоинт. Двенадцать
	-- моделей по две детали стоят пренебрежимо мало, поэтому держим их всегда.
	-- (Ветка buildOrb этого не умеет: там маркер — голая Part, а ModelStreamingMode
	-- есть только у Model. Сейчас стиль "skull", см. GameConfig.Race.CheckpointStyle.)
	skull.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
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
-- ПРИЗРАКИ = ДОБОР СОСТАВА, а не постоянная декорация. Их выпускают на КОНКРЕТНЫЙ
-- заезд (spawnGhosts на отсчёте) и снимают в конце (clearGhosts): раньше они
-- создавались один раз при старте сервера и болтались по трассе всегда, даже
-- когда живых гонщиков полный грид.
--
-- Едут они по осевой (RaceCore.sampleAt) со СВОЕЙ полосой — той же, что дают
-- игрокам стартовые места PlayerFlow, — а темп подстраивают под лидера
-- (GhostCatchUp/GhostBand): на нашей трассе фиксированная скорость либо уезжает
-- за горизонт, либо отстаёт на круг, а призрак нужен рядом, для борьбы.
--
-- Вид: не примитив ModelFactory.Buggy, а ВИДИМЫЕ детали настоящего багги
-- (VehicleTemplate) в материале ForceField. Видимых деталей всего 7 из 106 —
-- остальное у A-Chassis невидимая механика (клинья кузова, интерфейсы, звуки),
-- поэтому призрака дёшево двигать целиком каждый кадр.
type Ghost = {
	model: Model,
	pivotFromSeat: CFrame, -- пивот модели относительно её сиденья (как в PlayerFlow)
	speed: number, -- база, studs/сек
	dist: number, -- пройдено по осевой (от стартовой отметки)
	startDist: number,
	lane: number, -- смещение от осевой вбок: своя полоса, чтобы не слипались
	offset: number, -- где призрак ХОЧЕТ быть относительно лидера, studs
	weave: number, -- фаза покачивания в полосе
	stumbleUntil: number,
	name: string,
}

-- Раскладка грида повторяет PlayerFlow: нечётные места слева от осевой, чётные
-- справа, ряды на GRID_ROW_GAP назад; сиденье сдвинуто так, чтобы по центру
-- полосы шёл КУЗОВ. Цифры продублированы осознанно — в PlayerFlow они локальные,
-- и тащить сюда весь модуль ради двух констант незачем.
local GRID_LANE = 8
local GRID_ROW_GAP = 18.1
local CAR_SEAT_OFFSET_X = 1.6
local STUMBLE_SPEED = 0.35 -- «спотыкание» = резкий сброс хода, а НЕ стоп колом (полная остановка читается как поломка)
local WEAVE_AMPLITUDE = 1.6 -- покачивание в полосе: живой водитель, а не рельса
local WEAVE_RATE = 0.6

-- Просвет: настоящая машина, осев на полотно, держит низ кузова примерно на
-- столько над дорогой (у неё физические колёса крупнее видимого меша). Призраку
-- физики не досталось, поэтому высоту считаем сами — от ПОЛОТНА, а не от машины
-- игрока: у той в момент выпуска призраков ещё качается подвеска A-Chassis, и по
-- её сиденью призрак вставал на два studs ниже, чем надо.
local RIDE_CLEARANCE = 0.5

local ghosts: { Ghost } = {}
local ghostFolder: Folder? = nil
local ghostBaseY = 8.3 -- Y «сиденья» призрака: считается по полотну в spawnGhosts

-- // Шаблон вида -------------------------------------------------------------
local sourceParts: { BasePart } = {}
local sourceSeatCF = CFrame.new()
local sourceBottomY = 0 -- низ видимой машины в координатах сиденья (у нашей багги ≈ -1.78)
local sourceReady = false

-- Нижняя точка габаритов детали по оси Y относительно frame.
local function bottomOf(rel: CFrame, size: Vector3): number
	local ext = 0.5
		* (math.abs(rel.RightVector.Y) * size.X + math.abs(rel.UpVector.Y) * size.Y + math.abs(rel.LookVector.Y) * size.Z)
	return rel.Y - ext
end

local function collectSource()
	if sourceReady then
		return
	end
	sourceReady = true
	local t = ServerStorage:FindFirstChild("VehicleTemplate")
	local seat = t and t:FindFirstChild("DriveSeat")
	if t and t:IsA("Model") and seat and seat:IsA("BasePart") then
		sourceSeatCF = seat.CFrame
		for _, d in t:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 0.95 then
				table.insert(sourceParts, d)
			end
		end
	end
	if #sourceParts == 0 then
		-- запасной вариант (машины-меша нет): примитивный багги, как было раньше
		warn("[RaceScene] VehicleTemplate не найден — призраки собираются из примитивов.")
		local m = ModelFactory.Buggy()
		m.Name = "GhostSourceFallback"
		m.Parent = ServerStorage -- держим вне workspace: из него только клонируем детали
		local s2 = m:FindFirstChild("DriveSeat")
		sourceSeatCF = (s2 and s2:IsA("BasePart")) and s2.CFrame or m:GetPivot()
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(sourceParts, d)
			end
		end
	end
	sourceBottomY = math.huge
	for _, d in sourceParts do
		sourceBottomY = math.min(sourceBottomY, bottomOf(sourceSeatCF:Inverse() * d.CFrame, d.Size))
	end
end

local function buildGhostModel(spec: { Name: string, Speed: number, Offset: number, Color: Color3 }): (Model, CFrame)
	collectSource()
	local model = Instance.new("Model")
	model.Name = "Ghost_" .. (spec.Name:gsub("%s", ""))
	local root: BasePart? = nil
	for _, src in sourceParts do
		local part = src:Clone()
		for _, child in part:GetChildren() do
			-- оставляем только форму: скрипты, звуки, свет, аттачменты и сварки призраку
			-- не нужны и тянут за собой чужую логику
			if not (child:IsA("SpecialMesh") or child:IsA("BlockMesh") or child:IsA("CylinderMesh")) then
				child:Destroy()
			end
		end
		if part:IsA("MeshPart") then
			-- запечённая текстура перебивает ForceField: с ней «призрак» выглядит обычной машиной
			pcall(function()
				(part :: MeshPart).TextureID = ""
			end)
		end
		part.Anchored = true
		part.CanCollide = false -- сквозь призрака проезжают: он соперник по темпу, а не таран
		part.CanQuery = false -- и пули с прицелом турели проходят насквозь
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.ForceField
		part.Color = spec.Color
		part.CFrame = sourceSeatCF:Inverse() * src.CFrame -- собираем в системе координат СИДЕНЬЯ
		part.Parent = model
		if root == nil or part.Size.Magnitude > (root :: BasePart).Size.Magnitude then
			root = part -- самая крупная деталь = кузов, он и якорь модели
		end
	end
	model.PrimaryPart = root

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 140, 0, 24)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.Parent = model.PrimaryPart
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 1, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.Creepster -- шрифт в UI один (UITheme.Font); модуль серверный, тему не тянет
	nameLabel.TextColor3 = spec.Color
	nameLabel.TextStrokeTransparency = 0.5
	nameLabel.Text = spec.Name
	nameLabel.Parent = billboard

	return model, model:GetPivot() -- пивот пока считан в координатах сиденья = pivotFromSeat
end

-- // Движение ----------------------------------------------------------------
local function placeGhost(ghost: Ghost, now: number)
	local pos, dir = RaceCore.sampleAt(ghost.dist)
	local at = Vector3.new(pos.X, ghostBaseY, pos.Z)
	local base = CFrame.lookAt(at, at + Vector3.new(dir.X, 0, dir.Z))
	local weave = math.sin(now * WEAVE_RATE + ghost.weave) * WEAVE_AMPLITUDE
	ghost.model:PivotTo(base * CFrame.new(ghost.lane + weave - CAR_SEAT_OFFSET_X, 0, 0) * ghost.pivotFromSeat)
end

-- Снять всех призраков (конец заезда).
function RaceScene.clearGhosts()
	for _, ghost in ghosts do
		ghost.model:Destroy()
	end
	table.clear(ghosts)
end

-- Высота призраков над полотном. Полотно ровное (его красит MapBuilder), поэтому
-- меряем один раз на старте: рейкаст ТОЛЬКО по террейну, чтобы не поймать
-- надгробие или машину.
local function measureBaseY()
	collectSource()
	local start = RaceCore.sampleAt(0)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(start.X, 80, start.Z), Vector3.new(0, -160, 0), rp)
	-- запасная высота: террейн рисуется выше номинального верха плиты примерно на
	-- столько же, сколько меряет рейкастом PlayerFlow под стартовую решётку
	local roadY = hit and hit.Position.Y or ((GameConfig.Map.GroundTop or 2) + 4)
	ghostBaseY = roadY + RIDE_CLEARANCE - sourceBottomY
end

-- Выпустить `count` призраков на места грида, начиная с `firstSlot` (следующего
-- за живыми гонщиками).
function RaceScene.spawnGhosts(count: number, firstSlot: number)
	RaceScene.clearGhosts()
	if count <= 0 or #cfg.Ghosts == 0 then
		return
	end
	measureBaseY()
	if not ghostFolder or not (ghostFolder :: Folder).Parent then
		local folder = Instance.new("Folder")
		folder.Name = "RaceGhosts"
		folder.Parent = workspace
		ghostFolder = folder
	end
	for k = 1, count do
		local spec = cfg.Ghosts[(k - 1) % #cfg.Ghosts + 1]
		local slot = firstSlot + k - 1
		local row = math.ceil(slot / 2) - 1
		local model, pivotFromSeat = buildGhostModel(spec)
		local ghost: Ghost = {
			model = model,
			pivotFromSeat = pivotFromSeat,
			speed = spec.Speed,
			dist = -row * GRID_ROW_GAP, -- стартовое место: ряд ПОЗАДИ линии старта
			startDist = -row * GRID_ROW_GAP,
			lane = (slot % 2 == 1) and -GRID_LANE or GRID_LANE,
			offset = spec.Offset,
			weave = math.random() * math.pi * 2,
			stumbleUntil = 0,
			name = spec.Name,
		}
		placeGhost(ghost, 0)
		-- Целиком у всех клиентов, как и машины игроков: под стримингом модель
		-- приезжала бы по частям и призрак «собирался» бы на глазах.
		model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		model.Parent = ghostFolder
		for _, plr in Players:GetPlayers() do
			pcall(function()
				model:AddPersistentPlayer(plr)
			end)
		end
		table.insert(ghosts, ghost)
	end
end

function RaceScene.ghostCount(): number
	return #ghosts
end

-- Один кадр движения призраков. `leadProgress` — прогресс лидера среди ЖИВЫХ
-- гонщиков в кругах (RaceCore.Session.leadProgress); по нему призрак решает,
-- поддать или придержать, чтобы держаться своего места относительно игрока.
function RaceScene.stepGhosts(now: number, dt: number, leadProgress: number?)
	local pace = leadProgress and leadProgress * RaceCore.TrackLength or nil
	for _, ghost in ghosts do
		local speed = ghost.speed
		if pace then
			local err = (pace + ghost.offset) - (ghost.dist - ghost.startDist)
			speed *= 1 + math.clamp(err / cfg.GhostBand, -1, 1) * cfg.GhostCatchUp
		end
		if now < ghost.stumbleUntil then
			speed *= STUMBLE_SPEED
		elseif math.random() < cfg.StumbleChancePerSecond * dt then
			ghost.stumbleUntil = now + cfg.StumbleDuration
		end
		ghost.dist += speed * dt
		placeGhost(ghost, now)
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

-- Имя ведущего призрака: ему достаётся победа, если живых на дистанции не осталось.
function RaceScene.leadGhostName(): string?
	local best, bestName = -math.huge, nil :: string?
	for _, ghost in ghosts do
		local p = ghost.dist - ghost.startDist
		if p > best then
			best, bestName = p, ghost.name
		end
	end
	return bestName
end

-- Призрак, закрывший все круги: заезд окончен, живые проиграли. Раньше призраки
-- не побеждали принципиально — и одиночка получал «YOU WIN», даже приехав последним.
function RaceScene.finishedGhost(): string?
	for _, ghost in ghosts do
		if (ghost.dist - ghost.startDist) >= cfg.Laps * RaceCore.TrackLength then
			return ghost.name
		end
	end
	return nil
end

return RaceScene
