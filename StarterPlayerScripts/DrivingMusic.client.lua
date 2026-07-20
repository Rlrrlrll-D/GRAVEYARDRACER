--!strict
-- LocalScript: StarterPlayerScripts.DrivingMusic
-- Фоновый heavy-metal трек, играющий с момента посадки за руль своей машины
-- и затихающий, когда игрок выходит. Динамично под кладбище-рейсинг.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer

-- "A Beast Inside" — тяжёлый метал, free Creator Store (207с, зациклен).
local MUSIC_ID = "rbxassetid://130598693233260"
local TARGET_VOLUME = 0.15 -- фоновый трек тише, чтобы не забивал мотор/SFX/эмбиент (баланс 2026-07-20)
local FADE_SECONDS = 1.5

local music = Instance.new("Sound")
music.Name = "DrivingMusic"
music.SoundId = MUSIC_ID
music.Looped = true
music.Volume = 0
music.Parent = SoundService

-- игрок сидит за рулём СВОЕЙ машины (тег PlayerVehicle + Occupant == наш персонаж)
local function seatedInOwnVehicle(): boolean
	for _, v in CollectionService:GetTagged("PlayerVehicle") do
		if v:IsA("Model") then
			local seat = v:FindFirstChild("DriveSeat")
			if seat and seat:IsA("VehicleSeat") and seat.Occupant then
				local char = seat.Occupant.Parent
				if char and Players:GetPlayerFromCharacter(char) == player then
					return true
				end
			end
		end
	end
	return false
end

RunService.Heartbeat:Connect(function(dt: number)
	local want = seatedInOwnVehicle()
	if want and not music.IsPlaying then
		music:Play()
	end
	-- плавный фейд громкости к цели
	local target = if want then TARGET_VOLUME else 0
	music.Volume += (target - music.Volume) * math.clamp(dt / FADE_SECONDS, 0, 1)
	if not want and music.IsPlaying and music.Volume < 0.005 then
		music:Stop()
	end
end)
