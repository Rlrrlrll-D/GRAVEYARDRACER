--!strict
-- LocalScript: StarterPlayerScripts.UIController
-- Builds the HUD at runtime and keeps it in sync via Remotes.UpdateStats.
-- Also handles the CameraShake remote for hazard collisions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local updateStats = remotes:WaitForChild("UpdateStats") :: RemoteEvent
local cameraShakeEvent = remotes:WaitForChild("CameraShake") :: RemoteEvent
local raceUpdate = remotes:WaitForChild("RaceUpdate") :: RemoteEvent
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))

local player = Players.LocalPlayer

-- Чекпоинт (юзер: «поменяй звук прохода чекпоинтов на что-нибудь ghost-образное»).
-- Был волшебный звон Twinkle08 — сказочный, из другой игры. Теперь «Eerie Whispering,
-- Reverberant» (ProSoundEffects, 2.3с): шёпот с эхом, будто на скорости проскочил
-- сквозь кого-то. Длительность выбрана не на слух: чекпоинтов 12 на 3128 studs, то
-- есть на скорости они идут раз в ~2.9с — звук длиннее наложился бы сам на себя.
local SoundService = game:GetService("SoundService")
local checkpointSound = Instance.new("Sound")
checkpointSound.SoundId = "rbxassetid://9114228524"
checkpointSound.Volume = 0.6
checkpointSound.Parent = SoundService

local finishSound = Instance.new("Sound")
finishSound.SoundId = "rbxassetid://4961240438" -- грозовой раскат: драматичный крип-стинг на финиш
finishSound.Volume = 0.7
finishSound.Parent = SoundService

-- Предзагрузка звуков — чтобы чекпоинт/финиш не молчали при первом срабатывании.
task.spawn(function()
	pcall(function()
		game:GetService("ContentProvider"):PreloadAsync({ checkpointSound, finishSound })
	end)
end)
local lastCheckpointIndex: number? = nil
local playerGui = player:WaitForChild("PlayerGui")

-- // Build UI ------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GraveyardHUD"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local healthBg = Instance.new("Frame")
healthBg.Name = "HealthBackground"
healthBg.Size = UDim2.new(0, 220, 0, 24)
healthBg.Position = UDim2.new(1, -240, 0, 20) -- верх-ПРАВО (симметрично слева); LIVES под ним
healthBg.BackgroundColor3 = UITheme.PanelBg
healthBg.Parent = screenGui

local healthFill = Instance.new("Frame")
healthFill.Name = "HealthFill"
healthFill.Size = UDim2.new(1, 0, 1, 0)
healthFill.BackgroundColor3 = UITheme.Palette.Red
healthFill.BorderSizePixel = 0
healthFill.Parent = healthBg

local healthLabel = Instance.new("TextLabel")
healthLabel.Size = UDim2.new(1, 0, 1, 0)
healthLabel.BackgroundTransparency = 1
healthLabel.TextColor3 = UITheme.Ink
healthLabel.Font = UITheme.Font
healthLabel.TextScaled = true
healthLabel.Text = "Health"
healthLabel.Parent = healthBg

local speedLabel = Instance.new("TextLabel")
speedLabel.Name = "Speedometer"
speedLabel.Size = UDim2.new(0, 220, 0, 30)
speedLabel.Position = UDim2.new(0, 20, 0, 20) -- верх-лево (SPEED сверху)
speedLabel.BackgroundTransparency = 0 -- непрозрачно: красный читается ровно как HealthFill
speedLabel.BackgroundColor3 = UITheme.cycleColor(1) -- красный
speedLabel.TextColor3 = UITheme.Ink
speedLabel.Font = UITheme.Font
speedLabel.TextScaled = true
speedLabel.Text = "0 mph"
speedLabel.Parent = screenGui

local zombieLabel = Instance.new("TextLabel")
zombieLabel.Name = "ZombiesDefeated"
zombieLabel.Size = UDim2.new(0, 220, 0, 30)
zombieLabel.Position = UDim2.new(0, 20, 0, 52) -- верх-лево, под SPEED
zombieLabel.BackgroundTransparency = 0
zombieLabel.BackgroundColor3 = UITheme.cycleColor(2) -- тёмно-зелёный
zombieLabel.TextColor3 = UITheme.Ink
zombieLabel.Font = UITheme.Font
zombieLabel.TextScaled = true
zombieLabel.Text = "Zombies Defeated: 0"
zombieLabel.Parent = screenGui

