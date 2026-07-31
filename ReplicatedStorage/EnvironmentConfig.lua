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
	-- ДУГА СУТОК: день → сумерки → ночь. Три опорных состояния одних и тех же
	-- свойств, между ними клиент плавно интерполирует (StarterPlayerScripts.DayNightCycle).
	-- День — то, ОТКУДА всё начинается (и что стоит в лобби), ночь (Atmosphere выше) —
	-- то, КУДА приходит; сумерки — промежуточная опора, чтобы закат шёл через тёплый
	-- оранжевый, а не серым провалом из дня прямо в ночь.
	Day: {
		ClockTime: number,
		Density: number,
		FogColor: Color3,
		FogEnd: number,
		Brightness: number,
		OutdoorAmbient: Color3,
		ColorCorrectionSaturation: number,
		ColorCorrectionTintColor: Color3,
	},
	Dusk: {
		ClockTime: number, -- ClockTime растёт до Atmosphere.ClockTime + 24 (через полночь)
		Density: number,
		FogColor: Color3,
		FogEnd: number,
		Brightness: number,
		OutdoorAmbient: Color3,
		ColorCorrectionSaturation: number,
		ColorCorrectionTintColor: Color3,
		NightFallSeconds: number, -- за сколько секунд от старта отсчёта наступает полная ночь
		DuskAt: number, -- доля перехода, на которой стоят сумерки (0..1)
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
	-- ДЕНЬ: с него начинается игра (юзер: «начало игры днём, сумерки и темнеть
	-- должно медленно, не сразу»). Пасмурный серо-голубой полдень, а не курорт:
	-- кладбище должно читаться мрачно даже при солнце.
	Day = {
		ClockTime = 13.2,
		Density = 0.14,              -- лёгкая дымка: даль есть, но воздух не стеклянный
		FogColor = Color3.fromRGB(150, 156, 168),
		FogEnd = 1200,
		Brightness = 2.4,
		OutdoorAmbient = Color3.fromRGB(150, 152, 160),
		ColorCorrectionSaturation = -0.06,
		ColorCorrectionTintColor = Color3.fromRGB(248, 246, 240),
	},
	Dusk = {
		ClockTime = 17.9,            -- солнце у горизонта: густые сумерки, трассу видно
		Density = 0.28,              -- дымка реже, чем ночью — дальше видно
		FogColor = Color3.fromRGB(78, 68, 78),   -- тёплый закатный сумрак
		FogEnd = 900,                -- туман отодвинут: видно, кто где застрял
		Brightness = 2.1,
		OutdoorAmbient = Color3.fromRGB(105, 98, 110),
		ColorCorrectionSaturation = -0.12,
		ColorCorrectionTintColor = Color3.fromRGB(255, 236, 214), -- тёплый, к ночи уходит в холод
		-- Юзер: «темнеть должно медленно, не сразу». Раньше было 80 секунд от сумерек
		-- до ночи; теперь тот же счётчик покрывает ВСЮ дугу день→сумерки→ночь, так что
		-- на одну только вторую половину (сумерки→ночь) приходится больше прежнего.
		NightFallSeconds = 210,
		-- Сумерки стоят чуть дальше середины: день держится дольше заката, а сам
		-- закат — самая красивая часть дуги, её тянуть незачем.
		DuskAt = 0.55,
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
