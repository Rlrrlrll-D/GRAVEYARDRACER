--!strict
-- ModuleScript: ServerScriptService.PlayerFlow
-- Жизненный цикл игрока в сессионной модели (веха 4 плана V2): спавн ВСЕГДА в
-- лобби, выдача/уборка машины с владельцем (OwnerUserId), возврат в лобби между
-- заездами. Чинит старый баг накопления клонов багги: машина игрока
-- уничтожается на PlayerRemoving и при эвикте.
--
-- Лобби — платформа-обзор высоко над кладбищем (строится здесь кодом, имя
-- платформы = GameState.LobbyZoneName). Зомби не достают: они спавнятся только
-- у занятых машин внизу. Оформление площадки — позже.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameState = require(ReplicatedStorage:WaitForChild("GameState"))
local VehicleRegistry = require(ReplicatedStorage:WaitForChild("VehicleRegistry"))

local PlayerFlow = {}

local vehicleOfPlayer: { [Player]: Model } = {}

-- // Лобби-платформа ----------------------------------------------------------
local LOBBY_CENTER = Vector3.new(28, 150, 28) -- высоко над стартом: вид на трассу
local PLATFORM_SIZE = Vector3.new(56, 3, 56)
local WALL_HEIGHT = 24

local lobbyPlatform: BasePart? = nil

local function buildLobbyZone()
	local existing = workspace:FindFirstChild(GameState.LobbyZoneName)
	if existing and existing:IsA("BasePart") then
		lobbyPlatform = existing
		return
	end

	local rig = Instance.new("Model")
	rig.Name = "Lobby"

	local platform = Instance.new("Part")
	platform.Name = GameState.LobbyZoneName
	platform.Size = PLATFORM_SIZE
	platform.Position = LOBBY_CENTER
	platform.Anchored = true
	platform.Material = Enum.Material.Slate
	platform.Color = Color3.fromRGB(44, 50, 46) -- тёмный замшелый камень
	platform.Parent = rig

	-- невидимые стены по периметру: с площадки не упасть
	for _, spec in {
		{ off = Vector3.new(0, 0, -PLATFORM_SIZE.Z / 2), size = Vector3.new(PLATFORM_SIZE.X, WALL_HEIGHT, 1) },
		{ off = Vector3.new(0, 0, PLATFORM_SIZE.Z / 2), size = Vector3.new(PLATFORM_SIZE.X, WALL_HEIGHT, 1) },
		{ off = Vector3.new(-PLATFORM_SIZE.X / 2, 0, 0), size = Vector3.new(1, WALL_HEIGHT, PLATFORM_SIZE.Z) },
		{ off = Vector3.new(PLATFORM_SIZE.X / 2, 0, 0), size = Vector3.new(1, WALL_HEIGHT, PLATFORM_SIZE.Z) },
	} do
		local wall = Instance.new("Part")
		wall.Name = "LobbyWall"
		wall.Size = spec.size
		wall.Position = LOBBY_CENTER + spec.off + Vector3.new(0, WALL_HEIGHT / 2 + PLATFORM_SIZE.Y / 2, 0)
		wall.Anchored = true
		wall.Transparency = 1
		wall.CanQuery = false
		wall.Parent = rig
	end

	-- родной спавн Roblox на платформе; старые точки в мире выключаем
	local pad = Instance.new("SpawnLocation")
	pad.Name = "LobbySpawn"
	pad.Size = Vector3.new(12, 1, 12)
	pad.Position = LOBBY_CENTER + Vector3.new(0, PLATFORM_SIZE.Y / 2 + 0.5, 0)
	pad.Anchored = true
	pad.Neutral = true
	pad.Duration = 0 -- без форс-филда
	pad.Transparency = 1
	pad.Enabled = true
	pad.Parent = rig

	for _, d in workspace:GetChildren() do
		if d:IsA("SpawnLocation") then
			d.Enabled = false
		end
	end

	rig.Parent = workspace
	lobbyPlatform = platform
end

-- Телепорт персонажа в лобби (между заездами и после game over).
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
	local base = lobbyPlatform and lobbyPlatform.Position or LOBBY_CENTER
	local scatter = Vector3.new(math.random(-12, 12), 0, math.random(-12, 12))
	char:PivotTo(CFrame.new(base + scatter + Vector3.new(0, PLATFORM_SIZE.Y / 2 + 4, 0)))
end

-- // Стартовая решётка --------------------------------------------------------
-- База — CFrame сиденья преж-установленного багги (записываем при init и УБИРАЕМ
-- машину: свободных машин в мире больше нет, они выдаются на отсчёте).
local FALLBACK_SEAT_CF = CFrame.lookAt(Vector3.new(10.05, 7.21, 5.19), Vector3.new(9.05, 7.21, 5.19))
-- смещения мест 2..8 от сиденья первого места (решётка 2 колонны) — как у
-- старого VehicleSpawner
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
	car.Parent = workspace
	CollectionService:AddTag(car, "PlayerVehicle") -- VehicleController подхватит
	vehicleOfPlayer[player] = car
	return car
end

function PlayerFlow.getVehicle(player: Player): Model?
	local car = vehicleOfPlayer[player]
	return (car and car.Parent) and car or nil
end

-- Посадить владельца за руль его машины (персонаж может быть в лобби — телепортим).
function PlayerFlow.seatDriver(player: Player)
	local car = PlayerFlow.getVehicle(player)
	local seat = car and car:FindFirstChild("DriveSeat")
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (car and seat and seat:IsA("VehicleSeat") and char and hum and hum.Health > 0) then
		return
	end
	(seat :: VehicleSeat).Disabled = false;
	(char :: Model):PivotTo((seat :: VehicleSeat).CFrame * CFrame.new(0, 5, 0))
	task.wait()
	pcall(function()
		(seat :: VehicleSeat):Sit(hum :: Humanoid)
	end)
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
		PlayerFlow.sendToLobby(player)
	end
end

local initialized = false
function PlayerFlow.init()
	if initialized then
		return
	end
	initialized = true

	buildLobbyZone()
	captureGridBase()
	ensureTemplate()

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

	print("[PlayerFlow] Лобби построено, решётка записана, свободные машины убраны.")
end

return PlayerFlow
