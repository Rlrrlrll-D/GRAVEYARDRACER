--!strict
-- Script: ServerScriptService.MapBuilder
-- Программная расстановка объектов по данным ReplicatedStorage.MapLayout.
-- Каждый объект опускается на землю рейкастом и получает нужный тег
-- (Hazard / Grave / FlickerLight) — та же система, что и при ручной расстановке,
-- так что все остальные скрипты работают без изменений.
--
-- ШАБЛОНЫ (необязательно): создайте в ServerStorage папку "MapTemplates"
-- с моделями "Tombstone", "GraveMarker", "Lamp", "DeadTree" — билдер будет
-- клонировать их. Если папки/модели нет, создаются простые Part-заглушки,
-- которые потом можно заменить красивыми моделями, не трогая координаты.

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")

local MapLayout = require(ReplicatedStorage:WaitForChild("MapLayout"))

local RAYCAST_HEIGHT = 200 -- с какой высоты искать землю
local mapFolder = Instance.new("Folder")
mapFolder.Name = "GeneratedMap"
mapFolder.Parent = workspace

-- // Генерация Terrain-дороги по осевой (форма из Road.svg) -------------------
local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
if GameConfig.Map.GenerateRoad and MapLayout.TrackPolyline and #MapLayout.TrackPolyline > 0 then
	local MapGen = require(script.Parent:WaitForChild("MapGen"))
	MapGen.paintPolyline(MapLayout.TrackPolyline, {
		scale = MapLayout.Scale,
		width = GameConfig.Map.RoadWidth,
		top = GameConfig.Map.GroundTop,
		slab = GameConfig.Map.SlabThick,
		area = Vector2.new(GameConfig.Map.AreaW, GameConfig.Map.AreaH),
	})
	task.wait() -- дать террейну примениться перед рейкастами декора
end

local templates = ServerStorage:FindFirstChild("MapTemplates")

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.FilterDescendantsInstances = { mapFolder }

local function groundPosition(x: number, z: number): Vector3
	local origin = Vector3.new(x, RAYCAST_HEIGHT, z)
	local result = workspace:Raycast(origin, Vector3.new(0, -RAYCAST_HEIGHT * 2, 0), raycastParams)
	if result then
		return result.Position
	end
	warn(`[MapBuilder] Земля не найдена под ({x}, {z}) — объект поставлен на Y=0.`)
	return Vector3.new(x, 0, z)
end

-- Позиция травы (не дороги) под (x,z), либо nil если там дорога/ничего.
-- Дорога = Terrain Material Ground, трава = Grass.
local function grassPosition(x: number, z: number): Vector3?
	local origin = Vector3.new(x, RAYCAST_HEIGHT, z)
	local r = workspace:Raycast(origin, Vector3.new(0, -RAYCAST_HEIGHT * 2, 0), raycastParams)
	if r and r.Instance == workspace.Terrain and r.Material == Enum.Material.Grass then
		return r.Position
	end
	return nil
end

local function getTemplate(name: string): Model?
	if templates then
		local model = templates:FindFirstChild(name)
		if model and model:IsA("Model") then
			return model
		end
	end
	return nil
end

