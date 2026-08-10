-- LocalScript: StarterPlayerScripts.NeonTune
-- ДЕВ-ПОДКРУТКА СВЕЧЕНИЯ ЧЕРЕПОВ-ЧЕКПОИНТОВ. Игроку не достаётся: только Studio
-- (или UserId из ALLOWED_USER_IDS, как в PhotoMode).
--
-- ЗАЧЕМ. Ореол вокруг неоновой ленты рисует BloomEffect, и он НЕ ПОПАДАЕТ В ЗАХВАТЫ
-- ЭКРАНА: авто-качество в нефокусном окне Studio выбрасывает блюм из конвейера, а
-- уровень качества закрыт капабилити и не фиксируется из скрипта. То есть подобрать
-- яркость я не могу в принципе — вижу только ты. Каждая догадка вслепую стоит полного
-- круга «правка → заливка → перезапуск → твой взгляд», и два таких круга уже ушли
-- впустую (шаг -20% на глаз не дал ничего). Здесь ты крутишь и видишь сразу.
--
-- РАСКЛАДКА. Стрелок здесь намеренно НЕТ: Roblox держит их за ядром (VirtualInput на
-- них отвечает «permanently bound to a CoreGUI core action»), а в заезде они бы ещё и
-- рулили машиной — крутить свет, одновременно уезжая в могилы, так себе занятие.
--   F6            вкл / выкл  (НЕ F7: тот занят Studio под «Run», ядро его не отдаёт)
--   ползунки R G B  цвет черепа мышью, 0..255
--   - / =         притушить / поднять ВСЕ три канала разом на 5% — быстрый способ
--                 менять яркость, не трогая оттенок
--   ; / '         Bloom Intensity ∓0.05  (ОБЩИЙ на сцену: тянет и фары, и фонари)
--   9 / 0         Bloom Threshold ∓0.05  (порог: что вообще начинает светиться).
--                 Не «,»/«.» — точку забирает система, до скрипта она не доходит.
--   Z             выключить зомби: иначе стая доедает машину, пока смотришь
--   K             стенд: улёт по кругу, камера сама. НЕ «O» — у юзера она до скрипта
--                 не доходит (проверено: K срабатывает, O нет, обе в одной цепочке)
--   \             сброс к тому, что стоит в конфиге
--   P             напечатать итоговые числа в Output — оттуда копировать мне
--
-- КРУТИТЬ МОЖНО ГДЕ УГОДНО, ЗАЕЗД НЕ НУЖЕН. Все 12 плашек существуют всегда и видны
-- всегда, включая лобби: UIController.setMarkersVisible гасит у чекпоинта билборд и
-- точечный свет, но саму неоновую ленту не трогает. (Похоже на недосмотр — по
-- комментарию рядом черепа задуманы «только во время гонки», — но для подкрутки это
-- удобно.) Пытаться прятать плашки отсюда бессмысленно: игровой цикл возвращает им
-- прозрачность обратно, проверено.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ALLOWED_USER_IDS: { number } = {}

local function isAllowed(): boolean
	if RunService:IsStudio() then
		return true
	end
	for _, id in ALLOWED_USER_IDS do
		if id == player.UserId then
			return true
		end
	end
	return false
end

if not isAllowed() then
	return
end

local TOGGLE_KEY = Enum.KeyCode.F6
local FONT = Enum.Font.Code

-- То, что стоит в UIController. Сюда же возвращает «\». Золотой подобран юзером
-- 2026-08-10 вместо прежнего зелёного (цвета стрелок старта).
local CONFIG_COLOR = Color3.fromRGB(252, 213, 62)

local active = false
-- ПОКАЗАТЬ ЧЕРЕПА В ЛОББИ. Плашки существуют всегда (все 12), но вне заезда UIController
-- держит их прозрачными — крутить свет вслепую невозможно, а затевать заезд ради каждой
-- подкрутки долго (порог MinRacers + соло-ожидание). По M временно делаем их видимыми.
-- На выходе возвращаем прозрачность: в лобби это верно само по себе, а в заезде
-- UIController перекрывает наше значение ближайшим RaceUpdate (они идут каждые 0.4с).
local forceVisible = false
local r, g, b = CONFIG_COLOR.R * 255, CONFIG_COLOR.G * 255, CONFIG_COLOR.B * 255
local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
local baseIntensity = bloom and bloom.Intensity or 1
local baseThreshold = bloom and bloom.Threshold or 1.5

