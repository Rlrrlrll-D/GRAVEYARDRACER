--!strict
-- ModuleScript: ServerScriptService.MapGen
-- Генератор Terrain-дороги (веха 8, Phase 1): красит полотно по осевой
-- (безье-сегментам) — плита-основание поля + дорога цепочкой
-- вертикальных цилиндров (гладко на поворотах, без стыковых дыр). ОДИН источник
-- правды: форма трассы = данные `segments`, полотно строится из них. Снимает
-- «двойной источник» (террейн рисовался вручную, данные — отдельно).
--
-- Использование:
--   MapGen.paint(MapGen.Serpentine, { area = Vector2.new(580, 440) })
-- origin позволяет красить в песочнице (сдвиг), для реальной карты origin=0.

local Terrain = workspace.Terrain

local MapGen = {}

-- // МАТЕРИАЛЫ ПОЛОТНА И ПОЛЯ -------------------------------------------------
-- ОДИН ИСТОЧНИК ПРАВДЫ: этими же значениями MapBuilder отличает поле от дороги
-- (`grassPosition` = рейкаст + сверка материала), поэтому менять их только тут.
--
-- Поле НЕ `Grass`: у травяного материала движок рисует объёмную декорацию —
-- самую тяжёлую геометрию кадра (замер 2026-07-30: `Grass 438 852 tris / 100
-- draws` против `Opaque 5 367 / 5`). Выключить её нечем — `Terrain.Decoration`
-- в этой версии Roblox «not a valid member», проверено и из плагина, и из
-- серверного скрипта. Замер 2026-07-31 на плите 400×400 показал, что декорацию
-- движок вешает на ДВА материала — `Grass` и `LeafyGrass` (у обоих одинаковые
-- 23 664 tris), а у `Mud`/`Ground`/`Slate` в этой категории ровно ноль. Значит
-- единственный рычаг — материал, и поле красится `Mud`.
--
-- Чтобы поле при этом не выглядело чёрной грязью, MapBuilder тонирует `Mud`
-- через `Terrain:SetMaterialColor` в жухлый оливково-серый (см. FIELD_COLOR):
-- получается мёртвая трава кладбища без единого полигона травинок.
MapGen.FieldMaterial = Enum.Material.Mud
MapGen.RoadMaterial = Enum.Material.Ground

export type PaintOpts = {
	scale: number?, -- множитель координат (MapLayout.Scale)
	width: number?, -- ширина полотна, studs
	top: number?, -- Y верхней поверхности
	slab: number?, -- толщина грунтовой плиты
	origin: Vector3?, -- сдвиг всей карты (песочница/реальная)
	area: Vector2?, -- (ширина, глубина) базовой травяной плиты; nil = без плиты
	samplesPerSeg: number?, -- плотность цилиндров на сегмент
}

local function bezier(seg: { Vector2 }, t: number): Vector2
	local u = 1 - t
	return seg[1] * (u * u * u) + seg[2] * (3 * u * u * t) + seg[3] * (3 * u * t * t) + seg[4] * (t * t * t)
end
MapGen.bezier = bezier

-- Покрасить дорогу. segments — массив {P0, C1, C2, P3} (studs, до scale).
function MapGen.paint(segments: { { Vector2 } }, opts: PaintOpts?)
	local o = opts or {}
	local scale = o.scale or 1
	local width = o.width or 40
	local top = o.top or 2
	local slab = o.slab or 12
	local origin = o.origin or Vector3.zero
	local spp = o.samplesPerSeg or 80

	-- базовая травяная плита (чистим воздухом → трава), если задана area
	if o.area then
		local size = Vector3.new(o.area.X, slab, o.area.Y)
		local cf = CFrame.new(origin.X, top - slab / 2, origin.Z)
		Terrain:FillBlock(cf, size, Enum.Material.Air)
		Terrain:FillBlock(cf, size, MapGen.FieldMaterial)
	end

	-- дорога — цепочка вертикальных цилиндров Ground по осевой
	for _, seg in segments do
		for i = 0, spp do
			local p = bezier(seg, i / spp)
			Terrain:FillCylinder(
				CFrame.new(p.X * scale + origin.X, top - slab / 2, p.Y * scale + origin.Z),
				slab,
				width / 2,
				MapGen.RoadMaterial
			)
		end
	end
end

