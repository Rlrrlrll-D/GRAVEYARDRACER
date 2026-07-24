--!strict
-- Script: ServerScriptService.MatchManager
-- Сессионная машина состояний матча (веха 4 плана V2). ЗАМЕНЯЕТ старый
-- RaceManager и VehicleSpawner — их скрипты удалены, фазами владеет только он.
--
--   Lobby ──(готовых ≥ MinRacers)──▶ Countdown ──▶ Racing ──▶ Results ──▶ Lobby
--
-- Разделение труда: RaceCore — логика заезда (чекпоинты/круги/победитель),
-- RaceScene — визуал (маркеры, призраки), PlayerFlow — игрок/машины/лобби.
--
-- КЛЮЧЕВОЕ: после game over (кончились жизни ИЛИ финиш) игрок НЕ остаётся в
-- мире — evict() сразу возвращает его в лобби, машина исчезает. Свободных машин
-- в мире нет: их выдаёт отсчёт и забирает эвикт.
--
-- Совместимость с клиентом: RaceUpdate шлёт те же фазы, что и старый RaceManager
-- («Idle»/«Countdown»/«Racing»/«Finished») — HUD (UIController) не переписывался.
-- Новое поле Participant=true в персональных пейлоадах гонщиков — по нему
-- LobbyUI прячет экран лобби только у участников заезда.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local GameState = require(ReplicatedStorage:WaitForChild("GameState"))
local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local RaceCore = require(script.Parent:WaitForChild("RaceCore"))
local RaceScene = require(script.Parent:WaitForChild("RaceScene"))
local PlayerFlow = require(script.Parent:WaitForChild("PlayerFlow"))

local cfg = GameConfig.Race
local Phase = GameState.Phase
local RESULTS_SECONDS = 8 -- пауза на экран итогов (как у старого RaceManager)
local RACE_ABORT_SECONDS = 30 -- никто так и не сел за руль → отменить заезд

local raceUpdate = Net.get(Net.Events.RaceUpdate)
local lobbyState = Net.get(Net.Events.LobbyState)
local playerReady = Net.get(Net.Events.PlayerReady)
local returnToLobby = Net.get(Net.Events.ReturnToLobby)

PlayerFlow.init()

-- // Готовность игроков -------------------------------------------------------
local ready: { [Player]: boolean } = {}
local phase = Phase.Lobby

playerReady.OnServerEvent:Connect(function(player, isReady)
	ready[player] = isReady == true
end)
Players.PlayerRemoving:Connect(function(p)
	ready[p] = nil
end)

local function readyList(): { Player }
	local list: { Player } = {}
	for p, r in ready do
		if r and p.Parent then
			table.insert(list, p)
		end
	end
	return list
end

local function broadcastLobby()
	-- ростер: все игроки сервера с флажком готовности (LobbyUI рисует список)
	local roster: { { name: string, ready: boolean } } = {}
	for _, plr in Players:GetPlayers() do
		table.insert(roster, { name = plr.DisplayName, ready = ready[plr] == true })
	end
	table.sort(roster, function(a, b)
		return a.name < b.name
	end)
	lobbyState:FireAllClients({
		phase = phase,
		ready = #readyList(),
		needed = cfg.MinRacers,
		total = #Players:GetPlayers(),
		roster = roster,
	})
end

-- // Эвикт --------------------------------------------------------------------
-- Единая точка «убрать игрока из мира»: и выбывание, и финиш, и победа.
local function evict(player: Player, resultKind: string, winnerName: string?)
	if resultKind == "won" then
		-- атрибут Wins: leaderstats зеркалит, PlayerData сохраняет в DataStore
		player:SetAttribute("Wins", ((player:GetAttribute("Wins") :: number?) or 0) + 1)
	end
	ready[player] = false
	PlayerFlow.unseat(player)
	PlayerFlow.sendToLobby(player) -- ← мир для «мёртвых» закрыт
	PlayerFlow.releaseVehicle(player) -- машина исчезает из мира
	returnToLobby:FireClient(player, { Result = resultKind, Winner = winnerName })
end

-- // Кто за рулём (только машины, выданные PlayerFlow) ------------------------
local function occupiedSeats(): { [Player]: VehicleSeat }
	local result: { [Player]: VehicleSeat } = {}
	for _, car in PlayerFlow.vehicles() do
		if car.Parent then
			local seat = car:FindFirstChild("DriveSeat")
			if seat and seat:IsA("VehicleSeat") and seat.Occupant then
				local character = seat.Occupant.Parent
				local plr = character and Players:GetPlayerFromCharacter(character)
				if plr then
					result[plr] = seat
				end
			end
		end
	end
	return result
end

