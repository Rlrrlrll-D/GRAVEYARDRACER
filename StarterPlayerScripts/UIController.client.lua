--!strict
-- LocalScript: StarterPlayerScripts.UIController
-- Builds the HUD at runtime and keeps it in sync via Remotes.UpdateStats.
-- Also handles the CameraShake remote for hazard collisions.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService") -- нужен улёту: ищет машину игрока
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local updateStats = remotes:WaitForChild("UpdateStats") :: RemoteEvent
local cameraShakeEvent = remotes:WaitForChild("CameraShake") :: RemoteEvent
local raceUpdate = remotes:WaitForChild("RaceUpdate") :: RemoteEvent
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local PlateArt = require(ReplicatedStorage:WaitForChild("PlateArt"))

local player = Players.LocalPlayer

-- Чекпоинт (юзер: «поменяй звук прохода чекпоинтов на что-нибудь ghost-образное»).
-- Был волшебный звон Twinkle08 — сказочный, из другой игры. Теперь «Eerie Whispering,
-- Reverberant» (ProSoundEffects, 2.3с): шёпот с эхом, будто на скорости проскочил
-- сквозь кого-то. Длительность выбрана не на слух: чекпоинтов 12 на 3128 studs, то
-- есть на скорости они идут раз в ~2.9с — звук длиннее наложился бы сам на себя.
local SoundService = game:GetService("SoundService")
local checkpointSound = Instance.new("Sound")
checkpointSound.SoundId = "rbxassetid://9114228524"
checkpointSound.Volume = 0.6
checkpointSound.Parent = SoundService

local finishSound = Instance.new("Sound")
finishSound.SoundId = "rbxassetid://4961240438" -- грозовой раскат: драматичный крип-стинг на финиш
finishSound.Volume = 0.7
finishSound.Parent = SoundService

-- Предзагрузка звуков — чтобы чекпоинт/финиш не молчали при первом срабатывании.
task.spawn(function()
	pcall(function()
		game:GetService("ContentProvider"):PreloadAsync({ checkpointSound, finishSound })
	end)
end)
local lastCheckpointIndex: number? = nil
local playerGui = player:WaitForChild("PlayerGui")

-- // Build UI ------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GraveyardHUD"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- // ПЛАШКИ HUD — ТЕ ЖЕ МАЗКИ, ЧТО В МЕНЮ (PlateArt) --------------------------
-- Требование юзера: интерфейс в игре не должен отличаться от заставки. Прежде HUD
-- был набором цветных прямоугольников, а меню — мазками кистью из вектора; на одном
-- экране это читалось как два разных интерфейса.
--
-- ПЛАШКИ ПОДРОСЛИ С 220×30 ДО 250×46 не ради красоты: мазок в исходнике 384×95, то
-- есть примерно 4:1. Растянутый в 220×30 (7,3:1) он превращается в мазню — щетина
-- размазывается вдоль, рваные концы теряются. 250×46 (5,4:1) уже держит форму.
--
-- Цвета остались прежними и в прежнем чередовании (красный → мох → кость): плашки
-- различаются по смыслу, а не по прихоти. Форму мазка выбирает PlateArt по номеру,
-- поэтому соседние плашки заведомо не одинаковые.
local PLATE_W, PLATE_H = 250, 46
local PLATE_STEP = 52 -- шаг столбца: высота плашки + просвет
local PLATE_X = 20 -- поле от края экрана
local PLATE_Y = 14

local function hudPlate(index: number, color: Color3, anchorRight: boolean, row: number): Frame
	local plate = PlateArt.plate(index, color)
	plate.Size = UDim2.fromOffset(PLATE_W, PLATE_H)
	if anchorRight then
		plate.AnchorPoint = Vector2.new(1, 0)
		plate.Position = UDim2.new(1, -PLATE_X, 0, PLATE_Y + row * PLATE_STEP)
	else
		plate.Position = UDim2.new(0, PLATE_X, 0, PLATE_Y + row * PLATE_STEP)
	end
	plate.Parent = screenGui
	return plate
end

-- ЗДОРОВЬЕ — ПОЛОСА, А НЕ НАДПИСЬ, и мазком это тоже надо было сохранить. Внутри
-- плашки-подложки лежит рамка с ClipsDescendants, а в ней ВТОРОЙ мазок, во всю
-- ширину плашки. Сужается рамка, а не мазок: щетина не растягивается, красное
-- просто убывает слева направо, как краска сходит с кисти.
-- Подложка КОСТЯНАЯ, а не тёмная. С тёмной (PanelBg) пустая часть шкалы на светлом
-- небе пропадала, и полоса выглядела всегда полной — юзер это увидел на первом же
-- снимке. Костяная подложка убыль показывает сразу.
local healthPlate = hudPlate(4, UITheme.cycleColor(3), true, 0)
healthPlate.Name = "Health"

local healthMask = Instance.new("Frame")
healthMask.Name = "FillMask"
healthMask.Size = UDim2.new(1, 0, 1, 0)
healthMask.BackgroundTransparency = 1
healthMask.ClipsDescendants = true
healthMask.Parent = healthPlate

local healthFill = PlateArt.plate(4, UITheme.Palette.Red)
healthFill.Name = "HealthFill"
healthFill.Size = UDim2.fromOffset(PLATE_W, PLATE_H) -- в пикселях: маска его НЕ жмёт
healthFill.Parent = healthMask

-- Буквы КОСТЯНЫЕ с тёмной обводкой: они лежат сразу на двух фонах — на красной
-- заливке слева и на костяной подложке справа. Костяное на красном читается само,
-- костяное на костяном держит обводка, поэтому она здесь плотнее обычной.
local healthLabel = PlateArt.caption(healthPlate, "Health", UITheme.Ink)
healthLabel.TextStrokeTransparency = 0.1

local speedPlate = hudPlate(1, UITheme.cycleColor(1), false, 0) -- красный
speedPlate.Name = "Speedometer"
local speedLabel = PlateArt.caption(speedPlate, "0 mph", UITheme.Ink)

local zombiePlate = hudPlate(2, UITheme.cycleColor(2), false, 1) -- тёмно-зелёный
zombiePlate.Name = "ZombiesDefeated"
local zombieLabel = PlateArt.caption(zombiePlate, "Zombies Defeated: 0", UITheme.Ink)

-- Кости — валюта заезда, третьи в левом столбце: SPEED и ZOMBIES уже там, и все три
-- величины растут по ходу гонки. Чередование цветов продолжается, поэтому на костяной
-- плашке буквы тёмные (PlateArt.caption сам решает по светлоте, ставить ли обводку).
local bonesPlate = hudPlate(3, UITheme.cycleColor(3), false, 2) -- кость
bonesPlate.Name = "Bones"
local bonesLabel = PlateArt.caption(bonesPlate, "Bones: 0", UITheme.Palette.Red)

local livesPlate = hudPlate(5, UITheme.cycleColor(3), true, 1) -- кость, симметрично ZOMBIES
livesPlate.Name = "Lives"
local livesLabel = PlateArt.caption(livesPlate, "Lives: 3", UITheme.Palette.Red)

local wreckedPlate = PlateArt.plate(6, UITheme.Palette.Red)
wreckedPlate.Name = "WreckedBanner"
wreckedPlate.Size = UDim2.fromOffset(460, 78)
wreckedPlate.AnchorPoint = Vector2.new(0.5, 0.5)
wreckedPlate.Position = UDim2.new(0.5, 0, 0.35, 0)
wreckedPlate.Visible = false
wreckedPlate.Parent = screenGui
local wreckedLabel = PlateArt.caption(wreckedPlate, "VEHICLE DESTROYED", UITheme.Ink, 34)

-- // Race HUD --------------------------------------------------------------
local racePlate = PlateArt.plate(7, UITheme.Palette.Green)
racePlate.Name = "RaceStatus"
racePlate.Size = UDim2.fromOffset(420, 50)
racePlate.AnchorPoint = Vector2.new(0.5, 0)
racePlate.Position = UDim2.new(0.5, 0, 0, PLATE_Y)
racePlate.Parent = screenGui
local raceLabel = PlateArt.caption(racePlate, "", UITheme.Ink, 28)

