--!strict
-- ModuleScript: ReplicatedStorage.GameConfig
-- Central tunable values for the Graveyard Racer game.

export type GameConfigType = {
	Vehicle: {
		MaxHealth: number,
		MaxFuel: number,
		FuelDrainPerSecond: number,
		CrushSpeedThreshold: number, -- studs/sec; above this, vehicle crushes zombies
		-- LowSpeedCollisionDamage убран: касание зомби больше не ранит машину, урон
		-- наносит только замах (Zombie.AttackDamage). Медленное касание лишь глушит газ.
		CrushDamageToZombie: number,
		RespawnDelay: number, -- seconds the wreck burns before respawning at start
	},
	Zombie: {
		MaxHealth: number,
		WalkSpeed: number,
		ChaseRadius: number,
		AttackRange: number, -- досягаемость удара ОТ КУЗОВА машины (не от сиденья)
		AttackDamage: number,
		AttackCooldown: number,
		SpawnInterval: number,
		MaxZombies: number,
		SpawnRadius: number,
		MinSpawnDistance: number, -- ближе этого к машине из могилы не лезут
		Standoff: number, -- на столько studs зомби останавливается ОТ КУЗОВА
		MaxAttackers: number, -- сколько зомби бьют ОДНУ машину одновременно
	},
	Weapon: {
		Damage: number,
		Range: number,
		FireRate: number, -- shots per second
	},
	Hazard: {
		SpeedPenaltyMultiplier: number,
		Damage: number,
		ShakeIntensity: number,
		ShakeDuration: number,
	},
	Race: {
		Laps: number,
		Lives: number, -- сколько раз машина может быть уничтожена до выбывания (DNF)
		MinRacers: number, -- заезд стартует только когда за руль сядет ≥ этого числа игроков
		MinRacersAlone: number, -- абсолютный минимум: с меньшим числом не стартуем НИКОГДА
		SoloWaitSeconds: number, -- сколько держим место за соперниками, прежде чем пустить тех, кто есть
		CountdownSeconds: number,
		CheckpointRadius: number, -- studs; насколько близко надо проехать к чекпоинту
		GhostsEnabled: boolean, -- false = чистый PvP: неполный состав едет как есть
		GhostFillTo: number, -- сколько машин должно быть на гриде; недостающих добирают призраки
		GhostCatchUp: number, -- доля скорости (0..1), на которую призрак ускоряется/тормозит, догоняя темп лидера
		GhostBand: number, -- studs отставания/отрыва, на которых подстройка выходит на полную
		CheckpointStyle: string, -- "orb" или "skull" (череп-Каспер)
		StumbleChancePerSecond: number, -- шанс "спотыкания" призрака в секунду
		StumbleDuration: number,
		Ghosts: {{ Name: string, Speed: number, Offset: number, Color: Color3 }}, -- Speed в studs/сек, Offset — где призрак держится относительно лидера (studs)
	},
	Map: {
		GenerateRoad: boolean, -- true = MapBuilder красит Terrain-дорогу по MapLayout.TrackPolyline
		RoadWidth: number, -- ширина полотна, studs
		GroundTop: number, -- Y верхней поверхности террейна
		SlabThick: number, -- толщина грунтовой плиты
		AreaW: number, -- ширина базовой травяной плиты
		AreaH: number, -- глубина базовой травяной плиты
	},
	-- Внутренняя валюта «Кости». Начисления собраны здесь, а не разбросаны по
	-- скриптам: баланс экономики правится в одном месте. Начисляет всё Economy.
	Economy: {
		BonesPerZombie: number, -- за убитого зомби
		BonesPerFinish: number, -- дошёл до финиша (проиграл, но доехал)
		BonesPerWin: number, -- за победу, СВЕРХ BonesPerFinish
		BonesPerCheckpoint: number, -- за пройденный чекпоинт: капает и тому, кто не выиграл
	},
}

