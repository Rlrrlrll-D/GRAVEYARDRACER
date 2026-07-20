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
Lighting.FogColor = cfg.FogColor
Lighting.FogStart = cfg.FogStart
Lighting.FogEnd = cfg.FogEnd
Lighting.GlobalShadows = true
Lighting.ShadowSoftness = 0.4
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
bloom.Threshold = 1.5

-- // Плавный переход день/вечер → ночь на старте --------------------------------
-- Выше атмосфера настроена на «ночь» (финал из EnvironmentConfig). Здесь стартуем
-- с тёплого вечера и за DUSK_DURATION секунд ведём свет в ночь: ClockTime (с
-- переносом через полночь), яркость, туман и цветокоррекция едут вместе.
local DUSK_DURATION = 120 -- секунд от дня до глубокой ночи (пара гоночных кругов)

-- дневные стартовые значения (тёплый солнечный день с лёгкой дымкой)
local eveClock = 13.5
local eveBrightness = 3.2
local eveAmbient = Color3.fromRGB(190, 172, 150)
local eveFog = Color3.fromRGB(198, 172, 148)
local eveAtmColor = Color3.fromRGB(240, 220, 195)
local eveDensity = 0.12
local eveTint = Color3.fromRGB(255, 248, 235)
local eveSat = 0.15

-- ночные цели (из cfg); ClockTime с переносом: 16.0 → 24.7 (= 0.7 mod 24)
local rawStart = eveClock
local rawEnd = cfg.ClockTime + 24

local function lerpN(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- снимок вечера
Lighting.ClockTime = eveClock
Lighting.Brightness = eveBrightness
Lighting.OutdoorAmbient = eveAmbient
Lighting.Ambient = eveAmbient
Lighting.FogColor = eveFog
atmosphere.Color = eveAtmColor
atmosphere.Density = eveDensity
colorCorrection.TintColor = eveTint
colorCorrection.Saturation = eveSat

task.spawn(function()
	local elapsed = 0 -- реальное wall-время через накопление task.wait (os.clock — CPU-время)
	while true do
		local a = math.clamp(elapsed / DUSK_DURATION, 0, 1)
		local e = a * a * (3 - 2 * a) -- smoothstep
		Lighting.ClockTime = lerpN(rawStart, rawEnd, e) % 24
		Lighting.Brightness = lerpN(eveBrightness, cfg.Brightness, e)
		Lighting.OutdoorAmbient = eveAmbient:Lerp(cfg.OutdoorAmbient, e)
		Lighting.Ambient = Lighting.OutdoorAmbient
		Lighting.FogColor = eveFog:Lerp(cfg.FogColor, e)
		atmosphere.Color = eveAtmColor:Lerp(cfg.Color, e)
		atmosphere.Density = lerpN(eveDensity, cfg.Density, e)
		colorCorrection.TintColor = eveTint:Lerp(cfg.ColorCorrectionTintColor, e)
		colorCorrection.Saturation = lerpN(eveSat, cfg.ColorCorrectionSaturation, e)
		if a >= 1 then
			break
		end
		elapsed += task.wait(0.1)
	end
end)

print("[AtmosphereSetup] Атмосфера кладбища настроена (переход день→ночь запущен).")
