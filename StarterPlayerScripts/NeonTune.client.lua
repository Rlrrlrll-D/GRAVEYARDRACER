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
--   , / .         Bloom Threshold ∓0.05  (порог: что вообще начинает светиться)
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

-- То, что стоит в UIController на момент сборки подкрутки. Сюда же возвращает «\».
local CONFIG_COLOR = Color3.fromRGB(55, 128, 85)

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
layout.Padding = UDim.new(0, 6)
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
	local row = Instance.new("Frame")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 32)
	row.BackgroundTransparency = 1
	row.Parent = panel

	local caption = Instance.new("TextLabel")
	caption.Size = UDim2.new(1, 0, 0, 14)
	caption.BackgroundTransparency = 1
	caption.Font = FONT
	caption.TextSize = 13
	caption.TextColor3 = UITheme.Palette.Bone
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.Parent = row

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, 0, 0, 6)
	track.Position = UDim2.new(0, 0, 0, 20)
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

local valuesLabel = makeLabel(6, 36, 14, 0)
local hintsLabel = makeLabel(7, 86, 12, 0.45)
hintsLabel.Text = table.concat({
	"-  =   притушить / поднять все три канала",
	";  '   Bloom Intensity (общий на сцену)",
	",  .   Bloom Threshold",
	"M — показать черепа вне заезда",
	"\\ — сброс · P — числа в Output",
}, "\n")

local skullsLabel = makeLabel(8, 16, 12, 0.45)

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
		"Color3.fromRGB(%d, %d, %d)\nBloom  I %.2f   T %.2f",
		math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5),
		bloom and bloom.Intensity or 0,
		bloom and bloom.Threshold or 0
	)
	skullsLabel.Text = painted > 0
		and string.format("покрашено черепов: %d · показ (M): %s", painted, forceVisible and "ВКЛ" or "выкл")
		or "плашек черепов нет — их строит UIController"
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
	if bloom then
		print(string.format("[NeonTune] BloomIntensity = %.2f, Threshold = %.2f", bloom.Intensity, bloom.Threshold))
	end
end

-- // Ввод --------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode == TOGGLE_KEY then
		active = not active
		gui.Enabled = active
		if active then
			bloom = Lighting:FindFirstChildOfClass("BloomEffect")
			applyAll()
		elseif forceVisible then
			forceVisible = false -- выключили подкрутку — черепа не должны остаться висеть
			hideSkulls()
		end
		return
	end
	if not active or processed then
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
	elseif key == Enum.KeyCode.Period and bloom then
		bloom.Threshold = math.clamp(bloom.Threshold + 0.05, 0, 5)
	elseif key == Enum.KeyCode.Comma and bloom then
		bloom.Threshold = math.clamp(bloom.Threshold - 0.05, 0, 5)
	elseif key == Enum.KeyCode.BackSlash then
		r, g, b = CONFIG_COLOR.R * 255, CONFIG_COLOR.G * 255, CONFIG_COLOR.B * 255
		if bloom then
			bloom.Intensity = baseIntensity
			bloom.Threshold = baseThreshold
		end
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
