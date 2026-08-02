--!strict
-- ModuleScript: ReplicatedStorage.SkullBadge
-- ЗНАЧОК-ЧЕРЕП ДЛЯ 2D-ИНТЕРФЕЙСА, СОБРАННЫЙ ИЗ НАСТОЯЩЕГО ВЕКТОРА ЮЗЕРА.
--
-- Берём те же контуры, что и объёмный череп чекпоинтов (ReplicatedStorage.SkullOutline,
-- вынуты из D:\VECTOR\skull.ai), и заливаем их построчно: строка значка = один Frame
-- на каждый отрезок, попавший внутрь силуэта. Правило чётности само делает глазницы
-- дырами — отдельно их вырезать не нужно.
--
-- ПОЧЕМУ НЕ КАРТИНКОЙ. Готовый ассет 79551611166203 в UI не грузится (IsLoaded
-- остаётся false даже после явного PreloadAsync), залить свой PNG нельзя — публикация
-- отвечает 401 «User is not authenticated», а EditableImage закрыт настройкой
-- Security в Experience Settings. Заливка примитивами ни от чего этого не зависит и
-- на 12–16 пикселях от растра неотличима.
--
-- Использование:
--   SkullBadge.build(handle, 12)             -- костяной череп по центру родителя
--   SkullBadge.build(handle, 12, someColor)  -- своим цветом

local SkullOutline = require(script.Parent:WaitForChild("SkullOutline"))

local SkullBadge = {}

local BONE = Color3.fromRGB(224, 214, 170)

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
-- Контуры разомкнуты (см. SkullOutline), поэтому последний отрезок замыкаем вручную.
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

-- Раскладка значка шириной w пикселей: список строк {y, x, длина} в пикселях.
-- Считается один раз на ширину — ползунков в панели несколько, а форма у всех одна.
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

-- Построить череп по центру parent. Возвращает контейнер (Frame с именем Skull).
function SkullBadge.build(parent: GuiObject, w: number, color: Color3?): Frame
	local h = math.max(1, math.floor(w * ASPECT + 0.5))
	local skull = Instance.new("Frame")
	skull.Name = "Skull"
	skull.BackgroundTransparency = 1
	skull.AnchorPoint = Vector2.new(0.5, 0.5)
	skull.Position = UDim2.fromScale(0.5, 0.5)
	skull.Size = UDim2.fromOffset(w, h)
	skull.ZIndex = (parent.ZIndex or 1) + 1
	skull.Parent = parent

	local tint = color or BONE
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
