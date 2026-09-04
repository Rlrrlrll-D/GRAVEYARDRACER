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
	-- // ВАРИАНТ ПАДЕНИЯ --------------------------------------------------------
	-- Жалоба: «каждый раз падают навзничь». Само падение было направленным и
	-- раньше — тело валится в сторону push, — но стреляют почти всегда спереди, а
	-- зомби стоит лицом к машине: направление выходило одно и то же.
	--
	-- Поэтому направление теперь ВЫБИРАЕТСЯ, а не выводится из одного push:
	--   back     — навзничь, как было;
	--   side     — на бок: ось наклона довёрнута на 60-85°, тело ложится боком;
	--   face     — лицом вниз: валимся ПО ходу собственного взгляда;
	--   collapse — ноги подкосились: глубокая просадка на месте, потом завал в
	--              случайную сторону. Самый заметный, поэтому и самый редкий.
	--
	-- Контекст решает, что уместно: сбила машина сзади (push совпадает со взглядом)
	-- — падать лицом вниз естественно, а «навзничь» смотрелось бы неправдой.
	-- Остальное — жребий, но с весами: чаще всё-таки классическое падение назад.
	local facing = Vector3.new(startPivot.LookVector.X, 0, startPivot.LookVector.Z)
	facing = facing.Magnitude > 1e-3 and facing.Unit or push
	local fromBehind = facing:Dot(push) > 0.4 -- толкает В спину: удар прилетел сзади
	local cause = tostring(zombie:GetAttribute("DeathCause") or "")

	local style: string
	local roll = math.random()
	if fromBehind then
		style = if roll < 0.6 then "face" else "side"
	elseif cause == "car" then
		-- Из-под колёс тело выбрасывает: назад или вбок, но не «оседает».
		style = if roll < 0.5 then "back" else "side"
	else
		style = if roll < 0.4 then "back" elseif roll < 0.75 then "side" else "collapse"
	end

	-- Направление опрокидывания под выбранный вариант.
	local tipDir = push
	if style == "face" then
		tipDir = facing
	elseif style == "side" then
		local a = math.rad(60 + math.random() * 25) * (if math.random() < 0.5 then 1 else -1)
		tipDir = (CFrame.Angles(0, a, 0) * push)
	elseif style == "collapse" then
		tipDir = (CFrame.Angles(0, math.random() * math.pi * 2, 0) * push)
	end
	tipDir = Vector3.new(tipDir.X, 0, tipDir.Z)
	tipDir = tipDir.Magnitude > 1e-3 and tipDir.Unit or push
	-- Ось наклона перпендикулярна направлению падения; поворот вокруг неё уводит
	-- макушку в сторону tipDir (проверено по правилу правой руки для up × dir).
	local tipAxis = Vector3.yAxis:Cross(tipDir)

	-- Разброс в мелочах — то, что отличает две смерти одного варианта. Без него
	-- четыре стиля читаются как четыре заранее записанных ролика.
	local speed = 0.85 + math.random() * 0.35 -- множитель длительностей
	local hitTime = DEATH_HIT_TIME * speed
	local buckleTime = DEATH_BUCKLE_TIME * speed * (if style == "collapse" then 1.8 else 1)
	local fallTime = DEATH_FALL_TIME * speed * (if style == "collapse" then 0.75 else 1)
	local bounceTime = DEATH_BOUNCE_TIME * speed
	local fallAngle = DEATH_FALL_ANGLE * (0.94 + math.random() * 0.1)
	local buckleDrop = DEATH_BUCKLE_DROP * (if style == "collapse" then 2.4 else 0.85 + math.random() * 0.4)
	local bounceAngle = DEATH_BOUNCE_ANGLE * (0.6 + math.random() * 0.9)
	local bounceLift = DEATH_BOUNCE_LIFT * (0.6 + math.random() * 0.8)
	-- Доворот вокруг собственной вертикали: он же решает, ляжет тело плашмя или
	-- вполоборота. Копится по ходу падения, а не ставится скачком.
	local twist = math.rad(10 + math.random() * 30) * (if math.random() < 0.5 then 1 else -1)
	if style == "side" then
		twist *= 1.8
	end
	local limb = 0.85 + math.random() * 0.3 -- общий разброс амплитуды рук/головы

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
	-- `turn` — доворот вокруг собственной вертикали ДО опрокидывания: пока тело
	-- стоит, это разворот на месте, а после наклона он же превращается в крен вдоль
	-- корпуса. Отсюда и разница «лёг плашмя» / «лёг вполоборота».
	local function bodyCF(angle: number, drop: number, turn: number?): CFrame
		local spin = CFrame.new(pivotPoint) * CFrame.fromAxisAngle(tipAxis, angle) * CFrame.new(-pivotPoint)
		local stand = startPivot * CFrame.Angles(0, turn or 0, 0)
		return CFrame.new(0, -drop, 0) * spin * stand
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

	-- ЧТО ИМЕННО КЛАДЁМ НА ГРУНТ — ТОРС, а не самую низкую точку тела.
	--
	-- Юзер: «зомби не долетают до земли». Замер лежащего трупа по деталям объяснил:
	--     Right Arm низ +0.35   <- только она и касалась земли
	--     Torso     низ +1.35   <- корпус лежал НА собственной руке
	--     Head      низ +1.56
	--     Left Arm  низ +3.33   <- торчала вверх
	-- Посадка по минимуму ставит на грунт кончик ближайшей конечности, а всё тело
	-- поднимается на её толщину — и висит. Опора у лежащего тела одна осмысленная:
	-- торс. Конечности пусть ложатся вокруг (чуть утонуть краем ладони не страшно,
	-- висеть в воздухе — страшно).
	local torsoPart: BasePart? = (torso and torso:IsA("BasePart")) and torso :: BasePart or nil
	local function restPoint(): (number, number, number)
		if torsoPart then
			local cf, half = torsoPart.CFrame, torsoPart.Size / 2
			local ext = math.abs(cf.RightVector.Y) * half.X
				+ math.abs(cf.UpVector.Y) * half.Y
				+ math.abs(cf.LookVector.Y) * half.Z
			return cf.Position.Y - ext, cf.Position.X, cf.Position.Z
		end
		return lowestNow()
	end

	-- Досадить тело на грунт после установки позы. `blend` растягивает поправку по
	-- фазе, чтобы тело не дёргалось вверх скачком: при blend=1 торс ложится точно.
	local function settle(blend: number)
		local low, lx, lz = restPoint()
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
	if not phase(zombie, hitTime, easeOut, function(a)
		set(neck, -0.55 * limb * a, 0, 0)
		set(spine, -0.30 * limb * a, 0, 0)
		set(rs, -0.85 * limb * a, 0, 1.15 * limb * a)
		set(ls, -0.85 * limb * a, 0, -0.95 * limb * a) -- левая чуть иначе: симметрия читается как робот
	end) then
		return
	end

	-- 2. НОГИ ПОДКОСИЛИСЬ: бёдра складываются вперёд, тело проседает. У варианта
	-- collapse эта фаза длиннее и просадка втрое глубже — тело именно оседает,
	-- а уже потом заваливается.
	if not phase(zombie, buckleTime, easeSmooth, function(a)
		set(rh, 0, 0, 0.70 * a)
		set(lh, 0, 0, -0.55 * a)
		set(neck, -0.55 + 0.25 * a, 0.18 * a, 0)
		set(rs, -0.85 + 0.45 * a, 0, 1.15 - 0.55 * a)
		set(ls, -0.85 + 0.45 * a, 0, -0.95 + 0.40 * a)
		zombie:PivotTo(bodyCF(0, buckleDrop * a, twist * 0.3 * a))
	end) then
		return
	end

	-- 3. ПАДЕНИЕ: с разгоном (easeIn), руки и голова доболтываются следом.
	--
	-- К концу падения конечности СВОДЯТСЯ К ТЕЛУ. Раньше они, наоборот, разводились
	-- (локальный X плеча уходил с -0.40 до -0.90 — это «руки в стороны» ОТНОСИТЕЛЬНО
	-- ТОРСА). Пока тело стоит, «в стороны» — это вбок и незаметно; но падает оно
	-- вокруг мировой оси и часто ложится НА БОК, и тогда та же разводка задирает одну
	-- руку в небо, а вторую загоняет под корпус. Замер: левая рука на +3.33, правая
	-- на +0.35, торс на ней сверху. Теперь к концу падения руки идут вдоль тела, и
	-- лежащий силуэт получается плоским.
	if not phase(zombie, fallTime, easeIn, function(a)
		set(neck, -0.30 - 0.20 * a, (0.18 + 0.22 * a) * limb, 0)
		set(rs, -0.40 + 0.28 * a, 0, (0.60 - 0.45 * a) * limb)
		set(ls, -0.40 + 0.28 * a, 0, (-0.55 + 0.40 * a) * limb)
		set(rh, 0, 0, 0.70 - 0.58 * a)
		set(lh, 0, 0, -0.55 + 0.45 * a)
		zombie:PivotTo(bodyCF(fallAngle * a, buckleDrop, twist * (0.3 + 0.7 * a)))
		settle(a) -- к концу падения низ тела ложится ровно на грунт
	end) then
		return
	end

	-- 4. ОТСКОК: перелёт на пару градусов и возврат — вес тела на удар о землю.
	if not phase(zombie, bounceTime, easeSmooth, function(a)
		local over = math.sin(a * math.pi) -- 0 → 1 → 0
		zombie:PivotTo(bodyCF(fallAngle + bounceAngle * over, buckleDrop, twist))
		-- руки остаются лежать вдоль тела, на отскоке лишь чуть подбрасывает
		set(rs, -0.12 - 0.10 * over, 0, 0.15 * limb)
		set(ls, -0.12 - 0.08 * over, 0, -0.15 * limb)
		set(neck, -0.50, (0.40 + 0.10 * over) * limb, 0)
		settle(1)
		-- отскок: на миг приподнимаем тело над грунтом и тут же роняем обратно
		zombie:PivotTo(zombie:GetPivot() + Vector3.new(0, bounceLift * over, 0))
	end) then
		return
	end

	task.wait(DEATH_LIE_TIME)
	if zombie.Parent then
		sinkUnderground(zombie, DEATH_SINK_DEPTH, DEATH_SINK_TIME)
	end
