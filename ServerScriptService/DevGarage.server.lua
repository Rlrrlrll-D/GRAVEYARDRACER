--!strict
-- Script: ServerScriptService.DevGarage
-- ГАРАЖ-ПЕСОЧНИЦА (дев, только Studio): по просьбе клиента (SkullTune, кнопка GARAGE)
-- ставит над стартом площадку и на ней ВСЕ кузова × ВСЕ краски из каталога — чтобы
-- крутить черепа/тон/краску, глядя сразу на всё, а не по одной машине в заезде (юзер
-- 2026-09-12: «песочница-гараж вне игры со всеми моделями»).
--
-- Шаблоны кузовов лежат в ServerStorage — клиенту их не достать, поэтому клоны делает
-- сервер; текстуру с черепами (EditableImage, только клиент) надевает тот же сторож
-- StarterPlayerScripts.RankSkull, что и на машины: модели помечены тегом DevGarageBody,
-- у каждой OwnerUserId = заказчик (ранг — его) и DevSkin = краска этого экземпляра.
-- Тег PlayerVehicle НЕ используем нарочно: по нему живут зомби, гонка и физика.
--
-- ТОЛЬКО STUDIO: ремоут DevGarage в живой игре не создаётся (как DevZombies), поэтому
-- его нет и в манифесте ReplicatedStorage.Net.

local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
	return
end

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ShopCatalog = require(ReplicatedStorage:WaitForChild("ShopCatalog"))

local TAG = "DevGarageBody"
local GAP_X = 16 -- между красками
local GAP_Z = 22 -- между кузовами
local RISE = 70 -- площадка над персонажем заказчика

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local remote = Instance.new("RemoteEvent")
remote.Name = "DevGarage"
remote.Parent = remotes

-- Точка «земли» в системе сиденья — как в PlayerFlow.baseGround: кузов встаёт на
-- площадку ровно так же, как на колёса живой машины.
local function seatGround(): Vector3
	local tpl = ServerStorage:FindFirstChild("VehicleTemplate")
	local seat = tpl and tpl:FindFirstChild("DriveSeat")
	local wheels = tpl and tpl:FindFirstChild("Wheels")
	if not (seat and seat:IsA("BasePart") and wheels) then
		return Vector3.new(0, -2, 0)
	end
	local sum, n, radius = Vector3.zero, 0, 0
	for _, w in wheels:GetChildren() do
		if w:IsA("BasePart") then
			sum += seat.CFrame:ToObjectSpace(w.CFrame).Position
			n += 1
			radius = math.max(radius, w.Size.Y / 2)
		end
	end
	if n == 0 then
		return Vector3.new(0, -2, 0)
	end
	local base = sum / n
	return Vector3.new(base.X, base.Y - radius, base.Z)
end

local garage: Model? = nil

local function teardown()
	if garage then
		garage:Destroy()
		garage = nil
	end
end

