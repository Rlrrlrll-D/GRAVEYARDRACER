--!strict
-- ModuleScript: ReplicatedStorage.SkullBadge
-- ЗНАЧОК-ЧЕРЕП ДЛЯ 2D-ИНТЕРФЕЙСА, СОБРАННЫЙ ИЗ НАСТОЯЩЕГО ВЕКТОРА ЮЗЕРА.
--
-- Контуры — те же, что у объёмного черепа чекпоинтов (ReplicatedStorage.SkullOutline,
-- вынуты из D:\VECTOR\skull.ai). Здесь они растеризуются в EditableImage со сглаживанием
-- и отдаются ImageLabel'у: одна картинка на всё меню, красится ImageColor3 под цвет
-- места (белая заливка + альфа по силуэту). Глазницы вырезает правило чётности.
--
-- ПОЧЕМУ РАСТР СТРОИМ САМИ, А НЕ БЕРЁМ АССЕТ. Готовый силуэт rbxassetid://79551611166203
-- в UI не грузится (IsLoaded остаётся false даже после явного PreloadAsync), а залить
-- свой PNG нельзя — публикация отвечает 401 «User is not authenticated». Растеризация
-- на месте ни от сети, ни от авторизации не зависит.
--
-- ЗАПАСНОЙ ПУТЬ. EditableImage закрыт настройкой Security в Experience Settings: если
-- её выключить, CreateEditableImage ещё создаётся, но первая же запись пикселей падает
-- с «EditableImage is not accessible». Тогда значок рисуется полосками-Frame по тем же
-- контурам — на 12 пикселях разница почти не видна, только край ступенькой.
--
-- Использование:
--   SkullBadge.build(handle, 12)             -- костяной череп по центру родителя
--   SkullBadge.build(handle, 12, someColor)  -- своим цветом

local AssetService = game:GetService("AssetService")

local SkullOutline = require(script.Parent:WaitForChild("SkullOutline"))

local SkullBadge = {}

local BONE = Color3.fromRGB(224, 214, 170)

-- Разрешение растра. Значок носят на 12–16 пикселях, но рисуем крупнее: движок сам
-- уменьшит с фильтрацией, и запаса хватит, если значок где-то понадобится больше.
local TEX_W = 64
local SUBROWS = 4 -- подстрок на пиксель: столько уровней сглаживания по вертикали

-- Габарит контуров в нормированных единицах: ширина ровно 1, высота считается.
local MIN_Y, MAX_Y = math.huge, -math.huge
for _, loop in SkullOutline.Loops do
	for _, p in loop do
		MIN_Y = math.min(MIN_Y, p[2])
		MAX_Y = math.max(MAX_Y, p[2])
	end
end
local ASPECT = MAX_Y - MIN_Y -- высота на единицу ширины (~1.139)

-- Отрезки строки: где горизонталь на высоте ny входит в силуэт и где выходит.
-- Контуры разомкнуты (см. SkullOutline), поэтому последнее ребро замыкаем сами.
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

-- // Растр --------------------------------------------------------------------
-- Покрытие пикселя копится честно: по вертикали — SUBROWS подстрок, по горизонтали —
-- доля пикселя, накрытая отрезком. Отсюда мягкий край без «лесенки».
local imageContent: Content? = nil
local imageTried = false

