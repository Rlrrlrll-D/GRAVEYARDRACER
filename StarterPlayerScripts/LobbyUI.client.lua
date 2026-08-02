--!strict
-- LocalScript: StarterPlayerScripts.LobbyUI
-- ЗАСТАВКА + предстартовый экран (упрощённая модель «заставка → отсчёт → гонка»).
-- Показывается, пока игрок ВНЕ заезда: сразу при заходе и после каждого заезда.
-- Никаких платформ/диорам — просто затемнённый блюр-фон реального кладбища +
-- тайтл + столбик плашек-мазков (PLAY / OPTIONS / RACERS). При старте заезда
-- прячется у участника (по Participant=true в персональном RaceUpdate),
-- возвращается по ReturnToLobby / фазе Idle. Пока показана — геймплейный HUD
-- скрыт, фон заблюрен. Плашки и подложки — мазки кистью из PlateArt.
--
-- ОДНОВРЕМЕННО НА ЭКРАНЕ ЛИБО МЕНЮ, ЛИБО ОДНА ПАНЕЛЬ. Панели (ростер и опции)
-- открываются строго по центру, поэтому меню на время уходит — иначе они легли бы
-- поверх тайтла и плашек. Что именно открыто, хранит атрибут игрока LobbyPanel:
-- панель опций живёт в чужом ScreenGui (OptionsMenu), и атрибут — единственная
-- связь, которой не важен порядок запуска LocalScript'ов.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local GameState = require(ReplicatedStorage:WaitForChild("GameState"))
local PlateArt = require(ReplicatedStorage:WaitForChild("PlateArt"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Какая панель открыта: "" | "Options" | "Racers". Читают оба меню.
local PANEL_ATTR = "LobbyPanel"

-- // Блюр фона СРАЗУ — до ожидания Remotes (иначе фон мелькает незаблюренным) --
local BLUR = 10 -- мягкий, но фон читается
local blur = Instance.new("BlurEffect")
blur.Name = "MenuBlur"
blur.Size = BLUR
blur.Parent = Lighting

local playerReady = Net.get(Net.Events.PlayerReady)
local lobbyState = Net.get(Net.Events.LobbyState)
local returnToLobby = Net.get(Net.Events.ReturnToLobby)
local raceUpdate = Net.get(Net.Events.RaceUpdate)

-- // Каркас ------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "LobbyUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 10 -- поверх HUD
gui.Parent = playerGui

local root = Instance.new("Frame") -- затемняющая вуаль поверх блюра
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = UITheme.Shadow
root.BackgroundTransparency = 0.35
root.Visible = true
root.Parent = gui
UITheme.fitToScreen(root) -- вся вёрстка ниже — в пикселях, здесь она ужимается под окно

-- виньетка сверху/снизу под тайтл и плашки
local function shade(top: boolean)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = UITheme.Shadow
	f.BorderSizePixel = 0
	f.Size = UDim2.new(1, 0, 0.42, 0)
	f.Position = top and UDim2.new(0, 0, 0, 0) or UDim2.new(0, 0, 0.58, 0)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Transparency = if top
		then NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
		else NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.05) })
	g.Parent = f
	f.Parent = root
end
shade(true)
shade(false)

-- Всё меню целиком — в одном блоке: панели открываются по центру, и блок на это
-- время прячется одной строкой.
--
-- БЛОК ФИКСИРОВАННОЙ ВЫСОТЫ, ПРИБИТЫЙ К ЦЕНТРУ. Раньше тайтл отсчитывался от верха
-- в пикселях, а столбик плашек — от середины экрана долей: стоило вырастить тайтл,
-- и он въезжал в плашки. Теперь внутри блока всё в пикселях от его верха, а сам блок
-- ровно RefHeight высотой и центрирован — на любом экране пропорции те же.
local MENU_H = UITheme.RefHeight
local menuBlock = Instance.new("Frame")
menuBlock.Name = "Menu"
menuBlock.AnchorPoint = Vector2.new(0.5, 0.5)
menuBlock.Size = UDim2.new(1, 0, 0, MENU_H)
menuBlock.Position = UDim2.fromScale(0.5, 0.5)
menuBlock.BackgroundTransparency = 1
menuBlock.Parent = root

