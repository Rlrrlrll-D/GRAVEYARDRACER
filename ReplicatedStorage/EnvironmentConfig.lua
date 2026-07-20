--!strict
-- ModuleScript: ReplicatedStorage.EnvironmentConfig
-- Тонкая настройка атмосферы кладбища: туман, освещение, гроза, мерцание фонарей.

export type EnvironmentConfigType = {
	Atmosphere: {
		ClockTime: number,
		Density: number,
		Offset: number,
		Color: Color3,
		Decay: Color3,
		Glare: number,
		Haze: number,
		FogColor: Color3,
		FogStart: number,
		FogEnd: number,
		Brightness: number,
		OutdoorAmbient: Color3,
		ColorCorrectionSaturation: number,
		ColorCorrectionContrast: number,
		ColorCorrectionTintColor: Color3,
		BloomIntensity: number,
		StarCount: number,
	},
	Thunder: {
		MinInterval: number,
		MaxInterval: number,
		FlashBrightnessBoost: number,
		FlashDuration: number,
	},
	Flicker: {
		MinBrightness: number,
		MaxBrightness: number,
		MinIntervalSeconds: number,
		MaxIntervalSeconds: number,
	},
}

local EnvironmentConfig: EnvironmentConfigType = {
	Atmosphere = {
		ClockTime = 0.7,             -- ~00:42, глубокая ночь
		Density = 0.45,
		Offset = 0.25,
		Color = Color3.fromRGB(150, 160, 170),
		Decay = Color3.fromRGB(40, 45, 60),
		Glare = 0,
		Haze = 3,
		FogColor = Color3.fromRGB(35, 40, 55),
		FogStart = 40,
		FogEnd = 400,
		Brightness = 0.9,
		OutdoorAmbient = Color3.fromRGB(45, 50, 65),
		ColorCorrectionSaturation = -0.35,   -- приглушаем цвета
		ColorCorrectionContrast = 0.08,
		ColorCorrectionTintColor = Color3.fromRGB(210, 225, 255), -- лёгкий холодный оттенок
		BloomIntensity = 0.4,
		StarCount = 4000,
	},
	Thunder = {
		MinInterval = 18,
		MaxInterval = 45,
		FlashBrightnessBoost = 1.6,
		FlashDuration = 0.15,
	},
	Flicker = {
		MinBrightness = 0.6,
		MaxBrightness = 1.8,
		MinIntervalSeconds = 0.08,
		MaxIntervalSeconds = 0.6,
	},
}

return EnvironmentConfig
