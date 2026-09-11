--!strict
-- Script: ServerScriptService.StreamPrefetch
-- ПРОСИМ СТРИМИНГ ЗАГРУЗИТЬ КУСОК ТРАССЫ ЗАРАНЕЕ, ПО ХОДУ ДВИЖЕНИЯ.
--
-- ЖАЛОБА 2026-09-07 (телефон, живой заезд): «перед скримером появилось Gameplay
-- paused, подождите пока загрузится контент».
--
-- Это НЕ скример: мыши прогреваются в лобби (BatFX создаёт пул из 72 штук и зовёт
-- PreloadAsync под заставкой), и к моменту заезда они в кэше. Надпись «Gameplay
-- paused» рисует не наш код, а сам движок: под StreamingEnabled клиент замирает,
-- когда персонаж оказывается там, где геометрия ещё не приехала. На телефоне канал
-- уже, а машина едет быстро — стриминг за ней не поспевает.
--
-- ЧТО ДЕЛАЕМ. Раз в секунду для каждого водителя просим загрузить область ВПЕРЕДИ
-- машины: пока игрок доедет до этого места, куски уже будут у него. Метод серверный
-- (Player:RequestStreamAroundAsync), просит вежливо — движок сам решает, что успеет.
--
-- ЧТО СТОИТ В СВОЙСТВАХ И ПОЧЕМУ ИМЕННО ТАК. Пороги держит Workspace, скриптом они не
-- пишутся и даже не читаются («StreamingIntegrityMode is not a valid member»), правятся
-- только в Properties. Сейчас: StreamingMinRadius 192 (было 128 — зона больше, пауз
-- меньше), StreamingTargetRadius 300, StreamingIntegrityMode **PauseOutsideLoadedArea**.
--
-- MinimumRadiusPause НЕ СТАВИТЬ. Он убирает саму надпись, но вместе с ней и страховку:
-- физика считается там, где геометрия ещё не приехала, и A-Chassis РАЗРЫВАЕТ багги на
-- старте (проверено на телефоне 2026-09-07; в Studio не воспроизводится).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VehicleRegistry = require(ReplicatedStorage:WaitForChild("VehicleRegistry"))
local MapLayout = require(ReplicatedStorage:WaitForChild("MapLayout"))

-- Как далеко вперёд просить. 220 studs — это около четырёх секунд хода на нашей
-- скорости: успевает приехать даже на телефонном канале, но не тянет пол-карты.
local LOOK_AHEAD = 220
-- Чаще секунды звать нельзя: RequestStreamAroundAsync ограничен движком примерно
-- двумя вызовами в секунду на игрока, а лишние он просто отбрасывает.
local PERIOD = 1.0

-- ЗОНЫ СКРИМЕРОВ ГРЕЕМ ОТДЕЛЬНО. Все семь стоят на дальних поворотах и шпильках
-- (координаты около ±250), то есть ровно там, где стриминг и не поспевает: машина
-- влетает в угол карты, а куски ещё едут. Жалоба 2026-09-07 — пауза перед вторым
-- скримером. Поэтому за ZONE_LOOK studs до зоны просим загрузить её заранее.
local ZONE_LOOK = 420
local ZONE_PERIOD = 2.0
local zones: { Vector3 } = {}
for _, z in (MapLayout.ScareZones or {}) do
	table.insert(zones, Vector3.new(z.Position.X, 8, z.Position.Y))
end

local busy: { [Player]: boolean } = {}
local zoneBusy: { [Player]: boolean } = {}

local function prefetch(player: Player)
	if busy[player] then
		return
	end
	local car = VehicleRegistry.GetVehicleForPlayer(player)
	if not car then
		return
	end
	local seat = car:FindFirstChild("DriveSeat")
	if not (seat and seat:IsA("BasePart")) then
		return
	end
	-- Куда смотрит машина, туда и просим. Скорость не берём: на старте она нулевая,
	-- а грузить надо уже тогда — первые секунды заезда самые тяжёлые.
	local ahead = seat.Position + seat.CFrame.LookVector * LOOK_AHEAD
	busy[player] = true
	task.spawn(function()
		pcall(function()
			player:RequestStreamAroundAsync(ahead)
		end)
		busy[player] = false
	end)
end

-- Ближайшая зона ВПЕРЕДИ по ходу: сзади и по бокам греть незачем, туда мы не едем.
local function prefetchZone(player: Player)
	if zoneBusy[player] or #zones == 0 then
		return
	end
	local car = VehicleRegistry.GetVehicleForPlayer(player)
	local seat = car and car:FindFirstChild("DriveSeat")
	if not (seat and seat:IsA("BasePart")) then
		return
	end
	local pos, look = seat.Position, seat.CFrame.LookVector
	local best, bestDist = nil, math.huge
	for _, z in zones do
		local delta = z - pos
		local dist = delta.Magnitude
		if dist < ZONE_LOOK and dist > 40 and delta.Unit:Dot(look) > 0.25 and dist < bestDist then
			best, bestDist = z, dist
		end
	end
	if not best then
		return
	end
	zoneBusy[player] = true
	task.spawn(function()
		pcall(function()
			player:RequestStreamAroundAsync(best)
		end)
		zoneBusy[player] = false
	end)
end

Players.PlayerRemoving:Connect(function(player)
	busy[player] = nil
	zoneBusy[player] = nil
end)

task.spawn(function()
	while true do
		task.wait(ZONE_PERIOD)
		for _, player in Players:GetPlayers() do
			prefetchZone(player)
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(PERIOD)
		for _, player in Players:GetPlayers() do
			prefetch(player)
		end
	end
end)

print(("[StreamPrefetch] загружен: %d studs вперёд раз в %.1f с, плюс зоны скримеров (%d шт.) за %d studs."):format(LOOK_AHEAD, PERIOD, #zones, ZONE_LOOK))
