--!strict
-- LocalScript: StarterPlayerScripts.DayNightCycle
-- Сумерки → ночь по ходу заезда. Заезд стартует в густых сумерках (видно трассу,
-- соперников и кто где застрял) и постепенно уходит в глубокую ночь.
--
-- ПОЧЕМУ У КЛИЕНТА. Прежняя версия крутила переход на сервере и реплицировала
-- свойства Lighting каждые 0.1с: это дралось с клиентом (тот форсил ночь) и давало
-- строб света, а сам переход был так растянут, что заезд минуты шёл «днём». Здесь
-- сервер пишет ОДНУ метку — ReplicatedStorage.NightAnchor (время начала отсчёта по
-- серверным часам), — а каждый клиент интерполирует у себя, каждый кадр и без сети.
-- Метка серверная, поэтому опоздавший к заезду увидит ровно ту же стадию сумерек,
-- что и остальные, а не начнёт свои с нуля.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EnvironmentConfig = require(ReplicatedStorage:WaitForChild("EnvironmentConfig"))
local night = EnvironmentConfig.Atmosphere
local dusk = EnvironmentConfig.Dusk

-- NightAnchor: 0 — ночь (базовое состояние сервера), < 0 — держим сумерки (лобби),
-- > 0 — идёт переход, значение = серверное время его начала.
local anchor = ReplicatedStorage:WaitForChild("NightAnchor") :: NumberValue

local function waitForEffect<T>(class: string): T
	local found = Lighting:FindFirstChildOfClass(class)
	while not found do
		Lighting.ChildAdded:Wait()
		found = Lighting:FindFirstChildOfClass(class)
	end
	return found :: any
end

-- по КЛАССУ, а не по имени: AtmosphereSetup переиспользует то, что уже лежит в
-- Lighting, а лежащее в .rbxl могло быть переименовано — по имени бы зависли.
local atmosphere: Atmosphere = waitForEffect("Atmosphere")
local colorCorrection: ColorCorrectionEffect = waitForEffect("ColorCorrectionEffect")

-- ClockTime идёт ЧЕРЕЗ полночь: 17.9 → 24.7, на выходе берём остаток от 24.
-- Иначе интерполяция 17.9 → 0.7 отмотала бы сутки назад, через полдень.
local NIGHT_CLOCK = night.ClockTime + 24

-- Темнеет не линейно: первые секунды держим светлее (на старте толкотня и надо
-- видеть соседей), к концу перехода ускоряемся. t^1.6 даёт именно такую кривую.
local function ease(t: number): number
	return t ^ 1.6
end

local function apply(t: number)
	local k = ease(math.clamp(t, 0, 1))
	Lighting.ClockTime = (dusk.ClockTime + (NIGHT_CLOCK - dusk.ClockTime) * k) % 24
	Lighting.Brightness = dusk.Brightness + (night.Brightness - dusk.Brightness) * k
	Lighting.OutdoorAmbient = dusk.OutdoorAmbient:Lerp(night.OutdoorAmbient, k)
	Lighting.Ambient = Lighting.OutdoorAmbient
	Lighting.FogColor = dusk.FogColor:Lerp(night.FogColor, k)
	Lighting.FogEnd = dusk.FogEnd + (night.FogEnd - dusk.FogEnd) * k
	atmosphere.Density = dusk.Density + (night.Density - dusk.Density) * k
	colorCorrection.Saturation = dusk.ColorCorrectionSaturation
		+ (night.ColorCorrectionSaturation - dusk.ColorCorrectionSaturation) * k
	colorCorrection.TintColor = dusk.ColorCorrectionTintColor:Lerp(night.ColorCorrectionTintColor, k)
end

local running = false

local function tick()
	local startedAt = anchor.Value
	if startedAt == 0 then
		return true -- сервер ещё не провёл ни одного заезда: остаёмся на ночи
	end
	if startedAt < 0 then
		-- лобби: держим сумерки, чтобы на старте отсчёта небо не прыгнуло из ночи
		apply(0)
		return true
	end
	local elapsed = workspace:GetServerTimeNow() - startedAt
	local dur = math.max(dusk.NightFallSeconds, 1)
	if elapsed >= dur then
		apply(1) -- дошли до ночи — доводим точно и выходим из цикла
		return true
	end
	apply(elapsed / dur)
	return false
end

local function run()
	if running then
		return
	end
	running = true
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		if tick() then
			conn:Disconnect()
			running = false
		end
	end)
end

anchor.Changed:Connect(run)
run() -- на случай, если метка уже стоит (зашли посреди заезда)
