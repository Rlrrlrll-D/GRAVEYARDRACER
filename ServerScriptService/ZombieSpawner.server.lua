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
local Badges = require(script.Parent:WaitForChild("Badges"))

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

-- // Порода мертвеца: окрас и рост -------------------------------------------
-- ОДИН ШАБЛОН, РАЗНЫЕ ПОКОЙНИКИ. Толпа одинаковых клонов читается как клонов, а не
-- как кладбища. Меняем ровно то, что можно менять без второй модели: цвет тела
-- (мешевые лохмотья — это «одежда») и цвет головы («кожа»). Кисти рук остаются
-- зеленоватыми у всех: этот оттенок запечён в оверлей-текстуре классического зомби,
-- и он же связывает толпу в одну породу — так и задумано.
--
-- Окрасы согласованы с юзером по пробам 2026-08-07 (утопленник и гнилой отвергнуты).
local VARIANTS = {
	{ body = Color3.fromRGB(39, 70, 45), head = Color3.fromRGB(58, 125, 21) }, -- зелёный (исходный)
	{ body = Color3.fromRGB(96, 90, 64), head = Color3.fromRGB(128, 120, 86) }, -- восковой
	{ body = Color3.fromRGB(62, 52, 44), head = Color3.fromRGB(88, 74, 62) }, -- землистый
	{ body = Color3.fromRGB(74, 80, 70), head = Color3.fromRGB(96, 104, 90) }, -- пепельный
}

-- ВСЕ РОСТЫ x1.5 (2026-08-10, юзер: «зомби лилипуты какие-то»). Множитель применён к
-- обоим диапазонам сразу, поэтому соотношение «обычный / здоровяк» и разброс внутри
-- породы сохранились — толпа просто стала крупнее целиком, а не разъехалась.
-- Досягаемость удара и глубина могилы считаются ОТ РОСТА (ARM_REACH и BASE_HEIGHT
-- ниже), так что подстроятся сами: высокий бьёт с большего расстояния и вылезает из
-- более глубокой ямы. Отдельно править их не надо.
local SCALE_MIN, SCALE_MAX = 1.275, 1.8 -- было 0.85 / 1.2
local BRUTE_CHANCE = 0.08 -- каждый двенадцатый примерно
local BRUTE_MIN, BRUTE_MAX = 2.025, 2.175 -- было 1.35 / 1.45
local ARM_REACH = 2 -- studs: длина руки R6, на столько меняется досягаемость на каждую единицу роста

-- // ВЕС НЕ РАСТЁТ ВМЕСТЕ С РОСТОМ ------------------------------------------
--
-- ЖАЛОБА: «в толпе зомби багги ведёт себя непредсказуемо». Замер живой машины
-- в заезде объясняет, почему толпа вообще способна ею вертеть:
--     сборка кузова с водителем   46.5   <- A-Chassis делает всё лишнее Massless
--     колесо (отдельная сборка)    1.7
--     зомби ростом 1.79           36.1   <- 78% от всей машины
--     зомби-здоровяк              64.8   <- ТЯЖЕЛЕЕ машины в полтора раза
-- То есть один покойник — это почти вторая багги, а десяток вокруг весит как
-- грузовик. При таких числах любое касание двигает не зомби, а машину.
--
-- И это не изначальная задумка, а побочный эффект правки от 2026-08-10 («зомби
-- лилипуты какие-то»): все размеры подняли ×1.5, а масса растёт КУБОМ размера —
-- то есть выросла в 3.375 раза, молча. До той правки самый крупный весил 19, и
-- физика толпы никого не смущала.
--
-- Поэтому вес возвращаем к дореформенному: плотность делим ровно на тот куб,
-- на который её умножил рост. Смотреться зомби продолжает крупным — он и остаётся
-- крупным, меняется только то, чего не видно.
local SIZE_BOOST = 1.5 -- на столько подняли рост 2026-08-10
local DENSITY_FIX = 1 / (SIZE_BOOST ^ 3) -- ...и на столько же долой из плотности

-- Рост шаблона меряем один раз: от него считается и глубина могилы, чтобы высокий
-- покойник не начинал подъём, торча из земли по пояс.
local BASE_HEIGHT = select(2, template:GetBoundingBox()).Y

-- Разброс внутри окраса: без него четыре породы стоят четырьмя ровными группами.
-- Сдвиг маленький (±6%), порода остаётся узнаваемой.
local function jitter(c: Color3): Color3
	local k = 0.06
	local function ch(v: number): number
		return math.clamp(v * (1 + (math.random() - 0.5) * 2 * k), 0, 1)
	end
	return Color3.new(ch(c.R), ch(c.G), ch(c.B))
end

local function pickScale(): number
	if math.random() < BRUTE_CHANCE then
		return BRUTE_MIN + math.random() * (BRUTE_MAX - BRUTE_MIN)
	end
	return SCALE_MIN + math.random() * (SCALE_MAX - SCALE_MIN)
end

