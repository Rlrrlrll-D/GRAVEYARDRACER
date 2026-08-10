-- LocalScript: StarterPlayerScripts.PhotoMode
-- ДЕВ-ИНСТРУМЕНТ ДЛЯ СЪЁМКИ КАДРОВ (тизеры, иконка, картинки на страницу опыта).
-- Игроку не достаётся: включается только в Studio (или для UserId из ALLOWED_USER_IDS).
--
-- ЗАЧЕМ. Ночное кладбище нормально выглядит только в Play (в Edit локальный свет не
-- рисуется), а в Play мешает всё сразу: HUD поверх кадра, камера привязана к машине,
-- зомби бегут, кто-нибудь доигрывает замах ровно в момент снимка. Этот режим убирает
-- всё лишнее и даёт выставить кадр руками.
--
-- КАК СНИМАТЬ. Сохранить картинку из кода нельзя: CaptureService:CaptureScreenshot
-- отдаёт только временный rbxtemp://, а SaveScreenshotCapture закрыт капабилити
-- RobloxScript. Поэтому затвор — штатная кнопка Studio (лента View → Screenshot),
-- она снимает ЧИСТЫЙ вьюпорт без панелей редактора. Порядок: выставил кадр → H
-- (прячет панель и сетку) → клик по кнопке Screenshot → клик в окно игры → H.
--
-- РАСКЛАДКА
--   F4            вход / выход
--   ПКМ + мышь    поворот камеры
--   W A S D       движение, Q / E — вниз / вверх
--   Shift / Ctrl  быстрее ×4 / медленнее ×4
--   колесо        базовая скорость полёта
--   Z / C         крен, X — сбросить крен
--   [ / ]         поле зрения (оно же ползунком)
--   T             автофокус по центру кадра
--   F             заморозка мира (машины, зомби) вкл/выкл
--   G             сетка третей
--   B             киношные полосы 2.39:1 (остаются в кадре, это не подсказка)
--   U             HUD игры в кадре / скрыт. Плашка Roblox и курсор гаснут в обоих
--                 случаях; кадр с HUD нужен витрине — он объясняет игру
--   H             спрятать/вернуть интерфейс режима ВМЕСТЕ С КУРСОРОМ (стрелку Roblox
--                 рисует внутри кадра, и кнопка Screenshot забирает её вместе со сценой)
--
-- Со встроенным фрикамом Studio (Shift+P) одновременно не работает — оба берут
-- камеру себе. Что-то одно.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- // Кому доступно -----------------------------------------------------------
-- Пусто = только Studio. Захочется снимать в живой игре (там картинка чище: нет
-- накладных расходов редактора) — вписать сюда свой UserId, это единственная правка.
-- 8110001559 — владелец места. Нужен, чтобы снимать превью В НАСТОЯЩЕМ КЛИЕНТЕ, а не
-- только в Studio: там F11 даёт полный экран без ленты редактора, и не нужна возня с
-- размером окна ради разрешения (см. tools/photo-window.ps1). Остальным игрокам режим
-- по-прежнему недоступен: список сверяется с UserId, подделать его с клиента нельзя.
local ALLOWED_USER_IDS: { number } = { 8110001559 }

local function isAllowed(): boolean
	if RunService:IsStudio() then
		return true
	end
	for _, id in ALLOWED_USER_IDS do
		if id == player.UserId then
			return true
		end
	end
	return false
end

if not isAllowed() then
	return
end

-- // Настройки ---------------------------------------------------------------
local TOGGLE_KEY = Enum.KeyCode.F4
local LOOK_SENSITIVITY = 0.0032
local MOVE_SMOOTH = 12 -- чем меньше, тем «тяжелее» камера (кинематографичнее)
local LOOK_SMOOTH = 26
local ROLL_SPEED = 0.7 -- рад/с
local FONT = Enum.Font.Code -- дев-панель: читаемость важнее темы, цифры мелкие

-- // Состояние ---------------------------------------------------------------
local active = false
local camera = workspace.CurrentCamera

local pos = Vector3.zero
local yaw, pitch, roll = 0, 0, 0
local targetYaw, targetPitch = 0, 0
local velocity = Vector3.zero
local flySpeed = 40
local fov = 70