-- // Тайтл ------------------------------------------------------------------
-- ПОЧЕМУ НЕ TextScaled. TextSize в Roblox упирается в 100 — потолок самого движка,
-- и UITextSizeConstraint его не поднимает (MaxTextSize клампится в те же 100).
-- TextScaled при этом бесполезен вдвойне: он пересчитывает шрифт под коробку и
-- каждый раз снова упирается в потолок, поэтому сколько коробку ни увеличивай,
-- надпись остаётся одного размера — проверено замером, ровно 100 пикселей строки и
-- при коробке 240, и при 420. Растит буквы только UIScale на самой надписи.
--
-- Множитель не задан числом, а подбирается: тайтл занимает TITLE_FILL ширины блока,
-- но не выше отведённой ему полосы TITLE_H. Поэтому на широком коротком окне он не
-- лезет через весь экран, а на узком не съедает место под меню.
local TITLE_SIZE = 100 -- потолок TextSize; крупнее делает уже UIScale
local TITLE_H = 300 -- полоса под тайтл, единиц вёрстки
local TITLE_FILL = 0.55 -- какую долю ширины занимают буквы
local STATUS_GAP = 20 -- отбивка строки статуса от букв тайтла

local titleBox = Instance.new("Frame") -- полоса фиксированной высоты: вёрстка ниже от неё не зависит
titleBox.Name = "TitleBox"
titleBox.Size = UDim2.new(0.96, 0, 0, TITLE_H)
titleBox.Position = UDim2.new(0.02, 0, 0, 0)
titleBox.BackgroundTransparency = 1
titleBox.Parent = menuBlock

local title = Instance.new("TextLabel")
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.5)
title.Size = UDim2.fromOffset(600, TITLE_SIZE) -- размер ДО множителя; ширина с запасом
title.BackgroundTransparency = 1
title.Text = "GRAVEYARD RACER"
title.TextScaled = false
title.TextSize = TITLE_SIZE
UITheme.applyText(title, { color = UITheme.Palette.Red }) -- тайтл красный (кровь)
title.TextStrokeTransparency = 0.2
local titleZoom = Instance.new("UIScale")
titleZoom.Parent = title
title.Parent = titleBox

-- Строку статуса ставит тот же расчёт: её место зависит от того, насколько крупным
-- вышел тайтл. Объявлена заранее, создаётся ниже.
local statusLabel: TextLabel? = nil

-- Ширину букв при TextSize = 100 движок сообщает только после кадра отрисовки,
-- поэтому меряем на множителе 1 и на этот кадр прячем надпись — иначе она мигнёт
-- мелкой. Пересчитываем и при смене размера окна.
local function fitTitle()
	title.TextTransparency = 1
	titleZoom.Scale = 1
	task.wait()
	local w = title.TextBounds.X
	if w > 0 then
		local byWidth = (titleBox.AbsoluteSize.X * TITLE_FILL) / w
		titleZoom.Scale = math.clamp(math.min(byWidth, TITLE_H / TITLE_SIZE), 0.3, 12)
	end
	title.TextTransparency = 0

	-- ПОД САМИ БУКВЫ, А НЕ ПОД КОРОБКУ (просьба юзера). Надпись стоит по центру своей
	-- полосы, и низ строки — это ещё не низ букв: Creepster оставляет под выносные
	-- элементы около пятой части высоты. Отсюда поправка, иначе между тайтлом и
	-- строкой зияет провал в сотню пикселей.
	--
	-- Поправка неполная (0.1 вместо 0.2) плюс отбивка STATUS_GAP: вплотную под буквы
	-- строка прилипала к тайтлу и читалась его частью.
	local s = statusLabel
	if s then
		local lineH = TITLE_SIZE * titleZoom.Scale
		local lettersBottom = (TITLE_H + lineH) / 2 - lineH * 0.1 + STATUS_GAP
		s.Position = UDim2.new(0.22, 0, 0, math.floor(lettersBottom))
	end
