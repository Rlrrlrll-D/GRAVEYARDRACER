--!strict
-- Script: ServerScriptService.AssetWarmup
-- Собирает ВСЕ ассеты сессии в один список, который клиент прогревает в лобби.
--
-- ЗАЧЕМ. Замер 2026-07-26 (клиентский профайлер кадра) показал фризы по 180-220 мс
-- в ПРОИЗВОЛЬНЫХ точках трассы — не у зон скримеров и не у декора. В логе рядом с
-- каждым таким рывком стоят строки `Failed to load sound rbxassetid://... HttpError:
-- Timedout`. Причина не в игровой логике: любой ассет, которого нет в локальном кэше,
-- тянется по сети при ПЕРВОМ использовании, и кадр ждёт ответа. На плохом канале
-- (у юзера — раздача с телефона) это стабильные просадки в случайных местах.
-- Прогрев переносит эти ожидания под заставку, где рывок никому не мешает, а в
-- заезде всё идёт из кэша. Если CDN не отдаёт файл вообще — прогрев не спасёт,
-- но повторные заезды в сессии станут чистыми.
--
-- ПОЧЕМУ СОБИРАЕТ СЕРВЕР. Половина ассетов живёт в ServerStorage (VehicleTemplate с
-- десятком звуков A-Chassis, ZombieTemplate), которого клиент не видит вообще, а под
-- StreamingEnabled в клиентском Workspace лежит только ближний кусок карты. Меши
-- декора уже отдаёт MapBuilder через ReplicatedStorage.DecorAssets — этот список
-- дополняющий: звуки и всё, что найдено в шаблонах.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")

-- Звуки, которые скрипты создают на ходу: инстансов в дереве нет, обходом их не
-- найти. ДОБАВЛЯЕШЬ звук в код — добавь id и сюда, иначе он снова будет тянуться
-- по сети посреди заезда.
local RUNTIME_SOUNDS = {
	"rbxassetid://9114228524", -- UIController: шёпот на чекпоинте
	"rbxassetid://4961240438", -- UIController: финиш / GraveyardAmbience: гром
	"rbxassetid://88311346538102", -- TurretAimClient: выстрел
	"rbxassetid://130598693233260", -- DrivingMusic: музыка заезда
	"rbxassetid://9125386815", -- BatFX: залп крыльев колонии (скример)
	"rbxassetid://9117009021", -- BatFX: визг стаи (скример)
	"rbxassetid://93232280469148", -- BatFX: человеческий крик (скример)
	"rbxassetid://72166668675269", -- TurretAimClient: осечка (заезд решён)
	"rbxassetid://9112764040", -- GraveyardAmbience: сверчки
	"rbxassetid://121066883602737", -- ZombieAI: рык при замахе
	"rbxassetid://9116771817", -- ZombieAI: лязг по кузову
}

-- Картинки/меши, которые тоже рождаются из кода, а не лежат инстансами.
local RUNTIME_IMAGES = {
	"rbxassetid://79551611166203", -- RaceScene: плашка-череп чекпоинта (и слои ореола)
}

local sounds: { [string]: boolean } = {}
local assets: { [string]: boolean } = {}
local anims: { [string]: boolean } = {}

-- Берём только сетевые ассеты: rbxasset:// — локальные файлы клиента, их греть не надо.
-- Старый формат `http://www.roblox.com/asset/?id=` тоже сетевой: именно в нём лежат
-- анимации зомби, и из-за проверки только на rbxassetid:// они пролетали мимо прогрева.
local function isRemote(id: string?): boolean
	if id == nil or id == "" then
		return false
	end
	return string.sub(id, 1, 13) == "rbxassetid://" or string.find(id, "roblox.com/asset", 1, true) ~= nil
end

local function scan(root: Instance?)
	if not root then
		return
	end
	for _, d in root:GetDescendants() do
		if d:IsA("Sound") then
			if isRemote(d.SoundId) then
				sounds[d.SoundId] = true
			end
		elseif d:IsA("MeshPart") then
			if isRemote(d.MeshId) then
				assets[d.MeshId] = true
			end
			if isRemote(d.TextureID) then
				assets[d.TextureID] = true
			end
		elseif d:IsA("SpecialMesh") then
			if isRemote(d.MeshId) then
				assets[d.MeshId] = true
			end
			if isRemote(d.TextureId) then
				assets[d.TextureId] = true
			end
		elseif d:IsA("Decal") or d:IsA("Texture") then
			if isRemote(d.Texture) then
				assets[d.Texture] = true
			end
		elseif d:IsA("ImageLabel") or d:IsA("ImageButton") then
			if isRemote(d.Image) then
				assets[d.Image] = true
			end
		elseif d:IsA("ParticleEmitter") or d:IsA("Beam") then
			if isRemote(d.Texture) then
				assets[d.Texture] = true
			end
		elseif d:IsA("CharacterMesh") then
			-- R6-риг зомби одет ПЯТЬЮ CharacterMesh (руки/ноги/торс), и про этот класс
			-- обход не знал вовсе — ни меш, ни текстура зомби в прогрев не попадали.
			-- Здесь id числовые, а не строки, поэтому собираем url руками.
			for _, id in { d.MeshId, d.BaseTextureId, d.OverlayTextureId } do
				if id ~= nil and id ~= 0 then
					assets["rbxassetid://" .. tostring(id)] = true
				end
			end
		elseif d:IsA("Shirt") then
			if isRemote(d.ShirtTemplate) then
				assets[d.ShirtTemplate] = true
			end
		elseif d:IsA("Pants") then
			if isRemote(d.PantsTemplate) then
				assets[d.PantsTemplate] = true
			end
		elseif d:IsA("Animation") then
			-- ГЛАВНАЯ НАХОДКА замера: спавн зомби вешал кадр на 190-210 мс, потому что
			-- Animator тянет анимацию при ПЕРВОМ воспроизведении. У ZombieTemplate их
			-- десять (Animate.* + Animations.Attack/Arms). Серверная часть спавна при
			-- этом стоит 1.7 мс — всё время уходило у клиента на догрузку.
			if isRemote(d.AnimationId) then
				anims[d.AnimationId] = true
			end
		end
	end