local freezeOn = true
local dof: DepthOfFieldEffect? = nil

-- НАШ HUD В КАДРЕ ИЛИ НЕТ (переключатель U, живёт между заходами в режим).
-- По умолчанию режим прячет весь интерфейс — так снимают чистую сцену. Но для витрины
-- опыта нужен и обратный кадр: HUD с «LAP 1/3 · POSITION 1/1», жизнями и счётчиком
-- зомби объясняет игру лучше любого пейзажа. Плашка Roblox и курсор при этом гаснут
-- ВСЕГДА — они не наши и в снимке не нужны ни в одном из режимов.
local keepGameUi = false

-- // Ремоут заморозки --------------------------------------------------------
-- Его создаёт PhotoModeService и ТОЛЬКО в Studio — в живой игре ремоута нет, и
-- заморозка просто недоступна. Ждём коротко, без него режим всё равно рабочий.
local freezeRemote: RemoteEvent? = nil
task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 20)
	if remotes then
		local r = remotes:WaitForChild("PhotoFreeze", 20)
		if r and r:IsA("RemoteEvent") then
			freezeRemote = r
		end
	end
end)

-- // Интерфейс ---------------------------------------------------------------
-- ДВА ScreenGui, а не один, из-за смещения топбара. Направляющие обязаны совпадать
-- с настоящими границами картинки, поэтому им IgnoreGuiInset = true. А панель ловит
-- мышь: у ползунков AbsolutePosition должен считаться в той же системе координат,
-- что и input.Position, — то есть БЕЗ инсета. В одном ScreenGui это не совмещается.
local overlayGui = Instance.new("ScreenGui")
overlayGui.Name = "PhotoModeOverlay"
overlayGui.ResetOnSpawn = false
overlayGui.IgnoreGuiInset = true
overlayGui.DisplayOrder = 1000
overlayGui.Enabled = false
overlayGui.Parent = playerGui

local panelGui = Instance.new("ScreenGui")
panelGui.Name = "PhotoModePanel"
panelGui.ResetOnSpawn = false
panelGui.IgnoreGuiInset = false
panelGui.DisplayOrder = 1001
panelGui.Enabled = false
panelGui.Parent = playerGui

-- --- сетка третей ---
local guides = Instance.new("Frame")
guides.Name = "Guides"
guides.Size = UDim2.fromScale(1, 1)
guides.BackgroundTransparency = 1
guides.Visible = false
guides.Parent = overlayGui

local function guideLine(horizontal: boolean, at: number)
	local line = Instance.new("Frame")
	line.BorderSizePixel = 0
	line.BackgroundColor3 = Color3.new(1, 1, 1)
	line.BackgroundTransparency = 0.75
	if horizontal then
		line.Size = UDim2.new(1, 0, 0, 1)
		line.Position = UDim2.fromScale(0, at)
	else
		line.Size = UDim2.new(0, 1, 1, 0)
		line.Position = UDim2.fromScale(at, 0)
	end
	line.Parent = guides
end

guideLine(false, 1 / 3)
guideLine(false, 2 / 3)
guideLine(true, 1 / 3)
guideLine(true, 2 / 3)

-- Сетка помнит СВОЁ состояние отдельно от видимости панели: иначе «спрятал H —
-- вернул H» гасило её насовсем, и её приходилось каждый раз включать заново.
local guidesOn = false
local function applyGuides()
	guides.Visible = guidesOn and panelGui.Enabled
end

-- --- киношные полосы ---
-- Их H НЕ прячет: это не подсказка, а часть композиции — они должны попасть в снимок.
local LETTERBOX_RATIO = 2.39
local barTop = Instance.new("Frame")
barTop.Name = "LetterboxTop"
barTop.BackgroundColor3 = Color3.new(0, 0, 0)
barTop.BorderSizePixel = 0
barTop.Size = UDim2.new(1, 0, 0, 0)
barTop.Visible = false
barTop.Parent = overlayGui

local barBottom = barTop:Clone()
barBottom.Name = "LetterboxBottom"
barBottom.AnchorPoint = Vector2.new(0, 1)
barBottom.Position = UDim2.fromScale(0, 1)
barBottom.Parent = overlayGui

