--!strict
-- ModuleScript: ServerScriptService.PlayerFlow
-- Жизненный цикл игрока в упрощённой модели «заставка → отсчёт → гонка»:
-- игрок стоит у СТАРТА (без лобби-платформы и диорам), заморожен пока не гонка;
-- на старте ему выдаётся своя машина с владельцем (OwnerUserId) и он в неё
-- садится; после заезда возвращается к старту. Машина уничтожается при эвикте и
-- на PlayerRemoving — чинит старый баг накопления клонов багги.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VehicleRegistry = require(ReplicatedStorage:WaitForChild("VehicleRegistry"))
local MapLayout = require(ReplicatedStorage:WaitForChild("MapLayout"))
local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))

local PlayerFlow = {}

local vehicleOfPlayer: { [Player]: Model } = {}

-- // Точка старта (где игрок стоит под заставкой/отсчётом) --------------------
-- Захватывается в init из мировой SpawnLocation; игрок телепортируется сюда и
-- замораживается, пока не сядет в машину. Никакой платформы/диорамы.
local START_CF = CFrame.new(28, 5, 28)

local function freeze(hum: Humanoid)
	hum.WalkSpeed = 0
	hum.JumpPower = 0
	hum.JumpHeight = 0
end
local function unfreeze(hum: Humanoid)
	hum.WalkSpeed = 16
	hum.JumpPower = 50
	hum.JumpHeight = 7.2
end

-- Вернуть персонажа к старту (под заставку) и заморозить. Имя sendToLobby
-- сохранено — им пользуется MatchManager.evict/onCharacterAdded.
function PlayerFlow.sendToLobby(player: Player)
	local char = player.Character
	if not char then
		return
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and hum.SeatPart then
		-- Sit=false снимает SeatWeld только на следующем шаге физики → PivotTo
		-- утащило бы персонажа обратно к сиденью. Снимаем weld сами, мгновенно.
		local weld = hum.SeatPart:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end
	if hum then
		hum.Sit = false
	end
	task.wait() -- дать физике отпустить персонажа
	local scatter = Vector3.new(math.random(-6, 6), 0, math.random(-6, 6))
	char:PivotTo(START_CF + scatter)
	if hum then
		freeze(hum) -- под заставкой не бродим
	end
end

-- // Стартовая решётка: КОЛОННА ПО ДВА ВДОЛЬ ТРАССЫ ---------------------------
-- Места идут парами назад от стартовой линии ПО ОСЕВОЙ (MapLayout.TrackPolyline):
-- ряд = два места по разные стороны от осевой, машины смотрят по касательной, так
-- что колонна повторяет изгиб дороги, а не уходит по прямой в траву.
--
-- Габариты багги в системе координат сиденья (замерено по VehicleTemplate):
-- длина 13.1 (нос 7.3 впереди сиденья, корма 5.8 позади), ширина 8.3, причём
-- сиденье смещено на 1.6 ВЛЕВО от геометрического центра кузова.
local CAR_LEN = 13.1
local CAR_SEAT_OFFSET_X = 1.6 -- центр кузова правее сиденья на столько
local GRID_ROW_GAP = CAR_LEN + 5 -- 18.1: между рядами есть просвет (раньше 8 — машины ПЕРЕКРЫВАЛИСЬ)
local GRID_LANE = 8 -- вбок от осевой (дорога 44.8 → полполотна 22.4, край кузова на 12.2)

local FALLBACK_SEAT_CF = CFrame.lookAt(Vector3.new(10.05, 7.21, 5.19), Vector3.new(9.05, 7.21, 5.19))
local gridBaseSeatCF = FALLBACK_SEAT_CF
local gridSlots: { CFrame } = {} -- построенные места (заполняется, когда террейн готов)
local gridDepthStuds = 0 -- фактическая длина колонны по осевой (для точки лобби)

PlayerFlow.MaxSlots = 8
local GRID_ROWS = math.ceil(PlayerFlow.MaxSlots / 2)

local function captureGridBase()
	local captured = false
	for _, v in CollectionService:GetTagged("PlayerVehicle") do
		if v:IsA("Model") and v.Parent == workspace then
			local seat = v:FindFirstChild("DriveSeat")
			if not captured and seat and seat:IsA("VehicleSeat") then
				gridBaseSeatCF = seat.CFrame
				captured = true
			end
			v:Destroy() -- мир стартует без свободных машин
		end
	end
	if not captured then
		warn("[PlayerFlow] Преж-установленного багги нет — решётка от запасного CFrame.")
	end
end

