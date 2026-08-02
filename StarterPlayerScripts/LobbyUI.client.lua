--!strict
-- LocalScript: StarterPlayerScripts.LobbyUI
-- ЗАСТАВКА + предстартовый экран (упрощённая модель «заставка → отсчёт → гонка»).
-- Показывается, пока игрок ВНЕ заезда: сразу при заходе и после каждого заезда.
-- Никаких платформ/диорам — просто затемнённый блюр-фон реального кладбища +
-- тайтл + кнопка PLAY (готовность) + статус + ростер. При старте заезда прячется
-- у участника (по Participant=true в персональном RaceUpdate), возвращается по
-- ReturnToLobby / фазе Idle. Пока показана — геймплейный HUD скрыт, фон заблюрен.
-- Кнопки PLAY и OPTIONS по центру; ростер RACERS слева, панель опций
-- (OptionsMenu.Panel) справа — симметрично. Тема — из UITheme.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local GameState = require(ReplicatedStorage:WaitForChild("GameState"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

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

-- виньетка сверху/снизу под тайтл и кнопки
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

-- Тайтл крупнее (просьба юзера): 120 -> 170 по высоте, поле по бокам уже, поэтому
-- при TextScaled буквы вырастают заметно. Верх подтянут, чтобы не уехать за виньетку.
local title = Instance.new("TextLabel")
title.Size = UDim2.new(0.96, 0, 0, 170)
-- Отступ сверху в ПИКСЕЛЯХ, а не в долях экрана: панели ставятся под тайтл, и при
-- доле низ тайтла ездил вместе с высотой окна — панели то отрывались, то налезали.
title.Position = UDim2.new(0.02, 0, 0, 44)
title.BackgroundTransparency = 1
title.Text = "GRAVEYARD RACER"
title.TextScaled = true
UITheme.applyText(title, { color = UITheme.Palette.Red }) -- тайтл красный (кровь)
title.TextStrokeTransparency = 0.2
title.Parent = root

-- Слоган «the dead don't brake» из-под тайтла УБРАН (просьба юзера). На его месте —
-- строка о числе подключившихся, которая раньше висела ниже меню (см. statusLabel).

-- вспомогательная кнопка-плашка меню (PLAY / OPTIONS) в общем стиле
local function makeButton(text: string, bg: Color3, yOffset: number, h: number): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 320, 0, h)
	b.Position = UDim2.new(0.5, -160, 0.56, yOffset)
	b.BackgroundColor3 = bg
	b.AutoButtonColor = true
	b.Text = text
	b.TextScaled = true
	UITheme.applyText(b)
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)
	local st = Instance.new("UIStroke")
	st.Color = UITheme.Shadow
	st.Thickness = 2
	st.Transparency = 0.3
	st.Parent = b
	b.Parent = root
	return b
end

-- // PLAY (= готовность; заезд стартует, когда готовых ≥ MinRacers) ------------
-- ГОТОВНОСТЬ ПОКАЗЫВАЕТ ЦВЕТ, А НЕ ГАЛОЧКА (просьба юзера): не готов — красная
-- плашка, готов — светло-зелёная. Галочка из текста убрана: цвет читается с одного
-- взгляда и через всю комнату, а «✓» приходилось выискивать.
local isReady = false
local playBtn = makeButton("PLAY", UITheme.Palette.Red, 0, 64)

-- // OPTIONS (открывает панель опций СЛЕВА — OptionsMenu.Panel) ----------------
-- Тёмно-зелёная из палитры (была почти чёрная 22,33,27): рядом со светло-зелёной
-- PLAY это читается как одна пара «светлое действие / тёмное второстепенное».
local optBtn = makeButton("OPTIONS", UITheme.Palette.Green, 74, 50)

-- Строка о числе подключившихся переехала ПОД ТАЙТЛ, на место убранного слогана.
local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(0.5, 0, 0, 44) -- уже тайтла: в узком окне не лезет на панели
statusLabel.Position = UDim2.new(0.25, 0, 0, 226) -- сразу под тайтлом (44 + 170 + зазор)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Press PLAY to race"
statusLabel.TextScaled = true
UITheme.applyText(statusLabel, { color = UITheme.Palette.Bone })
statusLabel.Parent = root

playBtn.Activated:Connect(function()
	isReady = not isReady
	playBtn.BackgroundColor3 = isReady and UITheme.Palette.GreenLight or UITheme.Palette.Red
	playBtn.TextColor3 = UITheme.Ink -- надпись всегда костяная: красная на зелёном сливалась
	playerReady:FireServer(isReady)
end)

-- панель опций живёт в отдельном ScreenGui (OptionsMenu); тумблим её Visible
local function optionsPanel(): GuiObject?
	local om = playerGui:FindFirstChild("OptionsMenu")
	local p = om and om:FindFirstChild("Panel", true) -- панель лежит внутри корня с UIScale
	return (p and p:IsA("GuiObject")) and (p :: GuiObject) or nil
end
optBtn.Activated:Connect(function()
	local p = optionsPanel()
	if p then
		p.Visible = not p.Visible
	end
end)