local letterboxOn = false
local function layoutLetterbox()
	local vp = camera.ViewportSize
	local barHeight = math.max(0, (vp.Y - vp.X / LETTERBOX_RATIO) * 0.5)
	barTop.Size = UDim2.new(1, 0, 0, barHeight)
	barBottom.Size = UDim2.new(1, 0, 0, barHeight)
end

-- --- панель ---
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0, 1)
panel.Position = UDim2.new(0, 16, 1, -16)
panel.Size = UDim2.fromOffset(292, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundColor3 = UITheme.PanelBg
panel.BackgroundTransparency = 0.15
panel.BorderSizePixel = 0
panel.Parent = panelGui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 12)
pad.PaddingBottom = UDim.new(0, 12)
pad.PaddingLeft = UDim.new(0, 14)
pad.PaddingRight = UDim.new(0, 14)
pad.Parent = panel

local list = Instance.new("UIListLayout")
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Padding = UDim.new(0, 8)
list.Parent = panel

local function makeLabel(order: number, height: number, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, height)
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.TextSize = size
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Text = ""
	label.Parent = panel
	return label
end

local titleLabel = makeLabel(1, 18, 16, UITheme.Palette.Bone)
titleLabel.Text = "PHOTO MODE"

local statusLabel = makeLabel(2, 46, 13, UITheme.Palette.Bone)
statusLabel.TextTransparency = 0.25

-- Ползунок. Возвращает функцию обновления — цифры на панели меняются и с клавиш.
local sliderRefreshers: { () -> () } = {}

local function makeSlider(order: number, name: string, minV: number, maxV: number, get: () -> number, set: (number) -> (), format: (number) -> string)
	local row = Instance.new("Frame")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 32)
	row.BackgroundTransparency = 1
	row.Parent = panel

	local caption = Instance.new("TextLabel")
	caption.Size = UDim2.new(1, 0, 0, 14)
	caption.BackgroundTransparency = 1
	caption.Font = FONT
	caption.TextSize = 13
	caption.TextColor3 = UITheme.Palette.Bone
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.Parent = row

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, 0, 0, 6)
	track.Position = UDim2.new(0, 0, 0, 20)
	track.BackgroundColor3 = UITheme.Shadow
	track.BorderSizePixel = 0
	track.Parent = row
	Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = UITheme.Palette.GreenLight
	fill.BorderSizePixel = 0
	fill.Parent = track
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(12, 12)
	knob.Position = UDim2.fromScale(0, 0.5)
	knob.BackgroundColor3 = UITheme.Palette.Bone
	knob.BorderSizePixel = 0
	knob.ZIndex = 2
	knob.Parent = track
	Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

	local function refresh()
		local alpha = math.clamp((get() - minV) / (maxV - minV), 0, 1)
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.new(alpha, 0, 0.5, 0)
		caption.Text = string.format("%-14s %s", name, format(get()))
	end
	table.insert(sliderRefreshers, refresh)

	-- Зона захвата на всю строку: 6-пиксельную полоску мышью не поймать.
	local hit = Instance.new("TextButton")
	hit.Size = UDim2.fromScale(1, 1)
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Text = ""
	hit.Parent = row

	local dragging = false
	local function setFromX(x: number)
		local width = math.max(track.AbsoluteSize.X, 1)
		local alpha = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
		set(minV + alpha * (maxV - minV))
		refresh()
	end

	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)

	refresh()
end

local function metres(v: number): string
	return string.format("%.0f", v)
end

makeSlider(3, "Поле зрения", 15, 120, function()
	return fov
end, function(v)
	fov = v
end, function(v)
	return string.format("%.0f°", v)
end)

makeSlider(4, "Фокус", 5, 400, function()
	return dof and dof.FocusDistance or 60
end, function(v)
	if dof then
		dof.FocusDistance = v
	end
end, metres)

makeSlider(5, "Резкая зона", 0, 120, function()
	return dof and dof.InFocusRadius or 25
end, function(v)
	if dof then
		dof.InFocusRadius = v
	end
end, metres)

makeSlider(6, "Размытие", 0, 1, function()
	return dof and dof.FarIntensity or 0
end, function(v)
	if dof then
		dof.FarIntensity = v
		dof.NearIntensity = v * 0.6 -- передний план мылим слабее: иначе каша у нижнего края
	end
end, function(v)
	return string.format("%.2f", v)
end)

