--!strict
-- ModuleScript: ReplicatedStorage.GameState
-- Общие имена фаз матча — единый словарь для сервера (MatchManager) и клиента
-- (LobbyUI / UIController). Строки СОВПАДАЮТ с тем, что уже шлёт RaceUpdate.Phase
-- («Countdown»/«Racing»), чтобы миграция со старого RaceManager была бесшовной.

local GameState = {}

GameState.Phase = {
	Lobby     = "Lobby",     -- игроки в лобби, жмут Ready (замена прежнего «Idle»)
	Countdown = "Countdown", -- набрали MinRacers готовых → отсчёт на старте
	Racing    = "Racing",    -- заезд идёт
	Results   = "Results",   -- экран итогов (замена прежнего «Finished»)
}

-- Куда игрок «уходит» между заездами и после game over. LobbyZone — якорь в
-- Workspace (Part с этим именем), персонаж телепортируется на него.
GameState.LobbyZoneName = "LobbyZone"

return GameState