-- // Панель ------------------------------------------------------------------
-- Правый нижний угол: левый занят панелью фото-режима, их могут держать включёнными
-- одновременно. IgnoreGuiInset НЕ ставим: ползунки ловят мышь, и AbsolutePosition
-- должен считаться в той же системе координат, что и input.Position (без инсета).
local gui = Instance.new("ScreenGui")
gui.Name = "NeonTune"
gui.ResetOnSpawn = false
gui.DisplayOrder = 1002
gui.Enabled = false
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(1, 1)
panel.Position = UDim2.new(1, -16, 1, -16)
panel.Size = UDim2.fromOffset(330, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundColor3 = UITheme.PanelBg
panel.BackgroundTransparency = 0.15
panel.BorderSizePixel = 0
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 12)
pad.PaddingBottom = UDim.new(0, 12)
pad.PaddingLeft = UDim.new(0, 14)
pad.PaddingRight = UDim.new(0, 14)
pad.Parent = panel

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 3)
layout.Parent = panel

local function makeLabel(order: number, height: number, size: number, transparency: number): TextLabel
	local l = Instance.new("TextLabel")
	l.LayoutOrder = order
	l.Size = UDim2.new(1, 0, 0, height)
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.TextSize = size
	l.TextColor3 = UITheme.Palette.Bone
	l.TextTransparency = transparency
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.Text = ""
	l.Parent = panel
	return l
end

local titleLabel = makeLabel(1, 18, 16, 0)
titleLabel.Text = "NEON TUNE"

-- Образец цвета: смотреть на цифры и на саму краску — разные вещи, а череп в кадре
-- ещё и залит блюмом, по нему чистый тон не прочесть.
local swatch = Instance.new("Frame")
swatch.LayoutOrder = 2
swatch.Size = UDim2.new(1, 0, 0, 18)
swatch.BorderSizePixel = 0
swatch.Parent = panel
Instance.new("UICorner", swatch).CornerRadius = UDim.new(0, 4)

local refreshers: { () -> () } = {}
local applyAll -- вперёд: ползунки дёргают её, а определена она ниже

local function makeSlider(order: number, name: string, get: () -> number, set: (number) -> ())
	-- 24 вместо 32: ползунков стало тринадцать, и в прежней вёрстке панель переставала
	-- влезать по высоте — верх уезжал за край экрана вместе с ползунками цвета.
	local row = Instance.new("Frame")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 24)
	row.BackgroundTransparency = 1
	row.Parent = panel

	local caption = Instance.new("TextLabel")
	caption.Size = UDim2.new(1, 0, 0, 13)
	caption.BackgroundTransparency = 1
	caption.Font = FONT
	caption.TextSize = 13
	caption.TextColor3 = UITheme.Palette.Bone
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.Parent = row

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, 0, 0, 6)
	track.Position = UDim2.new(0, 0, 0, 16)
	track.BackgroundColor3 = UITheme.Shadow
	track.BorderSizePixel = 0
	track.Parent = row
	Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = UITheme.Palette.GreenLight
	fill.BorderSizePixel = 0
	fill.Parent = track
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(12, 12)
	knob.Position = UDim2.fromScale(0, 0.5)
	knob.BackgroundColor3 = UITheme.Palette.Bone
	knob.BorderSizePixel = 0
	knob.ZIndex = 2
	knob.Parent = track
	Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

	local function refresh()
		local alpha = math.clamp(get() / 255, 0, 1)
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.new(alpha, 0, 0.5, 0)
		caption.Text = string.format("%-4s %3d", name, math.floor(get() + 0.5))
	end
	table.insert(refreshers, refresh)

	-- Зона захвата на всю строку: 6-пиксельную полоску мышью не поймать.
	local hit = Instance.new("TextButton")
	hit.Size = UDim2.fromScale(1, 1)
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Text = ""
	hit.Parent = row

	local dragging = false
	local function setFromX(x: number)
		local width = math.max(track.AbsoluteSize.X, 1)
		set(math.clamp((x - track.AbsolutePosition.X) / width, 0, 1) * 255)
		applyAll()
	end

	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)

	refresh()
