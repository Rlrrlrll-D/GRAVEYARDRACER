--!strict
-- ModuleScript: ReplicatedStorage.VehicleRegistry
-- Tracks which Player is currently driving which vehicle Model.
-- Shared by every server script so they don't need to search the whole
-- Workspace or duplicate driver-tracking logic.

local VehicleRegistry = {}

local playerToVehicle: {[Player]: Model} = {}
local vehicleToPlayer: {[Model]: Player} = {}

function VehicleRegistry.SetDriver(vehicle: Model, player: Player?)
	local previousPlayer = vehicleToPlayer[vehicle]
	if previousPlayer then
		playerToVehicle[previousPlayer] = nil
		vehicleToPlayer[vehicle] = nil
	end

	if player then
		local previousVehicle = playerToVehicle[player]
		if previousVehicle then
			vehicleToPlayer[previousVehicle] = nil
		end
		playerToVehicle[player] = vehicle
		vehicleToPlayer[vehicle] = player
	end
end

function VehicleRegistry.GetVehicleForPlayer(player: Player): Model?
	return playerToVehicle[player]
end

function VehicleRegistry.GetPlayerForVehicle(vehicle: Model): Player?
	return vehicleToPlayer[vehicle]
end

function VehicleRegistry.ClearPlayer(player: Player)
	local vehicle = playerToVehicle[player]
	if vehicle then
		vehicleToPlayer[vehicle] = nil
	end
	playerToVehicle[player] = nil
end

return VehicleRegistry
