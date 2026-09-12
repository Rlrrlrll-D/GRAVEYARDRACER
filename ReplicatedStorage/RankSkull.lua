--!strict
-- ModuleScript: ReplicatedStorage.RankSkull
-- ЧЕРЕП-РАНГ КАК РИСУНОК В ТЕКСТУРЕ КУЗОВА (план B, одобрен юзером 2026-09-11).
--
-- Почему не декаль: у Decal/Texture/SurfaceGui только альфа-смешивание, а юзер хочет
-- «как в Photoshop» — Multiply/Overlay, чтобы текстура кузова читалась сквозь цвет.
-- Значит, смешивать надо в самой текстуре: берём текстуру кузова в EditableImage,
-- растеризуем череп из настоящего вектора (SkullOutline) попиксельно нужным режимом
-- и отдаём кузову через TextureContent. Всё на клиенте: EditableImage не реплицируется,
-- зато и заливать ничего не надо. Один композит на (кузов, набор мест, цвет, режим),
-- общий для всех машин с таким рангом — см. кэш ниже.
--
-- ГДЕ РИСОВАТЬ. Развёртки кузовов перепакованы под это (tools/blender/reunwrap_buggy.py,
-- coffin_v2.py): четыре зоны — верх (капот / крышка), корма, левый и правый борт —
-- лежат в атласе цельными прямоугольниками с известными UV. Числа ниже — из вывода
-- этих скриптов; поменяешь развёртку — перепиши их здесь.
--
-- ОРИЕНТАЦИЯ. У «верха» и «кормы» ось V идёт вверх по рисунку (к носу / к небу),
-- у бортов зона повёрнута: длина борта вдоль V, высота вдоль U — там череп рисуется
-- лёжа, макушкой в +U. Череп симметричен, поэтому зеркальность U не важна.
--
-- ЦВЕТ КУЗОВА. Текстура на MeshPart ОТКЛЮЧАЕТ Color3 (проверено 2026-09-11), поэтому
-- краску скина домножаем на холст сами, до черепов — см. compose. У гроба текстуры
-- нет: холст 512² белый × краска = ровный цвет, и Multiply черепа на нём — просто
-- цвет черепа, притемнённый краской.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkullOutline = require(ReplicatedStorage:WaitForChild("SkullOutline"))
local SkullShapes = require(ReplicatedStorage:WaitForChild("SkullShapes"))

local RankSkull = {}

export type Zone = {
	u0: number, v0: number, u1: number, v1: number, -- прямоугольник зоны в UV
	rotated: boolean, -- длина зоны вдоль V (борта)
	studsW: number, studsH: number, -- физический размер зоны, studs (ширина × высота)
	-- где череп: центр в долях зоны (ta вдоль длины/ширины, tb вдоль высоты) и высота
	-- черепа в studs. Из отметок юзера на листе ракурсов (2026-09-11).
	ta: number, tb: number, height: number,
	flip: boolean?, -- развернуть на 180°: зубами «вперёд» (к носу) — просьба юзера для капота/крышки
	-- Отзеркалить по ширине. Roblox при импорте разворачивает меш на 180° вокруг Y (x → −x),
	-- и ось U капота/крышки на машине идёт справа налево: симметричный череп этого не
	-- выдавал, лента с именем ранга читалась зеркально (2026-09-12). Корма и борта в
	-- развёртке уже перевёрнуты (flipU в Blender) и не мирятся.
	mirror: boolean?,
}

export type BodySpec = {
	atlas: number, -- сторона квадратного атласа, px
	-- сила краски: 1 = краска домножает холст целиком, меньше — холст просвечивает
	-- (гроб 0.65: BLOOD на досках уходил в чистый тёмно-красный, юзер 2026-09-12 —
	-- «прижать к тёмно-коричневому»)
	paintStrength: number?,
	-- тон холста: домножение текстуры до краски (багги 0.85 — «придави тон, нужен
	-- контраст с черепом», юзер 2026-09-12)
	baseTone: number?,
	texture: string?, -- текстура кузова (nil = белый холст)
	zones: { [string]: Zone },
}

