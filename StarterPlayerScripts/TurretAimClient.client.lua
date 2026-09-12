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

-- Слот WEAPON: темп/дальность/дробины/вид выстрела по надетому стволу (атрибут игрока
-- EquippedWeapon); веер дробин — та же функция, что у сервера, от одного seed.
local Weapons = require(ReplicatedStorage:WaitForChild("Weapons"))
local ShotFX = require(ReplicatedStorage:WaitForChild("ShotFX"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local fireWeapon = remotes:WaitForChild("FireWeapon") :: RemoteEvent
local bulletFired = remotes:WaitForChild("BulletFired") :: RemoteEvent

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local mouse = player:GetMouse()

-- Free Creator Store SFX: "Machine gun shot" (0.22s single shot). Played per
-- bullet on every client, so all players hear each shot positionally.
local GUNSHOT_SOUND_ID = "rbxassetid://88311346538102"

-- ОСЕЧКА: сухой щелчок вместо выстрела, когда стрелять уже нельзя (заезд решён,
-- см. WeaponsLocked ниже). Без звука нажатие проваливалось в тишину, и это читалось
-- как «игра зависла», а не как «оружие заперто». Free Creator Store, 0.23с — короче
-- самого выстрела, чтобы удержанная гашетка не превратилась в трещотку.
local DRYFIRE_SOUND_ID = "rbxassetid://72166668675269"
local DRYFIRE_INTERVAL = 0.45 -- реже темпа стрельбы: щелчок должен читаться поштучно

-- Предзагрузка звуков выстрела (всех стволов) — чтобы первые выстрелы не запаздывали.
task.spawn(function()
	local ContentProvider = game:GetService("ContentProvider")
	local list = {}
	local seen = {}
	for _, id in { GUNSHOT_SOUND_ID, DRYFIRE_SOUND_ID } do
		seen[id] = true
	end
	for _, w in Weapons.Stats do
		seen[w.soundId] = true
	end
	for id in seen do
		local snd = Instance.new("Sound")
		snd.SoundId = id
		table.insert(list, snd)
	end
	pcall(function()
		ContentProvider:PreloadAsync(list)
	end)
	for _, snd in list do
		snd:Destroy()
	end
end)

local function myWeapon(): Weapons.Stats
	return Weapons.forPlayer(player)
end

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
-- ПРОТЯЖКА ПАЛЬЦЕМ БОЛЬШЕ НЕ НАВОДИТ (2026-08-11): на сенсоре цель выбирает автонаводка
-- ниже, и getMouseHit до aimRay даже не доходит. Слушатели оставлены живыми ради
-- ForceTouchUI на десктопе — там TouchActive поднят вручную, а мышь есть, — но на
-- настоящем телефоне aimPoint теперь ни на что не влияет.
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

-- // АВТОНАВОДКА НА СЕНСОРЕ ---------------------------------------------------
-- «Как в GTA на телефоне» (2026-08-11, решение юзера). Там вручную не целятся вовсе —
-- игра сама держит цель, и ровно поэтому на ходу вообще можно стрелять.
--
-- У нас та же причина, только жёстче: пальцев ровно два, левый на стрелках руля, правый
-- на газе, а газ, тормоз и гашетка стоят одной колонкой под одним большим пальцем.
-- Третьему пальцу взяться неоткуда, и протяжка для наводки требовала бросить руль или
-- газ. Разбор целиком — в MOBILE_AUDIT.md.
--
-- ЗАХВАТ ДЕРЖИТСЯ, пока цель жива и в радиусе. Без этого турель дёргалась бы между
-- одинаково близкими зомби, а трассер метался по экрану. Перевыбор — не чаще пяти раз в
-- секунду: перебор всех зомби каждый кадр не нужен, они не телепортируются.
local lockedTarget: Model? = nil
local nextPick = 0
local AUTO_PICK_PERIOD = 0.2

local function zombiePoint(z: Model): Vector3?
	local ok, pivot = pcall(function()
		return z:GetPivot()
	end)
	if not ok then
		return nil
	end
	return pivot.Position + Vector3.new(0, 1.5, 0) -- по груди, а не по ногам
end

local function zombieAlive(z: Model): boolean
	if not z.Parent then
		return false
	end
	local hum = z:FindFirstChildWhichIsA("Humanoid")
	return hum == nil or hum.Health > 0
end

local function pickTarget(origin: Vector3): Model?
	local best: Model? = nil
	local bestDist = math.huge
	for _, z in CollectionService:GetTagged("Zombie") do
		if z:IsA("Model") and zombieAlive(z) then
			local p = zombiePoint(z)
			if p then
				local d = (p - origin).Magnitude
				if d < bestDist and d <= myWeapon().range then
					best, bestDist = z, d
				end
			end
		end
	end
	return best
end

-- // ПОКОЙ СТВОЛА ------------------------------------------------------------
-- Жалоба: со старта ствол смотрит в пол. Так и было, и это не сбой наводки:
-- целимся мы в точку ПОД КУРСОРОМ, а курсор в начале заезда стоит там, где его
-- оставили, — обычно в середине экрана, то есть на полотне в двух десятках studs
-- перед бампером. Возвышение к такой точке отрицательное, ствол честно опускается.
--
-- Точка покоя — прямо по ходу машины и НА ВЫСОТЕ САМОЙ ТУРЕЛИ: возвышение выходит
-- нулевым (ствол горизонтально), рыскание — вдоль корпуса. Раньше на сенсоре
-- аналогичная точка бралась от СИДЕНЬЯ, которое ниже турели, и ствол всё равно
-- смотрел чуть под уклон.
local REST_DISTANCE = 90

local function restPoint(vehicle: Model?): Vector3?
	local seat = vehicle and vehicle:FindFirstChild("DriveSeat")
	if not (seat and seat:IsA("BasePart")) then
		return nil
	end
	local turret = vehicle and vehicle:FindFirstChild("Turret", true)
	local origin = (turret and turret:IsA("BasePart")) and (turret :: BasePart).Position
		or (seat :: BasePart).Position
	local fwd = (seat :: BasePart).CFrame.LookVector
	fwd = Vector3.new(fwd.X, 0, fwd.Z)
	if fwd.Magnitude < 1e-3 then
		return nil
	end
	return origin + fwd.Unit * REST_DISTANCE
end

-- Тронул ли игрок наводку в этом заезде. До первого движения мыши (или выстрела)
-- держим ствол в покое; сбрасывается при смене машины — то есть каждый заезд
-- начинается со ствола «вперёд», а не с того, куда целились в прошлом.
local hasAimed = false
UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		local d = input.Delta
		if math.abs(d.X) + math.abs(d.Y) > 0.5 then
			hasAimed = true
		end
	end
end)
UserInputService.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		hasAimed = true
	end
end)

