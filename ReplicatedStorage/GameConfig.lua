--!strict
-- ModuleScript: ReplicatedStorage.GameConfig
-- Central tunable values for the Graveyard Racer game.

export type GameConfigType = {
	Vehicle: {
		MaxHealth: number,
		MaxFuel: number,
		FuelDrainPerSecond: number,
		CrushSpeedThreshold: number, -- studs/sec; above this, vehicle crushes zombies
		LowSpeedCollisionDamage: number,
		CrushDamageToZombie: number,
		RespawnDelay: number, -- seconds the wreck burns before respawning at start
	},
	Zombie: {
		MaxHealth: number,
		WalkSpeed: number,
		ChaseRadius: number,
		AttackRange: number,
		AttackDamage: number,
		AttackCooldown: number,
		SpawnInterval: number,
		MaxZombies: number,
		SpawnRadius: number,
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
		CountdownSeconds: number,
		CheckpointRadius: number, -- studs; насколько близко надо проехать к чекпоинту
		GhostsEnabled: boolean, -- false = чистый PvP без призраков-пейсеров
		CheckpointStyle: string, -- "orb" или "skull" (череп-Каспер)
		StumbleChancePerSecond: number, -- шанс "спотыкания" призрака в секунду
		StumbleDuration: number,
		Ghosts: {{ Name: string, Speed: number, Color: Color3 }}, -- Speed в studs/сек
	},
}

local GameConfig: GameConfigType = {
	Vehicle = {
		MaxHealth = 100,
		MaxFuel = 100,
		FuelDrainPerSecond = 0.15,
		CrushSpeedThreshold = 25,
		LowSpeedCollisionDamage = 8,
		CrushDamageToZombie = 100,
		RespawnDelay = 5,
	},
	Zombie = {
		MaxHealth = 50,
		WalkSpeed = 10,
		ChaseRadius = 60,
		AttackRange = 6,
		AttackDamage = 5,
		AttackCooldown = 1.5,
		SpawnInterval = 4,
		MaxZombies = 25,
		SpawnRadius = 80,
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
		CountdownSeconds = 5,
		CheckpointRadius = 26,
		GhostsEnabled = false, -- фокус на реальных игроках; true = призраки-пейсеры для тренировки (но НЕ побеждают)
		CheckpointStyle = "skull", -- "orb" (магический шар) или "skull" (череп-Каспер)
		StumbleChancePerSecond = 0.06,
		StumbleDuration = 2,
		Ghosts = {
			{ Name = "Bone Shaker", Speed = 30, Color = Color3.fromRGB(120, 255, 180) },
			{ Name = "Grave Digger", Speed = 34, Color = Color3.fromRGB(150, 200, 255) },
			{ Name = "Ghost Rider", Speed = 38, Color = Color3.fromRGB(255, 160, 120) },
		},
	},
}

return GameConfig
