--!strict
-- LocalScript: StarterPlayerScripts.OptionsMenu
-- Панель опций: кнопка-шестерёнка (низ-право) открывает слайдеры громкости
-- Общая/Музыка/Мотор/Звуки. Живо двигает SoundGroups через Audio. Персистентность
-- (DataStore/SettingsService) — позже; пока правки на сессию (+ шлём SaveSettings).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Audio = require(ReplicatedStorage:WaitForChild("Audio"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local SettingsSchema = require(ReplicatedStorage:WaitForChild("SettingsSchema"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local settings = SettingsSchema.defaults()

local gui = Instance.new("ScreenGui")
gui.Name = "OptionsMenu"
gui.ResetOnSpawn = false
gui.DisplayOrder = 20
gui.IgnoreGuiInset = true
gui.Parent = playerGui

-- // Кнопка-шестерёнка -------------------------------------------------------
local gear = Instance.new("TextButton")
gear.Name = "GearButton"
gear.Size = UDim2.fromOffset(44, 44)
gear.Position = UDim2.new(1, -56, 1, -56)
gear.BackgroundColor3 = UITheme.PanelBg
gear.BackgroundTransparency = 0.2
gear.Text = "⚙"
gear.TextScaled = true
gear.Font = Enum.Font.GothamBold -- у Creepster нет глифа шестерёнки
gear.TextColor3 = UITheme.Palette.Bone
Instance.new("UICorner", gear).CornerRadius = UDim.new(0, 8)
gear.Parent = gui

-- // Панель ------------------------------------------------------------------
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Active = true -- перехватывает клики (не стреляем из турели сквозь панель)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(440, 380)
panel.BackgroundColor3 = UITheme.PanelBg
panel.BackgroundTransparency = 0.05
panel.Visible = false
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
local stroke = Instance.new("UIStroke")
stroke.Color = UITheme.Palette.Bone
stroke.Transparency = 0.6
stroke.Thickness = 2
stroke.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 56)
title.BackgroundTransparency = 1
title.Text = "ОПЦИИ"
title.TextScaled = true
UITheme.applyText(title, { color = UITheme.Palette.Bone })
title.Parent = panel

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(36, 36)
closeBtn.Position = UDim2.new(1, -44, 0, 10)
closeBtn.BackgroundColor3 = UITheme.Palette.Red
closeBtn.Text = "X"
closeBtn.TextScaled = true
UITheme.applyText(closeBtn)
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)
closeBtn.Parent = panel

-- // Слайдер -----------------------------------------------------------------
local activeDrag: ((x: number) -> ())? = nil

local function makeSlider(key: string, label: string, index: number)
	local y = 78 + (index - 1) * 70

	local cap = Instance.new("TextLabel")
	cap.Size = UDim2.new(1, -120, 0, 26)
	cap.Position = UDim2.fromOffset(24, y)
	cap.BackgroundTransparency = 1
	cap.TextXAlignment = Enum.TextXAlignment.Left
	cap.Text = label
	cap.TextScaled = true
	UITheme.applyText(cap, { color = UITheme.Ink })
	cap.Parent = panel

	local pct = Instance.new("TextLabel")
	pct.Size = UDim2.fromOffset(70, 26)
	pct.Position = UDim2.new(1, -94, 0, y)
	pct.BackgroundTransparency = 1
	pct.TextScaled = true
	UITheme.applyText(pct, { color = UITheme.cycleColor(index) })
	pct.Parent = panel

	local track = Instance.new("TextButton") -- кнопка → клик перехватывается (не стреляет турель)
	track.Text = ""
	track.AutoButtonColor = false
	track.Size = UDim2.new(1, -48, 0, 12)
	track.Position = UDim2.fromOffset(24, y + 34)
	track.BackgroundColor3 = Color3.fromRGB(64, 64, 64)
	track.Parent = panel
	Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = UITheme.cycleColor(index)
	fill.BorderSizePixel = 0
	fill.Parent = track
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

	local handle = Instance.new("Frame")
	handle.AnchorPoint = Vector2.new(0.5, 0.5)
	handle.Size = UDim2.fromOffset(20, 20)
	handle.BackgroundColor3 = UITheme.Palette.Bone
	handle.ZIndex = 2
	handle.Parent = track
	Instance.new("UICorner", handle).CornerRadius = UDim.new(1, 0)

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

makeSlider("masterVolume", "Общая", 1)
makeSlider("musicVolume", "Музыка", 2)
makeSlider("engineVolume", "Мотор", 3)
makeSlider("sfxVolume", "Звуки", 4)

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

gear.Activated:Connect(function()
	panel.Visible = not panel.Visible
end)
closeBtn.Activated:Connect(function()
	panel.Visible = false
end)