end

local existing = ReplicatedStorage:FindFirstChild("WarmupAssets")
local holder: StringValue
if existing and existing:IsA("StringValue") then
	holder = existing
else
	holder = Instance.new("StringValue")
	holder.Name = "WarmupAssets"
	holder.Parent = ReplicatedStorage
end

-- Формат строк: "s|id" — звук (клиент делает под него Sound-инстанс),
--               "n|id" — анимация (клиент делает Animation-инстанс),
--               "a|id" — меш/картинка (клиент грузит по url).
-- Разделение нужно потому, что по самому id тип ассета не определить, а звуки с
-- анимациями ContentProvider греет только через инстанс, не по строке.
local function publish(): (number, number, number)
	local lines: { string } = {}
	local nSounds, nAssets, nAnims = 0, 0, 0
	for id in sounds do
		table.insert(lines, "s|" .. id)
		nSounds += 1
	end
	for id in anims do
		table.insert(lines, "n|" .. id)
		nAnims += 1
	end
	for id in assets do
		table.insert(lines, "a|" .. id)
		nAssets += 1
	end
	table.sort(lines) -- порядок стабильный: удобно сверять логи между заездами
	holder.Value = table.concat(lines, "\n")
	return nSounds, nAssets, nAnims
end

local function sweep()
	scan(ServerStorage)
	scan(ReplicatedStorage)
	scan(workspace)
	scan(StarterPlayer)
	scan(StarterGui)
	scan(SoundService)
end

-- // КОПИЯ РИГА ЗОМБИ ДЛЯ ПРОГРЕВА ОТРИСОВКИ -----------------------------------
-- Замер 2026-07-30: первый зомби, попавший в кадр, стоил 193 и 207 мс ЦЕЛИКОМ в
-- фазе отрисовки («ВПЕРВЫЕ В КАДРЕ: ZombieTemplate×12»), и текстурная память в тот
-- же момент прыгнула с 36.9 до 43.0 Мб. Сетевой прелоад этого не закрывает: меш
-- строится при первой ОТРИСОВКЕ, а не при загрузке. Клиенту ServerStorage не виден,
-- поэтому кладём ему копию рига в ReplicatedStorage — `DecorPreload` показывает её
-- камере под заставкой. Humanoid ОСТАВЛЯЕМ: без него CharacterMesh не применяется и
-- прогрелись бы не те меши. Скрипты убираем, чтобы копия не оживала.
local function publishZombieWarmCopy()
	local template = ServerStorage:FindFirstChild("ZombieTemplate")
	if not template then
		return
	end
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	if not assetsFolder then
		assetsFolder = Instance.new("Folder")
		assetsFolder.Name = "Assets"
		assetsFolder.Parent = ReplicatedStorage
	end
	if assetsFolder:FindFirstChild("ZombieWarm") then
		return
	end
	local copy = template:Clone()
	copy.Name = "ZombieWarm"
	for _, d in copy:GetDescendants() do
		if d:IsA("BaseScript") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	copy.Parent = assetsFolder
end
publishZombieWarmCopy()

sweep()
for _, id in RUNTIME_SOUNDS do
	sounds[id] = true
end
for _, id in RUNTIME_IMAGES do
	assets[id] = true
end
local s0, a0, n0 = publish()
print(("[AssetWarmup] к прогреву: %d звуков, %d анимаций, %d мешей/картинок."):format(s0, n0, a0))

-- ДОСБОР. Первый проход неизбежно неполон: скрипты создают свои звуки в собственном
-- старте, и на первом кадре их инстансов ещё нет. Так мы прошляпили восемь звуков
-- атмосферы GraveyardAmbience (вороны/скрипы/вой) — они падали по таймауту уже в
-- заезде. Поэтому пересматриваем дерево ещё несколько раз и дописываем найденное;
-- клиент слушает Changed и греет только новые id.
task.spawn(function()
	local prevS, prevA, prevN = s0, a0, n0
	for _ = 1, 8 do
		task.wait(2)
		sweep()
		local ns, na, nn = publish()
		if ns ~= prevS or na ~= prevA or nn ~= prevN then
			print(("[AssetWarmup] досбор: +%d звуков, +%d анимаций, +%d ассетов (итого %d/%d/%d).")
				:format(ns - prevS, nn - prevN, na - prevA, ns, nn, na))
			prevS, prevA, prevN = ns, na, nn
		end
	end
end)
