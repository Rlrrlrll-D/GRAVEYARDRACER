--!strict
-- LocalScript: StarterPlayerScripts.OptionsMenu
-- Панель опций СТРОГО ПО ЦЕНТРУ экрана. Открывается плашкой OPTIONS из заставки,
-- закрывается своей плашкой BACK — то есть возвращает в меню. Пока панель открыта,
-- меню заставки спрятано (см. LobbyUI): панели по центру, и иначе они легли бы
-- поверх тайтла и плашек.
--
-- СВЯЗЬ С ЗАСТАВКОЙ — ЧЕРЕЗ АТРИБУТ ИГРОКА LobbyPanel ("" | "Options" | "Racers").
-- Панель живёт в своём ScreenGui, и раньше меню искало её по имени через PlayerGui,
-- а она в ответ так же искала ростер. Атрибуту не важен порядок запуска
-- LocalScript'ов и не важно, кто кого успел создать.
--
-- Строки генерируются из SettingsSchema.Options: слайдеры + тумблеры. Громкости
-- двигают SoundGroups через Audio сразу; остальное (тряска/скримеры/сенса) —
-- через эхо SaveSettings→PushSettings (SettingsService, DataStore). Плашки и
-- подложка — мазки кистью из PlateArt; рамка и скругления убраны (просьба юзера).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Audio = require(ReplicatedStorage:WaitForChild("Audio"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local SettingsSchema = require(ReplicatedStorage:WaitForChild("SettingsSchema"))
local SkullBadge = require(ReplicatedStorage:WaitForChild("SkullBadge"))
local PlateArt = require(ReplicatedStorage:WaitForChild("PlateArt"))

-- ПАНЕЛЬ ОПЦИЙ — КОСТЯНАЯ (просьба юзера): подложка цвета кости, буквы по ней
-- тёмно-мховые. Ростер рядом остался тёмным — там строки сами цветные плашки, и
-- на кости они бы спорили с фоном.
local BONE = UITheme.Palette.Bone
local DARK = UITheme.Shadow -- буквы и обводки поверх кости
local ENGRAVE = BONE -- костяная надпись на ТЁМНЫХ плашках (тумблер, череп ручки)
local MOSS = UITheme.Palette.Green
local RED = UITheme.Palette.Red
local GREEN_LIGHT = UITheme.Palette.GreenLight -- светло-зелёный проекта (готовность PLAY)
-- КРАСНАЯ ТЕМА (просьба юзера): нижний слой шкалы под ползунками — красный, поверх
-- него ложится мшистая заливка. Прежде подложка была тёмным мхом 22,33,27 и шкала
-- целиком читалась одним пятном — теперь непройденная часть сразу видна.
local TRACK_BG = RED

local PANEL_ATTR = "LobbyPanel"

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local settings = SettingsSchema.defaults()

local gui = Instance.new("ScreenGui")
gui.Name = "OptionsMenu"
gui.ResetOnSpawn = false
gui.DisplayOrder = 20 -- поверх заставки (LobbyUI = 10)
gui.IgnoreGuiInset = true
gui.Parent = playerGui

-- Прозрачный корень нужен только ради UIScale: он ужимает панель под высоту окна
-- так же, как заставку (UITheme.fitToScreen), — иначе в невысоком окне низ панели
-- уезжает за экран. Клики не перехватывает: Active=false, фон прозрачный.
local root = Instance.new("Frame")
root.Name = "Root"
root.Size = UDim2.fromScale(1, 1)
root.BackgroundTransparency = 1
root.Parent = gui
UITheme.fitToScreen(root)

local function corner(inst: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end

-- Надпись по костяной подложке: тёмная и БЕЗ обводки. Обводка нужна светлому тексту
-- на тёмном, чтобы он не сливался; тёмному по светлому она только утолщает буквы.
local function engrave(text: string): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = UITheme.Font
	l.Text = text
	l.TextColor3 = DARK
	l.TextStrokeTransparency = 1
	l.ZIndex = 2 -- поверх подложки-мазка
	return l
end

-- // Панель ПО ЦЕНТРУ ---------------------------------------------------------
-- Размер тот же, что у ростера в LobbyUI: панели сменяют друг друга на одном месте.
-- Панель крупная и с широкими полями (просьба юзера). Ширина растёт вместе с
-- полем, поэтому под содержимое остаётся даже больше прежнего: 620 − 2×110 = 400.
-- Поле 110, а не 70, потому что у подложки рваный край: сплошная краска начинается
-- только с ~140-го пикселя, и при меньшем поле строки садились на «волоски» кисти,
-- а глаз всё равно читал их как прижатые к краю.
local PANEL_W = 620
local PANEL_H = 580
local PAD = 110
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Active = true -- перехватывает клики
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.BackgroundTransparency = 1
panel.Visible = false
panel.Parent = root

-- Сплошная подложка вместо фона с рамкой: обводка и скругление убраны (просьба
-- юзера), панель держит форму мазка — плотное нутро, рваные края.
local backdrop = PlateArt.backdrop(BONE)
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.ZIndex = 1
backdrop.Parent = panel

local title = engrave("OPTIONS")
-- Заголовок крупный (просьба юзера): 50 -> 72 по высоте, при TextScaled буквы
-- вырастают на ту же треть. Строки опций сдвинуты ниже, чтобы он в них не упёрся.
title.Size = UDim2.new(1, -2 * PAD, 0, 72)
-- Поле сверху 36, а не 16 (просьба юзера, общая для всех панелей): на 16 пикселях
-- заголовок садится на щетину рваного края подложки. Строки ниже сдвинуты на
-- столько же, BACK стал ниже — иначе последний ползунок в него упирается.
title.Position = UDim2.fromOffset(PAD, 36)
title.TextScaled = true
title.TextXAlignment = Enum.TextXAlignment.Center -- по центру (просьба юзера)
title.Parent = panel

-- // Строки из SettingsSchema.Options -----------------------------------------
-- Семь строк с шагом 56 идут от y=100 (под выросшим заголовком) и кончаются на 484,
-- а BACK начинается с 496 — двенадцать пикселей зазора. Ради них BACK стал ниже
-- (66 вместо 76): иначе последний ползунок упирался в него.
local activeDrag: ((x: number) -> ())? = nil
local ROW_H = 56
local function rowY(index: number): number
	return 116 + (index - 1) * ROW_H
end

-- обновление строки извне (PushSettings: сохранённые опции пришли с сервера)
local applyExternal: { [string]: (value: any) -> () } = {}

local function sendSave()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local save = remotes and remotes:FindFirstChild("SaveSettings")
	if save then
		(save :: RemoteEvent):FireServer(settings) -- SettingsService: sanitize → эхо PushSettings
	end
end

local function makeSlider(opt: SettingsSchema.Option, index: number)
	local y = rowY(index)
	local minV = opt.min or 0
	local maxV = opt.max or 1

	local cap = engrave(opt.label)
	cap.Size = UDim2.new(1, -2 * PAD - 76, 0, 26)
	cap.Position = UDim2.fromOffset(PAD, y)
	cap.TextXAlignment = Enum.TextXAlignment.Left
	cap.TextSize = 26
	cap.Parent = panel

	local pct = engrave("100")
	pct.Size = UDim2.fromOffset(60, 26)
	pct.Position = UDim2.new(1, -PAD - 60, 0, y)
	pct.TextXAlignment = Enum.TextXAlignment.Right
	pct.TextSize = 26
	pct.Parent = panel

	local track = Instance.new("TextButton") -- кнопка → клик перехватывается
	track.Text = ""
	track.AutoButtonColor = false
	track.Size = UDim2.new(1, -2 * PAD, 0, 16)
	track.Position = UDim2.fromOffset(PAD, y + 32)
	track.BackgroundColor3 = TRACK_BG
	track.ZIndex = 2
	corner(track, 8)
	local groove = Instance.new("UIStroke")
	groove.Color = DARK
	groove.Transparency = 0.5
	groove.Thickness = 1
	groove.Parent = track
	track.Parent = panel

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = MOSS
	fill.BorderSizePixel = 0
	fill.ZIndex = 2
	corner(fill, 8)
	fill.Parent = track

	-- РУЧКА: красный кружок с черепом (просьба юзера). Череп — плоский силуэт из
	-- векторного файла, тот же ассет, что стоял у чекпоинтов; вписан с полем, иначе
	-- на 20 px он упирается в края кружка и читается пятном.
	local handle = Instance.new("Frame")
	handle.AnchorPoint = Vector2.new(0.5, 0.5)
	handle.Size = UDim2.fromOffset(26, 26)
	handle.BackgroundColor3 = RED
	handle.ZIndex = 3
	corner(handle, 13)
	local rim = Instance.new("UIStroke") -- тёмный ободок: красное на кости иначе растекается
	rim.Color = DARK
	rim.Transparency = 0.35
	rim.Thickness = 1
	rim.Parent = handle
	-- череп из вектора юзера (тот же контур, что у чекпоинтов) — костяной на красной ручке
	SkullBadge.build(handle, 16, ENGRAVE)
	handle.Parent = track

	-- t — позиция ползунка 0..1; значение опции = min + t*(max-min)
	local function set(t: number, fromUser: boolean)
		t = math.clamp(t, 0, 1)
		settings[opt.key] = minV + t * (maxV - minV)
		fill.Size = UDim2.new(t, 0, 1, 0)
		handle.Position = UDim2.new(t, 0, 0.5, 0)
		pct.Text = tostring(math.floor(t * 100))
		if fromUser and string.find(opt.key, "Volume") then
			Audio.apply(settings) -- громкости слышны сразу; остальное применит эхо PushSettings
		end
	end
	local v = tonumber(settings[opt.key]) or minV
	set((v - minV) / math.max(maxV - minV, 1e-6), false)
	applyExternal[opt.key] = function(value: any)
		if type(value) == "number" then
			set((value - minV) / math.max(maxV - minV, 1e-6), false)
		end
	end

	local function setFromX(x: number)
		local rel = (x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1)
		set(rel, true)
	end
	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			setFromX(input.Position.X)
			activeDrag = setFromX
		end
	end)
end

-- Тумблер-флаг: OFF красный / ON светло-зелёный. Прежде было мох/тёмный-мох — два
-- почти одинаковых по светлоте цвета, состояние приходилось читать по надписи.
-- Теперь переключение показывает КРАСНЫЙ (просьба юзера), тем же языком, что и PLAY.
-- Плашка тумблера — такой же мазок, только узкий, поэтому поле у надписи меньше.
local function makeToggle(opt: SettingsSchema.Option, index: number)
	local y = rowY(index)

	local cap = engrave(opt.label)
	cap.Size = UDim2.new(1, -2 * PAD - 138, 0, 30)
	cap.Position = UDim2.fromOffset(PAD, y + 10)
	cap.TextXAlignment = Enum.TextXAlignment.Left
	cap.TextSize = 26
	cap.Parent = panel

	local btn = PlateArt.button(index, RED)
	btn.Size = UDim2.fromOffset(126, 48)
	btn.Position = UDim2.new(1, -PAD - 126, 0, y + 2)
	btn.ZIndex = 2
	local label = PlateArt.caption(btn, "OFF", ENGRAVE, 14)
	btn.Parent = panel

	local function render()
		local on = settings[opt.key] == true
		label.Text = on and "ON" or "OFF"
		PlateArt.tint(btn, on and GREEN_LIGHT or RED)
	end
	btn.Activated:Connect(function()
		settings[opt.key] = not (settings[opt.key] == true)
		render()
		sendSave()
	end)
	render()
	applyExternal[opt.key] = function(value: any)
		if type(value) == "boolean" then
			settings[opt.key] = value
			render()
		end
	end
end

for i, opt in SettingsSchema.Options do
	if opt.kind == "slider" then
		makeSlider(opt, i)
	else
		makeToggle(opt, i)
	end
end

-- // BACK: возврат в меню -----------------------------------------------------
-- Кнопка RACERS отсюда УБРАНА (просьба юзера): ростер вызывается своей плашкой в
-- меню заставки, а не из опций. Красного «X» в углу тоже нет.
--
-- BACK — БЕЗ ПЛАШКИ (просьба юзера): на костяной подложке мазок под надписью читался
-- как заплатка на краске. Осталась одна тёмная надпись; наведение подсвечивает её,
-- иначе кнопка ничем не отзывается на мышь.
local backBtn = Instance.new("TextButton")
backBtn.Name = "BackPlate"
backBtn.AnchorPoint = Vector2.new(0.5, 1)
backBtn.Size = UDim2.fromOffset(340, 52)
backBtn.Position = UDim2.new(0.5, 0, 1, -14)
backBtn.BackgroundTransparency = 1
backBtn.AutoButtonColor = false
backBtn.Text = "BACK"
backBtn.TextScaled = true
backBtn.Font = UITheme.Font
backBtn.TextColor3 = DARK
backBtn.TextStrokeTransparency = 1
backBtn.ZIndex = 2
backBtn.Parent = panel
backBtn.MouseEnter:Connect(function()
	backBtn.TextColor3 = RED
end)
backBtn.MouseLeave:Connect(function()
	backBtn.TextColor3 = DARK
end)
backBtn.Activated:Connect(function()
	player:SetAttribute(PANEL_ATTR, "")
end)

-- Панель видна ровно тогда, когда меню просит именно её.
local function applyPanel()
	panel.Visible = player:GetAttribute(PANEL_ATTR) == "Options"
end
player:GetAttributeChangedSignal(PANEL_ATTR):Connect(applyPanel)
applyPanel()

-- сохранённые опции пришли с сервера (вход в игру / эхо) → обновить строки UI
ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PushSettings").OnClientEvent:Connect(function(s)
	if type(s) ~= "table" then
		return
	end
	for key, fn in applyExternal do
		if s[key] ~= nil then
			fn(s[key])
		end
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if activeDrag and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		activeDrag(input.Position.X)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		if activeDrag then
			activeDrag = nil
			sendSave() -- слайдер отпущен → зафиксировать значение на сервере
		end
	end
end)
