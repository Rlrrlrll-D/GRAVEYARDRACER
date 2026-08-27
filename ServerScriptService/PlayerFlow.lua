--!strict
-- ModuleScript: ServerScriptService.PlayerFlow
-- Жизненный цикл игрока в упрощённой модели «заставка → отсчёт → гонка»:
-- игрок стоит у СТАРТА (без лобби-платформы и диорам), заморожен пока не гонка;
-- на старте ему выдаётся своя машина с владельцем (OwnerUserId) и он в неё
-- садится; после заезда возвращается к старту. Машина уничтожается при эвикте и
-- на PlayerRemoving — чинит старый баг накопления клонов багги.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VehicleRegistry = require(ReplicatedStorage:WaitForChild("VehicleRegistry"))
local MapLayout = require(ReplicatedStorage:WaitForChild("MapLayout"))
local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local ShopCatalog = require(ReplicatedStorage:WaitForChild("ShopCatalog"))

local PlayerFlow = {}

local vehicleOfPlayer: { [Player]: Model } = {}

-- // Точка старта (где игрок стоит под заставкой/отсчётом) --------------------
-- Захватывается в init из мировой SpawnLocation; игрок телепортируется сюда и
-- замораживается, пока не сядет в машину. Никакой платформы/диорамы.
local START_CF = CFrame.new(28, 5, 28)

-- Обочина для ждущих: полполотна 22.4 + запас, чтобы гонщика не тянуло в толпу.
local LOBBY_SIDE = 32
local LOBBY_CLEAR_RADIUS = 7 -- в каком радиусе считаем декор, выбирая сторону

-- Пока игрок не за рулём, машина обязана проходить сквозь него (он заморожен у
-- старта и увернуться не может). Группа заведена в Bootstrap.
local function setCharacterGroup(char: Model, group: string)
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") then
			pcall(function()
				d.CollisionGroup = group
			end)
		end
	end
end

local function freeze(hum: Humanoid)
	hum.WalkSpeed = 0
	hum.JumpPower = 0
	hum.JumpHeight = 0
end
local function unfreeze(hum: Humanoid)
	hum.WalkSpeed = 16
	hum.JumpPower = 50
	hum.JumpHeight = 7.2
end

-- Вернуть персонажа к старту (под заставку) и заморозить. Имя sendToLobby
-- сохранено — им пользуется MatchManager.evict/onCharacterAdded.
function PlayerFlow.sendToLobby(player: Player)
	local char = player.Character
	if not char then
		return
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and hum.SeatPart then
		-- Sit=false снимает SeatWeld только на следующем шаге физики → PivotTo
		-- утащило бы персонажа обратно к сиденью. Снимаем weld сами, мгновенно.
		local weld = hum.SeatPart:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end
	if hum then
		hum.Sit = false
	end
	task.wait() -- дать физике отпустить персонажа
	-- разброс ВДОЛЬ обочины, а не куда попало: вбок он выталкивал бы обратно на полотно
	local scatter = START_CF.RightVector * math.random(-5, 5)
	char:PivotTo(START_CF + scatter)
	setCharacterGroup(char, "Bystanders") -- сквозь ждущих машина проезжает
	if hum then
		freeze(hum) -- под заставкой не бродим
	end
end

-- // Стартовая решётка: КОЛОННА ПО ДВА ВДОЛЬ ТРАССЫ ---------------------------
-- Места идут парами назад от стартовой линии ПО ОСЕВОЙ (MapLayout.TrackPolyline):
-- ряд = два места по разные стороны от осевой, машины смотрят по касательной, так
-- что колонна повторяет изгиб дороги, а не уходит по прямой в траву.
--
-- Габариты багги в системе координат сиденья (замерено по VehicleTemplate):
-- длина 13.1 (нос 7.3 впереди сиденья, корма 5.8 позади), ширина 8.3, причём
-- сиденье смещено на 1.6 ВЛЕВО от геометрического центра кузова.
local CAR_LEN = 13.1
local CAR_SEAT_OFFSET_X = 1.6 -- центр кузова правее сиденья на столько
local GRID_ROW_GAP = CAR_LEN + 5 -- 18.1: между рядами есть просвет (раньше 8 — машины ПЕРЕКРЫВАЛИСЬ)
local GRID_LANE = 8 -- вбок от осевой (дорога 44.8 → полполотна 22.4, край кузова на 12.2)

local FALLBACK_SEAT_CF = CFrame.lookAt(Vector3.new(10.05, 7.21, 5.19), Vector3.new(9.05, 7.21, 5.19))
local gridBaseSeatCF = FALLBACK_SEAT_CF
local gridSlots: { CFrame } = {} -- построенные места (заполняется, когда террейн готов)
local gridDepthStuds = 0 -- фактическая длина колонны по осевой (для точки лобби)

PlayerFlow.MaxSlots = 8
local GRID_ROWS = math.ceil(PlayerFlow.MaxSlots / 2)

local function captureGridBase()
	local captured = false
	for _, v in CollectionService:GetTagged("PlayerVehicle") do
		if v:IsA("Model") and v.Parent == workspace then
			local seat = v:FindFirstChild("DriveSeat")
			if not captured and seat and seat:IsA("VehicleSeat") then
				gridBaseSeatCF = seat.CFrame
				captured = true
			end
			v:Destroy() -- мир стартует без свободных машин
		end
	end
	if not captured then
		warn("[PlayerFlow] Преж-установленного багги нет — решётка от запасного CFrame.")
	end