local raceCenter = Instance.new("TextLabel")
raceCenter.Name = "RaceCenter"
raceCenter.Size = UDim2.new(0, 520, 0, 90)
raceCenter.Position = UDim2.new(0.5, -260, 0.2, 0)
raceCenter.BackgroundTransparency = 1
raceCenter.TextColor3 = Color3.fromRGB(255, 220, 120)
raceCenter.Font = UITheme.Font
raceCenter.TextScaled = true
raceCenter.TextStrokeTransparency = 0.4
raceCenter.Text = ""
raceCenter.Parent = screenGui

-- Стрелка-компас: крутится к СЛЕДУЮЩЕМУ чекпоинту относительно камеры.
-- На старте указывает на чекпоинт №1 — видно, в какую сторону ехать.
local arrowFrame = Instance.new("Frame")
arrowFrame.Name = "CheckpointArrow"
arrowFrame.AnchorPoint = Vector2.new(0.5, 0.5)
arrowFrame.Size = UDim2.new(0, 56, 0, 56)
arrowFrame.Position = UDim2.new(0.5, 0, 0.72, 0)
arrowFrame.BackgroundTransparency = 1
arrowFrame.Visible = false
arrowFrame.Parent = screenGui

for _, side in { -1, 1 } do -- шеврон "∧" из двух планок
	local wing = Instance.new("Frame")
	wing.AnchorPoint = Vector2.new(0.5, 0.5)
	wing.Size = UDim2.new(0, 7, 0, 30)
	wing.Position = UDim2.new(0.5, side * 9, 0.5, 6)
	wing.Rotation = side * 40
	wing.BackgroundColor3 = Color3.fromRGB(224, 214, 170) -- кость (был мятный)
	wing.BorderSizePixel = 0
	wing.Parent = arrowFrame
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 3)
	corner.Parent = wing
end

local arrowDistance = Instance.new("TextLabel")
arrowDistance.Name = "CheckpointDistance"
arrowDistance.AnchorPoint = Vector2.new(0.5, 0)
arrowDistance.Size = UDim2.new(0, 120, 0, 20)
arrowDistance.Position = UDim2.new(0.5, 0, 0.72, 34)
arrowDistance.BackgroundTransparency = 1
arrowDistance.TextColor3 = Color3.fromRGB(224, 214, 170)
arrowDistance.TextStrokeTransparency = 0.6
arrowDistance.Font = UITheme.Font
arrowDistance.TextScaled = true
arrowDistance.Visible = false
arrowDistance.Parent = screenGui

local arrowTargetIndex: number? = nil -- индекс чекпоинта, куда показывает стрелка

type RacePayload = {
	Phase: string,
	Countdown: number?,
	Go: boolean?,
	Lap: number?,
	Laps: number?,
	Position: number?,
	Racers: number?,
	NextCheckpoint: number?,
	PlayerWon: boolean?,
	Winner: string?,
	Eliminated: boolean?,
	Waiting: number?,
	Needed: number?,
	WaitLeft: number?, -- секунд до старта неполным составом; nil = порог уже набран
}

-- // ПЛАШКА-ЧЕРЕП КАК НАСТОЯЩАЯ НЕОНОВАЯ ДЕТАЛЬ ------------------------------
--
-- Юзер: «ты можешь сделать плашку неоновой как стрелки?». Может — но только если
-- силуэт перестанет быть картинкой. Material = Neon есть у ДЕТАЛИ, у ImageLabel его
-- нет и быть не может, а блюм берёт лишь то, что ярче единицы (BloomEffect.Threshold
-- = 1.5 в этом плейсе): пиксель UI ярче 1.0 не бывает, потому у плашки и не было
-- ореола, сколько её ни высветляй.
--
-- ЧЕРЕП — ОБВОДКА, А НЕ ЗАЛИВКА. Юзер: «максимум свечения при минимуме толщины».
-- Сплошная заливка читалась наклейкой именно потому, что она сплошная: у стрелки
-- старта ровно те же Neon и цвет, но она узкая полоса — глаз видит ЛИНИЮ СВЕТА, а
-- не пятно. Поэтому череп теперь тонкая лента по контуру, принцип детали тот же.
--
-- Контур взят из НАСТОЯЩЕГО вектора (ReplicatedStorage.SkullOutline, разобран из
-- D:\VECTOR\skull.ai — три замкнутых контура, 32 кривые Безье). Прежний трафарет —
-- заливка, траченная по пикселям PNG; для линии она не годится: обводка полигона со
-- ступеньками даёт рваную толщину, а из кривых лента ровная на любой ширине.
--
-- ЧИСЛА ПОДОБРАНЫ ЮЗЕРОМ ЖИВЬЁМ (временный _NeonTune, клавиши в плей), потому что
-- ореол рисует только BloomEffect, а он не попадает в мои захваты экрана: авто-
-- качество в нефокусном окне Studio выкидывает блюм из конвейера, и увидеть его мог
-- только живой глаз. Снятые показания: толщина 0.18, размер 4, цвет как у стрелок,
-- прозрачность 0, Bloom Intensity 1.0 (последнее — в EnvironmentConfig).
--
-- ПОЧЕМУ НА КЛИЕНТЕ, а не на сервере: меш, построенный из EditableMesh, не
-- реплицируется — сервер собрал бы его себе, а игроки увидели бы пустоту. Сервер
-- поэтому держит только невидимый якорь (RaceScene), а вид навешивает каждый клиент.
local AssetService = game:GetService("AssetService")
-- ЯРКОСТЬ ПРИГЛУШЕНА НА 20% (2026-08-08, юзер: «убрать чуть-чуть свечения у черепов,
-- слишком ярко»). Было 110,255,170 — ровно цвет стрелок старта (BuildTemplates), юзер
-- сам просил их сравнять. Теперь НЕ РОВНО: ореол у Neon растёт от яркости цвета, и
-- убавить его, не тронув цвет, нечем — Transparency на тонкой ленте только съедает саму
-- линию (см. plate.Transparency ниже), а BloomIntensity общий на всю сцену и утащил бы
-- за собой фары, фонари и те же стрелки. Захочется вернуть пару «череп = стрелки» —
-- либо вернуть 110,255,170 здесь, либо приглушить и стрелки в BuildTemplates.
-- Бело-голубой вариант (110,190,255) остался в истории.
--
-- ВТОРОЙ ЗАХОД, ШАГ КРУПНЫЙ (2026-08-09, юзер: «черепа не ослаблены по свету»).
-- Первая попытка убавила яркость на 20% (110,255,170 → 88,204,136) и на глаз не дала
-- ничего: ореол рисует BloomEffect, а он берёт всё, что ярче порога 1.5, — пока цвет
-- заметно выше порога, размер гало почти не меняется. Мелкими шагами тут гадать нельзя
-- ещё и потому, что блюм не попадает в мои захваты экрана: каждая проверка стоит
-- полного круга через тебя. Поэтому сразу вдвое от исходного. Перелёт (череп стал
-- тусклым) чинить проще, чем ещё три незаметных шага.
-- ВЕРНУЛИ ИСХОДНЫЙ ЦВЕТ СТРЕЛОК (2026-08-10). История: 110,255,170 стояли с самого
-- начала и светились; по просьбе «убрать чуть-чуть свечения» я срезал яркость сперва до
-- 88,204,136, потом до 55,128,85 — и ореол пропал совсем, потому что блюм берёт только
-- то, что ярче порога 1.5, а половинный неон до него не дотягивает. Дальше я вместо
-- отката выдумал версию про толщину линии и полез строить под неё ползунок — версия
-- оказалась неверной, свечение держал цвет. Если снова покажется ярко, уменьшать надо
-- РАЗМЕР (SKULL_WIDTH) или порог блюма, но не яркость: у неё край обрыва, а не спуск.
-- 2026-08-10: юзер подобрал живьём ЗОЛОТОЙ вместо зелёного (был 110,255,170 — цвет
-- стрелок старта). Вместе с ним подобраны толщина 0.04 и блюм 0.50/0.35.
local SKULL_COLOR = Color3.fromRGB(252, 213, 62)
-- ЧЕРЕП ВДВОЕ МЕНЬШЕ, СВЕЧЕНИЕ ТО ЖЕ (2026-08-09, юзер: «уж очень они здоровые»).
-- Менять механизм не понадобилось: размер и толщина линии тут УЖЕ независимы, просто
-- это неочевидно из кода. Меш нормирован к ширине рисунка 1, лента в нём занимает долю
-- SKULL_STROKE / SKULL_WIDTH, а потом деталь умножается на SKULL_WIDTH — доля и
-- множитель сокращаются, и абсолютная толщина ленты всегда равна SKULL_STROKE, какой бы
-- ни была ширина черепа. Угловое масштабирование по дистанции тянет модель целиком,
-- поэтому на экране линия остаётся ровно той же в пикселях, а череп ужимается вдвое.
-- Иначе говоря: за «видно издалека» отвечает SKULL_STROKE, за габарит — SKULL_WIDTH,
-- и трогать первый ради второго не нужно.
local SKULL_WIDTH = 2 -- ширина черепа в studs (было 4)
-- 0.08 подобрано юзером живьём (2026-08-10, ползунок «Толщ» в NeonTune) вместе с
-- блюмом: Intensity 0.55, Threshold 1.35 — см. EnvironmentConfig/AtmosphereSetup. Линия
-- стала вдвое тоньше прежней, а ореол вернулся за счёт блюма, а не за счёт цвета.
local SKULL_STROKE = 0.03 -- толщина линии в studs — НЕ ТРОГАТЬ ради размера, см. выше
local plateTemplate: BasePart? = nil
local plateTried = false