local GameConfig: GameConfigType = {
	Vehicle = {
		MaxHealth = 100,
		MaxFuel = 100,
		FuelDrainPerSecond = 0.15,
		CrushSpeedThreshold = 25,
		CrushDamageToZombie = 100,
		RespawnDelay = 2, -- коротко «горим» в кресле, затем сброс на старт (без выброса пешком)
	},
	Zombie = {
		MaxHealth = 50,
		WalkSpeed = 10,
		ChaseRadius = 60,
		-- ДОСЯГАЕМОСТЬ МЕРЯЕТСЯ ОТ КУЗОВА, А НЕ ОТ СИДЕНЬЯ, и это правка не косметическая.
		-- Багги 12.6 studs в длину, сиденье сидит почти в её центре. Пока порог был
		-- «6 studs до DriveSeat», зомби, подошедший к БАМПЕРУ, был от сиденья в 6.3+ —
		-- то есть условие «дошёл, стой и бей» у него не выполнялось НИКОГДА, и он
		-- продолжал переть в кузов на полном ходу. Отсюда и «коллапс в толпе»: десяток
		-- тел вечно ломится внутрь машины. Теперь порог — расстояние до КОРОБКИ кузова,
		-- и 2.9 studs это ровно вытянутая рука R6 (у крупных больше, см. ARM_REACH).
		AttackRange = 2.9,
		AttackDamage = 5,
		AttackCooldown = 1.5,
		SpawnInterval = 4,
		MaxZombies = 25,
		SpawnRadius = 80,
		-- Из могилы, которая ближе этого к любой машине, никто не вылезает. Подъём идёт
		-- 1.2с ЗАЯКОРЕННЫМ телом, а якорь для физики — бесконечная масса: зомби, начавший
		-- расти прямо под багги, был для неё стеной. Радиус берём с запасом от габарита
		-- (полдлины кузова 6.3 + ход подъёма).
		MinSpawnDistance = 26,
		-- Дистанция, на которой зомби ОСТАНАВЛИВАЕТСЯ перед кузовом. Меньше AttackRange,
		-- иначе он замирал бы в шаге от того, до чего не дотягивается.
		Standoff = 2.1,
		-- ПОТОЛОК УРОНА ТОЛПЫ. Кусает зомби по-прежнему на AttackDamage, но по кузову
		-- одновременно работают только столько — очередь держит ZombieAI.claimAttackSlot.
		-- Весь урон толпы, сколько бы их ни собралось, теперь ровно
		--     MaxAttackers * AttackDamage / AttackCooldown = 3 * 5 / 1.5 = 10 в секунду,
		-- то есть 10 секунд на жизнь и 30 на все три. Было — по 3.3 с КАЖДОГО: четырнадцать
		-- окруживших давали 46 в секунду и съедали машину целиком за две.
		MaxAttackers = 3,
	},
	Weapon = {
		Damage = 20,
		Range = 300,
		FireRate = 6,
	},
	Hazard = {
		SpeedPenaltyMultiplier = 0.15,
		Damage = 15,
		ShakeIntensity = 0.6,
		ShakeDuration = 0.4,
	},
	Race = {
		Laps = 3,
		Lives = 3,
		MinRacers = 3, -- заезд стартует только когда за рулём ≥ этого числа игроков (для соло-теста снизьте до 1)
		-- ПОРОГ МЯГКИЙ, И ЭТО НЕ ПОСЛАБЛЕНИЕ, А УСЛОВИЕ ВЫЖИВАНИЯ НА СТАРТЕ. В день
		-- публикации онлайна нет: первый зашедший упрётся в «1 / 3», подождёт минуту и
		-- уйдёт — а следующему опять будет не с кем, и сервер не наберёт троих никогда.
		-- Поэтому MinRacers остаётся тем, чего мы ХОТИМ, а MinRacersAlone — тем, на что
		-- согласны, если через SoloWaitSeconds соперники так и не пришли. Когда онлайн
		-- появится, ждать до конца почти не придётся: троих наберёт раньше.
		MinRacersAlone = 1,
		SoloWaitSeconds = 45, -- 45с: успеть осмотреться и не заскучать; правится одной цифрой
		CountdownSeconds = 5,
		CheckpointRadius = 40, -- ≥ полуширины дороги (22.4) + запас на широкую траекторию в поворотах, чтобы никто не «промахивался» мимо чекпоинта и не застревал
		-- ПРИЗРАКИ = ДОБОР СОСТАВА. Пустая трасса убивает гонку сильнее слабой графики:
		-- одиночка, которому не с кем ехать, просто выходит. Поэтому если живых меньше
		-- GhostFillTo, недостающие места на гриде занимают призраки — и они МОГУТ
		-- выиграть, иначе «YOU WIN» выдавалось бы даже приехавшему последним.
		GhostsEnabled = true,
		GhostFillTo = 3, -- 1 живой → 2 призрака, 2 живых → 1, трое и больше → ни одного
		-- Темп: база + мягкая подстройка под лидера. Фиксированная скорость на нашей
		-- трассе (круг ~3128 studs) либо уезжает за горизонт, либо отстаёт на круг —
		-- призрак должен ехать РЯДОМ, за это и отвечает подстройка.
		GhostCatchUp = 0.3,
		GhostBand = 260,
		CheckpointStyle = "skull", -- "orb" (магический шар) или "skull" (череп-Каспер)
		StumbleChancePerSecond = 0.06,
		StumbleDuration = 2,
		-- Offset — «своё место» призрака относительно лидера: один норовит идти впереди,
		-- другой висит на хвосте. Без этого призраки слипаются в одну точку.
		Ghosts = {
			{ Name = "Bone Shaker", Speed = 62, Offset = -70, Color = Color3.fromRGB(120, 255, 180) },
			{ Name = "Grave Digger", Speed = 66, Offset = 40, Color = Color3.fromRGB(150, 200, 255) },
			{ Name = "Ghost Rider", Speed = 70, Offset = 110, Color = Color3.fromRGB(255, 160, 120) },
		},
	},
	Map = {
		GenerateRoad = true, -- красить Terrain по MapLayout.TrackPolyline (форма из Road.svg)
		RoadWidth = 44.8, -- ×1.4 от ширины макета (32 SVG-ед.)
		GroundTop = 2,
		SlabThick = 12,
		AreaW = 680,
		AreaH = 680,
	},
	Economy = {
		-- Прикидка на заезд: 12 чекпоинтов × 3 круга × 2 = 72, десяток зомби = 50,
		-- финиш 25, победа ещё 75. То есть победный заезд ≈ 220 костей, проигранный
		-- но доеханный ≈ 145. Скины за кости имеет смысл ставить в 1500–4000.
		BonesPerZombie = 5,
		BonesPerFinish = 25,
		BonesPerWin = 75,
		BonesPerCheckpoint = 2,
	},
}

return GameConfig
