--!strict
-- LocalScript: ReplicatedFirst.LoadingScreen
-- ПЕРВОЕ, ЧТО ВИДИТ ИГРОК. До этого на месте заставки была стандартная крутилка
-- Roblox, а за ней — недособранный мир: карта строится и греется до 30 секунд
-- (замер `[DecorPreload] отрисовка трассы прогрета ... за 26.6с`), и всё это время
-- вход в игру выглядел как чужой лоадер и пустое кладбище.
--
-- ПОЧЕМУ ИМЕННО ReplicatedFirst. Только скрипты этой службы стартуют ДО того, как
-- реплицировался остальной DataModel, и только отсюда можно снять штатную заставку
-- (`RemoveDefaultLoadingScreen`). StarterPlayerScripts к этому моменту ещё не
-- существует — там живёт шторка прогрева (DecorPreload.WarmupCurtain), которая
-- подхватывает эстафету позже.
--
-- ПОЧЕМУ ЦВЕТА ПРОДУБЛИРОВАНЫ, А НЕ ВЗЯТЫ ИЗ UITheme. Смысл этого экрана — быть на
-- экране МГНОВЕННО, а `ReplicatedStorage:WaitForChild("UITheme")` в первый кадр
-- почти наверняка уступит поток: модуль ещё не приехал. Поэтому рисуем сразу
-- запасными значениями, а тему подтягиваем фоном и перекрашиваемся, когда она
-- появится, — так UITheme остаётся источником правды, но не задерживает показ.
--
-- СМЫКАНИЕ СО ШТОРКОЙ. Фон здесь тот же, что у WarmupCurtain (PanelBg, затемнённый
-- на 45%), поэтому переход «загрузка → меню» не мигает: под уходящим экраном лежит
-- ровно такая же заливка.

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- Снимаем штатную заставку ДО первого yield: после него она успевает мигнуть.
pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

-- LocalPlayer в ReplicatedFirst МОЖЕТ БЫТЬ ЕЩЁ NIL: скрипты этой службы стартуют
-- раньше, чем игрок появляется в Players, — на том и погорела первая сборка
-- (`player:WaitForChild` по nil, экран не рисовался вовсе, и в логе было тихо).
-- Ждать можно только ПОСЛЕ RemoveDefaultLoadingScreen: до него нельзя уступать поток.
local player = Players.LocalPlayer
while not player do
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
	player = Players.LocalPlayer
end

-- Запасная палитра = UITheme (PanelBg / Bone / Shadow / Red).
local BG = Color3.fromRGB(22, 33, 27):Lerp(Color3.new(0, 0, 0), 0.45)
local BONE = Color3.fromRGB(224, 214, 170)
local SHADOW = Color3.fromRGB(12, 19, 14)
local RED = Color3.fromRGB(150, 30, 30)

local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100 -- поверх всего: пока он висит, ничего другого показывать нельзя
gui.Parent = player:WaitForChild("PlayerGui")

local back = Instance.new("Frame")
back.Name = "Back"
back.Size = UDim2.fromScale(1, 1)
back.BackgroundColor3 = BG
back.BorderSizePixel = 0
back.Parent = gui

-- ТАЙТЛ ТОТ ЖЕ, ЧТО В МЕНЮ, И ЧИСЛА ТЕ ЖЕ. Экран загрузки уходит прямо в LobbyUI,
-- и если заглавие отличается кеглем или цветом, переход читается как подмена
-- картинки. Поэтому здесь буквально копия настроек LobbyUI: красный (кровь),
-- обводка 0.2, 55% ширины блока, но не выше отведённой полосы.
--
-- TextSize у Roblox упирается в 100 намертво: TextScaled пересчитывает кегль и
-- снова бьётся в тот же потолок, UITextSizeConstraint тоже обрезается до 100.
-- Крупнее делает ТОЛЬКО UIScale на самой надписи — так это и решено в LobbyUI.
local TITLE_SIZE = 100 -- потолок TextSize; крупнее делает уже UIScale
local TITLE_H = 300 -- полоса под тайтл
-- ЗДЕСЬ ЗАГЛАВИЕ КРУПНЕЕ, ЧЕМ В МЕНЮ, И ЭТО НАМЕРЕННО. В меню под ним ростер и три
-- плашки, поэтому там 0.55; на загрузке кроме него ничего нет, и юзер попросил
-- «увеличить вдвое». Ровно вдвое (1.1 ширины экрана) буквы не влезают — берём
-- максимум, который влезает с полем: 0.95 коробки ≈ 0.91 экрана, это ×1.75.
local TITLE_FILL = 0.95 -- какую долю ширины коробки занимают буквы

