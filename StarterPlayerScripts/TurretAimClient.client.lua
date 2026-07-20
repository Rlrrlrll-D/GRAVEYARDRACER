--!strict
-- LocalScript: StarterPlayerScripts.TurretAimClient
--
-- SETUP per vehicle Model:
--   TurretBase (Part, welded/part of the chassis)
--   Turret (Part) connected to TurretBase via a HingeConstraint named
--     "TurretHinge", parented under TurretBase, with:
--       ActuatorType = Servo
--       ServoMaxTorque = large enough to move the turret (e.g. 50000)
--       AngularVelocity = a comfortable turn speed (e.g. 4)
--   Muzzle (Attachment, child of Turret) marking the bullet spawn point.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local Audio = require(ReplicatedStorage:WaitForChild("Audio"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local fireWeapon = remotes:WaitForChild("FireWeapon") :: RemoteEvent
local bulletFired = remotes:WaitForChild("BulletFired") :: RemoteEvent

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local mouse = player:GetMouse()

-- Free Creator Store SFX: "Machine gun shot" (0.22s single shot). Played per
-- bullet on every client, so all players hear each shot positionally.
local GUNSHOT_SOUND_ID = "rbxassetid://88311346538102"

-- Предзагрузка звука выстрела — чтобы первые выстрелы не запаздывали.
task.spawn(function()
	local ContentProvider = game:GetService("ContentProvider")
	local s = Instance.new("Sound")
	s.SoundId = GUNSHOT_SOUND_ID
	pcall(function()
		ContentProvider:PreloadAsync({ s })
	end)
	s:Destroy()
end)

local function findMyVehicle(): Model?
	for _, vehicle in CollectionService:GetTagged("PlayerVehicle") do
		if vehicle:IsA("Model") then
			local seat = vehicle:FindFirstChild("DriveSeat")
			if seat and seat:IsA("VehicleSeat") and seat.Occupant then
				local character = seat.Occupant.Parent
				if character and Players:GetPlayerFromCharacter(character) == player then
					return vehicle
				end
			end
		end
	end
	return nil
end

-- Точка в мире под перекрестием (курсором). mouse.UnitRay учитывает
-- инсет топ-бара правильно (в отличие от ViewportPointToRay+GetMouseLocation,
-- что давало вертикальный сдвиг и промах мимо прицела). Вторым
-- возвращает объект под курсором — чтобы красить крест зелёным на зомби.
local function getMouseHit(excludeVehicle: Model?): (Vector3, Instance?)
	local unitRay = mouse.UnitRay
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local filter = {}
	if excludeVehicle then
		table.insert(filter, excludeVehicle)
	end
	if player.Character then
		table.insert(filter, player.Character)
	end
	raycastParams.FilterDescendantsInstances = filter
	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * GameConfig.Weapon.Range, raycastParams)
	if result then
		return result.Position, result.Instance
	end
	return unitRay.Origin + unitRay.Direction * GameConfig.Weapon.Range, nil
end

local function createTracer(origin: Vector3, hitPosition: Vector3)
	local distance = (hitPosition - origin).Magnitude
	local tracer = Instance.new("Part")
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CanQuery = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = Color3.fromRGB(255, 200, 80)
	tracer.Size = Vector3.new(0.15, 0.15, distance)
	tracer.CFrame = CFrame.new(origin:Lerp(hitPosition, 0.5), hitPosition)
	tracer.Parent = workspace
	Debris:AddItem(tracer, 0.1)
end

local function createMuzzleFlash(origin: Vector3)
	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Ball
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 220, 130)
	flash.Size = Vector3.new(1.1, 1.1, 1.1)
	flash.CFrame = CFrame.new(origin)

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 210, 120)
	light.Brightness = 6
	light.Range = 14
	light.Parent = flash

	flash.Parent = workspace
	Debris:AddItem(flash, 0.05)
end

local function playGunshot(position: Vector3)
	local speaker = Instance.new("Part")
	speaker.Anchored = true
	speaker.CanCollide = false
	speaker.CanQuery = false
	speaker.Transparency = 1
	speaker.Size = Vector3.new(0.2, 0.2, 0.2)
	speaker.CFrame = CFrame.new(position)

	local sound = Instance.new("Sound")
	sound.SoundId = GUNSHOT_SOUND_ID
	sound.Volume = 0.55
	sound.SoundGroup = Audio.SFX
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 8
	sound.RollOffMaxDistance = 220
	sound.PlaybackSpeed = 0.95 + math.random() * 0.12 -- лёгкий разброс, чтобы очередь не звучала механически
	sound.Parent = speaker

	speaker.Parent = workspace
	sound:Play()
	Debris:AddItem(speaker, 1)