-- // Ростер: кто на сервере и кто готов ---------------------------------------
-- ПЕРЕЕХАЛ НАПРАВО И СПРЯТАН (просьба юзера): раньше висел слева всегда, теперь
-- открывается кнопкой RACERS из панели опций и появляется там, где прежде были
-- опции. Сами опции ушли налево, на его место. Размеры прежние — панели зеркальны.
local rosterPanel = Instance.new("Frame")
rosterPanel.Name = "Roster"
rosterPanel.Size = UDim2.new(0, 280, 0, 404)
rosterPanel.Position = UDim2.new(1, -308, 0, 240) -- под тайтлом, вровень с панелью опций
rosterPanel.Visible = false
rosterPanel.BackgroundColor3 = UITheme.PanelBg
rosterPanel.BackgroundTransparency = 0.2
rosterPanel.Parent = root
Instance.new("UICorner", rosterPanel).CornerRadius = UDim.new(0, 10)
local rosterEdge = Instance.new("UIStroke")
rosterEdge.Color = UITheme.Palette.Bone
rosterEdge.Transparency = 0.6
rosterEdge.Thickness = 2
rosterEdge.Parent = rosterPanel

local rosterTitle = Instance.new("TextLabel")
rosterTitle.Size = UDim2.new(1, 0, 0, 40)
rosterTitle.BackgroundTransparency = 1
rosterTitle.Text = "RACERS"
rosterTitle.TextScaled = true
UITheme.applyText(rosterTitle, { color = UITheme.Palette.Bone })
rosterTitle.Parent = rosterPanel

local rosterList = Instance.new("Frame")
rosterList.Size = UDim2.new(1, -16, 1, -48)
rosterList.Position = UDim2.fromOffset(8, 44)
rosterList.BackgroundTransparency = 1
rosterList.Parent = rosterPanel
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 4)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = rosterList

-- Цвета плашек, из которых набирается список.
local ROSTER_BG = { UITheme.Palette.Red, UITheme.Palette.Green, UITheme.Palette.Bone }

-- ЦВЕТ ТЕКСТА ВЫБИРАЕТ ЯРКОСТЬ ПЛАШКИ, А НЕ СМЫСЛ СТРОКИ. Пробовали иначе: на
-- красной плашке светло-зелёная надпись, на светло-зелёной — красная. Оба тона
-- тёмные (150,30,30 и 52,90,64), рядом друг с другом имя расплывалось в пятно.
-- Теперь на тёмных плашках надпись костяная, на костяной — тёмно-мховая, а
-- готовность по-прежнему читается ЦВЕТОМ ПЛАШКИ.
local function inkFor(bg: Color3): Color3
	local lum = 0.299 * bg.R + 0.587 * bg.G + 0.114 * bg.B
	return lum > 0.5 and UITheme.Shadow or UITheme.Ink
end

type RosterRow = { name: string, ready: boolean }
local function renderRoster(roster: { RosterRow })
	for _, c in rosterList:GetChildren() do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	local prevBg: Color3? = nil
	for i, row in roster do
		local l = Instance.new("TextLabel")
		l.LayoutOrder = i
		l.Size = UDim2.new(1, 0, 0, 30)

		local bg
		if row.ready then
			-- ГОТОВ: плашка светло-зелёная — тот же язык, что у нажатой PLAY
			bg = UITheme.Palette.GreenLight
		else
			-- ЦВЕТА НЕ ПОВТОРЯЮТСЯ ПОДРЯД. Прежний cycleColor(i) шёл строго по кругу,
			-- но соседние строки всё равно совпадали, когда часть из них перекрашивалась
			-- в «готов». Поэтому берём первый цвет цикла, отличный от предыдущей строки.
			for k = 0, #ROSTER_BG - 1 do
				local c = ROSTER_BG[((i - 1 + k) % #ROSTER_BG) + 1]
				if c ~= prevBg then
					bg = c
					break
				end
			end
			bg = bg or ROSTER_BG[1]
		end
		prevBg = bg

		l.BackgroundColor3 = bg
		l.BackgroundTransparency = 0.15
		l.TextColor3 = inkFor(bg)
		l.Font = UITheme.Font
		l.TextScaled = true
		l.Text = row.name -- готовность показывает ЦВЕТ, галочка убрана
		Instance.new("UICorner", l).CornerRadius = UDim.new(0, 6)
		l.Parent = rosterList
	end
end

lobbyState.OnClientEvent:Connect(function(state)
	if state.phase == GameState.Phase.Lobby then
		statusLabel.Text = string.format("Racers ready: %d / %d", state.ready or 0, state.needed or 1)
	elseif state.phase == GameState.Phase.Countdown or state.phase == GameState.Phase.Racing then
		statusLabel.Text = "Race in progress — PLAY for the next one"
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
		local p = optionsPanel()
		if p then
			p.Visible = false -- уходя в гонку, закрываем опции
		end
		rosterPanel.Visible = false -- и ростер, он теперь тоже открывается кнопкой
	end
end

-- Приход из мира после game over/финиша: заставка вместо экрана итога.
-- ИТОГ СЮДА НЕ ДУБЛИРУЕМ. Раньше строка под тайтлом писала «YOU WIN!»/«GAME OVER»,
-- но её через долю секунды затирал очередной LobbyState фазы Lobby на «Racers ready:
-- N / M» — итог мигал и пропадал. Результат и так показан во весь экран (MatchResult),
-- а эта строка — про набор в следующий заезд.
returnToLobby.OnClientEvent:Connect(function(_payload)
	isReady = false
	playBtn.Text = "PLAY"
	playBtn.BackgroundColor3 = UITheme.Palette.Red -- вернулись в лобби — снова «не готов»
	playBtn.TextColor3 = UITheme.Ink
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

setLobbyVisible(true)

-- HUD может появиться позже нас: дождавшись, приводим его в согласие с заставкой.
task.spawn(function()
	local g = playerGui:WaitForChild("GraveyardHUD", 30)
	if g and g:IsA("ScreenGui") then
		hudGui = g
		applyHud(root.Visible)
	end
end)