-- Багги: атлас 1024, капот/корма 80 px/stud, борта 60 (повёрнуты). Зона «left» —
-- U = высота, V = длина от кормы (ta = 0 у кормы); «right» зеркальна: ta = 0 у носа.
-- Корма — три грани (нижняя панель / уступ / верхняя), череп на нижней (tb ≈ 0.27).
-- Борт: нижняя панель между крыльями, по центру (ta 0.5; юзер 2026-09-11: «слишком
-- близко к заднему крылу — сместить к центру»).
RankSkull.Bodies = {
	buggy = {
		atlas = 1024,
		texture = "rbxassetid://108257958365417", -- ржавчина (tools/blender/buggy_texture.py), импорт юзера 2026-09-12
		paintStrength = 0.65, -- BLOOD «сильно отдаёт красным» — как у гроба, в тёмно-коричневый
		baseTone = 0.85,
		zones = {
			top   = { u0 = 0.015, v0 = 0.635, u1 = 0.376, v1 = 0.914, rotated = false, studsW = 4.63, studsH = 3.57, ta = 0.5,  tb = 0.5,  height = 3.1, flip = true, mirror = true },
			rear  = { u0 = 0.406, v0 = 0.635, u1 = 0.802, v1 = 0.846, rotated = false, studsW = 5.07, studsH = 2.70, ta = 0.5,  tb = 0.27, height = 1.25 },
			left  = { u0 = 0.635, v0 = 0.015, u1 = 0.794, v1 = 0.588, rotated = true,  studsW = 9.77, studsH = 2.71, ta = 0.50, tb = 0.26, height = 1.2 },
			right = { u0 = 0.824, v0 = 0.015, u1 = 0.982, v1 = 0.586, rotated = true,  studsW = 9.74, studsH = 2.70, ta = 0.50, tb = 0.26, height = 1.2 },
		},
	},
	-- Гроб: атлас 1024 в развёртке, холст берём 512 (текстуры нет, хватит). Крышка —
	-- V к носу (череп у носа, tb ≈ 0.68, там же стоял крест); борта: «left» ta = 0 у
	-- кормы, «right» — у носа; заднее колесо на ta ≈ 0.34 от кормы.
	coffin = {
		atlas = 1024,
		texture = "rbxassetid://90339981575144", -- доски (tools/blender/coffin_texture.py), импорт юзера 2026-09-12
		paintStrength = 0.65,
		zones = {
			top   = { u0 = 0.015, v0 = 0.585, u1 = 0.366, v1 = 0.942, rotated = false, studsW = 6.00, studsH = 6.10, ta = 0.5,  tb = 0.38, height = 3.1, flip = true, mirror = true },
			rear  = { u0 = 0.396, v0 = 0.585, u1 = 0.659, v1 = 0.784, rotated = false, studsW = 4.48, studsH = 3.40, ta = 0.5,  tb = 0.42, height = 2.2 },
			left  = { u0 = 0.585, v0 = 0.015, u1 = 0.758, v1 = 0.435, rotated = true,  studsW = 8.28, studsH = 3.40, ta = 0.30, tb = 0.45, height = 1.9 },
			right = { u0 = 0.788, v0 = 0.015, u1 = 0.960, v1 = 0.435, rotated = true,  studsW = 8.28, studsH = 3.40, ta = 0.70, tb = 0.45, height = 1.9 },
		},
	},
} :: { [string]: BodySpec }

RankSkull.Colors = {
	-- Лестница «от кости к золоту» по рангам (юзер 2026-09-11: «цвета черепов от
	-- костного до жёлтого, светлый череп на тёмном фоне»).
	bone = Color3.fromRGB(188, 179, 162), -- подобрано юзером в SkullTune 2026-09-12 (было Palette.Bone 224,214,170)
	ivory = Color3.fromRGB(236, 222, 140),
	amber = Color3.fromRGB(248, 214, 100),
	gold = Color3.fromRGB(255, 210, 70), -- жёлтый «YOU WIN!» и контура черепов чекпоинтов
} :: { [string]: Color3 }

