--!strict
-- LocalScript: StarterPlayerScripts.AudioController
-- Роутит звуки по SoundGroups (ReplicatedStorage.Audio) и применяет громкости.
--   • музыка (DrivingMusic) → Music
--   • мотор (Rev, A-Chassis) → Engine
--   • прочие звуки под SoundService (чекпоинт/финиш/крылья мыши) → SFX
-- Турельный выстрел роутится в самом TurretAimClient (он в workspace, не тут).
-- Серверный эмбиент/зомби пока не сгруппированы (позиционные в workspace) — TODO.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local CollectionService = game:GetService("CollectionService")

local Audio = require(ReplicatedStorage:WaitForChild("Audio"))
local SettingsSchema = require(ReplicatedStorage:WaitForChild("SettingsSchema"))

-- // Роутинг звуков под SoundService (музыка + разовые SFX) ------------------
local function routeServiceSound(s: Instance)
	if not s:IsA("Sound") then
		return
	end
	if s.Name == "DrivingMusic" then
		s.SoundGroup = Audio.Music
	elseif s.SoundGroup == nil then
		s.SoundGroup = Audio.SFX
	end
end
for _, s in SoundService:GetChildren() do
	routeServiceSound(s)
end
SoundService.ChildAdded:Connect(routeServiceSound)

-- // Роутинг мотора (Rev создаётся на DriveSeat в рантайме при FE) -----------
local function routeVehicle(v: Instance)
	if not v:IsA("Model") then
		return
	end
	local function tag(d: Instance)
		if d:IsA("Sound") and d.Name == "Rev" then
			d.SoundGroup = Audio.Engine
		end
	end
	for _, d in v:GetDescendants() do
		tag(d)
	end
	v.DescendantAdded:Connect(tag)
end
for _, v in CollectionService:GetTagged("PlayerVehicle") do
	routeVehicle(v)
end
CollectionService:GetInstanceAddedSignal("PlayerVehicle"):Connect(routeVehicle)

-- // Применение громкостей ---------------------------------------------------
-- стартуем с дефолтов схемы (= согласованный баланс); OptionsMenu и PushSettings
-- (загрузка из DataStore, будет позже) обновят под предпочтения игрока.
Audio.apply(SettingsSchema.defaults())

local remotes = ReplicatedStorage:WaitForChild("Remotes")
remotes:WaitForChild("PushSettings").OnClientEvent:Connect(function(s)
	if type(s) == "table" then
		Audio.apply(s)
	end
end)
