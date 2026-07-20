--!strict
-- ModuleScript: ReplicatedStorage.UITheme
-- ЕДИНЫЙ источник шрифтов и цветов для всего интерфейса Graveyard Racer.
-- Задача: «крипи»-шрифт с победного экрана — везде; палитра чередует три
-- кладбищенских тона (кровь-красный / замшелый тёмно-зелёный / кость-жёлтый).
--
-- Использование:
--   local UITheme = require(ReplicatedStorage.UITheme)
--   UITheme.applyText(label)                       -- заголовок, костяной цвет
--   UITheme.applyText(speed, { numeric = true })   -- цифры (читаемый Bangers)
--   frame.BackgroundColor3 = UITheme.cycleColor(i)  -- чередование по индексу

local UITheme = {}

-- // Шрифты ------------------------------------------------------------------
-- Основной «ярмарочно-жуткий» шрифт — тот самый, что на "YOU WIN!". Теперь он
-- на ВСЕХ заголовках/баннерах/кнопках.
UITheme.Font = Enum.Font.Creepster
-- Creepster на мелком кегле (спидометр, таймер, циферки) нечитаем — для плотной
-- цифири держим запасной комиксный шрифт той же эстетики.
UITheme.FontNumeric = Enum.Font.Bangers

-- // Палитра «кладбище» ------------------------------------------------------
UITheme.Palette = {
	Red   = Color3.fromRGB(150, 30, 30),   -- кровь / опасность / здоровье
	Green = Color3.fromRGB(34, 64, 44),    -- замшелый тёмно-зелёный (фон панелей)
	Bone  = Color3.fromRGB(224, 214, 170), -- жёлтый ближе к кости (тёплый костяной)
}
UITheme.Ink = Color3.fromRGB(232, 226, 205)  -- костяной текст по умолчанию
UITheme.Shadow = Color3.fromRGB(12, 10, 9)   -- почти чёрная подложка/обводка
UITheme.PanelBg = Color3.fromRGB(18, 20, 17) -- тёмная база под панели

-- Порядок чередования: красный → тёмно-зелёный → кость, по кругу.
UITheme.Cycle = { UITheme.Palette.Red, UITheme.Palette.Green, UITheme.Palette.Bone }

-- Цвет для i-го элемента (1-based), циклически. Для «чередования цветов в UI».
function UITheme.cycleColor(i: number): Color3
	local c = UITheme.Cycle
	return c[((i - 1) % #c) + 1]
end

-- Применить тему к TextLabel/TextButton одним вызовом.
function UITheme.applyText(gui: TextLabel | TextButton, opts: { numeric: boolean?, color: Color3? }?)
	local o = opts or {}
	gui.Font = (o.numeric and UITheme.FontNumeric) or UITheme.Font
	gui.TextColor3 = o.color or UITheme.Ink
	gui.TextStrokeColor3 = UITheme.Shadow
	gui.TextStrokeTransparency = 0.4
end

return UITheme