end

-- Точка на осевой в `dist` studs ПОЗАДИ старта + касательная (направление езды).
-- Полилиния замкнутая, движение — по возрастанию индекса, значит назад = вниз по
-- индексу. Возвращает мировые X/Z (уже с учётом MapLayout.Scale) и единичный
-- вектор направления движения.
local function trackPointBehind(dist: number): (Vector2?, Vector2?)
	local poly = MapLayout.TrackPolyline
	if not poly or #poly < 4 then
		return nil, nil
	end
	local n = #poly
	local i = 1 -- TrackPolyline[1] — стартовая точка (= Landmarks.StartGate)
	local remaining = dist
	for _ = 1, n do
		local prev = ((i - 2) % n) + 1 -- индекс i-1 с заворотом
		local a, b = poly[prev], poly[i]
		local d = (b - a).Magnitude
		local fwd = d > 1e-4 and (b - a).Unit or Vector2.new(1, 0)
		if d >= remaining then
			local p = b:Lerp(a, d > 1e-4 and (remaining / d) or 0)
			return p * MapLayout.Scale, fwd
		end
		remaining -= d
		i = prev
	end
	return nil, nil
end

-- Ряд на дистанции dist позади старта: базовый CFrame и центры кузовов обеих полос.
local function gridRow(dist: number, y: number): (CFrame?, { Vector3 })
	local res, fwd = trackPointBehind(dist)
	if not res or not fwd then
		return nil, {}
	end
	local p, f = res :: Vector2, fwd :: Vector2
	local at = Vector3.new(p.X, y, p.Y)
	local base = CFrame.lookAt(at, at + Vector3.new(f.X, 0, f.Y))
	return base, { (base * CFrame.new(-GRID_LANE, 0, 0)).Position, (base * CFrame.new(GRID_LANE, 0, 0)).Position }
end

-- Построить места по осевой на высоте y (высота дороги — полотно плоское).
-- ВАЖНО: шаг между рядами АДАПТИВНЫЙ. Отмерять ряды по осевой недостаточно — на
-- изгибе внутренняя полоса идёт по более короткой дуге и машины съезжаются
-- (на нашей трассе 3-й ряд оставался с зазором 1 stud). Поэтому ряд отодвигается
-- назад, пока ОБЕ полосы не разойдутся на GRID_ROW_GAP.
local function buildGridSlots(y: number)
	local slots: { CFrame } = {}
	local dist = 0
	local _, prevBodies = gridRow(0, y)
	if #prevBodies == 0 then
		return -- нет полилинии: остаёмся на запасной решётке
	end
	for row = 0, GRID_ROWS - 1 do
		if row > 0 then
			dist += GRID_ROW_GAP
			for _ = 1, 60 do
				local _, bodies = gridRow(dist, y)
				if #bodies == 0 then
					return
				end
				local ok = true
				for k, b in bodies do
					if (b - prevBodies[k]).Magnitude < GRID_ROW_GAP - 0.05 then
						ok = false
						break
					end
				end
				if ok then
					break
				end
				dist += 1
			end
		end
		local base, bodies = gridRow(dist, y)
		if not base then
			return
		end
		prevBodies = bodies
		for side = 0, 1 do
			-- нечётные места слева от осевой, чётные справа; сиденье сдвигаем так,
			-- чтобы по центру полосы оказался КУЗОВ, а не сиденье.
			local lane = (side == 0) and -GRID_LANE or GRID_LANE
			table.insert(slots, (base :: CFrame) * CFrame.new(lane - CAR_SEAT_OFFSET_X, 0, 0))
		end
	end
	gridSlots = slots
	gridDepthStuds = dist
end

-- CFrame СИДЕНЬЯ для места i (1..MaxSlots)
function PlayerFlow.gridSlot(i: number): CFrame
	local built = gridSlots[math.clamp(i, 1, PlayerFlow.MaxSlots)]
	if built then
		return built
	end
	-- запасной вариант (террейн ещё не готов / нет полилинии): прямая колонна по два
	if i <= 1 then
		return gridBaseSeatCF
	end
	local row = math.ceil(i / 2) - 1
	local lane = (i % 2 == 1) and -GRID_LANE or GRID_LANE
	return gridBaseSeatCF * CFrame.new(lane - CAR_SEAT_OFFSET_X, 0, row * GRID_ROW_GAP)
end

-- // Выдача/уборка машины -----------------------------------------------------
local template: Model? = nil
local pivotFromSeat = CFrame.new()

local function ensureTemplate(): Model?
	if template then
		return template
	end
	local t = ServerStorage:FindFirstChild("VehicleTemplate")
	if t and t:IsA("Model") then
		local seat = t:FindFirstChild("DriveSeat")
		if seat and seat:IsA("VehicleSeat") then
			-- пивот багги наклонён (Wedge) → ставим клоны по CFrame сиденья
			pivotFromSeat = seat.CFrame:Inverse() * t:GetPivot()
		end
		template = t
	else
		warn("[PlayerFlow] Нет ServerStorage.VehicleTemplate.")
	end
	return template
end

