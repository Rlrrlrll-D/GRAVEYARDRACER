--!strict
-- LocalScript: StarterPlayerScripts.TouchControls
-- ЭКРАННОЕ УПРАВЛЕНИЕ ДЛЯ ТЕЛЕФОНА И ПЛАНШЕТА.
--
-- Раскладка (выбрана юзером): слева под большим пальцем — две стрелки поворота,
-- справа — газ и тормоз, над газом — гашетка. Прицел и HUD не трогаем: датчики
-- в этом проекте и так наверху (UIController), а штатные приборы A-Chassis
-- выключены целиком (GaugeLayout) — низ экрана свободен под пальцы.
--
-- ПОЧЕМУ НЕ ContextActionService:BindAction. Он рисует кнопки сам, но рисует их
-- СВОИМ круглым шаблоном: серый круг с буквой. Всё остальное меню собрано из
-- мазков кистью, и вкрапление стандартных кругляшей выглядело бы вставкой из
-- другой игры. Кнопки здесь — те же PlateArt, что и в лобби.
--
-- КАК ЭТО ДОЕЗЖАЕТ ДО МАШИНЫ. Руль и педали живут в чужом коде: A-Chassis 6
-- держит газ/тормоз/руль ЛОКАЛЬНЫМИ переменными скрипта Drive (_GThrot, _GBrake,
-- _GSteerT) и заполняет их из UserInputService. Подделать InputObject нельзя, а
-- сенсорной ветки у AC6 нет вовсе (проверено поиском: ни TouchEnabled, ни
-- ContextActionService, ни TouchGui — только клавиатура, мышь и геймпад).
-- Поэтому вся логика и вся вёрстка лежат ЗДЕСЬ, а в Drive вживлена прививка на
-- три присваивания, читающая атрибуты игрока:
--
--   TouchActive   (bool)   — сенсорный режим включён, AC6 слушает атрибуты
--   TouchSteer    (-1..1)  — руль
--   TouchThrottle (0..1)   — газ
--   TouchBrake    (0..1)   — тормоз
--   TouchFire     (bool)   — гашетка (читает TurretAimClient)
--
-- Атрибуты, а не Value-объекты: их не надо создавать, они не реплицируются и не
-- засоряют дерево. Ставятся только на СМЕНЕ состояния — кнопки цифровые, так что
-- за заезд это десятки записей, а не десятки тысяч.
--
-- ЗАДНИЙ ХОД ОТДЕЛЬНОЙ КНОПКИ НЕ ТРЕБУЕТ: у AC6 в режиме Auto тормоз на скорости
-- ниже 20 сам переключает передачу в R, а газ возвращает в D (Drive, автоматическая
-- трансмиссия). То есть «упёрся в надгробие → подержал тормоз → выехал назад»
-- работает теми же двумя педалями.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local PlateArt = require(ReplicatedStorage:WaitForChild("PlateArt"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ForceTouchUI — атрибут для показа раскладки на десктопе (снять скриншот, дать
-- юзеру посмотреть, не поднимая эмулятор устройства). В проде его никто не ставит.
local function touchWanted(): boolean
	if player:GetAttribute("ForceTouchUI") == true then
		return true
	end
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- Атрибуты ставим всегда, даже на десктопе: прививка в Drive и TurretAimClient
-- должны видеть явное «сенсора нет», а не отсутствие атрибута.
player:SetAttribute("TouchActive", false)
player:SetAttribute("TouchSteer", 0)
player:SetAttribute("TouchThrottle", 0)
player:SetAttribute("TouchBrake", 0)
player:SetAttribute("TouchFire", false)

if not touchWanted() then
	-- Устройство может стать сенсорным на ходу: эмулятор устройства в Studio,
	-- подключённый к компьютеру планшет. Ждём сигнала, ничего пока не рисуя.
	local ready = Instance.new("BindableEvent")
	local function recheck()
		if touchWanted() then
			ready:Fire()
		end
	end
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(recheck)
	player:GetAttributeChangedSignal("ForceTouchUI"):Connect(recheck)
	ready.Event:Wait()
end

-- // Вёрстка -----------------------------------------------------------------
-- Размеры в опорных пикселях (экран высотой REF), масштаб — одним UIScale, как в
-- меню. Палец физически одного размера на любом экране, поэтому масштаб не даём
-- уходить ниже 0.8: на низком экране кнопки лучше займут больше доли, чем станут
-- нежимаемыми.
local REF = 700
local M = 22 -- поле от края экрана

local gui = Instance.new("ScreenGui")
gui.Name = "TouchControls"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 20 -- ниже прицела (50), выше HUD
gui.Enabled = false
gui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "Pad"
root.BackgroundTransparency = 1
root.Parent = gui

local fit = Instance.new("UIScale")
fit.Parent = root
local function applyScale()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local s = math.clamp(cam.ViewportSize.Y / REF, 0.8, 1.5)
	fit.Scale = s
	root.Size = UDim2.fromScale(1 / s, 1 / s) -- UIScale множит и саму рамку — гасим
end
applyScale()
do
	local function watch()
		applyScale()
		local cam = workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(applyScale)
		end
	end
	watch()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watch)
end

-- Прозрачность мазка: кнопки лежат поверх дороги, сплошными их держать не хочется.
-- Но и утоньшать нельзя: сцена ночная и мшисто-зелёная, на первой сборке зелёные
-- мазки при 0.32 сливались с травой — на экране оставались висеть одни значки.
local IDLE_ALPHA = 0.12
local HELD_ALPHA = 0

local function setAlpha(plate: GuiObject, a: number)
	local brush = plate:FindFirstChild("Brush")
	if brush and brush:IsA("ImageLabel") then
		brush.ImageTransparency = a
	elseif brush and brush:IsA("Frame") then
		brush.BackgroundTransparency = a
	end
end

-- Шеврон из двух планок — тот же приём, что у стрелки-компаса в UIController:
-- «▲» шрифтом Creepster не нарисовать, а картинку в UI не завести (см. PlateArt).
-- Поворот контейнера задаёт направление: 0 — вверх, 180 — вниз, ±90 — вбок.
--
-- ЗНАК ПОВОРОТА ПЛАНОК ВАЖЕН. Rotation в GUI растёт по часовой, поэтому у планки
-- с ПОЛОЖИТЕЛЬНЫМ углом верх уезжает вправо. Чтобы вершины сошлись НАВЕРХУ (то
-- есть получилось «∧»), левой планке нужен плюс, правой минус — то есть -side.
-- В первой сборке стояло side, вершина сходилась внизу, и все четыре стрелки
-- показывали ровно в обратную сторону.
local function chevron(parent: GuiObject, turn: number, color: Color3, size: number)
	local box = Instance.new("Frame")
	box.Name = "Glyph"
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.Size = UDim2.fromOffset(size, size)
	box.BackgroundTransparency = 1
	box.Rotation = turn
	box.ZIndex = parent.ZIndex + 1
	for _, side in { -1, 1 } do
		local wing = Instance.new("Frame")
		wing.AnchorPoint = Vector2.new(0.5, 0.5)
		wing.Size = UDim2.fromOffset(math.floor(size * 0.17), math.floor(size * 0.66))
		wing.Position = UDim2.new(0.5, side * math.floor(size * 0.19), 0.5, 0)
		wing.Rotation = -side * 40
		wing.BackgroundColor3 = color
		wing.BorderSizePixel = 0
		wing.ZIndex = box.ZIndex
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 3)
		c.Parent = wing
		wing.Parent = box
	end
	box.Parent = parent