-- Вершина ленты хранит не готовую точку, а СПОСОБ ЕЁ ПОЛУЧИТЬ: точку осевой линии
-- контура (cx, cy), нормаль к ней (nx, ny) и сторону (sign = ±1). Позиция считается как
-- «отойти от осевой на полтолщины в свою сторону».
--
-- Так сделано ради ТОЛЩИНЫ. Она — единственное, что отделяет светящуюся стрелку от
-- несветящегося черепа: блюм берёт уже нарисованные пиксели, а линия в доли пикселя при
-- сглаживании смешивается с фоном и не дотягивает до порога. Храня осевую с нормалью,
-- толщину можно менять на живом меше одним проходом по вершинам — без пересборки, то
-- есть и в плей, и без расхода бюджета EditableMesh.
--
-- Деформацию (S-изгиб) считаем ВСЕГДА от этой базы, а не от предыдущего кадра, иначе
-- ошибка накапливается и череп уползает.
type RibbonVertex = {
	id: number,
	cx: number,
	cy: number,
	nx: number,
	ny: number,
	sign: number,
	z: number,
}

-- Позиция вершины при толщине w (в долях ширины рисунка).
local function vertexBase(v: RibbonVertex, w: number): (number, number)
	return v.cx + v.sign * v.nx * w * 0.5, v.cy + v.sign * v.ny * w * 0.5
end

local function buildRibbon(): (BasePart?, any?, { RibbonVertex }?)
	local okShape, shape = pcall(function()
		return require(ReplicatedStorage:WaitForChild("SkullOutline", 10))
	end)
	if not okShape or type(shape) ~= "table" then
		warn("[UIController] SkullOutline не найден — череп-чекпоинт не собран")
		return nil
	end
	-- EditableMesh НЕЛЬЗЯ уничтожать, пока жива собранная из него деталь: MeshPart
	-- продолжает ссылаться на этот объект (`MeshContent = SourceType=Object`), и после
	-- `em:Destroy()` деталь перестаёт рисоваться совсем — размер и MeshSize остаются
	-- прежними, а в кадре пусто. Проверено A/B: два одинаковых черепа рядом, виден
	-- только тот, у которого меш живой. Поэтому держим его до конца сессии.
	--
	-- Обратная сторона: у EditableMesh свой бюджет памяти, и он невелик — замер дал
	-- ~8 таких мешей, дальше CreateEditableMesh молча возвращает nil. Здесь сборка
	-- одна на клиента, так что это безопасно; а вот пересобирать меш в цикле нельзя
	-- без освобождения ПРЕДЫДУЩЕГО (так сделано во временной подкрутке _NeonTune).
	local em = AssetService:CreateEditableMesh()
	if not em then
		warn("[UIController] EditableMesh не выдан — бюджет памяти исчерпан")
		return nil
	end
	local verts: { RibbonVertex } = {}
	local ok, part = pcall(function()
		-- Лента по каждому контуру: в каждой точке берём нормаль к линии (касательная,
		-- повёрнутая на 90°) и отступаем на полтолщины в обе стороны — получаются две
		-- кромки, между ними квадами и идёт лента. Толщина здесь в ДОЛЯХ ширины черепа:
		-- меш живёт в нормированных координатах, в studs его переводит Size.
		--
		-- Обе стороны из одного контура: вершины дублируются на +z и -z, треугольники
		-- у тыльной стороны идут в обратном порядке, иначе она отсекается по нормали.
		local halfT = 0.006 -- полутолщина ленты «в глубину»: тонкая, но не нулевая
		local w = SKULL_STROKE / SKULL_WIDTH
		for _, loop in ipairs(shape.Loops) do
			local n = #loop
			local innerF, outerF, innerB, outerB = {}, {}, {}, {}
			for k = 1, n do
				local cur = loop[k]
				local prev = loop[(k - 2) % n + 1]
				local nxt = loop[k % n + 1]
				local tx, ty = nxt[1] - prev[1], nxt[2] - prev[2]
				local len = math.sqrt(tx * tx + ty * ty)
				if len < 1e-9 then
					tx, ty, len = 1, 0, 1
				end
				local nx, ny = -ty / len, tx / len
				local ix, iy = cur[1] - nx * w / 2, cur[2] - ny * w / 2
				local ox, oy = cur[1] + nx * w / 2, cur[2] + ny * w / 2
				innerF[k] = em:AddVertex(Vector3.new(ix, iy, halfT))
				outerF[k] = em:AddVertex(Vector3.new(ox, oy, halfT))
				innerB[k] = em:AddVertex(Vector3.new(ix, iy, -halfT))
				outerB[k] = em:AddVertex(Vector3.new(ox, oy, -halfT))
				local cx, cy = cur[1], cur[2]
				table.insert(verts, { id = innerF[k], cx = cx, cy = cy, nx = nx, ny = ny, sign = -1, z = halfT })
				table.insert(verts, { id = outerF[k], cx = cx, cy = cy, nx = nx, ny = ny, sign = 1, z = halfT })
				table.insert(verts, { id = innerB[k], cx = cx, cy = cy, nx = nx, ny = ny, sign = -1, z = -halfT })
				table.insert(verts, { id = outerB[k], cx = cx, cy = cy, nx = nx, ny = ny, sign = 1, z = -halfT })
			end
			for k = 1, n do
				local j = k % n + 1
				em:AddTriangle(innerF[k], outerF[k], outerF[j])
				em:AddTriangle(innerF[k], outerF[j], innerF[j])
				em:AddTriangle(innerB[k], outerB[j], outerB[k])
				em:AddTriangle(innerB[k], innerB[j], outerB[j])
			end
		end
		return AssetService:CreateMeshPartAsync(Content.fromObject(em))
	end)
	if not ok or typeof(part) ~= "Instance" then
		em:Destroy() -- деталь не создана, ссылаться на меш некому — можно освободить
		warn("[UIController] меш черепа не собрался: " .. tostring(part))
		return nil
	end
	local plate = part :: MeshPart
	plate.Name = "Plate"
	-- Меш нормирован к ширине рисунка 1, поэтому множим на ширину в studs напрямую
	-- (лента добавляет к габариту свою полтолщины — ровно так и подбиралось живьём).
	plate.Size = plate.Size * SKULL_WIDTH
	plate.Material = Enum.Material.Neon -- ровно как стрелки старта
	plate.Color = SKULL_COLOR
	plate.Transparency = 0 -- по подбору: линии тонкие, гасить их прозрачностью нечем
	plate.Anchored = true
	plate.CanCollide = false
	plate.CanQuery = false
	plate.CanTouch = false
	plate.CastShadow = false
	return plate, em, verts
