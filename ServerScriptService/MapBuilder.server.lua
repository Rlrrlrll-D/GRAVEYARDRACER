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

-- ТРАВА ТЕРРЕЙНА: проверена и НЕ виновата в фризах (замер 2026-07-30). В кадре она
-- действительно самая тяжёлая по геометрии — `Stats.RenderBreakdown` на пустой карте
-- дал `Grass 438 852 tris / 100 draws` против `Opaque 5 367 / 5`, — но цена эта
-- РОВНАЯ, а не рывками: проезд камерой на 84 studs/с по свежеперезалитому полю (вся
-- трава пересобиралась заново) дал 2230 кадров с худшим 19 мс и ноль всплесков.
-- Выключить её всё равно нечем: `Terrain.Decoration` в этой версии Roblox — «not a
-- valid member» и из песочницы MCP, и из обычного серверного скрипта; трава идёт от
-- самого материала Grass. Если когда-нибудь понадобится убрать — менять материал поля.
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
-- то есть надгробия почти ничего не стоят — тяжёлая тут земля, а не декор.
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
local CEM_KINDS = {
	{ name = "Tombstone", weight = 30, sMin = 1.0, sMax = 2.6 },
	{ name = "Tombstone_B", weight = 22, sMin = 1.0, sMax = 2.4 },
	{ name = "Tombstone_C", weight = 14, sMin = 0.9, sMax = 1.8 },
	{ name = "Tombstone_G", weight = 12, sMin = 1.2, sMax = 2.6 },
	{ name = "Tombstone_F", weight = 10, sMin = 0.9, sMax = 1.6 },
	{ name = "Tombstone_E", weight = 8, sMin = 0.6, sMax = 1.0 }, -- обелиск, высокий
	-- Плита широкая (11 studs): в полный рост читается как стена поперёк участка,
	-- поэтому и вес маленький, и масштаб срезан — она тут семейный склеп, не забор.
	{ name = "Tombstone_D", weight = 3, sMin = 0.45, sMax = 0.7 }
}
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
	-- Дорога = Ground, поле = Grass, поэтому «занято ли место дорогой» решает тот же
	-- рейкаст, что и у остальной расстановки: nil = полотно или дыра.
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
			local tmpl = getTemplateVariant(kind.name)
			if tmpl then
				local model = tmpl:Clone()
				model:ScaleTo(RNG:NextNumber(kind.sMin, kind.sMax))
				dropToGround(model, g, CEM_YAW) -- разворот ОДИН на всех: ряды параллельны
				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") then
						part.Anchored = true
						part.CanCollide = true
						part.CollisionGroup = "Obstacles"
						part.CastShadow = false
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
				CollectionService:AddTag(light, "FlickerLight")
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

-- ОПТИМИЗАЦИЯ (2026-07-25): пучки-травинки дорогие — каждый 2-4 WedgePart. Раньше
-- их было ~490 (=~1500 деталей, БОЛЬШЕ ПОЛОВИНЫ всей сцены) → просадки/фризы,
-- кулеры. Оставляем лёгкую россыпь для переднего плана; фон держит terrain-материал
-- Grass (при желании — включить грасс-декорацию Terrain в свойствах, она бесплатна).
local fieldTarget, ftries, fieldPlaced = 45, 0, 0
while fieldPlaced < fieldTarget and ftries < fieldTarget * 12 do
	ftries += 1
	local g = grassPosition(RNG:NextNumber(-330, 330), RNG:NextNumber(-330, 330))
	if g then
		placeGrassTuft(g, RNG:NextNumber(1.0, 2.0))
		fieldPlaced += 1
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

-- // ОПТИМИЗАЦИЯ теней (2026-07-25): под Future каждый CastShadow-part дорог
-- (были сотни casters → фризы). Тени оставляем ТОЛЬКО деревьям (атмосферные
-- силуэты); весь прочий декор — без теней.
for _, m in mapFolder:GetChildren() do
	local keepShadow = m.Name:match("^DeadTree") ~= nil
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
		.. `Деревья: {nTree} по площади + {nAlleyTrees} в аллеях. Фонарей у дороги: {nClusterLamps}. `
		.. `Травы: {grassCount} пучков. Ограда по периметру ±335.`
)