end

-- Гашетка — то же перекрестие, что и прицел (TurretAimClient): палец жмёт ровно
-- тот знак, который видит в центре экрана.
local function crosshairGlyph(parent: GuiObject, color: Color3, size: number)
	local box = Instance.new("Frame")
	box.Name = "Glyph"
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.Size = UDim2.fromOffset(size, size)
	box.BackgroundTransparency = 1
	box.ZIndex = parent.ZIndex + 1

	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(0.72, 0.72)
	ring.BackgroundTransparency = 1
	ring.ZIndex = box.ZIndex
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = math.max(2, size * 0.055)
	stroke.Parent = ring
	ring.Parent = box

	local T = math.max(2, size * 0.055)
	for _, spec in {
		{ UDim2.new(0.5, 0, 0, 0), Vector2.new(0.5, 0), UDim2.fromOffset(T, size * 0.3) },
		{ UDim2.new(0.5, 0, 1, 0), Vector2.new(0.5, 1), UDim2.fromOffset(T, size * 0.3) },
		{ UDim2.new(0, 0, 0.5, 0), Vector2.new(0, 0.5), UDim2.fromOffset(size * 0.3, T) },
		{ UDim2.new(1, 0, 0.5, 0), Vector2.new(1, 0.5), UDim2.fromOffset(size * 0.3, T) },
		{ UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), UDim2.fromOffset(T + 1, T + 1) },
	} do
		local bar = Instance.new("Frame")
		bar.Position = spec[1] :: UDim2
		bar.AnchorPoint = spec[2] :: Vector2
		bar.Size = spec[3] :: UDim2
		bar.BackgroundColor3 = color
		bar.BorderSizePixel = 0
		bar.ZIndex = box.ZIndex
		bar.Parent = box
	end
	box.Parent = parent
