--!strict
-- LocalScript: StarterPlayerScripts.BatFX  [СКЕЛЕТ — ещё не подключён к Studio]
-- Рисует летучих мышей по команде BatManager. Клиент-онли: модели-мыши живут
-- только у зрителя, CanCollide/CanQuery=false, никакой репликации.
--
-- АССЕТ: готовая мышь из Creator Store / Toolbox. Положить модель в
-- ReplicatedStorage.Assets.Bat (Model с анимацией взмаха крыльев или просто меш).
-- BAT_ASSET_ID — запасной вариант через InsertService, если модели нет в игре.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local batScare = Net.get(Net.Events.BatScare)

local player = Players.LocalPlayer

local BAT_ASSET_ID = 0 -- TODO: id выбранной мыши из стора (или использовать Assets.Bat)
local SCREECH_ID = "rbxassetid://0" -- TODO: писк/шелест крыльев из стора

-- опция «скримеры» (обновляется из PushSettings — см. LobbyUI/SettingsService)
local jumpscaresOn = true
-- TODO: подписаться на PushSettings и обновлять jumpscaresOn

local batTemplate: Model? = nil
do
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local b = assets and assets:FindFirstChild("Bat")
	if b and b:IsA("Model") then batTemplate = b end
	-- TODO: если nil и BAT_ASSET_ID>0 — InsertService:LoadAsset(BAT_ASSET_ID)
end

local screech = Instance.new("Sound")
screech.SoundId = SCREECH_ID
screech.Volume = 0.6
screech.Parent = SoundService

-- один «вылет»: мышь стартует у origin и по дуге быстро уносится наружу
local function launchOne(origin: Vector3, fast: boolean)
	if not batTemplate then return end
	local bat = batTemplate:Clone()
	for _, p in bat:GetDescendants() do
		if p:IsA("BasePart") then
			p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.Anchored = true
		end
	end
	-- случайное направление «врассыпную», с уклоном вверх
	local dir = (Vector3.new(math.random() - 0.5, math.random() * 0.6 + 0.2, math.random() - 0.5)).Unit
	local speed = fast and math.random(90, 140) or math.random(35, 55) -- swarm резче
	bat.Parent = workspace.CurrentCamera
	local t0 = os.clock()
	local life = fast and 1.2 or 2.2
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function(dt)
		local age = os.clock() - t0
		if age > life or not bat.Parent then conn:Disconnect(); return end
		local pos = origin + dir * (speed * age) + Vector3.new(0, math.sin(age * 20) * 1.5, 0) -- взмах
		bat:PivotTo(CFrame.lookAt(pos, pos + dir))
	end)
	Debris:AddItem(bat, life + 0.1)
end

batScare.OnClientEvent:Connect(function(origin: Vector3, count: number, kind: string)
	if kind == "swarm" then
		if not jumpscaresOn then return end -- уважаем пугливых
		screech:Play()
		-- резкий синхронный разлёт стаи в лицо
		for _ = 1, count do launchOne(origin, true) end
	else -- flyby: одна-две неспешные мыши мимо
		for _ = 1, count do launchOne(origin, false) end
	end
end)