end

local templateMesh: any = nil
local templateVerts: { RibbonVertex }? = nil
local currentStroke = SKULL_STROKE -- в studs; меняется живьём подкруткой

local function applyStrokeTo(em: any, verts: { RibbonVertex }, strokeStuds: number)
	local w = strokeStuds / SKULL_WIDTH
	for _, v in verts do
		local x, y = vertexBase(v, w)
		em:SetPosition(v.id, Vector3.new(x, y, v.z))
	end
end

-- Толщина линии у ВСЕХ черепов разом: плашки-клоны ссылаются на один и тот же меш,
-- поэтому достаточно переставить его вершины.
local function setSkullStroke(strokeStuds: number)
	currentStroke = math.clamp(strokeStuds, 0.02, 1.5)
	if templateMesh and templateVerts then
		applyStrokeTo(templateMesh, templateVerts, currentStroke)
	end
end

local function buildPlateTemplate(): BasePart?
	if plateTried then
		return plateTemplate
	end
	plateTried = true
	-- меш держим живым: без него деталь не рисуется (см. выше)
	local plate, em, verts = buildRibbon()
	plateTemplate = plate
	templateMesh = em
	templateVerts = verts
	return plate
end

-- ДЕВ-ДОСТУП ДЛЯ ПОДКРУТКИ (NeonTune, только Studio). Толщина живёт здесь, а крутить её
-- надо из другого скрипта — отсюда общий стол в _G. Для игрового кода это ничего не
-- меняет: в живой игре ветка не выполняется, и ручки не существует.
if RunService:IsStudio() then
	_G.__SkullTune = {
		setStroke = setSkullStroke,
		getStroke = function()
			return currentStroke
		end,
	}
end

-- Навесить плашку на череп, если её там ещё нет (у каждого клиента своя).
local function ensurePlate(model: Model): BasePart?
	local existing = model:FindFirstChild("Plate")
	if existing and existing:IsA("BasePart") then
		return existing
	end
	local template = buildPlateTemplate()
	if not template then
		return nil
	end
	local plate = template:Clone()
	plate.CFrame = model:GetPivot() -- стартовое; дальше каждый кадр ставит aimPlate
	plate.Parent = model
	return plate
end

-- Плашка — деталь, а не билборд, поэтому «лицом к камере» её ставим сами. Двенадцать
-- CFrame за кадр — цена никакая, зато силуэт всегда развёрнут к водителю, как и был.
-- roll (градусы) — закрутка вокруг оси взгляда, ею пользуется растворение.
local function aimPlate(model: Model, roll: number?)
	local plate = model:FindFirstChild("Plate")
	if not (plate and plate:IsA("BasePart")) then
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	-- Позицию берём ОТ ПИВОТА МОДЕЛИ, а не от самой плашки. Так надёжнее: плашка
	-- создаётся клиентом в произвольный момент, и в первом заходе она осталась в
	-- начале координат — модель к тому времени ещё не была на месте. Раз мы всё равно
	-- трогаем её CFrame каждый кадр, пусть он и задаёт положение: тогда любой сдвиг
	-- черепа (парение, улёт) плашка подхватывает сама.
	local pivot = model:GetPivot().Position
	local cf = CFrame.lookAt(pivot, cam.CFrame.Position)
	plate.CFrame = roll and (cf * CFrame.Angles(0, 0, math.rad(roll))) or cf
end

-- Плотность ведём ОДНОЙ величиной fade: 0 — как построено (неон в полную силу), 1 — исчез.
local SKULL_BASE_ALPHA = 0
local function setSkullFade(model: Model, fade: number)
	local plate = ensurePlate(model)
	if plate then
		plate.Transparency = math.clamp(SKULL_BASE_ALPHA + (1 - SKULL_BASE_ALPHA) * fade, 0, 1)
	end
end

-- Найти маркер чекпоинта: череп помечен атрибутом cpN (один череп может обслуживать
-- несколько чекпоинтов при совпадении координат — перекрёсток восьмёрки); орб — по имени.
local function findMarker(index: number): Instance?
	local folder = workspace:FindFirstChild("RaceMarkers")
	if not folder then
		return nil
	end
	for _, m in folder:GetChildren() do
		if m:IsA("Model") and m:GetAttribute("cp" .. index) == true then
			return m
		end
	end
	return folder:FindFirstChild("Checkpoint" .. index)
end

-- Внешний вид плашки-черепа: «свой» следующий (active) — чуть крупнее и плотнее,
-- свет ярче; прочие — сильно полупрозрачные (призрачные), свет спокойный.
-- ПЛОТНОСТЬ ЧЕРЕПА. Прежние абзацы про «прозрачность плашки», билборд и ореолы
-- сняты вместе с самой плашкой: череп теперь неоновая геометрия (RaceScene).
-- ПАРАМЕТРЫ ЭФФЕКТА РАВНЫ СТРЕЛКАМ (требование юзера: «уровняй параметры эффектов у
-- плашки к стрелкам»). У шеврона старта ровно два: Material = Neon и Transparency =
-- 0.15 — и больше ничего, он всегда горит одинаково. Поэтому и у плашки затухания
-- сняты совсем: и свой чекпоинт, и чужие идут на тех же 0.15.
--
-- Прежние 0.12/0.25 и «дыхание» 0.07 были попыткой развести свой чекпоинт с чужими
-- ЯРКОСТЬЮ. Разводить есть чем и без неё: свой крупнее (SKULL_SCALE_ACTIVE), и это
-- ровно то различие, которое стояло здесь исторически. Вернуть приглушение — поднять
-- SKULL_FADE_IDLE, вернуть дыхание — SKULL_PULSE.
local SKULL_FADE_ACTIVE = 0 -- 0 = как построено: Neon + Transparency 0
local SKULL_FADE_IDLE = 0 -- столько же: приглушённых стрелок на старте не бывает
local SKULL_PULSE = 0 -- стрелки не «дышат»
local SKULL_SCALE_ACTIVE = 1.22 -- свой ещё и крупнее: видно, к какому едешь

local skullHome: { [Model]: CFrame } = {} -- «дом» каждого черепа (парение + сброс после сбора)
local collecting: { [Model]: boolean } = {} -- череп сейчас «улетает» вверх → парение его не трогает
local spent: { [Model]: boolean } = {} -- уже собран: прячем, пока игрок не отъедет
local function applySkullState(model: Model, active: boolean)
	if collecting[model] or spent[model] then return end -- улетающий и собранный не трогаем
	setSkullFade(model, active and SKULL_FADE_ACTIVE or SKULL_FADE_IDLE)
	-- Масштаб здесь НЕ трогаем: им управляет цикл парения, он держит угловой размер
	-- (дальний череп крупнее, чтобы линия на экране оставалась той же толщины).
end

local transformed: { [number]: boolean } = {} -- этот чекпоинт уже распался в текущем заходе

-- ПРИЗРАК УЛЁТА — СВОЙ МЕШ, А НЕ КЛОН ЧЕРЕПА. Клон ссылался бы на ТОТ ЖЕ EditableMesh,
-- что и все чекпоинты сразу: согнув его, мы согнули бы каждый череп на карте. Поэтому
-- лента собирается второй раз, отдельно. Он ОДИН на клиента и переиспользуется: за раз
-- распадается только один череп (сторожат transformed/collecting), а бюджет EditableMesh
-- невелик (~8 на сессию) — плодить по мешу на чекпоинт нельзя.
local ghostPart: BasePart? = nil
local ghostMesh: any = nil
local ghostVerts: { RibbonVertex }? = nil
local ghostMinY, ghostSpanY = 0, 1
local ghostBaseSize = Vector3.one
local ghostTried = false