-- // Успокоить механику A-Chassis --------------------------------------------
-- ЖАЛОБА 2026-08-27 (планшет, живой клиент): «на старте багги улетела к дереву,
-- передняя подвеска деформировалась».
--
-- Разбор. Машину на отсчёте держит ЯКОРЬ (holdVehicle ниже), а клиентский Drive всё
-- это время продолжает крутиться и 15 раз в секунду переписывает силовые объекты
-- AC6: `#AV` (BodyAngularVelocity на каждом колесе, P = 1e9) и `Steer` (BodyGyro на
-- рычаге, P = 90000, MaxTorque 50000 — при массе рычага 0.8). У ЗАЯКОРЕННОЙ детали
-- владельца нет, поэтому эти записи НИКУДА НЕ ЕДУТ: они живут только у клиента, а на
-- сервере остаются значения пятисекундной давности.
--
-- На GO сервер снимает якорь и отдаёт владение. Передача владения идёт по сети — на
-- планшете это сотни миллисекунд, и всё это окно СЕРВЕР считает физику по своим,
-- протухшим силам, а клиент по своим. В момент, когда владение перещёлкивается, две
-- версии механизма сходятся рывком: рычаг получает удар от гироскопа, пружину
-- (Stiffness 8000, ход 2.1..3.3) пробивает за упор — и машину выкидывает с грида.
--
-- В STUDIO ЭТОГО НЕ УВИДЕТЬ, как и родственного бага с респавном (VehicleController):
-- там передача владения мгновенная, окна расхождения не существует.
--
-- Лечится не подбором сил, а тем, чтобы отдавать машину клиенту с ПОКОЯЩЕЙСЯ
-- механикой: обнуляем моторы колёс и просим гироскопы держать ровно ту позу, в
-- которой рычаги уже стоят. Через кадр-другой Drive перепишет всё сам — но уже
-- будучи владельцем, то есть без спора с сервером.
local function quietChassis(car: Model)
	local wheels = car:FindFirstChild("Wheels")
	if wheels then
		for _, w in wheels:GetChildren() do
			local av = w:FindFirstChild("#AV")
			if av and av:IsA("BodyAngularVelocity") then
				(av :: BodyAngularVelocity).AngularVelocity = Vector3.zero;
				(av :: BodyAngularVelocity).MaxTorque = Vector3.zero
			end
			local arm = w:FindFirstChild("Arm")
			local steer = arm and arm:FindFirstChild("Steer")
			if arm and arm:IsA("BasePart") and steer and steer:IsA("BodyGyro") then
				-- цель = ТЕКУЩАЯ поза рычага: гироскопу нечего доворачивать
				(steer :: BodyGyro).CFrame = (arm :: BasePart).CFrame
			end
		end
	end
	local seat = car:FindFirstChild("DriveSeat")
	local flip = seat and seat:FindFirstChild("Flip")
	if flip and flip:IsA("BodyGyro") then
		(flip :: BodyGyro).MaxTorque = Vector3.zero -- дуга «переворота» на старте не нужна
	end
end
PlayerFlow.quietChassis = quietChassis -- тем же пользуется VehicleController на респавне

-- Погасить инерцию. Только ПОСЛЕ разякоривания: у заякоренной детали скорости и так
-- нули, присвоение до снятия якоря ушло бы в никуда.
local function stillVelocities(car: Model)
	for _, p in car:GetDescendants() do
		if p:IsA("BasePart") and not (p :: BasePart).Anchored then
			(p :: BasePart).AssemblyLinearVelocity = Vector3.zero;
			(p :: BasePart).AssemblyAngularVelocity = Vector3.zero
		end
	end
end

-- // ТУРЕЛЬ: ставим на место и привариваем ПОСЛЕ спавна ------------------------
-- Жалоба юзера: «пулемёт висит в воздухе над машиной». Разбор показал, что в шаблоне
-- вся машина держится ЯКОРЯМИ (детали `Part` — невидимые заякоренные плиты
-- A-Chassis), сварок почти нет. При спавне A-Chassis разякоривает всё и сваривает по
-- своей схеме, турель в неё не входит: `TurretBase` успевает уехать, а `Turret` со
-- стволом вообще остаются отдельными физическими сборками и падают (замерено:
-- основание оказывалось на 4.5 studs НИЖЕ сиденья вместо 2.4 выше, оба шарнира
-- `Active=false`). Поэтому ставим турель на место сами — по позе из шаблона
-- относительно сиденья — и привариваем жёстким `Weld` (он хранит смещение в C0 и
-- восстанавливает его, в отличие от `WeldConstraint`, который запоминает то
-- положение, в котором деталь застал момент активации).
local TURRET_PARTS = { "TurretBase", "TurretMast", "Turret", "GunCradle", "GunMesh" }

-- ВЛАДЕНИЕ ТУРЕЛЬЮ — ВОДИТЕЛЮ. Жалоба: «точка выстрела запаздывает при поворотах».
-- Направление выстрела и так считается по прицелу, а не по стволу, значит отставала
-- сама турель. Причина структурная: `Turret` и `GunCradle` — ОТДЕЛЬНЫЕ физические
-- сборки (их держат шарниры, а не сварка), а сетевое владение выдаётся по сборкам —
-- машину отдали водителю, турель осталась за сервером. Прицел ставит `TargetAngle`
-- у клиента, а отрабатывает сервопривод на сервере, и поворот приезжает через круг
-- связи; на вираже, когда угол меняется быстро, это и читается как запаздывание.
local function giveTurretOwnership(car: Model, player: Player)
	for _, name in { "Turret", "GunCradle", "GunMesh" } do
		local part = car:FindFirstChild(name, true)
		if part and part:IsA("BasePart") and not part.Anchored then
			pcall(function()
				part:SetNetworkOwner(player)
			end)
		end
	end