end

-- // ГАБАРИТ КУЗОВА: ВОКРУГ ЧЕГО ДЕРЖАТСЯ ЗОМБИ ------------------------------
--
-- ЖАЛОБА: «в толпе зомби машину складывает, уехать невозможно». Корень — здесь, в
-- том, ОТ ЧЕГО меряется дистанция.
--
-- Раньше и «догнал», и «дошёл, стой и бей» считались от `DriveSeat.Position`. Но
-- сиденье сидит почти в геометрическом центре багги, а кузов — 8.3 x 12.6 studs.
-- Зомби, упёршийся в БАМПЕР, оказывался от сиденья в 6.3+ studs, то есть условие
-- «дошёл» у него не выполнялось НИКОГДА. Он не останавливался — он до скончания века
-- шёл вперёд на полном ходу, всей силой Humanoid, прямо в кузов. Умножьте на десяток
-- тел с разных сторон: машина стоит в тисках из постоянных боковых сил, а стоит дать
-- газ — эти силы никуда не деваются и складываются с тягой как попало.
--
-- Теперь дистанция меряется до КОРОБКИ КУЗОВА, и по горизонтали: высота не при чём,
-- зомби всё равно ходит по земле.
--
-- Коробку берём у `BuggyBody` — это видимый кузов, и его собственные оси совпадают с
-- машиной. Габарит МОДЕЛИ для этого не годится: pivot шаблона повёрнут на 83°, и
-- `Model:GetBoundingBox()` возвращает косой ящик заметно крупнее самой багги.
type Footprint = { cf: CFrame, hx: number, hy: number, hz: number }

