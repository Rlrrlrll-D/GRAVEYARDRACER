-- LocalScript: StarterPlayerScripts.DecorPreload
-- Фон-прелоад мешей карты. Roblox подгружает ГЕОМЕТРИЮ/ТЕКСТУРУ меша при первом
-- показе камерой — отсюда рывки «на участках трассы» (въехал в новую зону с
-- надгробиями/деревьями → кадр грузит их меши → фриз). Прогреваем всё разом в
-- начале, пока игрок под заставкой, чтобы в заезде дороги не спотыкались.
--
-- Список ассетов даёт СЕРВЕР (ReplicatedStorage.DecorAssets, собирает MapBuilder):
-- под StreamingEnabled в клиентском workspace лежит только ближний кусок карты,
-- так что собрать список по workspace нельзя — прогрелся бы только старт, а
-- фризы остались бы ровно там, где они и были: при въезде в новый участок.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

task.spawn(function()
	local holder = ReplicatedStorage:WaitForChild("DecorAssets", 60)
	if not holder or not holder:IsA("StringValue") then
		return
	end

	local urls: { string } = {}
	for id in holder.Value:gmatch("[^\n]+") do
		table.insert(urls, id)
	end
	if #urls == 0 then
		return
	end

	pcall(function()
		ContentProvider:PreloadAsync(urls)
	end)
end)
