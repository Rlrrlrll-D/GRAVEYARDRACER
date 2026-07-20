--!strict
-- Script: ServerScriptService.MatchManager  [СКЕЛЕТ — ещё не подключён к Studio]
-- Машина состояний матча промышленного вида. ЗАМЕНЯЕТ вечный while-цикл
-- RaceManager: тот надо распилить на модуль RaceCore (чистая логика чекпоинтов/
-- кругов, без управления фазами) — MatchManager дёргает его каждый кадр в фазе
-- Racing и получает победителя/выбывших.
--
--   Lobby ──(готовых ≥ MinRacers)──▶ Countdown ──▶ Racing ──▶ Results ──▶ Lobby
--
-- КЛЮЧЕВОЕ ТРЕБОВАНИЕ: после game over (кончились жизни ИЛИ финиш) игрок НЕ
-- остаётся в игровом мире — его сразу выкидывает в лобби (PlayerFlow.sendToLobby),
-- машина глохнет/убирается, показывается экран итогов. Мир для «мёртвых» закрыт.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local GameState = require(ReplicatedStorage:WaitForChild("GameState"))
local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
-- local RaceCore = require(script.Parent.RaceCore) -- TODO: выделить из RaceManager
local PlayerFlow = _G.PlayerFlow -- TODO: заменить на require(ModuleScript)

local Phase = GameState.Phase
local raceUpdate = Net.get(Net.Events.RaceUpdate)
local lobbyState = Net.get(Net.Events.LobbyState)
local playerReady = Net.get(Net.Events.PlayerReady)
local returnToLobby = Net.get(Net.Events.ReturnToLobby)

-- // Готовность игроков в лобби ---------------------------------------------
local ready: { [Player]: boolean } = {}

playerReady.OnServerEvent:Connect(function(player, isReady)
	ready[player] = isReady == true
end)
Players.PlayerRemoving:Connect(function(p) ready[p] = nil end)

local function countReady(): number
	local n = 0
	for p, r in ready do
		if r and p.Parent then n += 1 end
	end
	return n
end

local function broadcastLobby()
	lobbyState:FireAllClients({
		ready = countReady(),
		needed = GameConfig.Race.MinRacers,
		total = #Players:GetPlayers(),
	})
end

-- // Эвикт из мира ----------------------------------------------------------
-- Единая точка «убрать игрока из заезда»: и при выбывании (нет жизней), и на
-- финише. Персонаж — в лобби, машина заглушена, клиенту — экран итогов.
local function evict(player: Player, resultKind: string, extra: { [string]: any }?)
	ready[player] = false
	local car = PlayerFlow and PlayerFlow.getVehicle(player)
	if car then
		local seat = car:FindFirstChild("DriveSeat")
		if seat and seat:IsA("VehicleSeat") then seat.Disabled = true end
	end
	if PlayerFlow then PlayerFlow.sendToLobby(player) end -- ← НЕ оставляем в мире
	local payload = { Phase = Phase.Results, Result = resultKind }
	if extra then for k, v in extra do payload[k] = v end end
	returnToLobby:FireClient(player, payload) -- клиент: показать итог, открыть лобби
end

-- // Фазы -------------------------------------------------------------------
local function runLobby()
	repeat
		broadcastLobby()
		raceUpdate:FireAllClients({ Phase = Phase.Lobby, Waiting = countReady(), Needed = GameConfig.Race.MinRacers })
		task.wait(0.5)
	until countReady() >= GameConfig.Race.MinRacers
end

local function runCountdown()
	-- TODO: выпустить готовых игроков на грид (PlayerFlow.assignVehicle + посадить),
	-- FullReset машинам, разморозить управление.
	for c = GameConfig.Race.CountdownSeconds, 1, -1 do
		raceUpdate:FireAllClients({ Phase = Phase.Countdown, Countdown = c, Laps = GameConfig.Race.Laps })
		task.wait(1)
	end
end

local function runRacing()
	raceUpdate:FireAllClients({ Phase = Phase.Racing, Go = true, Laps = GameConfig.Race.Laps })
	local winner: Player? = nil
	while not winner do
		task.wait()
		-- TODO: local frame = RaceCore.step(dt) → прогресс/позиции/победитель.
		-- Скелет показывает ТОЛЬКО контур эвикта — самое важное для этого этапа:
		for _, player in Players:GetPlayers() do
			local car = PlayerFlow and PlayerFlow.getVehicle(player)
			if car and car:GetAttribute("Eliminated") and ready[player] then
				evict(player, "eliminated") -- кончились жизни → сразу в лобби
			end
			-- if RaceCore.finished(player) then winner = winner or player;
			--     evict(player, player == winner and "won" or "finished", { Winner = winner.DisplayName }) end
		end
		-- if RaceCore.everyoneOut() then break end
	end
	return winner
end

local function runResults(winner: Player?)
	-- Победителя тоже эвиктим — после заезда в мире не остаётся никто.
	for _, player in Players:GetPlayers() do
		if ready[player] then
			evict(player, player == winner and "won" or "lost",
				{ Winner = winner and winner.DisplayName or nil })
		end
	end
	task.wait(GameConfig.Race.CountdownSeconds) -- пауза на экран итогов
end

-- // Главный цикл матча -----------------------------------------------------
task.spawn(function()
	while true do
		runLobby()
		runCountdown()
		local winner = runRacing()
		runResults(winner)
	end
end)

print("[MatchManager] СКЕЛЕТ загружен (не активируйте вместе со старым RaceManager).")
