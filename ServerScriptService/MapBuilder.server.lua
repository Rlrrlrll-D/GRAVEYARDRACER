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
local MapGen = require(script.Parent:WaitForChild("MapGen"))

-- ТРАВА ТЕРРЕЙНА УБРАНА (2026-07-31, по требованию юзера «убирай траву с поля,
-- если это облегчит кадр»). Она была самой тяжёлой геометрией кадра — замер
-- 2026-07-30 дал `Grass 438 852 tris / 100 draws` против `Opaque 5 367 / 5`.
-- Рывков она не давала (цена ровная), но платить 438 тысяч треугольников за фон
-- на встроенной Intel Iris Xe незачем.
--
-- Выключателя у неё нет: `Terrain.Decoration` в этой версии Roblox — «not a valid
-- member» и из песочницы MCP, и из серверного скрипта (перепроверено 31.07).
-- Декорацию движок вешает на материал, причём на ДВА: замер на плите 400×400 дал
-- одинаковые 23 664 tris у `Grass` и у `LeafyGrass` и ровно ноль у `Mud`, `Ground`,
-- `Slate`. Поэтому поле теперь `MapGen.FieldMaterial` = Mud, а чтобы оно не стало
-- чёрной грязью — тонируется в жухлый оливково-серый: мёртвая трава кладбища без
-- единого полигона травинок.
local FIELD_COLOR = Color3.fromRGB(78, 82, 58)
workspace.Terrain:SetMaterialColor(MapGen.FieldMaterial, FIELD_COLOR)

if GameConfig.Map.GenerateRoad and MapLayout.TrackPolyline and #MapLayout.TrackPolyline > 0 then
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

-- Позиция ПОЛЯ (не дороги) под (x,z), либо nil если там дорога/ничего.
-- Поле и дорога различаются материалом террейна — оба берём из MapGen, чтобы
-- источник правды был один: перекрасишь поле там, и весь декор поедет следом.
local function grassPosition(x: number, z: number): Vector3?
	local origin = Vector3.new(x, RAYCAST_HEIGHT, z)
	local r = workspace:Raycast(origin, Vector3.new(0, -RAYCAST_HEIGHT * 2, 0), raycastParams)
	if r and r.Instance == workspace.Terrain and r.Material == MapGen.FieldMaterial then
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
-- Спавн-точки зомби. Бугров-могил на карте больше нет (юзер: «могилы бугры убери
-- вообще»), поэтому место, откуда лезет зомби, отмечает надгробие — тег `Grave`
-- остаётся на нём, логика спавна не меняется.
for _, data in MapLayout.Graves do
	local model = getTemplate("Tombstone")
	model = model and model:Clone() or makePlaceholder("Tombstone", Vector3.new(3, 4, 1.2), Color3.fromRGB(120, 120, 130))
	placeOnGrass(model, data.Position.X, data.Position.Y, data.Rotation)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			-- Группа как у ВСЕГО остального декора. Эти 14 камней её не получали и
			-- оставались в Default, а Zombies↔Default = true — то есть надгробие
			-- работало для зомби полом: замер поймал живого, стоящего на +4.61 над
			-- землёй. В Obstacles зомби проходит сквозь камень, машину камень держит.
			part.CollisionGroup = "Obstacles"
		end
	end
	CollectionService:AddTag(model, "Grave")
end

-- // Lamps (мерцающие фонари) -------------------------------------------------
-- ВЫКЛЮЧЕНО (2026-07-30): восемь фонарей из `MapLayout.Lamps` стоят по данным карты
-- и прежнего роста (9.5 studs), а вдоль трассы теперь идёт процедурный ряд — высокий
-- (×1.8) и в 4 studs от кромки, см. блок кластеров. Рядом со столбами старые
-- смотрелись пеньками, поэтому оставляем один источник правды. Данные не удаляю:
-- вернуть — снять `false and`.
for _, data in (false and MapLayout.Lamps or {}) :: { any } do
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

-- // ПОДОШВА ШАБЛОНА: где модель на самом деле касается земли ------------------
-- Жалоба юзера: «деревья висят над землёй». Замер 2026-07-31 объяснил, почему:
-- `dropToGround` сажает на грунт нижний угол ГАБАРИТНОЙ КОРОБКИ, а шаблоны деревьев
-- НАКЛОНЕНЫ (DeadTree на 15°, DeadTree_B на 18° — наклон вшит в сам шаблон). У
-- наклонённой коробки нижний угол — пустое место: он уходил в грунт, а ствол при
-- этом висел на 2.2 studs выше. Плотный скан подошвы одного дерева: 0 из 169
-- колонн касались земли.
--
-- Поэтому подошву меряем ЛУЧАМИ по самому мешу, а не по коробке. Меряем ОДИН РАЗ
-- на шаблон (масштаб 1, без поворота) и переносим на клоны: масштаб множит смещение,
-- рыскание вокруг Y его поворачивает, а вертикаль от рыскания не зависит.
-- Заодно скан даёт, ГДЕ у модели ствол: самая низкая колонна — это и есть точка
-- опоры, и сажать модель надо именно ею, а не пивотом (у мешей пивот уезжает от
-- ствола) и не центром деталей (у дерева это середина кроны).
local PROBE_ORIGIN = Vector3.new(0, 5000, 0) -- промерочная площадка высоко над картой
local PROBE_GRID = 6 -- 13x13 колонн на подошву: хватает, чтобы поймать ствол

export type Footprint = {
	base: Vector3, -- точка опоры относительно пивота (масштаб 1, без поворота)
	radius: number, -- горизонтальный радиус ВСЕЙ модели, studs (масштаб 1)
	baseRadius: number, -- радиус пятна КАСАНИЯ земли: ствол, а не крона
}
-- Насколько выше самой низкой точки колонна ещё считается «подошвой». Кроне дерева
-- до земли далеко, поэтому в полосу попадает только комель — а у надгробия, наоборот,
-- вся плита. Ровно это и нужно: у дерева занято место под стволом (крона пусть
-- нависает над камнями, это красиво), у надгробия — весь его участок.
local BASE_BAND = 2.0
local footprintCache: { [Instance]: Footprint } = {}

-- Нижний угол ориентированной коробки детали в мировых координатах.
local function partBottom(p: BasePart): number
	local cf, half = p.CFrame, p.Size / 2
	return cf.Position.Y
		- (
			math.abs(cf.RightVector.Y) * half.X
			+ math.abs(cf.UpVector.Y) * half.Y
			+ math.abs(cf.LookVector.Y) * half.Z
		)
end