end

bulletFired.OnClientEvent:Connect(function(origin: Vector3, hitPosition: Vector3)
	createTracer(origin, hitPosition)
	createMuzzleFlash(origin)
	playGunshot(origin)
end)

-- // Crosshair (виден, пока игрок за рулём; следует за прицелом-мышью) -------
local playerGui = player:WaitForChild("PlayerGui")
local crossGui = Instance.new("ScreenGui")
crossGui.Name = "WeaponCrosshair"
crossGui.ResetOnSpawn = false
crossGui.IgnoreGuiInset = true -- offset == GetMouseLocation == WorldToViewportPoint (проверено: иначе крест ниже цели на инсет)
crossGui.DisplayOrder = 50
crossGui.Enabled = false
crossGui.Parent = playerGui

local reticle = Instance.new("Frame")
reticle.Name = "Reticle"
reticle.AnchorPoint = Vector2.new(0.5, 0.5)
reticle.BackgroundTransparency = 1
reticle.Size = UDim2.fromOffset(30, 30)
reticle.Parent = crossGui

local CROSS_IDLE = Color3.fromRGB(255, 110, 80) -- тёплый, в тон трассеру/вспышке
local CROSS_TARGET = Color3.fromRGB(120, 255, 130) -- зелёный: навёлся на зомби
local crossLines: { Frame } = {}
local function makeCrossLine(name: string): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = CROSS_IDLE
	local stroke = Instance.new("UIStroke") -- тёмная обводка: читается на любом фоне
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 1
	stroke.Transparency = 0.3
	stroke.Parent = f
	f.Parent = reticle
	table.insert(crossLines, f)
	return f
end
do
	local L, T, GAP = 8, 2, 4 -- длина луча, толщина, зазор от центра (компактный крест)
	local top = makeCrossLine("Top")
	top.AnchorPoint = Vector2.new(0.5, 1); top.Position = UDim2.new(0.5, 0, 0.5, -GAP); top.Size = UDim2.fromOffset(T, L)
	local bot = makeCrossLine("Bottom")
	bot.AnchorPoint = Vector2.new(0.5, 0); bot.Position = UDim2.new(0.5, 0, 0.5, GAP); bot.Size = UDim2.fromOffset(T, L)
	local left = makeCrossLine("Left")
	left.AnchorPoint = Vector2.new(1, 0.5); left.Position = UDim2.new(0.5, -GAP, 0.5, 0); left.Size = UDim2.fromOffset(L, T)
	local right = makeCrossLine("Right")
	right.AnchorPoint = Vector2.new(0, 0.5); right.Position = UDim2.new(0.5, GAP, 0.5, 0); right.Size = UDim2.fromOffset(L, T)
	local dot = makeCrossLine("Dot")
	dot.AnchorPoint = Vector2.new(0.5, 0.5); dot.Position = UDim2.new(0.5, 0, 0.5, 0); dot.Size = UDim2.fromOffset(2, 2)
end

-- // Прицел следует за курсором; выстрел идёт в ЭТУ ЖЕ точку под перекрестием.
-- Крест — на точке камера-луча под курсором (стабильно под мышью), а не
-- на луче от дула — иначе крест «плавал» бы при повороте турели.
RunService.RenderStepped:Connect(function()
	local vehicle = findMyVehicle()
	if not vehicle then
		if crossGui.Enabled then
			crossGui.Enabled = false
			UserInputService.MouseIconEnabled = true
		end
		return
	end
	if not crossGui.Enabled then
		crossGui.Enabled = true
		UserInputService.MouseIconEnabled = false -- крест заменяет системный курсор
	end
	local target, hitInst = getMouseHit(vehicle)
	local sp = camera:WorldToViewportPoint(target) -- пара с IgnoreGuiInset=false
	reticle.Visible = sp.Z > 0
	if reticle.Visible then
		reticle.Position = UDim2.fromOffset(sp.X, sp.Y)
		local isZombie = false
		if hitInst then
			local m = hitInst:FindFirstAncestorOfClass("Model")
			isZombie = (m ~= nil) and CollectionService:HasTag(m, "Zombie")
		end
		local col = isZombie and CROSS_TARGET or CROSS_IDLE
		for _, l in crossLines do
			l.BackgroundColor3 = col
		end
	end
end)