-- // Растр черепа --------------------------------------------------------------
-- ФОРМЫ ПО РАНГАМ (2026-09-12): юзер ушёл от «один череп, разные цвета» к «разные
-- черепа с лентой и именем ранга» (SkullShapes из skull_range.ai); цвет у всех один.
-- Форма по имени ранга; без имени — классический череп чекпоинтов (SkullOutline).
type Shape = { loops: { { { number } } }, minY: number, maxY: number, aspect: number }
local shapeCache: { [string]: Shape } = {}

local function shapeFor(name: string?): Shape
	local key = name or "@outline"
	local ready = shapeCache[key]
	if ready then
		return ready
	end
	local loops = (name and SkullShapes.Shapes[name]) or SkullOutline.Loops
	local minY, maxY = math.huge, -math.huge
	for _, loop in loops do
		for _, p in loop do
			minY = math.min(minY, p[2])
			maxY = math.max(maxY, p[2])
		end
	end
	local shape = { loops = loops, minY = minY, maxY = maxY, aspect = maxY - minY }
	shapeCache[key] = shape
	return shape
end

local SUBROWS = 4 -- подстрок на пиксель: край гладкий, но без «свечения» — покрытие честное

local function spansAt(shape: Shape, ny: number): { number }
	local xs = {}
	for _, loop in shape.loops do
		local n = #loop
		for i = 1, n do
			local a, b = loop[i], loop[(i % n) + 1]
			local y1, y2 = a[2], b[2]
			if (y1 > ny) ~= (y2 > ny) then
				local t = (ny - y1) / (y2 - y1)
				table.insert(xs, a[1] + t * (b[1] - a[1]))
			end
		end
	end
	table.sort(xs)
	return xs
end

-- Покрытие черепа шириной w px (высота от пропорции формы): cov[j*w + i + 1], j = 0 — макушка.
local covCache: { [string]: { w: number, h: number, cov: { number } } } = {}
local function coverage(shapeName: string?, w: number): (number, number, { number })
	local ck = (shapeName or "@outline") .. "|" .. w
	local ready = covCache[ck]
	if ready then
		return ready.w, ready.h, ready.cov
	end
	local shape = shapeFor(shapeName)
	local h = math.max(1, math.floor(w * shape.aspect + 0.5))
	local cov = table.create(w * h, 0)
	local weight = 1 / SUBROWS
	for py = 0, h - 1 do
		for s = 0, SUBROWS - 1 do
			local ny = shape.maxY - ((py + (s + 0.5) / SUBROWS) / h) * shape.aspect
			local xs = spansAt(shape, ny)
			for i = 1, #xs - 1, 2 do
				local a = (xs[i] + 0.5) * w
				local b = (xs[i + 1] + 0.5) * w
				if b > a then
					local from = math.max(0, math.floor(a))
					local to = math.min(w - 1, math.ceil(b) - 1)
					for px = from, to do
						local l = math.max(a, px)
						local r = math.min(b, px + 1)
						if r > l then
							local idx = py * w + px + 1
							cov[idx] += (r - l) * weight
						end
					end
				end
			end
		end
	end
	covCache[ck] = { w = w, h = h, cov = cov }
	return w, h, cov
end

-- // Режимы наложения (формулы W3C compositing, поканально, 0..1) -------------
local function softLightD(b: number): number
	if b <= 0.25 then
		return ((16 * b - 12) * b + 4) * b
	end
	return math.sqrt(b)
end
local BLEND: { [string]: (number, number) -> number } = {
	normal = function(_, c)
		return c
	end,
	multiply = function(b, c)
		return b * c
	end,
	screen = function(b, c)
		return 1 - (1 - b) * (1 - c)
	end,
	overlay = function(b, c)
		if b <= 0.5 then
			return 2 * b * c
		end
		return 1 - 2 * (1 - b) * (1 - c)
	end,
	softlight = function(b, c)
		if c <= 0.5 then
			return b - (1 - 2 * c) * b * (1 - b)
		end
		return b + (2 * c - 1) * (softLightD(b) - b)
	end,
	-- Linear Dodge (Add): текстура проходит сквозь цвет целиком (наклон 1), череп
	-- светлеет на величину цвета × плотность. Юзер: «нужно, чтобы пробивала текстура
	-- через цвет» + «светлый череп на тёмном фоне» — Screen выбеливает, Overlay
	-- тускловат, Add даёт и то и другое.
	lineardodge = function(b, c)
		return math.min(1, b + c)
	end,
}
RankSkull.Modes = BLEND

