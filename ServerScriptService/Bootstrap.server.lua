--!strict
-- Script: ServerScriptService.Bootstrap
-- Runs once on server start. Creates shared Remotes and configures
-- PhysicsService collision groups. Every other script WaitForChild()s
-- the Remotes folder, so load order relative to this script doesn't matter.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")

local Net = require(ReplicatedStorage:WaitForChild("Net"))

-- // Remotes -----------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage

-- Создаём по манифесту ReplicatedStorage.Net — единый источник имён событий
-- (и старые FireWeapon/RaceUpdate/…, и новые PlayerReady/LobbyState/BatScare/…).
for _, eventName in Net.Events do
	local event = Instance.new("RemoteEvent")
	event.Name = eventName
	event.Parent = remotes
end

-- // Collision Groups ---------------------------------------------------
-- Bystanders — те, кто сейчас НЕ в заезде: стоят у старта замороженные (PlayerFlow).
-- Увернуться они не могут, поэтому машина обязана проходить сквозь них.
-- VehicleWheels — КОЛЁСА И ПОДВЕСКА, отдельно от кузова. Разбор ниже, у правила
-- «VehicleWheels ↔ Zombies = false».
local GROUPS = { "Vehicles", "VehicleWheels", "Zombies", "Obstacles", "Environment", "Projectiles", "Bystanders" }

for _, groupName in GROUPS do
	local ok = pcall(function()
		PhysicsService:RegisterCollisionGroup(groupName)
	end)
	if not ok then
		warn(`[Bootstrap] Collision group "{groupName}" already exists, skipping.`)
	end
end

-- Zombies physically collide with vehicles (gives the crush a physical feel).
-- Сквозь ДЕКОР они по-прежнему ходят: полноценного обхода препятствий у них нет,
-- и без этого стая застревала бы в надгробиях по дороге к машине.
PhysicsService:CollisionGroupSetCollidable("Vehicles", "Zombies", true)
PhysicsService:CollisionGroupSetCollidable("Vehicles", "Obstacles", true)
PhysicsService:CollisionGroupSetCollidable("Vehicles", "Environment", true)

-- ДРУГ В ДРУГА НЕ ПРОНИКАЮТ (2026-08-28, просьба юзера). Раньше стояло `false` — и
-- это было не косметическое решение, а плата за отсутствие обхода препятствий: тела
-- слипались в одну точку, зато не толкались.
--
-- Теперь плата не нужна. Толпа больше не ломится в кузов (каждый останавливается у
-- борта, ZombieAI.surfacePoint), а вес тела вернули к дореформенному (ZombieSpawner,
-- DENSITY_FIX) — то есть куча-мала из пятнадцати тел, ради страховки от которой
-- контакт и выключали, физически стала лёгкой. Заодно исчезает главная нелепость
-- прежнего варианта: десяток покойников, слитых в один силуэт у борта.
PhysicsService:CollisionGroupSetCollidable("Zombies", "Zombies", true)

-- // Колёса: с миром как кузов, но зомби в подвеску не попадают -------------
--
-- ЖАЛОБА: «в толпе зомби машину рвёт и кидает непредсказуемо». Замер масс в
-- шаблоне объясняет, почему именно рвёт:
--     кузов (одна сборка)         ~7700
--     КОЛЕСО (отдельная сборка)   ~9.7   <- Tune.FWheelDensity = .1
--     зомби ростом 1.8            ~37
--     зомби-здоровяк              ~58
-- Колесо у A-Chassis — САМОСТОЯТЕЛЬНАЯ сборка на пружине (Stiffness 8000, ход 2.2),
-- а не часть кузова. Тело, попавшее между колесом и аркой, тяжелее этого колеса
-- вчетверо-вшестеро: пружину пробивает за упор, рычаг выворачивает, и машина уезжает
-- с деформированной подвеской (это же ловит сторож в VehicleController).
--
-- Кузов зомби по-прежнему бьёт и толкает — ощущение толпы остаётся. Из подвески они
-- исключены целиком: там от них только поломка, увидеть их под аркой всё равно нельзя.
PhysicsService:CollisionGroupSetCollidable("VehicleWheels", "Zombies", false)
PhysicsService:CollisionGroupSetCollidable("VehicleWheels", "Bystanders", false) -- как и кузов
PhysicsService:CollisionGroupSetCollidable("VehicleWheels", "Projectiles", false) -- как и всё: попадания лучом
PhysicsService:CollisionGroupSetCollidable("VehicleWheels", "Obstacles", true)
PhysicsService:CollisionGroupSetCollidable("VehicleWheels", "Environment", true)
PhysicsService:CollisionGroupSetCollidable("Zombies", "Obstacles", false)
PhysicsService:CollisionGroupSetCollidable("Zombies", "Environment", true)
PhysicsService:CollisionGroupSetCollidable("Projectiles", "Zombies", false) -- hits are raycast, not physical
PhysicsService:CollisionGroupSetCollidable("Projectiles", "Environment", false)
-- Ждущих в лобби машина не сбивает: они заморожены у старта, а трасса замкнута —
-- гонщик проезжает мимо них на каждом круге.
PhysicsService:CollisionGroupSetCollidable("Vehicles", "Bystanders", false)

print("[Bootstrap] Remotes created and collision groups configured.")
