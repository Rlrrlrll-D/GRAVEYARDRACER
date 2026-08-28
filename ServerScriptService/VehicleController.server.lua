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
local PlayerFlow = require(script.Parent:WaitForChild("PlayerFlow"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local updateStats = remotes:WaitForChild("UpdateStats") :: RemoteEvent

local TAG = "PlayerVehicle"
local BASE_MAX_SPEED = 50 -- studs/sec at full throttle before hazard penalties

-- // Группы столкновений машины -----------------------------------------------
-- Кузов — "Vehicles", колёса и подвеска — "VehicleWheels" (правила в Bootstrap:
-- зомби в подвеску не попадают, всё остальное как у кузова).
--
-- ЗОВЁТСЯ ДВАЖДЫ, И ЭТО ОБЯЗАТЕЛЬНО. A-Chassis достраивает шасси уже ПОСЛЕ того, как
-- машина появилась в Workspace: он сам создаёт рычаги (`Arm`), гироскопы и весовой
-- кирпич. Детали, рождённые после первого прохода, оставались в группе "Default" —
-- то есть жили по правилам «сталкиваюсь со всем», включая зомби. Второй проход
-- (из вахты ниже, там уже есть ожидание готового `Arm`) их подбирает.
local function applyCollisionGroups(vehicle: Model)
	local wheels = vehicle:FindFirstChild("Wheels")
	for _, part in vehicle:GetDescendants() do
		if part:IsA("BasePart") then
			local inWheels = wheels ~= nil and part:IsDescendantOf(wheels :: Instance)
			part.CollisionGroup = if inWheels then "VehicleWheels" else "Vehicles"
		end
	end
end

local function setupVehicle(vehicle: Model)
	local driveSeat = vehicle:FindFirstChild("DriveSeat")
	if not driveSeat or not driveSeat:IsA("VehicleSeat") then
		warn(`[VehicleController] {vehicle.Name} is missing a VehicleSeat named "DriveSeat".`)
		return
	end

	applyCollisionGroups(vehicle)

	vehicle:SetAttribute("Health", GameConfig.Vehicle.MaxHealth)
	vehicle:SetAttribute("MaxHealth", GameConfig.Vehicle.MaxHealth)
	vehicle:SetAttribute("Fuel", GameConfig.Vehicle.MaxFuel)
	vehicle:SetAttribute("Speed", 0)
	vehicle:SetAttribute("SpeedMultiplier", 1)
	vehicle:SetAttribute("Destroyed", false)
	vehicle:SetAttribute("Lives", GameConfig.Race.Lives)
	vehicle:SetAttribute("Eliminated", false)
	vehicle:SetAttribute("Invulnerable", false)
	-- Ставит MatchManager, когда заезд решён: турель молчит и сбитые не засчитываются.
	vehicle:SetAttribute("WeaponsLocked", false)

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
				ZombiesDefeated = driver:GetAttribute("RaceZombies") or 0, -- за заезд, как и в StatsService
				Bones = driver:GetAttribute("Bones") or 0,
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
	--
	-- ТЕЛЕПОРТ ИДЁТ ЧЕРЕЗ ЯКОРЬ, И ЭТО ОБЯЗАТЕЛЬНО (2026-08-11, жалоба «сгорела, а
	-- возродилась совсем поломанной»). Двигает машину СЕРВЕР, а физикой владеет КЛИЕНТ —
	-- без этого A-Chassis не едет вовсе, — и водитель на респавне намеренно остаётся в
	-- кресле (см. burnAndRespawn). Голый PivotTo по клиентской сборке расходится: сервер
	-- переставил детали, клиент продолжает считать от своего состояния, а держатся они
	-- ШАРНИРАМИ, А НЕ СВАРКОЙ — подвеску и колёса растягивает, и машина возвращается
	-- разобранной.
	--
	-- В STUDIO ЭТОГО НЕ УВИДЕТЬ: клиент и сервер там в одном процессе, расхождению
	-- неоткуда взяться. Баг живёт только в настоящем клиенте, где между ними сеть.
	--
	-- Порядок ровно тот, что обкатан в PlayerFlow.holdVehicle/releaseVehicleHold (ими же
	-- пользуется MatchManager на отсчёте): заякорить ВСЕ детали — только шасси мало,
	-- колёса на шарнирах докрутятся и сорвут машину с места на разякоривании, — потом
	-- переставить, снять якорь и ВЕРНУТЬ ВЛАДЕНИЕ. Возврат обязателен: якорь сбрасывает
	-- владение на сервер, и без него получим второй известный баг — «машина не едет».
	local function repairAtHome()
		local occupant = (driveSeat :: VehicleSeat).Occupant
		local driver: Player? = nil
		if occupant and occupant.Parent then
			driver = Players:GetPlayerFromCharacter(occupant.Parent)
		end

		local wasAnchored: { [BasePart]: boolean } = {}
		for _, inst in vehicle:GetDescendants() do
			if inst:IsA("BasePart") then
				local part = inst :: BasePart
				wasAnchored[part] = part.Anchored
				part.Anchored = true
			end
		end

		vehicle:PivotTo(homeCFrame)

		for part, anchored in wasAnchored do
			if part.Parent then
				part.Anchored = anchored
			end
		end
		-- Инерцию гасим ПОСЛЕ разякоривания: у заякоренной детали скорости и так нули,
		-- присвоение до снятия ушло бы в никуда.
		for part in wasAnchored do
			if part.Parent and not part.Anchored then
				part.AssemblyLinearVelocity = Vector3.zero
				part.AssemblyAngularVelocity = Vector3.zero
			end
		end
		-- Инерции мало: у AC6 своя силовая обвязка (моторы колёс `#AV`, гироскопы руля),
		-- и пока машина стояла на якоре, серверная копия этих сил осталась взведённой, а
		-- клиентская ушла вперёд — на передаче владения они сходятся рывком и рвут
		-- подвеску. Разбор целиком — над PlayerFlow.quietChassis.
		PlayerFlow.quietChassis(vehicle)

		-- Владение обратно водителю. ТУРЕЛЬ ОТДЕЛЬНО: `Turret` и `GunCradle` — свои
		-- физические сборки (их держат шарниры), якорь снял владение и с них. Не вернуть
		-- — вернётся старая жалоба «точка выстрела запаздывает при поворотах»
		-- (см. PlayerFlow.giveTurretOwnership).
		if driver then
			local owner = driver :: Player
			local function grant()
				pcall(function()
					(driveSeat :: VehicleSeat):SetNetworkOwner(owner)
				end)
				for _, name in { "Turret", "GunCradle", "GunMesh" } do
					local found = vehicle:FindFirstChild(name, true)
					if found and found:IsA("BasePart") and not (found :: BasePart).Anchored then
						pcall(function()
							(found :: BasePart):SetNetworkOwner(owner)
						end)
					end
				end
			end
			grant()
			-- Ретрай с проверкой, как в PlayerFlow: одиночный SetNetworkOwner иногда не
			-- прижимается, пока сборка оседает, и это ровно «стреляет, но не едет».
			task.spawn(function()
				for _ = 1, 12 do
					local current: Player? = nil
					pcall(function()
						current = (driveSeat :: VehicleSeat):GetNetworkOwner()
					end)
					if current == owner then
						return
					end
					grant()
					task.wait(0.1)
				end
				warn(`[VehicleController] владение {vehicle.Name} не вернулось водителю после респавна`)
			end)
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

		-- КАСАНИЕ ЗОМБИ ЛИБО ДАВИТ ЕГО, ЛИБО НЕ ЗНАЧИТ НИЧЕГО. Здоровье машины оно не
		-- трогает (урон только с замаха, см. ZombieAI) и газ больше не глушит: заглохнуть
		-- посреди толпы — это стоять и получать по кузову, ничего не решая. Толпа и так
		-- тормозит машину физически, массой тел.
		local speed = (vehicle:GetAttribute("Speed") :: number?) or 0
		if speed >= GameConfig.Vehicle.CrushSpeedThreshold then
			-- Тот же замок, что и у турели: после решённого заезда сбитый зомби НИКОМУ
			-- не засчитывается, иначе запрет на стрельбу обходился бы бампером. Гибнуть
			-- под колёсами он не перестаёт — меняется только то, кому идёт счёт.
			local killer: Player? = nil
			if not vehicle:GetAttribute("WeaponsLocked") then
				killer = VehicleRegistry.GetPlayerForVehicle(vehicle)
			end
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
		end
	end

	for _, part in vehicle:GetDescendants() do
		if part:IsA("BasePart") then
			part.Touched:Connect(onPartTouched)
		end
	end

	-- // Вахта за целостностью шасси --------------------------------------
	-- ЖАЛОБА 2026-08-27 (планшет): «на старте багги улетела к дереву, передняя
	-- подвеска деформировалась». Первопричину закрывает PlayerFlow (машину отдают
	-- клиенту с покоящейся механикой, см. quietChassis), но само порванное шасси не
	-- лечилось ничем: игрок доигрывал заезд на растянутой машине, и по сути заезд был
	-- для него кончен. Поэтому — сторож: заметил разрыв, собрал машину обратно.
	--
	-- Порог намеренно грубый, и это не небрежность. Колесо держит шарнир, а ход
	-- пружины 2.1..3.3 studs — уехать от сиденья на 8 studs ДАЛЬШЕ, чем было собрано,
	-- у целой машины оно физически не может. Значит срабатывание = механизм правда
	-- разорван, а не «подпрыгнули на кочке». Выдержка в секунду добавлена, чтобы не
	-- ловить одиночный кадр рассинхрона на передаче владения.
	--
	-- Чиним НА МЕСТЕ, а не телепортом на старт: разорвана сборка, а не позиция, и
	-- отбрасывать игрока к решётке посреди круга было бы наказанием за наш же баг.
	-- Поза каждой детали снимается относительно СИДЕНЬЯ один раз, когда A-Chassis
	-- собрал шасси и турель уже приварена, — это и есть эталон «как собрано».
	local TEAR_SLACK = 8
	local TEAR_HOLD = 1
	local TEAR_COOLDOWN = 5

	task.spawn(function()
		local wheels: Instance? = nil
		for _ = 1, 100 do -- ждём, пока AC6 достроит шасси (создаёт `Arm` у каждого колеса)
			local w = vehicle:FindFirstChild("Wheels")
			local any = w and w:FindFirstChildWhichIsA("BasePart")
			if any and any:FindFirstChild("Arm") then
				wheels = w
				break
			end
			task.wait(0.1)
		end
		if not wheels or not vehicle.Parent then
			return
		end
		task.wait(0.6) -- дать PlayerFlow приварить турель: её поза тоже входит в эталон
		applyCollisionGroups(vehicle) -- второй проход: рычаги подвески от AC6 уже на месте

		local seatCF = (driveSeat :: VehicleSeat).CFrame
		local restPose: { [BasePart]: CFrame } = {}
		for _, d in vehicle:GetDescendants() do
			if d:IsA("BasePart") then
				restPose[d :: BasePart] = seatCF:Inverse() * (d :: BasePart).CFrame
			end
		end
		local restDist: { [BasePart]: number } = {}
		for _, w in (wheels :: Instance):GetChildren() do
			if w:IsA("BasePart") then
				restDist[w :: BasePart] = ((w :: BasePart).Position - (driveSeat :: VehicleSeat).Position).Magnitude
			end
		end

		local function rebuild()
			local occupant = (driveSeat :: VehicleSeat).Occupant
			local driver: Player? = nil
			if occupant and occupant.Parent then
				driver = Players:GetPlayerFromCharacter(occupant.Parent)
			end
			local wasAnchored: { [BasePart]: boolean } = {}
			for _, d in vehicle:GetDescendants() do
				if d:IsA("BasePart") then
					wasAnchored[d :: BasePart] = (d :: BasePart).Anchored;
					(d :: BasePart).Anchored = true
				end
			end
			local home = (driveSeat :: VehicleSeat).CFrame
			for part, rel in restPose do
				if part.Parent then
					part.CFrame = home * rel
				end
			end
			for part, anchored in wasAnchored do
				if part.Parent then
					part.Anchored = anchored
				end
			end
			for part in wasAnchored do
				if part.Parent and not part.Anchored then
					part.AssemblyLinearVelocity = Vector3.zero
					part.AssemblyAngularVelocity = Vector3.zero
				end
			end
			PlayerFlow.quietChassis(vehicle)
			if driver then
				pcall(function()
					(driveSeat :: VehicleSeat):SetNetworkOwner(driver :: Player)
				end)
			end
			warn(`[VehicleController] {vehicle.Name}: шасси разорвано — собрано заново на месте.`)
		end

		local tornSince: number? = nil
		local nextRebuildAt = 0
		while vehicle.Parent do
			task.wait(0.5)
			local seat = driveSeat :: VehicleSeat
			-- на якоре (отсчёт, съёмка) и на горящей машине не сторожим: там ничего не едет
			if seat.Anchored or vehicle:GetAttribute("Destroyed") then
				tornSince = nil
				continue
			end
			local torn = false
			for part, dist in restDist do
				if part.Parent and (part.Position - seat.Position).Magnitude > dist + TEAR_SLACK then
					torn = true
					break
				end
			end
			if not torn then
				tornSince = nil
			else
				tornSince = tornSince or os.clock()
				if os.clock() - (tornSince :: number) >= TEAR_HOLD and os.clock() >= nextRebuildAt then
					nextRebuildAt = os.clock() + TEAR_COOLDOWN
					tornSince = nil
					pcall(rebuild)
				end
			end
		end
	end)
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