end

-- // Кнопки ------------------------------------------------------------------
-- Каждая кнопка — прямоугольный прозрачный TextButton (он и ловит палец) с мазком
-- внутри: рваные края мазка иначе оставили бы по углам мёртвые зоны.
type Button = { plate: TextButton, pop: UIScale }

local shapeIndex = 0
local function makeButton(w: number, h: number, color: Color3): Button
	shapeIndex += 1
	local plate = PlateArt.button(shapeIndex, color)
	plate.Size = UDim2.fromOffset(w, h)
	plate.Active = true
	plate.AutoButtonColor = false
	setAlpha(plate, IDLE_ALPHA)
	local pop = Instance.new("UIScale")
	pop.Parent = plate
	plate.Parent = root
	return { plate = plate, pop = pop }
end

-- Палец, начавший жать кнопку, может уехать за её границу — GuiObject.InputEnded
-- тогда не придёт, и кнопка залипнет «нажатой». Поэтому отпускание ловим глобально
-- по тому же InputObject.
local heldBy: { [InputObject]: () -> () } = {}

local function bind(btn: Button, down: () -> (), up: () -> ())
	local function press()
		setAlpha(btn.plate, HELD_ALPHA)
		btn.pop.Scale = 0.93
		down()
	end
	local function release()
		setAlpha(btn.plate, IDLE_ALPHA)
		btn.pop.Scale = 1
		up()
	end
	btn.plate.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			if heldBy[input] then
				return
			end
			heldBy[input] = release
			press()
		end
	end)
end

UserInputService.InputEnded:Connect(function(input)
	local release = heldBy[input]
	if release then
		heldBy[input] = nil
		release()
	end
end)

-- Руль. Держим обе стороны отдельно: одновременное нажатие ◀ и ▶ даёт ноль, а не
-- «кто последний отпустил», иначе после сдвоенного тапа руль остаётся вывернутым.
local steerL, steerR = false, false
local function pushSteer()
	local v = 0
	if steerL and not steerR then
		v = -1
	elseif steerR and not steerL then
		v = 1
	end
	player:SetAttribute("TouchSteer", v)
end

local STEER_W, STEER_H = 132, 92
local left = makeButton(STEER_W, STEER_H, UITheme.Palette.Green)
left.plate.Name = "SteerLeft"
left.plate.AnchorPoint = Vector2.new(0, 1)
left.plate.Position = UDim2.new(0, M, 1, -M)
chevron(left.plate, -90, UITheme.Palette.Bone, 54)
bind(left, function()
	steerL = true
	pushSteer()
end, function()
	steerL = false
	pushSteer()
end)

local right = makeButton(STEER_W, STEER_H, UITheme.Palette.Green)
right.plate.Name = "SteerRight"
right.plate.AnchorPoint = Vector2.new(0, 1)
right.plate.Position = UDim2.new(0, M + STEER_W + 14, 1, -M)
chevron(right.plate, 90, UITheme.Palette.Bone, 54)
bind(right, function()
	steerR = true
	pushSteer()
end, function()
	steerR = false
	pushSteer()
end)

-- Педали. Тормоз внизу (под пальцем в покое), газ над ним: газ держат почти
-- всегда, а тормоз — короткими нажатиями, и промах вниз безопаснее промаха вверх.
local BRAKE_W, BRAKE_H = 150, 78
local GAS_W, GAS_H = 150, 96

local brake = makeButton(BRAKE_W, BRAKE_H, UITheme.Palette.Red)
brake.plate.Name = "Brake"
brake.plate.AnchorPoint = Vector2.new(1, 1)
brake.plate.Position = UDim2.new(1, -M, 1, -M)
chevron(brake.plate, 180, UITheme.Palette.Bone, 46)
bind(brake, function()
	player:SetAttribute("TouchBrake", 1)
end, function()
	player:SetAttribute("TouchBrake", 0)
end)

