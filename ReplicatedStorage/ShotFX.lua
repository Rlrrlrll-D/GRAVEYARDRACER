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
	if not start or stats.tracerWidth <= 0 then
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

-- ВСПЫШКА ВПЕРЕДИ ДУЛА, А НЕ НА НЁМ. Шар, центрованный на срезе, наполовину накрывал
-- ствол (юзер 2026-09-13: «вспышки должны рендериться под стволами»). Сдвигаем центр
-- вперёд на ~половину диаметра: шар только касается среза. Направление — ось люльки
-- (+X аттачмента Muzzle) или, для чужого выстрела, к первой точке попадания.
local function flashDir(source: Source, dir: Vector3?): Vector3?
	local d = dir
	if typeof(source) ~= "Vector3" then
		local a = source :: Attachment
		if a.Parent then
			d = a.WorldCFrame.RightVector
		end
	end
	if not d or d.Magnitude < 0.01 then
		return nil
	end
	return d.Unit
end

local function flashPoint(source: Source, origin: Vector3, dir: Vector3?, size: number): Vector3
	local d = flashDir(source, dir)
	if not d then
		return origin
	end
	return origin + d * (size * 0.45)
end

-- ЯЗЫК ОГНЯ (дробовик): вытянутый вдоль выстрела эллипсоид — Part со SpecialMesh
-- Sphere тянется по Size, в отличие от Ball; начало у среза, длина flashLength.
local function tongueCFrame(source: Source, origin: Vector3, dir: Vector3?, length: number): CFrame
	local d = flashDir(source, dir) or Vector3.zAxis
	local center = origin + d * (length * 0.5 - 0.1)
	return CFrame.lookAt(center, center + d)
end

function ShotFX.flash(source: Source, stats: Weapons.Stats, dir: Vector3?)
	local start0 = originOf(source)
	if not start0 then
		return
	end
	local start = flashPoint(source, start0, dir, stats.flashSize)
	-- Спрайт-свечение (дробовик): один невидимый якорь у дула, на нём билборды —
	-- внешнее мягкое свечение и малое ядро; свет тот же PointLight.
	if stats.flashSprite then
		local anchor = Instance.new("Part")
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(0.2, 0.2, 0.2)
		anchor.CFrame = CFrame.new(start)
		local function sprite(size: number, color: Color3)
			local bb = Instance.new("BillboardGui")
			bb.Size = UDim2.fromScale(size, size)
			bb.LightInfluence = 0
			bb.AlwaysOnTop = false
			bb.Parent = anchor
			local img = Instance.new("ImageLabel")
			img.BackgroundTransparency = 1
			img.Size = UDim2.fromScale(1, 1)
			img.Image = stats.flashSprite :: string
			img.ImageColor3 = color
			img.ImageTransparency = stats.flashTransparency or 0
			img.Parent = bb
		end
		sprite(stats.flashSize, stats.flashColor)
		if stats.flashCore then
			sprite(stats.flashCore.size, stats.flashCore.color)
		end
		local light = Instance.new("PointLight")
		light.Color = stats.flashColor
		light.Brightness = 6
		light.Range = 10 + 4 * stats.flashSize
		light.Parent = anchor
		anchor.Parent = workspace
		local life = stats.flashLife or FLASH_LIFE
		followMuzzle(source, life, function(origin)
			anchor.CFrame = CFrame.new(flashPoint(source, origin, dir, stats.flashSize))
		end)
		Debris:AddItem(anchor, life)
		return
	end
	local length = stats.flashLength
	local function ball(size: number, color: Color3): BasePart
		local b = Instance.new("Part")
		b.Anchored = true
		b.CanCollide = false
		b.CanQuery = false
		b.Material = Enum.Material.Neon
		b.Color = color
		b.Transparency = stats.flashTransparency or 0
		if length then
			-- эллипсоид: Ball не тянется, SpecialMesh Sphere — тянется по Size
			b.Shape = Enum.PartType.Block
			local m = Instance.new("SpecialMesh")
			m.MeshType = Enum.MeshType.Sphere
			m.Parent = b
			b.Size = Vector3.new(size, size, length)
			b.CFrame = tongueCFrame(source, start0, dir, length)
		else
			b.Shape = Enum.PartType.Ball
			b.Size = Vector3.new(size, size, size)
			b.CFrame = CFrame.new(start)
		end
		return b
	end
	local flash = ball(stats.flashSize, stats.flashColor)
	local light = Instance.new("PointLight")
	light.Color = stats.flashColor
	light.Brightness = 6
	light.Range = 10 + 4 * stats.flashSize -- радиус свечения растёт со вспышкой
	light.Parent = flash
	flash.Parent = workspace
	-- малое ядро внутри свечения (дробовик): та же плотность, свой цвет
	local core: BasePart? = nil
	local c = stats.flashCore
	if c then
		core = ball(c.size, c.color)
		core.Parent = workspace
	end
	local life = stats.flashLife or FLASH_LIFE
	followMuzzle(source, life, function(origin)
		if length then
			local cf = tongueCFrame(source, origin, dir, length)
			flash.CFrame = cf
			if core then
				core.CFrame = cf
			end
		else
			local p = flashPoint(source, origin, dir, stats.flashSize)
			flash.CFrame = CFrame.new(p)
			if core then
				core.CFrame = CFrame.new(p)
			end
		end
	end)
	Debris:AddItem(flash, life)
	if core then
		Debris:AddItem(core, life)
	end
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
	sound.RollOffMaxDistance = stats.soundRange or 220
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
	local origin = originOf(source)
	local dir = if origin and hits[1] then (hits[1] - origin) else nil
	ShotFX.flash(source, stats, dir)
	local origin = originOf(source)
	if origin then
		ShotFX.shot(origin, stats)
	end
end

return ShotFX
