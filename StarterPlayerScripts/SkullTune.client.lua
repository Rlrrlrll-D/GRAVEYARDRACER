--!strict
-- LocalScript: StarterPlayerScripts.SkullTune
-- ДЕВ-ПОДКРУТКА ЧЕРЕПОВ-РАНГОВ И КРАСКИ КУЗОВА. Только Studio (как NeonTune/PhotoMode).
--
-- ЗАЧЕМ. Режим наложения, плотность, подъём яркости, четыре цвета лестницы и краска
-- кузова подбираются глазами, а в Edit-свете затенённые поверхности синеют от неба —
-- судить можно только в Play. Юзер: «на экран я сделаю как надо, а ты потом зашьёшь в
-- код» — здесь крутит он, P печатает числа в Output, я переношу их в GameConfig /
-- RankSkull.Colors / ShopCatalog.
--
--   F8            вкл / выкл панели
--   MODE          кнопка: перебор режимов наложения
--   TIER          кнопка: какой цвет лестницы крутим (и показываем на своей машине,
--                 даже если ранг ниже — все четыре места)
--   OPACITY/LIFT  0..1
--   R G B         цвет черепа выбранной ступени, 0..255
--   PAINT R G B   краска кузова (то, чем домножается текстура), 0..255
--   \             сброс к конфигу
--   P             напечатать всё в Output
-- Пересборка текстуры ~0.05с на изменение; ползунок тянуть можно, пересобирается на
-- отпускании и раз в 0.15с по ходу.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not RunService:IsStudio() then
	return
end

