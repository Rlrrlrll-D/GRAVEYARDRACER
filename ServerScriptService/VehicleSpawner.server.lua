--!strict
-- Script: ServerScriptService.VehicleSpawner
-- Каждому игроку — своя машина. По мере входа игроков клонирует
-- ServerStorage.VehicleTemplate (нетронутая копия GraveyardBuggy) на
-- стартовую решётку за воротами и вешает тег PlayerVehicle — дальше
-- VehicleController/RaceManager подхватывают её автоматически.
-- Первая машина уже стоит в Workspace и считается местом №1.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local template = ServerStorage:WaitForChild("VehicleTemplate") :: Model
local templateSeat = template:FindFirstChild("DriveSeat") :: VehicleSeat
-- связь пивот<->сиденье: пивот у багги наклонён (Wedge), поэтому ставим
-- клоны по CFrame сиденья, а не по пивоту
local pivotFromSeat = templateSeat.CFrame:Inverse() * template:GetPivot()

-- смещения мест 2..N от сиденья первой машины (решётка 2 колонны)
local GRID = {
	Vector3.new(-10, 0, 0),
	Vector3.new(10, 0, 8),
	Vector3.new(-10, 0, 8),
	Vector3.new(10, 0, 16),
	Vector3.new(-10, 0, 16),
	Vector3.new(10, 0, 24),
	Vector3.new(-10, 0, 24),
}

local function firstVehicleSeat(): VehicleSeat?
	for _, v in CollectionService:GetTagged("PlayerVehicle") do
		if v:IsA("Model") then
			local seat = v:FindFirstChild("DriveSeat")
			if seat and seat:IsA("VehicleSeat") then
				return seat
			end
		end
	end
	return nil
end

local function ensureVehicles()
	local have = #CollectionService:GetTagged("PlayerVehicle")
	local need = math.min(#Players:GetPlayers(), #GRID + 1)
	local baseSeat = firstVehicleSeat()
	if not baseSeat then
		warn("[VehicleSpawner] Нет ни одной машины с тегом PlayerVehicle — решётку строить не от чего.")
		return
	end
	while have < need do
		local offset = GRID[have] -- have=1 -> место для второй машины
		local car = template:Clone()
		car.Name = "GraveyardBuggy" .. (have + 1)
		local seatCF = baseSeat.CFrame * CFrame.new(offset)
		car:PivotTo(seatCF * pivotFromSeat)
		car.Parent = workspace
		CollectionService:AddTag(car, "PlayerVehicle")
		have += 1
		print(`[VehicleSpawner] Машина №{have} выставлена на решётку.`)
	end
end

Players.PlayerAdded:Connect(function()
	task.wait(1) -- даём Bootstrap/VehicleController подняться
	ensureVehicles()
end)
ensureVehicles()
