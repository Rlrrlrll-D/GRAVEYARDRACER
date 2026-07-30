--!strict
-- Script: ServerScriptService.BatManager
-- Атмосфера летучих мышей. Сервер РЕШАЕТ, когда и где, и рассылает команду;
-- рой рисует каждый клиент у себя (BatFX) — дёшево, без репликации.
--   "flyby" — редкий одиночный пролёт (эмбиент, «кладбище живёт»).
--   "swarm" — резкий разлёт стаи в лицо (мини-скример; клиент чтит опцию jumpscares).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local MapLayout = require(ReplicatedStorage:WaitForChild("MapLayout"))
local batScare = Net.get(Net.Events.BatScare)
-- Скример = не только картинка: на рой из-за угла даём короткую тряску камеры.
-- Клиент (UIController) сам чтит опцию cameraShake, здесь фильтровать не нужно.
local cameraShake = Net.get(Net.Events.CameraShake)

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
			batScare:FireAllClients(o[math.random(1, #o)], math.random(24, 32), "swarm")
		end
	end
end)

-- // ЗОНЫ СКРИМЕРОВ (MapLayout.ScareZones) ------------------------------------
-- Зоны посажены на крутые повороты, где обзор закрыт. Въехал в зону — стая
-- срывается ВПЕРЕДИ ПО КУРСУ, то есть прямо в лобовое, «из-за угла». Скример
-- личный: летит FireClient только тому, кто въехал (остальных не дёргаем).
-- Рандом двойной: Chance зоны + кулдауны, чтобы не приедалось и не сыпалось
-- очередью на связке поворотов.
local ZONE_COOLDOWN = 25 -- одна и та же зона не сработает у игрока чаще (круг ≈40с)
local PLAYER_COOLDOWN = 9 -- глобально на игрока: соседние зоны не складываются
local ZONE_AHEAD = 30 -- насколько впереди машины рождается стая
local ZONE_UP = 6

local zones = MapLayout.ScareZones or {}
-- [player] = { [zoneIndex] = время }
local zoneSeen: { [Player]: { [number]: number } } = {}
local lastScare: { [Player]: number } = {}
Players.PlayerRemoving:Connect(function(plr)
	zoneSeen[plr] = nil
	lastScare[plr] = nil
end)

if #zones > 0 then
	task.spawn(function()
		while true do
			task.wait(0.25)
			local now = os.clock()
			for _, v in CollectionService:GetTagged("PlayerVehicle") do
				local seat = v:FindFirstChild("DriveSeat")
				local occ = seat and seat:IsA("BasePart") and (seat :: any).Occupant
				local plr = occ and Players:GetPlayerFromCharacter(occ.Parent)
				if plr and seat and seat:IsA("BasePart") then
					local pos = seat.Position
					local seen = zoneSeen[plr]
					if not seen then
						seen = {}
						zoneSeen[plr] = seen
					end
					if (now - (lastScare[plr] or -math.huge)) >= PLAYER_COOLDOWN then
						for i, z in zones do
							local zx = z.Position.X * MapLayout.Scale
							local zz = z.Position.Y * MapLayout.Scale
							local dx, dz = pos.X - zx, pos.Z - zz
							if dx * dx + dz * dz <= z.Radius * z.Radius then
								-- в зоне: срабатываем один раз на въезд (кулдаун зоны)
								if (now - (seen[i] or -math.huge)) >= ZONE_COOLDOWN then
									seen[i] = now
									if math.random() < (z.Chance or 1) then
										lastScare[plr] = now
										local origin = pos
											+ seat.CFrame.LookVector * ZONE_AHEAD
											+ Vector3.new(0, ZONE_UP, 0)
										local count = z.Kind == "swarm" and math.random(26, 34) or math.random(2, 4)
										batScare:FireClient(plr, origin, count, z.Kind)
										if z.Kind == "swarm" then
											cameraShake:FireClient(plr, 0.55, 0.3)
										end
									end
								end
								break -- зоны не перекрываются; хватит первой
							end
						end
					end
				end
			end
		end
	end)
end

-- внешний триггер (напр. ZombieSpawner при вылезании зомби рядом): взмыть стае
_G.TriggerBatSwarm = function(origin: Vector3, count: number?)
	batScare:FireAllClients(origin, count or 20, "swarm")
end

print(("[BatManager] загружен. Зон скримеров: %d."):format(#zones))