end

-- Слоган «the dead don't brake» из-под тайтла УБРАН (просьба юзера). На его месте —
-- строка о числе подключившихся, которая раньше висела ниже меню.
local status = Instance.new("TextLabel")
status.Size = UDim2.new(0.56, 0, 0, 56) -- уже тайтла: в узком окне не лезет на панели
status.Position = UDim2.new(0.22, 0, 0, 250) -- уточнит fitTitle, когда померит тайтл
status.BackgroundTransparency = 1
status.Text = "Press PLAY to race"
status.TextScaled = true
UITheme.applyText(status, { color = UITheme.Palette.Bone })
status.Parent = menuBlock
statusLabel = status

-- Тайтл померить можно только после того, как он попал в отрисовку; заодно расчёт
-- поставит на место строку статуса.
task.spawn(fitTitle)
titleBox:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	task.spawn(fitTitle)
end)

-- // Столбик плашек-мазков ----------------------------------------------------
-- Номер плашки задаёт форму мазка (PlateArt чередует два мазка и два поворота),
-- поэтому три подряд не повторяются даже при одинаковом цвете.
-- y отсчитывается от верха блока меню, а не от середины экрана: столбик и тайтл
-- живут в одной системе координат и не могут разъехаться.
local function menuPlate(index: number, text: string, color: Color3, w: number, h: number, y: number): TextButton
	local b = PlateArt.button(index, color)
	b.AnchorPoint = Vector2.new(0.5, 0)
	b.Size = UDim2.fromOffset(w, h)
	b.Position = UDim2.new(0.5, 0, 0, y)
	PlateArt.caption(b, text)
	b.Parent = menuBlock
	return b
end

-- PLAY (= готовность; заезд стартует, когда готовых ≥ MinRacers).
-- ГОТОВНОСТЬ ПОКАЗЫВАЕТ ЦВЕТ, А НЕ ГАЛОЧКА (просьба юзера): не готов — красный
-- мазок, готов — светло-зелёный. Галочка убрана: цвет читается с одного взгляда.
local isReady = false
local playBtn = menuPlate(1, "PLAY", UITheme.Palette.Red, 500, 110, 356)

-- OPTIONS и RACERS — второстепенные действия, оба мшисто-зелёные. Красный в меню
-- один и означает «ещё не готов» (см. UITheme: красный в интерфейсе единственный).
local optBtn = menuPlate(2, "OPTIONS", UITheme.Palette.Green, 460, 94, 478)
local racersBtn = menuPlate(3, "RACERS", UITheme.Palette.Green, 460, 94, 584)

playBtn.Activated:Connect(function()
	isReady = not isReady
	PlateArt.tint(playBtn, isReady and UITheme.Palette.GreenLight or UITheme.Palette.Red)
	playerReady:FireServer(isReady)
end)

-- // Панель ростера -----------------------------------------------------------
-- СТРОГО ПО ЦЕНТРУ и без рамки (просьба юзера): обводка и скругление убраны, фон
-- панели теперь сплошная подложка-мазок. Размер тот же, что у панели опций, — они
-- сменяют друг друга на одном месте.
-- Панель крупная и с широкими полями (просьба юзера). Ширина растёт вместе с
-- полем, поэтому под содержимое остаётся даже больше прежнего: 620 − 2×110 = 400.
-- Поле 110, а не 70, потому что у подложки рваный край: сплошная краска начинается
-- только с ~140-го пикселя, и при меньшем поле строки садились на «волоски» кисти,
-- а глаз всё равно читал их как прижатые к краю.
local PANEL_W = 620
local PANEL_H = 580
local PAD = 110

local rosterPanel = Instance.new("Frame")
rosterPanel.Name = "Roster"
rosterPanel.Active = true -- перехватывает клики
rosterPanel.AnchorPoint = Vector2.new(0.5, 0.5)
rosterPanel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
rosterPanel.Position = UDim2.fromScale(0.5, 0.5)
rosterPanel.BackgroundTransparency = 1
rosterPanel.Visible = false
rosterPanel.Parent = root