local function ensureGhost(): BasePart?
	if ghostTried then
		return ghostPart
	end
	ghostTried = true
	local part, em, verts = buildRibbon()
	if not (part and em and verts) then
		return nil
	end
	part.Name = "GhostSkull"
	part.Size = part.Size * SKULL_WIDTH
	ghostBaseSize = part.Size -- запоминаем: перед каждым улётом домножаем на масштаб черепа
	part.Material = Enum.Material.Neon
	part.Color = SKULL_COLOR
	part.Transparency = 1 -- припаркован невидимым до первого сбора
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = workspace -- НЕ в RaceMarkers: туда лезет цикл парения

	local minY, maxY = math.huge, -math.huge
	for _, v in verts do
		if v.cy < minY then
			minY = v.cy
		end
		if v.cy > maxY then
			maxY = v.cy
		end
	end
	ghostPart, ghostMesh, ghostVerts = part, em, verts
	ghostMinY = minY
	ghostSpanY = math.max(maxY - minY, 1e-6)
	return part
end

-- S-ИЗГИБ ПО САМОЙ ФОРМЕ, А НЕ ПО ТРАЕКТОРИИ (2026-08-09, юзер прислал референс
-- D:\VECTOR\skull_S.ai). Раньше череп летел по синусоиде и закручивался, оставаясь
-- черепом, — то есть искажения формы не было вовсе. Теперь гнётся сама лента: смещение
-- по X считается от высоты точки, поэтому верх уходит в одну сторону, низ в другую, а
-- глазницы и зубы вытягиваются вдоль дуги ровно как на референсе.
--
-- Деформацию ВСЕГДА считаем от исходных координат вершины (RibbonVertex.x/y), а не от
-- предыдущего кадра: иначе ошибка накапливается и череп уползает от «дома».
-- ВОЛНА ДОЛЖНА БЕЖАТЬ ПО ТЕЛУ, А НЕ ЗАСТЫВАТЬ (2026-08-09, юзер: «он просто сначала
-- всё изогнёт, а потом это всё поднимет — нет, нужно змееобразное движение»). Раньше
-- фаза синуса была постоянной: череп принимал форму S и дальше ехал вверх этой самой
-- фигурой, то есть двигался как вырезанная из картона змейка. Теперь фаза едет со
-- временем (S_WAVE_SPEED) — гребни бегут снизу вверх по телу, и череп именно
-- извивается. Плюс сама траектория идёт синусоидой вбок (PATH_*), а не по прямой.
-- ВСЕ ПАРАМЕТРЫ ЗМЕЙКИ В ОДНОЙ ТАБЛИЦЕ, А НЕ КОНСТАНТАМИ. Подобрать их вслепую нельзя:
-- эффект длится секунду, я его через свой стенд ни разу не увидел, и три захода правок
-- ушли в пустоту. Таблицу крутит подкрутка (NeonTune, F6) прямо в плей.
local SNAKE = {
	waves = 2, -- изгибов ДОПОЛНИТЕЛЬНОГО извива тела (поверх кривой)
	amp = 0, -- 0 = дополнительного извива нет, всю форму задаёт кривая ниже
	stretch = 1.69, -- во столько раз череп вытягивается по высоте к концу улёта
	narrow = 0.4, -- и сужается по ширине: получается змейка, а не блин
	-- 0 = ВОЛНА ПО ТЕЛУ НЕ БЕЖИТ (уточнение юзера: «должно быть поступательное движение
	-- вверх по СТАТИЧНОЙ синусоиде»). Синусоида задана в пространстве и не шевелится, а
	-- череп просто едет по ней вверх — сама траектория и рисует змейку (pathWaves/
	-- pathAmps). Бегущая волна делала обратное: тело извивалось на месте, и движение
	-- читалось как дрожь. Поднять выше нуля — вернуть прежнее поведение.
	waveSpeed = 0,
	-- 5.73с подобрано юзером на стенде. ЭТО ДОЛГО ПО МЕРКАМ ЗАЕЗДА: на 60+ studs/с
	-- чекпоинт уходит за спину за доли секунды, так что почти весь улёт игрок досмотрит
	-- уже в зеркало заднего вида. На стенде камера стоит, и там это выглядит иначе.
	rise = 5.73, -- секунд на всю анимацию
	heights = 9, -- на столько СОБСТВЕННЫХ высот черепа поднимается
	-- САМА КРИВАЯ, по которой течёт тело. Размах теперь в ДОЛЯХ ШИРИНЫ РИСУНКА (меш
	-- нормирован к 1), а не в studs: 0.35 — заметный перегиб, но силуэт ещё читается.
	-- Прежние 2.5 «в ширинах черепа» и давали ту самую чрезмерную амплитуду.
	pathWaves = 1.5, -- полных волн, укладывающихся на длину пути
	pathAmps = 0.19, -- размах перегиба
	travel = 1, -- 1 = кривая неподвижна в пространстве (см. warpGhost); меньше — «плывёт» вместе с телом
	-- ЛЕТИТ ВМЕСТЕ С МАШИНОЙ (2026-08-10, юзер: «чтобы он не улетал сразу за спину»).
	-- Улёт длится 5.7с, а чекпоинт на 60+ studs/с уходит назад за доли секунды — почти
	-- вся анимация оставалась за спиной. Теперь призрак подхватывает СМЕЩЕНИЕ машины:
	-- 1 = висит относительно неё неподвижно (летит рядом всю дорогу), 0 = как раньше,
	-- остаётся у чекпоинта. Промежуточные значения дают «сначала летит с тобой, потом
	-- отстаёт» — за это отвечает followFade.
	follow = 0.85,
	followFade = 0.6, -- доля пути, после которой призрак начинает отставать
}

local function warpGhost(a: number)
	local verts, em = ghostVerts, ghostMesh
	if not (verts and em) then
		return
	end
	-- Размах набирается за первую пятую часть пути, дальше держится: иначе в начале
	-- череп ещё «доскладывается», и извив читается только к середине.
	local amp = SNAKE.amp * math.min(1, a * 5)
	local phase = a * SNAKE.waveSpeed * math.pi * 2
	local w = currentStroke / SKULL_WIDTH -- призрак наследует текущую толщину линии
	for _, v in verts do
		local bx, by = vertexBase(v, w)
		local t = (by - ghostMinY) / ghostSpanY -- 0 внизу черепа, 1 наверху
		-- ТЕЧЕНИЕ ПО КРИВОЙ, А НЕ ЕЗДА ЮЗОМ (уточнение юзера: «он идёт юзом по слишком
		-- амплитудной синусоиде, а должен искривляться, течь по ней вверх»). Раньше вбок
		-- двигали ДЕТАЛЬ целиком — жёсткий силуэт скользил по кривой боком. Теперь вбок
		-- смещается КАЖДАЯ ТОЧКА, и смещение зависит от её места на кривой: положение
		-- точки = её высота в теле плюс пройденный путь. Кривая в пространстве стоит,
		-- а тело по ней ползёт, поэтому перегиб каждый кадр другой — это и есть «течёт».
		-- ФАЗА СЧИТАЕТСЯ ОТ ВЫСОТЫ В МИРЕ, А НЕ ОТ МЕСТА В ТЕЛЕ. Прошлый заход брал
		-- фазу от координаты внутри меша — и кривая поднималась ВМЕСТЕ с деталью, то
		-- есть была какой угодно, только не статичной. Теперь к местной высоте точки
		-- прибавляется подъём детали, пересчитанный в единицы меша: волна остаётся
		-- стоять в пространстве, а тело сквозь неё протекает. travel = 1 — идеально
		-- неподвижная кривая; медленнее «течение» делается ползунком Длит (дольше
		-- подъём — медленнее всё), а не расстройкой этой связи.
		local upLocal = SNAKE.heights * ghostSpanY * a * SNAKE.travel
		local s = (by - ghostMinY) + upLocal
		local curve = math.sin(s / ghostSpanY * math.pi * 2 * SNAKE.pathWaves) * SNAKE.pathAmps
		local bend = math.sin(t * math.pi * 2 * SNAKE.waves - phase) * amp
		local x = bx * (1 - SNAKE.narrow * a) + curve + bend
		local y = ghostMinY + (by - ghostMinY) * (1 + SNAKE.stretch * a)
		em:SetPosition(v.id, Vector3.new(x, y, v.z))
	end