-- Красим И объект BodyColors, И сами детали: BodyColors для рига авторитетнее и
-- переписал бы цвета деталей, а детали нужны на случай, если объекта в шаблоне не
-- окажется. Дешевле сделать оба, чем ловить потом «половина зомби не покрасилась».
local function dressZombie(zombie: Model)
	local variant = VARIANTS[math.random(#VARIANTS)]
	local body, head = jitter(variant.body), jitter(variant.head)
	local bc = zombie:FindFirstChildOfClass("BodyColors")
	if bc then
		bc.HeadColor3 = head
		bc.TorsoColor3 = body
		bc.LeftArmColor3, bc.RightArmColor3 = body, body
		bc.LeftLegColor3, bc.RightLegColor3 = body, body
	end
	for _, part in zombie:GetChildren() do
		if part:IsA("BasePart") then
			part.Color = if part.Name == "Head" then head else body
		end
	end
end

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
	local allSeats: {BasePart} = {} -- ВСЕ машины, а не только едущие: см. «слишком близко» ниже
	for _, vehicle in CollectionService:GetTagged("PlayerVehicle") do
		local seat = vehicle:FindFirstChild("DriveSeat")
		local protected = os.clock() < ((vehicle:GetAttribute("ProtectedUntil") :: number?) or 0)
		if seat and seat:IsA("BasePart") then
			table.insert(allSeats, seat)
			if seat.Occupant and not protected then
				table.insert(occupiedSeats, seat)
			end
		end
	end

	if #occupiedSeats == 0 then
		return nil -- nobody is driving, keep the graveyard quiet
	end

	-- СЛИШКОМ БЛИЗКО — НЕ ВЫЛЕЗАЕМ, и это про физику, а не про честность.
	--
	-- Подъём из могилы идёт 1.2с ЗАЯКОРЕННЫМ телом (riseFromGrave), а якорь для
	-- решателя — бесконечная масса. Нижней границы у радиуса спавна не было вовсе:
	-- могила в трёх studs от багги считалась подходящей ровно так же, как дальняя, —
	-- и в машину, увязшую в толпе, каждые четыре секунды вырастала неподвижная стена
	-- прямо под кузовом. Это и есть «попытался уехать — и всё разлетелось».
	--
	-- Считаем от ЛЮБОЙ машины, включая пустую и защищённую: под чужой стоящей багги
	-- вырастать так же нельзя.
	local function tooClose(grave: BasePart): boolean
		for _, seat in allSeats do
			if (grave.Position - seat.Position).Magnitude < GameConfig.Zombie.MinSpawnDistance then
				return true
			end
		end
		return false
	end

	local nearGraves: {BasePart} = {}
	for _, grave in graves do
		if not tooClose(grave) then
			for _, seat in occupiedSeats do
				if (grave.Position - seat.Position).Magnitude <= GameConfig.Zombie.SpawnRadius then
					table.insert(nearGraves, grave)
					break
				end
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
	-- Глубина — ДОЛЯ РОСТА, а не четыре studs всем подряд. Иначе высокий покойник
	-- начинал бы подъём, торча из земли по грудь: закапывание считается от ЦЕНТРА
	-- модели, и чем выше тело, тем выше над центром его макушка.
	local depth = BURY_DEPTH * (select(2, zombie:GetBoundingBox()).Y / BASE_HEIGHT)
	local buriedCFrame = finalCFrame * CFrame.new(0, -depth, 0)
	zombie:PivotTo(buriedCFrame)

	-- НА ВРЕМЯ ПОДЪЁМА ТЕЛО НЕ СТАЛКИВАЕТСЯ НИ С ЧЕМ. Оно заякорено, а заякоренная
	-- деталь для физики — бесконечная масса: машина, влетевшая в вылезающего зомби,
	-- бьётся о стену, а не о тело. Ловится это редко и выглядит как «на ровном месте
	-- подкинуло». Минимальную дистанцию спавна уже держит pickGrave, но в неё можно
	-- ВЪЕХАТЬ — от этого страхует уже только вот это.
	--
	-- Прежнее CanCollide запоминаем поимённо: у R6-зомби руки и ноги в шаблоне и так
	-- бесконтактные, восстанавливать всем подряд «true» нельзя.
	local parts: {BasePart} = {}
	local wasCollide: { [BasePart]: boolean } = {}
	for _, descendant in zombie:GetDescendants() do
		if descendant:IsA("BasePart") then
			local part = descendant :: BasePart
			table.insert(parts, part)
			wasCollide[part] = part.CanCollide
			part.CanCollide = false
			part.Anchored = true
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
		part.CanCollide = wasCollide[part]
	end
	if humanoid then
		humanoid.PlatformStand = false
	end

	-- ВЛАДЕНИЕ ФИЗИКОЙ ЗОМБИ — У СЕРВЕРА, ЯВНО. По умолчанию владение раздаётся
	-- автоматически: сборку без якоря движок отдаёт ближайшему игроку. То есть стаю,
	-- сбежавшуюся к багги, считал ТЕЛЕФОН ВОДИТЕЛЯ — вдобавок к самой A-Chassis
	-- (четыре колеса на пружинах, BodyAngularVelocity с P = 1e9, гироскопы). На слабом
	-- клиенте кадр проседает, шаг физики растёт, и первым это чувствует шасси: рывки
	-- руля и подвески, «непредсказуемая реакция». Плюс владение перещёлкивалось прямо
	-- во время контакта — каждый переход это разрыв в физике.
	--
	-- Только ПОСЛЕ снятия якоря: у заякоренной детали владельца нет и вызов упадёт.
	local root = zombie:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		pcall(function()
			(root :: BasePart):SetNetworkOwner(nil)
		end)
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
			-- ДВА СЧЁТЧИКА, И ОНИ О РАЗНОМ. ZombiesDefeated — за всё время (значок
			-- Hundred Down, лидерборд), RaceZombies — за текущий заезд (HUD и экран
			-- итогов). Обнуляет второй MatchManager на старте; здесь оба растут вместе.
			local thisRace = (killer:GetAttribute("RaceZombies") :: number?) or 0
			killer:SetAttribute("RaceZombies", thisRace + 1)
			Economy.award(killer, GameConfig.Economy.BonesPerZombie, "зомби")
			-- Счётчик накопительный (PlayerData сидирует его из записи при входе),
			-- поэтому сотня набирается за все сессии, а не за одну.
			if defeated + 1 >= 100 then
				Badges.award(killer, "hundred_zombies")
			end
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

	-- Рост и окрас — ДО замера габарита ниже: по нему считается, на какой высоте
	-- стоят ноги, и мерить надо уже готовое тело.
	local scale = pickScale()
	zombie:ScaleTo(scale) -- ScaleTo двигает и суставы, поэтому замах не разъезжается
	dressZombie(zombie)
	zombie:SetAttribute("BodyScale", scale)
	-- Досягаемость растёт ровно на длину руки, а не пропорционально всей дистанции:
	-- база `AttackRange` — это зазор от БОРТА КУЗОВА (см. ZombieAI.surfacePoint), в нём
	-- нет ничего, что стоило бы множить на рост, кроме самой руки.
	zombie:SetAttribute("AttackRange", GameConfig.Zombie.AttackRange + (scale - 1) * ARM_REACH)
	-- Где остановиться перед кузовом. Растёт вместе с телом, но медленнее руки: иначе
	-- здоровяк вставал бы дальше, чем достаёт. Разница Standoff↔AttackRange — это и
	-- есть запас, в котором удар засчитывается.
	zombie:SetAttribute("Standoff", GameConfig.Zombie.Standoff + (scale - 1) * (ARM_REACH * 0.5))

	for _, part in zombie:GetDescendants() do
		if part:IsA("BasePart") then
			local p = part :: BasePart
			p.CollisionGroup = "Zombies"
			-- вес — дореформенный, см. DENSITY_FIX
			local pp = p.CurrentPhysicalProperties
			p.CustomPhysicalProperties = PhysicalProperties.new(
				pp.Density * DENSITY_FIX,
				pp.Friction,
				pp.Elasticity,
				pp.FrictionWeight,
				pp.ElasticityWeight
			)
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

	-- ЗОМБИ НЕ ПАДАЕТ, НЕ КУВЫРКАЕТСЯ И НЕ САДИТСЯ ЗА РУЛЬ.
	--
	-- Humanoid сам переходит в FallingDown / Ragdoll, когда его толкнули или он
	-- запнулся, — и тогда тело перестаёт стоять и растекается по земле ПОД машиной,
	-- ровно туда, где ему быть нельзя. GettingUp довершает: тело рывком поднимается,
	-- упираясь в кузов. Нашей смерти эти состояния не нужны вовсе — падение отыгрывает
	-- ZombieAI.PlayDeath по Motor6D, на заякоренном теле.
	--
	-- Seated отключён по другой причине: DriveSeat — это VehicleSeat, и он усаживает
	-- ЛЮБОЙ коснувшийся Humanoid. Стоит водителю на миг встать (выброс, респавн), как
	-- за руль садится зомби — вместе с машиной.
	for _, state in {
		Enum.HumanoidStateType.FallingDown,
		Enum.HumanoidStateType.Ragdoll,
		Enum.HumanoidStateType.GettingUp,
		Enum.HumanoidStateType.Seated,
		Enum.HumanoidStateType.Climbing,
	} do
		pcall(function()
			humanoid:SetStateEnabled(state, false)
		end)
	end

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
		-- ДЕВ-ВЫКЛЮЧАТЕЛЬ (PhotoModeService, только Studio): пока флаг стоит, новых
		-- зомби не плодим. Нужен, чтобы настраивать свет и анимации у чекпоинтов —
		-- иначе стая доедает машину прямо во время наблюдения. В живой игре атрибута
		-- не существует, проверка просто ложна.
		if not workspace:GetAttribute("ZombiesOff")
			and #CollectionService:GetTagged("Zombie") < GameConfig.Zombie.MaxZombies
		then
			spawnZombie()
		end
	end
end)
