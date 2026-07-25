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
-- КЛЮЧЕВОЕ: выбывший (кончились жизни) НЕ выкидывается сразу — он остаётся
-- ЗРИТЕЛЕМ (spectate) и досматривает гонку; в лобби все возвращаются ВМЕСТЕ
-- после полноэкранного экрана итогов (runResults).
--
-- Совместимость с клиентом: RaceUpdate шлёт фазы «Idle»/«Countdown»/«Racing».
-- Итог заезда — отдельным MatchResult (полноэкранный), выбывание — Spectate.
-- Новое поле Participant=true в персональных пейлоадах гонщиков — по нему
-- LobbyUI прячет экран лобби только у участников заезда.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local GameState = require(ReplicatedStorage:WaitForChild("GameState"))
local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local RaceCore = require(script.Parent:WaitForChild("RaceCore"))
local RaceScene = require(script.Parent:WaitForChild("RaceScene"))
local PlayerFlow = require(script.Parent:WaitForChild("PlayerFlow"))

local cfg = GameConfig.Race
local Phase = GameState.Phase
local RESULTS_SECONDS = 6 -- держим полноэкранный экран итогов, затем всех в лобби
local RACE_ABORT_SECONDS = 30 -- никто так и не сел за руль → отменить заезд

local raceUpdate = Net.get(Net.Events.RaceUpdate)
local lobbyState = Net.get(Net.Events.LobbyState)
local playerReady = Net.get(Net.Events.PlayerReady)
local returnToLobby = Net.get(Net.Events.ReturnToLobby)
local spectateRemote = Net.get(Net.Events.Spectate)
local matchResult = Net.get(Net.Events.MatchResult)

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

-- // Выбывание / возврат ------------------------------------------------------
-- spectate: игрок потратил все жизни В ХОДЕ заезда. Машину убираем, персонажа
-- прячем у старта (без UI лобби), но игрока НЕ выкидываем — он остаётся ЗРИТЕЛЕМ:
-- клиент по Spectate ставит камеру на лидера и досматривает финиш. Возврат в
-- лобби происходит ВСЕМ разом в runResults (после экрана итогов).
local function spectate(player: Player, leaderUserId: number)
	ready[player] = false
	PlayerFlow.unseat(player)
	PlayerFlow.sendToLobby(player) -- безопасно у старта + фриз; ReturnToLobby НЕ шлём → заставка лобби не всплывает
	PlayerFlow.releaseVehicle(player)
	spectateRemote:FireClient(player, { LeaderUserId = leaderUserId })
end