local function vehicleFootprint(vehicle: Model): Footprint?
	local body = vehicle:FindFirstChild("BuggyBody")
	if body and body:IsA("BasePart") then
		local s = (body :: BasePart).Size
		return { cf = (body :: BasePart).CFrame, hx = s.X * 0.5, hy = s.Y * 0.5, hz = s.Z * 0.5 }
	end
	-- Запасной вариант — круг вокруг сиденья по габариту модели. Грубее (зомби встанут
	-- дальше, чем нужно), но безопасно: внутрь машины они всё равно не полезут.
	local seat = vehicle:FindFirstChild("DriveSeat")
	if seat and seat:IsA("BasePart") then
		local ext = vehicle:GetExtentsSize()
		local r = math.max(ext.X, ext.Z) * 0.5
		return { cf = (seat :: BasePart).CFrame, hx = r, hy = r, hz = r }
	end
	return nil
end

-- Расстояние ПО ГОРИЗОНТАЛИ от точки до коробки кузова + точка, где зомби следует
-- стоять (на `pad` от борта) + признак «точка внутри машины».
--
-- Возврат `dist` = 0 означает, что зомби уже в габарите кузова. Тогда `stand` — это
-- ближайший выход наружу по КРАТЧАЙШЕЙ стороне: вылезать через всю длину капота,
-- когда до борта полшага, ему незачем.
local function surfacePoint(fp: Footprint, p: Vector3, pad: number): (number, Vector3, boolean)
	local lp = fp.cf:PointToObjectSpace(p)
	local dx = math.clamp(lp.X, -fp.hx, fp.hx)
	local dz = math.clamp(lp.Z, -fp.hz, fp.hz)
	local ox, oz = lp.X - dx, lp.Z - dz
	local dist = math.sqrt(ox * ox + oz * oz)
	-- «Внутри» — это внутри и по высоте тоже: зомби на дне оврага под мостом, над
	-- которым проехала багги, попадать под выталкивание не должен.
	local inside = dist <= 1e-4 and math.abs(lp.Y) <= fp.hy + 3

	local px, pz = 0, 0
	if dist <= 1e-4 then
		local gx = (fp.hx + pad) * (if lp.X >= 0 then 1 else -1)
		local gz = (fp.hz + pad) * (if lp.Z >= 0 then 1 else -1)
		if math.abs(gx - lp.X) <= math.abs(gz - lp.Z) then
			px, pz = gx, lp.Z
		else
			px, pz = lp.X, gz
		end
	else
		-- (dx,dz) — ближайшая точка НА коробке, (ox,oz) — вектор от неё к зомби.
		-- Отступ откладываем от КОРОБКИ по этому направлению, а не от зомби:
		-- масштаб именно pad/dist, а не (dist+pad)/dist.
		local k = pad / dist
		px, pz = dx + ox * k, dz + oz * k
	end
	return dist, fp.cf:PointToWorldSpace(Vector3.new(px, lp.Y, pz)), inside
