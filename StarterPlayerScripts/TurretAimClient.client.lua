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

-- // Прицеливание на сенсоре -------------------------------------------------
-- На телефоне мыши нет. Перекрестие стоит там, куда его подвёл палец, и само
-- никуда не возвращается: иначе целиться, не отпуская газ, было бы нечем.
-- Точка живёт в координатах вьюпорта — ровно тех, что отдаёт WorldToViewportPoint
-- (ниже по ним ставится сам крест), поэтому обратное преобразование к лучу —
-- ViewportPointToRay, и крест с выстрелом сходятся без подгонки.
local function touchMode(): boolean
	return player:GetAttribute("TouchActive") == true
end

local aimPoint: Vector2? = nil -- nil = ещё не водили пальцем, значит центр экрана

local function aimRay(): Ray
	if not touchMode() then
		return mouse.UnitRay
	end
	local vp = camera.ViewportSize
	local p = aimPoint or (vp / 2)
	return camera:ViewportPointToRay(p.X, p.Y)
end

-- Водит прицел ЛЮБОЙ свободный палец, а не только на правой половине: кнопки
-- руля и педалей — GuiObject, касание по ним движок помечает gameProcessed и
-- сюда оно не доходит. Значит вся остальная площадь экрана — прицел, и левше
-- целиться так же удобно, как правше. Ход один к одному: прямое перетаскивание
-- читается лучше любой чувствительности, подобранной на глаз.
local aimTouch: InputObject? = nil
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if touchMode() and not gameProcessed and input.UserInputType == Enum.UserInputType.Touch then
		aimTouch = input
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if input ~= aimTouch then
		return
	end
	local vp = camera.ViewportSize
	local p = aimPoint or (vp / 2)
	aimPoint = Vector2.new(
		math.clamp(p.X + input.Delta.X, 30, vp.X - 30),
		math.clamp(p.Y + input.Delta.Y, 30, vp.Y - 30)
	)
end)
UserInputService.InputEnded:Connect(function(input)
	if input == aimTouch then
		aimTouch = nil
	end
end)

-- Точка в мире под перекрестием (курсором). mouse.UnitRay учитывает
-- инсет топ-бара правильно (в отличие от ViewportPointToRay+GetMouseLocation,
-- что давало вертикальный сдвиг и промах мимо прицела). Вторым
-- возвращает объект под курсором — чтобы красить крест зелёным на зомби.
local function getMouseHit(excludeVehicle: Model?): (Vector3, Instance?)
	local unitRay = aimRay()
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

-- НАЧАЛО ТРАССЕРА ЕДЕТ С ДУЛОМ. Жалоба: «отстаёт точка выхода трассера у ствола,
-- совпадает только когда не движется». Так и было: трассер со вспышкой — АНКОРНЫЕ
-- детали в мировых координатах, поставленные по позиции дула в МОМЕНТ выстрела и
-- живущие 0.1 с. На 80 studs/с ствол за эту десятую уезжает на 8 studs, и начало
-- трассера остаётся висеть позади — стоя на месте расхождения нет вовсе.
-- Поэтому источник теперь передаётся не точкой, а самим дулом (Attachment): пока
-- эффект жив, его начало каждый кадр берётся от текущего положения дула, а дальний
-- конец остаётся там, куда попали. Vector3 тоже принимается — им рисуются чужие
-- выстрелы, прилетевшие ремоутом: чужого дула у нас на руках нет.
type EffectSource = Attachment | Vector3

local function originOf(source: EffectSource): Vector3?
	if typeof(source) == "Vector3" then
		return source
	end
	local a = source :: Attachment
	return a.Parent and a.WorldPosition or nil
end

-- Держим эффект приклеенным к дулу на всё его недолгое время жизни.
local function followMuzzle(source: EffectSource, life: number, place: (Vector3) -> ())
	if typeof(source) == "Vector3" then
		return -- чужой выстрел: следовать не за чем, точка и так статична
	end
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local origin = originOf(source)
		if not origin or os.clock() - t0 >= life then
			conn:Disconnect()
			return
		end
		place(origin)
	end)
end

local TRACER_LIFE = 0.1
local FLASH_LIFE = 0.05

local function createTracer(source: EffectSource, hitPosition: Vector3)
	local start = originOf(source)
	if not start then
		return
	end
	local tracer = Instance.new("Part")
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CanQuery = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = Color3.fromRGB(224, 214, 170) -- кость (был янтарный)
	local function place(origin: Vector3)
		local distance = (hitPosition - origin).Magnitude
		tracer.Size = Vector3.new(0.15, 0.15, distance)
		tracer.CFrame = CFrame.new(origin:Lerp(hitPosition, 0.5), hitPosition)
	end
	place(start)
	tracer.Parent = workspace
	followMuzzle(source, TRACER_LIFE, place)
	Debris:AddItem(tracer, TRACER_LIFE)
end

local function createMuzzleFlash(source: EffectSource)
	local start = originOf(source)
	if not start then
		return
	end
	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Ball
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 220, 130)
	flash.Size = Vector3.new(1.1, 1.1, 1.1)
	flash.CFrame = CFrame.new(start)

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 210, 120)
	light.Brightness = 6
	light.Range = 14
	light.Parent = flash

	flash.Parent = workspace
	followMuzzle(source, FLASH_LIFE, function(origin)
		flash.CFrame = CFrame.new(origin)
	end)
	Debris:AddItem(flash, FLASH_LIFE)
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

