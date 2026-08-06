--!strict
-- LocalScript: StarterPlayerScripts.Onboarding
-- ПОДСКАЗКИ ПЕРВОГО ЗАЕЗДА. Новичок садится в багги, не зная ни управления, ни того,
-- что жизней три, ни зачем кости. Пять коротких строк, по одной, плашкой-мазком внизу
-- экрана — и больше никогда.
--
-- ПОЧЕМУ ПО СОБЫТИЯМ, А НЕ СПИСКОМ НА СТАРТЕ. Стена текста перед заездом не читается:
-- человек жмёт «дальше» и запоминает ноль. Подсказка приходит ровно тогда, когда
-- человек смотрит на то, о чём она: про стрельбу — когда в кадре зомби, про жизни —
-- когда первая уже потеряна.
--
-- «БОЛЬШЕ НИКОГДА» ЖИВЁТ НА СЕРВЕРЕ. Флаг — атрибут Onboarded, его сидирует PlayerData
-- из записи DataStore и поднимает MatchManager после первого заезда. Локально хранить
-- нельзя: подсказки обязаны не вернуться ни завтра, ни на другом устройстве.
--
-- ЗАЩЁЛКА active. Атрибут поднимается на экране итогов — то есть РАНЬШЕ, чем успевает
-- показаться последняя подсказка (про магазин, она ждёт возврата в лобби). Поэтому
-- атрибут решает только, НАЧИНАТЬ ли обучение; начатое доигрывается до конца.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local PlateArt = require(ReplicatedStorage:WaitForChild("PlateArt"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HINT_SECONDS = 5 -- сколько висит одна подсказка
local ZOMBIE_NOTICE = 80 -- studs: с какого расстояния зомби считается «в кадре»

local updateStats = Net.get(Net.Events.UpdateStats)
local raceUpdate = Net.get(Net.Events.RaceUpdate)
local returnToLobby = Net.get(Net.Events.ReturnToLobby)

-- // Тексты -------------------------------------------------------------------
-- Английские: Creepster кириллицы не знает (тот же выбор, что во всём интерфейсе).
-- Раскладка у телефона своя — «W / S» человеку с тачскрином не говорит ничего.
local function touch(): boolean
	return player:GetAttribute("TouchActive") == true
end

type Hint = { keys: string, touch: string }
local TEXTS: { [string]: Hint } = {
	drive = {
		keys = "W / S — gas and brake  ·  A / D — steer",
		touch = "Arrows steer  ·  pedals on the right",
	},
	route = {
		keys = "Follow the green skulls — 3 laps to win",
		touch = "Follow the green skulls — 3 laps to win",
	},
	shoot = {
		keys = "Hold LMB to fire — every zombie is bones",
		touch = "Tap the crosshair to fire — every zombie is bones",
	},
	lives = {
		keys = "Three lives. Lose them all and you're out.",
		touch = "Three lives. Lose them all and you're out.",
	},
	shop = {
		keys = "Bones buy skins and lives in the SHOP",
		touch = "Bones buy skins and lives in the SHOP",
	},
}

-- // Плашка -------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "Onboarding"
gui.ResetOnSpawn = false
-- Выше HUD (0) и заставки лобби (10), ниже сенсорных кнопок (20), прицела и экрана
-- итогов (50): подсказка не должна ни прятаться за HUD, ни закрывать педали.
gui.DisplayOrder = 15
gui.Parent = playerGui

-- Мазок КОСТЯНОЙ с красной надписью — как плашка костей в HUD. Зелёная читалась бы
-- продолжением строки статуса заезда, а подсказка — не статус.
local plate = PlateArt.plate(3, UITheme.Palette.Bone)
plate.Name = "Hint"
plate.AnchorPoint = Vector2.new(0.5, 0)
plate.Visible = false
plate.Parent = gui

local caption = PlateArt.caption(plate, "", UITheme.Palette.Red, 26)

local pop = Instance.new("UIScale")
pop.Parent = plate

-- ПОЧЕМУ ПОДСКАЗКА ВИСИТ НА ЛИНИИ СТРЕЛКИ, А НЕ У НИЖНЕГО КРАЯ. Стрелка-компас и
-- строка расстояния под ней стоят по ДОЛЕ высоты (0.72 в UIController), а прибитый
-- к низу мазок — по пикселям от края. На эталонном экране они разошлись бы, но чем
-- ниже экран, тем ближе друг к другу: при первой сборке мазок накрыл «125 studs»
-- ровно на 18 пикселей. Общий якорь снимает вопрос на любом экране: 54 пикселя ниже
-- той же линии — это всегда сразу под строкой расстояния.
--
-- Ширина разная не ради красоты: на телефоне низ экрана делят руль (слева) и педали
-- с прицелом (справа), и широкий мазок влезал бы им под пальцы.
-- Высота 46 — как у всех плашек HUD (PLATE_H в UIController): подсказка им ровня.
local function applySize()
	local w = if touch() then 480 else 620
	plate.Size = UDim2.fromOffset(w, 46)
	plate.Position = UDim2.new(0.5, 0, 0.72, 54)
end
applySize()
player:GetAttributeChangedSignal("TouchActive"):Connect(applySize)

local function show(text: string)
	caption.Text = text
	plate.Visible = true
	pop.Scale = 0.92
	TweenService:Create(pop, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

local function hide()
	plate.Visible = false
end

-- // Очередь ------------------------------------------------------------------
-- Подсказки не наслаиваются: пока висит одна, остальные ждут. Иначе потеря жизни
-- рядом с первым зомби стёрла бы обе строки быстрее, чем их успеют прочитать.
local queue: { string } = {}
local showing = false
local fired: { [string]: boolean } = {}

local function pump()
	if showing then
		return
	end
	local text = table.remove(queue, 1)
	if not text then
		hide()
		return
	end
	showing = true
	show(text)
	task.delay(HINT_SECONDS, function()
		showing = false
		pump()
	end)
end

local active = false -- обучение начато (защёлка, см. шапку)
local finished = false -- последняя подсказка выдана, скрипт своё отработал

local function hint(key: string)
	if finished or fired[key] then
		return
	end
	local row = TEXTS[key]
	if not row then
		return
	end
	fired[key] = true
	table.insert(queue, if touch() then row.touch else row.keys)
	pump()
end

-- // Триггеры -----------------------------------------------------------------
local racing = false
local lastLives: number? = nil

raceUpdate.OnClientEvent:Connect(function(data)
	racing = data.Phase == "Racing"
	if data.Phase == "Idle" then
		lastLives = nil
	end
end)

-- Первый пакет статистики В ЗАЕЗДЕ — самый честный признак, что человек за рулём:
-- зрителю-выбывшему сервер статов не шлёт, и подсказки про газ он не получит.
updateStats.OnClientEvent:Connect(function(stats)
	if not racing then
		return
	end
	if not active then
		if player:GetAttribute("Onboarded") == true then
			finished = true
			return
		end
		active = true
		hint("drive")
		hint("route") -- вторая в очереди: покажется, когда отвисит первая
	end

	local lives = stats.Lives
	if type(lives) == "number" then
		if lastLives and lives < lastLives then
			hint("lives")
		end
		lastLives = lives
	end
end)

-- Зомби «в кадре». Опрос раз в полсекунды по тегу — дешевле, чем ловить появление
-- каждого: их за заезд десятки, а нужен нам ровно первый подошедший.
task.spawn(function()
	while not finished do
		task.wait(0.5)
		if active and not fired.shoot and racing then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				for _, z in CollectionService:GetTagged("Zombie") do
					local part: BasePart? = nil
					if z:IsA("Model") then
						-- PrimaryPart у зомби бывает не проставлен (риг собирал Avatar
						-- Setup), поэтому запасной путь — корень humanoid'а.
						part = z.PrimaryPart or (z:FindFirstChild("HumanoidRootPart") :: BasePart?)
					end
					if part and (part.Position - root.Position).Magnitude <= ZOMBIE_NOTICE then
						hint("shoot")
						break
					end
				end
			end
		end
	end
end)

-- Про магазин говорим в лобби, а не на экране итогов: тот лежит выше (DisplayOrder
-- 50) и накрыл бы подсказку, а главное — кнопка SHOP в этот момент прямо на экране.
returnToLobby.OnClientEvent:Connect(function()
	if not active or finished then
		return
	end
	hint("shop")
	finished = true -- дальше подсказок нет; очередь доиграет сама
end)