end

makeSlider(3, "R", function() return r end, function(v) r = v end)
makeSlider(4, "G", function() return g end, function(v) g = v end)
makeSlider(5, "B", function() return b end, function(v) b = v end)

-- ТОЛЩИНА ЛИНИИ. Осторожно с трактовкой: я одно время считал её причиной пропавшего
-- свечения и построил этот ползунок под ту версию — она оказалась НЕВЕРНОЙ. Ореол
-- держал цвет, а погас он потому, что я срезал яркость вдвое (см. SKULL_COLOR в
-- UIController). Ползунок при этом полезен сам по себе: линию можно сделать жирнее или
-- тоньше, не трогая размер черепа. Ходит в studs, вершины живого меша переставляются
-- на месте — пересборки нет.
-- Верх 0.5, а не «побольше на всякий случай»: проверено живьём, что уже на 0.9 лента
-- смыкается сама с собой и череп становится сплошным пятном — глазницы и промежутки
-- между зубами затягивает. Полезный диапазон весь ниже, и ползунку нужна точность в нём.
-- Низ опущен до 0.01: 0.04 юзер выбрал, упершись в прежний предел, — значит хотелось
-- ещё тоньше, и запас нужен вниз, а не вверх.
local STROKE_MIN, STROKE_MAX = 0.01, 0.5
local strokeValue = 0.03 -- то, что стоит в UIController после подбора юзером

local function skullTune(): any
	return _G.__SkullTune
end

makeSlider(6, "Толщ", function()
	-- 0..255 у ползунка — общая шкала; переводим в неё реальные studs
	return (strokeValue - STROKE_MIN) / (STROKE_MAX - STROKE_MIN) * 255
end, function(v)
	strokeValue = STROKE_MIN + (v / 255) * (STROKE_MAX - STROKE_MIN)
	local tune = skullTune()
	if tune then
		tune.setStroke(strokeValue)
	end
end)

-- ПАРАМЕТРЫ ЗМЕЙКИ. Эффект длится секунду, и вслепую его не подобрать — три захода
-- правок ушли впустую именно поэтому. Таблица SNAKE живая: значения читаются каждый
-- кадр анимации, так что ползунок двигает даже уже летящий череп.
local function snake(): any
	local tune = skullTune()
	return tune and tune.snake
end

-- // Выключатель зомби -------------------------------------------------------
-- Юзер: «не дают настроить свечение и змейку». Так и есть: пока разглядываешь череп,
-- стая доедает машину, экран трясёт от ударов, а на выбывании тебя уносит в лобби.
-- Ремоут заводит PhotoModeService и только в Studio — в живой игре его нет, и ветка
-- молча ничего не делает.
local zombiesOff = false
local zombiesRemote: RemoteEvent? = nil
task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 20)
	if remotes then
		local r = remotes:WaitForChild("DevZombies", 20)
		if r and r:IsA("RemoteEvent") then
			zombiesRemote = r
		end
	end
end)

-- // СТЕНД: эффект по кругу, вне гонки ---------------------------------------
-- Юзер: «вообще я хочу увидеть эффект отдельно вне игры». И он прав: эффект длится
-- секунду и срабатывает только у активного чекпоинта на ходу — рассмотреть его в
-- заезде нельзя, а подбирать вслепую мы уже пробовали, ушло три захода впустую.
-- Стенд паркует камеру у ближайшего черепа и перезапускает улёт, пока не выключишь.
local standOn = false
local standCamera: Camera? = nil
-- Цель запоминаем: пересчитывать «ближайший череп» каждый кадр нельзя — камера сама
-- переезжает к черепу, ближайшим тут же становится другой, и стенд бы прыгал по карте.
local standTarget: Model? = nil
local standConns: { RBXScriptConnection } = {}
-- Что мы погасили и каким оно было: на выходе надо вернуть ИМЕННО прежнее состояние,
-- а не «включить всё» — часть экранов может быть законно выключена самой игрой.
local standHidden: { [LayerCollector]: boolean } = {}

