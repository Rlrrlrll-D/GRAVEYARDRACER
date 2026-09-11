--!strict
-- LocalScript: StarterPlayerScripts.RankSkull
-- ЧЕРЕПА-РАНГИ НА КУЗОВАХ: следит за машинами игроков и надевает на кузов текстуру
-- с черепами по рангу водителя (RankSkull.compose). Только клиент — EditableImage не
-- реплицируется, поэтому каждый клиент собирает картинки сам; композит на состояние
-- ранга один, машины с одинаковым рангом делят его через кэш модуля.
--
-- Что слушаем:
--   * тег PlayerVehicle — машина появилась; OwnerUserId — чья;
--   * BuggyBody в машине — кузов подставляют при выдаче и меняют в магазине
--     (applyBody), поэтому ждём деталь и следим за ChildAdded;
--   * ZombiesDefeated / Wins водителя — ранг вырос по ходу сессии;
--   * BodyId кузова — какой атлас брать.
-- Крест на крышке гроба (LidCross*) гаснет, когда на крышке рисуется череп: юзер —
-- «крест не должен быть на том же месте с черепом одновременно».

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local Ranks = require(ReplicatedStorage:WaitForChild("Ranks"))
local RankSkull = require(ReplicatedStorage:WaitForChild("RankSkull"))

local MODE = GameConfig.Ranks.SkullMode
local OPACITY = GameConfig.Ranks.SkullOpacity

-- Что рисовать на ступени: nil — ничего (нулевой ранг или ступень без черепа).
local function skullFor(standing: Ranks.Standing): { zones: { string }, color: string }?
	local tier = GameConfig.Ranks.Tiers[standing.index]
	return tier and tier.skull or nil
end

local function setCrossHidden(body: BasePart, hidden: boolean)
	for _, c in body:GetChildren() do
		if c:IsA("BasePart") and c.Name:sub(1, 8) == "LidCross" then
			c.Transparency = if hidden then 1 else 0
		end
	end
end

-- Собрать и надеть на кузов то, что положено водителю. Йилдит на первом кузове
-- каждого типа (чтение текстуры), поэтому вызывается из task.spawn.
local function dress(body: BasePart, driver: Player)
	local bodyId = body:GetAttribute("BodyId")
	if type(bodyId) ~= "string" then
		return
	end
	local spec = skullFor(Ranks.forPlayer(driver))
	local img = nil
	if spec then
		img = RankSkull.compose(bodyId, spec.zones, spec.color, MODE, OPACITY, body.Color)
	end
	if not body.Parent then
		return -- кузов успели заменить, пока читали текстуру
	end
	RankSkull.apply(body :: MeshPart, img)
	setCrossHidden(body, img ~= nil and spec ~= nil and table.find(spec.zones, "top") ~= nil)
end

local watched: { [Model]: { RBXScriptConnection } } = {}

local function watchCar(car: Model)
	if watched[car] then
		return
	end
	local conns: { RBXScriptConnection } = {}
	watched[car] = conns

	local function driver(): Player?
		local id = car:GetAttribute("OwnerUserId")
		return if type(id) == "number" then Players:GetPlayerByUserId(id) else nil
	end
	local colorHooked: { [Instance]: boolean } = {}
	local function redress()
		local plr = driver()
		local body = car:FindFirstChild("BuggyBody")
		if plr and body and body:IsA("MeshPart") then
			-- краску меняют в магазине на живой машине: холст гроба несёт её цвет,
			-- значит пересобрать (см. RankSkull.compose про Color3 и текстуры)
			if not colorHooked[body] then
				colorHooked[body] = true
				body:GetPropertyChangedSignal("Color"):Connect(function()
					local p = driver()
					if p and body.Parent then
						task.spawn(dress, body, p)
					end
				end)
			end
			task.spawn(dress, body, plr)
		end
	end

	table.insert(conns, car.ChildAdded:Connect(function(child)
		if child.Name == "BuggyBody" then
			-- атрибут BodyId ставится до Parent, но дадим кадр на репликацию детей (крест)
			task.defer(redress)
		end
	end))
	table.insert(conns, car:GetAttributeChangedSignal("OwnerUserId"):Connect(redress))

	-- ранг водителя растёт по ходу сессии: пересобрать, когда изменились статы
	local lastDriver: Player? = nil
	local statConns: { RBXScriptConnection } = {}
	local function rewireDriver()
		local plr = driver()
		if plr == lastDriver then
			return
		end
		for _, c in statConns do
			c:Disconnect()
		end
		table.clear(statConns)
		lastDriver = plr
		if plr then
			for _, attr in { "ZombiesDefeated", "Wins" } do
				table.insert(statConns, plr:GetAttributeChangedSignal(attr):Connect(redress))
			end
		end
	end
	table.insert(conns, car:GetAttributeChangedSignal("OwnerUserId"):Connect(rewireDriver))
	table.insert(conns, car.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			for _, c in conns do
				c:Disconnect()
			end
			for _, c in statConns do
				c:Disconnect()
			end
			watched[car] = nil
		end
	end))

	rewireDriver()
	redress()
end

for _, car in CollectionService:GetTagged("PlayerVehicle") do
	if car:IsA("Model") then
		watchCar(car)
	end
end
CollectionService:GetInstanceAddedSignal("PlayerVehicle"):Connect(function(car)
	if car:IsA("Model") then
		watchCar(car)
	end
end)
