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
		GeographicLatitude: number,
	},
	-- ДУГА СУТОК: ранний вечер → сумерки → ночь. Три опорных состояния одних и тех же
	-- свойств, между ними клиент плавно интерполирует (StarterPlayerScripts.DayNightCycle).
	-- Ранний вечер — то, ОТКУДА всё начинается (и что стоит в лобби), ночь (Atmosphere
	-- выше) — то, КУДА приходит; сумерки — промежуточная опора, чтобы закат шёл через
	-- тёплый оранжевый, а не серым провалом сразу в ночь.
	Evening: {
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
		-- НОЧЬ ТЕМНЕЕ (просьба юзера). Тронуты три величины, и все три — потолок
		-- «сколько света в сцене вообще»: сила луны (Brightness), общий подсвет теней
		-- (OutdoorAmbient) и цвет тумана, который на дальнем плане заменяет собой всё.
		-- Прежние 0.9 / (45,50,65) / (35,40,55) давали читаемую, но явно «синюю
		-- вечернюю» картинку. Ниже опускать нельзя: фары светят вперёд, а на что не
		-- падает их конус — читается только по этому фону, и на нуле трасса теряется.
		FogColor = Color3.fromRGB(20, 24, 34),
		FogStart = 40,
		FogEnd = 400,
		Brightness = 0.45,
		OutdoorAmbient = Color3.fromRGB(24, 27, 38),
		ColorCorrectionSaturation = -0.35,   -- приглушаем цвета
		ColorCorrectionContrast = 0.08,
		ColorCorrectionTintColor = Color3.fromRGB(210, 225, 255), -- лёгкий холодный оттенок
		-- 1.0, а не прежние 0.4: подобрано юзером живьём под неоновую обводку черепа
		-- (порог 1.5 не трогали). Влияет на ВСЮ сцену — фары, стрелки старта, огни.
		BloomIntensity = 1.0,
		StarCount = 4000,
		-- ЛУНА В КАДРЕ. Юзер: «луна должна быть в кадре, когда это соотносится со
		-- временем суток». Она и была на небе — но на широте 0 небесные тела идут
		-- почти через зенит: замер дал высоту луны +0.79…+0.91, то есть 52-65° над
		-- горизонтом, а водитель смотрит горизонтально (вертикальный полуугол обзора
		-- всего 35°). На 85 та же луна идёт по 7-28° — то есть в поле зрения.
		-- Сумеркам это не вредит: солнце на ClockTime 17.3 всё ещё над горизонтом
		-- (+5° против прежних +10°), закат сдвигается примерно на полчаса.
		GeographicLatitude = 85,
	},
	-- РАННИЙ ВЕЧЕР: с него начинается игра. Раньше тут стоял полдень (ClockTime 13.2,
	-- Brightness 2.4), но юзер: «надо сделать начало с сумерек, день — это ярковато
	-- для такого жанра», и он прав: при дневном солнце кладбище читается как парк.
	-- Теперь стартовая опора — солнце уже низко, свет косой и тёплый, но трассу и
	-- соперников ещё видно; дальше дуга идёт в густые сумерки и в ночь, то есть
	-- «темнеть медленно» сохранилось, просто дуга начинается ниже.
	-- ClockTime 17.3, а не 16.6: замер в плей показал, что на 16.6 солнце ещё градусов
	-- на 35 над горизонтом — это поздний день, а не сумерки. На 17.3 оно уже низкое и
	-- светит вкось, тени длинные. Полный закат (18.0) отдан следующей опоре.
	Evening = {
		ClockTime = 17.3,
		Density = 0.23,              -- дымка гуще полуденной: воздух уже вечерний
		FogColor = Color3.fromRGB(100, 92, 96),
		FogEnd = 950,
		Brightness = 2.15,
		OutdoorAmbient = Color3.fromRGB(112, 104, 108),
		ColorCorrectionSaturation = -0.11,
		ColorCorrectionTintColor = Color3.fromRGB(255, 238, 216),
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
		-- Сдвинуто с 0.55 на 0.35 вместе с переносом старта в сумерки: раньше первую
		-- половину дуги занимал день, и его стоило держать подольше. Теперь дуга и так
		-- начинается в сумерках, между опорами разница мала — а вот вторую половину
		-- (закат → ночь), где темнеет по-настоящему, надо тянуть подольше.
		DuskAt = 0.35,
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