local function measureFootprint(template: Model): Footprint
	local cached = footprintCache[template]
	if cached then
		return cached
	end

	local probe = template:Clone()
	probe:PivotTo(CFrame.new(PROBE_ORIGIN)) -- строго без поворота: меряем «как нарисовано»
	probe.Parent = workspace

	-- габарит: радиус для расстановки + рамка, по которой пускаем колонны
	local minX, maxX, minZ, maxZ, boxBottom = math.huge, -math.huge, math.huge, -math.huge, math.huge
	for _, p in probe:GetDescendants() do
		if p:IsA("BasePart") then
			local h = math.max(p.Size.X, p.Size.Z) / 2
			minX = math.min(minX, p.Position.X - h)
			maxX = math.max(maxX, p.Position.X + h)
			minZ = math.min(minZ, p.Position.Z - h)
			maxZ = math.max(maxZ, p.Position.Z + h)
			boxBottom = math.min(boxBottom, partBottom(p))
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { probe }
	-- Луч уважает группы столкновений, а декор живёт в Obstacles: без явной группы
	-- промер бы молча ничего не нашёл. Меряем от лица самого декора.
	params.CollisionGroup = "Obstacles"

	local best, bestX, bestZ = math.huge, PROBE_ORIGIN.X, PROBE_ORIGIN.Z
	local hits: { { x: number, z: number, y: number } } = {}
	local from = boxBottom - 10
	local height = (maxX - minX) + (maxZ - minZ) + 400 -- заведомо выше модели
	local stepX = (maxX - minX) / (PROBE_GRID * 2)
	local stepZ = (maxZ - minZ) / (PROBE_GRID * 2)
	for ix = 0, PROBE_GRID * 2 do
		for iz = 0, PROBE_GRID * 2 do
			local wx = minX + stepX * ix
			local wz = minZ + stepZ * iz
			local hit = workspace:Raycast(Vector3.new(wx, from, wz), Vector3.new(0, height, 0), params)
			if hit then
				table.insert(hits, { x = wx, z = wz, y = hit.Position.Y })
				if hit.Position.Y < best then
					best, bestX, bestZ = hit.Position.Y, wx, wz
				end
			end
		end
	end

	if best == math.huge then
		-- Меш не нащупался (например, CollisionFidelity выродился в ничто) — честно
		-- откатываемся на коробку: хуже, чем было, от этого не станет.
		best, bestX, bestZ = boxBottom, PROBE_ORIGIN.X, PROBE_ORIGIN.Z
		warn(`[MapBuilder] Подошва {template.Name} не нащупалась лучами — сажаю по коробке.`)
	end

	-- Опорная точка по горизонтали — ЦЕНТР пятна касания, а не самая низкая колонна.
	-- У надгробия подошва плоская: десятки колонн дают одну и ту же высоту, и «самая
	-- низкая» из них выпадает случайно то с одного края плиты, то с другого — камни
	-- одного ряда расходились бы по X на ширину подошвы, а решётка читалась бы криво
	-- (замер: 657 камней из 778 не попадали в узел). У дерева полоса касания — это
	-- комель, и его центр даже точнее прежней «самой низкой точки ствола».
	-- ВЫСОТУ при этом оставляем минимальной: сажаем по нижней точке модели, иначе
	-- выпуклая подошва повисла бы над грунтом.
	local sumX, sumZ, nBase = 0, 0, 0
	for _, h in hits do
		if h.y <= best + BASE_BAND then
			sumX += h.x
			sumZ += h.z
			nBase += 1
		end
	end
	if nBase > 0 then
		bestX, bestZ = sumX / nBase, sumZ / nBase
	end

	-- Радиус пятна касания: самая дальняя колонна, которая всё ещё «на подошве».
	-- Полшага сетки добавляем на грубость промера, чтобы не занизить.
	local baseRadius = 0
	for _, h in hits do
		if h.y <= best + BASE_BAND then
			local dx, dz = h.x - bestX, h.z - bestZ
			baseRadius = math.max(baseRadius, math.sqrt(dx * dx + dz * dz))
		end
	end
	baseRadius += math.max(stepX, stepZ) / 2

	local fp: Footprint = {
		base = Vector3.new(bestX, best, bestZ) - PROBE_ORIGIN,
		radius = math.max(maxX - minX, maxZ - minZ) / 2,
		baseRadius = baseRadius,
	}
	probe:Destroy()
	footprintCache[template] = fp
	return fp
end

-- Посадить клон так, чтобы ЕГО ТОЧКА ОПОРЫ попала в (x, groundY - sink, z).
-- Возвращает фактический горизонтальный радиус (для проверки занятости места).
local function plantOnGround(
	model: Model,
	template: Model,
	x: number,
	z: number,
	groundY: number,
	yawDeg: number,
	scale: number,
	sink: number
): number
	local fp = measureFootprint(template)
	local yaw = CFrame.Angles(0, math.rad(yawDeg), 0)
	local pivot = model:GetPivot()
	-- сначала разворот вокруг собственной вертикали, наклон шаблона сохраняем
	model:PivotTo(CFrame.new(pivot.Position) * yaw * pivot.Rotation)
	-- затем сдвиг: опора шаблона, повёрнутая и промасштабированная, должна лечь в точку
	local offset = yaw * (fp.base * scale)
	local cur = model:GetPivot()
	model:PivotTo(
		cur
			+ Vector3.new(
				x - (cur.Position.X + offset.X),
				(groundY - sink) - (cur.Position.Y + offset.Y),
				z - (cur.Position.Z + offset.Z)
			)
	)
	return fp.radius * scale
end

-- // ЗАНЯТОСТЬ МЕСТА: чтобы декор не пророс друг сквозь друга ------------------
-- Жалоба юзера: «некоторые деревья пробивают надгробья». Замер: 190 пересечений
-- ствол-камень из 281 дерева. Причина структурная — деревья и кладбище ставились
-- двумя независимыми проходами, ни один не знал о другом. Теперь оба пишут занятые
-- пятна в общую сетку и спрашивают её перед посадкой.
local OCC_CELL = 16 -- studs: ячейка пространственного хеша
local occupancy: { [string]: { { x: number, z: number, r: number } } } = {}

local function occKey(x: number, z: number): string
	return `{math.floor(x / OCC_CELL)}:{math.floor(z / OCC_CELL)}`
end

local function spotFree(x: number, z: number, r: number): boolean
	local cells = math.ceil((r + OCC_CELL) / OCC_CELL)
	for cx = -cells, cells do
		for cz = -cells, cells do
			local bucket = occupancy[occKey(x + cx * OCC_CELL, z + cz * OCC_CELL)]
			if bucket then
				for _, o in bucket do
					local dx, dz = x - o.x, z - o.z
					local need = r + o.r
					if dx * dx + dz * dz < need * need then
						return false
					end
				end
			end
		end
	end
	return true
end

local function occupy(x: number, z: number, r: number)
	local key = occKey(x, z)
	local bucket = occupancy[key]
	if not bucket then
		bucket = {}
		occupancy[key] = bucket
	end
	table.insert(bucket, { x = x, z = z, r = r })
end

