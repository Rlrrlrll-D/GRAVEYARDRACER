--!strict
-- LocalScript: StarterPlayerScripts.RaceTune
-- ПАНЕЛЬ ПОЛИРОВКИ (PUBLISH_CHECKLIST §5: плотность зомби, три жизни, громкости).
-- Только Studio, как SkullTune/NeonTune. Крутится ПРЯМО В ЗАЕЗДЕ: юзер едет, двигает
-- ползунки, P печатает строку в Output — числа переносятся в GameConfig / звуки.
--
--   F2            вкл / выкл панели (F3 — черепа, F4 — съёмка, F6 — неон)
--   \             сброс к конфигу
--   P             напечатать все числа в Output
--
-- ЛЕВАЯ КОЛОНКА — СЕРВЕР (ремоут DevTune → GameConfig на живую):
--   SPAWN INT     секунд между спавнами зомби (Zombie.SpawnInterval)
--   MAX ZOMBIES   потолок живых зомби (Zombie.MaxZombies)
--   SPAWN RAD     радиус, в котором вокруг машины вылезают (Zombie.SpawnRadius)
--   MAX ATTACK    сколько зомби бьют одну машину разом (Zombie.MaxAttackers)
--   BITE CD       пауза между укусами, с (Zombie.AttackCooldown)
--   Z HP ×        стойкость всех типов, множитель к Tiers.hp
--   Z SPEED ×     скорость всех типов (только НОВЫЕ зомби; KILL сносит старых)
--   Z BITE ×      укус всех типов
--   BRUTE W / RUNNER W   вес брута и раннера в жребии (шамблер 55, гуль 30)
--   RAM DMG       урон машине за таран брута (Zombie.RamDamageToCar)
--   HAZARD DMG    урон машине от ловушки (Hazard.Damage)
--   LIVES         жизни (Race.Lives; на живых машинах — сразу, в HUD видно)
--   LAPS          круги (Race.Laps; со следующего заезда)
--   KILL          снести всех зомби (после смены скорости/укуса — они в атрибутах)
-- ПРАВАЯ КОЛОНКА — ЗВУК (клиент; серверный рык — через ремоут):
--   GROWL ×       рык/стон/хрип зомби (ZombieAI.playSoundAt)
--   GUN MG/NL/RT  громкость выстрела по стволам (Weapons.Stats.soundVolume)
--   CHECKPOINT / FINISH   стинги (UIController)
--   MUSIC         целевая громкость трека в заезде (DrivingMusic.TARGET_VOLUME)
--   AMBIENT / THUNDER     сверчки и гром (GraveyardAmbience, серверные Sound в SoundService)
--   SPOOKY ×      ворон/вой/стая (Spooky1..3)
--   BAT WINGS / SQUEAL / SCREAM   стая скримера (BatFX)
--
-- СКОРОСТЬ МАШИНЫ здесь не крутится: она в A-Chassis Tune (Horsepower 411, Redline 8000,
-- FinalDrive 1.6), а Drive кэширует кривую момента на старте — на живую не поменять.
-- Правится в Edit в самом шаблоне, машина — заново.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

if not RunService:IsStudio() then
	return
end

local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local Weapons = require(ReplicatedStorage:WaitForChild("Weapons"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local TOGGLE_KEY = Enum.KeyCode.F2
local FONT = Enum.Font.Code

local remote: RemoteEvent? = nil
task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 20)
	local r = remotes and remotes:WaitForChild("DevTune", 20)
	if r and r:IsA("RemoteEvent") then
		remote = r
	end
end)

local function send(key: string, value: number?)
	if remote then
		remote:FireServer(key, value)
	end
end

-- // Состояние --------------------------------------------------------------------
local Z = GameConfig.Zombie
local function tierWeight(id: string): number
	for _, t in Z.Tiers do
		if t.id == id then
			return t.weight
		end
	end
	return 0
