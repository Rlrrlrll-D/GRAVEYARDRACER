--!strict
-- Script: ServerScriptService.FlickerLight
-- Заставляет мерцать любой PointLight/SpotLight/SurfaceLight, помеченный
-- тегом CollectionService "FlickerLight" — удобно для фонарей на кладбище.
--
-- SETUP: выделите лампочку/фонарь (сам источник света, объект типа
-- PointLight и т.п.) → Model tab → Tag Editor → добавьте тег "FlickerLight".

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnvironmentConfig = require(ReplicatedStorage:WaitForChild("EnvironmentConfig"))
local cfg = EnvironmentConfig.Flicker

local function isLight(instance: Instance): boolean
	return instance:IsA("PointLight") or instance:IsA("SpotLight") or instance:IsA("SurfaceLight")
end

local function startFlicker(light: Instance)
	if not isLight(light) then return end
	local lightObj = light :: PointLight

	task.spawn(function()
		while light.Parent do
			lightObj.Brightness = cfg.MinBrightness + math.random() * (cfg.MaxBrightness - cfg.MinBrightness)
			task.wait(cfg.MinIntervalSeconds + math.random() * (cfg.MaxIntervalSeconds - cfg.MinIntervalSeconds))
		end
	end)
end

for _, light in CollectionService:GetTagged("FlickerLight") do
	startFlicker(light)
end

CollectionService:GetInstanceAddedSignal("FlickerLight"):Connect(startFlicker)