-- Куда смотрит турель на сенсоре: в захваченного зомби, а если целей нет — по ходу
-- машины, чтобы ствол не замирал в случайном положении.
local function autoAim(vehicle: Model?): (Vector3?, Instance?)
	local seat = vehicle and vehicle:FindFirstChild("DriveSeat")
	if not (seat and seat:IsA("BasePart")) then
		return nil, nil
	end
	local origin = (seat :: BasePart).Position

	local locked = lockedTarget
	if not (locked and zombieAlive(locked)) then
		locked = nil
	elseif locked then
		local p = zombiePoint(locked)
		if not p or (p - origin).Magnitude > myWeapon().range then
			locked = nil
		end
	end

	local now = os.clock()
	if not locked and now >= nextPick then
		nextPick = now + AUTO_PICK_PERIOD
		locked = pickTarget(origin)
	end
	lockedTarget = locked

	if locked then
		local p = zombiePoint(locked)
		if p then
			-- вторым отдаём деталь зомби: по ней крест красится зелёным
			return p, locked:FindFirstChildWhichIsA("BasePart", true)
		end
	end
	return restPoint(vehicle) or (origin + (seat :: BasePart).CFrame.LookVector * 80), nil
end

-- Точка в мире под перекрестием (курсором). mouse.UnitRay учитывает
-- инсет топ-бара правильно (в отличие от ViewportPointToRay+GetMouseLocation,
-- что давало вертикальный сдвиг и промах мимо прицела). Вторым
-- возвращает объект под курсором — чтобы красить крест зелёным на зомби.
local function getMouseHit(excludeVehicle: Model?): (Vector3, Instance?)
	if touchMode() then
		local p, inst = autoAim(excludeVehicle)
		if p then
			return p, inst
		end
	end
	-- До первого движения мыши ствол держим вперёд (см. restPoint). Проверка идёт
	-- ПОСЛЕ сенсорной ветки: на телефоне мыши нет и hasAimed не поднимется никогда,
	-- а автонаводка там и так знает, куда смотреть.
	if not hasAimed then
		local rest = restPoint(excludeVehicle)
		if rest then
			return rest, nil
		end
	end
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
	local range = myWeapon().range
	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * range, raycastParams)
	if result then
		return result.Position, result.Instance
	end
	return unitRay.Origin + unitRay.Direction * range, nil
end

-- Трассер/вспышка/звук — ReplicatedStorage.ShotFX (вынесено 2026-09-12: тем же рисует
-- оружейная песочница гаража). Осечка — там же, dryFire.
local function playDryFire(position: Vector3)
	ShotFX.dryFire(position, DRYFIRE_SOUND_ID)