local titleBox = Instance.new("Frame")
titleBox.Name = "TitleBox"
titleBox.AnchorPoint = Vector2.new(0.5, 0.5)
titleBox.Position = UDim2.fromScale(0.5, 0.4)
titleBox.Size = UDim2.new(0.96, 0, 0, TITLE_H)
titleBox.BackgroundTransparency = 1
titleBox.Parent = back

local title = Instance.new("TextLabel")
title.Name = "Title"
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.5)
title.Size = UDim2.fromOffset(600, TITLE_SIZE) -- размер ДО множителя; ширина с запасом
title.BackgroundTransparency = 1
title.Font = Enum.Font.Creepster
title.TextScaled = false
title.TextSize = TITLE_SIZE
title.TextColor3 = RED -- тайтл красный (кровь), как в меню
title.TextStrokeColor3 = SHADOW
title.TextStrokeTransparency = 0.2
title.Text = "GRAVEYARD RACER"
title.Parent = titleBox

local titleZoom = Instance.new("UIScale")
titleZoom.Parent = title

local fitting = false -- замер с yield: второй заход посреди первого сорвёт обоих

-- ЗАМЕР ТОЛЬКО ПРИ ЕДИНИЧНОМ МНОЖИТЕЛЕ. TextBounds у надписи под UIScale приходит
-- УЖЕ УМНОЖЕННЫМ, поэтому мерить, не сбросив множитель, — значит гнать сам себя:
-- в первой сборке заглавие вырастало до 80% ширины вместо положенных 55%. Отсюда же
-- и task.wait(): бounds пересчитываются к следующему кадру, а не по присваиванию.
-- Один в один с LobbyUI — два заглавия обязаны совпадать до пикселя.
local function fitTitle()
	if fitting then
		return
	end
	fitting = true
	title.TextTransparency = 1 -- на кадр замера буквы прячем: иначе видно скачок
	titleZoom.Scale = 1
	task.wait()
	local w = title.TextBounds.X
	if w > 0 then
		local byWidth = (titleBox.AbsoluteSize.X * TITLE_FILL) / w
		-- Потолок по высоте нужен из-за крупного TITLE_FILL: на узком и низком
		-- экране (телефон в портрете) буквы, подогнанные по ширине, налезли бы на
		-- полосу прогресса. Держим их в трети высоты кадра.
		local maxH = math.min(TITLE_H, back.AbsoluteSize.Y * 0.3)
		titleZoom.Scale = math.clamp(math.min(byWidth, maxH / TITLE_SIZE), 0.3, 12)
	end
	title.TextTransparency = 0
	fitting = false
end

task.spawn(fitTitle)
titleBox:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	task.spawn(fitTitle)
end)

-- // Полоса прогресса --------------------------------------------------------
-- ЧТО ОНА ПОКАЗЫВАЕТ. Честного процента у загрузки Roblox нет: ContentProvider
-- знает только текущую длину очереди, а она то растёт (сервер досылает списки на
-- прогрев), то падает. Поэтому берём ДВА показания и всегда рисуем большее:
-- убывание очереди от её пика и просто время. Первое отражает настоящую работу,
-- второе не даёт полосе замереть, когда очередь пустует, а мир ещё не готов.
-- Полоса сразу под заглавием, а не у нижнего края (пробовал 0.8 — юзер вернул
-- обратно): весь блок читается одной группой, а низ кадра остаётся чистым. Ширина
-- долей экрана, не пикселями, — иначе на телефоне полоса занимает пол-экрана, а на
-- мониторе теряется.
local BAR_Y = 0.62
local BAR_H = 12

local barTrack = Instance.new("Frame")
barTrack.Name = "BarTrack"
barTrack.AnchorPoint = Vector2.new(0.5, 0.5)
barTrack.Position = UDim2.fromScale(0.5, BAR_Y)
barTrack.Size = UDim2.new(0.42, 0, 0, BAR_H)
barTrack.BackgroundColor3 = SHADOW
barTrack.BorderSizePixel = 0
barTrack.Parent = back

local trackStroke = Instance.new("UIStroke")
trackStroke.Color = BONE
trackStroke.Thickness = 1
trackStroke.Transparency = 0.55
trackStroke.Parent = barTrack

local barFill = Instance.new("Frame")
barFill.Name = "BarFill"
barFill.Size = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = RED
barFill.BorderSizePixel = 0
barFill.Parent = barTrack

local status = Instance.new("TextLabel")
status.Name = "Status"
status.AnchorPoint = Vector2.new(0.5, 0)
status.Position = UDim2.new(0.5, 0, BAR_Y, 26)
status.Size = UDim2.fromOffset(560, 30)
status.BackgroundTransparency = 1
status.Font = Enum.Font.Creepster -- шрифт в UI один (= UITheme.Font)
status.TextSize = 26
status.TextColor3 = BONE
status.TextStrokeColor3 = SHADOW
status.TextStrokeTransparency = 0.5
status.Text = "WAKING THE GRAVEYARD…"
status.Parent = back

