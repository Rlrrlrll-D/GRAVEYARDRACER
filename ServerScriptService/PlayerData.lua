--!strict
-- ModuleScript: ServerScriptService.PlayerData
-- Персистентность игрока (веха 6b): одна DataStore-запись на игрока:
--   { settings = { по SettingsSchema }, stats = { zombies = n, wins = n } }
-- Статы живут в АТРИБУТАХ игрока (ZombiesDefeated растит ZombieSpawner, Wins —
-- MatchManager, leaderstats зеркалит): при входе сидируются из записи, при
-- сохранении читаются обратно. Опциями владеет SettingsService (setSettings +
-- событие Loaded). Сохранение: PlayerRemoving и BindToClose. Без API-доступа
-- (Studio без «Enable Studio Access to API Services») деградирует в дефолты
-- с warn — игра работает, просто без памяти между сессиями.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SettingsSchema = require(ReplicatedStorage:WaitForChild("SettingsSchema"))

local STORE_NAME = "PlayerData_v1"

local PlayerData = {}

export type Record = {
	settings: { [string]: any },
	stats: { zombies: number, wins: number },
}

local store: GlobalDataStore? = nil
do
	local ok, s = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = s
	else
		warn("[PlayerData] DataStore недоступен (нет API-доступа?): " .. tostring(s))
	end
end

local records: { [Player]: Record } = {}
local closing = false

local loadedEvent = Instance.new("BindableEvent")
PlayerData.Loaded = loadedEvent.Event -- (player) — запись загружена (или дефолты)

local function keyFor(player: Player): string
	return "u" .. player.UserId
end

local function defaultRecord(): Record
	return { settings = SettingsSchema.defaults(), stats = { zombies = 0, wins = 0 } }
end

-- Всегда возвращает запись (дефолты, пока грузится или если игрок уже ушёл).
function PlayerData.get(player: Player): Record
	return records[player] or defaultRecord()
end

function PlayerData.isLoaded(player: Player): boolean
	return records[player] ~= nil
end

function PlayerData.setSettings(player: Player, s: { [string]: any })
	local rec = records[player]
	if rec then
		rec.settings = s
	end
end

local function load(player: Player)
	local rec = defaultRecord()
	if store then
		local ok, data = pcall(function()
			return (store :: GlobalDataStore):GetAsync(keyFor(player))
		end)
		if ok and type(data) == "table" then
			if type(data.settings) == "table" then
				rec.settings = SettingsSchema.sanitize(data.settings)
			end
			if type(data.stats) == "table" then
				rec.stats.zombies = tonumber(data.stats.zombies) or 0
				rec.stats.wins = tonumber(data.stats.wins) or 0
			end
		elseif not ok then
			warn("[PlayerData] Загрузка " .. player.Name .. " не удалась: " .. tostring(data))
		end
	end
	if player.Parent == nil then
		return -- ушёл, пока грузили
	end
	records[player] = rec
	-- сидируем атрибуты-счётчики: дальше их растят ZombieSpawner/MatchManager
	player:SetAttribute("ZombiesDefeated", rec.stats.zombies)
	player:SetAttribute("Wins", rec.stats.wins)
	loadedEvent:Fire(player)
end

local function save(player: Player)
	local rec = records[player]
	if not (rec and store) then
		return
	end
	-- статы читаем из атрибутов — там живые значения
	rec.stats.zombies = (player:GetAttribute("ZombiesDefeated") :: number?) or rec.stats.zombies
	rec.stats.wins = (player:GetAttribute("Wins") :: number?) or rec.stats.wins
	local ok, err = pcall(function()
		-- SetAsync (last-writer-wins): игрок в один момент на одном сервере,
		-- конфликтов записей у этой игры нет
		(store :: GlobalDataStore):SetAsync(keyFor(player), rec)
	end)
	if not ok then
		warn("[PlayerData] Сохранение " .. player.Name .. " не удалось: " .. tostring(err))
	end
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(load, player)
end)
for _, p in Players:GetPlayers() do
	task.spawn(load, p)
end

Players.PlayerRemoving:Connect(function(player)
	if not closing then
		save(player) -- при шатдауне сохраняет BindToClose, не дублируем запись
	end
	records[player] = nil
end)

game:BindToClose(function()
	closing = true
	for _, p in Players:GetPlayers() do
		save(p)
	end
end)

print("[PlayerData] Персистентность: DataStore " .. (store and "подключён" or "НЕДОСТУПЕН (дефолты)") .. ".")

return PlayerData
