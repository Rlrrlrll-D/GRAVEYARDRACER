--!strict
-- ModuleScript: ServerScriptService.Badges
-- ЗНАЧКИ ЗА ДОСТИЖЕНИЯ. Один список и одна точка выдачи: где именно значок
-- заслужен, решают MatchManager и ZombieSpawner, а КАК его выдать — только этот
-- модуль.
--
-- ID ЗАВОДЯТСЯ РУКАМИ на Creator Dashboard, кодом их создать нельзя. Пока стоит 0,
-- значок считается ненастроенным: выдача молча пропускается, никаких ошибок в лог.
-- Впиши номер — значок начнёт выдаваться сам.
--
-- ПОЧЕМУ ВЫДАЧА ВСЕГДА В ОТДЕЛЬНОМ ПОТОКЕ. `AwardBadge` и `UserHasBadgeAsync` —
-- сетевые вызовы, они ЙИЛДЯТ. Позвать их прямо из подсчёта итогов заезда значит
-- подвесить весь матч на время ответа Roblox (а он может и не прийти). Поэтому
-- award() возвращается немедленно, а сама выдача уходит в task.spawn.
--
-- ПОЧЕМУ СНАЧАЛА СПРАШИВАЕМ, ЕСТЬ ЛИ ЗНАЧОК. У AwardBadge жёсткий лимит на сервер;
-- повторная выдача уже имеющегося значка тратит его впустую. Ответ кэшируем на
-- сессию — второй раз за игру спрашивать не о чем.

local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")

local Badges = {}

-- Ключ → id значка с Dashboard. Ноль = ещё не заведён.
--
-- НОМЕРА СВЕРЕНЫ ПО API, А НЕ ВПИСАНЫ НА ВЕРУ (2026-08-11). Dashboard показывает значки
-- НОВЫМИ СВЕРХУ, то есть в порядке, обратном созданию, — и список пришёл именно в таком
-- виде. Впиши я его как есть, First Ride выдавался бы за сотню зомби.
-- Проверка на будущее: badges.roblox.com/v1/badges/<id> отдаёт name и description
-- публично, без авторизации. Перепутанный значок иначе не проявится ничем — выдача
-- пройдёт успешно, просто не за то.
Badges.Ids = {
	first_race = 1492362140274498, -- доехал до финиша первый раз
	first_win = 2706944826388815, -- первая победа
	ten_wins = 1871814996659084, -- десять побед
	hundred_zombies = 1256716160538986, -- сотня задавленных и расстрелянных
} :: { [string]: number }

-- Что писать в описании значка на Dashboard — держим рядом с ключом, чтобы при
-- заведении не выдумывать заново и чтобы текст в игре и на сайте не разошёлся.
Badges.Blurbs = {
	first_race = "Finish a race for the first time.",
	first_win = "Win your first race in the graveyard.",
	ten_wins = "Win ten races. The dead know your name.",
	hundred_zombies = "Put a hundred zombies back in the ground.",
} :: { [string]: string }

-- Кэш «значок уже есть» на сессию: { [player] = { [key] = true } }
local has: { [Player]: { [string]: boolean } } = {}

Players.PlayerRemoving:Connect(function(player)
	has[player] = nil
end)

-- Выдать значок. Возвращается сразу; сама выдача идёт фоном.
function Badges.award(player: Player, key: string)
	local id = Badges.Ids[key]
	if not id or id == 0 then
		return -- значок ещё не заведён на Dashboard — это не ошибка
	end
	local mine = has[player]
	if mine and mine[key] then
		return
	end

	task.spawn(function()
		if not player.Parent then
			return
		end
		local okHas, owns = pcall(function()
			return BadgeService:UserHasBadgeAsync(player.UserId, id)
		end)
		if okHas and owns then
			has[player] = has[player] or {}
			;(has[player] :: { [string]: boolean })[key] = true
			return
		end
		if not player.Parent then
			return
		end
		local okAward, granted = pcall(function()
			return BadgeService:AwardBadge(player.UserId, id)
		end)
		if okAward and granted then
			has[player] = has[player] or {}
			;(has[player] :: { [string]: boolean })[key] = true
			print(("[Badges] %s получил значок «%s»."):format(player.Name, key))
		elseif okAward then
			-- ВЫЗОВ ПРОШЁЛ, А ЗНАЧОК НЕ ВЫДАН. Именно так выглядит неверный id: Roblox
			-- не бросает ошибку, а спокойно возвращает false, и без этой строки опечатка
			-- в номере не проявилась бы НИКАК — значок просто никогда бы не появлялся.
			-- Сюда же попадает выдача из Studio (там она штатно не работает) и
			-- выключённый значок на Dashboard.
			warn(("[Badges] Значок «%s» (id %d) не выдан игроку %s: Roblox вернул false. Проверь номер и что значок включён."):format(key, id, player.Name))
		else
			warn(("[Badges] Выдача «%s» игроку %s упала: %s"):format(key, player.Name, tostring(granted)))
		end
	end)
end

local configured, total = 0, 0
for _, id in Badges.Ids do
	total += 1
	if id ~= 0 then
		configured += 1
	end
end
print(("[Badges] Значки: %d настроено из %d."):format(configured, total))

return Badges
