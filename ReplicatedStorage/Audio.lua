--!strict
-- ModuleScript: ReplicatedStorage.Audio
-- Клиентский аудио-микшер. Создаёт SoundGroups под SoundService и применяет
-- пользовательские громкости. Звуки попадают в группу через sound.SoundGroup
-- (роутит AudioController). Иерархия: Master → Music / Engine / SFX.
-- Слайдеры опций (OptionsMenu) двигают Volume этих групп; итоговая громкость
-- звука = sound.Volume × groupVolume × Master.Volume.

local SoundService = game:GetService("SoundService")

local Audio = {}

local function ensure(name: string, parent: Instance): SoundGroup
	local g = parent:FindFirstChild(name)
	if g and g:IsA("SoundGroup") then
		return g
	end
	local ng = Instance.new("SoundGroup")
	ng.Name = name
	ng.Volume = 1
	ng.Parent = parent
	return ng
end

Audio.Master = ensure("Master", SoundService)
Audio.Music = ensure("Music", Audio.Master)
Audio.Engine = ensure("Engine", Audio.Master)
Audio.SFX = ensure("SFX", Audio.Master)

-- применить настройки громкости (0..1) к группам
function Audio.apply(s: { [string]: any })
	Audio.Master.Volume = tonumber(s.masterVolume) or 1
	Audio.Music.Volume = tonumber(s.musicVolume) or 1
	Audio.Engine.Volume = tonumber(s.engineVolume) or 1
	Audio.SFX.Volume = tonumber(s.sfxVolume) or 1
end

return Audio