-- // Детерминированный ГПСЧ для декора (одна и та же карта каждый запуск) ------
local RNG = Random.new(20260717)

-- Деревья не ставим ближе этого радиуса к старту (0,0): у выезда с дороги должно
-- быть чисто (никакого «валежника» из чёрных деревьев), сами деревья — по карте.
local TREE_START_CLEAR = 90

-- На столько топим комель в грунт: у самой земли шов между стволом и грунтом
-- иначе читается как «дерево висит». Объявлено здесь, а не у остальных TREE_*
-- ниже, потому что первая же расстановка деревьев (по MapLayout) уже его просит.
local TREE_SINK = 0.35

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
	local tmpl = getTemplateVariant("DeadTree")
	local model = tmpl and tmpl:Clone()
		or makePlaceholder("DeadTree", Vector3.new(1.5, 12, 1.5), Color3.fromRGB(60, 52, 44))
	local scale = RNG:NextNumber(0.5, 2.6)
	model:ScaleTo(scale)
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
		if tmpl then
			-- по промеренной подошве: у наклонённого шаблона низ коробки — пустой угол
			local r = measureFootprint(tmpl).baseRadius * scale
			plantOnGround(model, tmpl, g.X, g.Z, g.Y, data.Rotation or 0, scale, TREE_SINK)
			occupy(g.X, g.Z, r)
		else
			dropToGround(model, g, data.Rotation or 0) -- заглушка-Part: коробка и есть меш
		end
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

-- // Расстояние до осевой трассы -----------------------------------------------
-- Нужно, чтобы деревья не лезли к полотну: рейкаст «под ногами трава» этого не
-- ловит — в 23 studs от осевой трава есть, а крона уже висит над дорогой.
local TREE_ROAD_CLEAR = 34 -- ближе этого к осевой деревьев нет: полотно 22.4 + запас
local TRACK_PTS: { Vector2 } = {}
do
	local poly = MapLayout.TrackPolyline
	local scale = MapLayout.Scale or 1
	if type(poly) == "table" then
		for _, p in poly do
			table.insert(TRACK_PTS, Vector2.new(p.X * scale, p.Y * scale))
		end
	end
end
local function trackDistance(x: number, z: number): number
	local best = math.huge
	local n = #TRACK_PTS
	if n == 0 then
		return best
	end
	local p = Vector2.new(x, z)
	for i = 1, n do
		local a, b = TRACK_PTS[i], TRACK_PTS[i % n + 1]
		local ab = b - a
		local len2 = ab:Dot(ab)
		local t = len2 > 0 and math.clamp((p - a):Dot(ab) / len2, 0, 1) or 0
		local d = (p - (a + ab * t)).Magnitude
		if d < best then
			best = d
		end
	end
	return best
end

-- Посадку «по стволу, а не по пивоту» теперь делает `plantOnGround` (см. промер
-- подошвы выше): прежний `centerOnTrunk` целился в ЦЕНТР МАСС деталей, а у дерева
-- это середина кроны, а не комель. Промер лучами находит точку опоры честно.

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
		-- Деревья держим ПОДАЛЬШЕ от полотна: 8 деревьев прошлой сборки стояли в
		-- 20-29 studs от осевой при полуширине дороги 22.4 — то есть кроной над
		-- трассой, и на широком вылете машина влетала в ствол.
		if name == "DeadTree" and trackDistance(x, z) < TREE_ROAD_CLEAR then
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
		-- Место проверяем ДО клонирования: радиус пятна касания известен из промера
		-- шаблона, клонировать ради отказа незачем.
		local scale = RNG:NextNumber(sMin, sMax)
		local footRadius = measureFootprint(tmpl).baseRadius * scale
		if not spotFree(x, z, footRadius) then
			continue
		end
		local model = tmpl:Clone()
		model:ScaleTo(scale)
		if name == "DeadTree" then
			paintTree(model) -- каждое дерево — свой случайный тёмно-коричневый
		end
		-- Топим на палец: у самой земли шов между стволом и грунтом читается как
		-- «дерево висит». Саму посадку делает plantOnGround — по промеренной подошве.
		plantOnGround(model, tmpl, x, z, g.Y, RNG:NextNumber(0, 360), scale, name == "DeadTree" and TREE_SINK or 0)
		occupy(x, z, footRadius)
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

-- Надгробия больше НЕ разбрасываются случайно: кладбище выстроено рядами, см. блок
-- «РЕГУЛЯРНОЕ КЛАДБИЩЕ» ниже. Могилы-бугры (`GraveMarker`) убраны с карты совсем.
-- Деревьев — кратно больше и с широким разбросом размеров: они как раз должны
-- стоять природно, вразнобой, в отличие от рядов надгробий.
local nTree = scatter("DeadTree", 230, 0.35, 3.6)

-- // КЛАСТЕРЫ ВДОЛЬ ТРАССЫ (веха 8, фаза 3) -----------------------------------
-- Ровная россыпь по площади читается как шум: с полотна не видно, где поворот, и
-- кладбище одинаково во все стороны. Поэтому ПОВЕРХ россыпи сажаем группы,
-- привязанные к геометрии трассы:
--   * на изгибах — могилы и кресты СНАРУЖИ поворота (именно туда смотрит водитель,
--     входя в вираж), на самых крутых — ещё и фонарь;
--   * на прямых — аллеи мёртвых деревьев по обе стороны полотна.
-- Замер 2026-07-30 такую добавку разрешает: весь статичный декор в кадре стоил
-- `Opaque 31 547 tris / 26 draws` против `Grass 188 682 / 44` у одной только травы,
-- то есть надгробия почти ничего не стоят. Тяжёлой тогда была земля — с 31.07
-- трава с поля снята совсем (см. шапку), так что запас по кадру стал только больше.
-- // РЕГУЛЯРНОЕ КЛАДБИЩЕ: ряды надгробий по всей площади, кроме трассы ----------
-- Требование юзера: «расположение не хаотичное, но строго геометрически параллельно,
-- размеры больше и разные, наполни карту максимально». Поэтому надгробия больше не
-- разбрасываются рандомом — они стоят СЕТКОЙ: шаг по X — место в ряду, шаг по Z —
-- сам ряд, разворот у ВСЕХ одинаковый (никакого случайного поворота, иначе поле
-- сразу читается как мусор). Разнообразие даёт не поворот, а типоразмер: семь
-- шаблонов надгробий (два своих + пять из стора) и широкий разброс масштаба.
-- Каждый N-й ряд и каждый M-й столбец пропускаем — это дорожки между участками,
-- без них поле выглядит как склад, а не кладбище.
local CEM_HALF = 318 -- до ограды (±335) остаётся полоса, чтобы камни в неё не влезали
local CEM_ROAD_CLEAR = 10 -- не ближе этого к кромке полотна (проверяется рейкастом)
local CEM_YAW = 0 -- единый разворот всех камней

