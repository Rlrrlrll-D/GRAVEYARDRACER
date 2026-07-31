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
local evening = EnvironmentConfig.Evening

-- NightAnchor: 0 — ночь (базовое состояние сервера), < 0 — держим ВЕЧЕР (лобби),
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

-- ДУГА СУТОК: три опоры вместо двух («темнеть должно медленно, не сразу»). Первой
-- опорой был ПОЛДЕНЬ, но юзер: «надо сделать начало с сумерек, день — это ярковато
-- для такого жанра», — теперь это ранний вечер. Дуга: вечер → сумерки → ночь,
-- сумерки стоят на доле DuskAt.
--
-- ClockTime идёт ЧЕРЕЗ полночь: 16.6 → 17.9 → 24.7, на выходе берём остаток от 24.
-- Иначе интерполяция к 0.7 отмотала бы сутки назад, через полдень.
local KEYS = {
	{ at = 0, cfg = evening, clock = evening.ClockTime },
	{ at = math.clamp(dusk.DuskAt, 0.05, 0.95), cfg = dusk, clock = dusk.ClockTime },
	{ at = 1, cfg = night, clock = night.ClockTime + 24 },
}

-- Темнеет не линейно: первую часть держим светлее (на старте толкотня и надо
-- видеть соседей), к концу перехода ускоряемся. t^1.35 даёт такую кривую, но
-- мягче прежней 1.6 — иначе день проскакивает почти мгновенно.
local function ease(t: number): number
	return t ^ 1.35
end

-- Молния множит текущую яркость на время вспышки (см. блок ThunderFlash ниже).
local flashBoost = 1

local function apply(t: number)
	local k = ease(math.clamp(t, 0, 1))
	-- какой отрезок дуги сейчас и насколько мы в нём продвинулись
	local i = 1
	while i < #KEYS - 1 and k > KEYS[i + 1].at do
		i += 1
	end
	local a, b = KEYS[i], KEYS[i + 1]
	local span = b.at - a.at
	local f = span > 1e-6 and math.clamp((k - a.at) / span, 0, 1) or 0
	local ca, cb = a.cfg, b.cfg

	Lighting.ClockTime = (a.clock + (b.clock - a.clock) * f) % 24
	Lighting.Brightness = (ca.Brightness + (cb.Brightness - ca.Brightness) * f) * flashBoost
	Lighting.OutdoorAmbient = ca.OutdoorAmbient:Lerp(cb.OutdoorAmbient, f)
	Lighting.Ambient = Lighting.OutdoorAmbient
	Lighting.FogColor = ca.FogColor:Lerp(cb.FogColor, f)
	Lighting.FogEnd = ca.FogEnd + (cb.FogEnd - ca.FogEnd) * f
	atmosphere.Density = ca.Density + (cb.Density - ca.Density) * f
	colorCorrection.Saturation = ca.ColorCorrectionSaturation
		+ (cb.ColorCorrectionSaturation - ca.ColorCorrectionSaturation) * f
	colorCorrection.TintColor = ca.ColorCorrectionTintColor:Lerp(cb.ColorCorrectionTintColor, f)
end

-- Насколько далеко зашёл переход прямо сейчас. nil = метки нет, свет держит сервер.
local function progress(): number?
	local startedAt = anchor.Value
	if startedAt == 0 then
		return nil -- сервер ещё не провёл ни одного заезда: остаёмся на ночи
	end
	if startedAt < 0 then
		return 0 -- лобби: ДЕНЬ, чтобы на старте отсчёта небо не прыгнуло из ночи
	end
	local elapsed = workspace:GetServerTimeNow() - startedAt
	return math.clamp(elapsed / math.max(dusk.NightFallSeconds, 1), 0, 1)
end

local running = false

local function tick()
	local t = progress()
	if not t then
		return true
	end
	apply(t)
	-- Выходим из цикла, когда двигаться больше некуда: дошли до ночи либо стоим
	-- на дне в лобби. Обратно разбудит anchor.Changed.
	return t >= 1 or anchor.Value < 0
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

-- // Молния ------------------------------------------------------------------
-- Сервер (GraveyardAmbience) только объявляет момент, саму вспышку рисуем у себя —
-- УМНОЖЕНИЕМ текущей яркости, а не записью абсолютного значения. Пока флэш жил на
-- сервере, он читал серверную (всегда ночную) яркость и возвращал её всем — первая
-- же молния гасила сумерки в ночь.
local thunder = EnvironmentConfig.Thunder
local flashSignal = ReplicatedStorage:WaitForChild("ThunderFlash", 30)
if flashSignal and flashSignal:IsA("NumberValue") then
	flashSignal.Changed:Connect(function()
		local t = progress()
		if not t then
			return -- светом заведует сервер, не вмешиваемся
		end
		flashBoost = thunder.FlashBrightnessBoost
		apply(t)
		task.wait(thunder.FlashDuration)
		flashBoost = 1
		local after = progress()
		if after then
			apply(after)
		end
	end)
end