end


-- ПРЕВРАЩЕНИЕ ЧЕРЕПА В СТРУЙКУ. Запускается НА ПОДЛЁТЕ (цикл парения ниже), а не по
-- факту прохождения: на 60+ studs/с пройденный чекпоинт оказывается за спиной за
-- доли секунды, и всю анимацию игрок физически не видел. Проход по чекпоинту
-- остаётся страховочным триггером — если мимо черепа прошли по широкой дуге.
-- Для орба — no-op.
local function collectSkull(index: number)
	if transformed[index] then
		return -- дважды один череп не растворяем
	end
	local marker = findMarker(index)
	if not (marker and marker:IsA("Model")) then
		return
	end
	local model = marker :: Model
	if collecting[model] then
		return
	end
	if not model.PrimaryPart then
		return
	end
	transformed[index] = true
	local home = skullHome[model] or model:GetPivot()

	collecting[model] = true -- парение общий череп больше не трогает
	setSkullFade(model, 1) -- и он спрятан локально на время улёта

	local ghost = ensureGhost()
	if not ghost then
		-- меша не досталось (бюджет) — улёта не будет, но чекпоинт всё равно засчитан
		task.delay(SNAKE.rise, function()
			collecting[model] = nil
			spent[model] = true
		end)
		return
	end

	ghost.Color = SKULL_COLOR
	ghost.Transparency = SKULL_BASE_ALPHA
	-- РАЗМЕР БЕРЁМ У ТОГО ЧЕРЕПА, КОГО ПОДМЕНЯЕМ (2026-08-09, юзер: «при подъезде к
	-- черепу пропадает сияние»). Оно не пропадало — призрак выходил базового размера,
	-- тогда как настоящий череп у чекпоинта раздут угловым масштабом (на 30 studs это
	-- почти вдвое). Подмена вдвое меньшим силуэтом и читалась как «сияние исчезло».
	ghost.Size = ghostBaseSize * model:GetScale()
	warpGhost(0)

	-- Вбок змейка идёт ПОПЕРЁК ВЗГЛЯДА, иначе с половины ракурсов она уходит «в экран»
	-- и читается прямой. Ось берём один раз на старте: если пересчитывать её каждый
	-- кадр, поворот машины дёргал бы траекторию.
	local camAtStart = workspace.CurrentCamera
	local side = camAtStart and camAtStart.CFrame.RightVector or Vector3.xAxis
	side = Vector3.new(side.X, 0, side.Z)
	side = side.Magnitude > 1e-3 and side.Unit or Vector3.xAxis

	-- Размер призрака за время улёта не меняется, поэтому мерки берём один раз.
	local ghostH, ghostW = ghost.Size.Y, ghost.Size.X

	-- Откуда считать смещение машины: запоминаем её положение в момент запуска. Берём
	-- СИДЕНЬЕ, а не корпус — оно есть у любой машины и не пляшет от подвески.
	local function mySeat(): BasePart?
		for _, v in CollectionService:GetTagged("PlayerVehicle") do
			local seat = v:FindFirstChild("DriveSeat")
			if seat and seat:IsA("BasePart") and seat.Occupant then
				local char = seat.Occupant.Parent
				if char and Players:GetPlayerFromCharacter(char) == player then
					return seat
				end
			end
		end
		return nil
	end
	local seatAtStart = mySeat()
	local seatOrigin = seatAtStart and seatAtStart.Position or nil

	task.spawn(function()
		local t0 = os.clock()
		while true do
			local a = (os.clock() - t0) / SNAKE.rise
			if a >= 1 then
				break
			end
			warpGhost(a)
			-- ДЕТАЛЬ ИДЁТ СТРОГО ВВЕРХ. Вбок её больше не двигаем — иначе получается
			-- «юзом»: жёсткий силуэт скользит по кривой боком. Змейку рисует warpGhost,
			-- смещая вершины, то есть перегибая само тело.
			local pos = home.Position + Vector3.new(0, SNAKE.heights * ghostH * a, 0)
			-- Подхватываем смещение машины, чтобы улёт не остался за спиной. Держим его
			-- полным до followFade, дальше плавно отпускаем — призрак отстаёт сам, и это
			-- читается как «дух проводил и отвалился», а не как приклеенный к капоту.
			if seatOrigin and seatAtStart and seatAtStart.Parent then
				local k = SNAKE.follow
				if a > SNAKE.followFade and SNAKE.followFade < 1 then
					k *= 1 - (a - SNAKE.followFade) / (1 - SNAKE.followFade)
				end
				pos += (seatAtStart.Position - seatOrigin) * k
			end
			-- БЕЗ ЗАКРУТКИ (просьба юзера «без вращений»). Разворот к камере оставлен —
			-- без него лента с половины ракурсов видна с торца и исчезает, — но он
			-- ТОЛЬКО по горизонтали: цель взгляда берём на высоте самого черепа,
			-- поэтому плашка стоит строго вертикально и не кренится.
			local cam = workspace.CurrentCamera
			if cam then
				local eye = cam.CFrame.Position
				ghost.CFrame = CFrame.lookAt(pos, Vector3.new(eye.X, pos.Y, eye.Z))
			else
				ghost.CFrame = CFrame.new(pos)
			end
			-- ГАСНЕТ ТОЛЬКО В ПОСЛЕДНЕЙ ТРЕТИ. При прежнем a*a на длинном подъёме череп
			-- тускнел уже с середины, и извив досматривался вполсилы.
			local fade = math.max(0, (a - 0.65) / 0.35)
			ghost.Transparency = SKULL_BASE_ALPHA + (1 - SKULL_BASE_ALPHA) * fade * fade
			task.wait()
		end
		ghost.Transparency = 1
		warpGhost(0) -- вернуть ленту в исходную форму к следующему сбору
		collecting[model] = nil
		-- НЕ показываем сразу. Юзер: «после улёта я успеваю увидеть возвращённый
		-- череп» — так и было: улёт кончался ровно у чекпоинта, и череп вспыхивал
		-- прямо перед носом. Теперь его вернёт цикл парения, когда игрок отъедет.
		spent[model] = true
		setSkullFade(model, 1)
	end)
end

-- ПРИНУДИТЕЛЬНЫЙ ЗАПУСК ДЛЯ ПОДКРУТКИ (только Studio). Обычный распад требует, чтобы
-- чекпоинт был АКТИВНЫМ — а это выставляет только настоящий гоночный апдейт. Из-за
-- этого эффект нельзя было посмотреть иначе как проехав заезд, и три захода правок
-- ушли вслепую. Здесь все три сторожа снимаются руками, и эффект гоняется где угодно.
local function forceCollect(): string
	local folder = workspace:FindFirstChild("RaceMarkers")
	if not folder then
		return "RaceMarkers нет"
	end
	local char = player.Character
	local cam = workspace.CurrentCamera
	local from = (char and char.PrimaryPart and char.PrimaryPart.Position)
		or (cam and cam.CFrame.Position)
	if not from then
		return "не от чего мерить расстояние"
	end
	local best: Model?, bestD, bestIdx = nil, math.huge, nil
	for _, m in folder:GetChildren() do
		if m:IsA("Model") and m.PrimaryPart then
			local d = (m:GetPivot().Position - from).Magnitude
			if d < bestD then
				local idx = nil
				for i = 1, 40 do
					if m:GetAttribute("cp" .. i) == true then
						idx = i
						break
					end
				end
				if idx then
					best, bestD, bestIdx = m, d, idx
				end
			end
		end
	end
	if not (best and bestIdx) then
		return "поблизости нет черепа с меткой cpN"
	end
	transformed[bestIdx] = nil -- «уже распадался в этом заходе»
	collecting[best] = nil -- «сейчас летит»
	spent[best] = nil -- «собран, ждём отъезда»
	collectSkull(bestIdx)
	return string.format("запущен на %s, %.0f studs", (best :: Model).Name, bestD)
