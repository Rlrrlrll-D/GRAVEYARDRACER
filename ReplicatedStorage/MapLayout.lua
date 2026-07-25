--!strict
-- ModuleScript: ReplicatedStorage.MapLayout
-- Карта размещения объектов. Форма трассы теперь ИЗ Road.svg (Adobe Illustrator):
-- путь #918542 (дорога-лента) → осевая линия (постоянная ширина), масштаб ×1.4.
-- `TrackPolyline` — единый источник правды формы (studs, центр 0,0). MapBuilder
-- красит Terrain по ней (MapGen), RaceCore считает по ней геометрию/чекпоинты.
-- Hazards/Graves/Lamps сгенерированы вдоль осевой (офсет на обочину); декор —
-- процедурной россыпью в MapBuilder (авто-подстройка под форму дороги).

export type PlacedObject = {
	Position: Vector2, -- X, Z в studs; высота Y — рейкастом по земле
	Rotation: number?,
}

export type MapLayoutType = {
	Scale: number,
	Hazards: {PlacedObject},
	Graves: {PlacedObject},
	Lamps: {PlacedObject},
	DeadTrees: {PlacedObject},
	Landmarks: {[string]: PlacedObject},
	TrackSegments: {{Vector2}}, -- устар. (восьмёрка); форма теперь в TrackPolyline
	TrackPolyline: {Vector2}, -- осевая трассы из Road.svg (замкнутая, studs)
	RaceCheckpoints: {Vector2},
	StartDir: Vector2, -- направление старта (для грида/ворот)
}

