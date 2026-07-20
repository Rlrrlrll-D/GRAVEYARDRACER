--!strict
-- Script: ServerScriptService.PlayerFlow  [СКЕЛЕТ — ещё не подключён к Studio]
-- Жизненный цикл игрока в сессионной модели: спавн в ЛОББИ (а не сразу на
-- решётку), выдача/уборка машины, и главное — «эвикт» из мира после game over.
--
-- Чинит попутно текущий баг: VehicleSpawner не удаляет клоны машин при выходе
-- игрока → они копятся. Здесь машина привязывается к игроку и убирается на
-- PlayerRemoving.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameState = require(ReplicatedStorage:WaitForChild("GameState"))
local VehicleRegistry = require(ReplicatedStorage:WaitForChild("VehicleRegistry"))

local PlayerFlow = {}

-- машина, закреплённая за игроком (владение — то, чего сейчас нет)
local vehicleOfPlayer: { [Player]: Model } = {}

-- // Лобби-зона -------------------------------------------------------------
local function lobbyCFrame(): CFrame
	local zone = workspace:FindFirstChild(GameState.LobbyZoneName)
	if zone and zone:IsA("BasePart") then
		return zone.CFrame * CFrame.new(0, 4, 0)
	end
	-- TODO: создать LobbyZone (площадка у ворот/над мавзолеем) в Studio.
	return CFrame.new(28, 6, 28) -- пока — над текущим SpawnLocation
end

-- Телепортнуть персонажа в лобби (используется между заездами и ПОСЛЕ game over).
function PlayerFlow.sendToLobby(player: Player)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Sit then hum.Sit = false end -- выкинуть из машины, если сидит
	task.wait() -- дать сиденью отпустить
	char:PivotTo(lobbyCFrame())
	-- TODO: заморозить управление в лобби (WalkSpeed=0 / ForceField), включить
	-- камеру-облёт трассы. Снять — при выпуске на старт.
end

-- // Выдача машины ----------------------------------------------------------
-- Скелет: клонирует ServerStorage.VehicleTemplate на слот игрока (грид-слот
-- назначает MatchManager перед стартом). Владение фиксируем здесь.
function PlayerFlow.assignVehicle(player: Player, spawnCFrame: CFrame): Model?
	local template = ServerStorage:FindFirstChild("VehicleTemplate")
	if not (template and template:IsA("Model")) then
		warn("[PlayerFlow] Нет VehicleTemplate.")
		return nil
	end
	local car = template:Clone()
	car.Name = "Buggy_" .. player.UserId
	car:PivotTo(spawnCFrame)
	car:SetAttribute("OwnerUserId", player.UserId) -- владение — для WeaponServer/RaceCore
	car.Parent = workspace
	CollectionService:AddTag(car, "PlayerVehicle") -- VehicleController подхватит
	vehicleOfPlayer[player] = car
	return car
end

function PlayerFlow.getVehicle(player: Player): Model?
	return vehicleOfPlayer[player]
end

local function cleanup(player: Player)
	local car = vehicleOfPlayer[player]
	if car then car:Destroy() end -- ← чинит накопление машин
	vehicleOfPlayer[player] = nil
	VehicleRegistry.ClearPlayer(player)
end

-- // Хуки ---------------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		task.wait(0.2)
		PlayerFlow.sendToLobby(player) -- всегда появляемся в лобби, не в мире
	end)
end)
Players.PlayerRemoving:Connect(cleanup)

_G.PlayerFlow = PlayerFlow -- временный мост для MatchManager-скелета (заменить на require)
return PlayerFlow