end

if RunService:IsStudio() then
	local tune = _G.__SkullTune
	if tune then
		tune.snake = SNAKE -- таблица живая: подкрутка меняет поля прямо во время анимации
		tune.playCollect = forceCollect
	end
end

-- Подсветка СВОЕГО следующего чекпоинта — локально, у каждого игрока своя
local activeSkullIndex: number? = nil -- за каким черепом сейчас следит цикл подлёта
local function highlightCheckpoint(index: number?)
	local folder = workspace:FindFirstChild("RaceMarkers")
	if not folder then return end
	if activeSkullIndex ~= index then
		activeSkullIndex = index
		if index then
			transformed[index] = nil -- новый заход на этот чекпоинт: распад снова разрешён
		end
	end
	for _, marker in folder:GetChildren() do
		if marker:IsA("Model") then
			-- череп активен, если обслуживает текущий чекпоинт (атрибут cpN)
			local active = index ~= nil and marker:GetAttribute("cp" .. index) == true
			applySkullState(marker, active)
		elseif marker:IsA("BasePart") then
			local id = marker.Name:match("%d+")
			local i = id and tonumber(id)
			if i then
				local active = (i == index)
				marker.Transparency = active and 0.5 or 0.78 -- орб: спокойный ободок, ленты — основной визуал
				marker.Size = active and Vector3.new(4, 4, 4) or Vector3.new(3, 3, 3)
			end
		end
	end
end

-- Черепа-чекпоинты видны только во время гонки (отсчёт/заезд), а не в
-- «ожидании игроков» и не после финиша. markersVisible=nil — первый вызов всегда срабатывает.
local markersVisible: boolean? = nil
local function setMarkersVisible(visible: boolean)
	if markersVisible == visible then return end
	markersVisible = visible
	local folder = workspace:FindFirstChild("RaceMarkers")
	if not folder then return end
	for _, m in folder:GetChildren() do
		if m:IsA("Model") then
			local anchor = m.PrimaryPart
			if anchor then
				local face = anchor:FindFirstChild("Face")
				if face and face:IsA("BillboardGui") then face.Enabled = visible end
				local light = anchor:FindFirstChildOfClass("PointLight")
				if light then light.Enabled = visible end
				-- Spirit — залповый (Rate=0, Enabled=false), его трогать не нужно:
				-- он и так молчит, пока его не выстрелит анимация распада.
			end
		elseif m:IsA("BasePart") then
			m.LocalTransparencyModifier = visible and 0 or 1 -- орб: скрыть локально
			for _, e in m:GetChildren() do
				if e:IsA("Trail") or e:IsA("ParticleEmitter") then e.Enabled = visible end
			end
		end
	end
end

-- Парение черепов-чекпоинтов — локально у каждого клиента (server держит их
-- статичными). Первый кадр фиксирует «дом» (GetPivot), дальше — синусоида по Y.
-- Череп в процессе распада (collecting) не парит — им управляет collectSkull.
-- РАЗМЕР ДЕРЖИМ УГЛОВОЙ. Юзер: «издалека свечения не видно». Виноват не блюм, а
-- толщина: линия 0.18 studs на 200+ studs тоньше пикселя — движку нечего рисовать,
-- а блюм берёт уже нарисованные пиксели, так что размывать ему тоже нечего.
-- Поэтому дальше SKULL_REF_DIST череп растёт пропорционально расстоянию: на экране
-- он всегда одного размера, и линия — одной толщины в пикселях. Ближе REF масштаб
-- держим на единице, чтобы у самого чекпоинта череп рос естественно, как предмет.
-- REF считан из ТОЛЩИНЫ ЛИНИИ НА ЭКРАНЕ, а не на глаз. Юзер подбирал образец в
-- ~16 studs от камеры: там череп занимал ~84 пикселя по высоте кадра, линия — около
-- 4 пикселей, и это ровно то, что он утвердил. Экранный размер = SKULL_WIDTH /
-- (2 * d * tan(FOV/2)) * высота кадра; при FOV 70 и 474 px четырёхпиксельной линии
-- отвечает d ≈ 20. На прежних 55 линия выходила В ОДИН пиксель — вот её и «не было
-- видно издалека», блюму нечего размывать, когда рисовать нечего.
local SKULL_REF_DIST = 20 -- на этой дистанции череп ровно SKULL_WIDTH studs
local SKULL_MAX_GROW = 10 -- то есть угловой размер держится до ~200 studs
local SKULL_HALF_HEIGHT = SKULL_WIDTH * 1.139 / 2 -- 1.139 = отношение сторон рисунка
-- Собранный череп возвращаем, только когда игрок отъехал (см. collectSkull).
local RESTORE_DIST = 90
-- ТРИГГЕР ПОДЛЁТА: как только «свой» череп ближе TRANSFORM_DIST, он начинает
-- превращаться в дым — чтобы анимацию было видно, а не угадывать по облачку в
-- зеркале. 30, а не прежние 46: на 46 весь улёт (0.8с) заканчивался ЕЩЁ ДО
-- чекпоинта, и игрок приезжал к пустому месту. На 30 машина влетает в облако.
local TRANSFORM_DIST = 30
RunService.Heartbeat:Connect(function()
	local folder = workspace:FindFirstChild("RaceMarkers")
	if not folder then return end
	local cam = workspace.CurrentCamera
	local char = player.Character
	local root = char and char.PrimaryPart
	local t = os.clock()
	for _, m in folder:GetChildren() do
		if m:IsA("Model") and m.PrimaryPart and not collecting[m] then
			local home = skullHome[m]
			if not home then
				home = m:GetPivot()
				skullHome[m] = home
			end
			if spent[m] then
				-- собран: висит спрятанным, пока игрок не отъехал
				if not root or (root.Position - home.Position).Magnitude > RESTORE_DIST then
					spent[m] = nil
					setSkullFade(m, SKULL_FADE_IDLE)
				end
			else
				local id = m.Name:match("%d+")
				local phase = (id and tonumber(id) or 0) * 0.7
				local y = math.sin(t * 1.3 + phase) * 0.9
				local idx = activeSkullIndex
				local isActive = idx ~= nil and m:GetAttribute("cp" .. idx) == true
				local scale = m:GetScale()
				if cam then
					-- Угловой размер держим ТОЛЬКО «своему» чекпоинту (решение юзера):
					-- он навигационный маркер, его и надо видеть издалека. Остальные —
					-- обычные предметы, физического размера, иначе полкадра в черепах.
					local want = 1
					if isActive then
						local dist = (home.Position - cam.CFrame.Position).Magnitude
						want = math.clamp(dist / SKULL_REF_DIST, 1, SKULL_MAX_GROW) * SKULL_SCALE_ACTIVE
					end
					-- ScaleTo обходит потомков, поэтому дёргаем его только на заметном
					-- изменении: на 2% размера глаз всё равно не ловит.
					if math.abs(scale - want) > want * 0.02 then
						m:ScaleTo(want)
						scale = want
					end
				end
				-- Масштаб растит череп в ОБЕ стороны от пивота, поэтому дальний, раздутый
				-- до 40 studs, уходил бы нижней половиной под террейн. Поднимаем ровно на
				-- прирост половины высоты — низ остаётся там же, где у нераздутого.
				y += SKULL_HALF_HEIGHT * (scale - 1)
				m:PivotTo(home + Vector3.new(0, y, 0))
				aimPlate(m) -- плашка-деталь сама к камере не поворачивается
				if isActive then
					-- «дыхание» плотности у своего черепа: живой, но всё равно воздушный
					setSkullFade(m, math.max(0, SKULL_FADE_ACTIVE + math.sin(t * 2.1) * SKULL_PULSE))
					if root and (root.Position - home.Position).Magnitude < TRANSFORM_DIST then
						collectSkull(idx :: number)
					end
				end
			end
		end
	end
end)

