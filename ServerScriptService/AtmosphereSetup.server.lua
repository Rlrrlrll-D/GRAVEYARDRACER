--!strict
-- Script: ServerScriptService.AtmosphereSetup
-- Настраивает Lighting, Atmosphere, Sky и пост-эффекты под туманное лунное
-- кладбище. Запускается один раз при старте сервера; свойства Lighting
-- реплицируются на всех клиентов автоматически.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnvironmentConfig = require(ReplicatedStorage:WaitForChild("EnvironmentConfig"))
local cfg = EnvironmentConfig.Atmosphere

Lighting.ClockTime = cfg.ClockTime
Lighting.Brightness = cfg.Brightness
Lighting.OutdoorAmbient = cfg.OutdoorAmbient
Lighting.Ambient = cfg.OutdoorAmbient
Lighting.GlobalShadows = true
Lighting.ShadowSoftness = 0.4
-- Широта задаёт наклон небесной дуги: на 0 солнце и луна ходят через зенит и в
-- кадр водителя не попадают. Держим их низко над горизонтом (см. EnvironmentConfig).
Lighting.GeographicLatitude = cfg.GeographicLatitude
Lighting.EnvironmentDiffuseScale = 0.6
Lighting.EnvironmentSpecularScale = 0.3

-- // Atmosphere (объёмный туман/дымка) ------------------------------------
local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") :: Atmosphere?
if not atmosphere then
	atmosphere = Instance.new("Atmosphere")
	atmosphere.Parent = Lighting
end
atmosphere.Density = cfg.Density
atmosphere.Offset = cfg.Offset
atmosphere.Color = cfg.Color
atmosphere.Decay = cfg.Decay
atmosphere.Glare = cfg.Glare
atmosphere.Haze = cfg.Haze

-- // Ночное небо (без текстур — просто звёзды и луна по умолчанию) --------
local sky = Lighting:FindFirstChildOfClass("Sky") :: Sky?
if not sky then
	sky = Instance.new("Sky")
	sky.Parent = Lighting
end
sky.CelestialBodiesShown = true
sky.StarCount = cfg.StarCount
sky.MoonAngularSize = 24
sky.SunAngularSize = 1

-- // Цветокоррекция (приглушаем цвета, холодный ночной оттенок) -----------
local colorCorrection = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") :: ColorCorrectionEffect?
if not colorCorrection then
	colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Parent = Lighting
end
colorCorrection.Saturation = cfg.ColorCorrectionSaturation
colorCorrection.Contrast = cfg.ColorCorrectionContrast
colorCorrection.TintColor = cfg.ColorCorrectionTintColor

-- // Лёгкое свечение вокруг ярких источников (луна, фонари) ---------------
local bloom = Lighting:FindFirstChildOfClass("BloomEffect") :: BloomEffect?
if not bloom then
	bloom = Instance.new("BloomEffect")
	bloom.Parent = Lighting
end
bloom.Intensity = cfg.BloomIntensity
bloom.Size = 24
-- 0.35 подобрано юзером живьём (2026-08-10, клавиши порога в NeonTune) вместе с
-- BloomIntensity 0.50, толщиной линии черепа 0.04 и золотым цветом 252,213,62.
-- Порог — «с какой яркости пиксель вообще начинает светиться». Прежние 1.5 брали
-- только самое яркое; на 0.35 в блюм попадает заметно больше сцены — не только
-- черепа, но и фары, фонари, стрелки старта и вообще всё светлое. Это осознанная
-- цена за то, чтобы волосяная линия черепа давала ореол.
bloom.Threshold = 0.35

-- // Сумерки → ночь ------------------------------------------------------------
-- Значения выше — это НОЧЬ, и она же базовое состояние: всё, что реплицируется с
-- сервера, стоит на ночи, поэтому даже без клиентского скрипта картинка корректна.
--
-- Сам переход считает КЛИЕНТ (StarterPlayerScripts.DayNightCycle). Прежняя версия
-- крутила его на сервере и реплицировала свойства Lighting каждые 0.1с — это
-- дралось с клиентом, который форсил ночь, и давало строб света. Теперь сервер
-- пишет ОДНО число на заезд — метку времени начала сумерек, — а каждый клиент
-- плавно интерполирует у себя. Ноль спама по сети и никакой борьбы за свойства.
local anchor = ReplicatedStorage:FindFirstChild("NightAnchor")
if not anchor then
	anchor = Instance.new("NumberValue")
	anchor.Name = "NightAnchor"
	anchor.Parent = ReplicatedStorage
end
;(anchor :: NumberValue).Value = 0 -- 0 = переход не идёт, держим ночь

print("[AtmosphereSetup] Атмосфера кладбища настроена (ночь; сумерки — по метке NightAnchor).")