local livesLabel = Instance.new("TextLabel")
livesLabel.Name = "Lives"
livesLabel.Size = UDim2.new(0, 220, 0, 30)
livesLabel.Position = UDim2.new(1, -240, 0, 52) -- верх-ПРАВО, под HEALTH (симметрично ZOMBIES слева)
livesLabel.BackgroundTransparency = 0
livesLabel.BackgroundColor3 = UITheme.cycleColor(3) -- кость (светлая) → тёмный текст
livesLabel.TextColor3 = UITheme.Palette.Red
livesLabel.Font = UITheme.Font
livesLabel.TextScaled = true
livesLabel.Text = "Lives: ♥♥♥"
livesLabel.Parent = screenGui

local wreckedLabel = Instance.new("TextLabel")
wreckedLabel.Name = "WreckedBanner"
wreckedLabel.Size = UDim2.new(0, 420, 0, 60)
wreckedLabel.Position = UDim2.new(0.5, -210, 0.35, 0)
wreckedLabel.BackgroundTransparency = 0
wreckedLabel.BackgroundColor3 = UITheme.Palette.Red
wreckedLabel.TextColor3 = UITheme.Ink
wreckedLabel.Font = UITheme.Font
wreckedLabel.TextScaled = true
wreckedLabel.Text = "VEHICLE DESTROYED"
wreckedLabel.Visible = false
wreckedLabel.Parent = screenGui

-- // Race HUD --------------------------------------------------------------
local raceLabel = Instance.new("TextLabel")
raceLabel.Name = "RaceStatus"
raceLabel.Size = UDim2.new(0, 380, 0, 30)
raceLabel.Position = UDim2.new(0.5, -190, 0, 10)
raceLabel.BackgroundTransparency = 0.45
raceLabel.BackgroundColor3 = UITheme.PanelBg
raceLabel.TextColor3 = UITheme.Ink
raceLabel.Font = UITheme.Font
raceLabel.TextScaled = true
raceLabel.Text = ""
raceLabel.Parent = screenGui

local raceCenter = Instance.new("TextLabel")
raceCenter.Name = "RaceCenter"
raceCenter.Size = UDim2.new(0, 520, 0, 90)
raceCenter.Position = UDim2.new(0.5, -260, 0.2, 0)
raceCenter.BackgroundTransparency = 1
raceCenter.TextColor3 = Color3.fromRGB(255, 220, 120)
raceCenter.Font = UITheme.Font
raceCenter.TextScaled = true
raceCenter.TextStrokeTransparency = 0.4
raceCenter.Text = ""
raceCenter.Parent = screenGui

-- Стрелка-компас: крутится к СЛЕДУЮЩЕМУ чекпоинту относительно камеры.
-- На старте указывает на чекпоинт №1 — видно, в какую сторону ехать.
local arrowFrame = Instance.new("Frame")
arrowFrame.Name = "CheckpointArrow"
arrowFrame.AnchorPoint = Vector2.new(0.5, 0.5)
arrowFrame.Size = UDim2.new(0, 56, 0, 56)
arrowFrame.Position = UDim2.new(0.5, 0, 0.72, 0)
arrowFrame.BackgroundTransparency = 1
arrowFrame.Visible = false
arrowFrame.Parent = screenGui

for _, side in { -1, 1 } do -- шеврон "∧" из двух планок
	local wing = Instance.new("Frame")
	wing.AnchorPoint = Vector2.new(0.5, 0.5)
	wing.Size = UDim2.new(0, 7, 0, 30)
	wing.Position = UDim2.new(0.5, side * 9, 0.5, 6)
	wing.Rotation = side * 40
	wing.BackgroundColor3 = Color3.fromRGB(224, 214, 170) -- кость (был мятный)
	wing.BorderSizePixel = 0
	wing.Parent = arrowFrame
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 3)
	corner.Parent = wing
end