local function nearestSkull(): Model?
	local folder = workspace:FindFirstChild("RaceMarkers")
	if not folder then
		return nil
	end
	local cam = workspace.CurrentCamera
	local from = cam and cam.CFrame.Position or Vector3.zero
	local best, bestD = nil, math.huge
	for _, m in folder:GetChildren() do
		if m:IsA("Model") and m.PrimaryPart then
			local d = (m:GetPivot().Position - from).Magnitude
			if d < bestD then
				best, bestD = m, d
			end
		end
	end
	return best
end

local function standLoop()
	-- КАМЕРУ ДЕРЖИМ КАЖДЫЙ КАДР, А НЕ РАЗ В ЦИКЛ. Прошлый заход ставил CFrame один раз
	-- на прогон — и штатный контроллер камеры возвращал её обратно тем же кадром.
	-- Снаружи это выглядело как «стенд не включается»: в логе «стенд ВКЛ» есть, а на
	-- экране ничего. Приоритет ПОСЛЕ Camera — иначе нас затирают в том же кадре.
	RunService:BindToRenderStep("NeonTuneStand", Enum.RenderPriority.Camera.Value + 10, function()
		if not standOn then
			return
		end
		local m = standTarget or nearestSkull()
		local cam = workspace.CurrentCamera
		if not (m and cam) then
			return
		end
		standTarget = m
		local home = m:GetPivot().Position
		local s = snake()
		-- РАМКУ СЧИТАЕМ ОТ НАСТОЯЩЕЙ ВЫСОТЫ ПОЛЁТА, а не от абстрактного числа. Прошлый
		-- заход брал heights * 2.2 и промахивался: подъём равен heights * СОБСТВЕННОЙ
		-- высоте призрака, а она зависит от масштаба черепа. Из-за этого камера смотрела
		-- в землю рядом, и стенд выглядел неработающим, хотя эффект шёл.
		local ghost = workspace:FindFirstChild("GhostSkull")
		local ghostH = (ghost and ghost:IsA("BasePart")) and ghost.Size.Y or 2.4
		local riseH = math.max((s and s.heights or 9) * ghostH, 8)
		-- смотрим в середину пути и отходим так, чтобы путь помещался целиком
		local look = home + Vector3.new(0, riseH * 0.5, 0)
		local dist = riseH * 0.95
		cam.CameraType = Enum.CameraType.Scriptable
		cam.FieldOfView = 55
		cam.CFrame = CFrame.lookAt(look + Vector3.new(dist * 0.75, riseH * 0.1, dist * 0.75), look)
	end)

	task.spawn(function()
		while standOn do
			local tune = skullTune()
			if tune and tune.playCollect and (standTarget or nearestSkull()) then
				tune.playCollect()
			end
			local s = snake()
			task.wait((s and s.rise or 1.2) + 0.5) -- пауза между прогонами
		end
	end)

	-- ЧУЖИЕ ЭКРАНЫ ГАСИМ СТОРОЖЕМ, А НЕ ОПРОСОМ. Лобби и HUD зажигают себя по RaceUpdate
	-- (каждые 0.4с), и мой прежний опрос раз в 0.3с гасил их с запозданием — из-за чего
	-- интерфейс МЕЛЬКАЛ (юзер это и увидел). Сторож ловит включение и гасит в том же
	-- кадре, так что мигания нет вовсе.
	local function watch(g: Instance)
		if not g:IsA("LayerCollector") or g == gui then
			return
		end
		local lc = g :: LayerCollector
		if standHidden[lc] == nil then
			standHidden[lc] = lc.Enabled
		end
		standConns[#standConns + 1] = lc:GetPropertyChangedSignal("Enabled"):Connect(function()
			if standOn and lc.Enabled then
				lc.Enabled = false
			end
		end)
		lc.Enabled = false
	end
	for _, g in playerGui:GetChildren() do
		watch(g)
	end
	standConns[#standConns + 1] = playerGui.ChildAdded:Connect(watch)
end

local function snakeSlider(order: number, name: string, field: string, minV: number, maxV: number)
	makeSlider(order, name, function()
		local s = snake()
		local v = s and s[field] or minV
		return (v - minV) / (maxV - minV) * 255
	end, function(v)
		local s = snake()
		if s then
			s[field] = minV + (v / 255) * (maxV - minV)
		end
	end)
end

-- ВСЕ ручки змейки, а не четыре из девяти. Прошлый набор не покрывал форму самой
-- кривой (Разм/Волн) — то есть ровно то, что и хотелось подобрать глазами.
snakeSlider(7, "Длит", "rise", 0.3, 6) -- секунд на весь улёт
snakeSlider(8, "Высота", "heights", 1, 25) -- на сколько своих ростов поднимается
snakeSlider(9, "Разм", "pathAmps", 0, 1.2) -- размах перегиба кривой — ГЛАВНАЯ форма
snakeSlider(10, "Волн", "pathWaves", 0.25, 5) -- сколько волн кривой на путь
snakeSlider(11, "Тянуть", "stretch", 0, 4) -- вытягивание по высоте к концу
snakeSlider(12, "Сужать", "narrow", 0, 0.95) -- сужение по ширине к концу
snakeSlider(13, "Течь", "travel", 0, 2) -- 1 = кривая стоит в пространстве
snakeSlider(14, "Извив", "amp", 0, 1.2) -- ДОПОЛНИТЕЛЬНЫЙ извив тела поверх кривой
snakeSlider(15, "Бег", "waveSpeed", 0, 3) -- как быстро этот извив бежит по телу

local valuesLabel = makeLabel(16, 52, 14, 0)
local hintsLabel = makeLabel(17, 100, 12, 0.45)
hintsLabel.Text = table.concat({
	"Z — выключить зомби (не мешают смотреть)",
	"K — СТЕНД: эффект по кругу, камера сама",
	"ENTER — прогнать улёт один раз",
	"-  =   притушить / поднять все три канала",
	";  '   Bloom Intensity (общий на сцену)",
	"9  0   Bloom Threshold",
	"M — показать черепа вне заезда",
	"\\ — сброс · P — числа в Output",
}, "\n")

local skullsLabel = makeLabel(18, 30, 12, 0.25)

-- // Применение --------------------------------------------------------------
local function currentColor(): Color3
	return Color3.fromRGB(math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5))