-- Веса типов: свои меши по одной детали — основа поля; магазинные крупные
-- памятники редкими акцентами, они дороже по деталям и заметно больше.
-- Восемь форм, и ни одна не доминирует: юзер сказал «надгробья сплошь одинаковые» —
-- прежние веса отдавали больше половины поля двум своим мешам. Добавлены кресты
-- (кельтский и на плинте) — именно силуэт креста ломает монотонность ряда.
-- `Tombstone_D` выброшен совсем: на нём были авторские подписи из стора
-- (`SurfaceGui`/`SIGN` — «RIP Dienyans main account»), а детали лежали повёрнутыми
-- на 90°, отчего памятник выглядел опрокинутым.
--
-- ВЕСА ПЕРЕСЧИТАНЫ 2026-07-31 ПО ЗАМЕРУ ЦЕНЫ КАЖДОГО ТИПА. Когда камней стало 1038
-- вместо 582, кадр с дороги вырос до 298 480 треугольников. Разбор по типам (прячем
-- группу, смотрим Opaque с одной точки) показал, что дело НЕ в количестве:
--     Tombstone_H  -> 133 896 tris     Tombstone_J -> 2 964
--     Tombstone_B  -> 107 084 tris     Tombstone_G -> 2 634
--     Tombstone    ->   7 170 tris     Tombstone_C -> 1 954
--     Tombstone_E  ->   1 064 tris     Tombstone_F ->   994
-- Два меша (оба мои, из Blender, с бевелем) стоят по ~730-770 треугольников штука
-- против 10-38 у остальных семи — вдвоём они съедали 81% кадра. Поэтому они больше не
-- массовка, а АКЦЕНТ: их доля срезана с 29% до 10%. Крестов при этом не убавилось —
-- квота ушла к `Tombstone_J` (крест на плинте, 23 треугольника), и силуэт креста в
-- рядах остался ровно таким же частым.
local CEM_KINDS = {
	{ name = "Tombstone", weight = 22, sMin = 1.0, sMax = 2.4 },
	{ name = "Tombstone_J", weight = 20, sMin = 1.0, sMax = 1.9 }, -- крест на плинте, дешёвый
	{ name = "Tombstone_C", weight = 16, sMin = 0.9, sMax = 1.8 },
	{ name = "Tombstone_G", weight = 14, sMin = 1.2, sMax = 2.6 },
	{ name = "Tombstone_F", weight = 12, sMin = 0.9, sMax = 1.6 },
	{ name = "Tombstone_E", weight = 6, sMin = 0.6, sMax = 1.0 }, -- обелиск, высокий
	{ name = "Tombstone_H", weight = 6, sMin = 0.9, sMax = 1.8 }, -- кельтский крест: дорогой, редкий
	{ name = "Tombstone_B", weight = 4, sMin = 1.0, sMax = 2.2 }, -- тоже дорогой, самый редкий
}

-- Камень одного тона на всё поле тоже читается как копипаста, поэтому у каждого
-- памятника свой оттенок серого, а один из шести — замшелый, позеленевший от сырости.
local CEM_STONE = Color3.fromRGB(163, 162, 165)
local function stoneTone(): Color3
	if RNG:NextNumber() < 0.17 then
		local g = RNG:NextInteger(96, 128)
		return Color3.fromRGB(g - 18, g, g - 26) -- мох
	end
	local t = RNG:NextInteger(-26, 14)
	return Color3.fromRGB(
		math.clamp(163 + t, 0, 255),
		math.clamp(162 + t, 0, 255),
		math.clamp(165 + math.floor(t * 0.85), 0, 255)
	)
end
local CEM_WEIGHT_TOTAL = 0
for _, k in CEM_KINDS do
	CEM_WEIGHT_TOTAL += k.weight
end
local function pickKind()
	local r = RNG:NextNumber(0, CEM_WEIGHT_TOTAL)
	for _, k in CEM_KINDS do
		r -= k.weight
		if r <= 0 then
			return k
		end
	end
	return CEM_KINDS[1]
end

-- // УЧАСТОК ПОД ЗАХОРОНЕНИЕ (2026-07-31) -------------------------------------
-- Требование юзера: «надгробья должны располагаться не как попало, а с учётом
-- размера захоронения». Прежняя сетка была ЖЁСТКОЙ (шаг 10×13 studs) при разбросе
-- масштабов от 0.6 до 2.6 — то есть шаг не имел никакого отношения к размеру камня:
-- крупные памятники налезали друг на друга, мелкие оставляли дыры, и ряд читался
-- как случайный, хотя строился по линейке.
--
-- ПЕРЕДЕЛАНО 2026-07-31 (юзер: «расставь уже кресты и надгробья равномерно рядами
-- и увеличь их количество»). Предыдущий заход давал каждому камню участок ПО ЕГО
-- размеру, и шаг вдоль ряда получался переменным: ряды оставались прямыми, но
-- столбцов не было вовсе — поле читалось как случайное, хотя строилось по линейке.
-- Замер это подтвердил: 582 камня на 75 рядов с разным шагом между рядами.
--
-- Теперь всё поле — ОДНА РЕШЁТКА с постоянным шагом: столбец = PLOT_STEP, ряд =
-- PLOT_ROW_STEP, и каждый камень стоит ровно в её узле. Крупный памятник не двигает
-- решётку, а ЗАНИМАЕТ НЕСКОЛЬКО ЯЧЕЕК подряд (как семейный участок), поэтому ряды и
-- столбцы читаются насквозь. Дорожки — это пропущенные линии решётки, а не вставки
-- переменной ширины: узлы соседних кварталов остаются на одной прямой.
--
-- Разброс масштаба сохранён, но подрезается глубиной ряда: камень, который не влезает
-- между рядами, ужимается до неё — иначе задний ряд наползал бы на передний.
local PLOT_STEP = 11 -- шаг решётки вдоль ряда (столбцы), studs
local PLOT_ROW_STEP = 14 -- шаг решётки между рядами, studs
local PLOT_GAP = 2.2 -- минимальный проход между соседними захоронениями, studs
local PLOT_AISLE_ROWS = 8 -- каждый 8-й ряд решётки пуст — поперечная дорожка
local PLOT_AISLE_EVERY = 13 -- каждый 13-й столбец решётки пуст — продольная дорожка

