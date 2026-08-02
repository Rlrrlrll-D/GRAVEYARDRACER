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
	-- Светло-зелёный. НЕ придуман здесь: этим цветом кнопка PLAY показывала готовность
	-- (LobbyUI), он же теперь работает во всём меню — плашка готового гонщика, включённый
	-- тумблер. Рядом с Green (тёмным) даёт пару «светлое действие / тёмный фон».
	GreenLight = Color3.fromRGB(52, 90, 64),
}
UITheme.Ink = Color3.fromRGB(224, 214, 170)  -- костяной текст по умолчанию (= Bone)
UITheme.Shadow = Color3.fromRGB(12, 19, 14)  -- тёмно-мховая обводка/подложка (был почти чёрный)
UITheme.PanelBg = Color3.fromRGB(22, 33, 27) -- тёмно-мховая база под панели

-- Порядок чередования: красный → тёмно-зелёный → кость, по кругу.
UITheme.Cycle = { UITheme.Palette.Red, UITheme.Palette.Green, UITheme.Palette.Bone }

-- Цвет для i-го элемента (1-based), циклически. Для «чередования цветов в UI».
function UITheme.cycleColor(i: number): Color3
	local c = UITheme.Cycle
	return c[((i - 1) % #c) + 1]
end

-- // Масштаб меню под окно ---------------------------------------------------
-- Заставка свёрстана в пикселях (тайтл 190, панели 470×580) под экран высотой
-- RefHeight. В окне ниже — маленькое окно Studio, ноутбучный экран — блоки лезут
-- друг на друга и обрезаются снизу. Один UIScale на корне переносит вёрстку
-- целиком, пропорции не плывут. Выше RefHeight не растягиваем: и так читается.
-- 700, а не 780: при 780 в невысоком окне всё ужималось до ~80% и меню читалось
-- мелким. Вёрстка помещается в 700 по высоте, поэтому запас там был лишний.
UITheme.RefHeight = 700

-- Повесить на контейнер UIScale и держать его в согласии с размером окна.
-- Контейнер должен быть рамкой во весь экран: UIScale множит и его самого,
-- поэтому размер тут же задаётся обратной величиной (1/s · s = 1) — иначе рамка
-- съёживается вместе с содержимым и всё, что привязано к её долям (кнопки по
-- центру, затемнение), уезжает в левый верхний угол.
function UITheme.fitToScreen(container: GuiObject): UIScale
	local scale = container:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Name = "FitScale"
	scale.Parent = container

	local function apply()
		local cam = workspace.CurrentCamera
		if cam then
			local s = math.clamp(cam.ViewportSize.Y / UITheme.RefHeight, 0.5, 1)
			scale.Scale = s
			container.Size = UDim2.fromScale(1 / s, 1 / s)
		end
	end

	local function watch()
		apply()
		local cam = workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(apply)
		end
	end

	watch()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watch)
	return scale
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