-- // Базовые холсты ------------------------------------------------------------
-- Пиксели текстуры кузова читаем один раз (CreateEditableImageAsync — сетевой вызов,
-- и только для ассетов создателя места; при отказе — nil, черепа не будет, кузов
-- останется как есть).
local baseCache: { [string]: { size: number, buf: buffer }? } = {}
local baseTried: { [string]: boolean } = {}

local baseLoading: { [string]: boolean } = {}
local function loadBase(bodyId: string): { size: number, buf: buffer }?
	-- Первый вызов читает текстуру с йилдом; остальные, пришедшие в это время, ЖДУТ его,
	-- а не получают nil (гараж: десять кузовов одеваются разом, восемь оставались без
	-- черепов — 2026-09-12).
	while baseLoading[bodyId] do
		task.wait()
	end
	if baseTried[bodyId] then
		return baseCache[bodyId]
	end
	baseTried[bodyId] = true
	baseLoading[bodyId] = true
	local spec = RankSkull.Bodies[bodyId]
	if not spec then
		return nil
	end
	local size = spec.atlas
	local buf: buffer
	if spec.texture then
		local ok, img = pcall(function()
			return AssetService:CreateEditableImageAsync(Content.fromAssetId(tonumber(spec.texture:match("%d+")) :: number))
		end)
		if not ok or not img then
			baseLoading[bodyId] = nil
			warn("[RankSkull] текстура кузова " .. bodyId .. " не читается: " .. tostring(img))
			return nil
		end
		size = img.Size.X
		buf = img:ReadPixelsBuffer(Vector2.zero, img.Size)
		img:Destroy() -- пиксели скопированы, сам объект больше не нужен
	else
		buf = buffer.create(size * size * 4)
		buffer.fill(buf, 0, 255) -- белый холст, непрозрачный
	end
	baseCache[bodyId] = { size = size, buf = buf }
	baseLoading[bodyId] = nil
	return baseCache[bodyId]
end

-- // Композит ------------------------------------------------------------------
-- Рисует череп в одну зону прямо в buf (RGBA8, сторона size).
-- lift — подъём яркости сверх режима: к результату наложения прибавляется lift × цвет.
-- Нужен, потому что кузов тёмный (rust ×0.78): Overlay на базе ~0.3 не даёт светлее
-- ~0.55 даже белым, а юзер хочет «черепа светлее» при сохранении зерна текстуры
-- (наклон Overlay остаётся, подъём лишь сдвигает).
local function paintZone(buf: buffer, size: number, zone: Zone, color: Color3, mode: string, opacity: number, lift: number, shapeName: string?)
	local blend = BLEND[mode] or BLEND.normal
	-- плотность px/stud одинакова по обеим осям зоны (так собран атлас)
	local pxPerStud = if zone.rotated then ((zone.u1 - zone.u0) * size) / zone.studsH else ((zone.u1 - zone.u0) * size) / zone.studsW
	local aspect = shapeFor(shapeName).aspect
	local sh = math.max(4, math.floor(zone.height * pxPerStud + 0.5)) -- высота черепа, px
	local sw = math.max(4, math.floor(sh / aspect + 0.5))
	local w, h, cov = coverage(shapeName, sw)
	-- центр черепа в пикселях атласа
	local cx, cy
	if zone.rotated then
		cx = (zone.u0 + zone.tb * (zone.u1 - zone.u0)) * size
		cy = (1 - (zone.v0 + zone.ta * (zone.v1 - zone.v0))) * size
	else
		cx = (zone.u0 + zone.ta * (zone.u1 - zone.u0)) * size
		cy = (1 - (zone.v0 + zone.tb * (zone.v1 - zone.v0))) * size
	end
	local cr, cg, cb = color.R, color.G, color.B
	for j = 0, h - 1 do
		for i = 0, w - 1 do
			local a = cov[j * w + i + 1] * opacity
			if a > 0.002 then
				local x, y
				-- flip = честный поворот на 180° (как наклейку крутят): и строки, и столбцы;
				-- один только jj давал зеркальную ленту — буквы вверх ногами, порядок прежний
				local jj = if zone.flip then h - 1 - j else j -- flip: макушка к водителю, зубы к носу
				local ii = if (zone.mirror == true) ~= (zone.flip == true) then w - 1 - i else i
				if zone.rotated then
					-- макушка (j = 0) смотрит в +U = +x
					x = math.floor(cx + (h / 2 - 1 - jj) + 0.5)
					y = math.floor(cy - w / 2 + ii + 0.5)
				else
					x = math.floor(cx - w / 2 + ii + 0.5)
					y = math.floor(cy - h / 2 + jj + 0.5)
				end
				if x >= 0 and y >= 0 and x < size and y < size then
					local o = (y * size + x) * 4
					local br, bg, bb = buffer.readu8(buf, o) / 255, buffer.readu8(buf, o + 1) / 255, buffer.readu8(buf, o + 2) / 255
					local rr = br + (math.min(1, blend(br, cr) + lift * cr) - br) * a
					local rg = bg + (math.min(1, blend(bg, cg) + lift * cg) - bg) * a
					local rb = bb + (math.min(1, blend(bb, cb) + lift * cb) - bb) * a
					buffer.writeu8(buf, o, math.clamp(math.floor(rr * 255 + 0.5), 0, 255))
					buffer.writeu8(buf, o + 1, math.clamp(math.floor(rg * 255 + 0.5), 0, 255))
					buffer.writeu8(buf, o + 2, math.clamp(math.floor(rb * 255 + 0.5), 0, 255))
				end
			end
		end
	end
