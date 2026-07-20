--!strict
-- Script: ServerScriptService.BatManager
-- Атмосфера летучих мышей. Сервер РЕШАЕТ, когда и где, и рассылает команду;
-- рой рисует каждый клиент у себя (BatFX) — дёшево, без репликации.
--   "flyby" — редкий одиночный пролёт (эмбиент, «кладбище живёт»).
--   "swarm" — резкий разлёт стаи в лицо (мини-скример; клиент чтит опцию jumpscares).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local batScare = Net.get(Net.Events.BatScare)

-- точки вылета: впереди по курсу каждого едущего игрока, чуть выше
local function driverOrigins(): { Vector3 }
	local pts: { Vector3 } = {}
	for _, v in CollectionService:GetTagged("PlayerVehicle") do
		local seat = v:FindFirstChild("DriveSeat")
		if seat and seat:IsA("BasePart") and seat.Occupant then
			table.insert(pts, seat.Position + seat.CFrame.LookVector * 35 + Vector3.new(0, 7, 0))
		end
	end
	return pts
end

-- эмбиент: одиночный пролёт, часто и ненавязчиво
task.spawn(function()
	while true do
		task.wait(math.random(7, 15))
		local o = driverOrigins()
		if #o > 0 then
			batScare:FireAllClients(o[math.random(1, #o)], math.random(1, 2), "flyby")
		end
	end
end)

-- скример-рой: редко, только когда есть кого пугать
task.spawn(function()
	while true do
		task.wait(math.random(40, 75))
		local o = driverOrigins()
		if #o > 0 and math.random() < 0.6 then
			batScare:FireAllClients(o[math.random(1, #o)], math.random(16, 24), "swarm")
		end
	end
end)

-- внешний триггер (напр. ZombieSpawner при вылезании зомби рядом): взмыть стае
_G.TriggerBatSwarm = function(origin: Vector3, count: number?)
	batScare:FireAllClients(origin, count or 20, "swarm")
end

print("[BatManager] загружен.")
