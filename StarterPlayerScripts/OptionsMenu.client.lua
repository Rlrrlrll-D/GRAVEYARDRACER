--!strict
-- LocalScript: StarterPlayerScripts.OptionsMenu
-- Опции на «надгробном камне»: аркой кверху, с подтёками мха, гравировка тёмным
-- по камню-кости. Шрифт — ТОЛЬКО Creepster. Палитра: кость + мох (зелёный);
-- красный — единственный акцент того же тона, что плашка «0 MPH» (кнопка закрыть).
-- Текст — только английский. Слайдеры Master/Music/Engine/SFX двигают SoundGroups
-- через Audio (живо). Персистентность (DataStore) — позже (шлём SaveSettings).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Audio = require(ReplicatedStorage:WaitForChild("Audio"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local SettingsSchema = require(ReplicatedStorage:WaitForChild("SettingsSchema"))

-- камень-кость + мох; красный только акцентом (= Palette.Red, тон «0 MPH»)
local STONE = Color3.fromRGB(42, 62, 48)      -- мшистый камень (был бежевый)
local STONE_TOP = Color3.fromRGB(52, 90, 64)  -- светлый мох (верх градиента)
local STONE_BOT = Color3.fromRGB(22, 33, 27)  -- тёмный мох (низ градиента)
local ENGRAVE = Color3.fromRGB(224, 214, 170) -- костяная гравировка (была тёмная)
local MOSS = UITheme.Palette.Green
local RED = UITheme.Palette.Red

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local settings = SettingsSchema.defaults()

local gui = Instance.new("ScreenGui")
gui.Name = "OptionsMenu"
gui.ResetOnSpawn = false
gui.DisplayOrder = 20
gui.IgnoreGuiInset = true
gui.Parent = playerGui

local function corner(inst: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end

-- гравированный лейбл: тёмным по камню, светлая обводка = фаска резьбы
local function engrave(text: string, scaled: boolean): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = UITheme.Font -- только Creepster
	l.Text = text
	l.TextScaled = scaled
	l.TextColor3 = ENGRAVE
	l.TextStrokeColor3 = UITheme.Shadow -- тёмная обводка под светлую кость
	l.TextStrokeTransparency = 0.35
	return l
end

-- // Переключатель: мини-камень «MENU» ---------------------------------------
local toggle = Instance.new("TextButton")
toggle.Name = "ToggleButton"
toggle.Size = UDim2.fromOffset(100, 46)
toggle.Position = UDim2.new(1, -116, 1, -62)
toggle.BackgroundColor3 = STONE
toggle.Font = UITheme.Font
toggle.Text = "MENU"
toggle.TextScaled = true
toggle.TextColor3 = ENGRAVE
toggle.TextStrokeColor3 = UITheme.Shadow
toggle.TextStrokeTransparency = 0.4
corner(toggle, 10)
toggle.Parent = gui

-- // Надгробие ---------------------------------------------------------------
local stone = Instance.new("Frame")
stone.Name = "Tombstone"
stone.Active = true -- перехватывает клики (не стреляем из турели сквозь камень)
stone.AnchorPoint = Vector2.new(0.5, 0.5)
stone.Position = UDim2.fromScale(0.5, 0.5)
stone.Size = UDim2.fromOffset(470, 480)
stone.BackgroundColor3 = STONE
stone.Visible = false
stone.Parent = gui
corner(stone, 150) -- аркой кверху

local grad = Instance.new("UIGradient")
grad.Rotation = 90
grad.Color = ColorSequence.new(STONE_TOP, STONE_BOT)
grad.Parent = stone

local edge = Instance.new("UIStroke") -- тёмная кайма-фаска
edge.Color = ENGRAVE
edge.Transparency = 0.55
edge.Thickness = 3
edge.Parent = stone

-- подтёки мха: сверху вниз, тают к низу
local drips = { { x = 0.22, w = 10, h = 0.5 }, { x = 0.4, w = 7, h = 0.32 }, { x = 0.64, w = 13, h = 0.62 }, { x = 0.82, w = 8, h = 0.42 } }
for _, spec in drips do
	local drip = Instance.new("Frame")
	drip.BackgroundColor3 = MOSS
	drip.BorderSizePixel = 0
	drip.AnchorPoint = Vector2.new(0.5, 0)
	drip.Position = UDim2.new(spec.x, 0, 0, 8)
	drip.Size = UDim2.new(0, spec.w, spec.h, 0)
	drip.ZIndex = 1
	corner(drip, 6)
	local dg = Instance.new("UIGradient")
	dg.Rotation = 90
	dg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	dg.Parent = drip
	drip.Parent = stone
end

local title = engrave("OPTIONS", true)
title.Size = UDim2.new(1, -90, 0, 64)
title.Position = UDim2.fromOffset(45, 42)
title.ZIndex = 3
title.Parent = stone

-- закрыть — единственный красный (тон «0 MPH»)
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(34, 34)
closeBtn.Position = UDim2.new(1, -54, 0, 26)
closeBtn.BackgroundColor3 = RED
closeBtn.Font = UITheme.Font
closeBtn.Text = "X"
closeBtn.TextScaled = true
closeBtn.TextColor3 = UITheme.Ink
closeBtn.TextStrokeColor3 = UITheme.Shadow
closeBtn.TextStrokeTransparency = 0.4
closeBtn.ZIndex = 3
corner(closeBtn, 6)
closeBtn.Parent = stone

-- // Слайдеры ----------------------------------------------------------------
local activeDrag: ((x: number) -> ())? = nil

local function makeSlider(key: string, label: string, index: number)
	local y = 128 + (index - 1) * 76

	local cap = engrave(label, false)
	cap.Size = UDim2.new(1, -150, 0, 28)
	cap.Position = UDim2.fromOffset(45, y)
	cap.TextXAlignment = Enum.TextXAlignment.Left
	cap.TextSize = 28
	cap.ZIndex = 3
	cap.Parent = stone

	local pct = engrave("100", false)
	pct.Size = UDim2.fromOffset(72, 28)
	pct.Position = UDim2.new(1, -116, 0, y)
	pct.TextSize = 28
	pct.ZIndex = 3
	pct.Parent = stone

	local track = Instance.new("TextButton") -- кнопка → клик перехватывается (турель не стреляет)
	track.Text = ""
	track.AutoButtonColor = false
	track.Size = UDim2.new(1, -90, 0, 14)
	track.Position = UDim2.fromOffset(45, y + 38)
	track.BackgroundColor3 = STONE_BOT
	track.ZIndex = 3
	corner(track, 7)
	local groove = Instance.new("UIStroke")
	groove.Color = ENGRAVE
	groove.Transparency = 0.45
	groove.Thickness = 2
	groove.Parent = track
	track.Parent = stone

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = MOSS
	fill.BorderSizePixel = 0
	fill.ZIndex = 3
	corner(fill, 7)
	fill.Parent = track

	local handle = Instance.new("Frame")
	handle.AnchorPoint = Vector2.new(0.5, 0.5)
	handle.Size = UDim2.fromOffset(22, 22)
	handle.BackgroundColor3 = ENGRAVE
	handle.ZIndex = 4
	corner(handle, 11)
	local hs = Instance.new("UIStroke")
	hs.Color = STONE_TOP
	hs.Thickness = 2
	hs.Parent = handle
	handle.Parent = track

	local function set(v: number, fromUser: boolean)
		v = math.clamp(v, 0, 1)
		settings[key] = v
		fill.Size = UDim2.new(v, 0, 1, 0)
		handle.Position = UDim2.new(v, 0, 0.5, 0)
		pct.Text = tostring(math.floor(v * 100))
		if fromUser then
			Audio.apply(settings)
		end
	end
	set(tonumber(settings[key]) or 1, false)

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

makeSlider("masterVolume", "MASTER", 1)
makeSlider("musicVolume", "MUSIC", 2)
makeSlider("engineVolume", "ENGINE", 3)
makeSlider("sfxVolume", "SFX", 4)

UserInputService.InputChanged:Connect(function(input)
	if activeDrag and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		activeDrag(input.Position.X)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		if activeDrag then
			activeDrag = nil
			local remotes = ReplicatedStorage:FindFirstChild("Remotes")
			local save = remotes and remotes:FindFirstChild("SaveSettings")
			if save then
				(save :: RemoteEvent):FireServer(settings) -- SettingsService подхватит позже
			end
		end
	end
end)

toggle.Activated:Connect(function()
	stone.Visible = not stone.Visible
end)
closeBtn.Activated:Connect(function()
	stone.Visible = false
end)