local nCemetery = 0
-- Где встали камни: по этим точкам потом пускаем траву у оснований (см. ниже).
local cemeterySpots: { { x: number, z: number, y: number, r: number } } = {}
do
	-- Дорога и поле — разные материалы террейна (см. MapGen), поэтому «занято ли
	-- место дорогой» решает тот же рейкаст, что и у остальной расстановки:
	-- nil = полотно или дыра.
	local roadProbe = {
		Vector2.new(CEM_ROAD_CLEAR, 0),
		Vector2.new(-CEM_ROAD_CLEAR, 0),
		Vector2.new(0, CEM_ROAD_CLEAR),
		Vector2.new(0, -CEM_ROAD_CLEAR),
	}
	-- Глубже этого камень не растёт: иначе соседний РЯД окажется у него внутри.
	local PLOT_MAX_RADIUS = (PLOT_ROW_STEP - PLOT_GAP) / 2
	local rowIndex = 0
	local z = -CEM_HALF
	while z <= CEM_HALF do
		rowIndex += 1
		if rowIndex % PLOT_AISLE_ROWS ~= 0 then -- иначе ряд пропущен целиком = дорожка
			local col = 0
			local nextFreeCol = 1 -- докуда решётку занял предыдущий крупный памятник
			local x = -CEM_HALF
			while x <= CEM_HALF do
				col += 1
				if col >= nextFreeCol and col % PLOT_AISLE_EVERY ~= 0 then
					local kind = pickKind()
					-- ТОЧНЫЙ шаблон, не `getTemplateVariant`: тот сам случайно выбирает среди
					-- всех `Tombstone_*` и затирает веса — в первой сборке из-за этого «Tombstone»
					-- с весом 18% получил 3% поля, а раздача типов шла почти поровну.
					local tmpl = getTemplate(kind.name)
					if tmpl then
						local baseR = measureFootprint(tmpl).baseRadius
						local scale = RNG:NextNumber(kind.sMin, kind.sMax)
						if baseR * scale > PLOT_MAX_RADIUS then
							scale = PLOT_MAX_RADIUS / baseR -- подрезаем по глубине ряда
						end
						local footRadius = baseR * scale

						local ok = clearOfLandmarks(x, z)
						local g = ok and grassPosition(x, z) or nil
						if g then
							-- у самой кромки не ставим: рейкаст в четырёх точках вокруг места
							for _, d in roadProbe do
								if not grassPosition(x + d.X, z + d.Y) then
									g = nil
									break
								end
							end
						end
						-- и место не должно быть уже занято деревом или фонарём
						if g and spotFree(x, z, footRadius) then
							local model = tmpl:Clone()
							model:ScaleTo(scale)
							plantOnGround(model, tmpl, x, z, g.Y, CEM_YAW, scale, 0) -- разворот ОДИН на всех: ряды параллельны
							occupy(x, z, footRadius)
							local tone = stoneTone()
							for _, part in model:GetDescendants() do
								if part:IsA("BasePart") then
									part.Anchored = true
									part.CanCollide = true
									part.CollisionGroup = "Obstacles"
									part.CastShadow = false
									part.Color = tone
								end
							end
							model.Parent = mapFolder
							nCemetery += 1
							table.insert(cemeterySpots, { x = x, z = z, y = g.Y, r = footRadius })
							-- широкий памятник забирает соседние ячейки решётки целиком
							nextFreeCol = col + math.max(1, math.ceil((2 * footRadius + PLOT_GAP) / PLOT_STEP))
						end
					end
				end
				x += PLOT_STEP
			end
		end
		z += PLOT_ROW_STEP
	end
end