end
type State = { [string]: number }
local function defaults(): State
	return {
		spawnInterval = Z.SpawnInterval,
		maxZombies = Z.MaxZombies,
		spawnRadius = Z.SpawnRadius,
		maxAttackers = Z.MaxAttackers,
		attackCooldown = Z.AttackCooldown,
		hpMult = 1, speedMult = 1, biteMult = 1,
		bruteWeight = tierWeight("brute"),
		runnerWeight = tierWeight("runner"),
		ramDamage = Z.RamDamageToCar,
		hazardDamage = GameConfig.Hazard.Damage,
		lives = GameConfig.Race.Lives,
		laps = GameConfig.Race.Laps,
		growl = 1,
		gunMg = Weapons.Stats.machinegun.soundVolume,
		gunNl = Weapons.Stats.nailer.soundVolume,
		gunRt = Weapons.Stats.rattle.soundVolume,
		checkpoint = 0.6, finish = 0.7, -- UIController
		music = 0.15, -- DrivingMusic.TARGET_VOLUME
		ambient = 0.4, thunder = 0.5, -- GraveyardAmbience
		spooky = 1, -- множитель к Spooky1..3 (0.45 / 0.25 / 0.20)
		batWings = 0.6, batSqueal = 0.35, batScream = 2.4, -- BatFX
	}
end
local state = defaults()
local base = defaults()

-- звуки по имени в SoundService (появляются позже панели — искать при каждом применении)
local function sound(name: string): Sound?
	local s = SoundService:FindFirstChild(name)
	return if s and s:IsA("Sound") then s else nil
end
local spookyBase: { [string]: number } = {}

local function applyClient()
	Weapons.Stats.machinegun.soundVolume = state.gunMg
	Weapons.Stats.nailer.soundVolume = state.gunNl
	Weapons.Stats.rattle.soundVolume = state.gunRt
	local cp = sound("CheckpointSound"); if cp then cp.Volume = state.checkpoint end
	local fin = sound("FinishSound"); if fin then fin.Volume = state.finish end
	local music = sound("DrivingMusic"); if music then music:SetAttribute("DevTarget", state.music) end
	local amb = sound("AmbientLoop"); if amb then amb.Volume = state.ambient end
	local th = sound("ThunderSound"); if th then th.Volume = state.thunder end
	for i = 1, 3 do
		local s = sound("Spooky" .. i)
		if s then
			spookyBase["Spooky" .. i] = spookyBase["Spooky" .. i] or s.Volume
			s.Volume = spookyBase["Spooky" .. i] * state.spooky
		end
	end
	local w = sound("BatWings"); if w then w.Volume = state.batWings end
	local sq = sound("BatSqueal"); if sq then sq.Volume = state.batSqueal end
	local sc = sound("BatScream"); if sc then sc.Volume = state.batScream end
end

local SERVER_KEYS = { "spawnInterval", "maxZombies", "spawnRadius", "maxAttackers", "attackCooldown",
	"hpMult", "speedMult", "biteMult", "bruteWeight", "runnerWeight", "ramDamage", "hazardDamage", "lives", "laps", "growl" }
local function applyServerAll()
	for _, k in SERVER_KEYS do
		send(k, state[k])
	end
end

-- // GUI ------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "RaceTune"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 60
gui.Enabled = false
gui.Parent = playerGui

local function makePanel(anchorX: number): Frame
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(anchorX, 1)
	panel.Position = UDim2.new(anchorX, if anchorX == 0 then 16 else -16, 1, -16)
	panel.Size = UDim2.fromOffset(300, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = UITheme.PanelBg
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
	panel.Parent = gui
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10); pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 14); pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = panel
	return panel
end
local panelL = makePanel(0)
local panelR = makePanel(1)
local column: Frame = panelL

local refreshers: { () -> () } = {}
local function refreshAll()
	for _, f in refreshers do
		f()
	end
end

