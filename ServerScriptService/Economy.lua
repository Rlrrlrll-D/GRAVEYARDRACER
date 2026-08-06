--!strict
-- ModuleScript: ServerScriptService.Economy
-- ВНУТРЕННЯЯ ВАЛЮТА «КОСТИ» — единственное место, где баланс растёт и тратится.
--
-- Сами кости живут в АТРИБУТЕ игрока `Bones` — ровно тем же приёмом, что уже
-- работает у `ZombiesDefeated` и `Wins`: атрибут реплицируется клиенту сам (HUD и
-- магазин читают его без единого ремоута), а `PlayerData` сидирует его при входе и
-- забирает обратно при сохранении.
--
-- ПОЧЕМУ ОТДЕЛЬНЫЙ МОДУЛЬ, А НЕ ПРОСТО SetAttribute ПО МЕСТУ:
--   * начисление в одном месте — значит, множитель «двойные кости» (game pass)
--     не надо вставлять в каждый скрипт, он живёт здесь;
--   * трата обязана быть атомарной проверкой «хватает ли» + списанием, иначе
--     двойной клик в магазине купит товар дважды за одну цену;
--   * баланс никогда не уходит в минус и не становится дробным.
--
-- НИКАКИХ РЕМОУТОВ ЗДЕСЬ НЕТ И БЫТЬ НЕ ДОЛЖНО. Клиент не начисляет и не тратит —
-- он только читает атрибут. Магазин зовёт `spend` уже на сервере, проверив товар.

local Players = game:GetService("Players")

local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local Economy = {}

local ATTR = "Bones"
local MULT_ATTR = "BonesMultiplier" -- ставит ShopService по владению пропуском

-- Сколько ждём загрузку записи, прежде чем начислять. Без этого кости, заработанные
-- в первые секунды сессии, затёрло бы сидирование из DataStore.
local LOAD_WAIT = 20

function Economy.balance(player: Player): number
	return (player:GetAttribute(ATTR) :: number?) or 0
end

local function set(player: Player, value: number)
	player:SetAttribute(ATTR, math.max(0, math.floor(value)))
end

-- Множитель начисления. Пропуска нет — единица; ShopService выставляет атрибут
-- при входе, проверив владение.
function Economy.multiplier(player: Player): number
	local m = (player:GetAttribute(MULT_ATTR) :: number?) or 1
	return math.clamp(m, 1, 10)
end

-- Начислить. reason идёт только в лог — экономику надо будет читать по записям.
-- Возвращает новый баланс (или текущий, если игрок уже ушёл).
function Economy.award(player: Player, amount: number, reason: string): number
	amount = math.floor(amount)
	if amount <= 0 then
		return Economy.balance(player)
	end
	local gain = math.floor(amount * Economy.multiplier(player))

	if not PlayerData.isLoaded(player) then
		-- Запись ещё грузится: досчитаем, когда приедет. Начислить сейчас нельзя —
		-- сидирование атрибута из DataStore затрёт наше значение.
		task.spawn(function()
			local deadline = os.clock() + LOAD_WAIT
			while player.Parent and not PlayerData.isLoaded(player) and os.clock() < deadline do
				task.wait(0.25)
			end
			if player.Parent and PlayerData.isLoaded(player) then
				set(player, Economy.balance(player) + gain)
			end
		end)
		return Economy.balance(player)
	end

	set(player, Economy.balance(player) + gain)
	return Economy.balance(player)
end

-- Списать. Возвращает true, только если денег хватило И они списаны.
-- Проверка и списание идут подряд без единого yield — между ними ничто не может
-- вклиниться, поэтому двойная покупка за одну цену невозможна.
function Economy.spend(player: Player, amount: number, reason: string): boolean
	amount = math.floor(amount)
	if amount <= 0 then
		return true
	end
	if not PlayerData.isLoaded(player) then
		return false -- на дефолтных нулях покупать нечего; и сохранить это некуда
	end
	local have = Economy.balance(player)
	if have < amount then
		return false
	end
	set(player, have - amount)
	print(("[Economy] %s: −%d костей (%s), осталось %d"):format(player.Name, amount, reason, have - amount))
	return true
end

-- Начислить всем сразу (конец заезда: участие/финиш).
function Economy.awardAll(players: { Player }, amount: number, reason: string)
	for _, p in players do
		if p.Parent then
			Economy.award(p, amount, reason)
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	if player:GetAttribute(ATTR) == nil then
		player:SetAttribute(ATTR, 0) -- чтобы HUD не ждал загрузки записи, показывая пустоту
	end
end)

return Economy
