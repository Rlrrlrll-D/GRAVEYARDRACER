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

-- // Оси суставов R6 (замерены по C0 шаблона 2026-07-31) ----------------------
-- Каждый Motor6D вращается вокруг осей СВОЕГО C0, а не торса, поэтому знаки тут
-- неочевидны и один раз посчитаны из матриц:
--   Плечи и бёдра: локальный Z смотрит в +X торса у правых и в -X у левых. Значит
--     локальный Z = сагиттальная ось (мах вперёд/назад), и симметричное движение
--     = +theta правому, -theta левому. Положительный угол уводит конечность ВПЕРЁД.
--   Плечи, локальный X: +Z торса у левого, -Z у правого. Это ось «развести руки
--     в стороны», и наружу обе руки уходят при ОТРИЦАТЕЛЬНОМ угле — у обеих.
--   Шея, локальный X = -X торса, поэтому голова запрокидывается НАЗАД при
--     отрицательном угле; локальный Y = +Z торса — это завал головы набок.
--   Root Hip (корень→торс), локальный X = -X торса: отрицательный угол выгибает
--     корпус назад.

-- Поза рук через C0 плеч R6. Ось вращения (локальный Z плеча) = ось X торса,
-- т.е. рука ходит в сагиттальной плоскости (вперёд/вверх/назад). Правой даём
-- +theta, левой -theta — движение выходит симметричным.
local function poseArms(rs: Motor6D, ls: Motor6D, baseR: CFrame, baseL: CFrame, theta: number)
	rs.C0 = baseR * CFrame.Angles(0, 0, theta)
	ls.C0 = baseL * CFrame.Angles(0, 0, -theta)
end

-- Прерывается не только удалением зомби, но и его смертью: атрибут `Dead` ставит
-- PlayDeath, и незавершённый мах обязан отпустить руки, иначе он продолжит тянуть
-- C0 плеч поверх позы трупа и мертвец будет махать из положения лёжа.
local function tweenArms(
	zombie: Model,
	rs: Motor6D,
	ls: Motor6D,
	baseR: CFrame,
	baseL: CFrame,
	fromT: number,
	toT: number,
	duration: number
)
	local t0 = os.clock()
	while os.clock() - t0 < duration do
		if not rs.Parent or not ls.Parent then return end -- зомби удалён посреди маха
		if zombie:GetAttribute("Dead") then return end
		local a = (os.clock() - t0) / duration
		a = a * a * (3 - 2 * a) -- smoothstep
		poseArms(rs, ls, baseR, baseL, fromT + (toT - fromT) * a)
		task.wait()
	end
	if rs.Parent and ls.Parent and not zombie:GetAttribute("Dead") then
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

-- Прокрутить фазу анимации: alpha 0→1 за duration, ease сглаживает. Возвращает
-- false, если зомби исчез посреди фазы — вызывающий на этом заканчивает.
local function phase(zombie: Model, duration: number, ease: (number) -> number, apply: (number) -> ()): boolean
	local t0 = os.clock()
	while true do
		if not zombie.Parent then
			return false
		end
		local raw = (os.clock() - t0) / duration
		if raw >= 1 then
			break
		end
		apply(ease(raw))
		task.wait()
	end
	apply(1)
	return true
end

local function easeSmooth(a: number): number
	return a * a * (3 - 2 * a)
end
local function easeOut(a: number): number -- резкий старт, мягкий конец (рывок)
	return 1 - (1 - a) * (1 - a)
end
local function easeIn(a: number): number -- разгон, как под тяжестью (падение)
	return a * a
end

-- Погружение тела под землю и удаление. Сдвиг СТРОГО в мировой вертикали
-- (`CFrame.new(0,-d,0) * start`, а не `start * ...`): после падения тело лежит
-- повёрнутым почти на 90°, и локальный «вниз» увёл бы труп вбок сквозь поле.
local function sinkUnderground(zombie: Model, depth: number, duration: number)
	for _, part in zombie:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	local start = zombie:GetPivot()
	phase(zombie, duration, easeIn, function(a)
		zombie:PivotTo(CFrame.new(0, -depth * a, 0) * start)
	end)
	zombie:Destroy()
