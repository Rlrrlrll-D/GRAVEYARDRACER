--!strict
-- LocalScript: StarterPlayerScripts.UIController
-- Builds the HUD at runtime and keeps it in sync via Remotes.UpdateStats.
-- Also handles the CameraShake remote for hazard collisions.

local Players = game:GetService("Players")
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
-- Цвет ТОТ ЖЕ, что у стрелок старта (BuildTemplates: 110,255,170) — юзер просил
-- «и цвет сделай как у стрелок и все остальные параметры». Бело-голубой вариант
-- (110,190,255) остался в истории: вернуть — поменять эту строку.
local SKULL_COLOR = Color3.fromRGB(110, 255, 170)
local SKULL_WIDTH = 4 -- ширина черепа в studs
local SKULL_STROKE = 0.18 -- толщина линии в studs
local plateTemplate: BasePart? = nil
local plateTried = false

local function buildPlateTemplate(): BasePart?
	if plateTried then
		return plateTemplate
	end
	plateTried = true
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
	plateTemplate = plate
	return plate
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

-- ПРЕВРАЩЕНИЕ ЧЕРЕПА В ДЫМ. Запускается НА ПОДЛЁТЕ (цикл парения ниже), а не по
-- факту прохождения: на 60+ studs/с пройденный чекпоинт оказывается за спиной за
-- доли секунды, и всю анимацию игрок физически не видел. Теперь череп распадается,
-- пока он ещё в кадре, и машина проезжает сквозь облако. Проход по чекпоинту
-- остаётся страховочным триггером — если мимо черепа прошли по широкой дуге.
-- Для орба — no-op.
local transformed: { [number]: boolean } = {} -- этот чекпоинт уже распался в текущем заходе
local function collectSkull(index: number)
	if transformed[index] then return end -- дважды один череп не растворяем
	local marker = findMarker(index)
	if not (marker and marker:IsA("Model")) then return end
	local model = marker :: Model
	if collecting[model] then return end
	local anchor = model.PrimaryPart
	if not anchor then return end
	transformed[index] = true
	local home = skullHome[model] or model:GetPivot()

	-- «Улёт» анимируем на КЛИЕНТ-ЛОКАЛЬНОМ КЛОНЕ, а общий череп прячем локально.
	-- Общий череп — сетевой инстанс: в Team Test окно-хост = сервер, его парение
	-- реплицируется и перебивало твин улёта у второго игрока (у него анимация «не
	-- срабатывала»). Клон сервер не знает — его никто не перебьёт; у каждого одинаково.
	collecting[model] = true -- локальное парение общий череп не трогает (applySkullState тоже пропустит)
	setSkullFade(model, 1) -- спрятать общий череп локально на время улёта

	local ghost = model:Clone()
	for _, d in ghost:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy() -- клон чисто визуальный, скрипты не нужны
		end
	end
	ghost.Name = "GhostSkull"
	ghost:PivotTo(home)
	ghost.Parent = workspace -- вне RaceMarkers → цикл парения его не трогает; клиент-локально
	local gAnchor = ghost.PrimaryPart

	-- Юзер: «нужно, чтобы S-образное искажение читалось СРАЗУ ПО ФОРМЕ ЧЕРЕПА и
	-- проходило быстрее». Было 0.6с и равномерное сжатие клона: змейку рисовала одна
	-- траектория, а сам силуэт до конца оставался черепом — то есть искажения по форме
	-- не было вовсе, и за 0.6с на скорости его читать было некогда.
	local RISE = 0.34

	-- S-ОБРАЗНЫЙ УЛЁТ + РАСПАД. Прямой твин Position змейку не даёт — ведём вручную:
	-- вверх с разгоном, поперёк — одна полная синусоида (вправо-назад-влево-назад).
	-- Поперечную ось берём от КАМЕРЫ, иначе с половины ракурсов змейка уходит «в
	-- экран» и читается как прямая. Никаких частиц: любой размытый спрайт на этой
	-- сцене читается как пятно, превращается САМ ЧЕРЕП.
	local gPlate = ghost:FindFirstChild("Plate")
	local baseSize = gPlate and gPlate:IsA("BasePart") and gPlate.Size or nil

	if gAnchor then
		local cam = workspace.CurrentCamera
		local side = cam and cam.CFrame.RightVector or Vector3.xAxis
		side = Vector3.new(side.X, 0, side.Z)
		side = side.Magnitude > 1e-3 and side.Unit or Vector3.xAxis
		local twist = (math.random() < 0.5 and -1 or 1) * 70 -- градусы, закрутка плашки
		local width = baseSize and baseSize.X or 4
		task.spawn(function()
			local t0 = os.clock()
			while ghost.Parent do
				local a = (os.clock() - t0) / RISE
				if a >= 1 then break end
				local up = 26 * a * a -- разгон вверх, как прежний Quad In
				-- Амплитуду ведём ОТ ШИРИНЫ ЧЕРЕПА и НЕ гасим к концу: змейка должна
				-- быть видна на всей дистанции, а не затухать на второй половине.
				local sway = math.sin(a * math.pi * 2) * width * 0.85
				ghost:PivotTo(home + Vector3.new(0, up, 0) + side * sway)
				-- ИСКАЖЕНИЕ ПО ФОРМЕ: череп не просто уменьшается, а вытягивается в
				-- струйку — ширина сходится почти в ноль, высота растёт втрое. Именно
				-- это делает S читаемым силуэтом, а не только траекторией.
				if gPlate and baseSize then
					gPlate.Size = Vector3.new(
						math.max(0.05, baseSize.X * (1 - 0.88 * a)),
						baseSize.Y * (1 + 2.1 * a),
						baseSize.Z
					)
				end
				aimPlate(ghost, twist * a) -- лицом к камере и с закруткой
				task.wait()
			end
		end)
	end

	-- гаснет не сразу: сначала видно, КАК он тянется, и только к концу исчезает
	if gPlate and gPlate:IsA("BasePart") then
		-- ОБЯЗАТЕЛЬНО вернуть плотность: клон снят уже ПОСЛЕ того, как общий череп
		-- спрятан (setSkullFade(model, 1)), то есть родился полностью прозрачным —
		-- и весь улёт шёл из невидимости в невидимость, юзер справедливо сказал
		-- «анимации улёта нет». Стартуем с той же плотности, какой череп горел.
		gPlate.Transparency = SKULL_BASE_ALPHA
		TweenService:Create(gPlate, TweenInfo.new(RISE, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
			{ Transparency = 1 }):Play()
	end

	task.delay(RISE + 0.2, function()
		ghost:Destroy()
		collecting[model] = nil
		-- НЕ показываем сразу. Юзер: «после улёта я успеваю увидеть возвращённый
		-- череп» — так и было: улёт кончался за 0.8с от триггера, то есть ровно у
		-- чекпоинта, и череп вспыхивал прямо перед носом. Теперь он остаётся
		-- спрятанным, а вернёт его цикл парения, когда игрок отъедет на RESTORE_DIST.
		spent[model] = true
		setSkullFade(model, 1)
	end)
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
