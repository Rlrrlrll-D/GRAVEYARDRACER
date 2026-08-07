--!strict
-- Script: ServerScriptService.PhotoModeService
-- Серверная половина дев-режима съёмки (StarterPlayerScripts.PhotoMode): по просьбе
-- клиента останавливает мир, чтобы кадр можно было выставить спокойно, а не ловить
-- зомби на бегу.
--
-- ТОЛЬКО STUDIO. Скрипт выходит на первой же строке в живой игре, и ремоут PhotoFreeze
-- там не создаётся вовсе — «заморозить сервер» некому и нечем. Поэтому его НЕТ и в
-- манифесте ReplicatedStorage.Net: попади он туда, Bootstrap создавал бы ремоут всем.
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

if not RunService:IsStudio() then
	return
end

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

remote.OnServerEvent:Connect(function(_player, on)
	if on == true then
		freeze()
	else
		unfreeze()
	end
end)

-- Съёмщик вышел из игры замороженным — мир не должен остаться стоять.
game:GetService("Players").PlayerRemoving:Connect(function()
	if #game:GetService("Players"):GetPlayers() <= 1 then
		unfreeze()
	end
end)

print("[PhotoMode] заморозка мира доступна (Studio)")