end

-- // ФАРЫ: наводим луч на дорогу ----------------------------------------------
-- Жалоба юзера: «свет от фар ломается при езде — пятно режется изгибом дороги или
-- объектом, на который проецируется». Разбор в Play-режиме (снимки сверху-сзади,
-- 2026-07-31) показал, в чём дело: аттачменты `HeadlightL/R` в шаблоне стоят с
-- нулевым поворотом, то есть луч идёт СТРОГО ГОРИЗОНТАЛЬНО на высоте ~3.5 studs
-- над полотном. Такой конус не освещает дорогу — он лишь чиркает по ней вскользь
-- далеко впереди, и на землю ложится не луч, а оторванный от машины блин с жёсткой
-- кромкой: у бампера темно, пятно висит в 15 studs, край обрывается по Range.
-- Любая неровность или надгробие на пути такого касательного света выкусывает из
-- блина кусок — это и читается как «пятно режется».
--
-- Лечится наведением, а не мощностью: небольшой наклон вниз сажает конус на
-- полотно от самого бампера, а более широкий и длинный конус даёт мягкий спад
-- вместо обрыва. Проверено съёмкой до/после на том же кадре.
--
-- Настройка живёт ЗДЕСЬ, а не в шаблоне: `VehicleTemplate` лежит в .rbxl, который
-- не под гитом, и правка в нём потерялась бы при любой пересборке машины.
-- ВТОРАЯ ЖАЛОБА (после первой правки): «дорога освещается не сразу, а фрагментарно
-- прямоугольными зонами с задержкой». Это НЕ наведение, это движок: место загружено
-- с `Lighting.Technology = ShadowMap` (атрибут RBX_OriginalTechnologyOnFileLoad=3),
-- а в этом режиме локальные источники света считаются ВОКСЕЛЬНОЙ СЕТКОЙ с шагом
-- 4 studs, и сетка пересобирается лениво, по кускам. Едущая машина обгоняет
-- пересчёт — отсюда и прямоугольники, и задержка.
--
-- Из кода это не выключить: `Lighting.Technology` не читается и не пишется скриптом
-- («lacking capability RobloxScript», перепроверено 31.07) — только руками в
-- Properties. Совсем убирает ступеньки перевод места на Future/Unified (там свет
-- попиксельный), но это заметный расход GPU, а машина юзера на встроенной Iris Xe —
-- решение его, не наше.
--
-- Что можно из кода: уменьшить ОБЪЁМ конуса — сетка пересчитывает ровно те воксели,
-- которые он накрывает. Прежние Range 60 / Angle 68 давали примерно 1200 вокселей на
-- фару, нынешние 38/56 — около 210, почти в шесть раз меньше работы на кадр. Чтобы
-- пятно при этом не потускнело и не отодвинулось, наклон чуть круче, а яркость выше.
local HEADLIGHT_PITCH = math.rad(-11) -- наклон луча вниз (минус = вниз, ось X кузова)
local HEADLIGHT_ANGLE = 56 -- ровно накрыть полотно, не расплёскивая свет по полю
local HEADLIGHT_RANGE = 38 -- главный рычаг против воксельных ступенек
local HEADLIGHT_BRIGHTNESS = 3.0 -- компенсация укороченной дальности

-- Скин кузова из магазина. Меш кузова один (BuggyBody) и он текстурирован — цвет
-- текстуру домножает, поэтому «покрасить» здесь значит именно перекрасить, а не
-- залить плашкой. Что надето, лежит в атрибуте EquippedSkin (ставит ShopService,
-- сохраняет PlayerData); незнакомый или отсутствующий скин откатывается к базовому.
local function applySkin(car: Model, player: Player)
	local skin = ShopCatalog.get(player:GetAttribute("EquippedSkin"))
	if not (skin and skin.kind == "skin") then
		skin = ShopCatalog.get(ShopCatalog.DefaultSkin)
	end
	local body = car:FindFirstChild("BuggyBody")
	if not (skin and body and body:IsA("BasePart")) then
		return
	end
	if skin.color then
		(body :: BasePart).Color = skin.color
	end
	if skin.material then
		(body :: BasePart).Material = skin.material
	end
end

local function tuneHeadlights(car: Model)
	local body = car:FindFirstChild("BuggyBody")
	if not (body and body:IsA("BasePart")) then
		return
	end
	for _, at in body:GetChildren() do
		if at:IsA("Attachment") and at.Name:match("^Headlight") then
			local light = at:FindFirstChildOfClass("SpotLight")
			if light then
				-- позицию аттачмента не трогаем — она выставлена по фарам меша,
				-- меняем только НАПРАВЛЕНИЕ и параметры конуса
				at.CFrame = CFrame.new(at.CFrame.Position) * CFrame.Angles(HEADLIGHT_PITCH, 0, 0)
				light.Angle = HEADLIGHT_ANGLE
				light.Range = HEADLIGHT_RANGE
				light.Brightness = HEADLIGHT_BRIGHTNESS
				-- Тени у фар выключены намеренно: с ними каждый камень у обочины
				-- начинает резать пятно по-настоящему, и кадр дорожает на ровном месте.
				light.Shadows = false
			end
		end
	end
