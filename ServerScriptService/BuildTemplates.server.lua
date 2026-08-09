--!strict
-- Script: ServerScriptService.BuildTemplates
-- Одноразовый билдер: наполняет ServerStorage.MapTemplates моделями из
-- ModelFactory (их подхватит MapBuilder), ставит мавзолей по координатам
-- MapLayout и создаёт машину на старте с тегом PlayerVehicle.
-- Также приводит задние моторы багги в движение по Throttle/Steer сиденья.
--
-- АДАПТАЦИЯ: в плейсе уже есть своя машина (GraveyardBuggy на A-Chassis
-- с тегом PlayerVehicle), поэтому секция 3 создаёт багги только если
-- в игре нет ни одной модели с тегом PlayerVehicle, а уже стоящие машины
-- лишь разворачивает носом по ходу гонки.

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local ModelFactory = require(script.Parent:WaitForChild("ModelFactory"))
local MapLayout = require(ReplicatedStorage:WaitForChild("MapLayout"))

-- // 1. Шаблоны для MapBuilder ------------------------------------------------
local templates = ServerStorage:FindFirstChild("MapTemplates")
if not templates then
	templates = Instance.new("Folder")
	templates.Name = "MapTemplates"
	templates.Parent = ServerStorage
end

local factoryTemplates: {[string]: () -> Model} = {
	Tombstone = ModelFactory.Tombstone,
	GraveMarker = ModelFactory.GraveMarker,
	Lamp = ModelFactory.Lamp,
	DeadTree = ModelFactory.DeadTree,
}
for name, build in factoryTemplates do
	if not templates:FindFirstChild(name) then
		build().Parent = templates
	end
end

-- // 2. Мавзолей по координатам из MapLayout (если задан лендмарк) --------------
if MapLayout.Landmarks.Mausoleum and not workspace:FindFirstChild("Mausoleum", true) then
	local mausoleum = ModelFactory.Mausoleum()
	local pos = MapLayout.Landmarks.Mausoleum.Position * MapLayout.Scale
	mausoleum:PivotTo(CFrame.new(pos.X, 8, pos.Y)) -- Y подгоните под рельеф
	mausoleum.Parent = workspace
end

-- // 3. Направление старта (из MapLayout.StartDir, форма Road.svg) --------------
-- машина/стрелки на старте равняются носом по ходу гонки к первому чекпоинту.
local startDir = Vector3.new(MapLayout.StartDir.X, 0, MapLayout.StartDir.Y).Unit

local function spawnBuggy(cf: CFrame): Model
	local buggy = ModelFactory.Buggy()
	buggy:PivotTo(cf) -- PrimaryPart (Chassis) без наклона, нос модели = -Z
	buggy.Parent = workspace
	CollectionService:AddTag(buggy, "PlayerVehicle")

	-- Управление: сиденье -> моторы задних колёс + сервоповорот не нужен,
	-- рулим напрямую вращением через differential torque (просто и надёжно).
	local seat = buggy:WaitForChild("DriveSeat") :: VehicleSeat
	local chassis = buggy:WaitForChild("Chassis") :: BasePart
	local hingeRL = chassis:WaitForChild("HingeRL") :: HingeConstraint
	local hingeRR = chassis:WaitForChild("HingeRR") :: HingeConstraint

	local WHEEL_SPEED = 28 -- рад/сек при полном газе

	RunService.Heartbeat:Connect(function()
		if not buggy.Parent then return end
		local throttle = seat.Throttle
		local steer = seat.Steer
		if buggy:GetAttribute("Destroyed") then
			throttle = 0
			steer = 0
		end
		-- дифференциал: при повороте одно колесо крутится быстрее другого
		hingeRL.AngularVelocity = -(throttle + steer * 0.5) * WHEEL_SPEED
		hingeRR.AngularVelocity = -(throttle - steer * 0.5) * WHEEL_SPEED
	end)

	return buggy
end

-- Своя машина уже в плейсе — только разворачиваем её носом по ходу гонки
-- (позицию не трогаем). VehicleSeat едет в сторону своего LookVector,
-- поэтому равняем по сиденью, а не по пивоту модели.
local function alignVehicle(model: Model)
	local seat = model:FindFirstChild("DriveSeat")
	if not (seat and seat:IsA("VehicleSeat")) then
		return
	end
	local look = seat.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.05 then
		return
	end
	local cur = flat.Unit
	local yaw = math.atan2(cur.Z * startDir.X - cur.X * startDir.Z, cur:Dot(startDir))
	if math.abs(yaw) < math.rad(2) then
		return -- уже смотрит куда надо
	end
	local pivot = model:GetPivot()
	model:PivotTo(CFrame.new(pivot.Position) * CFrame.Angles(0, yaw, 0) * pivot.Rotation)
	print(`[BuildTemplates] {model.Name} развёрнут по направлению трассы.`)