local rosterBackdrop = PlateArt.backdrop(UITheme.PanelBg)
rosterBackdrop.Size = UDim2.fromScale(1, 1)
rosterBackdrop.ZIndex = 1
rosterBackdrop.Parent = rosterPanel

local rosterTitle = Instance.new("TextLabel")
rosterTitle.Size = UDim2.new(1, -2 * PAD, 0, 72) -- вровень с заголовком опций
rosterTitle.Position = UDim2.fromOffset(PAD, 16)
rosterTitle.BackgroundTransparency = 1
rosterTitle.Text = "RACERS"
rosterTitle.TextScaled = true
rosterTitle.ZIndex = 2
UITheme.applyText(rosterTitle, { color = UITheme.Palette.Bone })
rosterTitle.Parent = rosterPanel

local rosterList = Instance.new("Frame")
rosterList.Size = UDim2.new(1, -2 * PAD, 1, -230)
rosterList.Position = UDim2.fromOffset(PAD, 100)
rosterList.BackgroundTransparency = 1
rosterList.ZIndex = 2
rosterList.Parent = rosterPanel
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 10)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = rosterList

-- ЦВЕТ ПЛАШКИ ОЗНАЧАЕТ ТОЛЬКО ГОТОВНОСТЬ (просьба юзера): не готов — красный,
-- готов — светло-зелёный. Раньше неготовые перебирали три цвета (красный, мох,
-- кость), чтобы соседние строки не сливались, но из-за этого цвет ничего не сообщал:
-- красная и костяная плашки значили одно и то же. Теперь язык тот же, что у кнопки
-- PLAY, и красный в интерфейсе остаётся единственным — «ещё не готов».
local function inkFor(bg: Color3): Color3
	local lum = 0.299 * bg.R + 0.587 * bg.G + 0.114 * bg.B
	return lum > 0.5 and UITheme.Shadow or UITheme.Ink
end

type RosterRow = { name: string, ready: boolean }
local function renderRoster(roster: { RosterRow })
	for _, c in rosterList:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	for i, row in roster do
		-- готов — светло-зелёный (как нажатая PLAY), не готов — красный
		local bg = if row.ready then UITheme.Palette.GreenLight else UITheme.Palette.Red
		local plate = PlateArt.plate(i, bg)
		plate.LayoutOrder = i
		plate.Size = UDim2.new(1, 0, 0, 48)
		plate.ZIndex = 2
		-- готовность показывает ЦВЕТ мазка, галочка убрана
		PlateArt.caption(plate, row.name, inkFor(bg))
		plate.Parent = rosterList
	end
end

-- // Возврат в меню -----------------------------------------------------------
-- Обе панели закрываются одинаково: снимают атрибут, меню возвращается само.
local function closePanel()
	player:SetAttribute(PANEL_ATTR, "")
end

local rosterBackBtn = PlateArt.button(2, UITheme.Palette.Green)
rosterBackBtn.Name = "BackPlate"
rosterBackBtn.AnchorPoint = Vector2.new(0.5, 1)
rosterBackBtn.Size = UDim2.fromOffset(340, 76)
-- BACK поднят от нижнего края (просьба юзера): у самого низа он висел в пустоте,
-- оторванный от списка, да ещё вплотную к рваной кромке подложки.
rosterBackBtn.Position = UDim2.new(0.5, 0, 1, -58)
rosterBackBtn.ZIndex = 2
PlateArt.caption(rosterBackBtn, "BACK")
rosterBackBtn.Parent = rosterPanel
rosterBackBtn.Activated:Connect(closePanel)

optBtn.Activated:Connect(function()
	player:SetAttribute(PANEL_ATTR, "Options")
end)
racersBtn.Activated:Connect(function()
	player:SetAttribute(PANEL_ATTR, "Racers")
end)

-- Меню и панель — взаимоисключающие состояния одного экрана.
local function applyPanel()
	local which = player:GetAttribute(PANEL_ATTR)
	menuBlock.Visible = (which == nil or which == "")
	rosterPanel.Visible = (which == "Racers")