end

-- Короткая анимация погружения в землю, затем удаление зомби.
local function despawn(zombie: Model)
	CollectionService:RemoveTag(zombie, "Zombie")
	sinkUnderground(zombie, 5, 1)
end

-- // СМЕРТЬ: процедурное падение --------------------------------------------
-- Требование юзера — анимация ОБЪЕКТА, не частицы. Поэтому зомби не рассыпается
-- на детали (`BreakJointsOnDeath` выключен в ZombieSpawner) и не улетает тряпкой:
-- он честно оседает и валится через опорную линию стоп, тем же приёмом, что и
-- замах, — позами Motor6D + разворотом всей модели.
--
-- Четыре фазы, и каждая нужна: без рывка не читается ПОПАДАНИЕ, без подламывания
-- ног тело падает доской, без разгона падение выглядит тюленем, а без отскока
-- труп «прилипает» к земле без веса.
local DEATH_HIT_TIME = 0.10 -- рывок от попадания: голова назад, руки врозь
local DEATH_BUCKLE_TIME = 0.30 -- ноги подламываются, тело проседает
local DEATH_FALL_TIME = 0.40 -- падение через стопы (с разгоном)
local DEATH_BOUNCE_TIME = 0.14 -- короткий отскок о землю
local DEATH_LIE_TIME = 1.30 -- сколько труп лежит, прежде чем уйти под землю
local DEATH_SINK_TIME = 1.10
local DEATH_SINK_DEPTH = 6

local DEATH_FALL_ANGLE = math.rad(84) -- добить почти до земли, но не перевернуть
local DEATH_BOUNCE_ANGLE = math.rad(6) -- перелёт, который тут же отыгрывается назад
local DEATH_BOUNCE_LIFT = 0.35 -- на столько тело подскакивает от удара о грунт
local DEATH_BUCKLE_DROP = 0.45 -- на сколько studs просесть, пока подгибаются ноги
local DEATH_PIVOT_LIFT = 1.0 -- ось наклона выше стоп: отвечает за ДУГУ падения, не за высоту
-- На столько миллиметров выше грунта лежит нижняя точка трупа: впритык тело
-- цепляется за неровности террейна и подрагивает, а с зазором лежит спокойно.
local DEATH_REST_CLEARANCE = 0.35

-- Гасим всё, что спорит с позой трупа. `Animate` крутит ходьбу через
-- Motor6D.Transform ПОВЕРХ наших C0, так что мало остановить дорожки — надо
-- отключить сам скрипт и обнулить Transform, иначе мертвец продолжает семенить.
local function silenceAnimation(zombie: Model, humanoid: Humanoid)
	local animate = zombie:FindFirstChild("Animate")
	if animate and animate:IsA("BaseScript") then
		animate.Disabled = true
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			track:Stop(0)
		end
	end
	for _, d in zombie:GetDescendants() do
		if d:IsA("Motor6D") then
			d.Transform = CFrame.identity
		end
	end
end

