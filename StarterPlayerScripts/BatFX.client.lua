--!strict
-- LocalScript: StarterPlayerScripts.BatFX
-- Рисует летучих мышей по команде BatManager (BatScare). Клиент-онли: клоны
-- живут только у зрителя и не реплицируются. Ассет — ReplicatedStorage.Assets.Bat
-- (одиночный MeshPart "Body", из стора: model 9372173692).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local batScare = Net.get(Net.Events.BatScare)

local SCREECH_ID = "rbxassetid://9113994447" -- залп крыльев (ProSoundEffects «Creature Wings 24», bat flaps 2.1с); пусто = без звука

-- опция «скримеры» (обновляется из PushSettings); по умолчанию включена
local jumpscaresOn = true
local remotes = ReplicatedStorage:WaitForChild("Remotes")
remotes:WaitForChild("PushSettings").OnClientEvent:Connect(function(s)
	if type(s) == "table" and type(s.jumpscares) == "boolean" then
		jumpscaresOn = s.jumpscares
	end
end)

local template = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Bat")

-- локальная папка для клонов (не реплицируется, легко чистить)
local folder = Instance.new("Folder")
folder.Name = "BatFX"
folder.Parent = workspace.CurrentCamera

local screech = Instance.new("Sound")
screech.SoundId = SCREECH_ID
screech.Volume = 0.7
screech.Parent = SoundService

-- один вылет: стартует у origin и по дуге быстро уносится наружу, «махая крыльями»
local function launchOne(origin: Vector3, fast: boolean)
	local bat = template:Clone()
	for _, p in bat:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
		end
	end
	local start = origin
		+ Vector3.new((math.random() - 0.5) * 6, (math.random() - 0.5) * 4, (math.random() - 0.5) * 6)
	local dir
	if fast then
		-- рой: взмывает вверх и врассыпную (потревоженная стая)
		dir = Vector3.new(math.random() - 0.5, math.random() * 0.7 + 0.5, math.random() - 0.5).Unit
	else
		-- одиночка: пролёт поперёк, почти горизонтально
		dir = Vector3.new(math.random() - 0.5, (math.random() - 0.5) * 0.25, math.random() - 0.5).Unit
	end
	local speed = fast and math.random(55, 95) or math.random(28, 46)
	local life = fast and 1.3 or 2.6
	local phase = math.random() * 6.28
	bat.Parent = folder
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local age = os.clock() - t0
		if age > life or not bat.Parent then
			conn:Disconnect()
			return
		end
		local bob = math.sin(age * 22 + phase) * 1.4 -- взмах вверх-вниз
		local pos = start + dir * (speed * age) + Vector3.new(0, bob, 0)
		-- лицом по курсу + «банк» крыльев вокруг оси движения
		bat:PivotTo(CFrame.lookAt(pos, pos + dir) * CFrame.Angles(0, 0, math.sin(age * 22 + phase) * 0.6))
	end)
	Debris:AddItem(bat, life + 0.1)
end

batScare.OnClientEvent:Connect(function(origin: Vector3, count: number, kind: string)
	if typeof(origin) ~= "Vector3" then return end
	if kind == "swarm" then
		if not jumpscaresOn then return end -- уважаем пугливых
		if SCREECH_ID ~= "" then screech:Play() end
		for _ = 1, count do
			launchOne(origin, true)
		end
	else -- flyby: одна-две неспешные мыши мимо
		for _ = 1, count do
			launchOne(origin, false)
		end
	end
end)
