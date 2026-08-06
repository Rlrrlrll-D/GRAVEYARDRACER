--!strict
-- ModuleScript: ReplicatedStorage.Net
-- Единый список сетевых событий. И клиент, и сервер берут имена ОТСЮДА —
-- нет опечаток, есть один список для аудита трафика. Bootstrap должен создавать
-- папку Remotes по Net.Events (сейчас он делает это захардкоженно — см. TODO).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

Net.Events = {
	-- === уже существуют (создаёт Bootstrap) ===
	FireWeapon  = "FireWeapon",  -- client→server: (origin, direction)
	BulletFired = "BulletFired", -- server→clients: (origin, hitPos)
	UpdateStats = "UpdateStats", -- server→client: (statsTable)
	CameraShake = "CameraShake", -- server→client: (intensity, duration)
	RaceUpdate  = "RaceUpdate",  -- server→clients: (raceStateTable)

	-- === НОВЫЕ: меню / лобби / опции / атмосфера ===
	PlayerReady   = "PlayerReady",   -- client→server: (ready: boolean)
	LobbyState    = "LobbyState",    -- server→clients: { ready = n, needed = MinRacers, roster = {...} }
	ReturnToLobby = "ReturnToLobby", -- server→client: «ты выбыл/финишировал — уходишь из мира в лобби»
	Spectate      = "Spectate",      -- server→client: «ты выбыл, смотришь гонку» { LeaderUserId = n }
	MatchResult   = "MatchResult",   -- server→client: полноэкранный итог заезда { Outcome, Winner, Zombies }
	SaveSettings  = "SaveSettings",  -- client→server: применить+сохранить опции
	PushSettings  = "PushSettings",  -- server→client: настройки, загруженные из DataStore при входе
	BatScare      = "BatScare",      -- server→clients: (origin: Vector3, count: number, kind: "swarm"|"flyby")

	-- === МАГАЗИН ===
	-- Действие от клиента ОДНО на все случаи, а не «купить»/«надеть»/«показать окно»
	-- тремя ремоутами: сервер всё равно проверяет товар по ShopCatalog заново, а
	-- разделение только плодило бы одинаковые обработчики. План называл это
	-- BuyWithBones — переименовано, когда стало ясно, что покупкой дело не кончается.
	ShopAction     = "ShopAction",     -- client→server: (action: "buy"|"equip"|"prompt", itemId: string)
	ShopState      = "ShopState",      -- server→client: { bones, owned = {id=true}, equipped }
	PurchaseResult = "PurchaseResult", -- server→client: { ok: boolean, item: string?, message: string }
}

-- Удобный доступ (ждёт создания Bootstrap-ом).
function Net.get(name: string): RemoteEvent
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	return remotes:WaitForChild(name) :: RemoteEvent
end

return Net
