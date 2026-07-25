-- LocalScript: StarterPlayerScripts.MatchResult
-- Две вещи, которых не хватало ядру «гонки на выживание»:
-- (1) РЕЖИМ ЗРИТЕЛЯ — по Spectate: выбывший (кончились жизни) НЕ выкидывается в
--     лобби, а остаётся в мире; камера следит за машиной-лидером до конца заезда.
-- (2) ПОЛНОЭКРАННЫЙ ИТОГ — по MatchResult: YOU WIN / GAME OVER / <NAME> WINS во
--     весь экран с эффектами (раньше итог тонул мелкой плашкой под опциями лобби).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

local spectateRemote = Net.get(Net.Events.Spectate)
local matchResult = Net.get(Net.Events.MatchResult)
local raceUpdate = Net.get(Net.Events.RaceUpdate)
local returnToLobby = Net.get(Net.Events.ReturnToLobby)

local GOLD = Color3.fromRGB(255, 210, 70)

-- // Каркас ------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "MatchResult"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50 -- поверх HUD и лобби
gui.Parent = playerGui

-- баннер зрителя (верх экрана)
local specBanner = Instance.new("TextLabel")
specBanner.Name = "SpectateBanner"
specBanner.Size = UDim2.new(0, 620, 0, 40)
specBanner.Position = UDim2.new(0.5, -310, 0, 24)
specBanner.BackgroundColor3 = UITheme.Shadow
specBanner.BackgroundTransparency = 0.3
specBanner.TextColor3 = UITheme.Palette.Bone
specBanner.Font = UITheme.Font
specBanner.TextScaled = true
specBanner.Text = "OUT OF LIVES — SPECTATING"
specBanner.Visible = false
Instance.new("UICorner", specBanner).CornerRadius = UDim.new(0, 8)
specBanner.Parent = gui

-- полноэкранный итог
local backdrop = Instance.new("Frame")
backdrop.Name = "ResultBackdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = UITheme.Shadow
backdrop.BackgroundTransparency = 1
backdrop.Visible = false
backdrop.Parent = gui

local title = Instance.new("TextLabel")
title.Name = "ResultTitle"
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Size = UDim2.new(0.9, 0, 0, 150)
title.Position = UDim2.new(0.5, 0, 0.42, 0)
title.BackgroundTransparency = 1
title.Font = UITheme.Font
title.TextScaled = true
title.TextStrokeTransparency = 0.2
title.Text = ""
title.Parent = backdrop
local titleScale = Instance.new("UIScale")
titleScale.Parent = title

local sub = Instance.new("TextLabel")
sub.Name = "ResultSub"
sub.AnchorPoint = Vector2.new(0.5, 0.5)
sub.Size = UDim2.new(0.7, 0, 0, 44)
sub.Position = UDim2.new(0.5, 0, 0.56, 0)
sub.BackgroundTransparency = 1
sub.Font = UITheme.Font
sub.TextScaled = true
sub.TextColor3 = UITheme.Palette.Bone
sub.Text = ""
sub.Parent = backdrop

-- // Режим зрителя -----------------------------------------------------------
local spectating = false
local leaderUserId = 0
local specConn: RBXScriptConnection? = nil

local function findLeaderCar(): Model?
	if leaderUserId > 0 then
		local c = workspace:FindFirstChild("Buggy_" .. leaderUserId)
		if c and c:IsA("Model") then
			return c
		end
	end
	for _, m in workspace:GetChildren() do
		if m:IsA("Model") and m.Name:match("^Buggy_") then
			return m
		end
	end
	return nil
end

local function startSpectating()
	if spectating then
		return
	end
	spectating = true
	specBanner.Visible = true
	camera.CameraType = Enum.CameraType.Scriptable
	specConn = RunService.RenderStepped:Connect(function()
		local car = findLeaderCar()
		if car then
			local pp = car.PrimaryPart or car:FindFirstChild("DriveSeat")
			if pp and pp:IsA("BasePart") then
				local pos = pp.Position
				local back = pp.CFrame.LookVector
				camera.CFrame = CFrame.lookAt(pos - back * 22 + Vector3.new(0, 12, 0), pos)
				return
			end
		end
		camera.CFrame = CFrame.lookAt(Vector3.new(0, 320, 0), Vector3.new(0, 0, 0))
	end)