end

-- // Пул картинок -----------------------------------------------------------------
-- БЮДЖЕТ EditableImage КОНЕЧЕН (2026-09-12: «Failed to create empty EditableImage …
-- memory budget limits» после десятка движений ползунка SkullTune: каждый вариант
-- создавал новую 1024² = 4 МБ и жил в кэше вечно). Поэтому:
--   * учитываем, какие кузова носят какую картинку (users), и картинку, которую
--     носит ТОЛЬКО пересобираемый кузов, переписываем НА МЕСТЕ (WritePixelsBuffer),
--     не создавая новой — так подкрутка не плодит картинок вовсе;
--   * картинок в пуле не больше MAX_IMAGES: лишние, которых никто не носит,
--     уничтожаем перед созданием новой. 12, а не 6: гараж-песочница (DevGarage)
--     одевает 2 кузова × 5 красок разом, плюс своя машина.
local imageCache: { [string]: EditableImage } = {}
local keyOf: { [EditableImage]: string } = {}
local users: { [EditableImage]: { [Instance]: boolean } } = {}
local wornBy: { [Instance]: EditableImage } = setmetatable({}, { __mode = "k" }) :: any
local MAX_IMAGES = 12

local function userCount(img: EditableImage): number
	local n = 0
	for _ in users[img] or {} do
		n += 1
	end
	return n
end

local function forget(img: EditableImage)
	local key = keyOf[img]
	if key then
		imageCache[key] = nil
	end
	keyOf[img] = nil
	users[img] = nil
	img:Destroy()
end

local function cacheCount(): number
	local n = 0
	for _ in imageCache do
		n += 1
	end
	return n
end

-- Освободить место: выкинуть картинки, которые никто не носит.
local function evictUnused(keep: EditableImage?)
	for _, img in imageCache do
		if cacheCount() < MAX_IMAGES then
			break
		end
		if img ~= keep and userCount(img) == 0 then
			forget(img)
		end
	end
end