end

-- Красим ВСЕ существующие плашки. Пересобирать меш не надо: цвет — свойство детали,
-- а не геометрии. Это и держит подкрутку безопасной — у EditableMesh бюджет памяти
-- около восьми штук, и пересборка в цикле без освобождения предыдущего роняет отрисовку.
local function applyToSkulls(): number
	local folder = workspace:FindFirstChild("RaceMarkers")
	if not folder then
		return 0
	end
	local colour = currentColor()
	local n = 0
	for _, d in folder:GetDescendants() do
		if d.Name == "Plate" and d:IsA("BasePart") then
			d.Color = colour
			if forceVisible then
				d.Transparency = 0
			end
			n += 1
		end
	end
	return n
end

-- Вернуть черепа как было (см. комментарий у forceVisible).
local function hideSkulls()
	local folder = workspace:FindFirstChild("RaceMarkers")
	if not folder then
		return
	end
	for _, d in folder:GetDescendants() do
		if d.Name == "Plate" and d:IsA("BasePart") then
			d.Transparency = 1
		end
	end
end

function applyAll()
	local painted = applyToSkulls()
	local c = currentColor()
	swatch.BackgroundColor3 = c
	for _, refresh in refreshers do
		refresh()
	end
	valuesLabel.Text = string.format(
		"Color3.fromRGB(%d, %d, %d)\nSKULL_STROKE = %.2f%s\nBloom  I %.2f   T %.2f",
		math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5),
		strokeValue,
		skullTune() and "" or "  (UIController не отдал ручку)",
		bloom and bloom.Intensity or 0,
		bloom and bloom.Threshold or 0
	)
	-- СОСТОЯНИЕ ПРЯМО НА ПАНЕЛИ. Консоль оказалась ненадёжным свидетелем: у меня стенд
	-- работал и снимался, а строки о нём в логе не было. Пусть будет видно глазами.
	local ghost = workspace:FindFirstChild("GhostSkull")
	skullsLabel.Text = string.format(
		"СТЕНД (K): %s · летит: %s · зомби (Z): %s\nчерепов: %d · показ (M): %s · курсор: %s",
		standOn and "ВКЛ" or "выкл",
		(ghost and ghost:IsA("BasePart") and ghost.Transparency < 0.99) and "да" or "нет",
		zombiesOff and "ВЫКЛ" or "вкл",
		painted,
		forceVisible and "вкл" or "выкл",
		UserInputService.MouseIconEnabled and "вкл" or "ВЫКЛ"
	)