-- // Фазы ---------------------------------------------------------------------
local function runLobby()
	phase = Phase.Lobby
	repeat
		broadcastLobby()
		raceUpdate:FireAllClients({ Phase = "Idle", Waiting = #readyList(), Needed = cfg.MinRacers })
		task.wait(0.5)
	until #readyList() >= cfg.MinRacers
end

local function runCountdown(): { Player }
	phase = Phase.Countdown
	local participants = readyList()
	-- мест на решётке может быть меньше, чем готовых
	while #participants > PlayerFlow.MaxSlots do
		table.remove(participants)
	end

	-- выпуск на грид: своя машина каждому + посадка
	for i, plr in participants do
		local car = PlayerFlow.assignVehicle(plr, PlayerFlow.gridSlot(i))
		if car then
			car:SetAttribute("FullReset", os.clock())
			PlayerFlow.seatDriver(plr)
		end
	end
	RaceScene.resetGhosts()

	-- машины неуязвимы, пока оседают на террейн и идёт отсчёт (иначе набивают
	-- урон столкновениями при спавне); снимаем неуязвимость на GO.
	local function setInvuln(v: boolean)
		for _, plr in participants do
			local car = PlayerFlow.getVehicle(plr)
			if car then
				car:SetAttribute("Invulnerable", v)
			end
		end
	end

	for c = cfg.CountdownSeconds, 1, -1 do
		setInvuln(true) -- каждый тик (перебивает setup VehicleController)
		broadcastLobby()
		for _, plr in Players:GetPlayers() do
			local payload: { [string]: any } = { Phase = "Countdown", Countdown = c, Laps = cfg.Laps }
			if table.find(participants, plr) then
				payload.Participant = true
			end
			raceUpdate:FireClient(plr, payload)
		end
		task.wait(1)
	end
	setInvuln(false) -- старт: машины снова уязвимы
	return participants
end

local function runRacing(participants: { Player }): (Player?, string?, RaceCore.Session)
	phase = Phase.Racing
	local session = RaceCore.newSession()

	for _, plr in Players:GetPlayers() do
		local payload: { [string]: any } = {
			Phase = "Racing", Go = true,
			Lap = 1, Laps = cfg.Laps, Position = 1,
			Racers = math.max(#participants, 1), NextCheckpoint = 1,
		}
		if table.find(participants, plr) then
			payload.Participant = true
		end
		raceUpdate:FireClient(plr, payload)
	end

	-- ГРЕЙС: машины неуязвимы первые секунды заезда — пока трогаются с места
	-- (A-Chassis раскачивается не мгновенно), иначе зомби у старта успевают
	-- уничтожить ещё неподвижную машину.
	local GRACE = 4
	for _, plr in participants do
		local car = PlayerFlow.getVehicle(plr)
		if car then
			car:SetAttribute("Invulnerable", true)
		end
	end
	task.delay(GRACE, function()
		for _, plr in participants do
			local car = PlayerFlow.getVehicle(plr)
			if car then
				car:SetAttribute("Invulnerable", false)
			end
		end
	end)

	local startClock = os.clock()
	local lastTick = os.clock()
	local lastBroadcast = 0
	while not session.winnerName do
		task.wait()
		local now = os.clock()
		local dt = now - lastTick
		lastTick = now

		local frame = session:step(occupiedSeats())
		for _, plr in frame.newlyEliminated do
			raceUpdate:FireClient(plr, { Phase = "Finished", Eliminated = true, PlayerWon = false })
			evict(plr, "eliminated", nil) -- жизни кончились → сразу в лобби
		end
		if frame.allOut then
			break -- гонщиков не осталось — заезд окончен без победителя
		end
		if not session.everRaced and now - startClock > RACE_ABORT_SECONDS then
			break -- никто так и не сел за руль (все ушли на отсчёте)
		end

		RaceScene.stepGhosts(now, dt)

		if now - lastBroadcast >= 0.4 and not session.winnerName then
			lastBroadcast = now
			broadcastLobby()
			for plr, row in session:standings(RaceScene.ghostProgresses()) do
				raceUpdate:FireClient(plr, {
					Phase = "Racing",
					Participant = true,
					Lap = row.Lap,
					Laps = row.Laps,
					Position = row.Position,
					Racers = row.Racers,
					NextCheckpoint = row.NextCheckpoint,
				})
			end
		end
	end
	return session.winner, session.winnerName, session
end

local function runResults(winner: Player?, winnerName: string?, session: RaceCore.Session)
	phase = Phase.Results
	broadcastLobby()
	for _, plr in Players:GetPlayers() do
		if session:isEliminated(plr) then
			continue -- уже получил GAME OVER и эвикт в ходе заезда
		end
		raceUpdate:FireClient(plr, {
			Phase = "Finished",
			PlayerWon = plr == winner,
			Winner = winnerName,
		})
		if PlayerFlow.getVehicle(plr) then
			-- участник, доживший до конца заезда: победителя тоже эвиктим —
			-- после заезда в мире не остаётся никто
			evict(plr, plr == winner and "won" or (winnerName and "lost" or "finished"), winnerName)
		end
	end
	task.wait(RESULTS_SECONDS)
end

-- // Главный цикл матча -------------------------------------------------------
print(`[MatchManager] Сессии включены: трасса {math.floor(RaceCore.TrackLength)} studs, {#RaceCore.Checkpoints} чекпоинтов, {RaceScene.GhostCount} призраков.`)

while true do
	runLobby()
	local participants = runCountdown()
	local winner, winnerName, session = runRacing(participants)
	runResults(winner, winnerName, session)
end