-- Точка на осевой в `dist` studs ПОЗАДИ старта + касательная (направление езды).
-- Полилиния замкнутая, движение — по возрастанию индекса, значит назад = вниз по
-- индексу. Возвращает мировые X/Z (уже с учётом MapLayout.Scale) и единичный
-- вектор направления движения.
local function trackPointBehind(dist: number): (Vector2?, Vector2?)
	local poly = MapLayout.TrackPolyline
	if not poly or #poly < 4 then
		return nil, nil
	end
	local n = #poly
	local i = 1 -- TrackPolyline[1] — стартовая точка (= Landmarks.StartGate)
	local remaining = dist
	for _ = 1, n do
		local prev = ((i - 2) % n) + 1 -- индекс i-1 с заворотом
		local a, b = poly[prev], poly[i]
		local d = (b - a).Magnitude
		local fwd = d > 1e-4 and (b - a).Unit or Vector2.new(1, 0)
		if d >= remaining then
			local p = b:Lerp(a, d > 1e-4 and (remaining / d) or 0)
			return p * MapLayout.Scale, fwd
		end
		remaining -= d
		i = prev
	end
	return nil, nil
end

-- Ряд на дистанции dist позади старта: базовый CFrame и центры кузовов обеих полос.
local function gridRow(dist: number, y: number): (CFrame?, { Vector3 })
	local res, fwd = trackPointBehind(dist)
	if not res or not fwd then
		return nil, {}
	end
	local p, f = res :: Vector2, fwd :: Vector2
	local at = Vector3.new(p.X, y, p.Y)
	local base = CFrame.lookAt(at, at + Vector3.new(f.X, 0, f.Y))
	return base, { (base * CFrame.new(-GRID_LANE, 0, 0)).Position, (base * CFrame.new(GRID_LANE, 0, 0)).Position }
end

-- Построить места по осевой на высоте y (высота дороги — полотно плоское).
-- ВАЖНО: шаг между рядами АДАПТИВНЫЙ. Отмерять ряды по осевой недостаточно — на
-- изгибе внутренняя полоса идёт по более короткой дуге и машины съезжаются
-- (на нашей трассе 3-й ряд оставался с зазором 1 stud). Поэтому ряд отодвигается
-- назад, пока ОБЕ полосы не разойдутся на GRID_ROW_GAP.
local function buildGridSlots(y: number)
	local slots: { CFrame } = {}
	local dist = 0
	local _, prevBodies = gridRow(0, y)
	if #prevBodies == 0 then
		return -- нет полилинии: остаёмся на запасной решётке
	end
	for row = 0, GRID_ROWS - 1 do
		if row > 0 then
			dist += GRID_ROW_GAP
			for _ = 1, 60 do
				local _, bodies = gridRow(dist, y)
				if #bodies == 0 then
					return
				end
				local ok = true
				for k, b in bodies do
					if (b - prevBodies[k]).Magnitude < GRID_ROW_GAP - 0.05 then
						ok = false
						break
					end
				end
				if ok then
					break
				end
				dist += 1
			end
		end
		local base, bodies = gridRow(dist, y)
		if not base then
			return
		end
		prevBodies = bodies
		for side = 0, 1 do
			-- нечётные места слева от осевой, чётные справа; сиденье сдвигаем так,
			-- чтобы по центру полосы оказался КУЗОВ, а не сиденье.
			local lane = (side == 0) and -GRID_LANE or GRID_LANE
			table.insert(slots, (base :: CFrame) * CFrame.new(lane - CAR_SEAT_OFFSET_X, 0, 0))
		end
	end
	gridSlots = slots
	gridDepthStuds = dist
end

-- CFrame СИДЕНЬЯ для места i (1..MaxSlots)
function PlayerFlow.gridSlot(i: number): CFrame
	local built = gridSlots[math.clamp(i, 1, PlayerFlow.MaxSlots)]
	if built then
		return built
	end
	-- запасной вариант (террейн ещё не готов / нет полилинии): прямая колонна по два
	if i <= 1 then
		return gridBaseSeatCF
	end
	local row = math.ceil(i / 2) - 1
	local lane = (i % 2 == 1) and -GRID_LANE or GRID_LANE
	return gridBaseSeatCF * CFrame.new(lane - CAR_SEAT_OFFSET_X, 0, row * GRID_ROW_GAP)
end

-- // Выдача/уборка машины -----------------------------------------------------
local template: Model? = nil
local pivotFromSeat = CFrame.new()