end

-- // МЕСТА ВОКРУГ МАШИНЫ ------------------------------------------------------
--
-- ЗАЧЕМ. `surfacePoint` ведёт каждого в БЛИЖАЙШУЮ к нему точку кузова, и все,
-- кто прибежал с одной стороны, вставали друг другу в затылок: бьёт передний,
-- остальные подпирают его спину и с дороги вообще не читаются как толпа.
--
-- Теперь у каждого своё место на кольце вокруг кузова. Слот занимается ОДИН раз
-- и держится, пока зомби жив: если перевыбирать его каждый такт, соседи начнут
-- меняться местами и толпа будет ёрзать.
--
-- Колец два. Внутреннее — на расстоянии удара, внешнее на RING_OUTER_PAD дальше:
-- зомби на карте до 25 (GameConfig.Zombie.MaxZombies), в один ряд вокруг багги
-- они не помещаются, а без второго ряда опоздавшие снова сбились бы в затылок.
local RING_SLOTS = 12 -- мест в одном кольце
local RING_OUTER_PAD = 3.4 -- насколько внешний ряд дальше внутреннего
local RING_CHOICE = 5 -- из скольких ближайших свободных мест выбираем наугад
-- «Я на месте» меряется ПО ГОРИЗОНТАЛИ. С обычным расстоянием в зачёт шла и
-- разница высот (точка кольца лежит на уровне центра кузова, зомби стоит на
-- земле), зомби до места «не доходил» никогда — стоял у борта и не бил.
local SLOT_ARRIVED = 3.0
local SLOT_PATIENCE = 2.5 -- дольше этого к своему месту не пробиваемся, бьём откуда стоим
local ORBIT_PAD = 1.4 -- обход идёт чуть шире стоянки, чтобы не тереться о кузов
local TURN_STEP = math.rad(35) -- на сколько доворачиваемся к машине за такт мышления

-- vehicle → { [slot] = zombie }. Обе таблицы слабые: уехавшая машина и удалённый
-- зомби уходят сами, чистить руками нечего.
local ringOwners: { [Model]: { [number]: Model } } = setmetatable({}, { __mode = "k" }) :: any

-- Место на кольце задаётся долей периметра t (0..1). Индекс слота переводится в
-- долю здесь — и только здесь, чтобы обход кольца и сама точка считались по одной
-- формуле. jitter (своя у каждого тела) сдвигает внутри своей доли, иначе места
-- читались бы как разметка парковки.
local function ringParamOf(index: number, jitter: number): (number, boolean)
	local outer = index > RING_SLOTS
	local slot = if outer then index - RING_SLOTS else index
	-- внешний ряд смещён на полшага: иначе он встал бы ровно за спинами внутреннего
	local t = (slot - 1 + jitter + (if outer then 0.5 else 0)) / RING_SLOTS
	return t % 1, outer