local hintsLabel = makeLabel(7, 134, 12, UITheme.Palette.Bone)
hintsLabel.TextTransparency = 0.45
hintsLabel.LayoutOrder = 7
hintsLabel.Text = table.concat({
	"ПКМ+мышь — поворот · WASD/QE — полёт",
	"Shift/Ctrl — быстрее/медленнее · колесо — скорость",
	"Z/C — крен, X — сброс · [ ] — поле зрения",
	"T — автофокус · F — заморозка · G — сетка",
	"B — киношные полосы · U — HUD игры в кадре",
	"H — спрятать панель и курсор",
	"",
	"Снимок: H → лента View → Screenshot",
}, "\n")

local function refreshPanel()
	statusLabel.Text = string.format(
		"Заморозка: %s%s\nHUD игры: %s\nСкорость полёта: %.0f",
		freezeOn and "ВКЛ" or "выкл",
		freezeRemote and "" or "  (нет сервера)",
		keepGameUi and "В КАДРЕ" or "скрыт",
		flySpeed
	)
	for _, refresh in sliderRefreshers do
		refresh()
	end
end

-- // Подавление чужого интерфейса --------------------------------------------
-- ОДНОГО Enabled = false НЕ ХВАТАЕТ. RaceUpdate прилетает каждые 0.4 с, и LobbyUI по
-- нему сам зажигает HUD — тот проступил бы прямо в кадре. Поэтому на каждый чужой
-- ScreenGui вешаем сторожа и запоминаем, каким его хотели видеть: на выходе вернём
-- ровно то состояние, до которого мир дошёл без нас.
type Suppressed = { wanted: boolean, conn: RBXScriptConnection }
local suppressed: { [LayerCollector]: Suppressed } = {}
local guiConns: { RBXScriptConnection } = {}

local function suppressGui(gui: Instance)
	if not gui:IsA("LayerCollector") then
		return
	end
	local lc = gui :: LayerCollector
	if lc == overlayGui or lc == panelGui or suppressed[lc] then
		return
	end

	local record = { wanted = lc.Enabled } :: any
	-- РЕАГИРУЕМ ТОЛЬКО НА ВКЛЮЧЕНИЕ. Отличить своё гашение от чужого флагом «сейчас
	-- пишем мы» нельзя: сигналы свойств отложенные (SignalBehavior.Deferred), обработчик
	-- приходит уже после того, как флаг снят, — и сторож записывал наш собственный
	-- false как исходное состояние, а на выходе гасил заставку насовсем.
	-- Поэтому false игнорируем целиком, а true — это заведомо чужое намерение.
	record.conn = lc:GetPropertyChangedSignal("Enabled"):Connect(function()
		if lc.Enabled then
			record.wanted = true
			lc.Enabled = false
		end
	end)
	lc.Enabled = false
	suppressed[lc] = record
end

local function restoreGuis()
	for lc, record in suppressed do
		record.conn:Disconnect()
		if lc.Parent then
			lc.Enabled = record.wanted
		end
	end
	table.clear(suppressed)
end

-- Привести наш интерфейс в согласие с переключателем U. Вызывается и на входе в режим,
-- и по нажатию — поэтому обе ветки обязаны быть полными, а не «доделывать» друг друга.
local function applyGameUi()
	if keepGameUi then
		for _, conn in guiConns do
			conn:Disconnect()
		end
		table.clear(guiConns)
		restoreGuis() -- вернуть каждому ScreenGui то состояние, до которого дошла игра
	else
		for _, gui in playerGui:GetChildren() do
			suppressGui(gui)
		end
		-- HUD может появиться уже после входа в режим (UIController создаёт его не
		-- мгновенно, а лобби пересоздаёт экраны между заездами) — ловим и таких.
		table.insert(guiConns, playerGui.ChildAdded:Connect(suppressGui))
	end
end

-- Блюр заставки живёт в Lighting и HUD-ом не выключается: войдя в режим из лобби,
-- мы получили бы размытый кадр целиком.
local blurStates: { [BlurEffect]: { size: number, conn: RBXScriptConnection } } = {}

