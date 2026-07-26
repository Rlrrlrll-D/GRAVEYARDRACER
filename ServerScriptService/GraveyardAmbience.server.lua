--!strict
-- Script: ServerScriptService.GraveyardAmbience
-- Зацикленный фоновый звук (ветер/сверчки/совы) + случайные вспышки "молнии"
-- с приглушённым громом.
--
-- ВАЖНО: замените SoundId у AmbientLoop и ThunderSound на реальные ID
-- из Creator Store (Toolbox → Audio). Как и с двигателем машины, чужие
-- старые ID часто дают "Asset is not approved for the requester" —
-- надёжнее всего использовать звук из СВОЕЙ библиотеки или из
-- каталога с явным разрешением на использование.

local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnvironmentConfig = require(ReplicatedStorage:WaitForChild("EnvironmentConfig"))
local thunderCfg = EnvironmentConfig.Thunder

-- // Фоновый зацикленный звук (ветер/сверчки) ------------------------------
local ambientLoop = Instance.new("Sound")
ambientLoop.Name = "AmbientLoop"
ambientLoop.SoundId = "rbxassetid://9112764040" -- Crickets Canyon, ночные сверчки с ветерком (Pro Sound Effects, Creator Store)
ambientLoop.Looped = true
ambientLoop.Volume = 0.4
ambientLoop.Parent = SoundService
ambientLoop:Play()

-- // Звук грома (проигрывается вместе со вспышкой) -------------------------
local thunderSound = Instance.new("Sound")
thunderSound.Name = "ThunderSound"
thunderSound.SoundId = "rbxassetid://4961240438" -- Thunder Rumble, близкий раскат (Creator Store)
thunderSound.Volume = 0.5
thunderSound.Parent = SoundService

-- Вспышку рисует КЛИЕНТ (DayNightCycle), сервер только объявляет момент.
-- Раньше сервер писал Lighting.Brightness напрямую — и затирал сумерки: он читал
-- СВОЮ яркость (всегда ночную, переход-то клиентский), умножал её и возвращал
-- ночное значение обратно, а это реплицировалось всем. Итог: первая же молния
-- гасила сумерки в ночь. Метка — тот же приём, что NightAnchor.
local flashSignal = ReplicatedStorage:FindFirstChild("ThunderFlash")
if not flashSignal then
	flashSignal = Instance.new("NumberValue")
	flashSignal.Name = "ThunderFlash"
	flashSignal.Parent = ReplicatedStorage
end

local function lightningFlash()
	local signal = flashSignal :: NumberValue
	signal.Value = workspace:GetServerTimeNow()
	thunderSound:Play()
end

task.spawn(function()
	while true do
		task.wait(math.random(thunderCfg.MinInterval, thunderCfg.MaxInterval))
		lightningFlash()
	end
end)

-- // Случайные криповые звуки (крики, скрипы, вороны, вой) ------------------
-- Одиночные выстрелы атмосферы в духе Тима Бёртона: далёкий крик, скрип
-- дерева, карканье, вой. Интервал и высота тона слегка случайные, чтобы
-- звуки не приедались. Все ID — бесплатные из Creator Store (Pro Sound Effects).
local SPOOKY = {
	{ id = 9125905538,     volume = 0.22 }, -- далёкий крик (пробегающий)
	{ id = 78855069358386, volume = 0.18 }, -- крик в лесу
	{ id = 9120839010,     volume = 0.35 }, -- скрип дерева, короткий
	{ id = 9120838740,     volume = 0.30 }, -- скрип дерева, протяжный
	{ id = 9118066001,     volume = 0.45 }, -- ворон
	{ id = 9118067220,     volume = 0.45 }, -- ворон, короткое карканье
	{ id = 9113952977,     volume = 0.25 }, -- далёкий вой
	{ id = 9120051478,     volume = 0.20 }, -- стая вдалеке
}

local spookySounds: {Sound} = {}
for i, entry in SPOOKY do
	local s = Instance.new("Sound")
	s.Name = "Spooky" .. i
	s.SoundId = `rbxassetid://{entry.id}`
	s.Volume = entry.volume
	s.Parent = SoundService
	table.insert(spookySounds, s)
end

task.spawn(function()
	local lastIndex = 0
	while true do
		task.wait(math.random(12, 30)) -- чаще: крип-звуки заметнее
		local index = math.random(#spookySounds)
		if index == lastIndex then
			index = index % #spookySounds + 1 -- не повторять один звук дважды подряд
		end
		lastIndex = index
		local s = spookySounds[index]
		s.PlaybackSpeed = 0.9 + math.random() * 0.2
		s:Play()
	end
end)
