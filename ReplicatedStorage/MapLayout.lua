--!strict
-- ModuleScript: ReplicatedStorage.MapLayout
-- Точная карта размещения объектов, переведённая из SVG-плана в studs.
-- Центр карты (0, 0) = стартовые ворота на перекрёстке восьмёрки.
-- Ось X — вправо по карте, ось Z — вниз по карте. Масштаб: 1 px SVG = 0.4 studs.
--
-- Баланс закодирован в этих данных:
--  * Hazard'ы стоят у кромки дороги на поворотах нижней петли (зона риска)
--    и по одному на верхней петле (чтобы разгон не был полностью безопасным).
--  * Могилы сгруппированы вокруг Hazard-зон: авария → штраф скорости 0.15 →
--    зомби из ближайших могил успевают добежать.
--  * Фонари стоят на каждом ключевом повороте — игрок видит опасность заранее.

export type PlacedObject = {
	Position: Vector2, -- X, Z в studs; высота Y вычисляется рейкастом по земле
	Rotation: number?, -- поворот вокруг Y в градусах (для декора)
}

export type MapLayoutType = {
	Scale: number,
	Hazards: {PlacedObject},
	Graves: {PlacedObject},
	Lamps: {PlacedObject},
	DeadTrees: {PlacedObject},
	Landmarks: {[string]: PlacedObject},
	TrackSegments: {{Vector2}}, -- кубические Безье восьмёрки (P0, C1, C2, P3)
	RaceCheckpoints: {Vector2}, -- чекпоинты гонки по порядку прохождения
}

local MapLayout: MapLayoutType = {
	Scale = 1, -- глобальный множитель: 1.5 растянет всю карту в полтора раза

	-- Красные плиты с SVG-карты: тег "Hazard" (+ авто-тег "Grave" ниже НЕ ставится)
	-- Все точки отодвинуты на ≥27 studs от осевой (край дороги 22 + запас),
	-- чтобы надгробия стояли у обочины, но не на полотне.
	Hazards = {
		{ Position = Vector2.new(-87, -14) },  -- западный вход в нижнюю петлю
		{ Position = Vector2.new(-120, 72) },  -- крутой юго-западный поворот
		{ Position = Vector2.new(-45, 138) },  -- южная дуга нижней петли
		{ Position = Vector2.new(24, 63) },    -- у мавзолея (слепой поворот)
		{ Position = Vector2.new(27, -29) },   -- выход с перекрёстка вверх
		{ Position = Vector2.new(40, -70) },   -- вход в верхнюю петлю
		{ Position = Vector2.new(120, -70) },  -- восточная дуга верхней петли
	},

	-- Зелёные кресты с SVG-карты: тег "Grave" (точки спавна зомби)
	-- Холмики отодвинуты на ≥24 studs от осевой — рядом с дорогой, но не на ней.
	Graves = {
		-- кластер нижней петли (вокруг Hazard-зоны)
		{ Position = Vector2.new(-104, 53) },
		{ Position = Vector2.new(-124, 90) },
		{ Position = Vector2.new(-80, 144) },
		{ Position = Vector2.new(-36, 64) },
		{ Position = Vector2.new(40, 96) },
		-- кластер верхней петли
		{ Position = Vector2.new(40, -60) },
		{ Position = Vector2.new(58, -140) },
		{ Position = Vector2.new(117, -60) },
		{ Position = Vector2.new(173, -105) },
		-- одиночная у перекрёстка
		{ Position = Vector2.new(-40, -44) },
	},

	-- Фонари: тег "FlickerLight" на PointLight внутри (≥28 studs от осевой)
	Lamps = {
		{ Position = Vector2.new(-32, -30) },  -- старт
		{ Position = Vector2.new(-180, 80) },  -- юго-западный поворот
		{ Position = Vector2.new(-67, 146) },  -- южная дуга
		{ Position = Vector2.new(3, -113) },   -- вход в верхнюю петлю
		{ Position = Vector2.new(123, -81) },  -- восточная дуга
		{ Position = Vector2.new(-42, 72) },   -- у мавзолея
	},

	-- Мёртвые деревья (чистый декор, без тегов; ≥32 studs от осевой)
	DeadTrees = {
		{ Position = Vector2.new(-168, -12), Rotation = 15 },
		{ Position = Vector2.new(-139, 146), Rotation = 80 },
		{ Position = Vector2.new(64, 132),  Rotation = 200 },
		{ Position = Vector2.new(192, -8),  Rotation = 310 },
		{ Position = Vector2.new(-16, -132), Rotation = 45 },
		{ Position = Vector2.new(-183, 67), Rotation = 130 },
		-- деревья у самой трассы (видны с дороги)
		{ Position = Vector2.new(-175, 30), Rotation = 70 },
		{ Position = Vector2.new(40, -40),  Rotation = 160 },
		{ Position = Vector2.new(25, 75),   Rotation = 240 },
		{ Position = Vector2.new(-10, -105), Rotation = 25 },
	},

	-- Осевая линия трассы-восьмёрки (те же кривые Безье, что на SVG-плане,
	-- пересчитанные в studs). По ней едут призраки-соперники RaceManager.
	TrackSegments = {
		{ Vector2.new(0, 0), Vector2.new(-92, 0), Vector2.new(-152, 44), Vector2.new(-152, 84) },
		{ Vector2.new(-152, 84), Vector2.new(-152, 128), Vector2.new(-80, 132), Vector2.new(-32, 100) },
		{ Vector2.new(-32, 100), Vector2.new(-4, 82), Vector2.new(4, 44), Vector2.new(0, 0) },
		{ Vector2.new(0, 0), Vector2.new(-4, -44), Vector2.new(4, -82), Vector2.new(32, -100) },
		{ Vector2.new(32, -100), Vector2.new(80, -132), Vector2.new(152, -128), Vector2.new(152, -84) },
		{ Vector2.new(152, -84), Vector2.new(152, -36), Vector2.new(92, 0), Vector2.new(0, 0) },
	},

	-- Чекпоинты гонки (по порядку; круг засчитывается после прохождения всех)
	RaceCheckpoints = {
		Vector2.new(-73, 11),   -- западный подход к нижней петле
		Vector2.new(-152, 84),  -- юго-западный поворот
		Vector2.new(-110, 120), -- южная дуга
		Vector2.new(-32, 100),  -- выход к мавзолею
		Vector2.new(0, 0),      -- перекрёсток (первый проход)
		Vector2.new(18, -87),   -- подъём в верхнюю петлю
		Vector2.new(110, -120), -- северная дуга
		Vector2.new(152, -84),  -- восточный поворот
		Vector2.new(110, -24),  -- спуск к финишу
		Vector2.new(0, 0),      -- финишная черта у ворот
	},

	-- Крупные ориентиры (ставятся вручную или шаблоном, координаты для сверки)
	Landmarks = {
		-- StartGate = стартовая черта (спавн/стрелки). Визуальная арка ворот
		-- сдвинута вперёд по ходу на X=-45 (стоит на траве у обочины), но
		-- логика старта остаётся на (0,0).
		StartGate = { Position = Vector2.new(0, 0) },
		Mausoleum = { Position = Vector2.new(-75, 70) },
		Chapel    = { Position = Vector2.new(92, -100) },
	},
}

return MapLayout