local function suppressBlur()
	for _, inst in Lighting:GetDescendants() do
		if inst:IsA("BlurEffect") then
			local blur = inst :: BlurEffect
			local record = { size = blur.Size } :: any
			-- Ноль игнорируем по той же причине, что и Enabled = false выше.
			record.conn = blur:GetPropertyChangedSignal("Size"):Connect(function()
				if blur.Size > 0 then
					record.size = blur.Size
					blur.Size = 0
				end
			end)
			blur.Size = 0
			blurStates[blur] = record
		end
	end
end

local function restoreBlur()
	for blur, record in blurStates do
		record.conn:Disconnect()
		if blur.Parent then
			blur.Size = record.size
		end
	end
	table.clear(blurStates)
end

-- Имена и полоски здоровья над головами — тоже мусор в кадре. Правка клиентская,
-- на сервер не уезжает.
local humanoidStates: { [Humanoid]: Enum.HumanoidDisplayDistanceType } = {}

local function hideNametags()
	for _, inst in workspace:GetDescendants() do
		if inst:IsA("Humanoid") then
			local hum = inst :: Humanoid
			humanoidStates[hum] = hum.DisplayDistanceType
			hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end
end

local function restoreNametags()
	for hum, distanceType in humanoidStates do
		if hum.Parent then
			hum.DisplayDistanceType = distanceType
		end
	end
	table.clear(humanoidStates)
end

-- CoreGui: запоминаем каждый тип отдельно — что-то из него мог выключить и не мы.
--
-- ЗАПОМНИТЬ И ПРИМЕНИТЬ — РАЗНЫЕ ДЕЙСТВИЯ. Гасить приходится не один раз за сеанс
-- (плашку Roblox возвращает всё, что трогает интерфейс между F4 и снимком), а слепок
-- исходного состояния снимать можно только ОДИН раз: второй проход записал бы уже
-- выключенное как «так и было», и на выходе из режима CoreGui остался бы погашен.
local coreGuiStates: { [Enum.CoreGuiType]: boolean } = {}
local coreGuiSaved = false

local function hideCoreGui()
	if not coreGuiSaved then
		for _, coreType in Enum.CoreGuiType:GetEnumItems() do
			if coreType ~= Enum.CoreGuiType.All then
				coreGuiStates[coreType] = StarterGui:GetCoreGuiEnabled(coreType)
			end
		end
		coreGuiSaved = true
	end
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
	pcall(function()
		StarterGui:SetCore("TopbarEnabled", false)
	end)
end

local function restoreCoreGui()
	for coreType, enabled in coreGuiStates do
		StarterGui:SetCoreGuiEnabled(coreType, enabled)
	end
	table.clear(coreGuiStates)
	coreGuiSaved = false
	pcall(function()
		StarterGui:SetCore("TopbarEnabled", true)
	end)
end

-- // Управление персонажем ---------------------------------------------------
local controls: any = nil
local function setCharacterControls(enabled: boolean)
	if not controls then
		local ok, module = pcall(function()
			return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")) :: any
		end)
		if not ok then
			return
		end
		local gotControls, result = pcall(function()
			return module:GetControls()
		end)
		if not gotControls then
			return
		end
		controls = result
	end
	pcall(function()
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end)
end

-- // Камера ------------------------------------------------------------------
local prevCameraType = Enum.CameraType.Custom
local prevCameraSubject: Instance? = nil
local prevFov = 70
local bound = false
local looking = false

-- // Курсор -------------------------------------------------------------------
-- КУРСОР ПОПАДАЕТ В СНИМОК: Roblox рисует его сам, внутри кадра, поэтому кнопка
-- Screenshot забирает его вместе со сценой. Прятать стрелку только на время поворота
-- камеры (пока зажата ПКМ) оказалось мало — по сценарию съёмки ПКМ как раз отпущена:
-- кадр выставлен, панель убрана по H, и мышь едет к кнопке в ленте ровно поверх кадра.
-- Правило: стрелка нужна только тогда, когда видна панель — по ней возят ползунки.
local function applyCursor()
	if not active then
		UserInputService.MouseIconEnabled = true
		return
	end
	UserInputService.MouseIconEnabled = panelGui.Enabled and not looking
