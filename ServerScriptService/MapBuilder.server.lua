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

-- // Расстояние до осевой трассы -----------------------------------------------
-- Нужно, чтобы деревья не лезли к полотну: рейкаст «под ногами трава» этого не
-- ловит — в 23 studs от осевой трава есть, а крона уже висит над дорогой.
local TREE_ROAD_CLEAR = 34 -- ближе этого к осевой деревьев нет: полотно 22.4 + запас
local TREE_SINK = 0.35 -- на столько топим ствол в грунт, чтобы не читался шов
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

-- // Посадка «по стволу», а не по пивоту ---------------------------------------
-- У мешей деревьев пивот смещён от самого ствола (у `DeadTree_B` на 2.2 studs, а с
-- масштабом до 3.6 это ~8). Из-за этого проверка «под точкой трава» относилась к
-- пустому месту, а ствол вставал в стороне — иногда прямо на полотно. Поэтому после
-- посадки сдвигаем модель так, чтобы в заданную точку попал ЦЕНТР МАССЫ деталей.
local function centerOnTrunk(model: Model, x: number, z: number)
	local sum, n = Vector3.zero, 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			sum += d.Position
			n += 1
		end
	end
	if n == 0 then
		return
	end
	local c = sum / n
	model:PivotTo(model:GetPivot() + Vector3.new(x - c.X, 0, z - c.Z))
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
		local model = tmpl:Clone()
		model:ScaleTo(RNG:NextNumber(sMin, sMax))
		if name == "DeadTree" then
			paintTree(model) -- каждое дерево — свой случайный тёмно-коричневый
		end
		dropToGround(model, g, RNG:NextNumber(0, 360))
		centerOnTrunk(model, x, z) -- ствол в проверенную точку, а не пивот меша
		-- после сдвига пересаживаем на землю и топим на палец: у самой земли шов
		-- между стволом и травой иначе читается как «дерево висит»
		local g2 = grassPosition(model:GetPivot().Position.X, model:GetPivot().Position.Z)
		if g2 then
			model:PivotTo(model:GetPivot() + Vector3.new(0, g2.Y - g.Y, 0))
		end
		model:PivotTo(model:GetPivot() - Vector3.new(0, TREE_SINK, 0))
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
local CEM_COL = 10 -- шаг места в ряду, studs
local CEM_ROW = 13 -- шаг между рядами, studs
local CEM_AISLE_ROW = 6 -- каждый 6-й ряд — поперечная дорожка
local CEM_AISLE_COL = 11 -- каждый 11-й столбец — продольная дорожка
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
local CEM_KINDS = {
	{ name = "Tombstone", weight = 18, sMin = 1.0, sMax = 2.4 },
	{ name = "Tombstone_B", weight = 15, sMin = 1.0, sMax = 2.2 },
	{ name = "Tombstone_H", weight = 14, sMin = 0.9, sMax = 1.8 }, -- кельтский крест
	{ name = "Tombstone_C", weight = 13, sMin = 0.9, sMax = 1.8 },
	{ name = "Tombstone_J", weight = 13, sMin = 1.0, sMax = 1.9 }, -- крест на плинте
	{ name = "Tombstone_G", weight = 12, sMin = 1.2, sMax = 2.6 },
	{ name = "Tombstone_F", weight = 10, sMin = 0.9, sMax = 1.6 },
	{ name = "Tombstone_E", weight = 5, sMin = 0.6, sMax = 1.0 }, -- обелиск, высокий
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

local nCemetery = 0
do
	-- Дорога и поле — разные материалы террейна (см. MapGen), поэтому «занято ли
	-- место дорогой» решает тот же рейкаст, что и у остальной расстановки:
	-- nil = полотно или дыра.
	local col = 0
	for x = -CEM_HALF, CEM_HALF, CEM_COL do
		col += 1
		local row = 0
		local colAisle = (col % CEM_AISLE_COL == 0)
		for z = -CEM_HALF, CEM_HALF, CEM_ROW do
			row += 1
			if colAisle or (row % CEM_AISLE_ROW == 0) then
				continue -- дорожка между участками
			end
			if not clearOfLandmarks(x, z) then
				continue
			end
			local g = grassPosition(x, z)
			if not g then
				continue -- полотно трассы
			end
			-- у самой кромки не ставим: рейкаст в четырёх точках вокруг места
			local tooCloseToRoad = false
			for _, d in { Vector2.new(CEM_ROAD_CLEAR, 0), Vector2.new(-CEM_ROAD_CLEAR, 0), Vector2.new(0, CEM_ROAD_CLEAR), Vector2.new(0, -CEM_ROAD_CLEAR) } do
				if not grassPosition(x + d.X, z + d.Y) then
					tooCloseToRoad = true
					break
				end
			end
			if tooCloseToRoad then
				continue
			end
			local kind = pickKind()
			-- ТОЧНЫЙ шаблон, не `getTemplateVariant`: тот сам случайно выбирает среди
			-- всех `Tombstone_*` и затирает веса — в первой сборке из-за этого «Tombstone»
			-- с весом 18% получил 3% поля, а раздача типов шла почти поровну.
			local tmpl = getTemplate(kind.name)
			if tmpl then
				local model = tmpl:Clone()
				model:ScaleTo(RNG:NextNumber(kind.sMin, kind.sMax))
				dropToGround(model, g, CEM_YAW) -- разворот ОДИН на всех: ряды параллельны
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
			end
		end
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
		local LAMP_GAP = 150 -- шаг фонарей вдоль дороги, studs
		local LAMP_OFFSET = 4 -- от кромки полотна: фонарь стоит У ДОРОГИ, не в поле
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
			local model = tmpl:Clone()
			model:ScaleTo(RNG:NextNumber(sMin, sMax))
			if name == "DeadTree" then
				paintTree(model)
			end
			dropToGround(model, g, RNG:NextNumber(0, 360))
			if name == "DeadTree" then
				centerOnTrunk(model, x, z)
				local p = model:GetPivot().Position
				local g2 = grassPosition(p.X, p.Z)
				if g2 then
					model:PivotTo(model:GetPivot() + Vector3.new(0, g2.Y - g.Y, 0))
				end
				model:PivotTo(model:GetPivot() - Vector3.new(0, TREE_SINK, 0))
			end
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
			local model = lamp:Clone()
			model:ScaleTo(LAMP_SCALE) -- ~17 studs: фонарь должен нависать над полотном
			dropToGround(model, g, RNG:NextNumber(0, 360))
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

-- // Трава: УБРАНА СОВСЕМ (2026-07-31) ----------------------------------------
-- Здесь жили пучки-травинки из WedgePart'ов. История: сперва их было ~490
-- (=~1500 деталей, больше половины всей сцены) → просадки и фризы; 25.07 их
-- срезали до 45 «для переднего плана». Теперь убраны и эти: юзер просил снять
-- траву с поля ради кадра, а держать 45 моделей ради переднего плана бессмысленно,
-- когда фоновой terrain-травы (см. FIELD_COLOR выше) больше нет — одинокие
-- травинки на голом поле читались бы как мусор, а не как трава.

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
		.. `Кладбище рядами: {nCemetery} надгробий (шаг {CEM_COL}×{CEM_ROW}, 7 типов). `
		.. `Деревья: {nTree} по площади + {nAlleyTrees} в аллеях (тени только у {shadowTrees} вдоль трассы). Фонарей у дороги: {nClusterLamps}. `
		.. `Трава убрана: поле = {MapGen.FieldMaterial.Name} без декорации. Ограда по периметру ±335.`
)