-- Покрасить дорогу по ПОЛИЛИНИИ (осевой) — points {Vector2}, замкнутая.
-- Между точками линейно до-семплим (sub) для гладкости.
function MapGen.paintPolyline(points: { Vector2 }, opts: PaintOpts?)
	local o = opts or {}
	local scale = o.scale or 1
	local width = o.width or 40
	local top = o.top or 2
	local slab = o.slab or 12
	local origin = o.origin or Vector3.zero
	local sub = o.samplesPerSeg or 4

	if o.area then
		-- Снести существующий террейн и ЩЕДРО по вертикали. Прежняя коробка шла от
		-- top-85 до top+5, то есть всё, что выше, оставалось: от старой ручной карты
		-- уцелели четыре бугра с верхушками на Y=8.6..10.9 (замер 2026-07-30). Низ им
		-- срезало, верхушка ложилась на плоское поле — юзер увидел «большой холм,
		-- покрытый травой, непонятного назначения» у восточной дуги: это кластер
		-- 50×40 studs у (181,114). Чистим до top+110, чтобы такого не оставалось.
		Terrain:FillBlock(
			CFrame.new(origin.X, top + 10, origin.Z),
			Vector3.new(o.area.X, 200, o.area.Y),
			Enum.Material.Air
		)
		Terrain:FillBlock(
			CFrame.new(origin.X, top - slab / 2, origin.Z),
			Vector3.new(o.area.X, slab, o.area.Y),
			MapGen.FieldMaterial
		)
	end

	local n = #points
	for i = 1, n do
		local a, b = points[i], points[i % n + 1]
		for s = 0, sub - 1 do
			local f = s / sub
			local x = (a.X + (b.X - a.X) * f) * scale + origin.X
			local z = (a.Y + (b.Y - a.Y) * f) * scale + origin.Z
			Terrain:FillCylinder(CFrame.new(x, top - slab / 2, z), slab, width / 2, MapGen.RoadMaterial)
		end
	end
end

-- Равномерные чекпоинты вдоль трассы (по длине дуги). count — сколько.
function MapGen.checkpoints(segments: { { Vector2 } }, count: number, scale: number?): { Vector2 }
	local s = scale or 1
	-- плотная полилиния + накопленная длина
	local pts: { Vector2 } = {}
	local cum: { number } = { 0 }
	local total = 0
	for _, seg in segments do
		for i = 0, 40 do
			local p = bezier(seg, i / 40) * s
			if #pts > 0 then
				total += (p - pts[#pts]).Magnitude
				table.insert(cum, total)
			end
			table.insert(pts, p)
		end
	end
	local out: { Vector2 } = {}
	for k = 1, count do
		local target = total * (k - 1) / count
		-- найти точку на этой длине
		local i = 1
		while i < #cum and cum[i + 1] < target do
			i += 1
		end
		table.insert(out, pts[i])
	end
	return out
end

-- // ЧЕРНОВИК формы: серпантин-круг (Phase 2) ---------------------------------
-- Длинная нижняя прямая (разгон) → правый вираж вверх → 3 «эса» (змейка) по
-- верху → верх-лево → левый вираж с изломом → замыкание. Замкнутый контур.
-- Пока ЧЕРНОВИК: активируется в MapLayout.TrackSegments после согласования формы
-- (тогда же MapBuilder красит террейн генератором и пересчитывает чекпоинты).
MapGen.Serpentine = {
	{ Vector2.new(-200, 165), Vector2.new(-70, 168), Vector2.new(70, 168), Vector2.new(200, 165) }, -- низ: прямая
	{ Vector2.new(200, 165), Vector2.new(250, 90), Vector2.new(250, 10), Vector2.new(230, -40) }, -- правый вираж вверх
	{ Vector2.new(230, -40), Vector2.new(230, -120), Vector2.new(220, -150), Vector2.new(170, -165) }, -- право-верх угол
	{ Vector2.new(170, -165), Vector2.new(120, -175), Vector2.new(115, -120), Vector2.new(60, -120) }, -- эс A
	{ Vector2.new(60, -120), Vector2.new(5, -120), Vector2.new(-5, -175), Vector2.new(-60, -165) }, -- эс B
	{ Vector2.new(-60, -165), Vector2.new(-115, -155), Vector2.new(-115, -120), Vector2.new(-170, -120) }, -- эс C
	{ Vector2.new(-170, -120), Vector2.new(-215, -90), Vector2.new(-250, -60), Vector2.new(-230, -30) }, -- верх-лево угол
	{ Vector2.new(-230, -30), Vector2.new(-215, 30), Vector2.new(-130, 20), Vector2.new(-160, 80) }, -- левый вираж с изломом
	{ Vector2.new(-160, 80), Vector2.new(-190, 120), Vector2.new(-235, 140), Vector2.new(-200, 165) }, -- замыкание
}

return MapGen