-- returnPlayerToLobby: финальный возврат в лобби ПОСЛЕ экрана итогов (всем участникам).
local function returnPlayerToLobby(player: Player, resultKind: string, winnerName: string?)
	ready[player] = false
	PlayerFlow.unseat(player)
	PlayerFlow.sendToLobby(player)
	PlayerFlow.releaseVehicle(player)
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

	-- свежий старт: сносим зомби с прошлого заезда, чтобы они не роились у грида
	-- на отсчёте (новые не заспавнятся, пока машины неуязвимы — см. ZombieSpawner).
	for _, z in CollectionService:GetTagged("Zombie") do
		z:Destroy()
	end

	-- выпуск на грид: СПЕРВА все машины, затем пауза, затем посадка. Порядок важен:
	-- у каждой машины свой серверный «A-Chassis Tune.Initialize», который на
	-- ChildAdded «SeatWeld» копирует клиентский интерфейс AC6 в PlayerGui водителя.
	-- Если посадить сразу после спавна (на 2-м+ заезде персонаж уже есть → посадка
	-- мгновенная), SeatWeld появляется РАНЬШЕ, чем Initialize успевает подключить
	-- свой хендлер → копия интерфейса теряется → машина «не едет». Пауза даёт
	-- Initialize подключиться (и машине осесть на террейн перед посадкой).
	for i, plr in participants do
		local car = PlayerFlow.assignVehicle(plr, PlayerFlow.gridSlot(i))
		if car then
			car:SetAttribute("FullReset", os.clock())
			-- Защита на всю подготовку+отсчёт+грейс ОДНИМ timestamp'ом (без мерцания
			-- атрибута): держит иммунитет к урону И не даёт зомби спавниться у грида
			-- (onPartTouched/ZombieSpawner смотрят ProtectedUntil). ≈ wait2+отсчёт5+грейс4.
			car:SetAttribute("ProtectedUntil", os.clock() + 12)
			car:SetAttribute("Invulnerable", true)
		end
	end

	task.wait(2)
	for _, plr in participants do
		PlayerFlow.seatDriver(plr)
	end
	RaceScene.resetGhosts()

	for c = cfg.CountdownSeconds, 1, -1 do
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
	-- ЧИСТЫЙ ЗАПУСК: сносим зомби у грида на GO (респавнятся по мере движения). Гарантия,
	-- что старт не забит зомби, даже если кто-то заспавнился на стыке отсчёт↔гонка.
	for _, plr in participants do
		local car = PlayerFlow.getVehicle(plr)
		local seat = car and car:FindFirstChild("DriveSeat")
		if seat and seat:IsA("BasePart") then
			for _, z in CollectionService:GetTagged("Zombie") do
				local ok, p = pcall(function()
					return z:GetPivot().Position
				end)
				if ok and (p - (seat :: BasePart).Position).Magnitude < 90 then
					z:Destroy()
				end
			end
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
	local spectators: { [Player]: boolean } = {} -- выбывшие: досматривают гонку
	local leaderUserId = 0 -- текущий лидер (кого показывать зрителям)
	while not session.winnerName do
		task.wait()
		local now = os.clock()
		local dt = now - lastTick
		lastTick = now

		local frame = session:step(occupiedSeats())
		for _, plr in frame.newlyEliminated do
			spectate(plr, leaderUserId) -- НЕ в лобби: зритель до конца заезда
			spectators[plr] = true
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
			local leaderId = 0
			for plr, row in session:standings(RaceScene.ghostProgresses()) do
				if row.Position == 1 then
					leaderId = plr.UserId
				end
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
			leaderUserId = leaderId
			for plr in spectators do
				if plr.Parent then
					spectateRemote:FireClient(plr, { LeaderUserId = leaderId })
				end
			end
		end
	end
	return session.winner, session.winnerName, session
end

local function outcomeFor(plr: Player, winner: Player?, winnerName: string?, session: RaceCore.Session): string
	if session:isEliminated(plr) then
		return "eliminated"
	elseif plr == winner then
		return "won"
	elseif winnerName then
		return "lost" -- доехал, но первым финишировал другой
	else
		return "finished" -- заезд без победителя (все сошли/отмена)
	end
end

local function runResults(winner: Player?, winnerName: string?, session: RaceCore.Session, participants: { Player })
	phase = Phase.Results
	broadcastLobby()
	-- 1) полноэкранный экран итогов ВСЕМ участникам — и выжившим, и зрителям-выбывшим
	for _, plr in participants do
		if not plr.Parent then
			continue
		end
		local outcome = outcomeFor(plr, winner, winnerName, session)
		if outcome == "won" then
			-- атрибут Wins: leaderstats зеркалит, PlayerData сохраняет в DataStore
			plr:SetAttribute("Wins", ((plr:GetAttribute("Wins") :: number?) or 0) + 1)
		end
		matchResult:FireClient(plr, {
			Outcome = outcome,
			Winner = winnerName,
			Zombies = (plr:GetAttribute("ZombiesDefeated") :: number?) or 0,
		})
	end
	-- 2) держим экран итогов, затем ВСЕХ участников разом в лобби
	task.wait(RESULTS_SECONDS)
	for _, plr in participants do
		if plr.Parent then
			returnPlayerToLobby(plr, outcomeFor(plr, winner, winnerName, session), winnerName)
		end
	end
end

-- // Главный цикл матча -------------------------------------------------------
print(`[MatchManager] Сессии включены: трасса {math.floor(RaceCore.TrackLength)} studs, {#RaceCore.Checkpoints} чекпоинтов, {RaceScene.GhostCount} призраков.`)

while true do
	runLobby()
	local participants = runCountdown()
	local winner, winnerName, session = runRacing(participants)
	runResults(winner, winnerName, session, participants)
end