end
player:GetAttributeChangedSignal(PANEL_ATTR):Connect(applyPanel)

lobbyState.OnClientEvent:Connect(function(state)
	if state.phase == GameState.Phase.Lobby then
		status.Text = string.format("Racers ready: %d / %d", state.ready or 0, state.needed or 1)
	elseif state.phase == GameState.Phase.Countdown or state.phase == GameState.Phase.Racing then
		status.Text = "Race in progress — PLAY for the next one"
	end
	-- Results: свой текст не ставим — итог показывает полноэкранный MatchResult
	if type(state.roster) == "table" then
		renderRoster(state.roster)
	end
end)

-- // Показ/скрытие заставки ---------------------------------------------------
-- Пока заставка видна: блюр фона включён, геймплейный HUD скрыт.
--
-- HUD ЖДЁМ, А НЕ ИЩЕМ ОДНОРАЗОВО. Раньше тут стоял FindFirstChild, и первый же
-- вызов setLobbyVisible(true) на старте сессии мог не найти GraveyardHUD — порядок
-- запуска LocalScript'ов не определён, UIController мог ещё не создать свой
-- ScreenGui. Тогда HUD оставался включённым ПОВЕРХ заставки до ближайшего
-- Idle-апдейта с сервера. Теперь ссылку добываем ожиданием и, получив её,
-- досинхронизируем состояние — мигание HUD при заходе исчезает.
local hudGui: ScreenGui? = nil

-- Флаг ставит MatchResult, пока на экране итог заезда или режим зрителя. Без него
-- очередной RaceUpdate «Racing» (они идут каждые 0.4с и приходят ОТДЕЛЬНЫМ remote'ом,
-- то есть могут обогнать MatchResult) зажигал HUD прямо поверх «YOU WIN!».
local function applyHud(lobbyVisible: boolean)
	local g = hudGui
	if g and g.Parent then
		g.Enabled = not lobbyVisible and player:GetAttribute("MatchOverlay") ~= true
	end
end

-- Итог ушёл — вернуть HUD, если мы уже в гонке (заставки нет).
player:GetAttributeChangedSignal("MatchOverlay"):Connect(function()
	applyHud(root.Visible)
end)

local function setLobbyVisible(visible: boolean)
	root.Visible = visible
	blur.Size = visible and BLUR or 0
	applyHud(visible)
	if not visible then
		closePanel() -- уходя в гонку, закрываем открытую панель
	end
end

-- Приход из мира после game over/финиша: заставка вместо экрана итога.
-- ИТОГ СЮДА НЕ ДУБЛИРУЕМ. Раньше строка под тайтлом писала «YOU WIN!»/«GAME OVER»,
-- но её через долю секунды затирал очередной LobbyState фазы Lobby на «Racers ready:
-- N / M» — итог мигал и пропадал. Результат и так показан во весь экран (MatchResult),
-- а эта строка — про набор в следующий заезд.
returnToLobby.OnClientEvent:Connect(function(_payload)
	isReady = false
	PlateArt.tint(playBtn, UITheme.Palette.Red) -- вернулись в лобби — снова «не готов»
	setLobbyVisible(true) -- игрок гарантированно ВНЕ мира, снова у старта под заставкой
end)

-- Старт заезда: у УЧАСТНИКА (Participant=true) заставка прячется; фаза Idle —
-- показывается у всех.
raceUpdate.OnClientEvent:Connect(function(data)
	if data.Participant == true and (data.Phase == "Countdown" or data.Phase == "Racing") then
		setLobbyVisible(false)
	elseif data.Phase == "Idle" then
		setLobbyVisible(true)
	end
end)

closePanel()
applyPanel()
setLobbyVisible(true)

-- HUD может появиться позже нас: дождавшись, приводим его в согласие с заставкой.
task.spawn(function()
	local g = playerGui:WaitForChild("GraveyardHUD", 30)
	if g and g:IsA("ScreenGui") then
		hudGui = g
		applyHud(root.Visible)
	end
end)