local nAlleyTrees, nClusterLamps = 0, 0
do
	local poly = MapLayout.TrackPolyline
	local scale = MapLayout.Scale or 1
	if type(poly) == "table" and #poly >= 8 then
		local ROAD_HALF = GameConfig.Map.RoadWidth / 2
		local STEP = 12 -- шаг обхода осевой, studs
		local ALLEY_GAP = 26 -- шаг деревьев в аллее
		local LAMP_GAP = 120 -- шаг фонарей вдоль дороги, studs
		-- От ОСЕВОЙ до столба = ROAD_HALF + это. Было 4, и все 26 фонарей молча сносила
		-- чистка дороги (она бьёт всё ближе ROAD_HALF + 6) — на карте не осталось ни
		-- одного. Теперь фонарь вынесен за радиус чистки и вдобавок помечен `Roadside`,
		-- а его подошва проверяется кольцом: полотно шире номинала (замер 31.07: кромка
		-- до 24.0 при ROAD_HALF = 22.4), и по одному лучу в центр это не поймать.
		local LAMP_OFFSET = 6
		local LAMP_SCALE = 1.8 -- шаблон 9.5 studs -> ~17: столб, а не пенёк
		local BEND_DEG = 3.2 -- поворот на шаг круче этого = изгиб
		local STRAIGHT_DEG = 1.1 -- положе этого = прямая
		local START_CLEAR = 80 -- у старта чисто: там колонна и выезд

		local n = #poly
		local function pt(i: number): Vector2
			local p = poly[((i - 1) % n) + 1]
			return Vector2.new(p.X * scale, p.Y * scale)
		end

		-- Плотная выборка по длине: у полилинии сегменты разной длины, и «через N
		-- точек» дало бы кластеры гуще на мелких сегментах.
		local cum: { number } = { 0 }
		local total = 0
		for i = 1, n do
			total += (pt(i + 1) - pt(i)).Magnitude
			cum[i + 1] = total
		end
		local function along(s: number): (Vector2, Vector2)
			s = s % total
			local i = 1
			while i < n and cum[i + 1] <= s do
				i += 1
			end
			local a, b = pt(i), pt(i + 1)
			local seg = cum[i + 1] - cum[i]
			local f = seg > 1e-6 and (s - cum[i]) / seg or 0
			local dir = b - a
			dir = dir.Magnitude > 1e-6 and dir.Unit or Vector2.new(0, 1)
			return a + (b - a) * f, dir
		end

		-- Поставить одну модель на траву в точке (x,z); false, если там дорога/занято.
		local function put(name: string, x: number, z: number, sMin: number, sMax: number): boolean
			if not clearOfLandmarks(x, z) then
				return false
			end
			-- аллея идёт вдоль полотна, поэтому здесь тоже держим дистанцию: точка
			-- задана от осевой, но пивот меша смещён, и без проверки ствол сползает к дороге
			if name == "DeadTree" and trackDistance(x, z) < TREE_ROAD_CLEAR then
				return false
			end
			local g = grassPosition(x, z)
			if not g then
				return false -- дорога, яма или край карты
			end
			local tmpl = getTemplateVariant(name)
			if not tmpl then
				return false
			end
			local scale = RNG:NextNumber(sMin, sMax)
			local footRadius = measureFootprint(tmpl).baseRadius * scale
			if not spotFree(x, z, footRadius) then
				return false -- на этом месте уже что-то стоит
			end
			local model = tmpl:Clone()
			model:ScaleTo(scale)
			if name == "DeadTree" then
				paintTree(model)
			end
			plantOnGround(model, tmpl, x, z, g.Y, RNG:NextNumber(0, 360), scale, name == "DeadTree" and TREE_SINK or 0)
			occupy(x, z, footRadius)
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") then
					part.Anchored = true
					part.CanCollide = true -- как у россыпи: группа Obstacles держит машину, но не зомби
					part.CollisionGroup = "Obstacles"
				end
			end
			model.Parent = mapFolder
			return true
		end

		-- Фонарь ставим У САМОЙ ДОРОГИ и высоким: прежние стояли в 9 studs от кромки и
		-- ростом 9.5 studs — юзер справедливо назвал их низкими и стоящими не у дороги.
		local lampIndex = 0
		local function putLamp(at: Vector2, outward: Vector2): boolean
			local spot = at + outward * (ROAD_HALF + LAMP_OFFSET)
			local lamp = getTemplateVariant("Lamp")
			local g = grassPosition(spot.X, spot.Y)
			if not lamp or not g then
				return false
			end
			-- Кольцо по подошве: столб не должен зацепить полотно даже краем.
			local footR = measureFootprint(lamp).baseRadius * LAMP_SCALE
			for a = 0, 315, 45 do
				local rad = math.rad(a)
				if not grassPosition(spot.X + math.cos(rad) * footR, spot.Y + math.sin(rad) * footR) then
					return false
				end
			end
			local model = lamp:Clone()
			-- Фонарь стоит у обочины НАМЕРЕННО и промерен по подошве — чистка дороги
			-- (она идёт последней и сносит всё близкое к осевой) обязана его пропустить.
			model:SetAttribute("Roadside", true)
			model:ScaleTo(LAMP_SCALE) -- ~17 studs: фонарь должен нависать над полотном
			plantOnGround(model, lamp, spot.X, spot.Y, g.Y, RNG:NextNumber(0, 360), LAMP_SCALE, 0)
			occupy(spot.X, spot.Y, measureFootprint(lamp).baseRadius * LAMP_SCALE)
			local bulb = model:FindFirstChild("Bulb")
			local holder = (bulb and bulb:IsA("BasePart")) and bulb or model.PrimaryPart
			if holder then
				local light = Instance.new("PointLight")
				light.Color = Color3.fromRGB(255, 186, 95)
				light.Range = 34 -- выше фонарь — шире пятно
				light.Brightness = 1.4
				light.Parent = holder
				-- Мерцает только каждый третий: `FlickerLight` крутит яркость НА СЕРВЕРЕ,
				-- и каждая смена реплицируется всем клиентам, а под unified-светом ещё и
				-- пересчитывается. Двадцать шесть мигающих фонарей — постоянный поток
				-- обновлений на ровном месте; для атмосферы хватает трети.
				lampIndex += 1
				if lampIndex % 3 == 0 then
					CollectionService:AddTag(light, "FlickerLight")
				end
			end
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") then
					part.Anchored = true
				end
			end
			model.Parent = mapFolder
			return true
		end

		local sinceLamp, sinceTree = 0, 0
		local prevDir: Vector2? = nil
		local lampSide = 1
		local s = 0
		while s < total do
			local p, dir = along(s)
			local turn = 0
			if prevDir then
				-- знак поворота: положительный — влево, отрицательный — вправо
				local cross = prevDir.X * dir.Y - prevDir.Y * dir.X
				local dot = math.clamp(prevDir:Dot(dir), -1, 1)
				turn = math.deg(math.atan2(cross, dot))
			end
			prevDir = dir
			sinceLamp += STEP
			sinceTree += STEP

			local farFromStart = p.Magnitude > START_CLEAR
			local normal = Vector2.new(-dir.Y, dir.X) -- левая нормаль к курсу

			-- ФОНАРИ ВДОЛЬ ДОРОГИ: регулярно по всей трассе, а на крутых виражах — чаще
			-- и обязательно снаружи поворота, чтобы вираж читался в темноте.
			local sharp = math.abs(turn) > BEND_DEG
			local due = sinceLamp >= (sharp and LAMP_GAP * 0.6 or LAMP_GAP)
			if farFromStart and due then
				local outward = sharp and (turn > 0 and -normal or normal) or normal * lampSide
				if putLamp(p, outward) then
					nClusterLamps += 1
					sinceLamp = 0
					lampSide = -lampSide -- на прямых чередуем стороны
				end
			end

			if farFromStart and math.abs(turn) < STRAIGHT_DEG and sinceTree >= ALLEY_GAP then
				-- АЛЛЕЯ по обе стороны прямой: коридор из деревьев тянет взгляд вперёд
				local planted = 0
				for _, side in { 1, -1 } do
					local off = ROAD_HALF + RNG:NextNumber(12, 22)
					local at = p + normal * (off * side)
					if put("DeadTree", at.X, at.Y, 0.5, 2.4) then
						planted += 1
					end
				end
				nAlleyTrees += planted
				if planted > 0 then
					sinceTree = 0
				end
			end
			s += STEP
		end
	end
end

