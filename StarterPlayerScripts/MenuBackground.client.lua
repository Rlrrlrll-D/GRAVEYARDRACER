--!strict
-- LocalScript: StarterPlayerScripts.MenuBackground
-- Стартовая ЗАСТАВКА Graveyard Racer. Статичный (без облёта) заблюренный кадр
-- 3D-диорамы кладбища (Workspace.MenuScene): луна, бёртоновские деревья,
-- надгробия; поверх — тематический тайтл и кнопки (Creepster + палитра
-- кость/мох/кровь из UITheme). Периодические звуки (ветер-подложка, сова) и
-- пролетающие в кадре летучие мыши-силуэты. Показывается один раз при заходе
-- ПОВЕРХ лобби сессионной модели: PLAY закрывает заставку и открывает лобби
-- (READY/ростер, LobbyUI), OPTIONS показывает опции-надгробие (OptionsMenu),
-- на время которого заставка уступает экран.
--
-- Свет: сервер (AtmosphereSetup) при старте раунда ведёт переход вечер→ночь и
-- реплицирует Lighting. Чтобы заставка сразу была глубокой ночью, каждый кадр
-- форсируем ФИНАЛЬНЫЕ ночные значения (перекрывают серверный переход). На
-- закрытии перестаём форсить — серверная ночь (к тому моменту та же) подхватывает.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local Audio = require(ReplicatedStorage:WaitForChild("Audio"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

-- Диорама — Persistent-модель, доезжает до клиента даже при StreamingEnabled.
local scene = workspace:WaitForChild("MenuScene", 15) :: Instance?
if not scene then
	return -- сцены нет — молча выходим, без заставки
end

local camPos = (scene:GetAttribute("CamPos") :: Vector3?) or Vector3.new(0, 3003.5, -30)
local camLook = (scene:GetAttribute("CamLook") :: Vector3?) or Vector3.new(1, 3008, 6)
local camCF = CFrame.lookAt(camPos, camLook)
local right, upV, fwd = camCF.RightVector, camCF.UpVector, camCF.LookVector

-- // Ночные цели (совпадают с EnvironmentConfig.Atmosphere — бесшовный хэндофф)
local NIGHT_CLOCK = 0.7
local NIGHT_BRIGHT = 0.95
local NIGHT_AMBIENT = Color3.fromRGB(45, 50, 65)
local NIGHT_FOG = Color3.fromRGB(35, 40, 55) -- финальный ночной туман (перебиваем «вечер» перехода)

-- // Звуки: ветер-подложка (луп) + периодическая сова + шелест крыльев --------
local WIND_ID = "rbxassetid://9114625745" -- Gods Wind Spooky Eerie (ProSoundEffects)
local OWL_ID = "rbxassetid://9117181540" -- Owl Hooting Reverberant
local WING_ID = "rbxassetid://9113994447" -- Creature Wings (взмахи, как в BatFX)

local function newSound(id: string, vol: number, looped: boolean): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = vol
	s.Looped = looped
	s.SoundGroup = Audio.SFX -- слайдер «Звуки» в опциях управляет громкостью
	s.Parent = SoundService
	return s
end

local wind = newSound(WIND_ID, 0.22, true)
local owl = newSound(OWL_ID, 0.4, false)
local wing = newSound(WING_ID, 0.16, false)

-- // Летучие мыши: клоны диорамного ассета, пролёт поперёк кадра силуэтом ------
local batTemplate = ReplicatedStorage:FindFirstChild("Assets")
batTemplate = batTemplate and batTemplate:FindFirstChild("Bat") or nil
local batFolder = Instance.new("Folder")
batFolder.Name = "MenuBats"
batFolder.Parent = camera

local function flybyBat()
	if not batTemplate then
		return
	end
	local bat = batTemplate:Clone()
	bat:ScaleTo(2.4)
	for _, p in bat:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
		end
	end
	local side = (math.random() < 0.5) and 1 or -1
	local dist = math.random(26, 52) -- как далеко перед камерой
	local height = (math.random(-40, 150)) / 10 -- от чуть ниже линии взгляда до высоко
	local startPos = camPos + fwd * dist - right * (side * 48) + upV * height
	local travel = right * (side * 96)
	local speed = math.random(30, 50)
	local life = 96 / speed
	local phase = math.random() * 6.28
	bat.Parent = batFolder
	wing.TimePosition = 0
	wing:Play()
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local age = os.clock() - t0
		if age > life or not bat.Parent then
			conn:Disconnect()
			return
		end
		local frac = age / life
		local bob = math.sin(age * 20 + phase) * 1.1
		local pos = startPos + travel * frac + upV * bob
		bat:PivotTo(CFrame.lookAt(pos, pos + travel.Unit) * CFrame.Angles(0, 0, math.sin(age * 20 + phase) * 0.6))
	end)
	Debris:AddItem(bat, life + 0.1)
end

-- // Блюр фона (клиент-локальный пост-эффект) ---------------------------------
local blur = Instance.new("BlurEffect")
blur.Name = "MenuBlur"
blur.Size = 0
blur.Parent = Lighting

-- // Форс ночного света поверх серверного перехода ---------------------------
local lightingActive = true
local lightConn = RunService.RenderStepped:Connect(function()
	if not lightingActive then
		return
	end
	Lighting.ClockTime = NIGHT_CLOCK
	Lighting.Brightness = NIGHT_BRIGHT
	Lighting.Ambient = NIGHT_AMBIENT
	Lighting.OutdoorAmbient = NIGHT_AMBIENT
	Lighting.FogColor = NIGHT_FOG
	Lighting.FogStart = 40
	Lighting.FogEnd = 400
end)

-- // Камера на диораму (статичная) --------------------------------------------
camera.CameraType = Enum.CameraType.Scriptable
camera.CFrame = camCF
local camConn = RunService.RenderStepped:Connect(function()
	if lightingActive then
		-- дефолтная камера сбрасывает тип в Custom при загрузке персонажа —
		-- форсируем Scriptable каждый кадр, иначе рендер идёт от персонажа
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = camCF
	end
end)

-- // Заморозка управления персонажем ------------------------------------------
local controls: any = nil
task.spawn(function()
	local ps = player:WaitForChild("PlayerScripts", 10)
	local pm = ps and ps:FindFirstChild("PlayerModule")
	if pm then
		local ok, mod = pcall(require, pm)
		if ok and mod then
			controls = mod:GetControls()
			if controls then
				controls:Disable()
			end
		end
	end
end)

-- // UI (тема: Creepster, кость/мох/кровь) ------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "MenuBackground"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50 -- поверх HUD и кнопки MENU опций
gui.Parent = playerGui

-- спрятать игровой HUD и CoreGui на время заставки (вернём при закрытии)
local hiddenGuis: { [ScreenGui]: boolean } = {}
for _, g in playerGui:GetChildren() do
	if g:IsA("ScreenGui") and g ~= gui then
		hiddenGuis[g] = g.Enabled
		g.Enabled = false
	end
end
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
end)

