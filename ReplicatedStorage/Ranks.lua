--!strict
-- ModuleScript: ReplicatedStorage.Ranks
-- РАНГ ИГРОКА — чистая функция от статов, которые PlayerData и так хранит
-- (ZombiesDefeated, Wins). Отдельного поля в записи нет и не нужно: ранг нельзя
-- купить, подарить или потерять, он только пересчитывается. Пороги и цена победы —
-- в GameConfig.Ranks (PLAN_SHOP §4).
--
-- Модуль общий: сервер по нему гейтит витрину (ShopService), клиент — рисует ранг в
-- лобби и на экране итогов. Оба считают по атрибутам игрока: они реплицируются,
-- поэтому у клиента и сервера ответ один и тот же без единого ремоута.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))

local Ranks = {}

export type Tier = { name: string, points: number }

export type Standing = {
	index: number, -- номер ранга, 1 = первый
	name: string,
	points: number, -- очков у игрока
	nextName: string?, -- следующий ранг; nil = выше некуда
	nextPoints: number?, -- его порог
	remaining: number?, -- сколько очков до него
}

local tiers: { Tier } = GameConfig.Ranks.Tiers

Ranks.Tiers = tiers

function Ranks.points(zombies: number, wins: number): number
	return math.max(0, math.floor(zombies)) + GameConfig.Ranks.WinPoints * math.max(0, math.floor(wins))
end

-- Номер ранга по очкам: последний порог, который взят. Пороги идут по возрастанию,
-- первый — с нуля, так что ответ всегда ≥ 1.
function Ranks.tierIndex(points: number): number
	local index = 1
	for i, tier in tiers do
		if points >= tier.points then
			index = i
		else
			break
		end
	end
	return index
end

function Ranks.standing(points: number): Standing
	local index = Ranks.tierIndex(points)
	local nextTier = tiers[index + 1]
	return {
		index = index,
		name = tiers[index].name,
		points = points,
		nextName = nextTier and nextTier.name or nil,
		nextPoints = nextTier and nextTier.points or nil,
		remaining = nextTier and (nextTier.points - points) or nil,
	}
end

-- По атрибутам игрока — одинаково на сервере и на клиенте. До загрузки записи
-- атрибутов нет: тогда это нулевой ранг, а не ошибка.
function Ranks.forPlayer(player: Player): Standing
	local zombies = (player:GetAttribute("ZombiesDefeated") :: number?) or 0
	local wins = (player:GetAttribute("Wins") :: number?) or 0
	return Ranks.standing(Ranks.points(zombies, wins))
end

-- Строка прогресса для лобби и экрана итогов: «PALLBEARER  ·  45 TO GRAVE ROBBER»,
-- на верхнем ранге — одно имя. Формат один на оба экрана, чтобы не разъехались.
function Ranks.progressLine(name: string, nextName: string?, remaining: number?): string
	if nextName and remaining then
		return string.format("%s  ·  %d TO %s", name, math.max(0, remaining), nextName)
	end
	return name
end

-- Номер ранга по имени (для гейтов в каталоге: «не ниже PALLBEARER»).
function Ranks.indexOf(name: string): number?
	for i, tier in tiers do
		if tier.name == name then
			return i
		end
	end
	return nil
end

return Ranks