local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local RankSkull = require(ReplicatedStorage:WaitForChild("RankSkull"))
local ShopCatalog = require(ReplicatedStorage:WaitForChild("ShopCatalog"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local TOGGLE_KEY = Enum.KeyCode.F8
local FONT = Enum.Font.Code
local MODES = { "overlay", "multiply", "screen", "softlight", "lineardodge", "normal" }
local TIERS = { "bone", "ivory", "amber", "gold" }

-- Исходные значения — чтобы «\» возвращал к конфигу.
local base = {
	mode = GameConfig.Ranks.SkullMode,
	opacity = GameConfig.Ranks.SkullOpacity,
	lift = GameConfig.Ranks.SkullLift or 0,
	colors = {} :: { [string]: Color3 },
}
for _, n in TIERS do
	base.colors[n] = RankSkull.Colors[n]
end
local rustItem = ShopCatalog.get(ShopCatalog.DefaultSkin)
base.paint = (rustItem and rustItem.color) or Color3.new(1, 1, 1)

local state = {
	modeIndex = table.find(MODES, base.mode) or 1,
	tierIndex = 1,
	opacity = base.opacity,
	lift = base.lift,
	paint = { base.paint.R * 255, base.paint.G * 255, base.paint.B * 255 },
}
local colors: { [string]: { number } } = {}
for _, n in TIERS do
	local c = base.colors[n]
	colors[n] = { c.R * 255, c.G * 255, c.B * 255 }
end

local active = false

-- // Панель ------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "SkullTune"
gui.ResetOnSpawn = false
gui.DisplayOrder = 1003
gui.Enabled = false
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0, 1)
panel.Position = UDim2.new(0, 16, 1, -16)
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

local refreshers: { () -> () } = {}
local applyAll -- ниже

local function makeLabel(order: number, text: string, size: number): TextLabel
	local l = Instance.new("TextLabel")
	l.LayoutOrder = order
	l.Size = UDim2.new(1, 0, 0, size + 4)
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.TextSize = size
	l.TextColor3 = UITheme.Palette.Bone
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = panel
	return l
end

local function makeButton(order: number, get: () -> string, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.LayoutOrder = order
	b.Size = UDim2.new(1, 0, 0, 22)
	b.BackgroundColor3 = UITheme.Palette.Green
	b.BorderSizePixel = 0
	b.Font = FONT
	b.TextSize = 13
	b.TextColor3 = UITheme.Palette.Bone
	b.Text = get()
	b.Parent = panel
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
	table.insert(refreshers, function()
		b.Text = get()
	end)
	b.Activated:Connect(function()
		onClick()
		applyAll()
	end)
	return b
end

local function makeSlider(order: number, name: string, max: number, get: () -> number, set: (number) -> ())
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
	knob.BackgroundColor3 = UITheme.Palette.Bone
	knob.BorderSizePixel = 0
	knob.ZIndex = 2
	knob.Parent = track
	Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
	local function refresh()
		local alpha = math.clamp(get() / max, 0, 1)
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.new(alpha, 0, 0.5, 0)
		caption.Text = if max == 1 then string.format("%-8s %.2f", name, get()) else string.format("%-8s %3d", name, math.floor(get() + 0.5))
	end
	table.insert(refreshers, refresh)
	local hit = Instance.new("TextButton")
	hit.Size = UDim2.fromScale(1, 1)
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Text = ""
	hit.Parent = row
	local dragging = false
	local lastApply = 0
	local function setFromX(x: number, final: boolean)
		local width = math.max(track.AbsoluteSize.X, 1)
		set(math.clamp((x - track.AbsolutePosition.X) / width, 0, 1) * max)
		refresh()
		if final or os.clock() - lastApply > 0.15 then
			lastApply = os.clock()
			applyAll()
		end
	end
	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			setFromX(input.Position.X, false)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			setFromX(input.Position.X, false)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
			setFromX(input.Position.X, true)
		end
	end)
end

makeLabel(1, "SKULL TUNE   (F8, \\ сброс, P печать)", 15)
makeButton(2, function()
	return "MODE: " .. MODES[state.modeIndex]
end, function()
	state.modeIndex = state.modeIndex % #MODES + 1
end)
makeButton(3, function()
	return "TIER: " .. TIERS[state.tierIndex]
end, function()
	state.tierIndex = state.tierIndex % #TIERS + 1
end)
makeSlider(4, "OPACITY", 1, function()
	return state.opacity
end, function(v)
	state.opacity = v
end)
makeSlider(5, "LIFT", 1, function()
	return state.lift
end, function(v)
	state.lift = v
end)
local swatch = Instance.new("Frame")
swatch.LayoutOrder = 6
swatch.Size = UDim2.new(1, 0, 0, 14)
swatch.BorderSizePixel = 0
swatch.Parent = panel
Instance.new("UICorner", swatch).CornerRadius = UDim.new(0, 4)
for i, ch in { "R", "G", "B" } do
	makeSlider(6 + i, "SKULL " .. ch, 255, function()
		return colors[TIERS[state.tierIndex]][i]
	end, function(v)
		colors[TIERS[state.tierIndex]][i] = v
	end)
end
local paintSwatch = Instance.new("Frame")
paintSwatch.LayoutOrder = 10
paintSwatch.Size = UDim2.new(1, 0, 0, 14)
paintSwatch.BorderSizePixel = 0
paintSwatch.Parent = panel
Instance.new("UICorner", paintSwatch).CornerRadius = UDim.new(0, 4)
for i, ch in { "R", "G", "B" } do
	makeSlider(10 + i, "PAINT " .. ch, 255, function()
		return state.paint[i]
	end, function(v)
		state.paint[i] = v
	end)
end
local info = makeLabel(14, "", 11)
info.TextWrapped = true
info.Size = UDim2.new(1, 0, 0, 64)

-- // Применение ----------------------------------------------------------------
local function tierColor(n: string): Color3
	local c = colors[n]
	return Color3.fromRGB(math.floor(c[1] + 0.5), math.floor(c[2] + 0.5), math.floor(c[3] + 0.5))
end
local function paintColor(): Color3
	return Color3.fromRGB(math.floor(state.paint[1] + 0.5), math.floor(state.paint[2] + 0.5), math.floor(state.paint[3] + 0.5))
end

local function summary(): string
	local parts = {}
	for _, n in TIERS do
		local c = colors[n]
		table.insert(parts, ("%s=(%d,%d,%d)"):format(n, c[1] + 0.5, c[2] + 0.5, c[3] + 0.5))
	end
	local p = state.paint
	return ("SkullMode=%s SkullOpacity=%.2f SkullLift=%.2f | %s | rust=(%d,%d,%d)"):format(
		MODES[state.modeIndex], state.opacity, state.lift, table.concat(parts, " "), p[1] + 0.5, p[2] + 0.5, p[3] + 0.5)
end

applyAll = function()
	for _, n in TIERS do
		RankSkull.Colors[n] = tierColor(n)
	end
	RankSkull.Overrides = if active then {
		mode = MODES[state.modeIndex],
		opacity = state.opacity,
		lift = state.lift,
		tint = paintColor(),
		colorName = TIERS[state.tierIndex],
	} else nil
	if not active then
		for _, n in TIERS do
			RankSkull.Colors[n] = base.colors[n]
		end
	end
	RankSkull.OverridesChanged:Fire()
	swatch.BackgroundColor3 = tierColor(TIERS[state.tierIndex])
	paintSwatch.BackgroundColor3 = paintColor()
	for _, f in refreshers do
		f()
	end
	info.Text = summary()
end

local function reset()
	state.modeIndex = table.find(MODES, base.mode) or 1
	state.opacity = base.opacity
	state.lift = base.lift
	state.paint = { base.paint.R * 255, base.paint.G * 255, base.paint.B * 255 }
	for _, n in TIERS do
		local c = base.colors[n]
		colors[n] = { c.R * 255, c.G * 255, c.B * 255 }
	end
	applyAll()
end

UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode == TOGGLE_KEY then
		active = not active
		gui.Enabled = active
		applyAll()
		return
	end
	if not active or processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.BackSlash then
		reset()
	elseif input.KeyCode == Enum.KeyCode.P then
		print("[SkullTune] " .. summary())
	end
end)

applyAll()
print("[SkullTune] подкрутка черепов и краски готова: F8")
