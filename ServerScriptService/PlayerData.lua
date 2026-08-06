--!strict
-- ModuleScript: ServerScriptService.PlayerData
-- Персистентность игрока: одна DataStore-запись на игрока:
--   { settings = { по SettingsSchema }, stats = { zombies = n, wins = n }, lock = {...} }
-- Статы живут в АТРИБУТАХ игрока (ZombiesDefeated растит ZombieSpawner, Wins —
-- MatchManager, leaderstats зеркалит): при входе сидируются из записи, при
-- сохранении читаются обратно. Опциями владеет SettingsService (setSettings +
-- событие Loaded). Без API-доступа (Studio без «Enable Studio Access to API
-- Services») деградирует в дефолты с warn — игра работает, просто без памяти.
--
-- ТРИ ЗАЩИТЫ, БЕЗ КОТОРЫХ ПРОГРЕСС ТЕРЯЕТСЯ (добавлены при подготовке к публикации):
--
-- 1. UpdateAsync вместо SetAsync. SetAsync пишет поверх того, что мы прочитали при
--    входе, и молча стирает всё, что легло в запись позже. UpdateAsync получает
--    СВЕЖЕЕ значение прямо перед записью.
-- 2. Замок сессии. Игрок, быстро перешедший на другой сервер, оказывается
--    одновременно на двух: старый сервер сохраняется последним и откатывает
--    прогресс. Теперь запись помечается id сервера, чужая свежая метка = не наша
--    запись, и мы её НЕ ТРОГАЕМ (owned=false → сохранения отключены совсем).
--    Метка старше LOCK_TIMEOUT считается брошенной — сервер умер, замок снимаем.
-- 3. Автосохранение. Раньше запись шла только на выходе игрока и в BindToClose;
--    падение сервера стирало всю сессию. Теперь ещё и раз в AUTOSAVE_INTERVAL.
--
-- Все обращения к DataStore идут через withRetry: сеть у Roblox рвётся регулярно,
-- одна неудачная попытка — это норма, а не повод потерять данные.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SettingsSchema = require(ReplicatedStorage:WaitForChild("SettingsSchema"))

local STORE_NAME = "PlayerData_v1"

local RETRIES = 4 -- попыток на один вызов DataStore
local LOCK_TIMEOUT = 90 -- сек: чужая метка старше — сервер считается умершим
local LOCK_TRIES = 5 -- сколько раз ждать, пока чужой сервер отпустит запись
local LOCK_STEP = 3 -- сек между попытками захвата
local AUTOSAVE_INTERVAL = 150 -- сек между фоновыми сохранениями
local CLOSE_DEADLINE = 25 -- сек: Roblox даёт на BindToClose около 30

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

-- Идентификатор сервера для замка. В Studio JobId пустой — там замок вырожденный,
-- но он и не нужен: сервер один.
local JOB = if RunService:IsStudio() or game.JobId == "" then "studio" else game.JobId

local records: { [Player]: Record } = {}
local owned: { [Player]: boolean } = {} -- захватили ли мы замок; без него НЕ сохраняем
local closing = false

local loadedEvent = Instance.new("BindableEvent")
PlayerData.Loaded = loadedEvent.Event -- (player) — запись загружена (или дефолты)

local function keyFor(player: Player): string
	return "u" .. player.UserId
end

local function defaultRecord(): Record
	return { settings = SettingsSchema.defaults(), stats = { zombies = 0, wins = 0 } }
end

-- // Обёртка над DataStore ----------------------------------------------------
-- Ждём бюджет, если он исчерпан: вызов сверх лимита не просто падает, а
-- надолго встаёт в очередь и роняет соседние запросы.
local function budgetOk(kind: Enum.DataStoreRequestType): boolean
	local ok, left = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(kind)
	end)
	return (not ok) or (left :: number) > 0 -- не смогли спросить — не мешаем
end

-- Возвращает (успех, результат). Успех true с результатом nil означает, что
-- транзакция сознательно отменена (функция-преобразователь вернула nil).
local function withRetry<T>(what: string, kind: Enum.DataStoreRequestType, fn: () -> T): (boolean, T?)
	local delay = 0.5
	for attempt = 1, RETRIES do
		if not budgetOk(kind) then
			task.wait(delay)
		end
		local ok, res = pcall(fn)
		if ok then
			return true, res
		end
		if attempt == RETRIES then
			warn("[PlayerData] " .. what .. " не удалось после " .. RETRIES .. " попыток: " .. tostring(res))
			return false, nil
		end
		task.wait(delay)
		delay *= 2
	end
	return false, nil
end

local function lockIsForeign(raw: any): boolean
	local lock = type(raw) == "table" and raw.lock
	if type(lock) ~= "table" then
		return false
	end
	if lock.job == JOB then
		return false
	end
	return os.time() - (tonumber(lock.at) or 0) < LOCK_TIMEOUT
