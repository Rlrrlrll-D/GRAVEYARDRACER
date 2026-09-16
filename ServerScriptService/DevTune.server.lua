--!strict
-- Script: ServerScriptService.DevTune
-- СЕРВЕРНАЯ ПОЛОВИНА ПАНЕЛИ ПОЛИРОВКИ (StarterPlayerScripts.RaceTune, F2): правит
-- GameConfig на живую — плотность и стойкость зомби, число жизней, урон, громкость рыка.
-- ТОЛЬКО STUDIO: в живой игре скрипт выходит первой строкой, ремоута DevTune не
-- существует (как у PhotoModeService / DevGarage), в манифест Net его не класть.
--
-- ПОЧЕМУ ЭТО РАБОТАЕТ. require кэширует модуль на весь сервер: таблица GameConfig у
-- ZombieSpawner, ZombieAI, VehicleController и здесь — ОДНА. Спавнер читает
-- SpawnInterval/MaxZombies на каждом витке, типы — при каждом спавне, VehicleController —
-- Lives на старте заезда и RamDamageToCar при таране. Правка здесь видна им сразу.
-- Что НЕ подхватывается на живую: уже вылезшие зомби (скорость/укус лежат у них в
-- атрибутах, ZombieAI читает их раз при старте цикла) — их сносит кнопка KILL.

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local ZombieAI = require(ServerScriptService:WaitForChild("ZombieAI"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local remote = Instance.new("RemoteEvent")
remote.Name = "DevTune"
remote.Parent = remotes

-- Исходные числа — чтобы «\» возвращал к конфигу, а множители считались от базы.
local Z = GameConfig.Zombie
local baseTiers = {}
for i, t in Z.Tiers do
	baseTiers[i] = table.clone(t)
end
local base = {
	SpawnInterval = Z.SpawnInterval,
	MaxZombies = Z.MaxZombies,
	SpawnRadius = Z.SpawnRadius,
	MaxAttackers = Z.MaxAttackers,
	AttackCooldown = Z.AttackCooldown,
	RamDamageToCar = Z.RamDamageToCar,
	HazardDamage = GameConfig.Hazard.Damage,
	Lives = GameConfig.Race.Lives,
	Laps = GameConfig.Race.Laps,
}
-- множители по типам: применяются ко всем Tiers от базовых копий
local mult = { hp = 1, speed = 1, bite = 1, bones = 1 }

local function applyTiers()
	for i, t in Z.Tiers do
		local b = baseTiers[i]
		t.hp = math.max(1, math.floor(b.hp * mult.hp + 0.5))
		t.walkSpeed = b.walkSpeed * mult.speed
		t.attackDamage = b.attackDamage * mult.bite
		t.bones = math.max(0, math.floor(b.bones * mult.bones + 0.5))
	end
end

local function setLivesOnCars(n: number)
	for _, car in CollectionService:GetTagged("PlayerVehicle") do
		car:SetAttribute("Lives", n)
	end
end

-- key → как применить. value — число (или nil для команд).
local handlers: { [string]: (number) -> () } = {
	spawnInterval = function(v) Z.SpawnInterval = math.max(0.3, v) end,
	maxZombies = function(v) Z.MaxZombies = math.floor(v + 0.5) end,
	spawnRadius = function(v) Z.SpawnRadius = v end,
	maxAttackers = function(v) Z.MaxAttackers = math.max(1, math.floor(v + 0.5)) end,
	attackCooldown = function(v) Z.AttackCooldown = math.max(0.3, v) end,
	ramDamage = function(v) Z.RamDamageToCar = v end,
	hazardDamage = function(v) GameConfig.Hazard.Damage = v end,
	lives = function(v)
		local n = math.max(1, math.floor(v + 0.5))
		GameConfig.Race.Lives = n
		setLivesOnCars(n)
	end,
	laps = function(v) GameConfig.Race.Laps = math.max(1, math.floor(v + 0.5)) end,
	hpMult = function(v) mult.hp = v; applyTiers() end,
	speedMult = function(v) mult.speed = v; applyTiers() end,
	biteMult = function(v) mult.bite = v; applyTiers() end,
	bruteWeight = function(v)
		for i, t in Z.Tiers do
			if t.id == "brute" then t.weight = v end
		end
	end,
	runnerWeight = function(v)
		for i, t in Z.Tiers do
			if t.id == "runner" then t.weight = v end
		end
	end,
	growl = function(v) ZombieAI.GrowlVolume = v end,
}

local function reset()
	Z.SpawnInterval = base.SpawnInterval
	Z.MaxZombies = base.MaxZombies
	Z.SpawnRadius = base.SpawnRadius
	Z.MaxAttackers = base.MaxAttackers
	Z.AttackCooldown = base.AttackCooldown
	Z.RamDamageToCar = base.RamDamageToCar
	GameConfig.Hazard.Damage = base.HazardDamage
	GameConfig.Race.Lives = base.Lives
	GameConfig.Race.Laps = base.Laps
	setLivesOnCars(base.Lives)
	mult.hp, mult.speed, mult.bite, mult.bones = 1, 1, 1, 1
	for i, t in Z.Tiers do
		for k, val in baseTiers[i] do
			(t :: any)[k] = val
		end
	end
	ZombieAI.GrowlVolume = 1
end

local function killZombies()
	for _, z in CollectionService:GetTagged("Zombie") do
		local hum = z:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Health = 0
		else
			z:Destroy()
		end
	end
end

remote.OnServerEvent:Connect(function(_player, key, value)
	if key == "reset" then
		reset()
	elseif key == "kill" then
		killZombies()
	elseif type(key) == "string" and type(value) == "number" and handlers[key] then
		handlers[key](value)
	end
end)

print("[DevTune] панель полировки на сервере готова (F2 на клиенте)")