end

local function step(dt: number)
	-- A-Chassis каждый кадр возвращает камеру себе — переспрашиваем режим, иначе
	-- нас выбьет обратно за руль на первом же кадре.
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	local down = function(key: Enum.KeyCode)
		return UserInputService:IsKeyDown(key)
	end

	local moveX = (down(Enum.KeyCode.D) and 1 or 0) - (down(Enum.KeyCode.A) and 1 or 0)
	local moveZ = (down(Enum.KeyCode.S) and 1 or 0) - (down(Enum.KeyCode.W) and 1 or 0)
	local moveY = (down(Enum.KeyCode.E) and 1 or 0) - (down(Enum.KeyCode.Q) and 1 or 0)

	local multiplier = 1
	if down(Enum.KeyCode.LeftShift) or down(Enum.KeyCode.RightShift) then
		multiplier = 4
	elseif down(Enum.KeyCode.LeftControl) or down(Enum.KeyCode.RightControl) then
		multiplier = 0.25
	end

	if down(Enum.KeyCode.Z) then
		roll += ROLL_SPEED * dt
	elseif down(Enum.KeyCode.C) then
		roll -= ROLL_SPEED * dt
	end

	-- Углы догоняют цель по экспоненте: мышь остаётся отзывчивой, но рывок кисти не
	-- превращается в дёрганый кадр.
	local lookAlpha = 1 - math.exp(-dt * LOOK_SMOOTH)
	yaw += (targetYaw - yaw) * lookAlpha
	pitch += (targetPitch - pitch) * lookAlpha

	-- Базис движения БЕЗ крена: наклонили горизонт — «вперёд» не должно уезжать вбок.
	local moveBasis = CFrame.fromOrientation(pitch, yaw, 0)
	local wish = moveBasis:VectorToWorldSpace(Vector3.new(moveX, 0, moveZ))
	if wish.Magnitude > 0 then
		wish = wish.Unit
	end
	wish += Vector3.new(0, moveY, 0) -- вверх/вниз всегда по миру, не по взгляду

	local moveAlpha = 1 - math.exp(-dt * MOVE_SMOOTH)
	velocity = velocity:Lerp(wish * flySpeed * multiplier, moveAlpha)
	pos += velocity * dt

	camera.CFrame = CFrame.new(pos) * CFrame.fromOrientation(pitch, yaw, roll)
	camera.FieldOfView = fov
end

-- // Автофокус ---------------------------------------------------------------
local function autoFocus()
	if not dof then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	local hit = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * 1000, params)
	local distance = hit and (hit.Position - camera.CFrame.Position).Magnitude or 200
	dof.FocusDistance = math.clamp(distance, 5, 400)
	dof.InFocusRadius = math.max(8, distance * 0.25)
	if dof.FarIntensity <= 0 then
		dof.FarIntensity = 0.6 -- фокус без размытия бессмыслен: включаем, раз просили
		dof.NearIntensity = 0.36
	end
	refreshPanel()
end

-- // Заморозка ---------------------------------------------------------------
local function sendFreeze(on: boolean)
	local remote = freezeRemote
	if remote then
		remote:FireServer(on)
	end
end

-- // Вход / выход ------------------------------------------------------------
local function enter()
	camera = workspace.CurrentCamera

	prevCameraType = camera.CameraType
	prevCameraSubject = camera.CameraSubject
	prevFov = camera.FieldOfView

	pos = camera.CFrame.Position
	local rx, ry, rz = camera.CFrame:ToOrientation()
	pitch, yaw, roll = rx, ry, rz
	targetPitch, targetYaw = rx, ry
	velocity = Vector3.zero
	fov = camera.FieldOfView

	camera.CameraType = Enum.CameraType.Scriptable

	dof = Instance.new("DepthOfFieldEffect")
	dof.Name = "PhotoModeDOF"
	dof.FocusDistance = 60
	dof.InFocusRadius = 25
	dof.FarIntensity = 0
	dof.NearIntensity = 0
	dof.Parent = Lighting

	applyGameUi()
	-- Блюр заставки гасим В ЛЮБОМ режиме, даже когда HUD оставлен в кадре: он размывает
	-- МИР, а не интерфейс, и в снимке от него один вред.
	suppressBlur()
	hideNametags()
	hideCoreGui()
	setCharacterControls(false)

	overlayGui.Enabled = true
	panelGui.Enabled = true
	applyGuides()
	applyCursor()
	layoutLetterbox()
	refreshPanel()

	sendFreeze(freezeOn)

	-- Приоритет ПОСЛЕ Camera: скрипт камеры A-Chassis отрабатывает в этом же кадре и
	-- ставит свой CFrame. Встань мы раньше — он бы затирал нас каждый кадр.
	RunService:BindToRenderStep("PhotoModeCamera", Enum.RenderPriority.Camera.Value + 10, step)
	bound = true