-- // Трава: ТОЛЬКО У НАДГРОБИЙ (2026-07-31) -----------------------------------
-- История: сперва пучков было ~490 (=~1500 деталей, больше половины всей сцены) →
-- просадки и фризы; 25.07 срезали до 45 по всему полю; 31.07 убрали совсем вместе
-- с terrain-травой ради кадра. Юзер попросил вернуть «кое-где близ надгробий» —
-- и это как раз правильное место: одинокая травинка посреди голого поля читается
-- как мусор, а пучок, пробившийся у основания камня, читается как заброшенность.
--
-- Поэтому траву сеем НЕ по площади, а по списку реально поставленных камней, и
-- только у каждого N-го. Пучок — три травинки одной моделью: цена всей затеи
-- порядка трёх сотен мелких деталей вместо прежних полутора тысяч.
-- ПЛОТНОСТЬ ПОДНЯТА 2026-07-31 (юзер: «траву забыл добавить к надгробьям»). Трава
-- была на месте — 80 пучков, — но на 582 камня это один куст на семь могил: с дороги
-- такое не читается вовсе, и выглядит как «забыл». Теперь у каждого второго камня, а
-- у крупных участков — два пучка с разных сторон. Потолок поднят соразмерно: пучок
-- это три плоские дощечки без теней, весь ковёр стоил 130 треугольников в кадре
-- против 129 тысяч у самих надгробий.
-- ТРАВА МЕЖДУ МОГИЛАМИ (2026-08-01, просьба юзера «накинуть травы между могилками»).
-- Прежняя росла только вплотную к камню, и с дороги кладбище читалось как ряды плит
-- на голом грунте. Добавлен второй проход: пучок садится в ПРОМЕЖУТКЕ, на 1.5-3.0
-- радиуса участка от центра камня — то есть ровно туда, где раньше был пустой грунт.
local GRASS_EVERY = 2 -- у каждого N-го надгробия — пучок у подножия
local GRASS_GAP_EVERY = 2 -- и у каждого N-го — ещё один в промежутке между могилами
local GRASS_MAX = 700 -- жёсткий потолок на оба прохода: кадр важнее плотности
local grassCount = 0
do
	-- ПУЧОК = ОДИН МЕШ (2026-08-01). Юзер про прежний вариант: «2-3 треугольника
	-- непонятной формы» — и это честно: пучок собирался из четырёх WedgePart, а клин
	-- шириной в полстада читается угловатым осколком, не травой. Тоньше делать нельзя,
	-- уже пробовали: на 0.12 studs лезвие превращается в иглу в пиксель и пропадает с
	-- трёх метров. Форму, которую примитивами не собрать, должен давать меш.
	--
	-- Шаблон `MapTemplates.GrassTuft` — низкополигональный пучок из стора (asset
	-- 88196712273495), нормирован по высоте к 1 и с пивотом в НИЗУ, поэтому сажается
	-- прямо на грунт, а масштаб задаётся здесь. Заодно вчетверо легче: ОДНА деталь на
	-- пучок вместо четырёх (замер: было 697 пучков = 2788 деталей, стало 697).
	--
	-- Запасной вариант с клиньями оставлен на случай, если шаблона в плейсе нет
	-- (он живёт в .rbxl, а не в git): лучше угловатая трава, чем никакой.
	local grassTemplate = templates and templates:FindFirstChild("GrassTuft")

	local function makeTuft(scale: number): Instance
		if grassTemplate and grassTemplate:IsA("BasePart") then
			local p = grassTemplate:Clone()
			p.Name = "GraveGrass"
			p.Size = grassTemplate.Size * (scale * 2.4) -- 2.4: шаблон высотой 1 stud
			-- PivotOffset НЕ масштабируется вместе с Size, поэтому пересчитываем его
			-- после смены размера: иначе пучок повиснет над грунтом или утонет в нём.
			p.PivotOffset = CFrame.new(0, -p.Size.Y / 2, 0)
			return p
		end
		local m = Instance.new("Model")
		m.Name = "GraveGrass"
		local root: BasePart? = nil
		-- Замер 31.07 крупным планом: пучок был из трёх лезвий шириной 0.12 studs и в
		-- тон полю — на экране это игла в пиксель, которой не видно уже с трёх метров
		-- (юзер: «траву забыл добавить»). Лезвий четыре, они втрое шире и заметно суше
		-- по цвету: трава у камня обязана читаться на фоне грунта.
		for _ = 1, 4 do
			local h = RNG:NextNumber(1.7, 3.6) * scale
			local blade = Instance.new("WedgePart")
			blade.Anchored = true
			blade.CanCollide = false
			blade.CanQuery = false
			blade.CanTouch = false
			blade.CastShadow = false
			blade.Material = Enum.Material.Grass
			-- суше и светлее поля: поле = RGB(78,82,58), в тон с ним трава пропадала
			blade.Color = Color3.fromRGB(
				RNG:NextInteger(104, 138),
				RNG:NextInteger(110, 142),
				RNG:NextInteger(54, 78)
			)
			blade.Size = Vector3.new(RNG:NextNumber(0.3, 0.5) * scale, h, RNG:NextNumber(0.5, 0.9) * scale)
			local ang = math.rad(RNG:NextNumber(0, 360))
			local off = RNG:NextNumber(0, 0.7) * scale
			blade.CFrame = CFrame.new(math.cos(ang) * off, h / 2, math.sin(ang) * off)
				* CFrame.Angles(0, ang, 0)
				* CFrame.Angles(0, 0, math.rad(RNG:NextNumber(4, 22)))
			blade.Parent = m
			root = root or blade
		end
		m.PrimaryPart = root
		return m
	end

	for i, spot in cemeterySpots do
		if grassCount >= GRASS_MAX then
			break
		end
		if i % GRASS_EVERY ~= 0 then
			continue
		end
		-- у широкого участка подножие длиннее — там второй пучок с другой стороны
		local tufts = spot.r >= 3.2 and 2 or 1
		local a0 = RNG:NextNumber(0, 360)
		for k = 1, tufts do
			if grassCount >= GRASS_MAX then
				break
			end
			-- прижимаем пучок к подножию камня, со случайной стороны
			local a = math.rad(a0 + (k - 1) * RNG:NextNumber(110, 250))
			local d = spot.r * RNG:NextNumber(0.55, 0.95)
			local gx, gz = spot.x + math.cos(a) * d, spot.z + math.sin(a) * d
			local g = grassPosition(gx, gz)
			if g then
				local tuft = makeTuft(RNG:NextNumber(0.9, 1.6))
				-- пучок строится от нуля вверх, поэтому сажаем пивотом на грунт
				tuft:PivotTo(CFrame.new(gx, g.Y, gz) * CFrame.Angles(0, RNG:NextNumber(0, 6.28), 0))
				tuft.Parent = mapFolder
				grassCount += 1
			end
		end
	end

	-- Второй проход: промежутки. Отступ 1.5-3.0 радиуса уводит пучок с самого участка
	-- на пустой грунт между рядами; попадание к соседнему камню не портит картину —
	-- трава у подножия и так уместна. Смещение по фазе (i + 1), чтобы кусты второго
	-- прохода не садились у тех же камней, что и первого, и ряд не выходил полосатым.
	for i, spot in cemeterySpots do
		if grassCount >= GRASS_MAX then
			break
		end
		if (i + 1) % GRASS_GAP_EVERY ~= 0 then
			continue
		end
		local a = math.rad(RNG:NextNumber(0, 360))
		local d = spot.r * RNG:NextNumber(1.5, 3.0)
		local gx, gz = spot.x + math.cos(a) * d, spot.z + math.sin(a) * d
		local g = grassPosition(gx, gz)
		if g then
			local tuft = makeTuft(RNG:NextNumber(0.8, 1.4)) -- в промежутке чуть мельче
			tuft:PivotTo(CFrame.new(gx, g.Y, gz) * CFrame.Angles(0, RNG:NextNumber(0, 6.28), 0))
			tuft.Parent = mapFolder
			grassCount += 1
		end
	end
end

-- // ЧИСТКА ДОРОГИ (2026-07-25): убираем ЛЮБОЙ декор, чей центр ближе
-- (RoadWidth/2 + запас) к осевой трассы — плиты/деревья у обочины иногда нависают
-- на полотно и бьют машину. Черепа-чекпоинты живут в RaceMarkers (не тут) — целы.
do
	local poly = MapLayout.TrackPolyline
	local scale = MapLayout.Scale
	local clearR = GameConfig.Map.RoadWidth / 2 + 6 -- половина дороги + буфер
	local clearR2 = clearR * clearR
	local removed = 0
	for _, m in mapFolder:GetChildren() do
		if m:GetAttribute("Roadside") then
			continue -- фонари вдоль дороги: поставлены у обочины осознанно, подошва промерена
		end
		local ok, piv = pcall(function()
			return m:GetPivot().Position
		end)
		if ok then
			local best = math.huge
			for _, p in poly do
				local dx = piv.X - p.X * scale
				local dz = piv.Z - p.Y * scale
				local d2 = dx * dx + dz * dz
				if d2 < best then
					best = d2
				end
			end
			if best < clearR2 then
				m:Destroy()
				removed += 1
			end
		end
	end
	print(("[MapBuilder] Дорога очищена: снято %d объектов с полотна."):format(removed))
