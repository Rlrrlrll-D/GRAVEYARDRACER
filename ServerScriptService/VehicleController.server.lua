--!strict
-- Script: ServerScriptService.VehicleController
-- Manages health / fuel / speed for every Model tagged "PlayerVehicle".
--
-- SETUP per vehicle Model (placed anywhere in Workspace):
--   - Tag the Model with CollectionService tag "PlayerVehicle"
--     (Studio: select Model > Model tab > Tag Editor > add "PlayerVehicle")
--   - Must contain a VehicleSeat named "DriveSeat"
--   - Model.PrimaryPart should be set
--
-- Stats live as Attributes on the Model (Health, MaxHealth, Fuel, Speed,
-- SpeedMultiplier, Destroyed) so HazardManager, WeaponServer and
-- StatsService can all read/write them without extra coupling.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local VehicleRegistry = require(ReplicatedStorage:WaitForChild("VehicleRegistry"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local updateStats = remotes:WaitForChild("UpdateStats") :: RemoteEvent

local TAG = "PlayerVehicle"
local BASE_MAX_SPEED = 50 -- studs/sec at full throttle before hazard penalties

local function setupVehicle(vehicle: Model)
	local driveSeat = vehicle:FindFirstChild("DriveSeat")
	if not driveSeat or not driveSeat:IsA("VehicleSeat") then
		warn(`[VehicleController] {vehicle.Name} is missing a VehicleSeat named "DriveSeat".`)
		return
	end

	for _, part in vehicle:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Vehicles"
		end
	end

	vehicle:SetAttribute("Health", GameConfig.Vehicle.MaxHealth)
	vehicle:SetAttribute("MaxHealth", GameConfig.Vehicle.MaxHealth)
	vehicle:SetAttribute("Fuel", GameConfig.Vehicle.MaxFuel)
	vehicle:SetAttribute("Speed", 0)
	vehicle:SetAttribute("SpeedMultiplier", 1)
	vehicle:SetAttribute("Destroyed", false)
	vehicle:SetAttribute("Lives", GameConfig.Race.Lives)
	vehicle:SetAttribute("Eliminated", false)
	vehicle:SetAttribute("Invulnerable", false)

	-- // Death & respawn ---------------------------------------------------
	-- On Destroyed: eject the driver and disable the seat (this also stops
	-- A-Chassis cars, which ignore VehicleSeat.MaxSpeed), burn for
	-- RespawnDelay seconds, then respawn at the spawn CFrame fully repaired.
	local homeCFrame = vehicle:GetPivot()

	local function clearFx()
		for _, fx in vehicle:GetDescendants() do
			if fx:IsA("Smoke") or fx:IsA("Fire") then
				fx:Destroy()
			end
		end
	end

	local function igniteWreck()
		local effectRoot = (vehicle.PrimaryPart or driveSeat) :: BasePart
		local smoke = Instance.new("Smoke")
		smoke.Size = 8
		smoke.Opacity = 0.4
		smoke.RiseVelocity = 8
		smoke.Color = Color3.fromRGB(35, 35, 35)
		smoke.Parent = effectRoot
		local fire = Instance.new("Fire")
		fire.Size = 9
		fire.Heat = 12
		fire.Parent = effectRoot
		return smoke, fire
	end

	-- Финальный кадр статов ПЕРЕД выбросом: StatsService шлёт HUD только
	-- пока игрок за рулём, иначе полоска замрёт на предсмертном значении.
	local function pushFinalStats(livesLeft: number)
		local driver = VehicleRegistry.GetPlayerForVehicle(vehicle)
		if driver then
			updateStats:FireClient(driver, {
				Health = 0,
				MaxHealth = vehicle:GetAttribute("MaxHealth") or GameConfig.Vehicle.MaxHealth,
				Speed = 0,
				Fuel = vehicle:GetAttribute("Fuel") or 0,
				Lives = livesLeft,
				ZombiesDefeated = driver:GetAttribute("ZombiesDefeated") or 0,
			})
		end
	end

	local function ejectDriver()
		local occupant = (driveSeat :: VehicleSeat).Occupant
		if occupant then
			occupant.Sit = false
		end
		(driveSeat :: VehicleSeat).Disabled = true
	end

	-- Ремонт на старте: позиция, скорости, статы, сиденье снова активно.
	local function repairAtHome()
		vehicle:PivotTo(homeCFrame)
		for _, part in vehicle:GetDescendants() do
			if part:IsA("BasePart") then
				part.AssemblyLinearVelocity = Vector3.zero
				part.AssemblyAngularVelocity = Vector3.zero
			end
		end
		vehicle:SetAttribute("Health", GameConfig.Vehicle.MaxHealth)
		vehicle:SetAttribute("Fuel", GameConfig.Vehicle.MaxFuel)
		vehicle:SetAttribute("SpeedMultiplier", 1);
		(driveSeat :: VehicleSeat).Disabled = false
		vehicle:SetAttribute("Destroyed", false)
		-- грейс-неуязвимость + отодвигаем зомби от точки респавна (чтобы не
		-- попадать сразу под атаку того же зомби после возрождения)
		vehicle:SetAttribute("ProtectedUntil", os.clock() + 3) -- грейс после респавна (авторитет)
		vehicle:SetAttribute("Invulnerable", true)
		task.delay(3, function()
			vehicle:SetAttribute("Invulnerable", false)
		end)
		local origin = homeCFrame.Position
		for _, z in CollectionService:GetTagged("Zombie") do
			if z:IsA("Model") then
				local ok, piv = pcall(function()
					return z:GetPivot()
				end)
				if ok then
					local off = Vector3.new(piv.Position.X - origin.X, 0, piv.Position.Z - origin.Z)
					if off.Magnitude < 40 then
						local dir = off.Magnitude > 0.1 and off.Unit or Vector3.new(1, 0, 0)
						z:PivotTo(piv + dir * 45)
					end
				end
			end
		end
	end

	-- Есть ещё жизни: водителя НЕ выбрасываем на дорогу — он остаётся в кресле,
	-- машина коротко «горит» (неуязвима, чтобы не добили), затем телепортируется на
	-- старт и чинится. Игрок всё это время в машине (по просьбе: без выброса пешком).
	local function burnAndRespawn(_livesLeft: number)
		local smoke, fire = igniteWreck()
		pushFinalStats(_livesLeft)
		vehicle:SetAttribute("Invulnerable", true) -- пока горит — не добить
		task.wait(GameConfig.Vehicle.RespawnDelay)
		smoke:Destroy()
		fire:Destroy()
		repairAtHome() -- телепорт машины (с сидящим водителем) на старт + починка + грейс
	end

	-- Жизни кончились: машина остаётся разбитой, игрок выбывает. Оживёт
	-- при следующем FullReset (старт нового заезда); RaceManager покажет GAME OVER.
	local function eliminate()
		igniteWreck()
		pushFinalStats(0)
		ejectDriver()
		vehicle:SetAttribute("Eliminated", true)
	end

	-- Полный сброс к старту нового заезда: жизни, ремонт, снятие "выбыл".
	local function fullReset()
		clearFx()
		vehicle:SetAttribute("Lives", GameConfig.Race.Lives)
		vehicle:SetAttribute("Eliminated", false)
		repairAtHome()
	end

	vehicle:GetAttributeChangedSignal("Destroyed"):Connect(function()
		if not vehicle:GetAttribute("Destroyed") then return end
		if vehicle:GetAttribute("Eliminated") then return end -- уже выбыл
		local lives = ((vehicle:GetAttribute("Lives") :: number?) or GameConfig.Race.Lives) - 1
		vehicle:SetAttribute("Lives", math.max(lives, 0))
		if lives > 0 then
			task.spawn(function()
				burnAndRespawn(lives)
			end)
		else
			task.spawn(eliminate)
		end
	end)

	vehicle:GetAttributeChangedSignal("FullReset"):Connect(function()
		task.spawn(fullReset)
	end)

	-- // Driver tracking --------------------------------------------------
	driveSeat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = driveSeat.Occupant
		if occupant then
			local character = occupant.Parent
			local player = character and Players:GetPlayerFromCharacter(character)
			if player then
				VehicleRegistry.SetDriver(vehicle, player)
			end
		else
			VehicleRegistry.SetDriver(vehicle, nil)
		end
	end)

	-- // Per-frame speed / fuel loop --------------------------------------
	RunService.Heartbeat:Connect(function(dt: number)
		if not vehicle.Parent then return end
		if vehicle:GetAttribute("Destroyed") then
			driveSeat.MaxSpeed = 0
			return
		end

		local speed = driveSeat.AssemblyLinearVelocity.Magnitude
		vehicle:SetAttribute("Speed", speed)

		local multiplier = (vehicle:GetAttribute("SpeedMultiplier") :: number?) or 1
		driveSeat.MaxSpeed = BASE_MAX_SPEED * multiplier

		if driveSeat.Occupant and driveSeat.Throttle ~= 0 then
			local fuel = (vehicle:GetAttribute("Fuel") :: number?) or GameConfig.Vehicle.MaxFuel
			fuel = math.max(0, fuel - GameConfig.Vehicle.FuelDrainPerSecond * dt)
			vehicle:SetAttribute("Fuel", fuel)
			if fuel <= 0 then
				driveSeat.Throttle = 0
			end
		end
	end)

	-- // Crush / stall combat -----------------------------------------------
	local lastHitAt: {[Instance]: number} = {}

	local function onPartTouched(hit: BasePart)
		if vehicle:GetAttribute("Destroyed") or vehicle:GetAttribute("Invulnerable") then return end
		-- ProtectedUntil — единый авторитет неуязвимости (timestamp, без мерцания
		-- атрибута): держит иммунитет на отсчёт+грейс и после респавна.
		if os.clock() < ((vehicle:GetAttribute("ProtectedUntil") :: number?) or 0) then return end

		local zombieModel = hit:FindFirstAncestorOfClass("Model")
		if not zombieModel or not CollectionService:HasTag(zombieModel, "Zombie") then
			return
		end

		local now = os.clock()
		if lastHitAt[zombieModel] and now - lastHitAt[zombieModel] < 0.5 then
			return
		end
		lastHitAt[zombieModel] = now

		local humanoid = zombieModel:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return end

		local speed = (vehicle:GetAttribute("Speed") :: number?) or 0
		if speed >= GameConfig.Vehicle.CrushSpeedThreshold then
			local killer = VehicleRegistry.GetPlayerForVehicle(vehicle)
			if killer then
				zombieModel:SetAttribute("KilledBy", killer.UserId)
			end
			-- Куда опрокинуть тело, если сбили насмерть: машина уносит зомби ПО ХОДУ
			-- движения (ZombieAI.PlayDeath читает атрибут). Берём именно скорость
			-- сборки, а не «от машины к зомби»: на касании вскользь второе дало бы
			-- падение вбок, хотя зомби явно подсекло капотом вперёд.
			local vel = driveSeat.AssemblyLinearVelocity
			local flat = Vector3.new(vel.X, 0, vel.Z)
			if flat.Magnitude > 1 then
				zombieModel:SetAttribute("DeathPush", flat.Unit)
			end
			humanoid:TakeDamage(GameConfig.Vehicle.CrushDamageToZombie)
		else
			local health = (vehicle:GetAttribute("Health") :: number?) or GameConfig.Vehicle.MaxHealth
			health = math.max(0, health - GameConfig.Vehicle.LowSpeedCollisionDamage)
			vehicle:SetAttribute("Health", health)
			driveSeat.Throttle = 0
			if health <= 0 then
				vehicle:SetAttribute("Destroyed", true)
			end
		end
	end

	for _, part in vehicle:GetDescendants() do
		if part:IsA("BasePart") then
			part.Touched:Connect(onPartTouched)
		end
	end
end

for _, vehicle in CollectionService:GetTagged(TAG) do
	if vehicle:IsA("Model") then
		task.spawn(setupVehicle, vehicle)
	end
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(function(instance)
	if instance:IsA("Model") then
		task.spawn(setupVehicle, instance)
	end
end)
