--!strict
-- LocalScript: StarterPlayerScripts.EngineSoundCleanup
-- A-Chassis создаёт звуки двигателя (Rev, Start1...) локально в DriveSeat.
-- При сгорании машины сервер высаживает водителя, но локальные звуки
-- никто не глушит — мотор "играет" у сгоревшей машины. Глушим их сами,
-- когда у машины с тегом PlayerVehicle атрибут Destroyed становится true.

local CollectionService = game:GetService("CollectionService")

local function silence(vehicle: Instance)
	for _, d in vehicle:GetDescendants() do
		if d:IsA("Sound") and d.IsPlaying then
			d:Stop()
		end
	end
end

local function watch(vehicle: Instance)
	vehicle:GetAttributeChangedSignal("Destroyed"):Connect(function()
		if vehicle:GetAttribute("Destroyed") == true then
			silence(vehicle)
		end
	end)
end

for _, v in CollectionService:GetTagged("PlayerVehicle") do
	watch(v)
end
CollectionService:GetInstanceAddedSignal("PlayerVehicle"):Connect(watch)