end

-- Турель уже стоит на месте? Сверяем позу `TurretBase` относительно сиденья с
-- шаблонной: если совпала, второй проход не нужен, а лишний проход по машине с
-- водителем опасен (см. ниже).
local TURRET_POSE_TOL = 0.25
local function turretMounted(car: Model): boolean
	local t = template
	local tSeat = t and t:FindFirstChild("DriveSeat")
	local tBase = t and t:FindFirstChild("TurretBase", true)
	local seat = car:FindFirstChild("DriveSeat")
	local base = car:FindFirstChild("TurretBase", true)
	if
		not (
			tSeat
			and tSeat:IsA("BasePart")
			and tBase
			and tBase:IsA("BasePart")
			and seat
			and seat:IsA("BasePart")
			and base
			and base:IsA("BasePart")
		)
	then
		return false
	end
	local want = (tSeat :: BasePart).CFrame:Inverse() * (tBase :: BasePart).CFrame
	local have = (seat :: BasePart).CFrame:Inverse() * (base :: BasePart).CFrame
	return (want.Position - have.Position).Magnitude <= TURRET_POSE_TOL
end

local function mountTurret(car: Model, player: Player?)
	local t = template
	local tSeat = t and t:FindFirstChild("DriveSeat")
	local seat = car:FindFirstChild("DriveSeat")
	if not (tSeat and tSeat:IsA("BasePart") and seat and seat:IsA("BasePart")) then
		return
	end
	-- МАШИНУ С ВОДИТЕЛЕМ ПЕРЕБИРАТЬ «НА ЖИВУЮ» НЕЛЬЗЯ. Как только игрок сел, физикой
	-- владеет КЛИЕНТ, и любая перестановка детали с сервера расходится с его сборкой:
	-- сервер переставил, клиент считает от своего — держатся детали шарнирами, а не
	-- сваркой, и подвеску растягивает. Это тот же механизм, по которому машина
	-- «возвращалась разобранной» после респавна (VehicleController.repairAtHome), и
	-- лечится он тем же: всю операцию делаем НА ЯКОРЕ, а потом возвращаем владение.
	local occupied = seat:IsA("VehicleSeat") and (seat :: VehicleSeat).Occupant ~= nil
	local frozen: { [BasePart]: boolean }? = nil
	if occupied then
		local snapshot: { [BasePart]: boolean } = {}
		for _, d in car:GetDescendants() do
			if d:IsA("BasePart") then
				snapshot[d :: BasePart] = (d :: BasePart).Anchored;
				(d :: BasePart).Anchored = true
			end
		end
		frozen = snapshot
	end
	-- ПОРЯДОК ВАЖЕН. Двигать деталь, уже вваренную в сборку машины, НЕЛЬЗЯ: сдвиг
	-- тащит ВСЮ сборку — кузов с колёсами, — и подвеску рвёт (машина буквально
	-- разлеталась). Поэтому сперва снимаем с турели все чужие соединения, и только
	-- потом ставим её на место и варим заново.
	local mounted: { BasePart } = {}
	for _, name in TURRET_PARTS do
		local dst = car:FindFirstChild(name, true)
		if dst and dst:IsA("BasePart") then
			table.insert(mounted, dst)
		end
	end
	local mountedSet: { [BasePart]: boolean } = {}
	for _, p in mounted do
		mountedSet[p] = true
	end
	for _, d in car:GetDescendants() do
		local a, b
		if d:IsA("WeldConstraint") then
			a, b = d.Part0, d.Part1
		elseif d:IsA("JointInstance") then
			a, b = d.Part0, d.Part1
		end
		-- сварки ВНУТРИ турели (ствол к люльке, стойка к основанию) не трогаем,
		-- режем только те, что связывают турель с машиной
		if a and b and (mountedSet[a] ~= mountedSet[b]) then
			d:Destroy()
		end
	end
	task.wait() -- дать движку пересобрать сборки, иначе сдвиг ещё потянет за собой машину

	for _, name in TURRET_PARTS do
		local src = t:FindFirstChild(name, true)
		local dst = car:FindFirstChild(name, true)
		if src and src:IsA("BasePart") and dst and dst:IsA("BasePart") then
			if not frozen then
				dst.Anchored = false -- на замороженной машине якорь как раз и нужен: двигаем ОДНУ деталь
			end
			-- поза из шаблона, пересчитанная от текущего сиденья
			dst.CFrame = seat.CFrame * (tSeat.CFrame:Inverse() * src.CFrame)
		end
	end

	-- Неподвижную часть держим сваркой к сиденью; вращаться должны только `Turret`
	-- (рыскание) и `GunCradle` (наклон) — их держат шарниры, которым прицел задаёт угол.
	for _, name in { "TurretBase", "TurretMast" } do
		local part = car:FindFirstChild(name, true)
		if part and part:IsA("BasePart") then
			local w = Instance.new("Weld")
			w.Name = "TurretMount"
			w.Part0 = seat
			w.Part1 = part
			w.C0 = seat.CFrame:Inverse() * part.CFrame
			w.Parent = part
		end
	end
	if frozen then
		for p, wasAnchored in frozen do
			if p.Parent then
				p.Anchored = wasAnchored
			end
		end
		quietChassis(car)
		stillVelocities(car)
		if player then
			pcall(function()
				(seat :: VehicleSeat):SetNetworkOwner(player :: Player)
			end)
		end
	end
	if player then
		giveTurretOwnership(car, player)
	end
