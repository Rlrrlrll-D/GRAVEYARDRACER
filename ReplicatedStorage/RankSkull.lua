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
-- ЦВЕТ КУЗОВА. Скин красит деталь Color3, шейдер домножает на него текстуру ПОСЛЕ
-- нашего композита — как и раньше. У гроба текстуры нет: рисуем на белом холсте
-- 512², и любой режим наложения там вырождается в обычный (белый × цвет = цвет).

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkullOutline = require(ReplicatedStorage:WaitForChild("SkullOutline"))

local RankSkull = {}

export type Zone = {
	u0: number, v0: number, u1: number, v1: number, -- прямоугольник зоны в UV
	rotated: boolean, -- длина зоны вдоль V (борта)
	studsW: number, studsH: number, -- физический размер зоны, studs (ширина × высота)
	-- где череп: центр в долях зоны (ta вдоль длины/ширины, tb вдоль высоты) и высота
	-- черепа в studs. Из отметок юзера на листе ракурсов (2026-09-11).
	ta: number, tb: number, height: number,
	flip: boolean?, -- развернуть на 180°: зубами «вперёд» (к носу) — просьба юзера для капота/крышки
}

export type BodySpec = {
	atlas: number, -- сторона квадратного атласа, px
	texture: string?, -- текстура кузова (nil = белый холст)
	zones: { [string]: Zone },
}

-- Багги: атлас 1024, капот/корма 80 px/stud, борта 60 (повёрнуты). Зона «left» —
-- U = высота, V = длина от кормы (ta = 0 у кормы); «right» зеркальна: ta = 0 у носа.
-- Корма — три грани (нижняя панель / уступ / верхняя), череп на нижней (tb ≈ 0.27).
-- Борт: нижняя панель между крыльями, ближе к заднему колесу (z ≈ −1.2 в кадре меша).
RankSkull.Bodies = {
	buggy = {
		atlas = 1024,
		texture = "rbxassetid://135253107984920",
		zones = {
			top   = { u0 = 0.015, v0 = 0.635, u1 = 0.376, v1 = 0.914, rotated = false, studsW = 4.63, studsH = 3.57, ta = 0.5,  tb = 0.5,  height = 3.0, flip = true },
			rear  = { u0 = 0.406, v0 = 0.635, u1 = 0.802, v1 = 0.846, rotated = false, studsW = 5.07, studsH = 2.70, ta = 0.5,  tb = 0.27, height = 1.25 },
			left  = { u0 = 0.635, v0 = 0.015, u1 = 0.794, v1 = 0.588, rotated = true,  studsW = 9.77, studsH = 2.71, ta = 0.37, tb = 0.26, height = 1.2 },
			right = { u0 = 0.824, v0 = 0.015, u1 = 0.982, v1 = 0.586, rotated = true,  studsW = 9.74, studsH = 2.70, ta = 0.63, tb = 0.26, height = 1.2 },
		},
	},
	-- Гроб: атлас 1024 в развёртке, холст берём 512 (текстуры нет, хватит). Крышка —
	-- V к носу (череп у носа, tb ≈ 0.68, там же стоял крест); борта: «left» ta = 0 у
	-- кормы, «right» — у носа; заднее колесо на ta ≈ 0.34 от кормы.
	coffin = {
		atlas = 512,
		texture = nil,
		zones = {
			top   = { u0 = 0.015, v0 = 0.585, u1 = 0.366, v1 = 0.942, rotated = false, studsW = 6.00, studsH = 6.10, ta = 0.5,  tb = 0.68, height = 2.8, flip = true },
			rear  = { u0 = 0.396, v0 = 0.585, u1 = 0.659, v1 = 0.784, rotated = false, studsW = 4.48, studsH = 3.40, ta = 0.5,  tb = 0.42, height = 2.2 },
			left  = { u0 = 0.585, v0 = 0.015, u1 = 0.758, v1 = 0.435, rotated = true,  studsW = 8.28, studsH = 3.40, ta = 0.30, tb = 0.45, height = 1.9 },
			right = { u0 = 0.788, v0 = 0.015, u1 = 0.960, v1 = 0.435, rotated = true,  studsW = 8.28, studsH = 3.40, ta = 0.70, tb = 0.45, height = 1.9 },
		},
	},
} :: { [string]: BodySpec }