-- Как getTemplate, но собирает все варианты "Name" и "Name_*"
-- (например Tombstone + Tombstone_B) и выбирает случайный.
local function getTemplateVariant(name: string): Model?
	if not templates then
		return nil
	end
	local variants = {}
	for _, child in templates:GetChildren() do
		if child:IsA("Model") and (child.Name == name or child.Name:sub(1, #name + 1) == name .. "_") then
			table.insert(variants, child)
		end
	end
	if #variants == 0 then
		return nil
	end
	return variants[math.random(#variants)]
end

-- Заглушка, если шаблона нет: простая Part с подписью для лёгкой замены.
local function makePlaceholder(name: string, size: Vector3, color: Color3): Model
	local model = Instance.new("Model")
	model.Name = name
	local part = Instance.new("Part")
	part.Name = "Body"
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.Slate
	part.Anchored = true
	part.Parent = model
	model.PrimaryPart = part
	return model
end

-- Опустить модель на заданную точку земли, сохранив её собственную ориентацию
-- (у Lamp/DeadTree PrimaryPart — повёрнутый цилиндр), добавив поворот вокруг Y.
local function dropToGround(model: Model, ground: Vector3, rotationDeg: number)
	local pivot = model:GetPivot()
	local yaw = CFrame.Angles(0, math.rad(rotationDeg), 0)
	model:PivotTo(CFrame.new(pivot.Position) * yaw * pivot.Rotation)
	-- Низ модели ищем по мировому минимуму Y всех партов: GetBoundingBox
	-- ориентирован по пивоту и для повёрнутых пивотов даёт неверную высоту.
	local minY = math.huge
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			local cf, half = p.CFrame, p.Size / 2
			local ext = math.abs(cf.RightVector.Y) * half.X
				+ math.abs(cf.UpVector.Y) * half.Y
				+ math.abs(cf.LookVector.Y) * half.Z
			minY = math.min(minY, cf.Position.Y - ext)
		end
	end
	local cur = model:GetPivot()
	model:PivotTo(cur + Vector3.new(ground.X - cur.Position.X, ground.Y - minY, ground.Z - cur.Position.Z))
end

local function place(model: Model, x: number, z: number, rotation: number?)
	local scale = MapLayout.Scale
	local ground = groundPosition(x * scale, z * scale)
	dropToGround(model, ground, rotation or 0)
	model.Parent = mapFolder
end

-- Ближайшая точка ТРАВЫ к (x,z) — спиральный поиск (декор не встаёт на дорогу).
local function grassGround(x: number, z: number): Vector3
	local g = grassPosition(x, z)
	if g then
		return g
	end
	for radius = 8, 60, 8 do
		for a = 0, 315, 45 do
			local cand = grassPosition(x + radius * math.cos(math.rad(a)), z + radius * math.sin(math.rad(a)))
			if cand then
				return cand
			end
		end
	end
	return groundPosition(x, z) -- крайний случай
end

-- Как place, но прилипает к ближайшей траве (для hazard/grave/lamp у обочины).
local function placeOnGrass(model: Model, x: number, z: number, rotation: number?)
	local scale = MapLayout.Scale
	dropToGround(model, grassGround(x * scale, z * scale), rotation or 0)
	model.Parent = mapFolder
end

-- // Hazards (надгробия-плиты у дороги) ------------------------------------
for _, data in MapLayout.Hazards do
	local model = getTemplateVariant("Tombstone")
	model = model and model:Clone() or makePlaceholder("Tombstone", Vector3.new(3, 4, 1.2), Color3.fromRGB(120, 120, 130))
	placeOnGrass(model, data.Position.X, data.Position.Y, data.Rotation)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			PhysicsService:SetPartCollisionGroup(part, "Obstacles")
		end
	end
	CollectionService:AddTag(model, "Hazard")
end

-- // Graves (точки спавна зомби) --------------------------------------------
for _, data in MapLayout.Graves do
	local model = getTemplate("GraveMarker")
	model = model and model:Clone() or makePlaceholder("GraveMarker", Vector3.new(4, 0.4, 7), Color3.fromRGB(70, 60, 50))
	placeOnGrass(model, data.Position.X, data.Position.Y, data.Rotation)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	CollectionService:AddTag(model, "Grave")
end

-- // Lamps (мерцающие фонари) -------------------------------------------------
for _, data in MapLayout.Lamps do
	local model = getTemplate("Lamp")
	local isPlaceholder = false
	if model then
		model = model:Clone()
	else
		isPlaceholder = true
		model = makePlaceholder("Lamp", Vector3.new(0.8, 9, 0.8), Color3.fromRGB(40, 40, 48))
		local bulb = Instance.new("Part")
		bulb.Name = "Bulb"
		bulb.Shape = Enum.PartType.Ball
		bulb.Size = Vector3.new(1.4, 1.4, 1.4)
		bulb.Material = Enum.Material.Neon
		bulb.Color = Color3.fromRGB(255, 217, 138)
		bulb.Anchored = true
		bulb.Parent = model
	end
	placeOnGrass(model, data.Position.X, data.Position.Y, data.Rotation)

	-- у заглушки поднять лампочку на верхушку столба (в шаблоне она уже на месте)
	local body = model.PrimaryPart
	local bulb = model:FindFirstChild("Bulb")
	if isPlaceholder and body and bulb and bulb:IsA("BasePart") then
		bulb.Position = body.Position + Vector3.new(0, body.Size.Y / 2 + 0.7, 0)
	end
	local lightHolder = (bulb :: BasePart?) or body
	if lightHolder then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 186, 95) -- насыщеннее: холодная цветокоррекция выбеливает свет
		light.Range = 24
		light.Brightness = 1.2
		light.Parent = lightHolder
		CollectionService:AddTag(light, "FlickerLight")
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
end

-- // Детерминированный ГПСЧ для декора (одна и та же карта каждый запуск) ------
local RNG = Random.new(20260717)

-- Деревья не ставим ближе этого радиуса к старту (0,0): у выезда с дороги должно
-- быть чисто (никакого «валежника» из чёрных деревьев), сами деревья — по карте.
local TREE_START_CLEAR = 90

-- Зоны, вокруг которых декор не ставим (пивот-центр, радиус-запрет).
-- Старт/грид новой трассы (StartGate) держим чистым.
local startPos = MapLayout.Landmarks.StartGate and MapLayout.Landmarks.StartGate.Position or Vector2.new(0, 0)
local LANDMARKS = {
	{ pos = startPos, r = 48 }, -- старт/грид/спавн-точка — чисто
}
local function clearOfLandmarks(x: number, z: number): boolean
	local p = Vector2.new(x, z)
	for _, l in LANDMARKS do
		if (p - l.pos).Magnitude < l.r then
			return false
		end
	end
	return true
end

-- Случайный тёмно-коричневый тон для дерева (каждое дерево — свой оттенок).
local function randomTreeColor(): Color3
	local base = RNG:NextInteger(48, 92)
	local r = math.min(base + RNG:NextInteger(0, 20), 112)
	local g = math.floor(base * RNG:NextNumber(0.5, 0.68))
	local b = math.floor(base * RNG:NextNumber(0.3, 0.46))
	return Color3.fromRGB(r, g, b)
end
local function paintTree(model: Instance)
	local col = randomTreeColor()
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Color = col
		end
	end
end

-- // Dead trees — убраны с дороги (только на траве) + случайный размер --------
for _, data in MapLayout.DeadTrees do
	local model = getTemplateVariant("DeadTree")
	model = model and model:Clone() or makePlaceholder("DeadTree", Vector3.new(1.5, 12, 1.5), Color3.fromRGB(60, 52, 44))
	model:ScaleTo(RNG:NextNumber(0.5, 2.6))
	paintTree(model)
	local wx, wz = data.Position.X * MapLayout.Scale, data.Position.Y * MapLayout.Scale
	local g = grassPosition(wx, wz)
	if not g then
		-- позиция попала на дорогу — ищем ближайшую траву по спирали
		for radius = 8, 48, 8 do
			for a = 0, 315, 45 do
				local nx = wx + radius * math.cos(math.rad(a))
				local nz = wz + radius * math.sin(math.rad(a))
				local cand = grassPosition(nx, nz)
				if cand then
					g = cand
					break
				end
			end
			if g then
				break
			end
		end
	end
	if g and clearOfLandmarks(g.X, g.Z) and Vector2.new(g.X, g.Z).Magnitude > TREE_START_CLEAR then -- не ставим деревья у старта/лендмарков
		dropToGround(model, g, data.Rotation or 0)
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
			end
		end
		model.Parent = mapFolder
	else
		model:Destroy()
	end
end

-- // Процедурная рассадка декора по траве (плотно, случайный размер/поворот) ---
-- Чистый декор без тегов (не спавнит зомби, не мешает физике машины на дороге).
local function scatter(name: string, count: number, sMin: number, sMax: number, minStartDist: number?): number
	local placed, tries = 0, 0
	while placed < count and tries < count * 40 do
		tries += 1
		local x = RNG:NextNumber(-330, 330)
		local z = RNG:NextNumber(-330, 330)
		if not clearOfLandmarks(x, z) then
			continue
		end
		if minStartDist and Vector2.new(x, z).Magnitude < minStartDist then
			continue
		end
		local g = grassPosition(x, z)
		if not g then
			continue
		end
		local tmpl = getTemplateVariant(name)
		if not tmpl then
			break
		end
		local model = tmpl:Clone()
		model:ScaleTo(RNG:NextNumber(sMin, sMax))
		if name == "DeadTree" then
			paintTree(model) -- каждое дерево — свой случайный тёмно-коричневый
		end
		dropToGround(model, g, RNG:NextNumber(0, 360))
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = true -- непроходимо: группа Obstacles блокирует машину, но не зомби
				part.CollisionGroup = "Obstacles"
			end
		end
		model.Parent = mapFolder
		placed += 1
	end
	return placed
end

local nTomb = scatter("Tombstone", 84, 0.6, 2.3)
local nGrave = scatter("GraveMarker", 48, 0.9, 2.1)
local nTree = scatter("DeadTree", 60, 0.4, 2.8)

-- // Трава: пучки-травинки выше terrain-травы, случайные высота/цвет/наклон ----
-- Terrain-трава короткая; добавляем более высокие пучки — гуще у оснований
-- объектов и по всей площади, чтобы придать картинке динамику.
local function makeGrassTuft(): Model
	local m = Instance.new("Model")
	m.Name = "GrassTuft"
	local blades = RNG:NextInteger(2, 4)
	local baseTone = RNG:NextNumber(0, 1) -- общий оттенок пучка (зелёный..жухлый)
	local root: BasePart? = nil
	for _ = 1, blades do
		local h = RNG:NextNumber(2.0, 5.0)
		local blade = Instance.new("WedgePart")
		blade.Anchored = true
		blade.CanCollide = false
		blade.CanQuery = false
		blade.CanTouch = false
		blade.CastShadow = false
		blade.Material = Enum.Material.LeafyGrass
		local dry = RNG:NextNumber(0, 1) * baseTone
		blade.Color = Color3.fromRGB(
			math.floor(46 + dry * 78),
			math.floor(58 + RNG:NextNumber(0, 62)),
			math.floor(26 + RNG:NextNumber(0, 26))
		)
		blade.Size = Vector3.new(0.12, h, RNG:NextNumber(0.35, 0.75))
		local ang = math.rad(RNG:NextNumber(0, 360))
		local off = RNG:NextNumber(0, 0.7)
		blade.CFrame = CFrame.new(math.cos(ang) * off, h / 2, math.sin(ang) * off)
			* CFrame.Angles(0, ang, 0)
			* CFrame.Angles(math.rad(RNG:NextNumber(-8, 8)), 0, math.rad(RNG:NextNumber(6, 28)))
		blade.Parent = m
		root = root or blade
	end
	m.PrimaryPart = root
	return m
end

local grassCount = 0
local function placeGrassTuft(ground: Vector3, scale: number)
	local t = makeGrassTuft()
	t:ScaleTo(scale)
	dropToGround(t, ground, RNG:NextNumber(0, 360))
	t.Parent = mapFolder
	grassCount += 1
end

-- гуще и выше у оснований уже расставленного декора
local decorSnapshot = mapFolder:GetChildren()
for _, m in decorSnapshot do
	local ok, piv = pcall(function()
		return m:GetPivot().Position
	end)
	if ok then
		for _ = 1, RNG:NextInteger(1, 2) do -- меньше пучков = легче рендер
			local a = math.rad(RNG:NextNumber(0, 360))
			local r = RNG:NextNumber(0.6, 3.4)
			local g = grassPosition(piv.X + math.cos(a) * r, piv.Z + math.sin(a) * r)
			if g then
				placeGrassTuft(g, RNG:NextNumber(1.2, 2.3))
			end
		end
	end
end

-- кольцо травы у старта/ворот (координаты из MapLayout)
local buildings = { startPos }
for _, bp in buildings do
	for _ = 1, 10 do
		local a = math.rad(RNG:NextNumber(0, 360))
		local r = RNG:NextNumber(8, 17)
		local g = grassPosition(bp.X * MapLayout.Scale + math.cos(a) * r, bp.Y * MapLayout.Scale + math.sin(a) * r)
		if g then
			placeGrassTuft(g, RNG:NextNumber(1.3, 2.4))
		end
	end
end

-- по всей площади (случайно)
local fieldTarget, ftries, fieldPlaced = 180, 0, 0
while fieldPlaced < fieldTarget and ftries < fieldTarget * 12 do
	ftries += 1
	local g = grassPosition(RNG:NextNumber(-330, 330), RNG:NextNumber(-330, 330))
	if g then
		placeGrassTuft(g, RNG:NextNumber(0.9, 1.8))
		fieldPlaced += 1
	end
end

print(
	`[MapBuilder] Расставлено: {#MapLayout.Hazards} hazard'ов, {#MapLayout.Graves} могил, {#MapLayout.Lamps} фонарей, {#MapLayout.DeadTrees} деревьев (по карте). `
		.. `Декор-россыпь: {nTomb} надгробий, {nGrave} могил, {nTree} деревьев, {grassCount} пучков травы.`
)
