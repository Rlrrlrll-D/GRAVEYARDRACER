--!strict
-- LocalScript: StarterPlayerScripts.BatFX
-- Рисует летучих мышей по команде BatManager (BatScare). Клиент-онли: клоны
-- живут только у зрителя и не реплицируются. Ассет — ReplicatedStorage.Assets.Bat
-- (одиночный MeshPart "Body", из стора: model 9372173692).
--
-- ПУЛ ВМЕСТО КЛОНИРОВАНИЯ НА ЛЕТУ: раньше каждый рой делал 18-26 `template:Clone()`
-- прямо в кадре события, плюс меш и звук грузились при первом показе. Зоны
-- скримеров стоят в фиксированных точках трассы (MapLayout.ScareZones), поэтому
-- фриз повторялся на одном и том же участке каждый круг. Теперь мыши клонируются
-- ОДИН раз при загрузке (пока игрок под заставкой) и переиспользуются, а меш со
-- звуком прогреваются через ContentProvider.
--
-- РОЙ ЛЕТИТ В ЛИЦО: цель — камера игрока, а не «вверх врассыпную». Мышь идёт от
-- точки вылета к своему смещению у лица (в ПРОСТРАНСТВЕ КАМЕРЫ, поэтому на
-- скорости она не отстаёт), за 0.13-0.22с накрывает экран и на 190 studs/с уходит
-- ЗА игрока. Никакого затухания у роя нет — иначе весь смысл скримера теряется.
-- Что ломало эффект и починено: односторонние полигоны меша (в упор было видно
-- «скелет» изнутри оболочки — DoubleSided), подмена меша низкополи-болванкой
-- (RenderFidelity), перехват летящей мыши из пула («долетела и вернулась») и
-- подлезание к камере вплотную (теперь экран накрывает РАЗМЕР мыши, а не близость).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")
local player = game:GetService("Players").LocalPlayer

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local batScare = Net.get(Net.Events.BatScare)

-- ЗВУК СКРИМЕРА (юзер: «сопроводи вылет мышей на скримере каким-то соответствующим
-- звуком»). Звук был и раньше, но один слой и не тот: «Creature Wings 24» — ровный
-- шелест крыльев с описанием «bat OR flying insect», под рой в лицо он читался как
-- шорох, а не как испуг. Теперь два слоя из той же библиотеки ProSoundEffects:
--   WINGS  — «Bat Noises, Bursts of Wings Flapping, Fast Aways» (2.6с): залп крыльев
--            целой колонии, а не одиночный взмах;
--   SQUEAL — «Mouse Vocal, Rapid Chatter, Squeaky, Shrill» (2.0с): собственно визг,
--            он и пугает. Задран по высоте — иначе слышно крысу, а не летучую мышь.
-- Пустая строка у любого из двух = этот слой молчит.
local WINGS_ID = "rbxassetid://9125386815"
local SQUEAL_ID = "rbxassetid://9117009021"
local POOL_SIZE = 48 -- рой (до 34) + эмбиент + запас: занятую мышь НИКОГДА не отбираем
local PARK = Vector3.new(0, -900, 0) -- «гараж» простаивающих клонов, под картой
local BAT_SCALE = 2.2 -- мышь крупнее: экран накрывает размером, а не подлезанием к камере

-- опция «скримеры» (обновляется из PushSettings); по умолчанию включена
local jumpscaresOn = true
local remotes = ReplicatedStorage:WaitForChild("Remotes")
remotes:WaitForChild("PushSettings").OnClientEvent:Connect(function(s)
	if type(s) == "table" and type(s.jumpscares) == "boolean" then
		jumpscaresOn = s.jumpscares
	end
end)

local template = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Bat")

-- локальная папка для клонов (не реплицируется, легко чистить)
local folder = Instance.new("Folder")
folder.Name = "BatFX"
folder.Parent = workspace.CurrentCamera

local wings = Instance.new("Sound")
wings.SoundId = WINGS_ID
wings.Volume = 1
wings.Parent = SoundService

local squeal = Instance.new("Sound")
squeal.SoundId = SQUEAL_ID
squeal.Volume = 0.85
squeal.Parent = SoundService

-- Части модели вместе с корнем (шаблон может быть и Model, и одиночным MeshPart).
local function partsOf(inst: Instance): { BasePart }
	local parts: { BasePart } = {}
	if inst:IsA("BasePart") then
		table.insert(parts, inst)
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	return parts
end

