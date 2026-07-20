--!strict
-- Script: ServerScriptService.HazardManager
-- SETUP: tag every tombstone / dead tree Part or Model in the graveyard with
-- the CollectionService tag "Hazard"
-- (Studio: select it > Model tab > Tag Editor > add "Hazard").
-- Hazards can optionally override the defaults with Attributes:
--   SpeedPenalty (number, 0-1) and Damage (number).

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local VehicleRegistry = require(ReplicatedStorage:WaitForChild("VehicleRegistry"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local cameraShake = remotes:WaitForChild("CameraShake") :: RemoteEvent

local lastHitAt: {[Model]: number} = {}

local function setupHazardPart(part: BasePart, hazardOwner: Instance)
	PhysicsService:SetPartCollisionGroup(part, "Obstacles")

	part.Touched:Connect(function(hit: BasePart)
		local vehicle = hit:FindFirstAncestorOfClass("Model")
		if not vehicle or not CollectionService:HasTag(vehicle, "PlayerVehicle") then
			return
		end
		if vehicle:GetAttribute("Destroyed") or vehicle:GetAttribute("Invulnerable") then return end

		local now = os.clock()
		if lastHitAt[vehicle] and now - lastHitAt[vehicle] < 1 then
			return
		end
		lastHitAt[vehicle] = now

		local speedPenalty = (hazardOwner:GetAttribute("SpeedPenalty") :: number?) or GameConfig.Hazard.SpeedPenaltyMultiplier
		local damage = (hazardOwner:GetAttribute("Damage") :: number?) or GameConfig.Hazard.Damage

		vehicle:SetAttribute("SpeedMultiplier", speedPenalty)
		task.delay(1.5, function()
			if vehicle.Parent then
				vehicle:SetAttribute("SpeedMultiplier", 1)
			end
		end)

		local health = (vehicle:GetAttribute("Health") :: number?) or GameConfig.Vehicle.MaxHealth
		health = math.max(0, health - damage)
		vehicle:SetAttribute("Health", health)
		if health <= 0 then
			vehicle:SetAttribute("Destroyed", true)
		end

		local driver = VehicleRegistry.GetPlayerForVehicle(vehicle)
		if driver then
			cameraShake:FireClient(driver, GameConfig.Hazard.ShakeIntensity, GameConfig.Hazard.ShakeDuration)
		end
	end)
end

local function setupHazard(instance: Instance)
	if instance:IsA("BasePart") then
		setupHazardPart(instance, instance)
	elseif instance:IsA("Model") then
		for _, part in instance:GetDescendants() do
			if part:IsA("BasePart") then
				setupHazardPart(part, instance)
			end
		end
	end
end

for _, hazard in CollectionService:GetTagged("Hazard") do
	setupHazard(hazard)
end

CollectionService:GetInstanceAddedSignal("Hazard"):Connect(setupHazard)
