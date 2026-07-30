-- LocalScript: StarterPlayerScripts.DecorPreload
-- Фон-прелоад ассетов карты и звуков. Roblox подгружает ГЕОМЕТРИЮ/ТЕКСТУРУ меша и
-- тело звука при первом использовании — отсюда рывки «на участках трассы» (въехал в
-- новую зону → кадр грузит меши → фриз) и просадки по 180-220 мс посреди заезда,
-- совпадающие с `Failed to load sound ... HttpError: Timedout` (замер 2026-07-26).
-- Прогреваем всё разом в начале, пока игрок под заставкой, чтобы в заезде дороги не
-- спотыкались.
--
-- Списки даёт СЕРВЕР, двумя каналами:
--   ReplicatedStorage.DecorAssets  — меши декора (собирает MapBuilder);
--   ReplicatedStorage.WarmupAssets — звуки + ассеты шаблонов (собирает AssetWarmup),
--     строками "s|id" (звук) и "a|id" (меш/картинка).
-- Собрать список по клиентскому workspace нельзя: под StreamingEnabled там лежит
-- только ближний кусок карты (прогрелся бы старт, а фризы остались там же, где были),
-- а половина ассетов вообще живёт в ServerStorage, невидимом клиенту.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")

local CHUNK = 40 -- греем пачками: один гигантский вызов держал бы очередь целиком

-- Прогретые инстансы НЕ удаляем: пока они живы, тела звуков и анимаций остаются в
-- памяти клиента. Уничтожить их — значит выбросить всё, за чем мы сюда пришли.
local warmed = Instance.new("Folder")
warmed.Name = "WarmupCache"
warmed.Parent = SoundService