local function buildImage(): Content?
	local h = math.max(1, math.floor(TEX_W * ASPECT + 0.5))
	local cov = table.create(TEX_W * h, 0)
	local weight = 1 / SUBROWS

	for py = 0, h - 1 do
		for s = 0, SUBROWS - 1 do
			local ny = MAX_Y - ((py + (s + 0.5) / SUBROWS) / h) * ASPECT
			local xs = spansAt(ny)
			for i = 1, #xs - 1, 2 do
				local a = (xs[i] + 0.5) * TEX_W
				local b = (xs[i + 1] + 0.5) * TEX_W
				if b > a then
					local from = math.max(0, math.floor(a))
					local to = math.min(TEX_W - 1, math.ceil(b) - 1)
					for px = from, to do
						local l = math.max(a, px)
						local r = math.min(b, px + 1)
						if r > l then
							local idx = py * TEX_W + px + 1
							cov[idx] += (r - l) * weight
						end
					end
				end
			end
		end
	end

	local ok, image = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(TEX_W, h) })
	end)
	if not ok or not image then
		return nil
	end

	local buf = buffer.create(TEX_W * h * 4)
	for i = 1, TEX_W * h do
		local o = (i - 1) * 4
		buffer.writeu8(buf, o, 255) -- белый: цвет даёт ImageColor3
		buffer.writeu8(buf, o + 1, 255)
		buffer.writeu8(buf, o + 2, 255)
		buffer.writeu8(buf, o + 3, math.clamp(math.floor(cov[i] * 255 + 0.5), 0, 255))
	end

	local written = pcall(function()
		image:WritePixelsBuffer(Vector2.zero, Vector2.new(TEX_W, h), buf)
	end)
	if not written then
		-- Настройка Security выключена: картинку не отдаём, значок нарисуют полоски.
		return nil
	end
	return Content.fromObject(image)
end

local function getImage(): Content?
	if not imageTried then
		imageTried = true
		imageContent = buildImage()
	end
	return imageContent
end

-- // Запасная отрисовка полосками ---------------------------------------------
-- Раскладка значка шириной w: список строк {y, x, длина} в пикселях. Считается один
-- раз на ширину — ползунков в панели несколько, а форма у всех одна.
local cache: { [number]: { { number } } } = {}

local function layout(w: number): { { number } }
	local ready = cache[w]
	if ready then
		return ready
	end
	local rows = {}
	local h = math.max(1, math.floor(w * ASPECT + 0.5))
	for row = 0, h - 1 do
		-- центр строки: в UI ось Y вниз, в контурах — вверх, отсюда вычитание
		local ny = MAX_Y - ((row + 0.5) / h) * ASPECT
		local xs = spansAt(ny)
		for i = 1, #xs - 1, 2 do
			local x0 = (xs[i] + 0.5) * w
			local x1 = (xs[i + 1] + 0.5) * w
			if x1 - x0 >= 0.35 then -- тоньше трети пикселя рисовать нечем
				table.insert(rows, { row, x0, x1 - x0 })
			end
		end
	end
	cache[w] = rows
	return rows
end

-- Построить череп по центру parent. Возвращает созданный объект.
function SkullBadge.build(parent: GuiObject, w: number, color: Color3?): GuiObject
	local h = math.max(1, math.floor(w * ASPECT + 0.5))
	local tint = color or BONE
	local content = getImage()

	if content then
		local img = Instance.new("ImageLabel")
		img.Name = "Skull"
		img.BackgroundTransparency = 1
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.Size = UDim2.fromOffset(w, h)
		img.ImageContent = content
		img.ImageColor3 = tint
		img.ScaleType = Enum.ScaleType.Fit
		img.ZIndex = parent.ZIndex + 1
		img.Parent = parent
		return img
	end

	local skull = Instance.new("Frame")
	skull.Name = "Skull"
	skull.BackgroundTransparency = 1
	skull.AnchorPoint = Vector2.new(0.5, 0.5)
	skull.Position = UDim2.fromScale(0.5, 0.5)
	skull.Size = UDim2.fromOffset(w, h)
	skull.ZIndex = parent.ZIndex + 1
	skull.Parent = parent

	for _, r in layout(w) do
		local seg = Instance.new("Frame")
		seg.BackgroundColor3 = tint
		seg.BorderSizePixel = 0
		seg.Position = UDim2.fromOffset(r[2], r[1])
		seg.Size = UDim2.fromOffset(r[3], 1)
		seg.ZIndex = skull.ZIndex
		seg.Parent = skull
	end
	return skull
end

return SkullBadge
