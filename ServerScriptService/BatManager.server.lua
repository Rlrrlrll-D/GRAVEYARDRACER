--!strict
-- Script: ServerScriptService.BatManager  [СКЕЛЕТ — ещё не подключён к Studio]
-- Атмосфера летучих мышей. Сервер только РЕШАЕТ, когда и где, и рассылает
-- команду; сам рой рисует каждый клиент у себя (BatFX) — дёшево, без репликации
-- десятков движущихся моделей.
--
-- Два режима:
--   "flyby" — нет-нет да пролетит одна-две мыши мимо (лёгкий эмбиент во время
--             гонки, чтобы кладбище «жило»).
--   "swarm" — внезапный резкий разлёт стаи прямо в лицо (мини-скример).
--             Реже, драматичнее; уважает опцию jumpscares у игрока (клиент решит).

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local batScare = Net.get(Net.Events.BatScare)

-- точки, откуда эффектно взмывать стае: деревья/мавзолей/часовня (пугающие места)
local function scaryOrigins(): { Vector3 }
	local pts: { Vector3 } = {}
	-- TODO: собрать позиции DeadTree/Mausoleum/Chapel из GeneratedMap; пока — заглушка
	for _, v in CollectionService:GetTagged("PlayerVehicle") do
		local seat = v:FindFirstChild("DriveSeat")
		if seat and seat:IsA("BasePart") and seat.Occupant then
			-- впереди по курсу игрока, чуть выше — «вылет из-за поворота»
			table.insert(pts, seat.Position + seat.CFrame.LookVector * 40 + Vector3.new(0, 8, 0))
		end
	end
	return pts
end

-- одиночный пролёт: часто, ненавязчиво
task.spawn(function()
	while true do
		task.wait(math.random(6, 14))
		local origins = scaryOrigins()
		if #origins > 0 then
			local o = origins[math.random(1, #origins)]
			batScare:FireAllClients(o, math.random(1, 2), "flyby")
		end
	end
end)

-- скример-стая: редко, только когда есть кого пугать
task.spawn(function()
	while true do
		task.wait(math.random(35, 70))
		local origins = scaryOrigins()
		if #origins > 0 and math.random() < 0.6 then
			local o = origins[math.random(1, #origins)]
			batScare:FireAllClients(o, math.random(16, 26), "swarm") -- клиент учтёт опцию jumpscares
		end
	end
end)

-- Внешний триггер (например, ZombieSpawner при вылезании зомби рядом): взмыть стае.
_G.TriggerBatSwarm = function(origin: Vector3, count: number?)
	batScare:FireAllClients(origin, count or 20, "swarm")
end

print("[BatManager] СКЕЛЕТ загружен.")
