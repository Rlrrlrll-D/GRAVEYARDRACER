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

local playerReady = Net.get(Net.Events.PlayerReady)
local lobbyState = Net.get(Net.Events.LobbyState)
local returnToLobby = Net.get(Net.Events.ReturnToLobby)
local raceUpdate = Net.get(Net.Events.RaceUpdate)

-- // Блюр фона (пока заставка показана) --------------------------------------
local blur = Instance.new("BlurEffect")
blur.Name = "MenuBlur"
blur.Size = 18
blur.Parent = Lighting

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

local title = Instance.new("TextLabel")
title.Size = UDim2.new(0.9, 0, 0, 120)
title.Position = UDim2.new(0.05, 0, 0.1, 0)
title.BackgroundTransparency = 1
title.Text = "GRAVEYARD RACER"
title.TextScaled = true
UITheme.applyText(title, { color = UITheme.Palette.Bone })
title.TextStrokeTransparency = 0.2
title.Parent = root

local sub = Instance.new("TextLabel")
sub.Size = UDim2.new(0.7, 0, 0, 40)
sub.Position = UDim2.new(0.15, 0, 0.1, 122)
sub.BackgroundTransparency = 1
sub.Text = "the dead don't brake"
sub.TextScaled = true
UITheme.applyText(sub, { color = UITheme.Palette.Red })
sub.Parent = root

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
local isReady = false
local playBtn = makeButton("PLAY", UITheme.Palette.Green, 0, 64)

-- // OPTIONS (открывает компактную панель опций справа — OptionsMenu.Panel) ----
local optBtn = makeButton("OPTIONS", Color3.fromRGB(22, 33, 27), 74, 50) -- тёмный мох

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(0, 480, 0, 34)
statusLabel.Position = UDim2.new(0.5, -240, 0.56, 134)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Press PLAY to race"
statusLabel.TextScaled = true
UITheme.applyText(statusLabel, { color = UITheme.Palette.Bone })
statusLabel.Parent = root

playBtn.Activated:Connect(function()
	isReady = not isReady
	playBtn.Text = isReady and "PLAY ✓" or "PLAY"
	playBtn.BackgroundColor3 = isReady and Color3.fromRGB(52, 90, 64) or UITheme.Palette.Green
	playerReady:FireServer(isReady)
end)

-- панель опций живёт в отдельном ScreenGui (OptionsMenu); тумблим её Visible
local function optionsPanel(): GuiObject?
	local om = playerGui:FindFirstChild("OptionsMenu")
	local p = om and om:FindFirstChild("Panel")
	return (p and p:IsA("GuiObject")) and (p :: GuiObject) or nil
end
optBtn.Activated:Connect(function()
	local p = optionsPanel()
	if p then
		p.Visible = not p.Visible
	end
end)

-- // Ростер: кто на сервере и кто готов ---------------------------------------
-- симметрично панели опций справа: та же ширина/верх, зеркально слева
local rosterPanel = Instance.new("Frame")
rosterPanel.Name = "Roster"
rosterPanel.Size = UDim2.new(0, 280, 0, 404)
rosterPanel.Position = UDim2.new(0, 28, 0.24, 0)
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

type RosterRow = { name: string, ready: boolean }
local function renderRoster(roster: { RosterRow })
	for _, c in rosterList:GetChildren() do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	for i, row in roster do
		local l = Instance.new("TextLabel")
		l.LayoutOrder = i
		l.Size = UDim2.new(1, 0, 0, 30)
		l.BackgroundColor3 = UITheme.cycleColor(i)
		l.BackgroundTransparency = 0.15
		l.TextColor3 = (i % 3 == 0) and UITheme.Shadow or UITheme.Ink
		l.Font = UITheme.Font
		l.TextScaled = true
		l.Text = row.ready and (row.name .. "  ✓") or row.name
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
	-- Results: текст итога уже поставил ReturnToLobby — не перетираем
	if type(state.roster) == "table" then
		renderRoster(state.roster)
	end
end)

-- // Показ/скрытие заставки ---------------------------------------------------
-- Пока заставка видна: блюр фона включён, геймплейный HUD скрыт.
local function setLobbyVisible(visible: boolean)
	root.Visible = visible
	blur.Size = visible and 18 or 0
	local hud = playerGui:FindFirstChild("GraveyardHUD")
	if hud and hud:IsA("ScreenGui") then
		hud.Enabled = not visible
	end
	if not visible then
		local p = optionsPanel()
		if p then
			p.Visible = false -- уходя в гонку, закрываем опции
		end
	end
end

-- Приход из мира после game over/финиша: показать итог, затем заставку.
returnToLobby.OnClientEvent:Connect(function(payload)
	local result = payload.Result
	statusLabel.Text = result == "won" and "YOU WIN!"
		or result == "eliminated" and "GAME OVER — OUT OF LIVES"
		or result == "finished" and "FINISHED"
		or (string.upper(tostring(payload.Winner or "GHOST")) .. " WINS")
	isReady = false
	playBtn.Text = "PLAY"
	playBtn.BackgroundColor3 = UITheme.Palette.Green
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
