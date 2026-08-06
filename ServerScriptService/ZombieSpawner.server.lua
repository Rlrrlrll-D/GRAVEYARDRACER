--!strict
-- Script: ServerScriptService.ZombieSpawner
-- Clones a zombie rig from ServerStorage.ZombieTemplate at grave locations
-- and animates it climbing out of the ground.
--
-- SETUP: place a Model named "ZombieTemplate" in ServerStorage containing:
--   - a Humanoid
--   - a HumanoidRootPart
--   - (optional) an Animation child named "AttackAnimation"
-- An R15 dummy or the Toolbox "Zombie" rig both work fine.
--
-- SETUP: tag every grave/tombstone spot with CollectionService tag "Grave".
-- This can be the tombstone Part itself, or a small invisible Part placed
-- at ground level next to it — either works, since only its Position is used.

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local ZombieAI = require(script.Parent:WaitForChild("ZombieAI"))
local Economy = require(script.Parent:WaitForChild("Economy"))

local template = ServerStorage:WaitForChild("ZombieTemplate") :: Model

-- // Лидерборд: зомби и победы (leaderstats в списке игроков) ------------------
-- Значения зеркалят атрибуты игрока: ZombiesDefeated растит onZombieDied, Wins —
-- MatchManager; PlayerData сидирует оба из DataStore при входе (веха 6b).
local function setupLeaderstats(player: Player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local zombies = Instance.new("IntValue")
	zombies.Name = "Zombies"
	zombies.Value = (player:GetAttribute("ZombiesDefeated") :: number?) or 0
	zombies.Parent = ls
	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Value = (player:GetAttribute("Wins") :: number?) or 0
	wins.Parent = ls
	ls.Parent = player
	player:GetAttributeChangedSignal("ZombiesDefeated"):Connect(function()
		zombies.Value = (player:GetAttribute("ZombiesDefeated") :: number?) or 0
	end)
	player:GetAttributeChangedSignal("Wins"):Connect(function()
		wins.Value = (player:GetAttribute("Wins") :: number?) or 0
	end)
end
for _, p in Players:GetPlayers() do
	setupLeaderstats(p)
end
Players.PlayerAdded:Connect(setupLeaderstats)

local RISE_DURATION = 1.2   -- seconds to climb out of the ground
local BURY_DEPTH = 4        -- studs below the final resting position to start from

local function getGravePart(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	elseif instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
	end
	return nil
end

-- Picks a grave within SpawnRadius of an occupied vehicle. Returns nil when
-- nobody is driving near any grave — zombies emerge only as players approach,
-- not on a global timer.
local function pickGrave(): BasePart?
	local graveTags = CollectionService:GetTagged("Grave")
	local graves: {BasePart} = {}
	for _, instance in graveTags do
		local part = getGravePart(instance)
		if part then
			table.insert(graves, part)
		end
	end
	if #graves == 0 then return nil end

	-- ВАЖНО: не считаем ЗАЩИЩЁННЫЕ машины (отсчёт+грейс на старте, ProtectedUntil в
	-- будущем) — иначе зомби вылезают у грида и роятся ещё до GO, стартовать невозможно.
	-- Спавним только вокруг реально едущих (незащищённых) машин.
	local occupiedSeats: {BasePart} = {}
	for _, vehicle in CollectionService:GetTagged("PlayerVehicle") do
		local seat = vehicle:FindFirstChild("DriveSeat")
		local protected = os.clock() < ((vehicle:GetAttribute("ProtectedUntil") :: number?) or 0)
		if seat and seat:IsA("BasePart") and seat.Occupant and not protected then
			table.insert(occupiedSeats, seat)
		end
	end

	if #occupiedSeats == 0 then
		return nil -- nobody is driving, keep the graveyard quiet
	end

	local nearGraves: {BasePart} = {}
	for _, grave in graves do
		for _, seat in occupiedSeats do
			if (grave.Position - seat.Position).Magnitude <= GameConfig.Zombie.SpawnRadius then
				table.insert(nearGraves, grave)
				break
			end
		end
	end
	if #nearGraves == 0 then
		return nil -- no driver close enough to any grave yet
	end
	return nearGraves[math.random(1, #nearGraves)]
end

-- Freezes the zombie underground, then eases it up to its final CFrame.
-- Runs synchronously within the caller's task so ZombieAI only starts once
-- the zombie has fully emerged.
--
-- ПРЕРЫВАЕТСЯ СМЕРТЬЮ. Юзер: «зомби зависают над чистой дорогой», и добивка была
-- именно эта: «зомби гибнут от выстрелов, а не от столкновения». Турель достаёт
-- зомби на 40-90 studs, то есть чаще всего РОВНО В МОМЕНТ, когда он лезет из
-- могилы, — подъём идёт 1.2с. Дальше два кода дрались за одно тело: `PlayDeath`
-- якорил детали и укладывал труп, а этот цикл продолжал тянуть его по своей дуге
-- и в конце ставил стоймя в `finalCFrame` и СНИМАЛ ЯКОРЯ. Раз-якоренный труп с
-- мёртвым Humanoid уезжал куда попало, а `sinkUnderground` потом якорил его там,
-- где застало. Замер по 8 расстрелянным: у кого якоря уцелели (7/7) — зазор ровно
-- +0.35, у кого сняты (0/7) — от +0.10 до +2.24, вот эти и «висят».
-- Возвращает true, если зомби дожил до конца подъёма (тогда запускается ИИ).
local function riseFromGrave(zombie: Model, finalCFrame: CFrame): boolean
	local buriedCFrame = finalCFrame * CFrame.new(0, -BURY_DEPTH, 0)
	zombie:PivotTo(buriedCFrame)

	local parts: {BasePart} = {}
	for _, descendant in zombie:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
			descendant.Anchored = true
		end
	end

	local humanoid = zombie:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = true
	end

	-- `Dead` ставит PlayDeath первым же действием — тот же сигнал, по которому
	-- обрывается недоигранный замах. Humanoid.Health проверяем на случай, если
	-- смерть случилась раньше, чем PlayDeath успел выставить атрибут.
	local function dead(): boolean
		return zombie:GetAttribute("Dead") == true or (humanoid ~= nil and humanoid.Health <= 0)
	end

	local startTime = os.clock()
	while os.clock() - startTime < RISE_DURATION do
		if dead() then
			return false -- тело теперь целиком за PlayDeath: не двигаем и не раз-якориваем
		end
		local alpha = math.clamp((os.clock() - startTime) / RISE_DURATION, 0, 1)
		local eased = alpha * alpha * (3 - 2 * alpha) -- smoothstep easing
		zombie:PivotTo(buriedCFrame:Lerp(finalCFrame, eased))
		task.wait()
	end
	if dead() then
		return false
	end
	zombie:PivotTo(finalCFrame)

	for _, part in parts do
		part.Anchored = false
	end
	if humanoid then
		humanoid.PlatformStand = false
	end
	return true
end

local function onZombieDied(zombie: Model, humanoid: Humanoid)
	humanoid.Died:Wait()

	local killerId = zombie:GetAttribute("KilledBy")
	if killerId then
		local killer = Players:GetPlayerByUserId(killerId :: number)
		if killer then
			local defeated = (killer:GetAttribute("ZombiesDefeated") :: number?) or 0
			killer:SetAttribute("ZombiesDefeated", defeated + 1)
			Economy.award(killer, GameConfig.Economy.BonesPerZombie, "зомби")
		end
	end

	-- Смерть отыгрывает ZombieAI: тело складывается и валится, лежит и уходит под
	-- землю (тег снимает он же). Раньше тут стоял `Debris:AddItem(zombie, 3)` —
	-- Humanoid ломал суставы, и от зомби оставался мешок деталей, лежавший три
	-- секунды. Debris теперь только страховка: если анимация оборвётся на ошибке,
	-- труп всё равно не останется на трассе навсегда.
	Debris:AddItem(zombie, 15)
	ZombieAI.PlayDeath(zombie)
end

local function spawnZombie()
	local grave = pickGrave()
	if not grave then
		return -- silent: either no "Grave" tags or no driver near any grave
	end

	local zombie = template:Clone()

	for _, part in zombie:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Zombies"
		end
	end

	-- Ноги — НА ГРУНТ, а не на «центр детали-надгробия». `grave.Position` — это центр
	-- части с тегом Grave, и у камня он гуляет как угодно: замер дал и +4.15 над землёй
	-- (зомби появлялся в воздухе и потом падал), и -2.31 под ней. Опору ищем лучом ОТ
	-- ЛИЦА ЗОМБИ (группа Zombies): сквозь декор он всё равно ходит, значит крышка
	-- надгробия ему не пол — нужна земля под ней.
	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Exclude
	groundParams.CollisionGroup = "Zombies"
	groundParams.FilterDescendantsInstances = { zombie }
	local groundHit = workspace:Raycast(grave.Position + Vector3.new(0, 60, 0), Vector3.new(0, -200, 0), groundParams)
	local footY = groundHit and groundHit.Position.Y or grave.Position.Y
	local _, size = zombie:GetBoundingBox()
	local finalCFrame = CFrame.new(Vector3.new(grave.Position.X, footY + size.Y / 2, grave.Position.Z))

	-- Bury BEFORE parenting: otherwise the clone flashes for a frame at the
	-- template's stored ServerStorage CFrame before the rise task teleports it.
	zombie:PivotTo(finalCFrame * CFrame.new(0, -BURY_DEPTH, 0))
	zombie.Parent = workspace
	CollectionService:AddTag(zombie, "Zombie")

	local humanoid = zombie:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.MaxHealth = GameConfig.Zombie.MaxHealth
	humanoid.Health = GameConfig.Zombie.MaxHealth
	-- ОБЯЗАТЕЛЬНО до смерти: иначе Humanoid на Died разрывает все Motor6D, риг
	-- распадается на отдельные детали и анимировать падение уже нечем.
	humanoid.BreakJointsOnDeath = false

	task.spawn(function()
		if riseFromGrave(zombie, finalCFrame) then
			task.spawn(ZombieAI.Run, zombie) -- не дожил до конца подъёма — ИИ незачем
		end
	end)
	task.spawn(onZombieDied, zombie, humanoid)
end

task.spawn(function()
	while true do
		task.wait(GameConfig.Zombie.SpawnInterval)
		if #CollectionService:GetTagged("Zombie") < GameConfig.Zombie.MaxZombies then
			spawnZombie()
		end
	end
end)
