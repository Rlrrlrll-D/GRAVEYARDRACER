--!strict
-- Script: ServerScriptService.WeaponServer
-- Authoritative hit detection for the vehicle-mounted turret. The client
-- only sends an aim direction; this script raycasts and applies damage,
-- then broadcasts the result so every client can draw a tracer.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local VehicleRegistry = require(ReplicatedStorage:WaitForChild("VehicleRegistry"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local fireWeapon = remotes:WaitForChild("FireWeapon") :: RemoteEvent
local bulletFired = remotes:WaitForChild("BulletFired") :: RemoteEvent

local lastFireTime: {[Player]: number} = {}
local MIN_FIRE_INTERVAL = 1 / GameConfig.Weapon.FireRate

fireWeapon.OnServerEvent:Connect(function(player: Player, origin: unknown, direction: unknown)
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then return end
	if (direction :: Vector3).Magnitude < 0.001 then return end

	local now = os.clock()
	if lastFireTime[player] and now - lastFireTime[player] < MIN_FIRE_INTERVAL then
		return -- rate limited, ignore
	end
	lastFireTime[player] = now

	local vehicle = VehicleRegistry.GetVehicleForPlayer(player)
	if not vehicle then return end

	local originVec = origin :: Vector3
	local directionVec = (direction :: Vector3).Unit

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { vehicle }

	local result = workspace:Raycast(originVec, directionVec * GameConfig.Weapon.Range, raycastParams)
	local hitPosition = originVec + directionVec * GameConfig.Weapon.Range

	if result then
		hitPosition = result.Position
		local zombieModel = result.Instance:FindFirstAncestorOfClass("Model")

		if zombieModel and CollectionService:HasTag(zombieModel, "Zombie") then
			local humanoid = zombieModel:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				zombieModel:SetAttribute("KilledBy", player.UserId)
				-- Куда опрокинуть тело, если этот выстрел окажется смертельным:
				-- пуля толкает зомби ОТ стрелка (ZombieAI.PlayDeath читает атрибут).
				zombieModel:SetAttribute("DeathPush", Vector3.new(directionVec.X, 0, directionVec.Z))
				humanoid:TakeDamage(GameConfig.Weapon.Damage)
			end
		end
	end

	-- стреляющему эффекты уже показаны локально (предсказание) —
	-- транслируем ОСТАЛЬНЫМ, чтоб у него не было двойного/запоздалого трассера
	for _, other in Players:GetPlayers() do
		if other ~= player then
			bulletFired:FireClient(other, originVec, hitPosition)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastFireTime[player] = nil
end)