-- Проигрывает смерть и удаляет тело. Вызывается из ZombieSpawner по Humanoid.Died.
function ZombieAI.PlayDeath(zombie: Model)
	local humanoid = zombie:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		zombie:Destroy()
		return
	end
	zombie:SetAttribute("Dead", true) -- недоигранный замах увидит это и отпустит руки
	CollectionService:RemoveTag(zombie, "Zombie")
	silenceAnimation(zombie, humanoid)

	-- Заморозить физику. Humanoid в состоянии Dead роняет тело сам, и без якорей
	-- он борется с нашей анимацией за позу; заодно труп перестаёт быть препятствием.
	for _, d in zombie:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end

	local torso = zombie:FindFirstChild("Torso")
	local root = zombie:FindFirstChild("HumanoidRootPart")
	local function joint(parent: Instance?, name: string): Motor6D?
		local j = parent and parent:FindFirstChild(name)
		return (j and j:IsA("Motor6D")) and j or nil
	end
	local neck = joint(torso, "Neck")
	local rs, ls = joint(torso, "Right Shoulder"), joint(torso, "Left Shoulder")
	local rh, lh = joint(torso, "Right Hip"), joint(torso, "Left Hip")
	local spine = joint(root, "Root Hip")

	local base: { [Motor6D]: CFrame } = {}
	for _, j in { neck, rs, ls, rh, lh, spine } do
		if j then
			base[j] = j.C0
		end
	end
	local function set(j: Motor6D?, rx: number, ry: number, rz: number)
		if j then
			j.C0 = base[j] * CFrame.Angles(rx, ry, rz)
		end
	end

	-- Куда валиться. Источник урона кладёт `DeathPush` (горизонтальное направление
	-- удара) — пуля толкает от стрелка, машина сбивает по ходу движения. Без
	-- подсказки роняем назад: зомби всегда лицом к машине, падать вперёд ему не с чего.
	local startPivot = zombie:GetPivot()
	local push = (zombie:GetAttribute("DeathPush") :: Vector3?) or -startPivot.LookVector
	push = Vector3.new(push.X, 0, push.Z)
	push = push.Magnitude > 1e-3 and push.Unit
		or Vector3.new(-startPivot.LookVector.X, 0, -startPivot.LookVector.Z).Unit
	-- Ось наклона перпендикулярна направлению падения; поворот вокруг неё уводит
	-- макушку в сторону push (проверено по правилу правой руки для up × push).
	local tipAxis = Vector3.yAxis:Cross(push)

	-- Самая низкая точка тела ПРЯМО СЕЙЧАС, по реальным деталям.
	--
	-- Раньше тут стоял габарит всей модели (`GetBoundingBox`), и юзер справедливо
	-- пожаловался: «зомби падая застывают в воздухе горизонтально». Причина —
	-- габарит снимался ОДИН РАЗ в момент смерти, а зомби нередко умирает с
	-- задранными в замахе руками: коробка выходит на пару studs выше реального
	-- тела, и тело зависало ровно на эту разницу. Плюс коробка модели заведомо
	-- шире содержимого. Считаем по каждой детали отдельно и КАЖДЫЙ КАДР — у R6
	-- их шесть, это дёшево, зато поза и грунт учитываются честно.
	-- Возвращает самую низкую точку тела и её место по горизонтали: под НЕЙ и надо
	-- искать грунт, а не под пивотом — за падение тело уезжает от точки смерти.
	local function lowestNow(): (number, number, number)
		local low, lx, lz = math.huge, startPivot.Position.X, startPivot.Position.Z
		for _, p in zombie:GetDescendants() do
			if p:IsA("BasePart") then
				local cf, half = p.CFrame, p.Size / 2
				local ext = math.abs(cf.RightVector.Y) * half.X
					+ math.abs(cf.UpVector.Y) * half.Y
					+ math.abs(cf.LookVector.Y) * half.Z
				local y = cf.Position.Y - ext
				if y < low then
					low, lx, lz = y, cf.Position.X, cf.Position.Z
				end
			end
		end
		return low, lx, lz
	end

	-- ОСЬ НАКЛОНА — У СТОП, и стопы меряем по реальным деталям.
	--
	-- Юзер: «ощущение, что пивот при падении не в районе ног, а где-то в центре тела».
	-- Так и было: низ брался как `pivot.Y - bbSize.Y/2` по габаритной коробке модели, а
	-- она (а) центрирована по ПИВОТУ, а не по телу, и (б) снимается в момент смерти,
	-- когда у зомби часто задраны в замахе руки — коробка растёт ВВЕРХ, половина её
	-- высоты растёт вместе с ней, и расчётный «низ» уезжал от стоп на эту половину.
	-- Ось выходила то выше, то ниже настоящих ног, и тело крутилось вокруг живота.
	-- Теперь низ — это честная нижняя точка деталей, та же, что и для посадки на грунт.
	local measuredLow = lowestNow()
	local feetY = measuredLow < math.huge and measuredLow or startPivot.Position.Y - 3
	local pivotPoint = Vector3.new(startPivot.Position.X, feetY + DEATH_PIVOT_LIFT, startPivot.Position.Z)

	-- Положение всей модели: поворот на angle вокруг мировой точки pivotPoint
	-- плюс просадка drop по мировой вертикали.
	local function bodyCF(angle: number, drop: number): CFrame
		local spin = CFrame.new(pivotPoint) * CFrame.fromAxisAngle(tipAxis, angle) * CFrame.new(-pivotPoint)
		return CFrame.new(0, -drop, 0) * spin * startPivot
	end

	-- Земля под телом.
	--
	-- Юзер: «зомби зависают в воздухе, не долетая до земли». Раньше грунт брался ОДНИМ
	-- лучом в момент смерти, из точки смерти, и в фильтре исключений стоял только сам
	-- зомби. Но зомби почти всегда умирает ПОД МАШИНОЙ: подсечённое капотом тело в этот
	-- миг лежит на кузове, луч упирался в кузов, и «грунтом» становилась крыша багги —
	-- труп аккуратно укладывался на неё, машина уезжала, и он оставался висеть ровно на
	-- её высоте. Второй случай того же бага — падение со склона или с обочины: тело за
	-- падение уезжает на пару studs вбок, а высота бралась по старому месту.
	--
	-- Поэтому: машины из луча исключены совсем, а грунт ищется КАЖДЫЙ КАДР и под
	-- текущей нижней точкой тела. Луч бьём с запасом сверху и вниз до самого низа карты,
	-- чтобы не промахнуться ни по высоко подброшенному телу, ни по яме.
	-- ГЛАВНОЕ: луч бьём ОТ ЛИЦА ЗОМБИ, группой `Zombies`. Замер 31.07 над первым же
	-- надгробием: луч группой `Default` упирается в камень на Y=6.28, а группой
	-- `Zombies` проходит сквозь него и находит землю на Y=4.02. Декор живёт в группе
	-- `Obstacles`, и она держит машину, но НЕ зомби (Bootstrap: Zombies↔Obstacles =
	-- false) — то есть камень зомби не опора, сквозь него он ходит. А вылезают зомби
	-- ровно у надгробий, поэтому «упор в камень» был не редкостью, а нормой: тело
	-- укладывалось на крышку надгробия и оставалось висеть над землёй на его высоту.
	-- Машины группу не спасают (Zombies↔Vehicles = true), их исключаем списком.
	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Exclude
	groundParams.CollisionGroup = "Zombies"
	local ignore: { Instance } = { zombie }
	for _, v in CollectionService:GetTagged("PlayerVehicle") do
		table.insert(ignore, v)
	end
	groundParams.FilterDescendantsInstances = ignore

	local function groundUnder(x: number, y: number, z: number): number?
		local hit = workspace:Raycast(Vector3.new(x, y + 8, z), Vector3.new(0, -400, 0), groundParams)
		return hit and hit.Position.Y or nil
	end

	-- Досадить тело на грунт после установки позы. `blend` растягивает поправку по
	-- фазе, чтобы тело не дёргалось вверх скачком: при blend=1 низ ложится точно.
	local function settle(blend: number)
		local low, lx, lz = lowestNow()
		if low == math.huge then
			return
		end
		local groundY = groundUnder(lx, low, lz)
		if not groundY then
			return -- под телом пусто (край карты): не дёргаем, просто оставляем как есть
		end
		local restY = groundY + DEATH_REST_CLEARANCE
		zombie:PivotTo(zombie:GetPivot() + Vector3.new(0, (restY - low) * blend, 0))
	end

	playSoundAt(GROWL_SOUND_ID, startPivot.Position, 0.75, 0.5, 0.62) -- предсмертный хрип: ниже и длиннее рыка

	-- 1. РЫВОК: голова запрокидывается, руки вскидываются врозь, корпус выгибает.
	if not phase(zombie, DEATH_HIT_TIME, easeOut, function(a)
		set(neck, -0.55 * a, 0, 0)
		set(spine, -0.30 * a, 0, 0)
		set(rs, -0.85 * a, 0, 1.15 * a)
		set(ls, -0.85 * a, 0, -0.95 * a) -- левая чуть иначе: симметрия читается как робот
	end) then
		return
	end

	-- 2. НОГИ ПОДКОСИЛИСЬ: бёдра складываются вперёд, тело проседает.
	if not phase(zombie, DEATH_BUCKLE_TIME, easeSmooth, function(a)
		set(rh, 0, 0, 0.70 * a)
		set(lh, 0, 0, -0.55 * a)
		set(neck, -0.55 + 0.25 * a, 0.18 * a, 0)
		set(rs, -0.85 + 0.45 * a, 0, 1.15 - 0.55 * a)
		set(ls, -0.85 + 0.45 * a, 0, -0.95 + 0.40 * a)
		zombie:PivotTo(bodyCF(0, DEATH_BUCKLE_DROP * a))
	end) then
		return
	end

	-- 3. ПАДЕНИЕ: с разгоном (easeIn), руки и голова доболтываются следом.
	if not phase(zombie, DEATH_FALL_TIME, easeIn, function(a)
		set(neck, -0.30 - 0.20 * a, 0.18 + 0.22 * a, 0)
		set(rs, -0.40 - 0.50 * a, 0, 0.60 - 0.35 * a)
		set(ls, -0.40 - 0.35 * a, 0, -0.55 + 0.30 * a)
		set(rh, 0, 0, 0.70 - 0.45 * a)
		set(lh, 0, 0, -0.55 + 0.30 * a)
		zombie:PivotTo(bodyCF(DEATH_FALL_ANGLE * a, DEATH_BUCKLE_DROP))
		settle(a) -- к концу падения низ тела ложится ровно на грунт
	end) then
		return
	end

	-- 4. ОТСКОК: перелёт на пару градусов и возврат — вес тела на удар о землю.
	if not phase(zombie, DEATH_BOUNCE_TIME, easeSmooth, function(a)
		local over = math.sin(a * math.pi) -- 0 → 1 → 0
		zombie:PivotTo(bodyCF(DEATH_FALL_ANGLE + DEATH_BOUNCE_ANGLE * over, DEATH_BUCKLE_DROP))
		set(rs, -0.90 + 0.12 * over, 0, 0.25)
		set(neck, -0.50, 0.40 + 0.10 * over, 0)
		settle(1)
		-- отскок: на миг приподнимаем тело над грунтом и тут же роняем обратно
		zombie:PivotTo(zombie:GetPivot() + Vector3.new(0, DEATH_BOUNCE_LIFT * over, 0))
	end) then
		return
	end

	task.wait(DEATH_LIE_TIME)
	if zombie.Parent then
		sinkUnderground(zombie, DEATH_SINK_DEPTH, DEATH_SINK_TIME)
	end
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
		tweenArms(zombie, rs, ls, baseR, baseL, 0, THETA_WIND, WINDUP_TIME)
		tweenArms(zombie, rs, ls, baseR, baseL, THETA_WIND, THETA_STRIKE, STRIKE_TIME)
		task.spawn(function()
			tweenArms(zombie, rs, ls, baseR, baseL, THETA_STRIKE, 0, RECOVER_TIME)
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
					-- ProtectedUntil — тот же авторитет неуязвимости, что и в onPartTouched:
					-- на отсчёт+грейс (и после респавна) укус зомби не проходит.
					local protected = os.clock() < ((vehicle:GetAttribute("ProtectedUntil") :: number?) or 0)
					if stillClose and not vehicle:GetAttribute("Destroyed") and not vehicle:GetAttribute("Invulnerable") and not protected then
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