local arrowDistance = Instance.new("TextLabel")
arrowDistance.Name = "CheckpointDistance"
arrowDistance.AnchorPoint = Vector2.new(0.5, 0)
arrowDistance.Size = UDim2.new(0, 120, 0, 20)
arrowDistance.Position = UDim2.new(0.5, 0, 0.72, 34)
arrowDistance.BackgroundTransparency = 1
arrowDistance.TextColor3 = Color3.fromRGB(224, 214, 170)
arrowDistance.TextStrokeTransparency = 0.6
arrowDistance.Font = UITheme.Font
arrowDistance.TextScaled = true
arrowDistance.Visible = false
arrowDistance.Parent = screenGui

local arrowTargetIndex: number? = nil -- индекс чекпоинта, куда показывает стрелка

type RacePayload = {
	Phase: string,
	Countdown: number?,
	Go: boolean?,
	Lap: number?,
	Laps: number?,
	Position: number?,
	Racers: number?,
	NextCheckpoint: number?,
	PlayerWon: boolean?,
	Winner: string?,
	Eliminated: boolean?,
	Waiting: number?,
	Needed: number?,
}

-- // ПЛАШКА-ЧЕРЕП КАК НАСТОЯЩАЯ НЕОНОВАЯ ДЕТАЛЬ ------------------------------
--
-- Юзер: «ты можешь сделать плашку неоновой как стрелки?». Может — но только если
-- силуэт перестанет быть картинкой. Material = Neon есть у ДЕТАЛИ, у ImageLabel его
-- нет и быть не может, а блюм берёт лишь то, что ярче единицы (BloomEffect.Threshold
-- = 1.5 в этом плейсе): пиксель UI ярче 1.0 не бывает, потому у плашки и не было
-- ореола, сколько её ни высветляй.
--
-- Поэтому силуэт снят с исходника (ReplicatedStorage.SkullShape: 208 прямоугольников,
-- полученных из D:\VECTOR\skull.svg — который, вопреки расширению, оказался обёрткой
-- вокруг встроенного PNG) и собирается в МЕШ прямо на клиенте через EditableMesh.
-- Загружать ассет не нужно, верификация не нужна — проверено в этом плейсе.
--
-- ПОЧЕМУ НА КЛИЕНТЕ, а не на сервере: меш, построенный из EditableMesh, не
-- реплицируется — сервер собрал бы его себе, а игроки увидели бы пустоту. Сервер
-- поэтому держит только невидимый якорь (RaceScene), а вид навешивает каждый клиент.
local AssetService = game:GetService("AssetService")
local SKULL_COLOR = Color3.fromRGB(196, 228, 255) -- бело-голубой, как просил юзер
local SKULL_WIDTH = 2.6 -- ширина плашки в studs
local plateTemplate: BasePart? = nil
local plateTried = false

local function buildPlateTemplate(): BasePart?
	if plateTried then
		return plateTemplate
	end
	plateTried = true
	local okShape, shape = pcall(function()
		return require(ReplicatedStorage:WaitForChild("SkullShape", 10))
	end)
	if not okShape or type(shape) ~= "table" then
		warn("[UIController] SkullShape не найден — плашка-череп не собрана")
		return nil
	end
	local ok, part = pcall(function()
		local em = AssetService:CreateEditableMesh()
		local gw, gh = shape.GridW, shape.GridH
		local step = 1 / gw
		local halfT = step * 2 -- толщина плиты: тонкая, но не нулевая
		for _, r in shape.Rects do
			local x0 = (r[1] - gw / 2) * step
			local x1 = (r[1] + r[3] - gw / 2) * step
			-- в сетке Y растёт ВНИЗ, в мире — вверх
			local y0 = (gh / 2 - (r[2] + r[4])) * step
			local y1 = (gh / 2 - r[2]) * step
			for _, z in { halfT, -halfT } do
				local a = em:AddVertex(Vector3.new(x0, y0, z))
				local b = em:AddVertex(Vector3.new(x1, y0, z))
				local c = em:AddVertex(Vector3.new(x1, y1, z))
				local d = em:AddVertex(Vector3.new(x0, y1, z))
				if z > 0 then -- лицевая сторона против часовой, тыльная наоборот
					em:AddTriangle(a, b, c)
					em:AddTriangle(a, c, d)
				else
					em:AddTriangle(a, c, b)
					em:AddTriangle(a, d, c)
				end
			end
		end
		return AssetService:CreateMeshPartAsync(Content.fromObject(em))
	end)
	if not ok or typeof(part) ~= "Instance" then
		warn("[UIController] меш черепа не собрался: " .. tostring(part))
		return nil
	end
	local plate = part :: MeshPart
	plate.Name = "Plate"
	if plate.Size.X > 0 then
		plate.Size = plate.Size * (SKULL_WIDTH / plate.Size.X)
	end
	plate.Material = Enum.Material.Neon -- ровно как стрелки старта
	plate.Color = SKULL_COLOR
	plate.Transparency = 0.15 -- и ровно та же прозрачность
	plate.Anchored = true
	plate.CanCollide = false
	plate.CanQuery = false
	plate.CanTouch = false
	plate.CastShadow = false
	plateTemplate = plate
	return plate
