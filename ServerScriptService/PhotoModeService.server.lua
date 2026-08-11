--!strict
-- Script: ServerScriptService.PhotoModeService
-- Серверная половина дев-режима съёмки (StarterPlayerScripts.PhotoMode): по просьбе
-- клиента останавливает мир, чтобы кадр можно было выставить спокойно, а не ловить
-- зомби на бегу.
--
-- ДОСТУП: STUDIO ЛИБО ВЛАДЕЛЕЦ. Раньше скрипт выходил на первой же строке в живой игре,
-- и ремоутов там не было вовсе. Но снимать превью удобнее в НАСТОЯЩЕМ клиенте (F11 даёт
-- полный экран без ленты редактора), а там зомби не давали спокойно выставить кадр.
--
-- РАЗ РЕМОУТ ВИДЕН ВСЕМ, КАЖДЫЙ ВЫЗОВ ОБЯЗАН ПРОВЕРЯТЬ, КТО ДЁРГАЕТ. Без проверки любой
-- игрок мог бы заморозить сервер или снести всех зомби — ровно та дыра, что нашлась в
-- ремоутах A-Chassis (SECURITY_AUDIT.md, раздел 2). Список сверяется по UserId НА
-- СЕРВЕРЕ, подделать его с клиента нельзя.
--
-- В манифесте ReplicatedStorage.Net этих ремоутов по-прежнему НЕТ: их заводит только
-- этот скрипт. Попади они туда — Bootstrap создавал бы их независимо от проверок здесь.
--
-- ЧТО ИМЕННО ЗАМОРАЖИВАЕТСЯ
--   * машины (тег PlayerVehicle) и зомби (тег Zombie) — Anchored на всех деталях;
--   * анимации зомби — AdjustSpeed(0), иначе анкер держит тело на месте, а поза
--     продолжает шагать;
--   * ИИ зомби — по атрибуту workspace.PhotoFreeze, его читает цикл ZombieAI.Run;
--     без этого зомби доигрывал бы замах (он идёт тайном по Motor6D, не анимацией).
--
-- Якорим КАЖДУЮ деталь, а не корневую: у машины колёса — отдельные сборки, и один
-- анкер шасси их не удержал бы.

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 8110001559 — владелец места. Тот же список, что в StarterPlayerScripts.PhotoMode;
-- держать их в синхроне вручную, значений всего одно.
local ALLOWED_USER_IDS: { number } = { 8110001559 }

local function isAllowed(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	for _, id in ALLOWED_USER_IDS do
		if id == player.UserId then
			return true
		end
	end
	return false
end

local FREEZE_TAGS = { "PlayerVehicle", "Zombie" }

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local remote = Instance.new("RemoteEvent")
remote.Name = "PhotoFreeze"
remote.Parent = remotes

local frozen = false
local anchorStates: { [BasePart]: boolean } = {}
local walkSpeeds: { [Humanoid]: number } = {}
local tracks: { AnimationTrack } = {}

local function freeze()
	if frozen then
		return
	end
	frozen = true
	workspace:SetAttribute("PhotoFreeze", true)

	for _, tag in FREEZE_TAGS do
		for _, model in CollectionService:GetTagged(tag) do
			for _, inst in model:GetDescendants() do
				if inst:IsA("BasePart") then
					local part = inst :: BasePart
					anchorStates[part] = part.Anchored
					part.Anchored = true
				elseif inst:IsA("Humanoid") then
					local humanoid = inst :: Humanoid
					walkSpeeds[humanoid] = humanoid.WalkSpeed
					humanoid.WalkSpeed = 0
					local animator = humanoid:FindFirstChildOfClass("Animator")
					if animator then
						for _, track in animator:GetPlayingAnimationTracks() do
							track:AdjustSpeed(0)
							table.insert(tracks, track)
						end
					end
				end
			end
		end
	end
end

local function unfreeze()
	if not frozen then
		return
	end
	frozen = false
	workspace:SetAttribute("PhotoFreeze", nil)

	for part, anchored in anchorStates do
		if part.Parent then
			part.Anchored = anchored
		end
	end
	table.clear(anchorStates)

	for humanoid, speed in walkSpeeds do
		if humanoid.Parent then
			humanoid.WalkSpeed = speed
		end
	end
	table.clear(walkSpeeds)

	for _, track in tracks do
		if track.IsPlaying then
			track:AdjustSpeed(1)
		end
	end
	table.clear(tracks)
end

remote.OnServerEvent:Connect(function(player, on)
	if not isAllowed(player) then
		return -- чужой клиент не морозит сервер
	end
	if on == true then
		freeze()
	else
		unfreeze()
	end
end)

-- // Выключатель зомби -------------------------------------------------------
-- Отдельно от заморозки, и намеренно: заморозка останавливает ВЕСЬ мир, включая
-- машину и саму сцену, а тут нужно ровно обратное — мир живёт, но никто не грызёт
-- машину, пока настраивают свечение черепов и анимацию улёта.
--
-- Гасим В ДВА ДЕЙСТВИЯ. Флаг перекрывает кран (ZombieSpawner его читает перед
-- спавном), но уже вылезшие продолжают идти к машине — поэтому их ещё и убираем.
-- Одного флага было бы мало, одного сноса — тоже: через SpawnInterval набегут новые.
local zombiesRemote = Instance.new("RemoteEvent")
zombiesRemote.Name = "DevZombies"
zombiesRemote.Parent = remotes

zombiesRemote.OnServerEvent:Connect(function(player, off)
	if not isAllowed(player) then
		return -- иначе любой игрок сносил бы всех зомби в заезде
	end
	local disable = off == true
	workspace:SetAttribute("ZombiesOff", disable or nil)
	local removed = 0
	if disable then
		for _, z in CollectionService:GetTagged("Zombie") do
			z:Destroy()
			removed += 1
		end
	end
	print(("[PhotoMode] зомби %s%s"):format(
		disable and "ВЫКЛЮЧЕНЫ" or "включены",
		disable and (", снято " .. removed) or ""))
end)

-- Съёмщик вышел из игры замороженным — мир не должен остаться стоять.
game:GetService("Players").PlayerRemoving:Connect(function()
	if #game:GetService("Players"):GetPlayers() <= 1 then
		unfreeze()
	end
end)

print(("[PhotoMode] заморозка мира и выключатель зомби подняты (%s)"):format(
	RunService:IsStudio() and "Studio: доступно всем" or "живая игра: только владельцу"))
