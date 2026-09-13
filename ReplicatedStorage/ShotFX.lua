--!strict
-- ModuleScript: ReplicatedStorage.ShotFX
-- ВИД И ЗВУК ВЫСТРЕЛА (только клиент): трассер, вспышка у дула (шар или язык огня с
-- ядром), звук. Вынесено из TurretAimClient 2026-09-12, чтобы тем же рисовала оружейная
-- песочница гаража. Параметры вида — в Weapons.Stats ствола.
--
-- ПУЛ И ОДИН ЦИКЛ (2026-09-13, телефон: «тормоза по нарастающей и пауза» после стволов).
-- Гатлинг — 15 выстрелов в секунду, дробовик — 8 трассеров за выстрел; на каждый
-- эффект создавались Part + PointLight + Sound и своё RenderStepped-подключение, а
-- Debris их сносил. На телефоне это мусор инстансов и GC каждый кадр. Теперь детали
-- эффектов живут в пулах и переиспользуются (Parent = nil между выстрелами, никаких
-- Destroy), а за всеми живыми эффектами следит ОДНО подключение RenderStepped.
--
-- НАЧАЛО ТРАССЕРА ЕДЕТ С ДУЛОМ. Трассер со вспышкой — анкорные детали в мировых
-- координатах; на 80 studs/с ствол за десятую секунды уезжает на 8 studs, и начало
-- трассера повисало бы позади. Поэтому источник передаётся не точкой, а самим дулом
-- (Attachment): пока эффект жив, его начало каждый кадр берётся от текущего положения
-- дула. Vector3 тоже принимается — чужие выстрелы приходят ремоутом точкой.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Audio = require(ReplicatedStorage:WaitForChild("Audio"))
local Weapons = require(ReplicatedStorage:WaitForChild("Weapons"))

local ShotFX = {}

export type Source = Attachment | Vector3

local TRACER_LIFE = 0.1
local FLASH_LIFE = 0.05
local POOL_CAP = 48 -- деталей одного вида держим не больше: лишние — Destroy
-- Телефон: дробь рисуем не всеми восемью трассерами, а тремя — пучок читается, а
-- деталей втрое меньше.
local MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local MOBILE_TRACERS = 3

local function originOf(source: Source): Vector3?
	if typeof(source) == "Vector3" then
		return source
	end
	local a = source :: Attachment
	return a.Parent and a.WorldPosition or nil
end

-- Направление наружу: ось люльки (+X аттачмента Muzzle) или, для чужого выстрела,
-- к первой точке попадания.
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

-- «Верх» у дула: ось Y люльки (аттачмент) или мировой верх для чужого выстрела.
local function flashUp(source: Source): Vector3
	if typeof(source) ~= "Vector3" then
		local a = source :: Attachment
		if a.Parent then
			return a.WorldCFrame.UpVector
		end
	end
	return Vector3.yAxis
end

-- ВСПЫШКА ВПЕРЕДИ ДУЛА, А НЕ НА НЁМ: шар, центрованный на срезе, наполовину накрывал
-- ствол. Сдвигаем центр вперёд на ~половину диаметра.
local function flashPoint(source: Source, origin: Vector3, dir: Vector3?, size: number): Vector3
	local d = flashDir(source, dir)
	if not d then
		return origin
	end
	return origin + d * (size * 0.45)
end

-- ЯЗЫК ОГНЯ (дробовик): вытянутый вдоль выстрела эллипсоид — Part со SpecialMesh
-- Sphere тянется по Size, в отличие от Ball; начало у среза, длина len.
local function tongueCFrame(source: Source, origin: Vector3, dir: Vector3?, len: number): CFrame
	local d = flashDir(source, dir) or Vector3.zAxis
	local center = origin + d * (len * 0.5 - 0.1)
	return CFrame.lookAt(center, center + d)
end

-- // Пулы ----------------------------------------------------------------------
local pools: { [string]: { BasePart } } = { tracer = {}, ball = {}, tongue = {}, speaker = {} }

local function newPart(): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

local function acquire(kind: string): BasePart
	local pool = pools[kind]
	local p = table.remove(pool)
	if p then
		return p
	end
	if kind == "tracer" then
		p = newPart()
		p.Name = "ShotTracer"
		p.Material = Enum.Material.Neon
	elseif kind == "ball" then
		p = newPart()
		p.Name = "ShotFlash"
		p.Shape = Enum.PartType.Ball
		p.Material = Enum.Material.Neon
		local light = Instance.new("PointLight")
		light.Parent = p
	elseif kind == "tongue" then
		p = newPart()
		p.Name = "ShotTongue"
		p.Material = Enum.Material.Neon
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
		local light = Instance.new("PointLight")
		light.Parent = p
	else
		p = newPart()
		p.Name = "ShotSpeaker"
		p.Transparency = 1
		p.Size = Vector3.new(0.2, 0.2, 0.2)
		local s = Instance.new("Sound")
		s.SoundGroup = Audio.SFX
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.Parent = p
	end
	return p
end

local function release(kind: string, p: BasePart)
	local pool = pools[kind]
	if #pool >= POOL_CAP then
		p:Destroy()
		return
	end
	p.Parent = nil
	table.insert(pool, p)
end

-- // Живые эффекты и один цикл --------------------------------------------------
type Live = { kind: string, part: BasePart, until_: number, place: ((Vector3) -> ())?, source: Source }
local live: { Live } = {}

local function add(kind: string, part: BasePart, life: number, source: Source, place: ((Vector3) -> ())?)
	table.insert(live, { kind = kind, part = part, until_ = os.clock() + life, place = place, source = source })
end