local function preload(items: { any })
	for i = 1, #items, CHUNK do
		local batch = {}
		for k = i, math.min(i + CHUNK - 1, #items) do
			table.insert(batch, items[k])
		end
		pcall(function()
			ContentProvider:PreloadAsync(batch)
		end)
	end
end

task.spawn(function()
	local holder = ReplicatedStorage:WaitForChild("DecorAssets", 60)
	if holder and holder:IsA("StringValue") then
		local urls: { string } = {}
		for id in holder.Value:gmatch("[^\n]+") do
			table.insert(urls, id)
		end
		if #urls > 0 then
			preload(urls)
		end
	end
end)

-- Список сервер ДОПОЛНЯЕТ на ходу (скрипты создают часть звуков в своём старте, на
-- первом кадре их ещё нет), поэтому слушаем Changed и греем только новое.
local done: { [string]: boolean } = {}
local busy = false
local pending: string? = nil

local consume: (string) -> ()
function consume(value: string)
	if busy then
		pending = value -- пачка ещё греется; догоним сразу после неё, не потеряв обновление
		return
	end
	busy = true
	local items: { any } = {}
	local nSounds, nAssets, nAnims = 0, 0, 0
	for line in value:gmatch("[^\n]+") do
		local kind, id = line:match("^(%a)|(.+)$")
		if kind and id and not done[line] then
			done[line] = true
			if kind == "s" then
				-- Звук ContentProvider надёжно греет только через инстанс, не по url.
				local s = Instance.new("Sound")
				s.SoundId = id
				s.Volume = 0 -- греем молча: играть его здесь не нужно
				s.Parent = warmed
				table.insert(items, s)
				nSounds += 1
			elseif kind == "n" then
				-- Анимации — та же история: только через инстанс. Именно они и вешали
				-- кадр на 190 мс при появлении зомби (Animator тянет их при первом
				-- воспроизведении, а их у рига десять).
				local a = Instance.new("Animation")
				a.AnimationId = id
				a.Parent = warmed
				table.insert(items, a)
				nAnims += 1
			elseif kind == "a" then
				table.insert(items, id)
				nAssets += 1
			end
		end
	end
	if #items > 0 then
		local t0 = os.clock()
		preload(items)
		print(("[DecorPreload] прогрето: %d звуков, %d анимаций, %d ассетов за %.1fс.")
			:format(nSounds, nAnims, nAssets, os.clock() - t0))
	end
	busy = false
	local queued = pending
	pending = nil
	if queued then
		consume(queued)
	end
end

task.spawn(function()
	local holder = ReplicatedStorage:WaitForChild("WarmupAssets", 60)
	if not holder or not holder:IsA("StringValue") then
		return
	end
	local sv = holder :: StringValue
	sv.Changed:Connect(function()
		consume(sv.Value)
	end)
	consume(sv.Value)
end)

-- // ПРОГРЕВ ОТРИСОВКИ ТРАССЫ ---------------------------------------------------
-- Замер 2026-07-27, разбор кадра по фазам, дал однозначный ответ:
--   [FRAME 187 мс] отрисовка 174 | анимация 0 | физика 11 | остальное 2
-- Всё время держит ОТРИСОВКА. Физика, анимация, репликация, сборка мусора и сеть
-- проверены и оправданы; снос ограды (1068 частей, 608 юнионов) ничего не изменил.
-- Причина в другом: движок строит меш области и заливает его в видеопамять в тот
-- кадр, когда область ВПЕРВЫЕ попадает в поле зрения. Отсюда всё, что мы видели:
-- рывок только за рулём (в лобби новых видов нет), только на первом круге, в
-- произвольных местах, без единого нового инстанса и без сетевого обмена.
--
-- Лечение общее для любой такой причины (террейн, декор, ограда): прогнать камеру
-- по трассе, пока игрок стоит под заставкой. Всё, что он увидит в заезде, к этому
-- моменту уже построено и залито. Идём с шагом через точку осевой и ждём КАДР на
-- каждой позиции — прогревает именно отрисовка, а не время.
-- Сколько это стоит: замер показал ~75 мс на КАЖДЫЙ новый вид, то есть на всю
-- трассу около 9 секунд. Это не издержки прогрева, а ровно та цена, которую иначе
-- платит первый круг — просто размазанная по сотням кадров, из которых мы видели
-- только два самых злых пика. Поэтому лимит щедрый: недоработавший прогрев
-- (первая версия обрывалась на 8с и успевала 106 видов из 120) смысла не имеет.
-- ПОЧЕМУ ПРЕЖНИЙ ПРОГРЕВ НЕ ДОРАБАТЫВАЛ (замер 2026-07-30). Он летел с FOV 110 и
-- четырьмя поворотами по 90°, «чтобы захватить всё разом». Но и мип текстуры, и
-- уровень детализации меша движок выбирает по РАЗМЕРУ ОБЪЕКТА НА ЭКРАНЕ, а при FOV
-- 110 против игровых 70 всё на экране мельче ровно в 2.04 раза (tan(55°)/tan(35°)).
-- То есть прогрев строил уровни на пару шагов грубее, чем нужно заезду, и первый
-- круг всё равно доплачивал — отсюда и наблюдение «рывки просто переезжают туда,
-- где подъезжаешь ближе, чем смотрел прогрев».
-- Замер, который это показал: текстурная память в лобби после прогрева — 18 Мб, а за
-- первый круг доросла до 34.5 Мб, причём подъезд камерой на 50 studs к одному
-- надгробию сразу даёт +3.6 Мб. То есть догружаются не новые картинки (их всего 5 на
-- весь декор, и они прелоадятся выше), а ВЫСОКИЕ МИПЫ тех же картинок.
-- Лечение: прогревать РОВНО тем видом, каким игрок поедет — не трогать FOV вообще,
-- камеру держать на водительской высоте и идти по осевой вперёд по курсу. Тогда
-- набор уровней, который построит прогрев, совпадает с тем, что попросит заезд.
local WARM_STEP_STUDS = 13 -- шаг вдоль осевой: 3128 studs трассы -> ~240 видов, как было
local WARM_EYE = 8 -- камера над ПОВЕРХНОСТЬЮ полотна (в игре: полотно 6.0, камера 13.9)
local WARM_LOOK = 30 -- на сколько studs вперёд смотрит камера (как погоня за машиной)
local WARM_SIDE_EVERY = 5 -- каждый N-й шаг — ещё два взгляда в стороны (обочины в поворотах)
local WARM_SIDE_YAW = 55 -- градусов в сторону: то, что проносится вплотную мимо борта
local WARM_LIMIT = 30 -- сек: страховка, чтобы прогрев не тянулся вечно

task.spawn(function()
	local okMap, MapLayout = pcall(function()
		return require(ReplicatedStorage:WaitForChild("MapLayout", 30))
	end)
	if not okMap or type(MapLayout) ~= "table" then
		return
	end
	local poly = MapLayout.TrackPolyline
	if type(poly) ~= "table" or #poly < 4 then
		return
	end
	local scale = MapLayout.Scale or 1
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end

	-- Прогрев идёт только пока игрок НЕ в машине: сел за руль — сразу отдаём камеру.
	local player = game:GetService("Players").LocalPlayer
	local function seated(): boolean
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		return (hum ~= nil) and (hum.SeatPart ~= nil)
	end
	if seated() then
		return
	end

	local n = #poly
	local function pt(i: number): Vector3
		local p = poly[((i - 1) % n) + 1]
		return Vector3.new(p.X * scale, 0, p.Y * scale)
	end

	-- Высоту берём с фактической поверхности: полотно рендерится выше номинального
	-- GroundTop (сейчас Ground на Y=6.00 при top=2), а прогревать надо с той высоты,
	-- с которой поедут, иначе размер на экране опять не совпадёт.
	local surfaceY = 6
	do
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Include
		rp.FilterDescendantsInstances = { workspace.Terrain }
		local probe = pt(1)
		local hit = workspace:Raycast(probe + Vector3.new(0, 200, 0), Vector3.new(0, -400, 0), rp)
		if hit then
			surfaceY = hit.Position.Y
		end
	end
	local eyeY = surfaceY + WARM_EYE

	-- Осевая как непрерывный путь: идём по ней шагом в studs, а не «через N точек»,
	-- иначе на длинных сегментах виды редеют, а на коротких дублируются.
	local cum: { number } = { 0 }
	local total = 0
	for i = 1, n do
		total += (pt(i + 1) - pt(i)).Magnitude
		cum[i + 1] = total
	end
	local function along(s: number): (Vector3, Vector3)
		s = s % total
		local i = 1
		while i < n and cum[i + 1] <= s do
			i += 1
		end
		local a, b = pt(i), pt(i + 1)
		local seg = cum[i + 1] - cum[i]
		local f = seg > 1e-6 and (s - cum[i]) / seg or 0
		local dir = (b - a)
		dir = dir.Magnitude > 1e-6 and dir.Unit or Vector3.zAxis
		return a + (b - a) * f, dir
	end

	local origType = cam.CameraType
	local origCF = cam.CFrame
	-- FOV НЕ МЕНЯЕМ: он и есть главный параметр, из-за которого прежний прогрев
	-- строил не те уровни детализации.
	cam.CameraType = Enum.CameraType.Scriptable

	local t0 = os.clock()
	local frames = 0
	local aborted = false
	local step = 0
	local s = 0
	while s < total do
		if seated() or os.clock() - t0 > WARM_LIMIT then
			aborted = true
			break
		end
		local pos, dir = along(s)
		local eye = Vector3.new(pos.X, eyeY, pos.Z)
		local fwd = CFrame.lookAt(eye, eye + dir * WARM_LOOK)
		cam.CFrame = fwd
		RunService.PreRender:Wait() -- ждём именно отрисованный кадр
		frames += 1
		-- Периодически — по взгляду в каждую сторону: то, что в заезде проносится
		-- вплотную мимо борта, вперёд смотрящая камера обрезает фрустумом.
		step += 1
		if step % WARM_SIDE_EVERY == 0 then
			for _, yaw in { WARM_SIDE_YAW, -WARM_SIDE_YAW } do
				if seated() or os.clock() - t0 > WARM_LIMIT then
					aborted = true
					break
				end
				cam.CFrame = fwd * CFrame.Angles(0, math.rad(yaw), 0)
				RunService.PreRender:Wait()
				frames += 1
			end
		end
		s += WARM_STEP_STUDS
	end

	cam.CFrame = origCF
	cam.CameraType = origType
	local spent = os.clock() - t0
	print(("[DecorPreload] отрисовка трассы прогрета: %d видов за %.1fс (%.0f мс на вид), FOV %.0f, глаз %.1f над полотном%s")
		:format(frames, spent, frames > 0 and (spent / frames) * 1000 or 0, cam.FieldOfView, WARM_EYE,
			aborted and " — ОБОРВАН, трасса покрыта не вся." or "."))
end)