end

-- Точка на периметре прямоугольника (кузов + отступ) по доле t.
local function ringPointAt(fp: Footprint, t: number, pad: number): Vector3
	local ex, ez = fp.hx + pad, fp.hz + pad
	local perim = 4 * (ex + ez)
	local s = (t % 1) * perim
	local x, z
	if s < 2 * ex then
		x, z = -ex + s, ez
	elseif s < 2 * ex + 2 * ez then
		x, z = ex, ez - (s - 2 * ex)
	elseif s < 4 * ex + 2 * ez then
		x, z = ex - (s - 2 * ex - 2 * ez), -ez
	else
		x, z = -ex, -ez + (s - 4 * ex - 2 * ez)
	end
	return fp.cf:PointToWorldSpace(Vector3.new(x, 0, z))
end

local function ringPoint(fp: Footprint, index: number, jitter: number, pad: number): Vector3
	local t, outer = ringParamOf(index, jitter)
	return ringPointAt(fp, t, pad + (if outer then RING_OUTER_PAD else 0))
end

-- Обратное преобразование: на какой доле периметра стоит сам зомби. Нужно, чтобы
-- понять, в какую сторону ОБХОДИТЬ машину — по часовой или против.
local function ringParamAt(fp: Footprint, p: Vector3, pad: number): number
	local lp = fp.cf:PointToObjectSpace(p)
	local ex, ez = fp.hx + pad, fp.hz + pad
	local perim = 4 * (ex + ez)
	local cx = math.clamp(lp.X, -ex, ex)
	local cz = math.clamp(lp.Z, -ez, ez)
	local s
	-- Какая грань ближе, решает не абсолютное расстояние, а доля полуразмера:
	-- кузов длиннее, чем шире, и по абсолютным метрам бок «выигрывал» бы всегда.
	if math.abs(lp.X) / ex >= math.abs(lp.Z) / ez then
		if lp.X > 0 then
			s = 2 * ex + (ez - cz) -- правый борт
		else
			s = 4 * ex + 2 * ez + (cz + ez) -- левый борт
		end
	else
		if lp.Z > 0 then
			s = cx + ex -- нос
		else
			s = 2 * ex + 2 * ez + (ex - cx) -- корма
		end
	end
	return (s / perim) % 1
end