-- HUD (GraveyardHUD и т.п.) может создаться ЧУТЬ позже — прячем и новоприбывших
local hideConn = playerGui.ChildAdded:Connect(function(child)
	if child:IsA("ScreenGui") and child ~= gui and hiddenGuis[child] == nil then
		hiddenGuis[child] = child.Enabled
		child.Enabled = false
	end
end)

-- виньетка: затемнение сверху (под тайтл) и снизу (под кнопки)
local function shade(top: boolean)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = UITheme.Shadow
	f.BorderSizePixel = 0
	f.Size = UDim2.new(1, 0, 0.42, 0)
	f.Position = top and UDim2.new(0, 0, 0, 0) or UDim2.new(0, 0, 0.58, 0)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Transparency = if top
		then NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		else NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.1) })
	g.Parent = f
	f.Parent = gui
end
shade(true)
shade(false)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(0.9, 0, 0, 128)
title.Position = UDim2.new(0.05, 0, 0.09, 0)
title.Text = "GRAVEYARD RACER"
title.TextScaled = true
UITheme.applyText(title, { color = UITheme.Palette.Bone })
title.TextStrokeTransparency = 0.2
title.Parent = gui

local sub = Instance.new("TextLabel")
sub.BackgroundTransparency = 1
sub.Size = UDim2.new(0.7, 0, 0, 44)
sub.Position = UDim2.new(0.15, 0, 0.09, 130)
sub.Text = "the dead don't brake"
sub.TextScaled = true
UITheme.applyText(sub, { color = UITheme.Palette.Red })
sub.Parent = gui

