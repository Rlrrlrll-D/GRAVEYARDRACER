--!strict
-- LocalScript: StarterPlayerScripts.LobbyUI
-- Экран лобби + экран итогов (веха 4). Виден, пока игрок ВНЕ заезда: в лобби
-- до старта и после эвикта (game over/финиш). Прячется у УЧАСТНИКОВ заезда по
-- полю Participant=true в персональных RaceUpdate от MatchManager; снова
-- показывается по ReturnToLobby и в фазе Idle (лобби).
-- Вся типографика/цвета — из UITheme (Creepster везде, палитра по кругу).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local GameState = require(ReplicatedStorage:WaitForChild("GameState"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local playerReady = Net.get(Net.Events.PlayerReady)
local lobbyState = Net.get(Net.Events.LobbyState)
local returnToLobby = Net.get(Net.Events.ReturnToLobby)
local raceUpdate = Net.get(Net.Events.RaceUpdate)

-- // Каркас экрана ----------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "LobbyUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 10 -- поверх HUD
gui.Parent = playerGui

local root = Instance.new("Frame") -- полупрозрачная кладбищенская вуаль
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = UITheme.PanelBg
root.BackgroundTransparency = 0.15
root.Visible = true
root.Parent = gui

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 96)
title.Position = UDim2.new(0, 0, 0.12, 0)
title.BackgroundTransparency = 1
title.Text = "GRAVEYARD RACER"
title.TextScaled = true
UITheme.applyText(title, { color = UITheme.Palette.Bone })
title.Parent = root

-- // Кнопка Ready (завязана на MinRacers-гейт MatchManager) ------------------
local isReady = false
local readyBtn = Instance.new("TextButton")
readyBtn.Size = UDim2.new(0, 320, 0, 64)
readyBtn.Position = UDim2.new(0.5, -160, 0.55, 0)
readyBtn.BackgroundColor3 = UITheme.Palette.Green
readyBtn.AutoButtonColor = true
readyBtn.Text = "READY"
readyBtn.TextScaled = true
UITheme.applyText(readyBtn)
Instance.new("UICorner", readyBtn).CornerRadius = UDim.new(0, 8)
readyBtn.Parent = root

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(0, 480, 0, 40)
statusLabel.Position = UDim2.new(0.5, -240, 0.55, 76)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Waiting for racers…"
statusLabel.TextScaled = true
UITheme.applyText(statusLabel, { color = UITheme.Palette.Bone })
statusLabel.Parent = root

readyBtn.Activated:Connect(function()
	isReady = not isReady
	readyBtn.Text = isReady and "READY ✓" or "READY"
	readyBtn.BackgroundColor3 = isReady and Color3.fromRGB(52, 90, 64) or UITheme.Palette.Green
	playerReady:FireServer(isReady)
end)

-- // Ростер: кто на сервере и кто готов (веха 5) -----------------------------
local rosterPanel = Instance.new("Frame")
rosterPanel.Name = "Roster"
rosterPanel.Size = UDim2.new(0, 280, 0, 336)
rosterPanel.Position = UDim2.new(0, 28, 0.28, 0)
rosterPanel.BackgroundColor3 = UITheme.PanelBg
rosterPanel.BackgroundTransparency = 0.2
rosterPanel.Parent = root
Instance.new("UICorner", rosterPanel).CornerRadius = UDim.new(0, 10)

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
		l.Size = UDim2.new(1, 0, 0, 32)
		l.BackgroundColor3 = UITheme.cycleColor(i)
		l.BackgroundTransparency = 0.15
		-- кость (каждый 3-й цвет цикла) светлая → тёмный текст, иначе костяной
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
		statusLabel.Text = "Race in progress — press READY for the next one"
	end
	-- Results: текст итога уже поставил ReturnToLobby — не перетираем
	if type(state.roster) == "table" then
		renderRoster(state.roster)
	end
end)

-- Опции — в OptionsMenu (надгробие, кнопка MENU внизу-справа): панель строится
-- из SettingsSchema.Options и доступна из лобби (DisplayOrder выше вуали).

-- // Показ/скрытие лобби ----------------------------------------------------
local function setLobbyVisible(visible: boolean)
	root.Visible = visible
	-- TODO: спрятать/показать геймплейный HUD (GraveyardHUD) — в лобби он не нужен.
end

-- Приход из мира после game over/финиша: показать итог, затем открыть лобби.
returnToLobby.OnClientEvent:Connect(function(payload)
	local result = payload.Result
	local text =
		result == "won" and "YOU WIN!"
		or result == "eliminated" and "GAME OVER — OUT OF LIVES"
		or result == "finished" and "FINISHED"
		or (string.upper(tostring(payload.Winner or "GHOST")) .. " WINS")
	statusLabel.Text = text
	isReady = false
	readyBtn.Text = "READY"
	readyBtn.BackgroundColor3 = UITheme.Palette.Green
	setLobbyVisible(true) -- ← игрок гарантированно ВНЕ мира, снова в лобби
end)

-- Старт заезда: у УЧАСТНИКА (Participant=true в персональном пейлоаде) лобби
-- прячется; фаза Idle (все в лобби) — показывается у всех.
raceUpdate.OnClientEvent:Connect(function(data)
	if data.Participant == true and (data.Phase == "Countdown" or data.Phase == "Racing") then
		setLobbyVisible(false)
	elseif data.Phase == "Idle" then
		setLobbyVisible(true)
	end
end)

setLobbyVisible(true)