local function ensureTemplate(): Model?
	if template then
		return template
	end
	local t = ServerStorage:FindFirstChild("VehicleTemplate")
	if t and t:IsA("Model") then
		local seat = t:FindFirstChild("DriveSeat")
		if seat and seat:IsA("VehicleSeat") then
			-- пивот багги наклонён (Wedge) → ставим клоны по CFrame сиденья
			pivotFromSeat = seat.CFrame:Inverse() * t:GetPivot()
		end
		template = t
	else
		warn("[PlayerFlow] Нет ServerStorage.VehicleTemplate.")
	end
	return template
end

function PlayerFlow.assignVehicle(player: Player, seatCFrame: CFrame): Model?
	PlayerFlow.releaseVehicle(player) -- на всякий: не плодим вторую машину
	local t = ensureTemplate()
	if not t then
		return nil
	end
	local car = t:Clone()
	car.Name = "Buggy_" .. player.UserId
	car:SetAttribute("OwnerUserId", player.UserId)
	local seat = car:FindFirstChild("DriveSeat")
	if seat and seat:IsA("VehicleSeat") then
		seat.HeadsUpDisplay = false -- нативный Roblox-спидометр (CoreGui.VehicleHudFrame) не нужен: свой HUD
	end
	car:PivotTo(seatCFrame * pivotFromSeat) -- ДО Parent: VehicleController запомнит «дом»
	-- A-Chassis + StreamingEnabled: под ModelStreamingMode.Default машину клиенту
	-- реплицирует ПО ЧАСТЯМ, и скопированный в PlayerGui Drive рвётся на
	-- car.DriveSeat/car.Wheels («not a valid member») → движок не заводится, машина
	-- не едет. Держим машину ЦЕЛИКОМ у всех клиентов (Persistent + persistent-игроки),
	-- чтобы AC6 всегда видел все детали сразу. (Машин мало — стриминг тут не нужен.)
	car.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	car.Parent = workspace
	for _, p in Players:GetPlayers() do
		pcall(function()
			car:AddPersistentPlayer(p)
		end)
	end
	CollectionService:AddTag(car, "PlayerVehicle") -- VehicleController подхватит
	vehicleOfPlayer[player] = car
	return car
end

function PlayerFlow.getVehicle(player: Player): Model?
	local car = vehicleOfPlayer[player]
	return (car and car.Parent) and car or nil
end

-- Посадить владельца за руль его машины (персонаж стоит у старта — телепортим).
function PlayerFlow.seatDriver(player: Player)
	local car = PlayerFlow.getVehicle(player)
	local seat = car and car:FindFirstChild("DriveSeat")
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (car and seat and seat:IsA("VehicleSeat") and char and hum and hum.Health > 0) then
		return
	end
	unfreeze(hum :: Humanoid); -- разморозить перед посадкой
	(seat :: VehicleSeat).Disabled = false
	-- Надёжная посадка: под StreamingEnabled одиночный Sit сразу после спавна (машина
	-- ещё оседает на террейн) часто НЕ регистрирует Occupant на сервере — а пока
	-- Occupant нет, сервер не отдаёт клиенту сетевое владение, и клиентский движок
	-- AC6 не может двигать машину («не едет»). Повторяем Sit, пока не сядет, затем
	-- ЯВНО отдаём владение водителю (не ждём хендлера SeatWeld в A-Chassis Initialize).
	local seated = false
	for _ = 1, 14 do
		if (seat :: VehicleSeat).Occupant == hum then
			seated = true
			break
		end
		(char :: Model):PivotTo((seat :: VehicleSeat).CFrame * CFrame.new(0, 3.5, 0))
		task.wait()
		pcall(function()
			(seat :: VehicleSeat):Sit(hum :: Humanoid)
		end)
		task.wait(0.1)
	end
	if seated then
		-- Отдаём владение водителю И ПРОВЕРЯЕМ, что прижилось. На 2-й+ машине в
		-- мультиплеере одиночный SetNetworkOwner иногда не срабатывает (ассамблея
		-- ещё оседает / владение перехватывает автопил) → «стреляет, но не едет»:
		-- турель на ремоутах и от владения не зависит, а физику AC6 двигает ТОЛЬКО
		-- владелец-клиент. Ретраим, пока GetNetworkOwner не станет игроком.
		local owner: Player? = nil
		for _ = 1, 12 do
			pcall(function()
				(seat :: VehicleSeat):SetNetworkOwner(player)
			end)
			task.wait(0.1)
			pcall(function()
				owner = (seat :: VehicleSeat):GetNetworkOwner()
			end)
			if owner == player then
				break
			end
		end
	end
end