RankSkull.Colors = {
	bone = Color3.fromRGB(224, 214, 170), -- UITheme.Palette.Bone
	gold = Color3.fromRGB(255, 210, 70), -- жёлтый «YOU WIN!» и контура черепов чекпоинтов
	-- Под Multiply светлая кость почти не читается (умножение только темнит): вариант
	-- потемнее, «старая кость», — на выбор юзера.
	oldbone = Color3.fromRGB(196, 176, 118),
} :: { [string]: Color3 }

-- // Растр черепа --------------------------------------------------------------
local MIN_Y, MAX_Y = math.huge, -math.huge
for _, loop in SkullOutline.Loops do
	for _, p in loop do
		MIN_Y = math.min(MIN_Y, p[2])
		MAX_Y = math.max(MAX_Y, p[2])
	end
end
local ASPECT = MAX_Y - MIN_Y -- высота на единицу ширины (~1.139)
local SUBROWS = 4 -- подстрок на пиксель: край гладкий, но без «свечения» — покрытие честное

local function spansAt(ny: number): { number }
	local xs = {}
	for _, loop in SkullOutline.Loops do
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

-- Покрытие черепа шириной w px (высота от пропорции): cov[j*w + i + 1], j = 0 — макушка.
local covCache: { [number]: { w: number, h: number, cov: { number } } } = {}
local function coverage(w: number): (number, number, { number })
	local ready = covCache[w]
	if ready then
		return ready.w, ready.h, ready.cov
	end
	local h = math.max(1, math.floor(w * ASPECT + 0.5))
	local cov = table.create(w * h, 0)
	local weight = 1 / SUBROWS
	for py = 0, h - 1 do
		for s = 0, SUBROWS - 1 do
			local ny = MAX_Y - ((py + (s + 0.5) / SUBROWS) / h) * ASPECT
			local xs = spansAt(ny)
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
	covCache[w] = { w = w, h = h, cov = cov }
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
}
RankSkull.Modes = BLEND

-- // Базовые холсты ------------------------------------------------------------
-- Пиксели текстуры кузова читаем один раз (CreateEditableImageAsync — сетевой вызов,
-- и только для ассетов создателя места; при отказе — nil, черепа не будет, кузов
-- останется как есть).
local baseCache: { [string]: { size: number, buf: buffer }? } = {}
local baseTried: { [string]: boolean } = {}

local function loadBase(bodyId: string): { size: number, buf: buffer }?
	if baseTried[bodyId] then
		return baseCache[bodyId]
	end
	baseTried[bodyId] = true
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
	return baseCache[bodyId]
end

-- // Композит ------------------------------------------------------------------
-- Рисует череп в одну зону прямо в buf (RGBA8, сторона size).
local function paintZone(buf: buffer, size: number, zone: Zone, color: Color3, mode: string, opacity: number)
	local blend = BLEND[mode] or BLEND.normal
	-- плотность px/stud одинакова по обеим осям зоны (так собран атлас)
	local pxPerStud = if zone.rotated then ((zone.u1 - zone.u0) * size) / zone.studsH else ((zone.u1 - zone.u0) * size) / zone.studsW
	local sh = math.max(4, math.floor(zone.height * pxPerStud + 0.5)) -- высота черепа, px
	local sw = math.max(4, math.floor(sh / ASPECT + 0.5))
	local w, h, cov = coverage(sw)
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
				local jj = if zone.flip then h - 1 - j else j -- flip: макушка к водителю, зубы к носу
				if zone.rotated then
					-- макушка (j = 0) смотрит в +U = +x
					x = math.floor(cx + (h / 2 - 1 - jj) + 0.5)
					y = math.floor(cy - w / 2 + i + 0.5)
				else
					x = math.floor(cx - w / 2 + i + 0.5)
					y = math.floor(cy - h / 2 + jj + 0.5)
				end
				if x >= 0 and y >= 0 and x < size and y < size then
					local o = (y * size + x) * 4
					local br, bg, bb = buffer.readu8(buf, o) / 255, buffer.readu8(buf, o + 1) / 255, buffer.readu8(buf, o + 2) / 255
					local rr = br + (blend(br, cr) - br) * a
					local rg = bg + (blend(bg, cg) - bg) * a
					local rb = bb + (blend(bb, cb) - bb) * a
					buffer.writeu8(buf, o, math.clamp(math.floor(rr * 255 + 0.5), 0, 255))
					buffer.writeu8(buf, o + 1, math.clamp(math.floor(rg * 255 + 0.5), 0, 255))
					buffer.writeu8(buf, o + 2, math.clamp(math.floor(rb * 255 + 0.5), 0, 255))
				end
			end
		end
	end