end

-- Чужой выстрел: список точек попадания (по дробине на луч) и id ствола стрелка.
bulletFired.OnClientEvent:Connect(function(origin: Vector3, hits: unknown, weaponId: unknown)
	local stats = Weapons.get(weaponId)
	local list: { Vector3 } = {}
	if typeof(hits) == "Vector3" then
		list[1] = hits :: Vector3
	elseif type(hits) == "table" then
		for _, h in hits :: { Vector3 } do
			if typeof(h) == "Vector3" then
				table.insert(list, h)
			end
		end
	end
	ShotFX.fire(origin, list, stats)
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
-- ФОТО-РЕЖИМ ГЛУШИТ ТУРЕЛЬ ЦЕЛИКОМ. Флаг ставит PhotoMode на входе и снимает на выходе
-- (атрибут, а не _G: тем же мостом до A-Chassis доезжает сенсорное управление). Без него
-- в режиме съёмки ствол ездил бы за мышью, которой водят камеру, а левая кнопка стреляла
-- бы прямо в кадр — с трассером и вспышкой. Наводку глушим тоже, а не только огонь:
-- турель должна ЗАМЕРЕТЬ в том положении, в каком её застали, иначе кадр не выставить.
local function photoMode(): boolean
	return player:GetAttribute("PhotoMode") == true
end

-- Смена машины = новый заезд: ствол снова смотрит вперёд, пока игрок не тронет мышь.
local lastAimVehicle: Model? = nil

RunService.RenderStepped:Connect(function()
	if photoMode() then return end

	local vehicle = findMyVehicle()
	if not vehicle then return end
	if vehicle ~= lastAimVehicle then
		lastAimVehicle = vehicle
		hasAimed = false
	end

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
local lastDryFire = 0
local firing = false

local function tryFire()
	local vehicle = findMyVehicle()
	if not vehicle then return end
	-- ЗАЕЗД РЕШЁН — НЕ СТРЕЛЯЕМ, НО И НЕ МОЛЧИМ. Замок ставит сервер
	-- (MatchManager.runResults), он же его и проверяет, так что обойти эту строку
	-- бесполезно. Но выстрел рисуется ПРЕДСКАЗАНИЕМ, до ответа сервера: без проверки
	-- проигравший на экране итогов видел бы трассеры и слышал очередь, по которой
	-- никто не умирает. Вместо этого — сухой щелчок осечки: понятно, что оружие
	-- заперто, а не что игра перестала отвечать.
	if vehicle:GetAttribute("WeaponsLocked") then
		local nowLocked = os.clock()
		if nowLocked - lastDryFire >= DRYFIRE_INTERVAL then
			lastDryFire = nowLocked
			local m = vehicle:FindFirstChild("Muzzle", true)
			local at = (m and m:IsA("Attachment")) and (m :: Attachment).WorldPosition or vehicle:GetPivot().Position
			playDryFire(at)
		end
		return
	end

	local muzzle = vehicle:FindFirstChild("Muzzle", true) -- дуло переехало на GunCradle
	if not muzzle or not muzzle:IsA("Attachment") then return end

	local stats = myWeapon()
	local now = os.clock()
	if now - lastLocalFire < 1 / stats.fireRate then return end
	lastLocalFire = now

	local origin = (muzzle :: Attachment).WorldPosition
	local direction = (getMouseHit(vehicle) - origin).Unit
	local seed = math.random(1, 1073741824) -- веер дробин: сервер разложит так же

	-- ЛОКАЛЬНОЕ ПРЕДСКАЗАНИЕ: трассер/вспышка/звук СРАЗУ у стрелка,
	-- без ожидания сервера (сервер шлёт bulletFired только ОСТАЛЬНЫМ).
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local flt = { vehicle } :: { Instance }
	if player.Character then
		table.insert(flt, player.Character)
	end
	rp.FilterDescendantsInstances = flt
	-- СВОЙ выстрел рисуем от самого дула, а не от снятой с него точки: на ходу точка
	-- устаревает за первый же кадр (см. комментарий в ShotFX).
	local hits = {}
	for _, dir in Weapons.pelletDirections(direction, stats, seed) do
		local res = workspace:Raycast(origin, dir * stats.range, rp)
		table.insert(hits, res and res.Position or (origin + dir * stats.range))
	end
	ShotFX.fire(muzzle :: Attachment, hits, stats)

	fireWeapon:FireServer(origin, direction, seed)
end

-- Machine gun: hold the button to keep firing. tryFire self-limits to FireRate.
RunService.RenderStepped:Connect(function()
	if firing then
		tryFire()
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if photoMode() then return end -- в режиме съёмки левая кнопка возит ползунки панели
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