end

function PlayerFlow.assignVehicle(player: Player, seatCFrame: CFrame): Model?
	PlayerFlow.releaseVehicle(player) -- на всякий: не плодим вторую машину
	local t = ensureTemplate()
	if not t then
		return nil
	end
	local car = t:Clone()
	car.Name = "Buggy_" .. player.UserId
	car:SetAttribute("OwnerUserId", player.UserId)
	local seat = car:FindFirstChild("DriveSeat")
	if seat and seat:IsA("VehicleSeat") then
		seat.HeadsUpDisplay = false -- нативный Roblox-спидометр (CoreGui.VehicleHudFrame) не нужен: свой HUD
	end
	tuneHeadlights(car) -- до Parent: свет приедет клиенту уже наведённым
		applySkin(car, player) -- тоже ДО Parent: игрок не должен видеть смену цвета
	car:PivotTo(seatCFrame * pivotFromSeat) -- ДО Parent: VehicleController запомнит «дом»
	-- A-Chassis + StreamingEnabled: под ModelStreamingMode.Default машину клиенту
	-- реплицирует ПО ЧАСТЯМ, и скопированный в PlayerGui Drive рвётся на
	-- car.DriveSeat/car.Wheels («not a valid member») → движок не заводится, машина
	-- не едет. Держим машину ЦЕЛИКОМ у всех клиентов (Persistent + persistent-игроки),
	-- чтобы AC6 всегда видел все детали сразу. (Машин мало — стриминг тут не нужен.)
	car.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	car.Parent = workspace
	for _, p in Players:GetPlayers() do
		pcall(function()
			car:AddPersistentPlayer(p)
		end)
	end
	-- Зашедшим ПОЗЖЕ (зритель посреди заезда) машину тоже отдаём целиком, иначе
	-- у них она приедет по частям — та же поломка AC6, только у наблюдателя.
	local joined: RBXScriptConnection
	joined = Players.PlayerAdded:Connect(function(p)
		if car.Parent then
			pcall(function()
				car:AddPersistentPlayer(p)
			end)
		else
			joined:Disconnect()
		end
	end)
	car.Destroying:Connect(function()
		joined:Disconnect()
	end)
	CollectionService:AddTag(car, "PlayerVehicle") -- VehicleController подхватит
	vehicleOfPlayer[player] = car
	-- Турель ставим ПОСЛЕ инициализации A-Chassis: он на старте разякоривает детали и
	-- сваривает машину по-своему, поэтому раньше времени крепить бесполезно — перетрёт.
	task.spawn(function()
		task.wait(0.4)
		if car.Parent then
			pcall(mountTurret, car, player)
		end
		-- Второй проход — ТОЛЬКО если первый не прижился (инициализация AC6 в этот раз
		-- оказалась дольше). Гонять его вслепую нельзя: к этой секунде игрок уже за
		-- рулём, машина у клиента, и лишняя перестановка деталей её ломает.
		task.wait(1.6)
		if car.Parent and not turretMounted(car) then
			warn(`[PlayerFlow] {car.Name}: турель не прижилась с первого раза — второй проход.`)
			pcall(mountTurret, car, player)
		end
	end)
	return car
end

function PlayerFlow.getVehicle(player: Player): Model?
	local car = vehicleOfPlayer[player]
	return (car and car.Parent) and car or nil
end

-- Посадить владельца за руль его машины (персонаж стоит у старта — телепортим).
function PlayerFlow.seatDriver(player: Player)
	local car = PlayerFlow.getVehicle(player)
	local seat = car and car:FindFirstChild("DriveSeat")
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (car and seat and seat:IsA("VehicleSeat") and char and hum and hum.Health > 0) then
		return
	end
	unfreeze(hum :: Humanoid) -- разморозить перед посадкой
	setCharacterGroup(char :: Model, "Default"); -- за рулём он снова обычное тело
	(seat :: VehicleSeat).Disabled = false
	-- Надёжная посадка: под StreamingEnabled одиночный Sit сразу после спавна (машина
	-- ещё оседает на террейн) часто НЕ регистрирует Occupant на сервере — а пока
	-- Occupant нет, сервер не отдаёт клиенту сетевое владение, и клиентский движок
	-- AC6 не может двигать машину («не едет»). Повторяем Sit, пока не сядет, затем
	-- ЯВНО отдаём владение водителю (не ждём хендлера SeatWeld в A-Chassis Initialize).
	local seated = false
	for _ = 1, 14 do
		if (seat :: VehicleSeat).Occupant == hum then
			seated = true
			break
		end
		(char :: Model):PivotTo((seat :: VehicleSeat).CFrame * CFrame.new(0, 3.5, 0))
		task.wait()
		pcall(function()
			(seat :: VehicleSeat):Sit(hum :: Humanoid)
		end)
		task.wait(0.1)
	end
	if seated then
		-- Отдаём владение водителю И ПРОВЕРЯЕМ, что прижилось. На 2-й+ машине в
		-- мультиплеере одиночный SetNetworkOwner иногда не срабатывает (ассамблея
		-- ещё оседает / владение перехватывает автопил) → «стреляет, но не едет»:
		-- физику AC6 двигает ТОЛЬКО владелец-клиент. Ретраим, пока GetNetworkOwner
		-- не станет игроком.
		local owner: Player? = nil
		for _ = 1, 12 do
			pcall(function()
				(seat :: VehicleSeat):SetNetworkOwner(player)
			end)
			task.wait(0.1)
			pcall(function()
				owner = (seat :: VehicleSeat):GetNetworkOwner()
			end)
			if owner == player then
				break
			end
		end
		-- Турель — ОТДЕЛЬНЫЕ сборки (их держат шарниры, а не сварка), и владение
		-- машиной на них НЕ распространяется. Без этого сервопривод поворота считает
		-- сервер, и прицел отстаёт на круг связи — заметнее всего на виражах.
		giveTurretOwnership(car, player)
	end
