--!strict
-- ModuleScript: ServerScriptService.ZombieAI
-- Runs the chase/attack behaviour for a single zombie. ZombieSpawner calls
-- task.spawn(ZombieAI.Run, zombie); the function loops internally until the
-- zombie's Humanoid dies or is removed from the world.
--
-- OPTIONAL per-template setup: add a child Animation instance named
-- "AttackAnimation" (with a valid AnimationId) to ZombieTemplate for the
-- attack pose to play.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local cameraShake = remotes:WaitForChild("CameraShake") :: RemoteEvent

-- Free Creator Store SFX (оба проверены на загрузку в этом плейсе).
local GROWL_SOUND_ID = "rbxassetid://121066883602737" -- Roblox Classic Zombie Growl (~1.2с) — рык при замахе
local HIT_SOUND_ID = "rbxassetid://9116771817"        -- Metal Pops Denting Car (~1.5с) — лязг по кузову

local IDLE_DESPAWN_SECONDS = 20 -- без цели дольше этого — зомби уходит под землю

-- // Замах (wind-up): зомби заносит руки над головой, затем резко бьёт вниз.
-- Урон наносится в НИЖНЕЙ точке маха, так что у игрока есть окно уехать.
local WINDUP_TIME = 0.45   -- сек: занос рук вверх/над головой
local STRIKE_TIME = 0.12   -- сек: резкий мах вниз (в конце — момент удара)
local RECOVER_TIME = 0.25  -- сек: плавный возврат рук в нейтраль
local THETA_WIND = 2.60    -- рад (~149°): руки высоко и назад — замах
local THETA_STRIKE = -0.70 -- рад (~-40°): руки вниз-вперёд (удар по машине). Полный
-- мах замах→удар — около 190° через вертикаль: рубящий удар сверху.

-- Поза рук через C0 плеч R6. Ось вращения (локальный Z плеча) = ось X торса,
-- т.е. рука ходит в сагиттальной плоскости (вперёд/вверх/назад). Правой даём
-- +theta, левой -theta — движение выходит симметричным.
local function poseArms(rs: Motor6D, ls: Motor6D, baseR: CFrame, baseL: CFrame, theta: number)
	rs.C0 = baseR * CFrame.Angles(0, 0, theta)
	ls.C0 = baseL * CFrame.Angles(0, 0, -theta)
end

local function tweenArms(rs: Motor6D, ls: Motor6D, baseR: CFrame, baseL: CFrame, fromT: number, toT: number, duration: number)
	local t0 = os.clock()
	while os.clock() - t0 < duration do
		if not rs.Parent or not ls.Parent then return end -- зомби удалён посреди маха
		local a = (os.clock() - t0) / duration
		a = a * a * (3 - 2 * a) -- smoothstep
		poseArms(rs, ls, baseR, baseL, fromT + (toT - fromT) * a)
		task.wait()
	end
	if rs.Parent and ls.Parent then
		poseArms(rs, ls, baseR, baseL, toT)
	end
end

-- Разовый позиционный звук: временный невидимый динамик у точки + Debris-уборка.
-- Серверный Sound реплицируется — слышат все клиенты рядом.
local function playSoundAt(soundId: string, position: Vector3, volume: number, minPitch: number, maxPitch: number)
	local speaker = Instance.new("Part")
	speaker.Anchored = true
	speaker.CanCollide = false
	speaker.CanQuery = false
	speaker.CanTouch = false
	speaker.Transparency = 1
	speaker.Size = Vector3.new(0.2, 0.2, 0.2)
	speaker.CFrame = CFrame.new(position)

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 8
	sound.RollOffMaxDistance = 160
	sound.PlaybackSpeed = minPitch + math.random() * (maxPitch - minPitch)
	sound.Parent = speaker

	speaker.Parent = workspace
	sound:Play()
	Debris:AddItem(speaker, 4)
end

local ZombieAI = {}

-- Короткая анимация погружения в землю, затем удаление зомби.
local function despawn(zombie: Model)
	CollectionService:RemoveTag(zombie, "Zombie")
	for _, part in zombie:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	local start = zombie:GetPivot()
	for t = 0.05, 1, 0.05 do
		zombie:PivotTo(start * CFrame.new(0, -5 * t, 0))
		task.wait(0.05)
	end
	zombie:Destroy()
end

local function findNearestVehicle(position: Vector3): (Model?, number)
	local nearest: Model? = nil
	local nearestDistance = math.huge

	for _, vehicle in CollectionService:GetTagged("PlayerVehicle") do
		if vehicle:IsA("Model") then
			local driveSeat = vehicle:FindFirstChild("DriveSeat")
			if driveSeat and driveSeat:IsA("VehicleSeat") and driveSeat.Occupant then
				local distance = (driveSeat.Position - position).Magnitude
				if distance < nearestDistance then
					nearest = vehicle
					nearestDistance = distance
				end
			end
		end
	end

	return nearest, nearestDistance
end