end

local function leave()
	if bound then
		RunService:UnbindFromRenderStep("PhotoModeCamera")
		bound = false
	end

	sendFreeze(false)

	overlayGui.Enabled = false
	panelGui.Enabled = false
	guides.Visible = false
	barTop.Visible = false
	barBottom.Visible = false
	letterboxOn = false

	for _, conn in guiConns do
		conn:Disconnect()
	end
	table.clear(guiConns)
	restoreGuis()
	restoreBlur()
	restoreNametags()
	restoreCoreGui()
	setCharacterControls(true)

	if dof then
		dof:Destroy()
		dof = nil
	end

	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	looking = false
	applyCursor() -- active уже false: стрелка возвращается безусловно

	camera.FieldOfView = prevFov
	camera.CameraSubject = prevCameraSubject
	camera.CameraType = prevCameraType
end

local function toggle()
	active = not active
	if active then
		enter()
	else
		leave()
	end
end

-- // Ввод --------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode == TOGGLE_KEY then
		toggle()
		return
	end
	if not active then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		looking = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		applyCursor()
		return
	end

	if processed then
		return -- клик по ползунку не должен считаться горячей клавишей
	end

	local key = input.KeyCode
	if key == Enum.KeyCode.F then
		freezeOn = not freezeOn
		sendFreeze(freezeOn)
		refreshPanel()
	elseif key == Enum.KeyCode.G then
		guidesOn = not guidesOn
		applyGuides()
	elseif key == Enum.KeyCode.B then
		letterboxOn = not letterboxOn
		layoutLetterbox()
		barTop.Visible = letterboxOn
		barBottom.Visible = letterboxOn
	elseif key == Enum.KeyCode.H then
		-- «Чистый кадр»: панель, сетка и КУРСОР уходят, полосы остаются — они часть кадра.
		panelGui.Enabled = not panelGui.Enabled
		applyGuides()
		applyCursor()
		-- Плашку Roblox гасим здесь ЗАНОВО, а не только на входе в режим: топбар живёт
		-- в CoreGui, и его возвращает всё, что трогает интерфейс между F4 и снимком.
		hideCoreGui()
	elseif key == Enum.KeyCode.U then
		keepGameUi = not keepGameUi
		applyGameUi()
		refreshPanel()
	elseif key == Enum.KeyCode.X then
		roll = 0
	elseif key == Enum.KeyCode.T then
		autoFocus()
	elseif key == Enum.KeyCode.LeftBracket then
		fov = math.clamp(fov - 5, 15, 120)
		refreshPanel()
	elseif key == Enum.KeyCode.RightBracket then
		fov = math.clamp(fov + 5, 15, 120)
		refreshPanel()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 and looking then
		looking = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		applyCursor()
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not active then
		return
	end
	if looking and input.UserInputType == Enum.UserInputType.MouseMovement then
		targetYaw -= input.Delta.X * LOOK_SENSITIVITY
		targetPitch = math.clamp(targetPitch - input.Delta.Y * LOOK_SENSITIVITY, -1.53, 1.53)
	elseif input.UserInputType == Enum.UserInputType.MouseWheel then
		flySpeed = math.clamp(flySpeed * (1.18 ^ input.Position.Z), 2, 600)
		refreshPanel()
	end
end)

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if workspace.CurrentCamera then
		camera = workspace.CurrentCamera
		layoutLetterbox()
	end
end)
camera:GetPropertyChangedSignal("ViewportSize"):Connect(layoutLetterbox)

print("[PhotoMode] режим съёмки готов: F4")
