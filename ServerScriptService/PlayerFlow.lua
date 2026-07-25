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

-- // Стартовая решётка --------------------------------------------------------
-- База — CFrame сиденья преж-установленного багги (записываем при init и УБИРАЕМ
-- машину: свободных машин в мире больше нет, они выдаются на отсчёте).
local FALLBACK_SEAT_CF = CFrame.lookAt(Vector3.new(10.05, 7.21, 5.19), Vector3.new(9.05, 7.21, 5.19))
-- смещения мест 2..8 от сиденья первого места (решётка 2 колонны)
local GRID_OFFSETS = {
	Vector3.new(-10, 0, 0),
	Vector3.new(10, 0, 8),
	Vector3.new(-10, 0, 8),
	Vector3.new(10, 0, 16),
	Vector3.new(-10, 0, 16),
	Vector3.new(10, 0, 24),
	Vector3.new(-10, 0, 24),
}
local gridBaseSeatCF = FALLBACK_SEAT_CF

PlayerFlow.MaxSlots = #GRID_OFFSETS + 1

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

-- CFrame СИДЕНЬЯ для места i (1..MaxSlots)
function PlayerFlow.gridSlot(i: number): CFrame
	if i <= 1 then
		return gridBaseSeatCF
	end
	local off = GRID_OFFSETS[math.clamp(i - 1, 1, #GRID_OFFSETS)]
	return gridBaseSeatCF * CFrame.new(off)
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
		pcall(function()
			(seat :: VehicleSeat):SetNetworkOwner(player) -- клиент рулит физикой сразу
		end)
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
		-- дефолт до готовности террейна
		gridBaseSeatCF = CFrame.lookAt(Vector3.new(sx, top + 10, sz), Vector3.new(sx, top + 10, sz) + dir)
		START_CF = CFrame.new(Vector3.new(sx, top + 8, sz) - dir * 30)
		task.spawn(function()
			local rp = RaycastParams.new()
			rp.FilterType = Enum.RaycastFilterType.Include
			rp.FilterDescendantsInstances = { workspace.Terrain }
			for _ = 1, 80 do
				local r = workspace:Raycast(Vector3.new(sx, 80, sz), Vector3.new(0, -160, 0), rp)
				if r and r.Material == Enum.Material.Ground then
					local sy = r.Position.Y
					gridBaseSeatCF = CFrame.lookAt(Vector3.new(sx, sy + 6, sz), Vector3.new(sx, sy + 6, sz) + dir)
					START_CF = CFrame.new(Vector3.new(sx, sy + 4, sz) - dir * 30)
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
