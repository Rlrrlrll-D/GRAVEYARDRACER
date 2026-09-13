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
		MaxHealth: number, -- запас по умолчанию; у типов (Tiers) свой
		-- ТИПЫ ЗОМБИ (2026-09-13): стойкость привязана к росту, который и так случайный.
		-- weight — доля в спавне; hp/walkSpeed/attackDamage/bones — своё; ramImmune — таран
		-- не давит (брут): машина получает ramDamageToCar, зомби — RamDamage от максимума.
		Tiers: { { id: string, weight: number, scaleMin: number, scaleMax: number, hp: number, walkSpeed: number, attackDamage: number, bones: number, ramImmune: boolean?, maxGap: number? } },
		RamDamage: number, -- доля HP, которую тараном снимают с ramImmune-зомби
		RamDamageToCar: number, -- сколько HP теряет машина, врезавшись в ramImmune-зомби
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
	-- Ранги: считаются из накопительных статов (ZombiesDefeated, Wins), отдельно не
	-- хранятся и не продаются. Пороги — по возрастанию, первый ранг с нуля.
	Ranks: {
		WinPoints: number, -- сколько очков даёт одна победа (зомби — по одному)
		Tiers: { { name: string, points: number, skull: { zones: { string }, color: string, shape: string? }? } },
		SkullMode: string, -- режим наложения черепа на текстуру кузова (см. RankSkull.Modes)
		SkullOpacity: number,
		SkullLift: number, -- подъём яркости черепа сверх режима (доля цвета), см. RankSkull
		-- по кузовам поверх общих (buggy/coffin): плотность/подъём/режим свои — на багги
		-- черепу нужно больше плотности, чем на досках гроба (юзер 2026-09-12)
		SkullBody: { [string]: { mode: string?, opacity: number?, lift: number?, color: string? } }?,
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
		-- ТИПЫ. С «жалостью» (maxGap) брут выпадает ~11%, раннер ~10%; средняя выплата
		-- ≈ 5.8 кости (симуляция 1000 спавнов) — чуть выше BonesPerZombie, магазин не трогаем. Стволы: пулемёт 20×6/с,
		-- дробь 8×14 в упор, гатлинг 9×15/с — шамблера дробь кладёт залпом, брут вязнет
		-- под гатлингом (18 попаданий), пулемёт — универсал. Очки ранга — 1 за любого.
		Tiers = {
			{ id = "shambler", weight = 55, scaleMin = 1.275, scaleMax = 1.5, hp = 40, walkSpeed = 10, attackDamage = 5, bones = 4 },
			{ id = "ghoul", weight = 30, scaleMin = 1.5, scaleMax = 1.8, hp = 65, walkSpeed = 10, attackDamage = 5, bones = 6 },
			{ id = "runner", weight = 7, scaleMin = 1.1, scaleMax = 1.2, hp = 25, walkSpeed = 15, attackDamage = 4, bones = 5, maxGap = 12 },
			-- maxGap: не реже, чем раз в столько спавнов — чистый жребий 8% мог не дать ни
			-- одного брута за заезд (юзер 2026-09-13)
			{ id = "brute", weight = 8, scaleMin = 2.025, scaleMax = 2.175, hp = 160, walkSpeed = 8, attackDamage = 8, bones = 15, ramImmune = true, maxGap = 11 },
		},
		RamDamage = 0.25, -- четыре тарана на брута, если не стрелять
		RamDamageToCar = 15, -- как ловушка (Hazard.Damage)
	},
	-- Стартовый пулемёт. Остальные стволы слота WEAPON (NAILER, RATTLE) — в
	-- ReplicatedStorage.Weapons, там же вид и звук выстрела; отсюда берётся только базовый.
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
	Ranks = {
		-- очки = ZombiesDefeated + WinPoints × Wins (PLAN_SHOP §4). Победный заезд
		-- со стрельбой ≈ 15 зомби + 25 = 40 очков: PALLBEARER — за 3 победных заезда
		-- или за сотню сбитых, BONE KING — за десятки вечеров.
		WinPoints = 25,
		-- Череп на кузове (RankSkull): места, цвет и ФОРМА на каждой ступени.
		-- Места: top (капот / крышка гроба), left, right (борта), rear (корма) — все
		-- четыре, что юзер отметил на листах ракурсов, на КАЖДОЙ ступени
		-- (2026-09-11: «я не увидел черепов сзади и сбоку — пофикси»).
		-- РАНГ РАЗЛИЧАЕТ ФОРМА, А НЕ ЦВЕТ (юзер 2026-09-12: «уходим от концепции разных
		-- цветов в пользу разных черепов»): shape — имя силуэта из SkullShapes
		-- (skull_range.ai — череп с лентой и именем ранга), цвет у всех один — bone,
		-- как подобрано в SkullTune. Нулевая ступень тоже с черепом: в векторе он есть.
		Tiers = {
			{ name = "GRAVEDIGGER", points = 0, skull = { zones = { "top", "left", "right", "rear" }, color = "bone", shape = "GRAVEDIGGER" } },
			{ name = "PALLBEARER", points = 100, skull = { zones = { "top", "left", "right", "rear" }, color = "bone", shape = "PALLBEARER" } },
			{ name = "GRAVE ROBBER", points = 400, skull = { zones = { "top", "left", "right", "rear" }, color = "bone", shape = "GRAVE ROBBER" } },
			{ name = "REAPER", points = 1200, skull = { zones = { "top", "left", "right", "rear" }, color = "bone", shape = "REAPER" } },
			{ name = "BONE KING", points = 3000, skull = { zones = { "top", "left", "right", "rear" }, color = "bone", shape = "BONE KING" } },
		},
		-- Режим наложения черепа на текстуру кузова (multiply / overlay / screen /
		-- softlight / lineardodge / normal), плотность и подъём яркости (доля цвета сверх
		-- режима — на тёмной ржавчине без него череп не поднимается выше полутона).
		-- ЧИСЛА ПОДОБРАНЫ ЮЗЕРОМ НА ЭКРАНЕ (SkullTune, 2026-09-12) и зашиты как есть;
		-- крутить снова — F3 в Studio, P печатает строку для переноса сюда.
		-- Гараж-песочница 2026-09-12: Overlay у обоих кузовов, общие числа = багги, гроб —
		-- своя плотность/подъём; у багги череп теплее (RankSkull.Colors.rosebone).
		SkullMode = "overlay",
		SkullOpacity = 0.53,
		SkullLift = 0.31,
		SkullBody = {
			buggy = { color = "rosebone" },
			coffin = { opacity = 0.64, lift = 0.26 },
		},
	},
}

return GameConfig