type Bat = {
	inst: PVInstance,
	parts: { BasePart },
	busy: boolean,
	-- параметры текущего вылета
	swarm: boolean,
	start: Vector3,
	offset: Vector3, -- цель В ПРОСТРАНСТВЕ КАМЕРЫ (рой) — держит прицел на лице
	dir: Vector3, -- курс (эмбиент) / последний курс перед проносом (рой)
	speed: number,
	delay: number, -- рой прилетает волной, а не пачкой в один кадр
	flight: number, -- сколько секунд до лица
	life: number,
	t0: number,
	phase: number,
}

local pool: { Bat } = {}
-- Пока идёт холостой прогон стаи (см. warmSwarm), общий шаг мышей не трогает пул:
-- иначе он увидит нулевой `t0`, решит, что вылет давно кончился, и запаркует их
-- обратно ещё до того, как кадр успеет их отрисовать.
local warming = false

local function park(bat: Bat)
	bat.busy = false
	for _, p in bat.parts do
		p.LocalTransparencyModifier = 1
	end
	bat.inst:PivotTo(CFrame.new(PARK))
end

local function newBat(): Bat
	local inst = template:Clone()
	local parts = partsOf(inst)
	for _, p in parts do
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		-- ПОЧЕМУ МЫШЬ «СКЕЛЕТИЛАСЬ». Ассет — MeshPart 3×1.5×0.5 с DoubleSided=false.
		-- Когда он проходит в упор мимо камеры, зритель смотрит СКВОЗЬ односторонние
		-- полигоны внутрь пустой оболочки: видно «рёбра» и дыры, то есть скелет.
		-- Двусторонние полигоны это убирают, RenderFidelity держит меш от подмены
		-- низкополи-болванкой, а сам масштаб (см. BAT_SCALE) позволяет не подлезать
		-- к камере вплотную — экран накрывает размер, а не близость.
		if p:IsA("MeshPart") then
			pcall(function()
				p.RenderFidelity = Enum.RenderFidelity.Precise
			end)
			pcall(function()
				p.DoubleSided = true
			end)
		end
		p.Size = p.Size * BAT_SCALE
	end
	inst.Parent = folder
	local bat: Bat = {
		inst = inst :: PVInstance,
		parts = parts,
		busy = false,
		swarm = false,
		start = PARK,
		offset = Vector3.zero,
		dir = Vector3.xAxis,
		speed = 0,
		delay = 0,
		flight = 1,
		life = 1,
		t0 = 0,
		phase = 0,
	}
	park(bat)
	return bat
end

