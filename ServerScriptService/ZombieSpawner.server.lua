--!strict
-- Script: ServerScriptService.ZombieSpawner
-- Clones a zombie rig from ServerStorage.ZombieTemplate at grave locations
-- and animates it climbing out of the ground.
--
-- SETUP: place a Model named "ZombieTemplate" in ServerStorage containing:
--   - a Humanoid
--   - a HumanoidRootPart
--   - (optional) an Animation child named "AttackAnimation"
-- An R15 dummy or the Toolbox "Zombie" rig both work fine.
--
-- SETUP: tag every grave/tombstone spot with CollectionService tag "Grave".
-- This can be the tombstone Part itself, or a small invisible Part placed
-- at ground level next to it — either works, since only its Position is used.

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local ZombieAI = require(script.Parent:WaitForChild("ZombieAI"))

local template = ServerStorage:WaitForChild("ZombieTemplate") :: Model

-- // Лидерборд: убитые зомби (leaderstats.Zombies в списке игроков) ------------
local function setupLeaderstats(player: Player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local zombies = Instance.new("IntValue")
	zombies.Name = "Zombies"
	zombies.Value = (player:GetAttribute("ZombiesDefeated") :: number?) or 0
	zombies.Parent = ls
	ls.Parent = player
	-- держим в синхроне со счётчиком-атрибутом (его растит onZombieDied)
	player:GetAttributeChangedSignal("ZombiesDefeated"):Connect(function()
		zombies.Value = (player:GetAttribute("ZombiesDefeated") :: number?) or 0
	end)
end
for _, p in Players:GetPlayers() do
	setupLeaderstats(p)
end
Players.PlayerAdded:Connect(setupLeaderstats)

local RISE_DURATION = 1.2   -- seconds to climb out of the ground
local BURY_DEPTH = 4        -- studs below the final resting position to start from

local function getGravePart(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	elseif instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
	end
	return nil
end

-- Picks a grave within SpawnRadius of an occupied vehicle. Returns nil when
-- nobody is driving near any grave — zombies emerge only as players approach,
-- not on a global timer.
local function pickGrave(): BasePart?
	local graveTags = CollectionService:GetTagged("Grave")
	local graves: {BasePart} = {}
	for _, instance in graveTags do
		local part = getGravePart(instance)
		if part then
			table.insert(graves, part)
		end
	end
	if #graves == 0 then return nil end

	local occupiedSeats: {BasePart} = {}
	for _, vehicle in CollectionService:GetTagged("PlayerVehicle") do
		local seat = vehicle:FindFirstChild("DriveSeat")
		if seat and seat:IsA("BasePart") and seat.Occupant then
			table.insert(occupiedSeats, seat)
		end
	end

	if #occupiedSeats == 0 then
		return nil -- nobody is driving, keep the graveyard quiet
	end

	local nearGraves: {BasePart} = {}
	for _, grave in graves do
		for _, seat in occupiedSeats do
			if (grave.Position - seat.Position).Magnitude <= GameConfig.Zombie.SpawnRadius then
				table.insert(nearGraves, grave)
				break
			end
		end
	end
	if #nearGraves == 0 then
		return nil -- no driver close enough to any grave yet
	end
	return nearGraves[math.random(1, #nearGraves)]
end

-- Freezes the zombie underground, then eases it up to its final CFrame.
-- Runs synchronously within the caller's task so ZombieAI only starts once
-- the zombie has fully emerged.
local function riseFromGrave(zombie: Model, finalCFrame: CFrame)
	local buriedCFrame = finalCFrame * CFrame.new(0, -BURY_DEPTH, 0)
	zombie:PivotTo(buriedCFrame)

	local parts: {BasePart} = {}
	for _, descendant in zombie:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
			descendant.Anchored = true
		end
	end

	local humanoid = zombie:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = true
	end

	local startTime = os.clock()
	while os.clock() - startTime < RISE_DURATION do
		local alpha = math.clamp((os.clock() - startTime) / RISE_DURATION, 0, 1)
		local eased = alpha * alpha * (3 - 2 * alpha) -- smoothstep easing
		zombie:PivotTo(buriedCFrame:Lerp(finalCFrame, eased))
		task.wait()
	end
	zombie:PivotTo(finalCFrame)

	for _, part in parts do
		part.Anchored = false
	end
	if humanoid then
		humanoid.PlatformStand = false
	end
end

local function onZombieDied(zombie: Model, humanoid: Humanoid)
	humanoid.Died:Wait()

	local killerId = zombie:GetAttribute("KilledBy")
	if killerId then
		local killer = Players:GetPlayerByUserId(killerId :: number)
		if killer then
			local defeated = (killer:GetAttribute("ZombiesDefeated") :: number?) or 0
			killer:SetAttribute("ZombiesDefeated", defeated + 1)
		end
	end

	CollectionService:RemoveTag(zombie, "Zombie")
	Debris:AddItem(zombie, 3) -- leave the body briefly, then clean up
end

local function spawnZombie()
	local grave = pickGrave()
	if not grave then
		return -- silent: either no "Grave" tags or no driver near any grave
	end

	local zombie = template:Clone()

	for _, part in zombie:GetDescendants() do
		if part:IsA("BasePart") then
			PhysicsService:SetPartCollisionGroup(part, "Zombies")
		end
	end

	-- Rest the zombie's feet exactly on top of the grave point.
	local _, size = zombie:GetBoundingBox()
	local finalCFrame = CFrame.new(grave.Position + Vector3.new(0, size.Y / 2, 0))

	-- Bury BEFORE parenting: otherwise the clone flashes for a frame at the
	-- template's stored ServerStorage CFrame before the rise task teleports it.
	zombie:PivotTo(finalCFrame * CFrame.new(0, -BURY_DEPTH, 0))
	zombie.Parent = workspace
	CollectionService:AddTag(zombie, "Zombie")

	local humanoid = zombie:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.MaxHealth = GameConfig.Zombie.MaxHealth
	humanoid.Health = GameConfig.Zombie.MaxHealth

	task.spawn(function()
		riseFromGrave(zombie, finalCFrame)
		task.spawn(ZombieAI.Run, zombie)
	end)
	task.spawn(onZombieDied, zombie, humanoid)
end

task.spawn(function()
	while true do
		task.wait(GameConfig.Zombie.SpawnInterval)
		if #CollectionService:GetTagged("Zombie") < GameConfig.Zombie.MaxZombies then
			spawnZombie()
		end
	end
end)
