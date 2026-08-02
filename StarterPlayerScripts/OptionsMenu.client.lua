--!strict
-- LocalScript: StarterPlayerScripts.OptionsMenu
-- Компактная панель опций СПРАВА (симметрично ростеру RACERS слева в LobbyUI).
-- Открывается/закрывается кнопкой OPTIONS из заставки (LobbyUI переключает
-- OptionsMenu.Panel.Visible) — своей кнопки-переключателя у панели НЕТ.
-- Строки генерируются из SettingsSchema.Options: слайдеры + тумблеры. Громкости
-- двигают SoundGroups через Audio сразу; остальное (тряска/скримеры/сенса) —
-- через эхо SaveSettings→PushSettings (SettingsService, DataStore). Шрифт —
-- только Creepster; палитра — кость/мох, красный только на «X» закрыть.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Audio = require(ReplicatedStorage:WaitForChild("Audio"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local SettingsSchema = require(ReplicatedStorage:WaitForChild("SettingsSchema"))
local SkullBadge = require(ReplicatedStorage:WaitForChild("SkullBadge"))

local ENGRAVE = Color3.fromRGB(224, 214, 170) -- костяная гравировка
local MOSS = UITheme.Palette.Green
local RED = UITheme.Palette.Red
local GREEN_LIGHT = UITheme.Palette.GreenLight -- светло-зелёный проекта (готовность PLAY)
-- КРАСНАЯ ТЕМА (просьба юзера): нижний слой шкалы под ползунками — красный, поверх
-- него ложится мшистая заливка. Прежде подложка была тёмным мхом 22,33,27 и шкала
-- целиком читалась одним пятном — теперь непройденная часть сразу видна.
local TRACK_BG = RED

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

-- гравированный лейбл: кость + тёмная обводка (фаска резьбы)
local function engrave(text: string): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = UITheme.Font
	l.Text = text
	l.TextColor3 = ENGRAVE
	l.TextStrokeColor3 = UITheme.Shadow
	l.TextStrokeTransparency = 0.35
	return l
end

-- // Панель СЛЕВА (просьба юзера: опции и ростер поменялись сторонами) --------
-- Высота 404 -> 456: семь строк опций кончаются на y=384, и внизу нужно место под
-- кнопку RACERS, которая открывает ростер. В прежние 404 она не влезала.
local PANEL_W = 280
local PANEL_H = 456
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Active = true -- перехватывает клики
panel.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
panel.Position = UDim2.new(0, 28, 0, 240) -- 28px от ЛЕВОГО края, под тайтлом заставки
panel.BackgroundColor3 = UITheme.PanelBg
panel.BackgroundTransparency = 0.2
panel.Visible = false
panel.Parent = root
corner(panel, 10)
local edge = Instance.new("UIStroke")
edge.Color = ENGRAVE
edge.Transparency = 0.6
edge.Thickness = 2
edge.Parent = panel

local title = engrave("OPTIONS")
title.Size = UDim2.new(1, -48, 0, 36)
title.Position = UDim2.fromOffset(16, 10)
title.TextScaled = true
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

-- закрыть — единственный красный
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(28, 28)
closeBtn.Position = UDim2.new(1, -38, 0, 12)
closeBtn.BackgroundColor3 = RED
closeBtn.Font = UITheme.Font
closeBtn.Text = "X"
closeBtn.TextScaled = true
closeBtn.TextColor3 = UITheme.Ink
closeBtn.TextStrokeColor3 = UITheme.Shadow
closeBtn.TextStrokeTransparency = 0.4
corner(closeBtn, 6)
closeBtn.Parent = panel

-- // Строки из SettingsSchema.Options -----------------------------------------
local activeDrag: ((x: number) -> ())? = nil
local ROW_H = 48
local function rowY(index: number): number
	return 48 + (index - 1) * ROW_H
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
	cap.TextColor3 = RED -- подписи над опциями красные (просьба юзера)
	cap.Size = UDim2.new(1, -78, 0, 22)
	cap.Position = UDim2.fromOffset(16, y)
	cap.TextXAlignment = Enum.TextXAlignment.Left
	cap.TextSize = 20
	cap.Parent = panel

	local pct = engrave("100")
	pct.Size = UDim2.fromOffset(48, 22)
	pct.Position = UDim2.new(1, -60, 0, y)
	pct.TextXAlignment = Enum.TextXAlignment.Right
	pct.TextSize = 20
	pct.Parent = panel

	local track = Instance.new("TextButton") -- кнопка → клик перехватывается
	track.Text = ""
	track.AutoButtonColor = false
	track.Size = UDim2.new(1, -32, 0, 12)
	track.Position = UDim2.fromOffset(16, y + 28)
	track.BackgroundColor3 = TRACK_BG
	corner(track, 6)
	local groove = Instance.new("UIStroke")
	groove.Color = ENGRAVE
	groove.Transparency = 0.5
	groove.Thickness = 1
	groove.Parent = track
	track.Parent = panel

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = MOSS
	fill.BorderSizePixel = 0
	corner(fill, 6)
	fill.Parent = track

	-- РУЧКА: красный кружок с черепом (просьба юзера). Череп — плоский силуэт из
	-- векторного файла, тот же ассет, что стоял у чекпоинтов; вписан с полем, иначе
	-- на 20 px он упирается в края кружка и читается пятном.
	local handle = Instance.new("Frame")
	handle.AnchorPoint = Vector2.new(0.5, 0.5)
	handle.Size = UDim2.fromOffset(20, 20)
	handle.BackgroundColor3 = RED
	handle.ZIndex = 2
	corner(handle, 10)
	local rim = Instance.new("UIStroke") -- костяной ободок: красное на красном иначе тонет
	rim.Color = ENGRAVE
	rim.Transparency = 0.35
	rim.Thickness = 1
	rim.Parent = handle
	-- череп из вектора юзера (тот же контур, что у чекпоинтов) — костяной на красной ручке
	SkullBadge.build(handle, 12, ENGRAVE)
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
local function makeToggle(opt: SettingsSchema.Option, index: number)
	local y = rowY(index)

	local cap = engrave(opt.label)
	cap.TextColor3 = RED -- подписи над опциями красные
	cap.Size = UDim2.new(1, -104, 0, 24)
	cap.Position = UDim2.fromOffset(16, y + 10)
	cap.TextXAlignment = Enum.TextXAlignment.Left
	cap.TextSize = 20
	cap.Parent = panel

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.fromOffset(72, 34)
	btn.Position = UDim2.new(1, -88, 0, y + 6)
	btn.Font = UITheme.Font
	btn.TextScaled = true
	btn.TextColor3 = ENGRAVE
	btn.TextStrokeColor3 = UITheme.Shadow
	btn.TextStrokeTransparency = 0.4
	corner(btn, 8)
	local bs = Instance.new("UIStroke")
	bs.Color = ENGRAVE
	bs.Transparency = 0.5
	bs.Thickness = 1
	bs.Parent = btn
	btn.Parent = panel

	local function render()
		local on = settings[opt.key] == true
		btn.Text = on and "ON" or "OFF"
		btn.BackgroundColor3 = on and GREEN_LIGHT or RED
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

-- // RACERS: ростер переехал сюда (просьба юзера) ------------------------------
-- Список гонщиков больше не висит слева постоянно — он открывается отсюда и
-- появляется СПРАВА, на месте, где раньше были эти самые опции. Панель ростера
-- живёт в чужом ScreenGui (LobbyUI), поэтому ищем её по имени — тем же приёмом,
-- которым LobbyUI находит эту панель. Ростер лежит внутри безымянного корневого
-- Frame, так что ищем рекурсивно.
local racersBtn = Instance.new("TextButton")
racersBtn.Name = "RacersToggle"
racersBtn.Size = UDim2.new(1, -32, 0, 40)
racersBtn.Position = UDim2.fromOffset(16, PANEL_H - 56)
racersBtn.BackgroundColor3 = MOSS
racersBtn.AutoButtonColor = true
racersBtn.Font = UITheme.Font
racersBtn.Text = "RACERS"
racersBtn.TextScaled = true
racersBtn.TextColor3 = ENGRAVE
racersBtn.TextStrokeColor3 = UITheme.Shadow
racersBtn.TextStrokeTransparency = 0.4
corner(racersBtn, 8)
local rbs = Instance.new("UIStroke")
rbs.Color = ENGRAVE
rbs.Transparency = 0.5
rbs.Thickness = 1
rbs.Parent = racersBtn
racersBtn.Parent = panel

local function rosterPanel(): GuiObject?
	local lobby = playerGui:FindFirstChild("LobbyUI")
	local r = lobby and lobby:FindFirstChild("Roster", true)
	return (r and r:IsA("GuiObject")) and (r :: GuiObject) or nil
end
racersBtn.Activated:Connect(function()
	local r = rosterPanel()
	if r then
		r.Visible = not r.Visible
	end
end)

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

closeBtn.Activated:Connect(function()
	panel.Visible = false
	local r = rosterPanel()
	if r then
		r.Visible = false -- закрыли опции — ростер, открытый отсюда, тоже уходит
	end
end)