end

-- Навесить плашку на череп, если её там ещё нет (у каждого клиента своя).
local function ensurePlate(model: Model): BasePart?
	local existing = model:FindFirstChild("Plate")
	if existing and existing:IsA("BasePart") then
		return existing
	end
	local template = buildPlateTemplate()
	if not template then
		return nil
	end
	local plate = template:Clone()
	plate.CFrame = model:GetPivot() -- стартовое; дальше каждый кадр ставит aimPlate
	plate.Parent = model
	return plate
end

-- Плашка — деталь, а не билборд, поэтому «лицом к камере» её ставим сами. Двенадцать
-- CFrame за кадр — цена никакая, зато силуэт всегда развёрнут к водителю, как и был.
-- roll (градусы) — закрутка вокруг оси взгляда, ею пользуется растворение.
local function aimPlate(model: Model, roll: number?)
	local plate = model:FindFirstChild("Plate")
	if not (plate and plate:IsA("BasePart")) then
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	-- Позицию берём ОТ ПИВОТА МОДЕЛИ, а не от самой плашки. Так надёжнее: плашка
	-- создаётся клиентом в произвольный момент, и в первом заходе она осталась в
	-- начале координат — модель к тому времени ещё не была на месте. Раз мы всё равно
	-- трогаем её CFrame каждый кадр, пусть он и задаёт положение: тогда любой сдвиг
	-- черепа (парение, улёт) плашка подхватывает сама.
	local pivot = model:GetPivot().Position
	local cf = CFrame.lookAt(pivot, cam.CFrame.Position)
	plate.CFrame = roll and (cf * CFrame.Angles(0, 0, math.rad(roll))) or cf
end

-- Плотность ведём ОДНОЙ величиной fade: 0 — как построено (неон 0.15), 1 — исчез.
local SKULL_BASE_ALPHA = 0.15
local function setSkullFade(model: Model, fade: number)
	local plate = ensurePlate(model)
	if plate then
		plate.Transparency = math.clamp(SKULL_BASE_ALPHA + (1 - SKULL_BASE_ALPHA) * fade, 0, 1)
	end
end

-- Найти маркер чекпоинта: череп помечен атрибутом cpN (один череп может обслуживать
-- несколько чекпоинтов при совпадении координат — перекрёсток восьмёрки); орб — по имени.
local function findMarker(index: number): Instance?
	local folder = workspace:FindFirstChild("RaceMarkers")
	if not folder then
		return nil
	end
	for _, m in folder:GetChildren() do
		if m:IsA("Model") and m:GetAttribute("cp" .. index) == true then
			return m
		end
	end
	return folder:FindFirstChild("Checkpoint" .. index)
end

-- Внешний вид плашки-черепа: «свой» следующий (active) — чуть крупнее и плотнее,
-- свет ярче; прочие — сильно полупрозрачные (призрачные), свет спокойный.
-- ПЛОТНОСТЬ ЧЕРЕПА. Прежние абзацы про «прозрачность плашки», билборд и ореолы
-- сняты вместе с самой плашкой: череп теперь неоновая геометрия (RaceScene).
-- Свой чекпоинт горит РОВНО как стрелки старта (fade = 0, то есть неон 0.15),
-- чужие приглушены. Дальше по трассе их дюжина, и если жечь все в полную силу,
-- горизонт превращается в гирлянду.
local SKULL_FADE_ACTIVE = 0 -- как построено: Neon 0.15 — один в один со стрелками
local SKULL_FADE_IDLE = 0.34 -- чужие чекпоинты — тот же неон, но приглушённый
local SKULL_PULSE = 0.07 -- амплитуда «дыхания» у своего чекпоинта
local SKULL_SCALE_ACTIVE = 1.22 -- свой ещё и крупнее: видно, к какому едешь