RunService.RenderStepped:Connect(function()
	if #live == 0 then
		return
	end
	local now = os.clock()
	for i = #live, 1, -1 do
		local e = live[i]
		if now >= e.until_ then
			release(e.kind, e.part)
			table.remove(live, i)
		elseif e.place then
			local origin = originOf(e.source)
			if origin then
				e.place(origin)
			end
		end
	end
end)

-- // Эффекты ---------------------------------------------------------------------
function ShotFX.tracer(source: Source, hitPosition: Vector3, stats: Weapons.Stats)
	local start = originOf(source)
	if not start or stats.tracerWidth <= 0 then
		return
	end
	local tracer = acquire("tracer")
	tracer.Color = stats.tracerColor
	local w = stats.tracerWidth
	local function place(origin: Vector3)
		local distance = (hitPosition - origin).Magnitude
		tracer.Size = Vector3.new(w, w, distance)
		tracer.CFrame = CFrame.new(origin:Lerp(hitPosition, 0.5), hitPosition)
	end
	place(start)
	tracer.Parent = workspace
	-- чужой выстрел (Vector3) не едет: следить не за чем
	add("tracer", tracer, TRACER_LIFE, source, if typeof(source) == "Vector3" then nil else place)
end

local function setLight(part: BasePart, color: Color3, brightness: number, range: number)
	local light = part:FindFirstChildOfClass("PointLight")
	if light then
		light.Color = color
		light.Brightness = brightness
		light.Range = range
		light.Enabled = brightness > 0
	end
end

function ShotFX.flash(source: Source, stats: Weapons.Stats, dir: Vector3?)
	local start0 = originOf(source)
	if not start0 then
		return
	end
	local length = stats.flashLength
	local life = stats.flashLife or FLASH_LIFE
	local follow = typeof(source) ~= "Vector3"

	-- шар или язык огня: одной функцией на вспышку и на ядро
	local function shape(size: number, color: Color3, len: number?, transparency: number, up: number): BasePart
		local kind = if len then "tongue" else "ball"
		local p = acquire(kind)
		p.Color = color
		p.Transparency = transparency
		if len then
			p.Size = Vector3.new(size, size, len)
			p.CFrame = tongueCFrame(source, start0, dir, len) + flashUp(source) * up
		else
			p.Size = Vector3.new(size, size, size)
			p.CFrame = CFrame.new(flashPoint(source, start0, dir, size) + flashUp(source) * up)
		end
		return p
	end

	local flash = shape(stats.flashSize, stats.flashColor, length, stats.flashTransparency or 0, 0)
	setLight(flash, stats.flashColor, stats.lightBrightness or 6, stats.lightRange or (10 + 4 * stats.flashSize))
	flash.Parent = workspace
	add(if length then "tongue" else "ball", flash, life, source, if follow then function(origin)
		if length then
			flash.CFrame = tongueCFrame(source, origin, dir, length)
		else
			flash.CFrame = CFrame.new(flashPoint(source, origin, dir, stats.flashSize))
		end
	end else nil)

	-- ядро (дробовик): копия формы своей длины, свой цвет, свой малый свет, над пламенем
	local c = stats.flashCore
	if c and c.size > 0 then
		local coreLen = c.length or length
		local coreUp = c.up or 0
		local core = shape(c.size, c.color, coreLen, 0, coreUp)
		setLight(core, c.color, c.light or 0, c.lightRange or 12)
		core.Parent = workspace
		add(if coreLen then "tongue" else "ball", core, life, source, if follow then function(origin)
			if coreLen then
				core.CFrame = tongueCFrame(source, origin, dir, coreLen) + flashUp(source) * coreUp
			else
				core.CFrame = CFrame.new(flashPoint(source, origin, dir, c.size) + flashUp(source) * coreUp)
			end
		end else nil)
	end
end

-- Звук из точки выстрела: динамик из пула, Sound переиспользуется (Play перезапускает).
local function playAt(position: Vector3, soundId: string, volume: number, pitch: number, minD: number, maxD: number, hold: number)
	local speaker = acquire("speaker")
	speaker.CFrame = CFrame.new(position)
	local sound = speaker:FindFirstChildOfClass("Sound") :: Sound
	if sound.SoundId ~= soundId then
		sound.SoundId = soundId
	end
	sound.Volume = volume
	sound.RollOffMinDistance = minD
	sound.RollOffMaxDistance = maxD
	sound.PlaybackSpeed = pitch
	speaker.Parent = workspace
	sound:Play()
	add("speaker", speaker, hold, position, nil)
end

function ShotFX.shot(position: Vector3, stats: Weapons.Stats)
	-- лёгкий разброс тона, чтобы очередь не звучала механически
	playAt(position, stats.soundId, stats.soundVolume, stats.soundPitch * (0.95 + math.random() * 0.12), 8, stats.soundRange or 220, 1.5)
end

-- Щелчок осечки: тише и с коротким хвостом — звук самого оружия, не удар по окрестностям.
function ShotFX.dryFire(position: Vector3, soundId: string)
	playAt(position, soundId, 0.7, 0.97 + math.random() * 0.08, 6, 60, 0.6)
end

-- Полный выстрел одним вызовом: трассер на каждую точку попадания, вспышка, звук.
function ShotFX.fire(source: Source, hits: { Vector3 }, stats: Weapons.Stats)
	local n = #hits
	local limit = if MOBILE and n > MOBILE_TRACERS then MOBILE_TRACERS else n
	for i = 1, limit do
		ShotFX.tracer(source, hits[i], stats)
	end
	local origin = originOf(source)
	local dir = if origin and hits[1] then (hits[1] - origin) else nil
	ShotFX.flash(source, stats, dir)
	if origin then
		ShotFX.shot(origin, stats)
	end
end

return ShotFX