end

local imageCache: { [string]: EditableImage } = {}

-- Собрать текстуру кузова bodyId с черепами в зонах zoneNames. Кэш по ключу: одна
-- картинка на комбинацию, общая для всех машин. Йилдит на первом обращении к кузову
-- (чтение текстуры). nil — если кузов неизвестен или EditableImage недоступен.
--
-- tint — цвет краски (Color3 детали). ЛЮБАЯ текстура на MeshPart ОТКЛЮЧАЕТ Color3
-- (проверено 2026-09-11: красный Color на текстурированном багги и на гробе с белым
-- EditableImage — без следа краски). Поэтому у кузова БЕЗ текстуры (гроб) холст
-- заливаем цветом краски сами, иначе гроб с черепом становился белым. У
-- текстурированного багги краска и раньше цвет не давала (только материал), это
-- поведение не трогаем — холст без тонировки.
function RankSkull.compose(bodyId: string, zoneNames: { string }, colorName: string, mode: string, opacity: number, tint: Color3?): EditableImage?
	local spec = RankSkull.Bodies[bodyId]
	local color = RankSkull.Colors[colorName]
	if not (spec and color) or #zoneNames == 0 then
		return nil
	end
	local names = table.clone(zoneNames)
	table.sort(names)
	local canvas = if spec.texture then nil else (tint or Color3.new(1, 1, 1))
	local key = ("%s|%s|%s|%s|%.2f|%s"):format(bodyId, table.concat(names, ","), colorName, mode, opacity, canvas and canvas:ToHex() or "-")
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
	if canvas then
		-- холст в цвет краски (см. выше про Color3 и текстуры)
		local r, g, b = math.floor(canvas.R * 255 + 0.5), math.floor(canvas.G * 255 + 0.5), math.floor(canvas.B * 255 + 0.5)
		for i = 0, size * size - 1 do
			local o = i * 4
			buffer.writeu8(buf, o, r)
			buffer.writeu8(buf, o + 1, g)
			buffer.writeu8(buf, o + 2, b)
			buffer.writeu8(buf, o + 3, 255)
		end
	else
		buffer.copy(buf, 0, base.buf)
	end
	for _, name in names do
		local zone = spec.zones[name]
		if zone then
			paintZone(buf, size, zone, color, mode, opacity)
		end
	end
	local ok, img = pcall(function()
		local image = AssetService:CreateEditableImage({ Size = Vector2.new(size, size) })
		image:WritePixelsBuffer(Vector2.zero, Vector2.new(size, size), buf)
		return image
	end)
	if not ok or not img then
		warn("[RankSkull] EditableImage недоступен: " .. tostring(img))
		return nil
	end
	imageCache[key] = img
	return img
end

-- Надеть картинку на кузов (nil — вернуть штатную текстуру).
function RankSkull.apply(body: MeshPart, img: EditableImage?)
	if img then
		body.TextureContent = Content.fromObject(img)
	else
		local spec = RankSkull.Bodies[body:GetAttribute("BodyId") :: any]
		body.TextureContent = if spec and spec.texture then Content.fromAssetId(tonumber(spec.texture:match("%d+")) :: number) else Content.none
	end
end

return RankSkull