local function makeButton(text: string, bg: Color3, slot: number): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 300, 0, 60)
	b.Position = UDim2.new(0.5, -150, 0.64, slot * 74)
	b.BackgroundColor3 = bg
	b.AutoButtonColor = true
	b.Text = text
	b.TextScaled = true
	UITheme.applyText(b)
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)
	local st = Instance.new("UIStroke")
	st.Color = UITheme.Shadow
	st.Thickness = 2
	st.Transparency = 0.3
	st.Parent = b
	b.Parent = gui
	return b
end

local playBtn = makeButton("PLAY", UITheme.Palette.Green, 0)
local optBtn = makeButton("OPTIONS", Color3.fromRGB(22, 33, 27), 1) -- тёмный мох

-- // Запуск: фейд блюра/звука + циклы мышей и совы ----------------------------
wind:Play()
TweenService:Create(blur, TweenInfo.new(1.2), { Size = 18 }):Play() -- мягкий фон под текст меню

local running = true
task.spawn(function()
	task.wait(2)
	while running do
		flybyBat()
		if math.random() < 0.35 then
			task.wait(0.4)
			flybyBat() -- иногда пара
		end
		task.wait(math.random(50, 110) / 10) -- каждые 5..11 c
	end
end)
task.spawn(function()
	while running do
		task.wait(math.random(120, 240) / 10) -- каждые 12..24 c
		if running then
			owl.TimePosition = 0
			owl:Play()
		end
	end
end)

-- // Закрытие заставки --------------------------------------------------------
local closing = false
local function closeMenu()
	if closing then
		return
	end
	closing = true
	running = false
	lightingActive = false -- отпускаем свет и камеру серверу/движку
	lightConn:Disconnect()
	camConn:Disconnect()
	hideConn:Disconnect()

	camera.CameraType = Enum.CameraType.Custom
	if controls then
		controls:Enable()
	end

	-- вернуть игровой HUD и CoreGui
	for g, wasEnabled in hiddenGuis do
		if g and g.Parent then
			g.Enabled = wasEnabled
		end
	end
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
	end)

	TweenService:Create(blur, TweenInfo.new(0.6), { Size = 0 }):Play()
	TweenService:Create(wind, TweenInfo.new(0.6), { Volume = 0 }):Play()

	-- плавно увести UI
	for _, d in gui:GetDescendants() do
		if d:IsA("GuiObject") then
			TweenService:Create(d, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		end
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			TweenService:Create(d, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end

	task.delay(0.7, function()
		blur:Destroy()
		wind:Stop()
		wind:Destroy()
		owl:Destroy()
		wing:Destroy()
		batFolder:Destroy()
		gui:Destroy()
	end)
end

playBtn.Activated:Connect(closeMenu)
optBtn.Activated:Connect(function()
	local om = playerGui:FindFirstChild("OptionsMenu")
	if not (om and om:IsA("ScreenGui")) then
		return
	end
	local stone = om:FindFirstChild("Tombstone")
	if not (stone and stone:IsA("GuiObject")) then
		return
	end
	om.Enabled = true -- заставка выключила его вместе с остальными GUI
	stone.Visible = true
	gui.Enabled = false -- заставка уступает экран надгробию (иначе тайтл/кнопки поверх опций)
	local conn: RBXScriptConnection
	conn = stone:GetPropertyChangedSignal("Visible"):Connect(function()
		if not stone.Visible then
			conn:Disconnect()
			if not closing then
				om.Enabled = false -- кнопку MENU снова прячем под заставку
				gui.Enabled = true -- опции закрыты → заставка вернулась
			end
		end
	end)
end)