-- Строки идут по мере готовности, а не по таймеру: игрок видит, что что-то
-- меняется, и это «что-то» привязано к настоящему прогрессу.
local PHRASES = {
	{ 0.00, "WAKING THE GRAVEYARD…" },
	{ 0.30, "RAISING THE DEAD…" },
	{ 0.60, "LIGHTING THE LANTERNS…" },
	{ 0.85, "FUELLING THE BUGGY…" },
	{ 1.00, "READY" },
}

-- Тему подтягиваем фоном: приедет — перекрасимся, не приедет — останемся на
-- запасных значениях, которые ей и равны.
task.spawn(function()
	local mod = ReplicatedStorage:WaitForChild("UITheme", 20)
	if not mod or not mod:IsA("ModuleScript") then
		return
	end
	local ok, theme = pcall(require, mod)
	if not ok or type(theme) ~= "table" then
		return
	end
	BG = theme.PanelBg:Lerp(Color3.new(0, 0, 0), 0.45)
	BONE = theme.Ink
	SHADOW = theme.Shadow
	RED = theme.Palette.Red
	back.BackgroundColor3 = BG
	title.Font = theme.Font
	title.TextColor3 = RED -- как в меню: заглавие кровью
	title.TextStrokeColor3 = SHADOW
	status.Font = theme.FontNumeric
	status.TextColor3 = BONE
	status.TextStrokeColor3 = SHADOW
	barTrack.BackgroundColor3 = SHADOW
	trackStroke.Color = BONE
	barFill.BackgroundColor3 = RED
	fitTitle()
end)

-- // Когда уходить -----------------------------------------------------------
-- Не «по таймеру» и не по одному game:IsLoaded: реплицированный DataModel ещё не
-- значит собранную карту. Ждём, пока StarterPlayerScripts доживут до своей шторки
-- (DecorPreload поднимает её и ставит атрибут) и соберётся меню — то есть пока
-- игроку не станет что нажимать. DEADLINE — страховка: экран поверх всего, и
-- зависнуть на нём насовсем нельзя ни при какой поломке.
local DEADLINE = 45
local RAMP = 18 -- сек, за которые «временная» половина полосы доходит до 0.9

local t0 = os.clock()
local peakQueue = 0

local function ready(): boolean
	if not game:IsLoaded() then
		return false
	end
	local pg = player:FindFirstChild("PlayerGui")
	if not pg or not pg:FindFirstChild("LobbyUI") then
		return false
	end
	-- шторка прогрева уже держит мир закрытым — можно передавать эстафету
	return player:GetAttribute("WarmupCurtain") ~= nil
end

local shown = 0
local conn: RBXScriptConnection
conn = RunService.PreRender:Connect(function()
	local elapsed = os.clock() - t0
	local q = ContentProvider.RequestQueueSize
	if q > peakQueue then
		peakQueue = q
	end
	local byQueue = if peakQueue > 0 then 1 - q / peakQueue else 0
	local byTime = math.min(elapsed / RAMP, 1) * 0.9
	local target = math.max(byQueue, byTime)

	local done = ready() or elapsed > DEADLINE
	if done then
		target = 1
	end
	-- Полоса только растёт (скачок назад читается как поломка) и ползёт к цели, а не
	-- прыгает: готовность приходит одним махом, и без сглаживания полоса дорисовывала
	-- бы последнюю треть мгновенно — глаз считывает это как «бар был декоративный».
	shown = math.max(shown, shown + (math.min(target, 1) - shown) * 0.16)
	barFill.Size = UDim2.new(shown, 0, 1, 0)

	for _, p in PHRASES do
		if shown >= (p[1] :: number) then
			status.Text = p[2] :: string
		end
	end

	if done and shown >= 0.995 then
		conn:Disconnect()
		task.spawn(function()
			local FADE = 0.5
			local f0 = os.clock()
			while os.clock() - f0 < FADE do
				local a = (os.clock() - f0) / FADE
				back.BackgroundTransparency = a
				title.TextTransparency = a
				title.TextStrokeTransparency = 0.35 + 0.65 * a
				status.TextTransparency = a
				status.TextStrokeTransparency = 0.5 + 0.5 * a
				barTrack.BackgroundTransparency = a
				barFill.BackgroundTransparency = a
				trackStroke.Transparency = 0.55 + 0.45 * a
				RunService.PreRender:Wait()
			end
			gui:Destroy()
		end)
	end
end)