-- ХОЛОСТОЙ ПРОГОН СТАИ. Профайлер (2026-07-30) поймал фриз с поимённой подписью:
--   [РЫВОК 202 мс] отрисовка 189 @ (260,138) | ВПЕРВЫЕ В КАДРЕ: Camera×28
--   [РЫВОК 210 мс] отрисовка 198 @ (261,169) | ВПЕРВЫЕ В КАДРЕ: Camera×28
-- 28 мышей (пул живёт в папке внутри CurrentCamera, отсюда имя «Camera») впервые
-- попали в кадр — и оба кадра целиком ушли в отрисовку. `ContentProvider` тут не
-- помогает: он тянет ассет по сети, а строится меш при первой ОТРИСОВКЕ, причём
-- уровень детализации движок выбирает по размеру объекта на экране. Эмбиентные
-- одиночки этого не оплачивают — они пролетают далеко и мелко; рой же приходит В
-- УПОР и накрывает экран, то есть требует самый подробный уровень.
-- Поэтому один раз проводим стаю перед камерой прямо под заставкой: там экран закрыт
-- блюром и тайтлом, а в заезде первый рой уже ничего не строит. Позиции берём те же,
-- что у настоящего вылета (диск ~8 studs в 5 studs перед камерой).
local function warmSwarm()
	local camera = workspace.CurrentCamera
	if not camera or #pool == 0 then
		return
	end
	-- Стаю мы рисуем НА ЭКРАНЕ — иначе движку нечего строить.
	-- Ждём ШТОРКУ прогрева (её вешает `DecorPreload` — непрозрачная панель под меню,
	-- закрывающая 3D, чтобы прогон камеры и вылет стаи не мельтешили на заставке).
	-- Именно ждём, а не проверяем однократно: при разовой проверке прогрев проигрывал
	-- гонку скриптов и молча пропускался. У зрителя, зашедшего посреди заезда, шторки
	-- нет — он прогрев пропустит и заплатит за первый рой один раз.
	local covered = false
	local deadline = os.clock() + 10
	while os.clock() < deadline do
		if player:GetAttribute("WarmupCurtain") == true then
			covered = true
			break
		end
		task.wait(0.2)
	end
	if not covered then
		return
	end
	warming = true
	local n = math.min(#pool, 32)
	for i = 1, n do
		local bat = pool[i]
		local ang = (i / n) * 6.28
		local rad = 1.5 + (i % 5) * 1.6
		for _, p in bat.parts do
			p.LocalTransparencyModifier = 0
		end
		bat.inst:PivotTo(
			CFrame.new(camera.CFrame * Vector3.new(math.cos(ang) * rad, math.sin(ang) * rad * 0.7, -5))
		)
	end
	for _ = 1, 3 do
		RunService.PreRender:Wait() -- ждём именно отрисованные кадры, а не время
	end
	for i = 1, n do
		park(pool[i])
	end
	warming = false
	print(("[BatFX] стая прогрета вхолостую: %d мышей в упор перед камерой."):format(n))
end

-- Пул и прогрев ассетов — сразу при загрузке, пока игрок в лобби под заставкой.
task.spawn(function()
	for _ = 1, POOL_SIZE do
		table.insert(pool, newBat())
		task.wait() -- растягиваем создание по кадрам: сам прогрев не должен дёргать
	end
	pcall(function()
		ContentProvider:PreloadAsync({ template, wings, squeal })
	end)
	warmSwarm()
end)

-- Свободная мышь. Занятую НЕ отбираем: перехват летящей мыши мгновенно телепортировал
-- её назад к точке вылета — со стороны это выглядело как «долетела и вернулась».
-- Если пул кончился, вылет просто пропускаем: в роях по 18-26 одной мышью меньше не видно.
local function take(): Bat?
	for _, bat in pool do
		if not bat.busy then
			return bat
		end
	end
	return nil
end

-- Один вылет. Рой (fast) идёт В ЛИЦО, эмбиент — неспешно мимо.
local function launchOne(origin: Vector3, fast: boolean)
	local bat = take()
	if not bat then
		return -- пул ещё не создан (первые кадры загрузки)
	end
	local camera = workspace.CurrentCamera
	bat.busy = true
	bat.swarm = fast
	bat.t0 = os.clock()
	bat.phase = math.random() * 6.28
	for _, p in bat.parts do
		p.LocalTransparencyModifier = 0
	end

	if fast then
		-- Стая срывается из точки вылета (сервер даёт её впереди по курсу) и
		-- сходится на лице. Смещения — диск ~2.5 studs вокруг камеры: мыши
		-- накрывают весь экран, но приходят волной, а не одной кучей.
		-- ШИРОКО И МГНОВЕННО — это скример, он должен пугать. Разлёт по всему экрану:
		-- радиус до 8 studs при цели в 5 studs перед камерой — крайние мыши уходят
		-- почти за край кадра, центральные накрывают его целиком. Задержек почти нет:
		-- стая появляется в лице за 0.13-0.22с, то есть «мгновенно».
		local ang = math.random() * 6.28
		-- Радиус шире прежнего (было 1.5-8): вместе с ранним разлётом (см. шаг стаи)
		-- это и даёт «уже разлетелись по всему экрану» до того, как стая дойдёт до лица.
		local rad = 2 + math.random() * 10
		bat.start = origin
			+ Vector3.new((math.random() - 0.5) * 22, (math.random() - 0.5) * 12, (math.random() - 0.5) * 22)
		bat.offset = Vector3.new(math.cos(ang) * rad, math.sin(ang) * rad * 0.7, -5.0)
		bat.delay = math.random() * 0.03
		bat.flight = 0.16 + math.random() * 0.09
		bat.life = bat.delay + bat.flight + 0.14 -- + короткий пронос ЗА игрока
		bat.speed = 190 -- пронос: уходит за спину, а не дрейфует перед носом
		bat.dir = camera and camera.CFrame.LookVector or Vector3.zAxis
	else
		-- одиночка: пролёт поперёк, почти горизонтально
		bat.start = origin
			+ Vector3.new((math.random() - 0.5) * 6, (math.random() - 0.5) * 4, (math.random() - 0.5) * 6)
		bat.dir = Vector3.new(math.random() - 0.5, (math.random() - 0.5) * 0.25, math.random() - 0.5).Unit
		bat.speed = math.random(28, 46)
		bat.delay = 0
		bat.flight = 0
		bat.life = 2.6
		bat.offset = Vector3.zero
	end
	bat.inst:PivotTo(CFrame.lookAt(bat.start, bat.start + bat.dir))
end

-- Один общий шаг на все мыши (раньше на каждую вешался свой RenderStepped).
RunService.RenderStepped:Connect(function()
	if warming then
		return -- стая на холостом прогоне: её позиции держит warmSwarm
	end
	local camera = workspace.CurrentCamera
	local now = os.clock()
	for _, bat in pool do
		if bat.busy then
			local age = now - bat.t0
			if age > bat.life then
				park(bat)
			else
				local pos, dir
				if bat.swarm and camera then
					local target = camera.CFrame * bat.offset -- цель едет вместе с камерой
					local a = math.clamp((age - bat.delay) / bat.flight, 0, 1)
					-- РАЗЛЁТ ИДЁТ ВПЕРЕДИ ПОДЛЁТА. Юзер: «мыши не успевают разлететься,
					-- в лицо летит куча — надо, чтобы до этого момента уже разлетелись по
					-- всему экрану». Причина была в том, что подход и разлёт шли ОДНОЙ
					-- интерполяцией с разгоном (a²): пока стая далеко, она сжата в точку,
					-- а весь угловой разлёт набегал в последние ~30 мс — то есть ровно
					-- тогда, когда она уже проносилась мимо. Теперь это две составляющие:
					-- вперёд — по-прежнему с разгоном, вбок — по a^0.3, то есть боковое
					-- смещение почти целиком набирается в первой трети пути.
					local face = camera.CFrame * Vector3.new(0, 0, bat.offset.Z)
					local lateral = camera.CFrame:VectorToWorldSpace(
						Vector3.new(bat.offset.X, bat.offset.Y, 0)
					)
					if a <= 0 then
						pos = bat.start -- ждёт своей очереди в волне
						dir = (target - bat.start).Unit
					elseif a < 1 then
						local eased = a * a * 1.15 -- разгон к лицу, не равномерно
						pos = bat.start:Lerp(face, math.min(eased, 1)) + lateral * (a ^ 0.3)
						dir = (target - pos).Magnitude > 1e-3 and (target - pos).Unit or bat.dir
						bat.dir = dir
					else
						-- прошла лицо: доносится мимо камеры и уходит за спину
						pos = target + bat.dir * (bat.speed * (age - bat.delay - bat.flight))
						dir = bat.dir
					end
					-- «взмах» поперёк курса, чтобы траектория не читалась рельсой
					local side = dir:Cross(Vector3.yAxis)
					if side.Magnitude > 1e-3 then
						pos += side.Unit * (math.sin(age * 26 + bat.phase) * 0.9 * (1 - a))
					end
				else
					local bob = math.sin(age * 22 + bat.phase) * 1.4
					dir = bat.dir
					pos = bat.start + dir * (bat.speed * age) + Vector3.new(0, bob, 0)
					-- Эмбиент гасим к концу: вдали меш ловит низкополи-LOD и выглядит
					-- «костляво». У РОЯ затухания нет — он обязан дойти до лица плотным.
					local fadeStart = bat.life * 0.6
					if age > fadeStart then
						local t = math.clamp((age - fadeStart) / (bat.life - fadeStart), 0, 1)
						for _, p in bat.parts do
							p.LocalTransparencyModifier = t
						end
					end
				end
				bat.inst:PivotTo(
					CFrame.lookAt(pos, pos + dir) * CFrame.Angles(0, 0, math.sin(age * 26 + bat.phase) * 0.6)
				)
			end
		end
	end
end)

batScare.OnClientEvent:Connect(function(origin: Vector3, count: number, kind: string)
	if typeof(origin) ~= "Vector3" then return end
	if not folder.Parent then
		folder.Parent = workspace.CurrentCamera -- камеру могли подменить (зритель/респавн)
	end
	if kind == "swarm" then
		if not jumpscaresOn then return end -- уважаем пугливых
		-- крылья и визг одновременно: залп крыльев даёт «масса рванула», визг — испуг.
		-- Высота визга каждый раз своя, иначе третий скример за заезд звучит заученно.
		if WINGS_ID ~= "" then
			wings.PlaybackSpeed = 0.95 + math.random() * 0.15
			wings:Play()
		end
		if SQUEAL_ID ~= "" then
			squeal.PlaybackSpeed = 1.18 + math.random() * 0.22
			squeal:Play()
		end
		for _ = 1, count do
			launchOne(origin, true)
		end
	else -- flyby: одна-две неспешные мыши мимо
		for _ = 1, count do
			launchOne(origin, false)
		end
	end
end)
