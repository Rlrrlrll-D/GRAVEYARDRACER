--!strict
-- ModuleScript: ReplicatedStorage.ShotFX
-- ВИД И ЗВУК ВЫСТРЕЛА (только клиент): трассер, вспышка у дула, звук. Вынесено из
-- TurretAimClient 2026-09-12, чтобы тем же рисовала оружейная песочница гаража
-- (SkullTune: «закинь стволы в песочницу — посмотрю и послушаю»). Параметры вида —
-- в Weapons.Stats надетого ствола.
--
-- НАЧАЛО ТРАССЕРА ЕДЕТ С ДУЛОМ. Жалоба: «отстаёт точка выхода трассера у ствола,
-- совпадает только когда не движется». Так и было: трассер со вспышкой — АНКОРНЫЕ
-- детали в мировых координатах, поставленные по позиции дула в МОМЕНТ выстрела и
-- живущие 0.1 с. На 80 studs/с ствол за эту десятую уезжает на 8 studs, и начало
-- трассера остаётся висеть позади — стоя на месте расхождения нет вовсе.
-- Поэтому источник передаётся не точкой, а самим дулом (Attachment): пока эффект
-- жив, его начало каждый кадр берётся от текущего положения дула, а дальний конец
-- остаётся там, куда попали. Vector3 тоже принимается — им рисуются чужие выстрелы,
-- прилетевшие ремоутом: чужого дула у нас на руках нет.

local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Audio = require(ReplicatedStorage:WaitForChild("Audio"))
local Weapons = require(ReplicatedStorage:WaitForChild("Weapons"))

local ShotFX = {}

export type Source = Attachment | Vector3

local TRACER_LIFE = 0.1
local FLASH_LIFE = 0.05

local function originOf(source: Source): Vector3?
	if typeof(source) == "Vector3" then
		return source
	end
	local a = source :: Attachment
	return a.Parent and a.WorldPosition or nil
end

-- Держим эффект приклеенным к дулу на всё его недолгое время жизни.
local function followMuzzle(source: Source, life: number, place: (Vector3) -> ())
	if typeof(source) == "Vector3" then
		return -- чужой выстрел: следовать не за чем, точка и так статична
	end
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local origin = originOf(source)
		if not origin or os.clock() - t0 >= life then
			conn:Disconnect()
			return
		end
		place(origin)
	end)
end

function ShotFX.tracer(source: Source, hitPosition: Vector3, stats: Weapons.Stats)
	local start = originOf(source)
	if not start then
		return
	end
	local tracer = Instance.new("Part")
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CanQuery = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = stats.tracerColor -- пулемёт: кость (был янтарный)
	local w = stats.tracerWidth
	local function place(origin: Vector3)
		local distance = (hitPosition - origin).Magnitude
		tracer.Size = Vector3.new(w, w, distance)
		tracer.CFrame = CFrame.new(origin:Lerp(hitPosition, 0.5), hitPosition)
	end
	place(start)
	tracer.Parent = workspace
	followMuzzle(source, TRACER_LIFE, place)
	Debris:AddItem(tracer, TRACER_LIFE)
end

function ShotFX.flash(source: Source, stats: Weapons.Stats)
	local start = originOf(source)
	if not start then
		return
	end
	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Ball
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 220, 130)
	flash.Size = Vector3.new(stats.flashSize, stats.flashSize, stats.flashSize)
	flash.CFrame = CFrame.new(start)

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 210, 120)
	light.Brightness = 6
	light.Range = 14
	light.Parent = flash

	flash.Parent = workspace
	followMuzzle(source, FLASH_LIFE, function(origin)
		flash.CFrame = CFrame.new(origin)
	end)
	Debris:AddItem(flash, FLASH_LIFE)
end

-- Временный динамик в точке выстрела: звук позиционный, слышен всем клиентам.
local function speakerAt(position: Vector3): BasePart
	local speaker = Instance.new("Part")
	speaker.Anchored = true
	speaker.CanCollide = false
	speaker.CanQuery = false
	speaker.Transparency = 1
	speaker.Size = Vector3.new(0.2, 0.2, 0.2)
	speaker.CFrame = CFrame.new(position)
	return speaker
end

function ShotFX.shot(position: Vector3, stats: Weapons.Stats)
	local speaker = speakerAt(position)
	local sound = Instance.new("Sound")
	sound.SoundId = stats.soundId
	sound.Volume = stats.soundVolume
	sound.SoundGroup = Audio.SFX
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 8
	sound.RollOffMaxDistance = 220
	sound.PlaybackSpeed = stats.soundPitch * (0.95 + math.random() * 0.12) -- лёгкий разброс, чтобы очередь не звучала механически
	sound.Parent = speaker
	speaker.Parent = workspace
	sound:Play()
	Debris:AddItem(speaker, 2)
end

-- Щелчок осечки. Тише и с коротким хвостом: это механический звук самого оружия, а не
-- удар по окрестностям, и разноситься на две сотни studs ему незачем.
function ShotFX.dryFire(position: Vector3, soundId: string)
	local speaker = speakerAt(position)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = 0.7
	sound.SoundGroup = Audio.SFX
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 6
	sound.RollOffMaxDistance = 60
	sound.PlaybackSpeed = 0.97 + math.random() * 0.08
	sound.Parent = speaker
	speaker.Parent = workspace
	sound:Play()
	Debris:AddItem(speaker, 1)
end

-- Полный выстрел одним вызовом: трассер на каждую точку попадания, вспышка, звук.
function ShotFX.fire(source: Source, hits: { Vector3 }, stats: Weapons.Stats)
	for _, h in hits do
		ShotFX.tracer(source, h, stats)
	end
	ShotFX.flash(source, stats)
	local origin = originOf(source)
	if origin then
		ShotFX.shot(origin, stats)
	end
end

return ShotFX