local function makeLabel(order: number, text: string)
	local l = Instance.new("TextLabel")
	l.LayoutOrder = order
	l.Size = UDim2.new(1, 0, 0, 18)
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.TextSize = 14
	l.TextColor3 = UITheme.Palette.Bone
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = column
end

local function makeButton(order: number, text: string, onClick: () -> ())
	local b = Instance.new("TextButton")
	b.LayoutOrder = order
	b.Size = UDim2.new(1, 0, 0, 22)
	b.BackgroundColor3 = UITheme.Palette.Green
	b.BorderSizePixel = 0
	b.Font = FONT
	b.TextSize = 13
	b.TextColor3 = UITheme.Palette.Bone
	b.Text = text
	b.Parent = column
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
	b.Activated:Connect(onClick)
end

-- Ползунок min..max; шаг step (0 — плавно); onSet — куда уходит значение.
local function makeSlider(order: number, name: string, key: string, min: number, max: number, step: number, onSet: (number) -> ())
	local row = Instance.new("Frame")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 23)
	row.BackgroundTransparency = 1
	row.Parent = column
	local caption = Instance.new("TextLabel")
	caption.Size = UDim2.new(1, 0, 0, 13)
	caption.BackgroundTransparency = 1
	caption.Font = FONT
	caption.TextSize = 13
	caption.TextColor3 = UITheme.Palette.Bone
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.Parent = row
	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, 0, 0, 6)
	track.Position = UDim2.new(0, 0, 0, 15)
	track.BackgroundColor3 = UITheme.Shadow
	track.BorderSizePixel = 0
	track.Parent = row
	Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = UITheme.Palette.GreenLight
	fill.BorderSizePixel = 0
	fill.Parent = track
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(12, 12)
	knob.BackgroundColor3 = UITheme.Palette.Bone
	knob.BorderSizePixel = 0
	knob.ZIndex = 2
	knob.Parent = track
	Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
	local function refresh()
		local v = state[key]
		local alpha = math.clamp((v - min) / (max - min), 0, 1)
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.new(alpha, 0, 0.5, 0)
		caption.Text = if step >= 1 then string.format("%-11s %4d", name, math.floor(v + 0.5)) else string.format("%-11s %.2f", name, v)
	end
	table.insert(refreshers, refresh)
	local hit = Instance.new("TextButton")
	hit.Size = UDim2.fromScale(1, 1)
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Text = ""
	hit.Parent = row
	local dragging = false
	local lastSend = 0
	local function setFromX(x: number, final: boolean)
		local width = math.max(track.AbsoluteSize.X, 1)
		local v = min + math.clamp((x - track.AbsolutePosition.X) / width, 0, 1) * (max - min)
		if step > 0 then
			v = math.floor(v / step + 0.5) * step
		end
		state[key] = v
		refresh()
		if final or os.clock() - lastSend > 0.12 then
			lastSend = os.clock()
			onSet(v)
		end
	end
	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			setFromX(input.Position.X, false)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			setFromX(input.Position.X, false)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
			setFromX(input.Position.X, true)
		end
	end)
end

local function serverSlider(order: number, name: string, key: string, min: number, max: number, step: number)
	makeSlider(order, name, key, min, max, step, function(v)
		send(key, v)
	end)
end
local function clientSlider(order: number, name: string, key: string, min: number, max: number, step: number)
	makeSlider(order, name, key, min, max, step, function()
		applyClient()
	end)
end

