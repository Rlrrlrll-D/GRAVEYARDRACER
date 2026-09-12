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
local PlayerFlow = require(script.Parent:WaitForChild("PlayerFlow"))

local TAG = "DevGarageBody"
local TURRET_PARTS = { "TurretBase", "TurretMast", "Turret", "GunCradle" } -- GunMesh приедет с люлькой
local RANGE_DEPTH = 46 -- стена-мишень перед стволами
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

	local weapons = ShopCatalog.weapons()
	local w = GAP_X * math.max(#skins, #weapons) + 12
	local d = GAP_Z * (#bodies + 1) + 12 + RANGE_DEPTH + 6 -- + ряд стволов и тир до стены
	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.CanCollide = false
	floor.Size = Vector3.new(w, 1, d)
	floor.CFrame = CFrame.new(origin - Vector3.new(0, 0.5, (RANGE_DEPTH + 6) / 2)) -- тир уходит в −Z
	floor.Material = Enum.Material.Slate
	floor.Color = Color3.fromRGB(38, 36, 40)
	floor.Parent = model

	-- Своего света у площадки НЕТ (юзер 2026-09-12: никакого свечения — только свет
	-- сцены; ночью судить при луне, как в заезде без фонарей).

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
	-- // Оружейная песочница: ряд турельных стоек с каждым стволом + стена-мишень.
	-- Стойка = турель из VehicleTemplate (основание, мачта, поворот, люлька) на тумбе,
	-- всё на якоре; ствол ставит PlayerFlow.mountWeapon — та же посадка, что на машине.
	-- Стрельбу (трассер/звук) рисует клиент сам (SkullTune, ShotFX): сервер тут не нужен.
	local tpl = ServerStorage:FindFirstChild("VehicleTemplate")
	local tSeat = tpl and tpl:FindFirstChild("DriveSeat")
	local tBase = tpl and tpl:FindFirstChild("TurretBase", true)
	if tpl and tSeat and tSeat:IsA("BasePart") and tBase and tBase:IsA("BasePart") then
		local rowZ = origin.Z - (GAP_Z * (#bodies + 1)) / 2 -- перед рядами кузовов, стреляют в −Z, где никого нет
		for wi, item in weapons do
			local rig = Instance.new("Model")
			rig.Name = "GarageGun_" .. item.id
			rig:SetAttribute("DevWeapon", item.id)
			local x = origin.X - (GAP_X * (#weapons - 1)) / 2 + GAP_X * (wi - 1)
			-- виртуальное сиденье: та же высота, что у кузовов; турель встаёт как на машине.
			-- В покое ствол шаблона смотрит НАЗАД (в заезде его доворачивает шарнир прицела),
			-- поэтому стойку разворачиваем на 180°: стрелять в −Z, к стене, а не в кузова.
			local slot = CFrame.new(x, origin.Y - ground.Y, rowZ) * CFrame.Angles(0, math.pi, 0)
			for _, name in TURRET_PARTS do
				local src = tpl:FindFirstChild(name, true)
				if src and src:IsA("BasePart") then
					local part = src:Clone()
					for _, c in part:GetDescendants() do
						if c:IsA("Weld") or c:IsA("WeldConstraint") or c:IsA("HingeConstraint") then
							c:Destroy() -- всё на якоре, шарниры и сварки не нужны
						end
					end
					part.Anchored = true
					part.CanCollide = false
					part.CFrame = slot * ((tSeat :: BasePart).CFrame:Inverse() * src.CFrame)
					part.Parent = rig
				end
			end
			-- тумба под основанием
			local base = rig:FindFirstChild("TurretBase")
			if base and base:IsA("BasePart") then
				local post = Instance.new("Part")
				post.Name = "Post"
				post.Anchored = true
				post.CanCollide = false
				post.Material = Enum.Material.Slate
				post.Color = Color3.fromRGB(50, 48, 52)
				local h = base.Position.Y - base.Size.Y / 2 - origin.Y
				post.Size = Vector3.new(2, math.max(h, 0.5), 2)
				post.CFrame = CFrame.new(base.Position.X, origin.Y + post.Size.Y / 2, base.Position.Z)
				post.Parent = rig
			end
			rig.Parent = model
			PlayerFlow.mountWeapon(rig, item, nil)
			local gun = rig:FindFirstChild("GunMesh", true)
			if gun and gun:IsA("BasePart") then
				gun.Anchored = true
			end
			local label = Instance.new("Part")
			label.Name = "Label"
			label.Anchored = true
			label.CanCollide = false
			label.Transparency = 1
			label.Size = Vector3.new(1, 1, 1)
			label.CFrame = CFrame.new(x, origin.Y + 0.6, rowZ + 6)
			label.Parent = rig
			local bb = Instance.new("BillboardGui")
			bb.Size = UDim2.fromOffset(180, 24)
			bb.AlwaysOnTop = true
			bb.MaxDistance = 200
			bb.Parent = label
			local t = Instance.new("TextLabel")
			t.Size = UDim2.fromScale(1, 1)
			t.BackgroundTransparency = 1
			t.Font = Enum.Font.Code
			t.TextSize = 14
			t.TextColor3 = Color3.fromRGB(220, 210, 190)
			t.Text = item.name
			t.Parent = bb
		end
		-- стена-мишень: перед стволами (они смотрят в −Z, как машина от сиденья)
		local wall = Instance.new("Part")
		wall.Name = "TargetWall"
		wall.Anchored = true
		wall.CanCollide = false
		wall.Material = Enum.Material.WoodPlanks
		wall.Color = Color3.fromRGB(96, 78, 58)
		wall.Size = Vector3.new(w, 14, 1)
		wall.CFrame = CFrame.new(origin.X, origin.Y + 7, rowZ - RANGE_DEPTH)
		wall.Parent = model
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