local skullHome: { [Model]: CFrame } = {} -- «дом» каждого черепа (парение + сброс после сбора)
local collecting: { [Model]: boolean } = {} -- череп сейчас «улетает» вверх → парение его не трогает
local function applySkullState(model: Model, active: boolean)
	if collecting[model] then return end -- «улетающий» череп не трогаем (иначе перебьёт растворение)
	setSkullFade(model, active and SKULL_FADE_ACTIVE or SKULL_FADE_IDLE)
	-- ScaleTo задаёт АБСОЛЮТНЫЙ масштаб, поэтому повторные вызовы не накапливаются
	model:ScaleTo(active and SKULL_SCALE_ACTIVE or 1)
end

-- ПРЕВРАЩЕНИЕ ЧЕРЕПА В ДЫМ. Запускается НА ПОДЛЁТЕ (цикл парения ниже), а не по
-- факту прохождения: на 60+ studs/с пройденный чекпоинт оказывается за спиной за
-- доли секунды, и всю анимацию игрок физически не видел. Теперь череп распадается,
-- пока он ещё в кадре, и машина проезжает сквозь облако. Проход по чекпоинту
-- остаётся страховочным триггером — если мимо черепа прошли по широкой дуге.
-- Для орба — no-op.
local transformed: { [number]: boolean } = {} -- этот чекпоинт уже распался в текущем заходе
local function collectSkull(index: number)
	if transformed[index] then return end -- дважды один череп не растворяем
	local marker = findMarker(index)
	if not (marker and marker:IsA("Model")) then return end
	local model = marker :: Model
	if collecting[model] then return end
	local anchor = model.PrimaryPart
	if not anchor then return end
	transformed[index] = true
	local home = skullHome[model] or model:GetPivot()

	-- «Улёт» анимируем на КЛИЕНТ-ЛОКАЛЬНОМ КЛОНЕ, а общий череп прячем локально.
	-- Общий череп — сетевой инстанс: в Team Test окно-хост = сервер, его парение
	-- реплицируется и перебивало твин улёта у второго игрока (у него анимация «не
	-- срабатывала»). Клон сервер не знает — его никто не перебьёт; у каждого одинаково.
	collecting[model] = true -- локальное парение общий череп не трогает (applySkullState тоже пропустит)
	setSkullFade(model, 1) -- спрятать общий череп локально на время улёта

	local ghost = model:Clone()
	for _, d in ghost:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy() -- клон чисто визуальный, скрипты не нужны
		end
	end
	ghost.Name = "GhostSkull"
	ghost:PivotTo(home)
	ghost.Parent = workspace -- вне RaceMarkers → цикл парения его не трогает; клиент-локально
	local gAnchor = ghost.PrimaryPart

	-- Юзер: «анимацию черепа при прохождении чека (дымок) сделай по S-образной
	-- траектории и быстрее». Было 1.0с по прямой вверх.
	local RISE = 0.6

	-- S-ОБРАЗНЫЙ УЛЁТ + РАСПАД. Прямой твин Position змейку не даёт — ведём вручную:
	-- вверх с разгоном, поперёк — одна полная синусоида (вправо-назад-влево-назад).
	-- Поперечную ось берём от КАМЕРЫ, иначе с половины ракурсов змейка уходит «в
	-- экран» и читается как прямая. Амплитуда к концу сходит на нет, череп при этом
	-- закручивается вокруг своей оси и сжимается — то есть на глазах превращается в
	-- струйку. Никаких частиц: любой размытый спрайт на этой сцене читается как пятно,
	-- превращается САМ ЧЕРЕП.
	if gAnchor then
		local cam = workspace.CurrentCamera
		local side = cam and cam.CFrame.RightVector or Vector3.xAxis
		side = Vector3.new(side.X, 0, side.Z)
		side = side.Magnitude > 1e-3 and side.Unit or Vector3.xAxis
		local twist = (math.random() < 0.5 and -1 or 1) * 46 -- градусы, закрутка плашки
		local startScale = ghost:GetScale()
		task.spawn(function()
			local t0 = os.clock()
			while ghost.Parent do
				local a = (os.clock() - t0) / RISE
				if a >= 1 then break end
				local up = 20 * a * a -- разгон вверх, как прежний Quad In
				local sway = math.sin(a * math.pi * 2) * 2.8 * (1 - a * 0.55)
				ghost:PivotTo(home + Vector3.new(0, up, 0) + side * sway)
				ghost:ScaleTo(math.max(0.12, startScale * (1 - a * 0.82)))
				aimPlate(ghost, twist * a) -- лицом к камере и с закруткой
				task.wait()
			end
		end)
	end

	-- гаснет не сразу: сначала видно, КАК он тянется, и только к концу исчезает
	local gPlate = ghost:FindFirstChild("Plate")
	if gPlate and gPlate:IsA("BasePart") then
		TweenService:Create(gPlate, TweenInfo.new(RISE, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
			{ Transparency = 1 }):Play()
	end

	task.delay(RISE + 0.2, function()
		ghost:Destroy()
		setSkullFade(model, SKULL_FADE_IDLE) -- снова виден к следующему кругу
		collecting[model] = nil
	end)
end

-- Подсветка СВОЕГО следующего чекпоинта — локально, у каждого игрока своя
local activeSkullIndex: number? = nil -- за каким черепом сейчас следит цикл подлёта
local function highlightCheckpoint(index: number?)
	local folder = workspace:FindFirstChild("RaceMarkers")
	if not folder then return end
	if activeSkullIndex ~= index then
		activeSkullIndex = index
		if index then
			transformed[index] = nil -- новый заход на этот чекпоинт: распад снова разрешён
		end
	end
	for _, marker in folder:GetChildren() do
		if marker:IsA("Model") then
			-- череп активен, если обслуживает текущий чекпоинт (атрибут cpN)
			local active = index ~= nil and marker:GetAttribute("cp" .. index) == true
			applySkullState(marker, active)
		elseif marker:IsA("BasePart") then
			local id = marker.Name:match("%d+")
			local i = id and tonumber(id)
			if i then
				local active = (i == index)
				marker.Transparency = active and 0.5 or 0.78 -- орб: спокойный ободок, ленты — основной визуал
				marker.Size = active and Vector3.new(4, 4, 4) or Vector3.new(3, 3, 3)
			end
		end
	end
end

-- Черепа-чекпоинты видны только во время гонки (отсчёт/заезд), а не в
-- «ожидании игроков» и не после финиша. markersVisible=nil — первый вызов всегда срабатывает.
local markersVisible: boolean? = nil
local function setMarkersVisible(visible: boolean)
	if markersVisible == visible then return end
	markersVisible = visible
	local folder = workspace:FindFirstChild("RaceMarkers")
	if not folder then return end
	for _, m in folder:GetChildren() do
		if m:IsA("Model") then
			local anchor = m.PrimaryPart
			if anchor then
				local face = anchor:FindFirstChild("Face")
				if face and face:IsA("BillboardGui") then face.Enabled = visible end
				local light = anchor:FindFirstChildOfClass("PointLight")
				if light then light.Enabled = visible end
				-- Spirit — залповый (Rate=0, Enabled=false), его трогать не нужно:
				-- он и так молчит, пока его не выстрелит анимация распада.
			end
		elseif m:IsA("BasePart") then
			m.LocalTransparencyModifier = visible and 0 or 1 -- орб: скрыть локально
			for _, e in m:GetChildren() do
				if e:IsA("Trail") or e:IsA("ParticleEmitter") then e.Enabled = visible end
			end
		end
	end
end

-- Парение черепов-чекпоинтов — локально у каждого клиента (server держит их
-- статичными). Первый кадр фиксирует «дом» (GetPivot), дальше — синусоида по Y.
-- Череп в процессе распада (collecting) не парит — им управляет collectSkull.
-- Здесь же ТРИГГЕР ПОДЛЁТА: как только «свой» череп ближе TRANSFORM_DIST, он
-- начинает превращаться в дым — чтобы анимацию было видно, а не угадывать по
-- облачку в зеркале. Расстояние подобрано так, чтобы облако успело раскрыться
-- к моменту, когда машина в него влетает (60+ studs/с × ~0.5с распада).
local TRANSFORM_DIST = 46
RunService.Heartbeat:Connect(function()
	local folder = workspace:FindFirstChild("RaceMarkers")
	if not folder then return end
	local t = os.clock()
	for _, m in folder:GetChildren() do
		if m:IsA("Model") and m.PrimaryPart and not collecting[m] then
			local home = skullHome[m]
			if not home then
				home = m:GetPivot()
				skullHome[m] = home
			end
			local id = m.Name:match("%d+")
			local phase = (id and tonumber(id) or 0) * 0.7
			local y = math.sin(t * 1.3 + phase) * 0.9
			m:PivotTo(home + Vector3.new(0, y, 0))
			aimPlate(m) -- плашка-деталь сама к камере не поворачивается
			-- «дыхание» плотности у своего черепа: живой, но всё равно воздушный
			local idx = activeSkullIndex
			if idx and m:GetAttribute("cp" .. idx) == true then
				setSkullFade(m, math.max(0, SKULL_FADE_ACTIVE + math.sin(t * 2.1) * SKULL_PULSE))
				local char = player.Character
				local root = char and char.PrimaryPart
				if root and (root.Position - home.Position).Magnitude < TRANSFORM_DIST then
					collectSkull(idx)
				end
			end
		end
	end
end)

-- анимация-«пружинка» центрального баннера (GO/победа/финиш)
local raceCenterScale = Instance.new("UIScale")
raceCenterScale.Parent = raceCenter
local function popCenter()
	raceCenterScale.Scale = 0.35
	TweenService:Create(
		raceCenterScale,
		TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
end

raceUpdate.OnClientEvent:Connect(function(data: RacePayload)
	if data.Phase == "Idle" then
		local waiting = data.Waiting or 0
		local needed = data.Needed or 1
		if needed > 1 and waiting > 0 and waiting < needed then
			raceLabel.Text = string.format("Waiting for racers… %d/%d — press READY", waiting, needed)
		elseif needed > 1 then
			raceLabel.Text = string.format("Press READY to race — need %d racers", needed)
		else
			raceLabel.Text = "Press READY to start the race"
		end
		raceCenter.Text = ""
		highlightCheckpoint(nil)
		arrowTargetIndex = nil
		setMarkersVisible(false) -- в ожидании гонки черепов не видно
	elseif data.Phase == "Countdown" then
		raceLabel.Text = string.format("Race: %d laps — follow the green beacons", data.Laps or 3)
		raceCenter.TextColor3 = Color3.fromRGB(255, 220, 120)
		raceCenter.Text = tostring(data.Countdown)
		setMarkersVisible(true) -- гонка начинается → черепа появляются
		arrowTargetIndex = 1 -- ещё на отсчёте показываем, куда стартовать
		highlightCheckpoint(1)
		lastCheckpointIndex = nil -- сброс, чтобы старт не звенел ложно
	elseif data.Phase == "Racing" then
		setMarkersVisible(true) -- на случай подключения в середине заезда
		if data.Go then
			raceCenter.Text = "GO!"
			task.delay(1.5, function()
				if raceCenter.Text == "GO!" then
					raceCenter.Text = ""
				end
			end)
		end
		raceLabel.Text = string.format("Lap %d/%d   ·   Position %d/%d",
			data.Lap or 1, data.Laps or 3, data.Position or 1, data.Racers or 4)
		if data.NextCheckpoint then
			if lastCheckpointIndex ~= nil and data.NextCheckpoint ~= lastCheckpointIndex then
				checkpointSound:Play() -- прошёл чекпоинт → магический звон
				collectSkull(lastCheckpointIndex) -- дух улетает вверх с пройденного черепа (орб — no-op)
			end
			lastCheckpointIndex = data.NextCheckpoint
			highlightCheckpoint(data.NextCheckpoint)
			arrowTargetIndex = data.NextCheckpoint
		end
	elseif data.Phase == "Finished" then
		arrowTargetIndex = nil
		setMarkersVisible(false) -- заезд окончен → прячем до следующего
		popCenter()
		finishSound:Play()
		if data.Eliminated then
			raceCenter.TextColor3 = UITheme.Palette.Red
			raceCenter.Text = "GAME OVER — OUT OF LIVES"
		elseif data.PlayerWon then
			raceCenter.TextColor3 = Color3.fromRGB(255, 210, 70) -- золото
			raceCenter.Text = "YOU WIN!"
		else
			raceCenter.TextColor3 = UITheme.Palette.Red
			raceCenter.Text = string.upper(data.Winner or "GHOST") .. " WINS"
		end
	end
end)

-- // Компас на следующий чекпоинт -------------------------------------------
local function checkpointPosition(index: number): Vector3?
	local marker = findMarker(index)
	if marker then
		if marker:IsA("BasePart") then
			return marker.Position
		elseif marker:IsA("Model") then
			local pp = (marker :: Model).PrimaryPart
			return pp and pp.Position or (marker :: Model):GetPivot().Position
		end
	end
	return nil
end

RunService.RenderStepped:Connect(function()
	local index = arrowTargetIndex
	local camera = workspace.CurrentCamera
	local target = index and checkpointPosition(index)
	if not target or not camera then
		arrowFrame.Visible = false
		arrowDistance.Visible = false
		return
	end

	local camCF = camera.CFrame
	local forward = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
	local toTarget = Vector3.new(target.X - camCF.Position.X, 0, target.Z - camCF.Position.Z)
	if forward.Magnitude < 0.05 or toTarget.Magnitude < 1 then
		return -- камера смотрит вертикально или чекпоинт под нами — оставляем как есть
	end
	forward = forward.Unit
	local dir = toTarget.Unit
	-- знаковый угол между взглядом камеры и целью в плоскости XZ;
	-- Rotation у GUI растёт по часовой, поэтому минус
	local crossY = forward.Z * dir.X - forward.X * dir.Z
	local dot = forward.X * dir.X + forward.Z * dir.Z
	arrowFrame.Rotation = -math.deg(math.atan2(crossY, dot))
	arrowDistance.Text = string.format("%d studs", math.floor(toTarget.Magnitude))
	arrowFrame.Visible = true
	arrowDistance.Visible = true
end)

-- // Live updates ---------------------------------------------------------
type StatsPayload = {
	Health: number,
	MaxHealth: number,
	Speed: number,
	Fuel: number,
	Lives: number?,
	ZombiesDefeated: number,
}

updateStats.OnClientEvent:Connect(function(stats: StatsPayload)
	local ratio = math.clamp(stats.Health / math.max(stats.MaxHealth, 1), 0, 1)
	TweenService:Create(healthFill, TweenInfo.new(0.2), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()
	healthLabel.Text = string.format("Health: %d / %d", stats.Health, stats.MaxHealth)
	speedLabel.Text = string.format("%d mph", math.floor(stats.Speed))
	zombieLabel.Text = string.format("Zombies Defeated: %d", stats.ZombiesDefeated)
	local lives = stats.Lives or 3
	livesLabel.Text = lives > 0 and ("Lives: " .. string.rep("♥", lives)) or "Lives: OUT"

	if stats.Health <= 0 then
		if lives > 0 then
			wreckedLabel.Text = string.format("VEHICLE DESTROYED — %d left", lives)
			wreckedLabel.TextColor3 = UITheme.Ink
		else
			wreckedLabel.Text = "GAME OVER"
			wreckedLabel.TextColor3 = UITheme.Ink
		end
		wreckedLabel.Visible = true
		task.delay(4.5, function()
			wreckedLabel.Visible = false
		end)
	end
end)

-- // Camera shake on hazard hits ------------------------------------------
-- опция «тряска камеры» (веха 5): доставляется эхом SaveSettings→PushSettings
local cameraShakeOn = true
remotes:WaitForChild("PushSettings").OnClientEvent:Connect(function(s)
	if type(s) == "table" and type(s.cameraShake) == "boolean" then
		cameraShakeOn = s.cameraShake
	end
end)

cameraShakeEvent.OnClientEvent:Connect(function(intensity: number, duration: number)
	if not cameraShakeOn then
		return
	end
	task.spawn(function()
		local camera = workspace.CurrentCamera
		local startTime = os.clock()
		while os.clock() - startTime < duration do
			local offset = Vector3.new(
				(math.random() - 0.5) * intensity,
				(math.random() - 0.5) * intensity,
				0
			)
			camera.CFrame = camera.CFrame * CFrame.new(offset)
			RunService.RenderStepped:Wait()
		end
	end)
end)