-- // Левая колонка: зомби и заезд ---------------------------------------------------
column = panelL
makeLabel(0, "ПОЛИРОВКА · зомби и заезд   (F2, \\ сброс, P печать)")
serverSlider(1, "SPAWN INT", "spawnInterval", 0.5, 10, 0.1)
serverSlider(2, "MAX ZOMBIES", "maxZombies", 5, 60, 1)
serverSlider(3, "SPAWN RAD", "spawnRadius", 40, 160, 1)
serverSlider(4, "MAX ATTACK", "maxAttackers", 1, 8, 1)
serverSlider(5, "BITE CD", "attackCooldown", 0.5, 4, 0.1)
serverSlider(6, "Z HP x", "hpMult", 0.25, 3, 0.05)
serverSlider(7, "Z SPEED x", "speedMult", 0.5, 2, 0.05)
serverSlider(8, "Z BITE x", "biteMult", 0.25, 3, 0.05)
serverSlider(9, "BRUTE W", "bruteWeight", 0, 40, 1)
serverSlider(10, "RUNNER W", "runnerWeight", 0, 40, 1)
serverSlider(11, "RAM DMG", "ramDamage", 0, 40, 1)
serverSlider(12, "HAZARD DMG", "hazardDamage", 0, 40, 1)
serverSlider(13, "LIVES", "lives", 1, 6, 1)
serverSlider(14, "LAPS", "laps", 1, 5, 1)
makeButton(15, "KILL — снести всех зомби", function()
	send("kill")
end)

-- // Правая колонка: звук -------------------------------------------------------------
column = panelR
makeLabel(0, "ПОЛИРОВКА · звук")
serverSlider(1, "GROWL x", "growl", 0, 3, 0.05)
clientSlider(2, "GUN MG", "gunMg", 0, 3, 0.05)
clientSlider(3, "GUN NAILER", "gunNl", 0, 3, 0.05)
clientSlider(4, "GUN RATTLE", "gunRt", 0, 3, 0.05)
clientSlider(5, "CHECKPOINT", "checkpoint", 0, 2, 0.05)
clientSlider(6, "FINISH", "finish", 0, 2, 0.05)
clientSlider(7, "MUSIC", "music", 0, 1, 0.01)
clientSlider(8, "AMBIENT", "ambient", 0, 2, 0.05)
clientSlider(9, "THUNDER", "thunder", 0, 2, 0.05)
clientSlider(10, "SPOOKY x", "spooky", 0, 3, 0.05)
clientSlider(11, "BAT WINGS", "batWings", 0, 3, 0.05)
clientSlider(12, "BAT SQUEAL", "batSqueal", 0, 3, 0.05)
clientSlider(13, "BAT SCREAM", "batScream", 0, 5, 0.05)

-- // Печать / сброс / клавиши ---------------------------------------------------------
local function summary(): string
	local s = state
	return ("[RaceTune] zombie: spawnInterval=%.1f maxZombies=%d spawnRadius=%d maxAttackers=%d attackCooldown=%.1f hp×%.2f speed×%.2f bite×%.2f bruteW=%d runnerW=%d ramDamageToCar=%d | hazardDamage=%d | race: lives=%d laps=%d\n"
		.. "[RaceTune] sound: growl×%.2f gun mg=%.2f nailer=%.2f rattle=%.2f checkpoint=%.2f finish=%.2f music=%.2f ambient=%.2f thunder=%.2f spooky×%.2f bats wings=%.2f squeal=%.2f scream=%.2f"):format(
		s.spawnInterval, s.maxZombies, s.spawnRadius, s.maxAttackers, s.attackCooldown, s.hpMult, s.speedMult, s.biteMult, s.bruteWeight, s.runnerWeight, s.ramDamage, s.hazardDamage, s.lives, s.laps,
		s.growl, s.gunMg, s.gunNl, s.gunRt, s.checkpoint, s.finish, s.music, s.ambient, s.thunder, s.spooky, s.batWings, s.batSqueal, s.batScream)
end

local function resetAll()
	for k, v in base do
		state[k] = v
	end
	send("reset")
	applyClient()
	refreshAll()
end

local active = false
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == TOGGLE_KEY then
		active = not active
		gui.Enabled = active
		if active then
			refreshAll()
			applyServerAll()
			applyClient()
		end
	elseif active and input.KeyCode == Enum.KeyCode.P then
		print(summary())
	elseif active and input.KeyCode == Enum.KeyCode.BackSlash then
		resetAll()
	end
end)

print("[RaceTune] панель полировки готова: F2 (зомби, жизни, звук)")