local function build(player: Player)
	teardown()
	local templates = ServerStorage:FindFirstChild("BodyTemplates")
	if not templates then
		warn("[DevGarage] нет ServerStorage.BodyTemplates")
		return
	end
	local bodies = ShopCatalog.bodies()
	local skins = ShopCatalog.skins()
	local ground = seatGround()

	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local origin = (hrp and hrp:IsA("BasePart")) and hrp.Position + Vector3.new(0, RISE, 0) or Vector3.new(0, 300, 0)
	origin = Vector3.new(math.floor(origin.X), math.floor(origin.Y), math.floor(origin.Z))

	local model = Instance.new("Model")
	model.Name = "DevGarage"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent -- далеко от персонажа, а видеть надо
	model:SetAttribute("Origin", origin)

	local w = GAP_X * #skins + 12
	local d = GAP_Z * #bodies + 12
	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.CanCollide = false
	floor.Size = Vector3.new(w, 1, d)
	floor.CFrame = CFrame.new(origin - Vector3.new(0, 0.5, 0))
	floor.Material = Enum.Material.Slate
	floor.Color = Color3.fromRGB(38, 36, 40)
	floor.Parent = model

	-- два мягких фонаря площадки: без них на высоте одна луна, кузова ночью чёрные
	for _, dx in { -w / 3, w / 3 } do
		local lampPart = Instance.new("Part")
		lampPart.Name = "Lamp"
		lampPart.Anchored = true
		lampPart.CanCollide = false
		lampPart.Transparency = 1
		lampPart.Size = Vector3.new(1, 1, 1)
		lampPart.CFrame = CFrame.new(origin + Vector3.new(dx, 14, 0))
		lampPart.Parent = model
		local light = Instance.new("PointLight")
		light.Brightness = 0.8
		light.Range = 60
		light.Color = Color3.fromRGB(255, 214, 160)
		light.Shadows = false
		light.Parent = lampPart
	end

	for bi, bodyItem in bodies do
		local tpl = bodyItem.bodyTemplate and templates:FindFirstChild(bodyItem.bodyTemplate)
		if not (tpl and tpl:IsA("BasePart")) then
			continue
		end
		local fit = tpl:GetAttribute("FitPivot")
		local offset = typeof(fit) == "Vector3" and fit or Vector3.zero
		for si, skin in skins do
			local car = Instance.new("Model")
			car.Name = ("Garage_%s_%s"):format(bodyItem.id, skin.id)
			car:SetAttribute("OwnerUserId", player.UserId)
			car:SetAttribute("DevSkin", skin.id)
			local body = (tpl :: BasePart):Clone()
			body.Name = "BuggyBody"
			body:SetAttribute("BodyId", bodyItem.id)
			for _, c in body:GetDescendants() do
				-- фары шаблона (SpotLight в HeadlightL/R): десять кузовов светили друг на
				-- друга, «модели светятся» (юзер 2026-09-12) — в гараже свет только сцены
				if c:IsA("Light") then
					c:Destroy()
				elseif c:IsA("BasePart") then
					c.Anchored = true
					c.CanCollide = false
					if skin.color then
						c.Color = skin.color
					end
				end
			end
			body.Anchored = true
			body.CanCollide = false
			if skin.color then
				body.Color = skin.color
			end
			if skin.material then
				body.Material = skin.material
			end
			body.Parent = car
			-- слот: краски вдоль X, кузова вдоль Z; носом к −Z (как сиденье без поворота)
			local x = origin.X - (GAP_X * (#skins - 1)) / 2 + GAP_X * (si - 1)
			local z = origin.Z - (GAP_Z * (#bodies - 1)) / 2 + GAP_Z * (bi - 1)
			local slot = CFrame.new(x, origin.Y - ground.Y, z)
			body:PivotTo(slot * CFrame.new(ground + offset))
			car.Parent = model
			CollectionService:AddTag(car, TAG)

			local label = Instance.new("Part")
			label.Name = "Label"
			label.Anchored = true
			label.CanCollide = false
			label.Transparency = 1
			label.Size = Vector3.new(1, 1, 1)
			label.CFrame = CFrame.new(x, origin.Y + 0.6, z + 9)
			label.Parent = car
			local bb = Instance.new("BillboardGui")
			bb.Size = UDim2.fromOffset(160, 24)
			bb.AlwaysOnTop = true
			bb.MaxDistance = 200
			bb.Parent = label
			local t = Instance.new("TextLabel")
			t.Size = UDim2.fromScale(1, 1)
			t.BackgroundTransparency = 1
			t.Font = Enum.Font.Code
			t.TextSize = 14
			t.TextColor3 = Color3.fromRGB(220, 210, 190)
			t.Text = skin.name
			t.Parent = bb
		end
	end
	model.Parent = workspace
	garage = model
	print(("[DevGarage] гараж: %d кузовов × %d красок над %s"):format(#bodies, #skins, tostring(origin)))
end

remote.OnServerEvent:Connect(function(player, on)
	if on == true then
		build(player)
	else
		teardown()
	end
end)

game:GetService("Players").PlayerRemoving:Connect(function()
	if #game:GetService("Players"):GetPlayers() <= 1 then
		teardown()
	end
end)