-- // Crosshair (виден, пока идёт заезд; следует за прицелом-мышью) -----------
-- ПРИЗНАК ЗАЕЗДА — ВКЛЮЧЁННЫЙ HUD, А НЕ НАЛИЧИЕ МАШИНЫ. Раньше крест зажигался
-- по одному «машина существует», а сервер отпускает её победителю только через
-- RESULTS_SECONDS — уже ПОСЛЕ полноэкранного итога. Крест висел поверх «YOU WIN!»,
-- да ещё и прятал системный курсор. HUD же гасится и в лобби, и на экране итога,
-- и у зрителя, поэтому он тут единственный источник правды.
local playerGui = player:WaitForChild("PlayerGui")
local hudGui: ScreenGui? = nil
task.spawn(function()
	local g = playerGui:WaitForChild("GraveyardHUD", 30)
	if g and g:IsA("ScreenGui") then
		hudGui = g
	end
end)
local function raceOnScreen(): boolean
	local g = hudGui
	return g ~= nil and g.Parent ~= nil and g.Enabled
end

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

local CROSS_IDLE = Color3.fromRGB(224, 214, 170) -- кость (покой); зелёный остаётся на цели
local CROSS_TARGET = Color3.fromRGB(120, 255, 130) -- зелёный: навёлся на зомби
local crossLines: { Frame } = {}
local function makeCrossLine(name: string): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = CROSS_IDLE
	local stroke = Instance.new("UIStroke") -- тёмная обводка: читается на любом фоне
	stroke.Color = Color3.fromRGB(12, 19, 14) -- тёмный мох (была чистая чернота)
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
	-- ДЕВ-ПАНЕЛЬ ЗАБИРАЕТ МЫШЬ СЕБЕ (атрибут ставит NeonTune, только в Studio). Без
	-- этой уступки выходила драка каждый кадр: панель гасила прицел, турель ниже видела
	-- «прицела нет», включала его заново и заодно прятала системный курсор — и так по
	-- кругу. Снаружи это выглядело как «курсора нет» и «всё мигает». Сама турель при
	-- этом продолжает целиться и стрелять, отключён только её захват курсора.
	if player:GetAttribute("DevPanelOpen") then
		if crossGui.Enabled then
			crossGui.Enabled = false
			UserInputService.MouseIconEnabled = true
		end
		return
	end
	local vehicle = findMyVehicle()
	if not vehicle or not raceOnScreen() then
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

-- опция «скорость наводки» (веха 5, эхо PushSettings): множитель скорости серво.
-- 0.5 (дефолт) = заводская скорость шарнира (×1), 0.1 = ×0.2, 1.0 = ×2.
-- Работает: физику своей машины симулирует клиент-владелец, правка AngularSpeed
-- локальна и легальна. Заводское значение кэшируем в атрибуте при первой встрече.
local aimSens = 0.5
remotes:WaitForChild("PushSettings").OnClientEvent:Connect(function(s)
	if type(s) == "table" and type(s.aimSens) == "number" then
		aimSens = math.clamp(s.aimSens, 0.1, 1)
	end
end)

local function applyAimSpeed(hinge: HingeConstraint)
	local base = hinge:GetAttribute("BaseAngularSpeed") :: number?
	if base == nil then
		base = hinge.AngularSpeed
		hinge:SetAttribute("BaseAngularSpeed", base)
	end
	hinge.AngularSpeed = (base :: number) * 2 * aimSens
end
RunService.RenderStepped:Connect(function()
	local vehicle = findMyVehicle()
	if not vehicle then return end

	local turretBase = vehicle:FindFirstChild("TurretBase") :: BasePart?
	local seat = vehicle:FindFirstChild("DriveSeat") :: BasePart?
	local turret = vehicle:FindFirstChild("Turret") :: BasePart?
	if not (turretBase and seat and turret) then return end

	local yawHinge = turretBase:FindFirstChild("TurretHinge")
	if not (yawHinge and yawHinge:IsA("HingeConstraint")) then return end
	applyAimSpeed(yawHinge)

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
		applyAimSpeed(pitchHinge)
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
	-- СВОЙ выстрел рисуем от самого дула, а не от снятой с него точки: на ходу точка
	-- устаревает за первый же кадр (см. комментарий у createTracer).
	createTracer(muzzle :: Attachment, hitPos)
	createMuzzleFlash(muzzle :: Attachment)
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
	-- На сенсоре стреляет ТОЛЬКО гашетка: там касание экрана — это наводка
	-- прицела, и стрельба по каждому касанию высаживала бы очередь на каждый
	-- поворот. На ноутбуке с сенсорным экраном (клавиатура есть, TouchActive нет)
	-- прежнее поведение остаётся.
	if touchMode() then return end
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

-- Гашетка сенсорной раскладки (TouchControls) — через атрибут игрока, тем же
-- путём, что руль и педали доезжают до A-Chassis.
player:GetAttributeChangedSignal("TouchFire"):Connect(function()
	firing = player:GetAttribute("TouchFire") == true
end)
