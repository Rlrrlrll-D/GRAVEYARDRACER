--!strict
-- ModuleScript: ServerScriptService.RaceCore
-- ЧИСТАЯ логика заезда, выделенная из RaceManager (веха 3 плана V2, без смены
-- поведения): геометрия трассы (безье → полилиния), чекпоинты, прогресс
-- гонщиков (чекпоинты/круги), выбывание, победитель (круги закрыты или
-- «последний выживший»), позиции. НИКАКИХ фаз, ремоутов и визуала — этим
-- занимается менеджер (сейчас RaceManager, после вехи 4 — MatchManager).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local MapLayout = require(ReplicatedStorage:WaitForChild("MapLayout"))

local cfg = GameConfig.Race

local RaceCore = {}

-- // Геометрия трассы ---------------------------------------------------------
local GHOST_Y = 4.3 -- центр шасси призрака: колёса на уровне дороги (Y≈2)

local function bezier(seg: { Vector2 }, t: number): Vector2
	local p0, p1, p2, p3 = seg[1], seg[2], seg[3], seg[4]
	local u = 1 - t
	return p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
end

local points: { Vector3 } = {}
for _, seg in MapLayout.TrackSegments do
	for i = 0, 39 do
		local p = bezier(seg, i / 40)
		table.insert(points, Vector3.new(p.X * MapLayout.Scale, GHOST_Y, p.Y * MapLayout.Scale))
	end
end
local segLengths: { number } = {}
local trackLength = 0
for i = 1, #points do
	local nextPoint = points[i % #points + 1]
	segLengths[i] = (nextPoint - points[i]).Magnitude
	trackLength += segLengths[i]
end
RaceCore.TrackLength = trackLength

-- Точка и направление на дистанции dist (замкнутый круг)
function RaceCore.sampleAt(dist: number): (Vector3, Vector3)
	local d = dist % trackLength
	local i = 1
	while d > segLengths[i] do
		d -= segLengths[i]
		i = i % #points + 1
	end
	local a = points[i]
	local b = points[i % #points + 1]
	local dir = (b - a).Unit
	return a + dir * d, dir
end

-- // Чекпоинты (мировые координаты, Y=0) --------------------------------------
local checkpoints: { Vector3 } = {}
for _, cp in MapLayout.RaceCheckpoints do
	table.insert(checkpoints, Vector3.new(cp.X * MapLayout.Scale, 0, cp.Y * MapLayout.Scale))
end
RaceCore.Checkpoints = checkpoints

-- // Сессия заезда ------------------------------------------------------------
export type Racer = {
	seat: VehicleSeat,
	cpIndex: number,
	laps: number,
}

export type StepResult = {
	newlyEliminated: { Player }, -- выбыли на этом шаге (кончились жизни)
	winner: Player?, -- победитель: круги закрыты или последний выживший
	winnerName: string?,
	allOut: boolean, -- заезд был, но гонщиков не осталось (без победителя)
}

export type StandingsRow = {
	Lap: number,
	Laps: number,
	Position: number,
	Racers: number,
	NextCheckpoint: number,
}

local Session = {}
Session.__index = Session

export type Session = typeof(setmetatable(
	{} :: {
		racers: { [Player]: Racer },
		eliminated: { [Player]: boolean },
		everRaced: boolean,
		peakRacers: number, -- пик числа реальных гонщиков (для «последнего выжившего»)
		winner: Player?,
		winnerName: string?,
	},
	Session
))

function RaceCore.newSession(): Session
	return setmetatable({
		racers = {},
		eliminated = {},
		everRaced = false,
		peakRacers = 0,
		winner = nil :: Player?,
		winnerName = nil :: string?,
	}, Session)
end

-- Один тик логики заезда. occupied — кто сейчас за рулём ({[Player]: seat}).
-- Порядок блоков — как в исходном цикле RaceManager.
function Session.step(self: Session, occupied: { [Player]: VehicleSeat }): StepResult
	local result: StepResult = { newlyEliminated = {}, winner = nil, winnerName = nil, allOut = false }

	-- регистрация гонщиков (присоединиться можно и после старта)
	for plr, seat in occupied do
		if not self.eliminated[plr] then
			local racer = self.racers[plr]
			if racer then
				racer.seat = seat
			else
				self.racers[plr] = { seat = seat, cpIndex = 1, laps = 0 }
			end
		end
	end
	for plr, racer in self.racers do
		if plr.Parent == nil or racer.seat.Parent == nil then
			self.racers[plr] = nil -- игрок вышел или его машину убрали
		end
	end
	local before = 0
	for _ in self.racers do
		before += 1
	end
	if before > self.peakRacers then
		self.peakRacers = before
	end

	-- выбывшие (кончились жизни): убрать из заезда
	for plr, racer in self.racers do
		local v = racer.seat.Parent
		if v and v:GetAttribute("Eliminated") then
			self.racers[plr] = nil
			if not self.eliminated[plr] then
				self.eliminated[plr] = true
				table.insert(result.newlyEliminated, plr)
			end
		end
	end

	-- итог по реальным гонщикам
	local active, lastPlr = 0, nil :: Player?
	for plr in self.racers do
		active += 1
		lastPlr = plr
	end
	if active > 0 then
		self.everRaced = true
	end
	if not self.winnerName then
		if self.peakRacers >= 2 and active == 1 and lastPlr then
			-- все соперники выбыли → последний выживший побеждает
			self.winner = lastPlr
			self.winnerName = (lastPlr :: Player).DisplayName
		elseif self.everRaced and active == 0 then
			result.allOut = true
		end
	end

	-- прохождение чекпоинтов по порядку
	for plr, racer in self.racers do
		local target = checkpoints[racer.cpIndex]
		local seatPos = racer.seat.Position
		local dx, dz = seatPos.X - target.X, seatPos.Z - target.Z
		if math.sqrt(dx * dx + dz * dz) <= cfg.CheckpointRadius then
			racer.cpIndex += 1
			if racer.cpIndex > #checkpoints then
				racer.cpIndex = 1
				racer.laps += 1
				if racer.laps >= cfg.Laps then
					self.winner = plr
					self.winnerName = plr.DisplayName
				end
			end
		end
	end

	result.winner = self.winner
	result.winnerName = self.winnerName
	return result
end

-- Персональные данные для трансляции. extraProgresses — прогресс не-игроков
-- (призраки-пейсеры) в кругах; участвуют в позиции и числе гонщиков.
function Session.standings(self: Session, extraProgresses: { number }?): { [Player]: StandingsRow }
	local progresses: { number } = {}
	local playerProgress: { [Player]: number } = {}
	for plr, racer in self.racers do
		local p = racer.laps + (racer.cpIndex - 1) / #checkpoints
		playerProgress[plr] = p
		table.insert(progresses, p)
	end
	if extraProgresses then
		for _, p in extraProgresses do
			table.insert(progresses, p)
		end
	end
	local rows: { [Player]: StandingsRow } = {}
	for plr, racer in self.racers do
		local mine = playerProgress[plr]
		local position = 1
		for _, p in progresses do
			if p > mine then
				position += 1
			end
		end
		rows[plr] = {
			Lap = math.min(racer.laps + 1, cfg.Laps),
			Laps = cfg.Laps,
			Position = position,
			Racers = #progresses,
			NextCheckpoint = racer.cpIndex,
		}
	end
	return rows
end

function Session.isEliminated(self: Session, plr: Player): boolean
	return self.eliminated[plr] == true
end

return RaceCore