local gas = makeButton(GAS_W, GAS_H, UITheme.Palette.GreenLight)
gas.plate.Name = "Throttle"
gas.plate.AnchorPoint = Vector2.new(1, 1)
gas.plate.Position = UDim2.new(1, -M, 1, -(M + BRAKE_H + 10))
chevron(gas.plate, 0, UITheme.Palette.Bone, 52)
bind(gas, function()
	player:SetAttribute("TouchThrottle", 1)
end, function()
	player:SetAttribute("TouchThrottle", 0)
end)

local FIRE = 96
local fire = makeButton(FIRE, FIRE, UITheme.Palette.Bone)
fire.plate.Name = "Fire"
fire.plate.AnchorPoint = Vector2.new(1, 1)
fire.plate.Position = UDim2.new(1, -(M + (GAS_W - FIRE) / 2), 1, -(M + BRAKE_H + 10 + GAS_H + 16))
crosshairGlyph(fire.plate, UITheme.Palette.Red, 58) -- на костяном мазке знак красный: тот же Palette.Red, что у тормоза
bind(fire, function()
	player:SetAttribute("TouchFire", true)
end, function()
	player:SetAttribute("TouchFire", false)
end)

-- // Когда показывать -------------------------------------------------------
-- Ровно тогда же, когда виден прицел: идёт заезд (включён HUD) и игрок в машине.
-- В лобби и на экране итога педали только мешают — там свои плашки.
local hudGui: ScreenGui? = nil
task.spawn(function()
	local g = playerGui:WaitForChild("GraveyardHUD", 60)
	if g and g:IsA("ScreenGui") then
		hudGui = g
	end
end)

local function inVehicle(): boolean
	for _, vehicle in CollectionService:GetTagged("PlayerVehicle") do
		local seat = vehicle:FindFirstChild("DriveSeat")
		if seat and seat:IsA("VehicleSeat") and seat.Occupant then
			local character = seat.Occupant.Parent
			if character and Players:GetPlayerFromCharacter(character) == player then
				return true
			end
		end
	end
	return false
end

local function releaseAll()
	steerL, steerR = false, false
	player:SetAttribute("TouchSteer", 0)
	player:SetAttribute("TouchThrottle", 0)
	player:SetAttribute("TouchBrake", 0)
	player:SetAttribute("TouchFire", false)
	for input, release in heldBy do
		heldBy[input] = nil
		release()
	end
end

-- ШТАТНОЕ УПРАВЛЕНИЕ ГАСИМ, И ЭТО НЕ КОСМЕТИКА (2026-08-11, жалобы с телефона:
-- «загружается штатный круг внизу слева под нашими стрелками» и «нет управления
-- стволом»). Обе — одна причина.
--
-- Roblox рисует свой джойстик поверх нашей раскладки, но хуже другое: DynamicThumbstick
-- ловит касания на ВСЕЙ ЛЕВОЙ ПОЛОВИНЕ экрана и метит их gameProcessed. А наводка турели
-- в TurretAimClient ведётся перетаскиванием любого свободного пальца и касания с
-- gameProcessed отсеивает — иначе прицел дёргался бы от нажатий на наши же кнопки.
-- В итоге штатный джойстик СЪЕДАЛ половину жестов наводки, и ствол не слушался.
--
-- Ходить пешком в игре негде: игрок либо в машине, либо заморожен в лобби, либо смотрит
-- заезд зрителем. Прыжок и джойстик не нужны нигде.
local okControls = pcall(function()
	local playerModule = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")) :: any
	playerModule:GetControls():Disable()
end)
if not okControls then
	warn("[TouchControls] не удалось выключить штатное управление — штатный джойстик останется поверх раскладки")
end

player:SetAttribute("TouchActive", true)

RunService.Heartbeat:Connect(function()
	local hud = hudGui
	local show = hud ~= nil and hud.Parent ~= nil and hud.Enabled and inVehicle()
	-- ForceTouchUI — режим показа: педали видно и без заезда, иначе снимать нечего.
	if player:GetAttribute("ForceTouchUI") == true then
		show = true
	end
	if gui.Enabled ~= show then
		gui.Enabled = show
		if not show then
			releaseAll() -- машину отобрали с зажатым газом — газ снять
		end
	end
end)

print("[TouchControls] Сенсорное управление включено: руль слева, педали и гашетка справа.")
