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
local LIFT = GameConfig.Ranks.SkullLift or 0

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
	-- Композит всегда: он же несёт краску (текстура на MeshPart отключает Color3, см.
	-- RankSkull.compose). Без черепов — просто крашеный кузов.
	-- Дев-подкрутка (SkullTune) подменяет режим/плотность/подъём/краску и цвет ступени.
	local o = RankSkull.Overrides
	local zones = spec and spec.zones or {}
	local colorName = spec and spec.color or nil
	if o and o.colorName then
		colorName = o.colorName
		if #zones == 0 then
			zones = { "top", "left", "right", "rear" } -- крутить можно и на нулевом ранге
		end
	end
	local img = RankSkull.compose(bodyId, zones, colorName,
		(o and o.mode) or MODE, (o and o.opacity) or OPACITY, (o and o.tint) or body.Color, (o and o.lift) or LIFT,
		RankSkull.worn(body)) -- свою картинку переписываем на месте, а не плодим новые
	if not body.Parent then
		return -- кузов успели заменить, пока читали текстуру
	end
	RankSkull.apply(body :: MeshPart, img)
	setCrossHidden(body, img ~= nil and spec ~= nil and table.find(spec.zones, "top") ~= nil)
end

local watched: { [Model]: { conns: { RBXScriptConnection }, redress: () -> () } } = {}

local function watchCar(car: Model)
	if watched[car] then
		return
	end
	local conns: { RBXScriptConnection } = {}

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
	-- кузов сменили в магазине: старая деталь больше ничего не носит — отпустить
	-- картинку, иначе пул считает её занятой навсегда
	table.insert(conns, car.ChildRemoved:Connect(function(child)
		if child.Name == "BuggyBody" then
			RankSkull.release(child)
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
			local body = car:FindFirstChild("BuggyBody")
			if body then
				RankSkull.release(body)
			end
			for _, c in conns do
				c:Disconnect()
			end
			for _, c in statConns do
				c:Disconnect()
			end
			watched[car] = nil
		end
	end))

	watched[car] = { conns = conns, redress = redress }
	rewireDriver()
	redress()
end

-- Дев-подкрутка: пересобрать всем машинам, что на виду.
RankSkull.OverridesChanged.Event:Connect(function()
	for _, w in watched do
		w.redress()
	end
end)

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