end

-- Плашки появляются не сразу и не все разом (UIController строит их по ходу заезда),
-- поэтому цвет доливаем по таймеру, а не только по нажатию клавиши.
task.spawn(function()
	while true do
		task.wait(0.5)
		if active then
			applyAll()
		end
	end
end)

local function printNumbers()
	local c = currentColor()
	print(string.format("[NeonTune] SKULL_COLOR = Color3.fromRGB(%d, %d, %d)",
		math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)))
	print(string.format("[NeonTune] SKULL_STROKE = %.2f", strokeValue))
	local s = snake()
	if s then
		print(string.format(
			"[NeonTune] SNAKE: rise=%.2f waveSpeed=%.2f amp=%.2f heights=%.1f stretch=%.2f narrow=%.2f waves=%.1f pathWaves=%.1f pathAmps=%.2f",
			s.rise, s.waveSpeed, s.amp, s.heights, s.stretch, s.narrow, s.waves, s.pathWaves, s.pathAmps))
	end
	if bloom then
		print(string.format("[NeonTune] BloomIntensity = %.2f, Threshold = %.2f", bloom.Intensity, bloom.Threshold))
	end
end

-- // Ввод --------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode == TOGGLE_KEY then
		active = not active
		gui.Enabled = active
		-- КУРСОР НАД ПАНЕЛЬЮ — СТОРОЖЕМ, А НЕ ОПРОСОМ (юзер: «курсор мелькает вместе с
		-- HUD»). За рулём TurretAimClient прячет системную стрелку, захватывает мышь и
		-- рисует свой крест — по ползункам им не попасть. Прежде я возвращал курсор раз
		-- в полсекунды, и он мигал: турель гасила, я зажигал. Сторож ловит сам факт
		-- гашения и возвращает стрелку в том же кадре, поэтому мигания нет.
		-- УСТУПКА ВМЕСТО ДРАКИ. Прежде я гасил прицел турели сторожем — а турель гасит
		-- системный курсор ровно в тот момент, когда ВКЛЮЧАЕТ прицел. Получался цикл:
		-- я выключил прицел → турель следующим кадром включила его и спрятала курсор →
		-- я снова выключил… Курсора не было вовсе. Теперь просто поднимаем флаг, а
		-- TurretAimClient сам не трогает мышь, пока панель открыта.
		player:SetAttribute("DevPanelOpen", active or nil)
		UserInputService.MouseIconEnabled = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		if active then
			bloom = Lighting:FindFirstChildOfClass("BloomEffect")
			applyAll()
		elseif forceVisible then
			forceVisible = false -- выключили подкрутку — черепа не должны остаться висеть
			hideSkulls()
		end
		return
	end
	if not active then
		return
	end
	-- processed НАМЕРЕННО НЕ ПРОВЕРЯЕМ. Ползунки сделаны на TextButton, и после клика по
	-- ним фокус остаётся на кнопке — Roblox начинает помечать ВСЕ последующие нажатия
	-- как «обработанные интерфейсом». Из-за этого клавиши переставали работать ровно
	-- после того, как покрутишь ползунок (юзер: «O не работает»). Единственное, что
	-- действительно надо пропускать, — ввод в текстовое поле, но их здесь нет вовсе.
	if UserInputService:GetFocusedTextBox() then
		return
	end

	local key = input.KeyCode
	if key == Enum.KeyCode.Equals then
		r, g, b = math.min(255, r * 1.05), math.min(255, g * 1.05), math.min(255, b * 1.05)
	elseif key == Enum.KeyCode.Minus then
		r, g, b = r * 0.95, g * 0.95, b * 0.95
	elseif key == Enum.KeyCode.Quote and bloom then
		bloom.Intensity = math.clamp(bloom.Intensity + 0.05, 0, 4)
	elseif key == Enum.KeyCode.Semicolon and bloom then
		bloom.Intensity = math.clamp(bloom.Intensity - 0.05, 0, 4)
	-- Порог переехал с «,»/«.» на «9»/«0» (юзер: «точка занята системой»).
	elseif key == Enum.KeyCode.Zero and bloom then
		bloom.Threshold = math.clamp(bloom.Threshold + 0.05, 0, 5)
	elseif key == Enum.KeyCode.Nine and bloom then
		bloom.Threshold = math.clamp(bloom.Threshold - 0.05, 0, 5)
	elseif key == Enum.KeyCode.BackSlash then
		r, g, b = CONFIG_COLOR.R * 255, CONFIG_COLOR.G * 255, CONFIG_COLOR.B * 255
		if bloom then
			bloom.Intensity = baseIntensity
			bloom.Threshold = baseThreshold
		end
	elseif key == Enum.KeyCode.Z then
		local r = zombiesRemote
		if not r then
			print("[NeonTune] ремоута DevZombies нет — он только в Studio")
			return
		end
		zombiesOff = not zombiesOff
		r:FireServer(zombiesOff)
		print("[NeonTune] зомби: " .. (zombiesOff and "ВЫКЛЮЧЕНЫ" or "включены"))
		return
	-- СТЕНД НА K, А НЕ НА O. Проверено юзером напрямую: K доходит, O — нет, при том что
	-- обе лежали в одной цепочке elseif и у меня срабатывали обе. Причину на его стороне
	-- (раскладка? перехват?) выяснять не стали — дешевле сменить клавишу, чем гоняться.
	elseif key == Enum.KeyCode.K then
		standOn = not standOn
		if standOn then
			-- Экраны гасит standLoop сторожами, здесь только CoreGui.
			game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
			standLoop()
			print("[NeonTune] стенд ВКЛ — эффект по кругу. K — выключить")
		else
			pcall(function()
				RunService:UnbindFromRenderStep("NeonTuneStand")
			end)
			for _, c in standConns do
				c:Disconnect()
			end
			table.clear(standConns)
			-- возвращаем ровно то, что было до стенда
			for lc, wasEnabled in standHidden do
				if lc.Parent then
					lc.Enabled = wasEnabled
				end
			end
			table.clear(standHidden)
			game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
			standTarget = nil
			local cam = standCamera or workspace.CurrentCamera
			if cam then
				cam.CameraType = Enum.CameraType.Custom -- вернуть камеру игроку
			end
			print("[NeonTune] стенд выкл")
		end
		return
	elseif key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter then
		local tune = skullTune()
		if tune and tune.playCollect then
			-- Ответ печатаем в Output: если череп не нашёлся, надо знать почему,
			-- а не гадать «нажал и ничего».
			print("[NeonTune] улёт: " .. tune.playCollect())
		else
			print("[NeonTune] UIController не отдал ручку запуска")
		end
		return
	elseif key == Enum.KeyCode.M then
		forceVisible = not forceVisible
		if not forceVisible then
			hideSkulls()
		end
	elseif key == Enum.KeyCode.P then
		printNumbers()
		return
	else
		return
	end
	applyAll()
end)

applyAll()
print("[NeonTune] подкрутка свечения готова: F6 (черепа видны только в заезде)")