end

-- Преж-размещённую машину на старте НЕ создаём: гридом/спавном машин владеет
-- PlayerFlow (выдаёт машину игроку на отсчёте, грид считает из MapLayout).
-- spawnBuggy/alignVehicle оставлены на случай ручной расстановки в .rbxl.
local startPos = MapLayout.Landmarks.StartGate.Position * MapLayout.Scale
local _, _ = spawnBuggy, alignVehicle -- функции сохранены, но здесь не вызываются

-- // 4. Шевроны направления на старте --------------------------------------------
-- Неоновые стрелки на полотне сразу за стартовой чертой: с места старта
-- не очевидно, в какую сторону восьмёрки ехать к первому чекпоинту.
-- ТОЛЬКО ПО ТЕРРЕЙНУ и nil при промахе. Раньше луч бил по всему подряд и на промахе
-- возвращал 2 — «дно» из Map.GroundTop. Именно это и закапывало стрелки, см. ниже.
local function roadY(x: number, z: number): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local result = workspace:Raycast(Vector3.new(x, 200, z), Vector3.new(0, -400, 0), params)
	return result and result.Position.Y or nil
end

local arrowFolder = Instance.new("Folder")
arrowFolder.Name = "StartArrows"
arrowFolder.Parent = workspace

local sideDir = Vector3.new(-startDir.Z, 0, startDir.X) -- перпендикуляр к трассе

-- СТРЕЛКИ СТАВИМ ПОСЛЕ ТОГО, КАК ПОЯВИТСЯ ПОЛОТНО (2026-08-09, юзер: «стрелок вообще
-- нет»). Они были на месте — все шесть, неоновые, — но ПОД ЗЕМЛЁЙ: верх на Y 2.25 при
-- полотне на Y 6.0. Причина в порядке запуска серверных скриптов: он не определён, и
-- BuildTemplates успевал промерить землю раньше, чем MapBuilder красил террейн. Луч
-- уходил в пустоту, срабатывало запасное значение — и шевроны ложились на дно карты.
-- ЖДЁМ ИМЕННО ФЛАГ workspace.MapReady, а не «попадания луча». Попадание — негодный
-- признак: базовая плита земли (Map.GroundTop = 2) лежит там с самого начала, луч
-- натыкается на неё сразу, и стрелки всё равно ложились на Y≈2 при полотне на Y=6.
-- Флаг ставит MapBuilder последней строкой, когда дорога уже поднята.
task.spawn(function()
	local deadline = os.clock() + 60
	while not workspace:GetAttribute("MapReady") and os.clock() < deadline do
		task.wait(0.25)
	end
	if not workspace:GetAttribute("MapReady") then
		warn("[BuildTemplates] MapBuilder не отчитался о готовности — стрелки старта не размещены")
		return
	end

	for i = 1, 3 do
		local flat = Vector3.new(startPos.X, 0, startPos.Y) + startDir * (10 + i * 12)
		-- 0.3 над поверхностью, а не 0.15: деталь толщиной 0.2 лежит плашмя, и при
		-- меньшем зазоре её нижняя грань цепляет террейн и мерцает z-файтингом.
		local ground = roadY(flat.X, flat.Z)
		if ground then
			local tip = Vector3.new(flat.X, ground + 0.3, flat.Z)
			for _, side in { -1, 1 } do
				local wing = Instance.new("Part")
				wing.Name = "StartChevron"
				wing.Size = Vector3.new(1.6, 0.2, 7)
				wing.Material = Enum.Material.Neon
				wing.Color = Color3.fromRGB(110, 255, 170) -- в цвет маяков-чекпоинтов
				wing.Transparency = 0.15
				wing.Anchored = true
				wing.CanCollide = false
				wing.CanQuery = false
				wing.CanTouch = false
				-- крыло шеврона: от вершины назад и вбок под 45°
				local tail = tip - startDir * 5 + sideDir * (side * 5)
				wing.CFrame = CFrame.lookAt((tip + tail) / 2, tip)
				wing.Parent = arrowFolder
			end
		end
	end
	print("[BuildTemplates] стрелки старта размещены по полотну.")
end)

print("[BuildTemplates] Шаблоны созданы, мавзолей размещён (стрелки — отдельной строкой, они ждут полотна).")