end

local function stopSpectating()
	if not spectating then
		return
	end
	spectating = false
	specBanner.Visible = false
	if specConn then
		specConn:Disconnect()
		specConn = nil
	end
	camera.CameraType = Enum.CameraType.Custom
end

spectateRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	leaderUserId = tonumber(payload.LeaderUserId) or 0
	startSpectating()
	local lead = leaderUserId > 0 and Players:GetPlayerByUserId(leaderUserId) or nil
	specBanner.Text = lead and ("OUT OF LIVES — SPECTATING " .. string.upper(lead.DisplayName))
		or "OUT OF LIVES — SPECTATING"
end)

-- // Полноэкранный итог + эффекты --------------------------------------------
local function emberBurst(color: Color3)
	for _ = 1, 26 do
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		local s = math.random(4, 11)
		dot.Size = UDim2.fromOffset(s, s)
		dot.Position = UDim2.new(0.5 + (math.random() - 0.5) * 0.6, 0, 0.62, 0)
		dot.BackgroundColor3 = color
		dot.BorderSizePixel = 0
		Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
		dot.Parent = backdrop
		local dx = (math.random() - 0.5) * 700
		local dy = -math.random(220, 520)
		TweenService:Create(
			dot,
			TweenInfo.new(math.random(11, 21) / 10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = dot.Position + UDim2.fromOffset(dx, dy), BackgroundTransparency = 1 }
		):Play()
		Debris:AddItem(dot, 2.5)
	end
end

local function hideResult()
	TweenService:Create(backdrop, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
	task.delay(0.4, function()
		backdrop.Visible = false
	end)
end

local function showResult(outcome: string, winner: string?, zombies: number)
	stopSpectating()

	if outcome == "won" then
		title.Text = "YOU WIN!"
		title.TextColor3 = GOLD
		sub.Text = string.format("%d zombies defeated", zombies or 0)
	elseif outcome == "eliminated" then
		title.Text = "GAME OVER"
		title.TextColor3 = UITheme.Palette.Red
		sub.Text = "out of lives — " .. string.upper(tostring(winner or "no one")) .. " wins"
	else -- lost / finished
		title.Text = string.upper(tostring(winner or "GHOST")) .. " WINS"
		title.TextColor3 = UITheme.Palette.Red
		sub.Text = string.format("you finished · %d zombies defeated", zombies or 0)
	end

	backdrop.Visible = true
	backdrop.BackgroundTransparency = 1
	TweenService:Create(backdrop, TweenInfo.new(0.35), { BackgroundTransparency = 0.25 }):Play()
	titleScale.Scale = 0.35
	TweenService:Create(titleScale, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	emberBurst(outcome == "won" and GOLD or UITheme.Palette.Red)
end

matchResult.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	showResult(tostring(payload.Outcome), payload.Winner, tonumber(payload.Zombies) or 0)
end)

-- сброс при старте СЛЕДУЮЩЕГО заезда: ТОЛЬКО на Countdown (новый заезд стартует).
-- НЕ на Racing — те апдейты идут каждые 0.4с и (raceUpdate и matchResult — разные
-- remote'ы, порядок между ними НЕ гарантирован) могут прийти ПОСЛЕ MatchResult,
-- ложно гася свежий экран итога. Именно это роняло оверлей «через раз».
raceUpdate.OnClientEvent:Connect(function(data)
	if type(data) == "table" and data.Participant == true and data.Phase == "Countdown" then
		stopSpectating()
		backdrop.Visible = false
	end
end)

-- Сервер шлёт ReturnToLobby ОДИН раз, ~6с после MatchResult (не спамит, порядок
-- надёжен) → гасим экран итога; дальше LobbyUI показывает заставку.
returnToLobby.OnClientEvent:Connect(function()
	hideResult()
end)