-- Собрать текстуру кузова bodyId: холст × краска, сверху черепа в зонах zoneNames
-- (список может быть пустым — на нулевом ранге нужна одна краска). Кэш по ключу:
-- одна картинка на комбинацию, общая для всех машин. Йилдит на первом обращении к
-- кузову (чтение текстуры). nil — если кузов неизвестен или EditableImage недоступен.
--
-- tint — цвет краски (Color3 детали). ЛЮБАЯ текстура на MeshPart ОТКЛЮЧАЕТ Color3
-- (проверено 2026-09-11: красный Color на текстурированном багги и на гробе с белым
-- EditableImage — без следа краски). До этого краски магазина на багги цвет не давали
-- вовсе, только материал. Юзер: «пусть краски красят и багги» — значит домножаем
-- сами: текстура × краска у багги, ровный холст цвета краски у гроба. Из этого же
-- следует, что композит нужен ВСЕГДА, даже без черепов — иначе на нулевом ранге
-- багги был бы некрашеным, а с первым черепом вдруг перекрашивался.
-- reuse — картинка, которую кузов носит сейчас: если её больше никто не носит, новый
-- композит пишется в неё на месте (см. пул выше).
-- patch — пятнистая краска (ShopCatalog.Item.patchy): tint тогда — базовая ржавчина,
-- а patch.color ложится локальными пятнами по шуму на долю coverage площади.
-- mode — как цвет пятна ложится на базу: "tint" = цвет × (0.6 + яркость базы) или любой
-- режим из BLEND (multiply/overlay/screen/softlight/lineardodge/normal); opacity —
-- плотность пятна.
export type Patch = { color: Color3, coverage: number, scale: number, seed: number, mode: string?, opacity: number? }

-- Порог шума под заданную долю площади: шум не равномерен, поэтому порог не считаем,
-- а меряем — 4096 проб по всему атласу, берём квантиль. Один раз на набор параметров.
local thrCache: { [string]: number } = {}
local function patchNoise(u: number, v: number, scale: number, seed: number): number
	-- две октавы: крупные пятна + рваный край
	return math.noise(u * scale, v * scale, seed) + 0.5 * math.noise(u * scale * 2.1 + 3.7, v * scale * 2.1 + 1.3, seed + 11)
end
-- Поле шума на весь атлас, f32-буфер. Считать ~1 с (2M вызовов math.noise), поэтому
-- держим одно последнее на (size, scale, seed): подкрутка цвета/доли/режима шум не
-- трогает, пересчёт только при смене масштаба или раскладки.
local fieldKey: string? = nil
local fieldBuf: buffer? = nil
local function noiseField(size: number, scale: number, seed: number): buffer
	local k = ("%d|%.2f|%d"):format(size, scale, seed)
	if fieldKey == k and fieldBuf then
		return fieldBuf
	end
	local b = buffer.create(size * size * 4)
	local inv = 1 / size
	for y = 0, size - 1 do
		local v = (y + 0.5) * inv
		for x = 0, size - 1 do
			buffer.writef32(b, (y * size + x) * 4, patchNoise((x + 0.5) * inv, v, scale, seed))
		end
	end
	fieldKey, fieldBuf = k, b
	return b
end