function PlayerFlow.unseat(player: Player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Sit then
		hum.Sit = false
	end
	local car = PlayerFlow.getVehicle(player)
	local seat = car and car:FindFirstChild("DriveSeat")
	if seat and seat:IsA("VehicleSeat") then
		seat.Disabled = true -- обратно не сесть
	end
end

function PlayerFlow.releaseVehicle(player: Player)
	local car = vehicleOfPlayer[player]
	vehicleOfPlayer[player] = nil
	VehicleRegistry.ClearPlayer(player)
	if car and car.Parent then
		car:Destroy() -- ← чинит накопление машин
	end
	-- Гасим клиентский интерфейс AC6. Без машины его Drive/Burnout/Smoke (все живут
	-- ВНУТРИ "A-Chassis Interface" в PlayerGui) продолжают крутиться на уничтоженной
	-- модели и спамят «DriveSeat/Wheels not a valid member». Свежий интерфейс
	-- копируется заново при следующей посадке (Initialize на SeatWeld).
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if pg then
		for _, iface in pg:GetChildren() do
			if iface.Name == "A-Chassis Interface" then
				iface:Destroy()
			end
		end
	end
end

-- Все выданные машины (для occupiedSeats MatchManager-а)
function PlayerFlow.vehicles(): { [Player]: Model }
	return vehicleOfPlayer
end

-- // Хуки ---------------------------------------------------------------------
local function onCharacterAdded(player: Player)
	task.wait(0.2) -- дать персонажу собраться
	local car = PlayerFlow.getVehicle(player)
	if car and not car:GetAttribute("Eliminated") then
		-- гонщик погиб посреди заезда → назад за руль, гонка продолжается
		PlayerFlow.seatDriver(player)
	else
		PlayerFlow.sendToLobby(player) -- к старту + заморозка
	end
end

local initialized = false
function PlayerFlow.init()
	if initialized then
		return
	end
	initialized = true

	captureGridBase()
	ensureTemplate()

	-- грид и точка старта — на старте новой трассы (из MapLayout, форма Road.svg).
	-- Высоту берём РЕЙКАСТОМ по фактической поверхности дороги (террейн рендерится
	-- выше номинального top), иначе колёса уходят в грунт → машину ломает на спавне.
	local sg = MapLayout.Landmarks.StartGate
	local sd = MapLayout.StartDir
	if sg and sd and (Vector2.new(sd.X, sd.Y).Magnitude > 1e-3) then
		local top = GameConfig.Map.GroundTop or 2
		local sx, sz = sg.Position.X * MapLayout.Scale, sg.Position.Y * MapLayout.Scale
		local dir = Vector3.new(sd.X, 0, sd.Y).Unit

		-- Место игрока под заставкой — ПОЗАДИ всей колонны (иначе машина заднего
		-- ряда спавнится прямо в стоящего игрока) и тоже по осевой, не по прямой.
		local function lobbyCF(y: number): CFrame
			local depth = gridDepthStuds > 0 and gridDepthStuds or (GRID_ROWS - 1) * GRID_ROW_GAP
			local p = trackPointBehind(depth + 22)
			if p then
				return CFrame.new(Vector3.new(p.X, y, p.Y))
			end
			return CFrame.new(Vector3.new(sx, y, sz) - dir * (depth + 22))
		end

		-- дефолт до готовности террейна
		gridBaseSeatCF = CFrame.lookAt(Vector3.new(sx, top + 10, sz), Vector3.new(sx, top + 10, sz) + dir)
		buildGridSlots(top + 10)
		START_CF = lobbyCF(top + 8)
		task.spawn(function()
			local rp = RaycastParams.new()
			rp.FilterType = Enum.RaycastFilterType.Include
			rp.FilterDescendantsInstances = { workspace.Terrain }
			for _ = 1, 80 do
				local r = workspace:Raycast(Vector3.new(sx, 80, sz), Vector3.new(0, -160, 0), rp)
				if r and r.Material == Enum.Material.Ground then
					local sy = r.Position.Y
					gridBaseSeatCF = CFrame.lookAt(Vector3.new(sx, sy + 6, sz), Vector3.new(sx, sy + 6, sz) + dir)
					buildGridSlots(sy + 6) -- полотно плоское → одна высота на всю колонну
					START_CF = lobbyCF(sy + 4)
					return
				end
				task.wait(0.2)
			end
		end)
	else
		local spawn = workspace:FindFirstChildOfClass("SpawnLocation")
		if spawn then
			START_CF = spawn.CFrame + Vector3.new(0, 3, 0)
		end
	end

	local function hook(player: Player)
		player.CharacterAdded:Connect(function()
			onCharacterAdded(player)
		end)
		if player.Character then
			onCharacterAdded(player)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
	Players.PlayerRemoving:Connect(PlayerFlow.releaseVehicle)

	print("[PlayerFlow] Старт у грида, решётка записана, свободные машины убраны (без платформы).")
end

return PlayerFlow