end

-- // Удержание машины на отсчёте ----------------------------------------------
-- Газ на отсчёте — читерство: A-Chassis живёт у КЛИЕНТА, сервер его команды не
-- фильтрует, поэтому единственный надёжный тормоз со стороны сервера — якорь.
-- Якорим ВСЕ детали (только шасси мало: колёса на хинджах докрутились бы и машину
-- сорвало бы с места на разякоривании), запомнив прежнее состояние.
--
-- ВАЖНО: Anchored=true СБРАСЫВАЕТ сетевое владение (у якоря владельца нет). Если
-- на GO просто разякорить, машина останется за сервером и клиентский AC6 не сможет
-- её двигать — это ровно тот баг «машина не едет», который мы долго ловили. Поэтому
-- на отпускании владение отдаётся водителю заново, с проверкой (как в seatDriver).
local heldCars: { [Model]: { [BasePart]: boolean } } = setmetatable({}, { __mode = "k" }) :: any

function PlayerFlow.holdVehicle(player: Player)
	local car = PlayerFlow.getVehicle(player)
	if not car or heldCars[car] then
		return
	end
	local prev: { [BasePart]: boolean } = {}
	for _, p in car:GetDescendants() do
		if p:IsA("BasePart") then
			prev[p] = p.Anchored
			p.Anchored = true
		end
	end
	-- Силовые объекты AC6 гасим и на входе в удержание: пока машина стоит на якоре,
	-- серверная копия «моторов» не должна оставаться взведённой (см. quietChassis).
	quietChassis(car)
	heldCars[car] = prev
end

function PlayerFlow.releaseVehicleHold(player: Player)
	local car = PlayerFlow.getVehicle(player)
	local prev = car and heldCars[car]
	if not (car and prev) then
		return
	end
	heldCars[car] = nil
	for p, wasAnchored in prev do
		if p.Parent then
			p.Anchored = wasAnchored
		end
	end
	-- ОТДАЁМ МАШИНУ КЛИЕНТУ В ПОКОЕ, И ЭТО ГЛАВНОЕ В ЭТОЙ ФУНКЦИИ. Разбор — над
	-- quietChassis: без этого на GO сервер и клиент секунду считают физику по разным
	-- силам, и на планшете машину выкидывало с грида с вывернутой подвеской.
	quietChassis(car)
	stillVelocities(car)
	local seat = car:FindFirstChild("DriveSeat")
	if not (seat and seat:IsA("VehicleSeat")) then
		return
	end
	pcall(function()
		(seat :: VehicleSeat):SetNetworkOwner(player)
	end)
	task.spawn(function()
		local owner: Player? = nil
		for _ = 1, 12 do
			pcall(function()
				owner = (seat :: VehicleSeat):GetNetworkOwner()
			end)
			if owner == player then
				return
			end
			pcall(function()
				(seat :: VehicleSeat):SetNetworkOwner(player)
			end)
			task.wait(0.1)
		end
	end)
end