local function patchThreshold(p: Patch): number
	local k = ("%.3f|%.2f|%d"):format(p.coverage, p.scale, p.seed)
	local ready = thrCache[k]
	if ready then
		return ready
	end
	local samples = table.create(4096)
	local rng = Random.new(p.seed)
	for i = 1, 4096 do
		samples[i] = patchNoise(rng:NextNumber(), rng:NextNumber(), p.scale, p.seed)
	end
	table.sort(samples)
	local idx = math.clamp(math.floor(#samples * (1 - p.coverage) + 0.5), 1, #samples)
	thrCache[k] = samples[idx]
	return samples[idx]
end

-- shapeName — форма черепа из SkullShapes (имя ранга); nil — классический SkullOutline.
function RankSkull.compose(bodyId: string, zoneNames: { string }, colorName: string?, mode: string, opacity: number, tint: Color3?, lift: number?, reuse: EditableImage?, patch: Patch?, shapeName: string?): EditableImage?
	local spec = RankSkull.Bodies[bodyId]
	if not spec then
		return nil
	end
	local color = colorName and RankSkull.Colors[colorName] or nil
	local names = if color then table.clone(zoneNames) else {}
	table.sort(names)
	local paint = tint or Color3.new(1, 1, 1)
	local up = lift or 0
	-- в ключе сам цвет, а не имя: SkullTune крутит RankSkull.Colors[name] на живую
	local patchKey = if patch then ("%s|%.3f|%.2f|%d|%s|%.2f"):format(patch.color:ToHex(), patch.coverage, patch.scale, patch.seed, patch.mode or "tint", patch.opacity or 1) else "-"
	-- тон/сила краски/место и размер черепа на капоте — поля спеки, SkullTune крутит их на живую
	local top = spec.zones.top
	local specKey = ("%.2f|%.2f|%.2f|%.2f"):format(spec.baseTone or 1, spec.paintStrength or 1, top and top.tb or 0, top and top.height or 0)
	local key = ("%s|%s|%s|%s|%s|%.2f|%.2f|%s|%s|%s"):format(bodyId, table.concat(names, ","), shapeName or "-", color and color:ToHex() or "-", mode, opacity, up, paint:ToHex(), patchKey, specKey)
	local ready = imageCache[key]
	if ready then
		return ready
	end
	local base = loadBase(bodyId)
	if not base then
		return nil
	end
	local size = base.size
	local buf = buffer.create(size * size * 4)
	buffer.copy(buf, 0, base.buf)
	-- краска: домножить каждый пиксель; paintStrength < 1 подмешивает белый — холст просвечивает
	local ps = spec.paintStrength or 1
	local tone = spec.baseTone or 1
	local pr, pg, pb = tone * (1 - (1 - paint.R) * ps), tone * (1 - (1 - paint.G) * ps), tone * (1 - (1 - paint.B) * ps)
	if math.abs(pr - 1) > 0.001 or math.abs(pg - 1) > 0.001 or math.abs(pb - 1) > 0.001 then
		for i = 0, size * size - 1 do
			local o = i * 4
			buffer.writeu8(buf, o, math.min(255, math.floor(buffer.readu8(buf, o) * pr + 0.5)))
			buffer.writeu8(buf, o + 1, math.min(255, math.floor(buffer.readu8(buf, o + 1) * pg + 0.5)))
			buffer.writeu8(buf, o + 2, math.min(255, math.floor(buffer.readu8(buf, o + 2) * pb + 0.5)))
		end
	end
	-- Пятна краски (мох): где шум выше порога — цвет краски по яркости базы, край
	-- мягкий (полоса ±0.06 по шуму), чтобы пятно не резалось по пикселям.
	if patch then
		local thr = patchThreshold(patch)
		local field = noiseField(size, patch.scale, patch.seed)
		local cr, cg, cb = patch.color.R, patch.color.G, patch.color.B
		local pmode = patch.mode or "tint"
		local pblend = BLEND[pmode]
		local pop = patch.opacity or 1
		for y = 0, size - 1 do
			for x = 0, size - 1 do
				local i4 = (y * size + x) * 4
				local n = buffer.readf32(field, i4)
				local a = math.clamp((n - thr + 0.06) / 0.12, 0, 1) * pop
				if a > 0 then
					local o = i4
					local br, bg, bb = buffer.readu8(buf, o) / 255, buffer.readu8(buf, o + 1) / 255, buffer.readu8(buf, o + 2) / 255
					local mr, mg, mb
					if pblend then
						mr, mg, mb = pblend(br, cr), pblend(bg, cg), pblend(bb, cb)
					else
						-- "tint": цвет × яркость базы — зерно ржавчины остаётся и внутри пятна
						local lum = 0.6 + (0.3 * br + 0.59 * bg + 0.11 * bb)
						mr, mg, mb = math.min(1, cr * lum), math.min(1, cg * lum), math.min(1, cb * lum)
					end
					buffer.writeu8(buf, o, math.floor((br + (mr - br) * a) * 255 + 0.5))
					buffer.writeu8(buf, o + 1, math.floor((bg + (mg - bg) * a) * 255 + 0.5))
					buffer.writeu8(buf, o + 2, math.floor((bb + (mb - bb) * a) * 255 + 0.5))
				end
			end
		end
	end
	if color then
		for _, name in names do
			local zone = spec.zones[name]
			if zone then
				paintZone(buf, size, zone, color, mode, opacity, up, shapeName)
			end
		end
	end
	local dims = Vector2.new(size, size)
	-- (1) своя картинка, которую никто больше не носит — переписать на месте
	local target: EditableImage? = nil
	if reuse and keyOf[reuse] and userCount(reuse) <= 1 and reuse.Size == dims then
		target = reuse
	end
	-- (2) иначе освободить пул и создать новую
	if not target then
		evictUnused(reuse)
		local ok, img = pcall(function()
			return AssetService:CreateEditableImage({ Size = dims })
		end)
		if ok and img then
			target = img
		elseif reuse and keyOf[reuse] and reuse.Size == dims then
			-- бюджет кончился: жертвуем своей, даже если её носит кто-то ещё — он
			-- пересоберётся своим ключом при следующем обращении
			target = reuse
		else
			warn("[RankSkull] EditableImage недоступен: " .. tostring(img))
			return nil
		end
	end
	local final = target :: EditableImage
	local wrote = pcall(function()
		final:WritePixelsBuffer(Vector2.zero, dims, buf)
	end)
	if not wrote then
		warn("[RankSkull] EditableImage не пишется")
		return nil
	end
	local old = keyOf[final]
	if old then
		imageCache[old] = nil
	end
	imageCache[key] = final
	keyOf[final] = key
	return final
end

-- Что носит кузов сейчас (для reuse в compose).
function RankSkull.worn(body: Instance): EditableImage?
	return wornBy[body]
end

-- Кузов больше не носит ничего (машину убрали): отпустить картинку.
function RankSkull.release(body: Instance)
	local prev = wornBy[body]
	if prev and users[prev] then
		users[prev][body] = nil
	end
	wornBy[body] = nil
end

-- Надеть картинку на кузов (nil — вернуть штатную текстуру). Ведёт учёт, кто что носит.
function RankSkull.apply(body: MeshPart, img: EditableImage?)
	local prev = wornBy[body]
	if prev and prev ~= img and users[prev] then
		users[prev][body] = nil
	end
	wornBy[body] = img
	if img then
		users[img] = users[img] or {}
		users[img][body] = true
		body.TextureContent = Content.fromObject(img)
	else
		local spec = RankSkull.Bodies[body:GetAttribute("BodyId") :: any]
		body.TextureContent = if spec and spec.texture then Content.fromAssetId(tonumber(spec.texture:match("%d+")) :: number) else Content.none
	end
end

-- Дев: подсунуть базу кузова сырыми пикселями (RGBA8, строки сверху) — предпросмотр
-- текстуры в Studio до загрузки ассета (тестура гроба, 2026-09-12). Композиты этого
-- кузова забываются: ненадетые — уничтожаются, надетые доживут до переодевания.
function RankSkull.setBase(bodyId: string, size: number, buf: buffer)
	baseCache[bodyId] = { size = size, buf = buf }
	baseTried[bodyId] = true
	local prefix = bodyId .. "|"
	for key, img in imageCache do
		if key:sub(1, #prefix) == prefix then
			if userCount(img) == 0 then
				forget(img)
			else
				imageCache[key] = nil
				keyOf[img] = nil
			end
		end
	end
end

-- // Дев-подкрутка (SkullTune) ------------------------------------------------
-- Пока Overrides не nil, сторож (RankSkull.client) берёт режим/плотность/подъём/краску
-- отсюда вместо GameConfig и цвета кузова; OverridesChanged — пересобрать всем машинам.
-- byBody — то же по кузовам (buggy/coffin): плотность/подъём/режим/цвет черепа у каждого
-- свои (юзер 2026-09-12: «на багги сильнее», «череп цвета ржавчины с наложением»).
export type BodyOverride = { mode: string?, opacity: number?, lift: number?, colorName: string? }
export type Overrides = { mode: string?, opacity: number?, lift: number?, tint: Color3?, colorName: string?, shape: string?, patch: Patch?, patchOff: boolean?, byBody: { [string]: BodyOverride }? }
RankSkull.Overrides = nil :: Overrides?
RankSkull.OverridesChanged = Instance.new("BindableEvent")

return RankSkull
