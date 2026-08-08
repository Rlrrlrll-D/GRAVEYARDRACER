--!strict
-- Script: ServerScriptService.StatsService
-- Single source of truth that pushes HUD updates to each driving player,
-- throttled to 5x/second instead of firing a remote on every attribute change.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local VehicleRegistry = require(ReplicatedStorage:WaitForChild("VehicleRegistry"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local updateStats = remotes:WaitForChild("UpdateStats") :: RemoteEvent

local UPDATE_INTERVAL = 0.2
local accumulated = 0

RunService.Heartbeat:Connect(function(dt: number)
	accumulated += dt
	if accumulated < UPDATE_INTERVAL then return end
	accumulated = 0

	for _, player in Players:GetPlayers() do
		local vehicle = VehicleRegistry.GetVehicleForPlayer(player)
		if vehicle then
			updateStats:FireClient(player, {
				Health = vehicle:GetAttribute("Health") or GameConfig.Vehicle.MaxHealth,
				MaxHealth = vehicle:GetAttribute("MaxHealth") or GameConfig.Vehicle.MaxHealth,
				Speed = vehicle:GetAttribute("Speed") or 0,
				Fuel = vehicle:GetAttribute("Fuel") or GameConfig.Vehicle.MaxFuel,
				Lives = vehicle:GetAttribute("Lives") or GameConfig.Race.Lives,
				-- HUD показывает счёт ЗА ЗАЕЗД (RaceZombies), накопительный
				-- ZombiesDefeated живёт в лидерборде и в значке Hundred Down.
				ZombiesDefeated = player:GetAttribute("RaceZombies") or 0,
				Bones = player:GetAttribute("Bones") or 0,
			})
		end
	end
end)