local MapLayout: MapLayoutType = {
	Scale = 1,

	Hazards = {
		{ Position = Vector2.new(-181.2, 67.5) },
		{ Position = Vector2.new(-190.1, -102.5) },
		{ Position = Vector2.new(123.3, 225.9) },
		{ Position = Vector2.new(-121.2, -205.9) },
		{ Position = Vector2.new(246.7, -204.6) },
		{ Position = Vector2.new(163.3, -113.2) },
		{ Position = Vector2.new(-236.6, 216.9) },
	},

	Graves = {
		{ Position = Vector2.new(169.3, 233.4) },
		{ Position = Vector2.new(76.1, 92.5) },
		{ Position = Vector2.new(156.1, -131.8) },
		{ Position = Vector2.new(-71.9, -120.2) },
		{ Position = Vector2.new(-73.4, -9.5) },
		{ Position = Vector2.new(-40.4, 102.2) },
		{ Position = Vector2.new(-166.9, 188.6) },
		{ Position = Vector2.new(-312.3, 209.2) },
		{ Position = Vector2.new(-215.0, -17.6) },
		{ Position = Vector2.new(-282.5, -254.5) },
		{ Position = Vector2.new(-41.2, -229.4) },
		{ Position = Vector2.new(144.0, -283.7) },
		{ Position = Vector2.new(233.7, -143.5) },
		{ Position = Vector2.new(282.0, 77.8) },
	},

	Lamps = {
		{ Position = Vector2.new(169.2, 237.4) },
		{ Position = Vector2.new(117.6, -47.1) },
		{ Position = Vector2.new(-192.1, -102.6) },
		{ Position = Vector2.new(-106.1, 99.1) },
		{ Position = Vector2.new(-245.2, 193.8) },
		{ Position = Vector2.new(-311.0, -189.0) },
		{ Position = Vector2.new(43.4, -214.5) },
		{ Position = Vector2.new(276.0, -60.4) },
	},

	DeadTrees = {}, -- деревья — процедурной россыпью (MapBuilder), не по точкам

	Landmarks = {
		StartGate = { Position = Vector2.new(-42.55, 65.87) },
	},

	TrackSegments = {}, -- пусто: форма трассы теперь в TrackPolyline

	StartDir = Vector2.new(-0.999, 0.038),

	RaceCheckpoints = {
		Vector2.new(-42.55, 65.87), Vector2.new(-132.24, 220.98), Vector2.new(-278.02, 136.07), Vector2.new(-271.89, -119.44), Vector2.new(-123.41, -236.21), Vector2.new(122.46, -235.86),
		Vector2.new(267.54, -130.18), Vector2.new(254.78, 123.92), Vector2.new(106.66, 252.51), Vector2.new(142.23, 4.69), Vector2.new(-0.91, -159.70), Vector2.new(-108.13, -51.18),
	},

	TrackPolyline = {
		Vector2.new(-42.55, 65.87), Vector2.new(-55.58, 66.36), Vector2.new(-68.63, 66.48), Vector2.new(-81.67, 66.45), Vector2.new(-94.72, 66.46), Vector2.new(-107.76, 66.78),
		Vector2.new(-120.77, 67.77), Vector2.new(-133.62, 69.98), Vector2.new(-145.77, 74.59), Vector2.new(-155.26, 83.38), Vector2.new(-158.85, 95.85), Vector2.new(-157.53, 108.80),
		Vector2.new(-153.62, 121.23), Vector2.new(-148.41, 133.19), Vector2.new(-143.08, 145.10), Vector2.new(-138.19, 157.19), Vector2.new(-134.04, 169.55), Vector2.new(-131.01, 182.24),
		Vector2.new(-129.51, 195.18), Vector2.new(-129.71, 208.21), Vector2.new(-132.24, 220.98), Vector2.new(-137.22, 233.02), Vector2.new(-144.72, 243.64), Vector2.new(-154.42, 252.34),
		Vector2.new(-165.68, 258.89), Vector2.new(-177.96, 263.21), Vector2.new(-190.82, 265.34), Vector2.new(-203.85, 265.33), Vector2.new(-216.71, 263.23), Vector2.new(-229.08, 259.15),
		Vector2.new(-240.68, 253.21), Vector2.new(-251.15, 245.47), Vector2.new(-260.19, 236.08), Vector2.new(-267.56, 225.34), Vector2.new(-273.01, 213.51), Vector2.new(-276.82, 201.04),
		Vector2.new(-278.84, 188.16), Vector2.new(-279.67, 175.14), Vector2.new(-279.71, 162.10), Vector2.new(-279.14, 149.07), Vector2.new(-278.02, 136.07), Vector2.new(-276.41, 123.12),
		Vector2.new(-274.39, 110.24), Vector2.new(-272.08, 97.40), Vector2.new(-269.49, 84.61), Vector2.new(-266.72, 71.86), Vector2.new(-263.80, 59.14), Vector2.new(-260.81, 46.45),
		Vector2.new(-257.90, 33.73), Vector2.new(-255.24, 20.96), Vector2.new(-253.09, 8.09), Vector2.new(-251.84, -4.89), Vector2.new(-251.38, -17.93), Vector2.new(-251.63, -30.97),
		Vector2.new(-252.55, -43.98), Vector2.new(-254.15, -56.93), Vector2.new(-256.37, -69.78), Vector2.new(-259.07, -82.54), Vector2.new(-262.40, -95.15), Vector2.new(-266.91, -107.38),
		Vector2.new(-271.89, -119.44), Vector2.new(-275.82, -131.87), Vector2.new(-278.70, -144.59), Vector2.new(-280.25, -157.54), Vector2.new(-280.43, -170.58), Vector2.new(-279.11, -183.55),
		Vector2.new(-276.02, -196.21), Vector2.new(-271.16, -208.30), Vector2.new(-264.41, -219.45), Vector2.new(-256.09, -229.48), Vector2.new(-246.52, -238.32), Vector2.new(-235.80, -245.74),
		Vector2.new(-224.19, -251.66), Vector2.new(-211.67, -255.17), Vector2.new(-198.66, -255.63), Vector2.new(-185.82, -253.44), Vector2.new(-173.41, -249.44), Vector2.new(-161.26, -244.67),
		Vector2.new(-149.04, -240.14), Vector2.new(-136.41, -236.90), Vector2.new(-123.41, -236.21), Vector2.new(-110.66, -238.75), Vector2.new(-98.75, -244.06), Vector2.new(-87.20, -250.12),
		Vector2.new(-75.41, -255.71), Vector2.new(-63.31, -260.56), Vector2.new(-50.88, -264.52), Vector2.new(-38.18, -267.47), Vector2.new(-25.26, -269.24), Vector2.new(-12.23, -269.72),
		Vector2.new(0.78, -268.79), Vector2.new(13.57, -266.30), Vector2.new(25.95, -262.21), Vector2.new(37.75, -256.68), Vector2.new(48.77, -249.69), Vector2.new(59.67, -242.53),
		Vector2.new(71.30, -236.65), Vector2.new(83.80, -232.98), Vector2.new(96.77, -231.84), Vector2.new(109.75, -232.97), Vector2.new(122.46, -235.86), Vector2.new(134.82, -240.03),
		Vector2.new(146.88, -245.01), Vector2.new(158.76, -250.39), Vector2.new(170.72, -255.61), Vector2.new(183.41, -258.51), Vector2.new(196.43, -259.15), Vector2.new(209.41, -258.01),
		Vector2.new(222.18, -255.39), Vector2.new(234.57, -251.32), Vector2.new(246.35, -245.73), Vector2.new(257.16, -238.46), Vector2.new(266.48, -229.36), Vector2.new(273.71, -218.54),
		Vector2.new(278.36, -206.38), Vector2.new(280.32, -193.50), Vector2.new(280.48, -180.47), Vector2.new(279.07, -167.50), Vector2.new(276.15, -154.80), Vector2.new(272.16, -142.38),
		Vector2.new(267.54, -130.18), Vector2.new(262.59, -118.11), Vector2.new(257.65, -106.03), Vector2.new(252.94, -93.87), Vector2.new(248.58, -81.57), Vector2.new(244.78, -69.09),
		Vector2.new(241.56, -56.45), Vector2.new(239.00, -43.66), Vector2.new(237.13, -30.75), Vector2.new(235.94, -17.76), Vector2.new(235.42, -4.73), Vector2.new(235.51, 8.32),
		Vector2.new(236.19, 21.34), Vector2.new(237.40, 34.33), Vector2.new(239.09, 47.26), Vector2.new(241.21, 60.14), Vector2.new(243.69, 72.94), Vector2.new(246.45, 85.70),
		Vector2.new(249.37, 98.41), Vector2.new(252.33, 111.12), Vector2.new(254.78, 123.92), Vector2.new(256.09, 136.90), Vector2.new(256.53, 149.94), Vector2.new(256.15, 162.97),
		Vector2.new(254.96, 175.96), Vector2.new(253.01, 188.86), Vector2.new(250.07, 201.57), Vector2.new(246.20, 214.02), Vector2.new(241.13, 226.03), Vector2.new(234.93, 237.50),
		Vector2.new(227.29, 248.05), Vector2.new(217.76, 256.92), Vector2.new(206.63, 263.68), Vector2.new(194.31, 267.88), Vector2.new(181.40, 269.67), Vector2.new(168.36, 269.78),
		Vector2.new(155.33, 269.00), Vector2.new(142.40, 267.32), Vector2.new(129.70, 264.39), Vector2.new(117.60, 259.55), Vector2.new(106.66, 252.51), Vector2.new(98.02, 242.80),
		Vector2.new(92.32, 231.10), Vector2.new(89.08, 218.49), Vector2.new(87.80, 205.52), Vector2.new(88.45, 192.50), Vector2.new(90.10, 179.56), Vector2.new(92.46, 166.73),
		Vector2.new(95.40, 154.02), Vector2.new(98.80, 141.42), Vector2.new(102.51, 128.92), Vector2.new(106.49, 116.49), Vector2.new(110.61, 104.11), Vector2.new(114.80, 91.76),
		Vector2.new(119.04, 79.42), Vector2.new(123.26, 67.08), Vector2.new(127.42, 54.71), Vector2.new(131.46, 42.31), Vector2.new(135.31, 29.84), Vector2.new(138.92, 17.31),
		Vector2.new(142.23, 4.69), Vector2.new(145.12, -8.03), Vector2.new(147.52, -20.85), Vector2.new(149.24, -33.78), Vector2.new(149.96, -46.80), Vector2.new(149.46, -59.83),
		Vector2.new(147.43, -72.70), Vector2.new(143.53, -85.12), Vector2.new(137.72, -96.78), Vector2.new(129.53, -106.93), Vector2.new(119.95, -115.78), Vector2.new(109.49, -123.56),
		Vector2.new(98.36, -130.35), Vector2.new(86.82, -136.43), Vector2.new(75.01, -141.94), Vector2.new(62.80, -146.54), Vector2.new(50.34, -150.37), Vector2.new(37.70, -153.60),
		Vector2.new(24.95, -156.34), Vector2.new(12.05, -158.31), Vector2.new(-0.91, -159.70), Vector2.new(-13.93, -160.57), Vector2.new(-26.97, -160.91), Vector2.new(-40.01, -160.51),
		Vector2.new(-53.01, -159.52), Vector2.new(-65.96, -158.00), Vector2.new(-78.83, -155.90), Vector2.new(-91.56, -153.07), Vector2.new(-104.07, -149.38), Vector2.new(-116.23, -144.67),
		Vector2.new(-127.85, -138.75), Vector2.new(-139.05, -132.07), Vector2.new(-149.40, -124.16), Vector2.new(-156.82, -113.56), Vector2.new(-159.74, -100.92), Vector2.new(-158.16, -88.05),
		Vector2.new(-152.22, -76.51), Vector2.new(-143.55, -66.81), Vector2.new(-132.77, -59.52), Vector2.new(-120.74, -54.52), Vector2.new(-108.13, -51.18), Vector2.new(-95.29, -48.86),
		Vector2.new(-82.36, -47.13), Vector2.new(-69.40, -45.67), Vector2.new(-56.43, -44.23), Vector2.new(-43.49, -42.59), Vector2.new(-30.62, -40.47), Vector2.new(-17.91, -37.56),
		Vector2.new(-5.57, -33.33), Vector2.new(5.87, -27.13), Vector2.new(15.45, -18.32), Vector2.new(21.73, -6.97), Vector2.new(24.32, 5.77), Vector2.new(24.12, 18.80),
		Vector2.new(21.91, 31.64), Vector2.new(16.38, 43.38), Vector2.new(7.22, 52.59), Vector2.new(-4.25, 58.74), Vector2.new(-16.69, 62.62), Vector2.new(-29.55, 64.79),
	},
}

return MapLayout