-- анимация-«пружинка» центрального баннера (GO/победа/финиш)
local raceCenterScale = Instance.new("UIScale")
raceCenterScale.Parent = raceCenter
local function popCenter()
	raceCenterScale.Scale = 0.35
	TweenService:Create(
		raceCenterScale,
		TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
end

raceUpdate.OnClientEvent:Connect(function(data: RacePayload)
	if data.Phase == "Idle" then
		local waiting = data.Waiting or 0
		local needed = data.Needed or 1
		local left = data.WaitLeft
		if type(left) == "number" and waiting > 0 then
			-- То же обещание, что и на экране лобби: ждём соперников, но не бесконечно
			-- (см. Race.SoloWaitSeconds). Без секунд строка выглядит как тупик.
			raceLabel.Text = string.format("Waiting for racers… %d/%d — starting in %ds", waiting, needed, math.ceil(left))
		elseif needed > 1 and waiting > 0 and waiting < needed then
			raceLabel.Text = string.format("Waiting for racers… %d/%d — press READY", waiting, needed)
		elseif needed > 1 then
			raceLabel.Text = string.format("Press READY to race — need %d racers", needed)
		else
			raceLabel.Text = "Press READY to start the race"
		end
		raceCenter.Text = ""
		highlightCheckpoint(nil)
		arrowTargetIndex = nil
		setMarkersVisible(false) -- в ожидании гонки черепов не видно
	elseif data.Phase == "Countdown" then
		raceLabel.Text = string.format("Race: %d laps — follow the green beacons", data.Laps or 3)
		raceCenter.TextColor3 = Color3.fromRGB(255, 220, 120)
		raceCenter.Text = tostring(data.Countdown)
		setMarkersVisible(true) -- гонка начинается → черепа появляются
		arrowTargetIndex = 1 -- ещё на отсчёте показываем, куда стартовать
		highlightCheckpoint(1)
		lastCheckpointIndex = nil -- сброс, чтобы старт не звенел ложно
	elseif data.Phase == "Racing" then
		setMarkersVisible(true) -- на случай подключения в середине заезда
		if data.Go then
			raceCenter.Text = "GO!"
			task.delay(1.5, function()
				if raceCenter.Text == "GO!" then
					raceCenter.Text = ""
				end
			end)
		end
		raceLabel.Text = string.format("Lap %d/%d   ·   Position %d/%d",
			data.Lap or 1, data.Laps or 3, data.Position or 1, data.Racers or 4)
		if data.NextCheckpoint then
			if lastCheckpointIndex ~= nil and data.NextCheckpoint ~= lastCheckpointIndex then
				checkpointSound:Play() -- прошёл чекпоинт → магический звон
				collectSkull(lastCheckpointIndex) -- дух улетает вверх с пройденного черепа (орб — no-op)
			end
			lastCheckpointIndex = data.NextCheckpoint
			highlightCheckpoint(data.NextCheckpoint)
			arrowTargetIndex = data.NextCheckpoint
		end
	elseif data.Phase == "Finished" then
		arrowTargetIndex = nil
		setMarkersVisible(false) -- заезд окончен → прячем до следующего
		popCenter()
		finishSound:Play()
		if data.Eliminated then
			raceCenter.TextColor3 = UITheme.Palette.Red
			raceCenter.Text = "GAME OVER — OUT OF LIVES"
		elseif data.PlayerWon then
			raceCenter.TextColor3 = Color3.fromRGB(255, 210, 70) -- золото
			raceCenter.Text = "YOU WIN!"
		else
			raceCenter.TextColor3 = UITheme.Palette.Red
			raceCenter.Text = string.upper(data.Winner or "GHOST") .. " WINS"
		end
	end
end)

-- // Компас на следующий чекпоинт -------------------------------------------
local function checkpointPosition(index: number): Vector3?
	local marker = findMarker(index)
	if marker then
		if marker:IsA("BasePart") then
			return marker.Position
		elseif marker:IsA("Model") then
			local pp = (marker :: Model).PrimaryPart
			return pp and pp.Position or (marker :: Model):GetPivot().Position
		end
	end
	return nil
end

RunService.RenderStepped:Connect(function()
	local index = arrowTargetIndex
	local camera = workspace.CurrentCamera
	local target = index and checkpointPosition(index)
	if not target or not camera then
		arrowFrame.Visible = false
		arrowDistance.Visible = false
		return
	end

	local camCF = camera.CFrame
	local forward = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
	local toTarget = Vector3.new(target.X - camCF.Position.X, 0, target.Z - camCF.Position.Z)
	if forward.Magnitude < 0.05 or toTarget.Magnitude < 1 then
		return -- камера смотрит вертикально или чекпоинт под нами — оставляем как есть
	end
	forward = forward.Unit
	local dir = toTarget.Unit
	-- знаковый угол между взглядом камеры и целью в плоскости XZ;
	-- Rotation у GUI растёт по часовой, поэтому минус
	local crossY = forward.Z * dir.X - forward.X * dir.Z
	local dot = forward.X * dir.X + forward.Z * dir.Z
	arrowFrame.Rotation = -math.deg(math.atan2(crossY, dot))
	arrowDistance.Text = string.format("%d studs", math.floor(toTarget.Magnitude))
	arrowFrame.Visible = true
	arrowDistance.Visible = true
end)

-- // Live updates ---------------------------------------------------------
type StatsPayload = {
	Health: number,
	MaxHealth: number,
	Speed: number,
	Fuel: number,
	Lives: number?,
	ZombiesDefeated: number,
	Bones: number?,
}

updateStats.OnClientEvent:Connect(function(stats: StatsPayload)
	local ratio = math.clamp(stats.Health / math.max(stats.MaxHealth, 1), 0, 1)
	TweenService:Create(healthMask, TweenInfo.new(0.2), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()
	healthLabel.Text = string.format("Health: %d / %d", stats.Health, stats.MaxHealth)
	speedLabel.Text = string.format("%d mph", math.floor(stats.Speed))
	zombieLabel.Text = string.format("Zombies Defeated: %d", stats.ZombiesDefeated)
	bonesLabel.Text = string.format("Bones: %d", stats.Bones or 0)
	local lives = stats.Lives or 3
	livesLabel.Text = lives > 0 and ("Lives: " .. string.rep("♥", lives)) or "Lives: OUT"

	if stats.Health <= 0 then
		if lives > 0 then
			wreckedLabel.Text = string.format("VEHICLE DESTROYED — %d left", lives)
		else
			wreckedLabel.Text = "GAME OVER"
		end
		wreckedPlate.Visible = true
		task.delay(4.5, function()
			wreckedPlate.Visible = false
		end)
	end
end)

-- // Camera shake on hazard hits ------------------------------------------
-- опция «тряска камеры» (веха 5): доставляется эхом SaveSettings→PushSettings
local cameraShakeOn = true
remotes:WaitForChild("PushSettings").OnClientEvent:Connect(function(s)
	if type(s) == "table" and type(s.cameraShake) == "boolean" then
		cameraShakeOn = s.cameraShake
	end
end)

cameraShakeEvent.OnClientEvent:Connect(function(intensity: number, duration: number)
	if not cameraShakeOn then
		return
	end
	task.spawn(function()
		local camera = workspace.CurrentCamera
		local startTime = os.clock()
		while os.clock() - startTime < duration do
			local offset = Vector3.new(
				(math.random() - 0.5) * intensity,
				(math.random() - 0.5) * intensity,
				0
			)
			camera.CFrame = camera.CFrame * CFrame.new(offset)
			RunService.RenderStepped:Wait()
		end
	end)
end)