-- // Aiming loop — YAW (азимут) + PITCH (возвышение): ствол смотрит точно
-- на курсор, луч не кривой по вертикали. Опора yaw — "вперёд машины".
local AIM_SIGN = 1 -- калибровка yaw (проверено)
local PITCH_SIGN = 1 -- калибровка pitch (если ствол наклоняется в другую сторону — -1)
RunService.RenderStepped:Connect(function()
	local vehicle = findMyVehicle()
	if not vehicle then return end

	local turretBase = vehicle:FindFirstChild("TurretBase") :: BasePart?
	local seat = vehicle:FindFirstChild("DriveSeat") :: BasePart?
	local turret = vehicle:FindFirstChild("Turret") :: BasePart?
	if not (turretBase and seat and turret) then return end

	local yawHinge = turretBase:FindFirstChild("TurretHinge")
	if not (yawHinge and yawHinge:IsA("HingeConstraint")) then return end

	local target = getMouseHit(vehicle)

	-- YAW: знаковый угол вокруг вертикали от "вперёд машины" к цели
	local cf = seat.CFrame.LookVector
	local carFwd = Vector3.new(cf.X, 0, cf.Z)
	if carFwd.Magnitude >= 1e-3 then
		carFwd = carFwd.Unit
		local flat = Vector3.new(target.X - turretBase.Position.X, 0, target.Z - turretBase.Position.Z)
		if flat.Magnitude >= 1e-3 then
			local targetDir = flat.Unit
			local up = Vector3.new(0, 1, 0)
			local angle = math.atan2(up:Dot(carFwd:Cross(targetDir)), carFwd:Dot(targetDir))
			yawHinge.TargetAngle = AIM_SIGN * math.deg(angle)
		end
	end

	-- PITCH: возвышение от центра турели к цели (ствол наклоняется по вертикали)
	local pitchHinge = turret:FindFirstChild("PitchHinge")
	if pitchHinge and pitchHinge:IsA("HingeConstraint") then
		local aimDir = target - turret.Position
		local horiz = math.sqrt(aimDir.X * aimDir.X + aimDir.Z * aimDir.Z)
		local elevation = math.atan2(aimDir.Y, horiz)
		pitchHinge.TargetAngle = PITCH_SIGN * math.deg(elevation)
	end
end)

-- // Firing ------------------------------------------------------------
local lastLocalFire = 0
local firing = false

local function tryFire()
	local vehicle = findMyVehicle()
	if not vehicle then return end

	local muzzle = vehicle:FindFirstChild("Muzzle", true) -- дуло переехало на GunCradle
	if not muzzle or not muzzle:IsA("Attachment") then return end

	local now = os.clock()
	if now - lastLocalFire < 1 / GameConfig.Weapon.FireRate then return end
	lastLocalFire = now

	local origin = (muzzle :: Attachment).WorldPosition
	local direction = (getMouseHit(vehicle) - origin).Unit

	-- ЛОКАЛЬНОЕ ПРЕДСКАЗАНИЕ: трассер/вспышка/звук СРАЗУ у стрелка,
	-- без ожидания сервера (сервер шлёт bulletFired только ОСТАЛЬНЫМ).
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local flt = { vehicle } :: { Instance }
	if player.Character then
		table.insert(flt, player.Character)
	end
	rp.FilterDescendantsInstances = flt
	local res = workspace:Raycast(origin, direction * GameConfig.Weapon.Range, rp)
	local hitPos = res and res.Position or (origin + direction * GameConfig.Weapon.Range)
	createTracer(origin, hitPos)
	createMuzzleFlash(origin)
	playGunshot(origin)

	fireWeapon:FireServer(origin, direction)
end

-- Machine gun: hold the button to keep firing. tryFire self-limits to FireRate.
RunService.RenderStepped:Connect(function()
	if firing then
		tryFire()
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		firing = true
		tryFire()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		firing = false
	end
end)