function PlayerFlow.unseat(player: Player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Sit then
		hum.Sit = false
	end
	local car = PlayerFlow.getVehicle(player)
	local seat = car and car:FindFirstChild("DriveSeat")
	if seat and seat:IsA("VehicleSeat") then
		seat.Disabled = true -- обратно не сесть
	end
end

function PlayerFlow.releaseVehicle(player: Player)
	local car = vehicleOfPlayer[player]
	vehicleOfPlayer[player] = nil
	VehicleRegistry.ClearPlayer(player)
	-- ИНТЕРФЕЙС AC6 ГАСИМ ПЕРВЫМ, И ЭТО НЕ ПРИДИРКА К ПОРЯДКУ. Его Drive/Burnout/Smoke
	-- (все живут ВНУТРИ "A-Chassis Interface" в PlayerGui) висят на событиях машины.
	-- Уничтожение модели снимает SeatWeld → у Burnout срабатывает DriveSeat.ChildRemoved
	-- → он лезет в car.Wheels уже опустошённой модели и роняет в лог «Wheels is not a
	-- valid member». Снести интерфейс ПОСЛЕ машины — значит опоздать ровно на этот кадр:
	-- обработчик успевает отработать. Снесённый заранее, он и не подписан больше ни на что.
	-- Свежий интерфейс копируется заново при следующей посадке (Initialize на SeatWeld).
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if pg then
		for _, iface in pg:GetChildren() do
			if iface.Name == "A-Chassis Interface" then
				iface:Destroy()
			end
		end
	end
	if car and car.Parent then
		car:Destroy() -- ← чинит накопление машин
	end
end

-- Все выданные машины (для occupiedSeats MatchManager-а)
function PlayerFlow.vehicles(): { [Player]: Model }
	return vehicleOfPlayer
end

-- // Хуки ---------------------------------------------------------------------
local function onCharacterAdded(player: Player)
	task.wait(0.2) -- дать персонажу собраться
	local car = PlayerFlow.getVehicle(player)
	if car and not car:GetAttribute("Eliminated") then
		-- гонщик погиб посреди заезда → назад за руль, гонка продолжается
		PlayerFlow.seatDriver(player)
	else
		PlayerFlow.sendToLobby(player) -- к старту + заморозка
	end
end

local initialized = false
function PlayerFlow.init()
	if initialized then
		return
	end
	initialized = true

	captureGridBase()
	ensureTemplate()

	-- грид и точка старта — на старте новой трассы (из MapLayout, форма Road.svg).
	-- Высоту берём РЕЙКАСТОМ по фактической поверхности дороги (террейн рендерится
	-- выше номинального top), иначе колёса уходят в грунт → машину ломает на спавне.
	local sg = MapLayout.Landmarks.StartGate
	local sd = MapLayout.StartDir
	if sg and sd and (Vector2.new(sd.X, sd.Y).Magnitude > 1e-3) then
		local top = GameConfig.Map.GroundTop or 2
		local sx, sz = sg.Position.X * MapLayout.Scale, sg.Position.Y * MapLayout.Scale
		local dir = Vector3.new(sd.X, 0, sd.Y).Unit

		-- Место игрока под заставкой — ПОЗАДИ всей колонны (иначе машина заднего
		-- ряда спавнится прямо в стоящего игрока) и НА ОБОЧИНЕ.
		--
		-- Раньше точка лежала прямо на осевой — то есть ждущие стояли посреди
		-- полотна. Трасса замкнута, гонщик проходит это место КАЖДЫЙ круг, а
		-- ждущие заморожены и увернуться не могут: получалась толпа на racing line
		-- (юзер поймал это на скриншоте с тестовыми клиентами Studio). Отходим вбок
		-- за край полотна и выбираем ту сторону, где меньше декора.
		local function sideIsClear(at: Vector3): number
			local n = 0
			for _, part in workspace:GetPartBoundsInRadius(at, LOBBY_CLEAR_RADIUS) do
				if part.CollisionGroup == "Obstacles" then -- весь декор карты
					n += 1
				end
			end
			return n
		end
		local function lobbyCF(y: number): CFrame
			local depth = gridDepthStuds > 0 and gridDepthStuds or (GRID_ROWS - 1) * GRID_ROW_GAP
			local p, fwd = trackPointBehind(depth + 22)
			local at, forward
			if p and fwd then
				at, forward = Vector3.new(p.X, y, p.Y), Vector3.new(fwd.X, 0, fwd.Y)
			else
				at, forward = Vector3.new(sx, y, sz) - dir * (depth + 22), dir
			end
			local side = Vector3.new(-forward.Z, 0, forward.X) -- перпендикуляр к полотну
			local left, right = at - side * LOBBY_SIDE, at + side * LOBBY_SIDE
			local spot = sideIsClear(left) <= sideIsClear(right) and left or right
			-- лицом к трассе: под заставкой видно решётку и проезжающих
			return CFrame.lookAt(spot, Vector3.new(at.X, spot.Y, at.Z))
		end

		-- дефолт до готовности террейна
		gridBaseSeatCF = CFrame.lookAt(Vector3.new(sx, top + 10, sz), Vector3.new(sx, top + 10, sz) + dir)
		buildGridSlots(top + 10)
		START_CF = lobbyCF(top + 8)
		task.spawn(function()
			local rp = RaycastParams.new()
			rp.FilterType = Enum.RaycastFilterType.Include
			rp.FilterDescendantsInstances = { workspace.Terrain }
			for _ = 1, 80 do
				local r = workspace:Raycast(Vector3.new(sx, 80, sz), Vector3.new(0, -160, 0), rp)
				if r and r.Material == Enum.Material.Ground then
					local sy = r.Position.Y
					gridBaseSeatCF = CFrame.lookAt(Vector3.new(sx, sy + 6, sz), Vector3.new(sx, sy + 6, sz) + dir)
					buildGridSlots(sy + 6) -- полотно плоское → одна высота на всю колонну
					START_CF = lobbyCF(sy + 4)
					return
				end
				task.wait(0.2)
			end
		end)
	else
		local spawn = workspace:FindFirstChildOfClass("SpawnLocation")
		if spawn then
			START_CF = spawn.CFrame + Vector3.new(0, 3, 0)
		end
	end

	local function hook(player: Player)
		player.CharacterAdded:Connect(function()
			onCharacterAdded(player)
		end)
		if player.Character then
			onCharacterAdded(player)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
	Players.PlayerRemoving:Connect(PlayerFlow.releaseVehicle)

	print("[PlayerFlow] Старт у грида, решётка записана, свободные машины убраны (без платформы).")
end

return PlayerFlow