end

-- // ОПТИМИЗАЦИЯ теней (2026-07-25, ужато 2026-07-31): каждый CastShadow-part
-- дорог, а деревьев стало 281 вместо прежних 60 — замер показал ровно 281 теневую
-- деталь на сцене против трёх десятков у всего остального. Тень оставляем только
-- деревьям ВДОЛЬ ТРАССЫ: их силуэт игрок и видит, а тени дальнего леса он не
-- увидит никогда — они лишь греют видеокарту (жалоба «шумят кулера»).
local SHADOW_TRACK_RANGE = 45
local shadowTrees = 0
for _, m in mapFolder:GetChildren() do
	local keepShadow = false
	if m.Name:match("^DeadTree") then
		local p = m:GetPivot().Position
		keepShadow = trackDistance(p.X, p.Z) < SHADOW_TRACK_RANGE
		if keepShadow then
			shadowTrees += 1
		end
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CastShadow = keepShadow
		end
	end
end

-- // Ограда по периметру карты. Кованый забор из стора (шаблон MapTemplates.Fence)
-- тайлится по периметру; под ним — тёмный каменный цоколь (ВИДИМЫЙ, коллайд —
-- держит машины; заменяет прежние невидимые стены). Прямоугольник вокруг площади.
local function buildPerimeterFence(half: number, baseY: number)
	local fence = Instance.new("Model")
	fence.Name = "PerimeterFence"
	local STONE = Color3.fromRGB(30, 30, 34)
	local full = half * 2 + 2

	-- каменный цоколь (коллайд, видимый) — барьер для машин
	local function curb(cx: number, cz: number, sx: number, sz: number)
		local c = Instance.new("Part")
		c.Anchored = true
		c.CanCollide = true
		c.CanQuery = false
		c.CanTouch = false
		c.CastShadow = false
		c.Material = Enum.Material.Slate
		c.Color = STONE
		c.Size = Vector3.new(sx, 5, sz) -- ниже: не чёрная стена, но держит машины
		c.Position = Vector3.new(cx, baseY + 2.5, cz)
		c.Parent = fence
	end
	curb(0, -half, full, 1.5)
	curb(0, half, full, 1.5)
	curb(-half, 0, 1.5, full)
	curb(half, 0, 1.5, full)

	-- кованый забор (декор) поверх цоколя — тайлим шаблон
	local tmpl = templates and templates:FindFirstChild("Fence")
	if tmpl then
		local _, size = tmpl:GetBoundingBox()
		local seg = math.max(size.X, 4)
		local function tileSide(fx: number, fz: number, tx: number, tz: number, rotY: number)
			local dx, dz = tx - fx, tz - fz
			local len = math.sqrt(dx * dx + dz * dz)
			local n = math.max(1, math.floor(len / seg))
			for i = 0, n - 1 do
				local t = (i + 0.5) / n
				-- юнионы шаблона уже RenderFidelity=Performance (задано в Studio: рантайм-
				-- скрипт НЕ может писать RenderFidelity — capability Plugin); клон наследует.
				local piece = tmpl:Clone()
				-- ШИПЫ ДОЛОЙ (2026-07-31, жалоба «шумят кулера»). Замер по кадру с трассы:
				-- ограда давала 81 264 tris из 238 928, и 69 720 из них — два юниона
				-- декоративных шипов поверху (`Small Spikes` 36 540 + `Large Spikes`
				-- 33 180). Это 29% треугольников всего кадра ради узора, который с 60-90
				-- studs читается как мохнатая линия. Столбы, рейки и прутья остаются —
				-- силуэт ограды сохраняется. Вернуть — убрать этот блок.
				for _, junk in { "Small Spikes", "Large Spikes" } do
					local part = piece:FindFirstChild(junk, true)
					while part do
						part:Destroy()
						part = piece:FindFirstChild(junk, true)
					end
				end
				piece:PivotTo(CFrame.new(fx + dx * t, baseY, fz + dz * t) * CFrame.Angles(0, rotY, 0))
				piece.Parent = fence
			end
		end
		tileSide(-half, -half, half, -half, 0)
		tileSide(-half, half, half, half, 0)
		tileSide(-half, -half, -half, half, math.rad(90))
		tileSide(half, -half, half, half, math.rad(90))
	end
	fence.Parent = workspace
end
buildPerimeterFence(335, GameConfig.Map.GroundTop + 2) -- ниже: утоплен в землю, без зазора

-- // Список ассетов декора для клиентского прелоада ---------------------------
-- Под StreamingEnabled клиент НЕ видит дальний декор, поэтому DecorPreload не может
-- собрать список мешей сам (в его workspace лежит только ближний кусок) — а без
-- прогрева меши грузятся в момент въезда в новый участок, это и есть фризы на
-- трассе. Сервер видит карту целиком, поэтому список собираем здесь и кладём в
-- ReplicatedStorage строкой (уникальные ID, по одному на строку).
do
	local seen: { [string]: boolean } = {}
	local ids: { string } = {}
	local function add(id: string)
		if id ~= "" and not seen[id] then
			seen[id] = true
			table.insert(ids, id)
		end
	end
	for _, root in { mapFolder, workspace:FindFirstChild("PerimeterFence"), workspace:FindFirstChild("StartGate"), workspace:FindFirstChild("GateSign") } do
		if root then
			for _, d in root:GetDescendants() do
				if d:IsA("MeshPart") then
					add(d.MeshId)
					add(d.TextureID)
				elseif d:IsA("Decal") or d:IsA("Texture") then
					add(d.Texture)
				elseif d:IsA("SpecialMesh") then
					add(d.MeshId)
					add(d.TextureId)
				end
			end
		end
	end
	local holder = Instance.new("StringValue")
	holder.Name = "DecorAssets"
	holder.Value = table.concat(ids, "\n")
	holder.Parent = ReplicatedStorage
	print(("[MapBuilder] Список ассетов для прелоада: %d уникальных."):format(#ids))
end

print(
	`[MapBuilder] Расставлено: {#MapLayout.Hazards} hazard'ов, {#MapLayout.Graves} могил, {#MapLayout.Lamps} фонарей, {#MapLayout.DeadTrees} деревьев (по карте). `
		.. `Кладбище рядами: {nCemetery} надгробий (участок по размеру камня, 8 типов). `
		.. `Деревья: {nTree} по площади + {nAlleyTrees} в аллеях (тени только у {shadowTrees} вдоль трассы). Фонарей у дороги: {nClusterLamps}. `
		.. `Поле = {MapGen.FieldMaterial.Name} без декорации, трава только у камней: {grassCount} пучков. Ограда по периметру ±335.`
)