function ZombieAI.Run(zombie: Model)
	local humanoid = zombie:FindFirstChildOfClass("Humanoid")
	local rootPart = zombie:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not rootPart then
		warn(`[ZombieAI] {zombie.Name} is missing Humanoid or HumanoidRootPart.`)
		return
	end

	humanoid.WalkSpeed = GameConfig.Zombie.WalkSpeed

	-- Плечевые сочленения R6 для процедурного замаха. У нестандартного рига
	-- их может не быть — тогда playSwing ничего не делает и бьём как раньше.
	local rShoulder: Motor6D? = nil
	local lShoulder: Motor6D? = nil
	local torso = zombie:FindFirstChild("Torso")
	if torso then
		local r = torso:FindFirstChild("Right Shoulder")
		local l = torso:FindFirstChild("Left Shoulder")
		if r and r:IsA("Motor6D") then rShoulder = r end
		if l and l:IsA("Motor6D") then lShoulder = l end
	end
	local baseR = rShoulder and rShoulder.C0 or CFrame.identity
	local baseL = lShoulder and lShoulder.C0 or CFrame.identity

	-- Проигрывает замах (руки вверх) + резкий удар вниз. Блокирует ~0.6с;
	-- урон вызывающий наносит ПОСЛЕ — в нижней точке удара. Возврат рук в
	-- нейтраль идёт фоном, чтобы не задерживать цикл ИИ.
	local function playSwing()
		if not (rShoulder and lShoulder) then return end
		local rs, ls = rShoulder, lShoulder
		tweenArms(rs, ls, baseR, baseL, 0, THETA_WIND, WINDUP_TIME)
		tweenArms(rs, ls, baseR, baseL, THETA_WIND, THETA_STRIKE, STRIKE_TIME)
		task.spawn(function()
			tweenArms(rs, ls, baseR, baseL, THETA_STRIKE, 0, RECOVER_TIME)
		end)
	end

	local attackTrack: AnimationTrack? = nil
	local attackAnimation = zombie:FindFirstChild("AttackAnimation")
	if attackAnimation and attackAnimation:IsA("Animation") then
		local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
		attackTrack = animator:LoadAnimation(attackAnimation)
	end

	local lastAttackAt = 0
	local idleSince = os.clock()
	local nextMoanAt = os.clock() + math.random() * 3 -- редкий протяжный стон при погоне

	while zombie.Parent and humanoid.Health > 0 do
		local vehicle, distance = findNearestVehicle(rootPart.Position)

		if not vehicle or distance > GameConfig.Zombie.ChaseRadius then
			-- цели нет: постояли — и обратно под землю
			if os.clock() - idleSince >= IDLE_DESPAWN_SECONDS then
				despawn(zombie)
				return
			end
		else
			idleSince = os.clock()
		end

		if vehicle and distance <= GameConfig.Zombie.ChaseRadius then
			local driveSeat = vehicle:FindFirstChild("DriveSeat") :: VehicleSeat

			if distance <= GameConfig.Zombie.AttackRange then
				humanoid:MoveTo(rootPart.Position) -- stop moving

				local now = os.clock()
				if now - lastAttackAt >= GameConfig.Zombie.AttackCooldown then
					lastAttackAt = now

					if attackTrack then
						attackTrack:Play()
					end

					-- рык-телеграф в начале замаха (позиционный, слышат все рядом)
					playSoundAt(GROWL_SOUND_ID, rootPart.Position, 0.7, 0.9, 1.12)

					-- ЗАМАХ: руки вверх → резкий мах вниз. Урон — только в нижней
					-- точке удара и только если машина ещё в радиусе (уехал — промах).
					playSwing()

					local seatNow = vehicle:FindFirstChild("DriveSeat") :: BasePart?
					local stillClose = seatNow ~= nil
						and (seatNow.Position - rootPart.Position).Magnitude <= GameConfig.Zombie.AttackRange
					if stillClose and not vehicle:GetAttribute("Destroyed") and not vehicle:GetAttribute("Invulnerable") then
						local health = (vehicle:GetAttribute("Health") :: number?) or GameConfig.Vehicle.MaxHealth
						health = math.max(0, health - GameConfig.Zombie.AttackDamage)
						vehicle:SetAttribute("Health", health)
						if health <= 0 then
							vehicle:SetAttribute("Destroyed", true)
						end

						-- ФИДБЕК УДАРА: лязг по кузову + лёгкая тряска камеры водителю
						playSoundAt(HIT_SOUND_ID, (seatNow :: BasePart).Position, 0.65, 0.95, 1.1)
						local occupant = driveSeat and driveSeat.Occupant
						if occupant then
							local driver = Players:GetPlayerFromCharacter(occupant.Parent)
							if driver then
								cameraShake:FireClient(driver, 0.32, 0.22)
							end
						end
					end
				end
			else
				humanoid:MoveTo(driveSeat.Position)
				if os.clock() >= nextMoanAt then
					nextMoanAt = os.clock() + 3 + math.random() * 3
					playSoundAt(GROWL_SOUND_ID, rootPart.Position, 0.42, 0.7, 0.85) -- стон: тише и ниже рыка
				end
			end
		end

		-- Stagger updates across zombies so 25 of them don't all think every frame.
		task.wait(0.4 + math.random() * 0.2)
	end
end

return ZombieAI