end

local function recordFrom(raw: any): Record
	local rec = defaultRecord()
	if type(raw) == "table" then
		if type(raw.settings) == "table" then
			rec.settings = SettingsSchema.sanitize(raw.settings)
		end
		if type(raw.stats) == "table" then
			rec.stats.zombies = tonumber(raw.stats.zombies) or 0
			rec.stats.wins = tonumber(raw.stats.wins) or 0
		end
	end
	return rec
end

-- // Публичное ---------------------------------------------------------------
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

-- // Загрузка с захватом замка ------------------------------------------------
local function load(player: Player)
	local rec = defaultRecord()
	local got = false

	if store then
		local key = keyFor(player)
		for attempt = 1, LOCK_TRIES do
			if player.Parent == nil then
				return -- ушёл, пока ждали
			end
			local ok, raw = withRetry("захват записи " .. player.Name, Enum.DataStoreRequestType.UpdateAsync, function()
				return (store :: GlobalDataStore):UpdateAsync(key, function(old)
					if lockIsForeign(old) then
						return nil -- занято живым сервером — не трогаем совсем
					end
					local next_ = (type(old) == "table") and old or {}
					next_.lock = { job = JOB, at = os.time() }
					return next_
				end)
			end)
			if ok and raw ~= nil then
				rec = recordFrom(raw)
				got = true
				break
			end
			if attempt < LOCK_TRIES then
				task.wait(LOCK_STEP)
			end
		end
		if not got then
			-- Запись занята другим сервером и он её не отпустил. Играем на дефолтах
			-- и НИЧЕГО не сохраняем: перезапись затёрла бы живую сессию игрока.
			warn("[PlayerData] Запись " .. player.Name .. " занята другим сервером — сессия без сохранения.")
		end
	end

	if player.Parent == nil then
		return
	end
	records[player] = rec
	owned[player] = got
	-- сидируем атрибуты-счётчики: дальше их растят ZombieSpawner/MatchManager
	player:SetAttribute("ZombiesDefeated", rec.stats.zombies)
	player:SetAttribute("Wins", rec.stats.wins)
	loadedEvent:Fire(player)
end

-- // Сохранение ---------------------------------------------------------------
-- release=true снимает замок (игрок ушёл / сервер гасится).
local function save(player: Player, release: boolean)
	local rec = records[player]
	if not (rec and store and owned[player]) then
		return
	end
	-- статы читаем из атрибутов — там живые значения
	rec.stats.zombies = (player:GetAttribute("ZombiesDefeated") :: number?) or rec.stats.zombies
	rec.stats.wins = (player:GetAttribute("Wins") :: number?) or rec.stats.wins

	local key = keyFor(player)
	withRetry("сохранение " .. player.Name, Enum.DataStoreRequestType.UpdateAsync, function()
		return (store :: GlobalDataStore):UpdateAsync(key, function(old)
			if lockIsForeign(old) then
				return nil -- нас перехватили, пока играли: чужое не портим
			end
			local next_ = (type(old) == "table") and old or {}
			next_.settings = rec.settings
			next_.stats = rec.stats
			next_.lock = if release then nil else { job = JOB, at = os.time() }
			return next_
		end)
	end)
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(load, player)
end)
for _, p in Players:GetPlayers() do
	task.spawn(load, p)
end

Players.PlayerRemoving:Connect(function(player)
	if not closing then
		save(player, true) -- при шатдауне сохраняет BindToClose, не дублируем запись
	end
	records[player] = nil
	owned[player] = nil
end)

-- Фоновое сохранение: падение сервера теперь стоит не больше AUTOSAVE_INTERVAL.
-- Игроки идут по одному с паузой — залп из десяти записей выест бюджет DataStore.
task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		if closing then
			break
		end
		for _, p in Players:GetPlayers() do
			if records[p] and owned[p] then
				save(p, false)
				task.wait(0.5)
			end
		end
	end
end)

game:BindToClose(function()
	closing = true
	-- Игроков сохраняем параллельно: последовательно десять человек в лимит
	-- шатдауна не укладываются.
	local left = 0
	for _, p in Players:GetPlayers() do
		left += 1
		task.spawn(function()
			save(p, true)
			left -= 1
		end)
	end
	local t0 = os.clock()
	while left > 0 and os.clock() - t0 < CLOSE_DEADLINE do
		task.wait(0.1)
	end
end)

print("[PlayerData] Персистентность: DataStore " .. (store and "подключён" or "НЕДОСТУПЕН (дефолты)") .. ", замок сессии + автосохранение " .. AUTOSAVE_INTERVAL .. "с.")

return PlayerData