-- Занять место. Возвращает индекс слота либо nil, если все 24 разобраны.
local function claimRingSlot(vehicle: Model, zombie: Model, fp: Footprint, pad: number, jitter: number): number?
	local owners = ringOwners[vehicle]
	if not owners then
		owners = {}
		ringOwners[vehicle] = owners
	end

	local mine: number? = nil
	for slot, holder in owners do
		if holder == zombie then
			mine = slot
		elseif not holder.Parent or holder:GetAttribute("Dead") then
			owners[slot] = nil -- место освободилось: тело удалено или уже труп
		end
	end
	if mine then
		return mine
	end

	-- Выбор — СЛУЧАЙНЫЙ ИЗ БЛИЖАЙШИХ, а не строго ближайший. Строго ближайший
	-- собирал всю толпу на том борту, с которого она прибежала (замер: семеро в
	-- четырёх секторах из двенадцати, все сзади-слева). Чисто случайный из всех
	-- гнал бы зомби через всю машину на пустое место — тоже неправда. Компромисс:
	-- сортируем свободные места по расстоянию и берём наугад одно из RING_CHOICE
	-- ближайших — обход получается коротким, но сторона каждый раз своя.
	local here = zombie:GetPivot().Position
	local free: { { slot: number, dist: number } } = {}
	for slot = 1, RING_SLOTS * 2 do
		if not owners[slot] then
			table.insert(free, { slot = slot, dist = (ringPoint(fp, slot, jitter, pad) - here).Magnitude })
		end
	end
	if #free == 0 then
		return nil
	end
	table.sort(free, function(a, b)
		return a.dist < b.dist
	end)
	local pick = free[math.random(1, math.min(RING_CHOICE, #free))].slot
	owners[pick] = zombie
	return pick
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

-- // ОЧЕРЕДЬ К КУЗОВУ: сколько зомби бьют машину ОДНОВРЕМЕННО ----------------
--
-- Смягчаем именно ТОЛПУ, а не укус. Сила одного покойника не тронута
-- (`AttackDamage` / `AttackCooldown` те же), а вот сумма больше не растёт линейно с
-- числом тел: замер живого заезда показал 14 зомби вокруг стоящей машины = 46 урона
-- в секунду, то есть весь запас в 100 HP за две секунды и все три жизни секунд за
-- семь. Уехать из такого попросту нечем.
--
-- Слот занимается на время перезарядки, поэтому пропускная способность толпы жёстко
-- равна `MaxAttackers * AttackDamage / AttackCooldown` при любом её размере.
-- Оставшиеся без слота не превращаются в истуканов: они так же стоят у борта, рычат
-- и берут слот, едва он освободится, — очередь всё время перемешивается, и со стороны
-- это читается как «бьют по очереди», а не как «половина толпы выключилась».
--
-- Ключи слабые: удалённые машины и зомби уходят вместе со сборкой мусора, чистить
-- вручную нечего.
local attackSlots = (setmetatable({}, { __mode = "k" }) :: any) :: { [Model]: { [Model]: number } }

local function claimAttackSlot(vehicle: Model, zombie: Model): boolean
	local slots = attackSlots[vehicle]
	if not slots then
		slots = (setmetatable({}, { __mode = "k" }) :: any) :: { [Model]: number }
		attackSlots[vehicle] = slots
	end
	local now = os.clock()
	local busy = 0
	for holder, expiry in slots do
		if expiry <= now or not holder.Parent then
			slots[holder] = nil -- отбил своё (или его уже нет) — слот свободен
		else
			busy += 1
		end
	end
	if busy >= GameConfig.Zombie.MaxAttackers then
		return false
	end
	slots[zombie] = now + GameConfig.Zombie.AttackCooldown
	return true
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

	-- Дальность удара — СВОЯ У КАЖДОГО ТЕЛА. Рост зомби случайный (ZombieSpawner), а
	-- вместе с телом растут и руки: с общей константой здоровяк махал бы, не доставая,
	-- а мелкий доставал бы оттуда, куда его кулак заведомо не дотягивается. Атрибут
	-- ставит спавнер; нет атрибута — значит рост обычный.
	local attackRange = (zombie:GetAttribute("AttackRange") :: number?) or GameConfig.Zombie.AttackRange
	local standoff = (zombie:GetAttribute("Standoff") :: number?) or GameConfig.Zombie.Standoff
	-- Своя доля внутри слота: с общим нулём места легли бы ровной разметкой.
	local ringJitter = 0.15 + math.random() * 0.7
	local slotSince = os.clock() -- с какого момента идём к своему месту (см. SLOT_PATIENCE)
	local lastRingGap = 1 -- прошлый разрыв по кольцу: по нему видно, идём мы или буксуем
	local lastAttackAt = 0
	local idleSince = os.clock()
	local nextMoanAt = os.clock() + math.random() * 3 -- редкий протяжный стон при погоне

	-- // ПРЕДОХРАНИТЕЛЬ: ВНУТРИ МАШИНЫ ТЕЛУ НЕ МЕСТО -------------------------
	--
	-- Дистанцию до кузова держит цикл ниже, но въехать в стоящего зомби машина может
	-- быстрее, чем он успеет отойти, — а видимый кузов багги (`BuggyBody`) вообще
	-- CanCollide = false, останавливать тело на подходе физике нечем. Зомби
	-- проваливается ВНУТРЬ и встаёт на тонкие плиты пола: дальше Humanoid честно
	-- пытается стоять и идти на движущейся опоре, упираясь в кресло и дуги. Он весит
	-- сопоставимо со всей багги — вот вам и «непредсказуемая реакция».
	--
	-- Выталкиваем ПЕРЕСТАНОВКОЙ, а не снятием контакта. Соблазн выключить CanCollide
	-- был, но у этого рига стоят на земле ровно торс и корень (руки и ноги в шаблоне
	-- бесконтактные) — сняв контакт с них, мы роняем зомби сквозь планету. Высоту не
	-- трогаем вовсе, двигаем только по горизонтали: ноги уже на грунте, а машина стоит
	-- на той же дороге.
	--
	-- Выдержка в полсекунды — чтобы на ходу это не превратилось в дрожь: пока машина
	-- едет сквозь толпу, тело либо гибнет под колёсами, либо остаётся позади само.
	local lastEvictAt = 0
	local function evict(to: Vector3)
		local now = os.clock()
		if now - lastEvictAt < 0.5 or zombie:GetAttribute("Dead") then
			return
		end
		lastEvictAt = now
		local pivot = zombie:GetPivot()
		zombie:PivotTo(pivot + Vector3.new(to.X - pivot.Position.X, 0, to.Z - pivot.Position.Z))
		if rootPart.Parent then
			rootPart.AssemblyLinearVelocity = Vector3.zero
			rootPart.AssemblyAngularVelocity = Vector3.zero
		end
	end

	while zombie.Parent and humanoid.Health > 0 do
		-- ПАУЗА НА ВРЕМЯ СЪЁМКИ (дев-режим PhotoMode, флаг ставит PhotoModeService и
		-- только в Studio). Анкер держит тело, но не замах: он идёт тайном по Motor6D
		-- плеч, и без этой остановки зомби махал бы рукой прямо в кадре. В живой игре
		-- атрибута не существует — цикл проскакивает проверку и работает как раньше.
		while workspace:GetAttribute("PhotoFreeze") do
			task.wait(0.2)
			if not zombie.Parent then
				return
			end
		end

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

		local bodyDistance = math.huge -- до КУЗОВА, а не до сиденья (см. vehicleFootprint)

		if vehicle and distance <= GameConfig.Zombie.ChaseRadius then
			local driveSeat = vehicle:FindFirstChild("DriveSeat") :: VehicleSeat
			local fp = vehicleFootprint(vehicle)
			local stand = driveSeat and driveSeat.Position or rootPart.Position
			local inside = false
			local atSlot = true -- нет слотов (все заняты) — прежнее поведение
			local ringGap = 0 -- насколько далеко до своего места ПО КОЛЬЦУ (доля периметра)
			if fp then
				bodyDistance, stand, inside = surfacePoint(fp :: Footprint, rootPart.Position, standoff)
				-- ИДЁМ НА СВОЁ МЕСТО, А НЕ В БЛИЖАЙШУЮ ТОЧКУ КУЗОВА.
				if not inside then
					local slot = claimRingSlot(vehicle, zombie, fp :: Footprint, standoff, ringJitter)
					if slot then
						local seatPoint = ringPoint(fp :: Footprint, slot, ringJitter, standoff)
						local flat = Vector3.new(
							seatPoint.X - rootPart.Position.X,
							0,
							seatPoint.Z - rootPart.Position.Z
						).Magnitude
						atSlot = flat <= SLOT_ARRIVED
						stand = seatPoint

						-- ОБХОД, А НЕ НАПРЯМИК. Humanoid ходит по прямой, и зомби,
						-- которому досталось место на том борту, честно шёл В КУЗОВ:
						-- утыкался, буксовал и оставался стоять боком. Поэтому пока
						-- разница по кольцу больше шага, целимся не в само место, а в
						-- СЛЕДУЮЩУЮ точку кольца в нужную сторону — получается обход
						-- машины по дуге. Идём чуть шире стоянки (ORBIT_PAD), чтобы
						-- не тереться о борт на ходу.
						if not atSlot then
							local tSlot = ringParamOf(slot, ringJitter)
							local tMe = ringParamAt(fp :: Footprint, rootPart.Position, standoff)
							local d = (tSlot - tMe + 0.5) % 1 - 0.5 -- знаковая разница по кольцу
							ringGap = math.abs(d)
							if math.abs(d) > 1 / RING_SLOTS and bodyDistance <= 12 then
								local dir = if d >= 0 then 1 else -1
								stand = ringPointAt(
									fp :: Footprint,
									tMe + dir / RING_SLOTS,
									standoff + ORBIT_PAD
								)
							end
						end
					end
				end
			end

			-- ОСТАНАВЛИВАЕМСЯ ТОЛЬКО НА СВОЁМ МЕСТЕ, и это половина всей затеи.
			-- Проверка на одну лишь дистанцию до кузова тормозила зомби там, где он
			-- ДОТЯНУЛСЯ, — то есть у ближнего борта, куда пришли и все остальные.
			-- Пока своё место не занято, продолжаем обходить машину.
			--
			-- ТЕРПЕНИЕ обязательно: в плотной толпе до слота можно не дойти вовсе —
			-- упрёшься в чужие спины и будешь толкаться вечно, ни разу не ударив.
			--
			-- Но считать его глухим таймером нельзя: обход половины машины занимает
			-- пару секунд, и такой таймер обрывал бы обход на полпути — зомби вставал
			-- бы боком там, где его застало. Поэтому терпение тратится, только пока
			-- разрыв по кольцу НЕ СОКРАЩАЕТСЯ: идёшь — иди сколько нужно, встал —
			-- через SLOT_PATIENCE бьём оттуда, где стоим.
			if atSlot then
				slotSince = os.clock()
				lastRingGap = ringGap
			elseif ringGap < lastRingGap - 0.005 then
				lastRingGap = ringGap
				slotSince = os.clock()
			elseif os.clock() - slotSince > SLOT_PATIENCE then
				atSlot = true
			end

			if inside then
				-- Влипли в габарит: наружу, и своим ходом тоже.
				evict(stand)
				humanoid.WalkSpeed = GameConfig.Zombie.WalkSpeed
				humanoid:MoveTo(stand)
			elseif bodyDistance <= attackRange and atSlot then
				-- СТОП — СКОРОСТЬЮ, А НЕ `MoveTo` В СЕБЯ. Прежний приём (`MoveTo` в
				-- собственную позицию) Humanoid отрабатывает как микро-цель: он всё
				-- время «доходит» и промахивается, дрожа на месте, — и всё это время
				-- давит на кузов. Нулевая скорость снимает силу движения совсем.
				humanoid.WalkSpeed = 0

				-- РАЗВОРОТ К МАШИНЕ. Humanoid поворачивает тело по ходу движения, а
				-- на своё место зомби приходит СБОКУ или в обход — и замирает,
				-- глядя вдоль борта («стоят и смотрят в сторону»). Пока он стоит,
				-- Humanoid его не крутит, поэтому доворачиваем сами, по шагу за такт:
				-- рывком на 90° это выглядело бы телепортом головы.
				if driveSeat then
					local to = Vector3.new(
						(driveSeat :: BasePart).Position.X - rootPart.Position.X,
						0,
						(driveSeat :: BasePart).Position.Z - rootPart.Position.Z
					)
					if to.Magnitude > 0.5 then
						local want = CFrame.lookAt(rootPart.Position, rootPart.Position + to.Unit)
						local _, dy = rootPart.CFrame:ToObjectSpace(want):ToEulerAnglesYXZ()
						if math.abs(dy) > math.rad(3) then
							rootPart.CFrame = rootPart.CFrame
								* CFrame.Angles(0, math.clamp(dy, -TURN_STEP, TURN_STEP), 0)
						end
					end
				end

				-- Порядок условий важен: за слотом идём, только когда своя перезарядка
				-- уже вышла, иначе очередь дёргали бы десять раз в секунду впустую.
				-- Не досталось — просто стоим и напираем, попробуем на следующем такте.
				local now = os.clock()
				if now - lastAttackAt >= GameConfig.Zombie.AttackCooldown
					and claimAttackSlot(vehicle, zombie)
				then
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
					local fpNow = vehicle.Parent and vehicleFootprint(vehicle) or nil
					local stillClose = false
					if fpNow and humanoid.Health > 0 then
						local d = select(1, surfacePoint(fpNow :: Footprint, rootPart.Position, 0))
						stillClose = d <= attackRange
					end
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
						if seatNow then
							playSoundAt(HIT_SOUND_ID, (seatNow :: BasePart).Position, 0.65, 0.95, 1.1)
						end
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
				humanoid.WalkSpeed = GameConfig.Zombie.WalkSpeed
				-- Идём не в СИДЕНЬЕ, а в точку у борта: цель снаружи машины, и дойдя
				-- до неё, зомби останавливается сам, а не упирается в кузов.
				humanoid:MoveTo(stand)
				if os.clock() >= nextMoanAt then
					nextMoanAt = os.clock() + 3 + math.random() * 3
					playSoundAt(GROWL_SOUND_ID, rootPart.Position, 0.42, 0.7, 0.85) -- стон: тише и ниже рыка
				end
			end
		else
			humanoid.WalkSpeed = GameConfig.Zombie.WalkSpeed
		end

		-- Шаг мышления. Вдали редкий (25 тел не должны думать каждый кадр), но у самой
		-- машины — частый: на прежних 0.4-0.6с зомби между решениями проходил 4-6 studs,
		-- то есть от «ещё далеко» до «внутри кузова» ровно за один такт. Быстро думают
		-- только те, кто рядом, и их всегда единицы.
		if bodyDistance <= 22 then
			task.wait(0.1 + math.random() * 0.05)
		else
			task.wait(0.4 + math.random() * 0.2)
		end
	end
end

return ZombieAI
