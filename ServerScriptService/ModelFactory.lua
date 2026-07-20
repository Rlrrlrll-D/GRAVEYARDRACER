--!strict
-- ModuleScript: ServerScriptService.ModelFactory
-- Собирает модели игры из примитивов (Part). Ничего не нужно скачивать
-- из Toolbox — все модели строятся кодом и потом легко перекрашиваются.

local ModelFactory = {}

local function newPart(props: {[string]: any}): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(part :: any)[key] = value
	end
	return part
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
end

-- =============================================================== TOMBSTONE ==
-- Надгробие-плита со скруглённым верхом и постаментом (тег Hazard).
function ModelFactory.Tombstone(): Model
	local model = Instance.new("Model")
	model.Name = "Tombstone"

	local base = newPart({
		Name = "Base", Size = Vector3.new(3.4, 0.6, 1.8),
		Color = Color3.fromRGB(95, 95, 105), Material = Enum.Material.Concrete,
	})
	base.Parent = model

	local slab = newPart({
		Name = "Slab", Size = Vector3.new(2.6, 3.2, 0.8),
		Color = Color3.fromRGB(120, 120, 132), Material = Enum.Material.Slate,
		CFrame = base.CFrame * CFrame.new(0, 1.9, 0),
	})
	slab.Parent = model

	local top = newPart({
		Name = "Top", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, 2.6, 2.6),
		Color = slab.Color, Material = Enum.Material.Slate,
		CFrame = slab.CFrame * CFrame.new(0, 1.6, 0) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(math.rad(90), 0, 0),
	})
	top.Parent = model

	model.PrimaryPart = base
	return model
end

-- ============================================================= GRAVEMARKER ==
-- Земляной холмик + маленький крест (тег Grave, точка спавна зомби).
function ModelFactory.GraveMarker(): Model
	local model = Instance.new("Model")
	model.Name = "GraveMarker"

	local mound = newPart({
		Name = "Mound", Size = Vector3.new(4, 0.7, 7),
		Color = Color3.fromRGB(72, 60, 48), Material = Enum.Material.Ground,
	})
	mound.Parent = model

	local post = newPart({
		Name = "CrossPost", Size = Vector3.new(0.35, 2.2, 0.35),
		Color = Color3.fromRGB(84, 70, 56), Material = Enum.Material.Wood,
		CFrame = mound.CFrame * CFrame.new(0, 1.4, -3),
	})
	post.Parent = model

	local bar = newPart({
		Name = "CrossBar", Size = Vector3.new(1.5, 0.32, 0.32),
		Color = post.Color, Material = Enum.Material.Wood,
		CFrame = post.CFrame * CFrame.new(0, 0.55, 0),
	})
	bar.Parent = model

	model.PrimaryPart = mound
	return model
end

-- ==================================================================== LAMP ==
-- Кованый фонарный столб с плафоном (в Bulb вешается PointLight+FlickerLight).
function ModelFactory.Lamp(): Model
	local model = Instance.new("Model")
	model.Name = "Lamp"

	local pole = newPart({
		Name = "Body", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(9, 0.5, 0.5),
		Color = Color3.fromRGB(38, 38, 46), Material = Enum.Material.Metal,
		CFrame = CFrame.new(0, 4.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
	})
	pole.Parent = model

	local cage = newPart({
		Name = "Cage", Size = Vector3.new(1.3, 1.6, 1.3),
		Color = Color3.fromRGB(30, 30, 38), Material = Enum.Material.Metal,
		Transparency = 0.35,
		CFrame = CFrame.new(0, 9.4, 0),
	})
	cage.Parent = model

	local bulb = newPart({
		Name = "Bulb", Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.9, 0.9, 0.9),
		Color = Color3.fromRGB(255, 217, 138), Material = Enum.Material.Neon,
		CFrame = cage.CFrame,
	})
	bulb.Parent = model

	local cap = newPart({
		Name = "Cap", Size = Vector3.new(1.7, 0.35, 1.7),
		Color = Color3.fromRGB(30, 30, 38), Material = Enum.Material.Metal,
		CFrame = cage.CFrame * CFrame.new(0, 1, 0),
	})
	cap.Parent = model

	model.PrimaryPart = pole
	return model
end

-- ================================================================ DEADTREE ==
-- Кривое мёртвое дерево: наклонный ствол + 3 ветки.
function ModelFactory.DeadTree(): Model
	local model = Instance.new("Model")
	model.Name = "DeadTree"
	local woodColor = Color3.fromRGB(56, 48, 40)

	local trunk = newPart({
		Name = "Trunk", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(15, 2.4, 2.4),
		Color = woodColor, Material = Enum.Material.Wood,
		CFrame = CFrame.new(0, 7.5, 0) * CFrame.Angles(0, 0, math.rad(90)), -- ствол вертикально (не кривой)
	})
	trunk.Parent = model

	local branchSpecs = {
		{ y = 10,   yaw = 20,  pitch = 48, len = 6.5 },
		{ y = 12,   yaw = 160, pitch = 55, len = 5.5 },
		{ y = 13.5, yaw = 280, pitch = 40, len = 4.5 },
	}
	for i, spec in branchSpecs do
		local branch = newPart({
			Name = `Branch{i}`, Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(spec.len, 0.9, 0.9),
			Color = woodColor, Material = Enum.Material.Wood,
			CFrame = CFrame.new(0, spec.y, 0)
				* CFrame.Angles(0, math.rad(spec.yaw), 0)
				* CFrame.Angles(0, 0, math.rad(spec.pitch))
				* CFrame.new(spec.len / 2, 0, 0),
		})
		branch.Parent = model
	end

	model.PrimaryPart = trunk
	return model
end

-- =============================================================== MAUSOLEUM ==
-- Мавзолей: корпус, двускатная крыша, колонны и чёрный дверной проём.
function ModelFactory.Mausoleum(): Model
	local model = Instance.new("Model")
	model.Name = "Mausoleum"
	local stone = Color3.fromRGB(88, 90, 104)

	local body = newPart({
		Name = "Body", Size = Vector3.new(18, 10, 13),
		Color = stone, Material = Enum.Material.Concrete,
		CFrame = CFrame.new(0, 5, 0),
	})
	body.Parent = model

	local roof = newPart({
		Name = "Roof", Size = Vector3.new(20, 4, 15),
		Color = Color3.fromRGB(66, 68, 82), Material = Enum.Material.Slate,
		CFrame = CFrame.new(0, 12, 0),
	})
	roof.Parent = model
	local roofMesh = Instance.new("SpecialMesh")
	roofMesh.MeshType = Enum.MeshType.Wedge
	roofMesh.Parent = roof

	local door = newPart({
		Name = "Doorway", Size = Vector3.new(4, 7, 0.4),
		Color = Color3.fromRGB(12, 12, 16), Material = Enum.Material.SmoothPlastic,
		CFrame = CFrame.new(0, 3.5, -6.6),
	})
	door.Parent = model

	for _, xSign in { -1, 1 } do
		local column = newPart({
			Name = "Column", Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(9, 1.4, 1.4),
			Color = stone, Material = Enum.Material.Concrete,
			CFrame = CFrame.new(xSign * 7, 4.5, -7.2) * CFrame.Angles(0, 0, math.rad(90)),
		})
		column.Parent = model
	end

	model.PrimaryPart = body
	return model
end

-- =================================================================== BUGGY ==
-- Рабочая машина: шасси, 4 колеса на констрейнтах, DriveSeat,
-- турель (TurretBase + Turret + TurretHinge/Servo + Muzzle).
-- Задние колёса — моторы, передние — сервоповорот (см. VehicleDrive).
function ModelFactory.Buggy(): Model
	local model = Instance.new("Model")
	model.Name = "GraveyardBuggy"

	local chassis = newPart({
		Name = "Chassis", Size = Vector3.new(6, 1.2, 10),
		Color = Color3.fromRGB(96, 58, 34), Material = Enum.Material.DiamondPlate,
		CFrame = CFrame.new(0, 2.4, 0),
		Anchored = false,
	})
	chassis.Parent = model

	local hood = newPart({
		Name = "Hood", Size = Vector3.new(5.4, 1, 3),
		Color = Color3.fromRGB(80, 48, 28), Material = Enum.Material.DiamondPlate,
		CFrame = chassis.CFrame * CFrame.new(0, 1.1, -3.2),
		Anchored = false,
	})
	hood.Parent = model
	weld(chassis, hood)

	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriveSeat"
	seat.Size = Vector3.new(2.4, 0.8, 2.4)
	seat.Color = Color3.fromRGB(40, 40, 46)
	seat.Material = Enum.Material.Fabric
	seat.CFrame = chassis.CFrame * CFrame.new(0, 1, 1)
	seat.MaxSpeed = 50
	seat.Torque = 12
	seat.TurnSpeed = 12
	seat.Anchored = false
	seat.Parent = model
	weld(chassis, seat)

	-- // Колёса ---------------------------------------------------------------
	local wheelPositions = {
		FL = Vector3.new(-3.4, -0.9, -3.4),
		FR = Vector3.new(3.4, -0.9, -3.4),
		RL = Vector3.new(-3.4, -0.9, 3.4),
		RR = Vector3.new(3.4, -0.9, 3.4),
	}
	for name, offset in wheelPositions do
		local wheel = newPart({
			Name = `Wheel{name}`, Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.2, 2.8, 2.8),
			Color = Color3.fromRGB(25, 25, 28), Material = Enum.Material.Rubber,
			CFrame = chassis.CFrame * CFrame.new(offset),
			Anchored = false,
		})
		wheel.Parent = model

		local chassisAttachment = Instance.new("Attachment")
		chassisAttachment.Name = `WheelMount{name}`
		chassisAttachment.Position = offset
		chassisAttachment.Orientation = Vector3.new(0, 0, 90) -- ось шарнира вбок
		chassisAttachment.Parent = chassis

		local wheelAttachment = Instance.new("Attachment")
		wheelAttachment.Orientation = Vector3.new(0, 0, 90)
		wheelAttachment.Parent = wheel

		local hinge = Instance.new("HingeConstraint")
		hinge.Name = `Hinge{name}`
		hinge.Attachment0 = chassisAttachment
		hinge.Attachment1 = wheelAttachment
		local isRear = name == "RL" or name == "RR"
		if isRear then
			hinge.ActuatorType = Enum.ActuatorType.Motor
			hinge.MotorMaxTorque = 20000
			hinge.AngularVelocity = 0
		else
			hinge.ActuatorType = Enum.ActuatorType.None -- свободное вращение
		end
		hinge.Parent = chassis
	end

	-- // Турель ---------------------------------------------------------------
	local turretBase = newPart({
		Name = "TurretBase", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 2.4, 2.4),
		Color = Color3.fromRGB(52, 52, 60), Material = Enum.Material.Metal,
		CFrame = chassis.CFrame * CFrame.new(0, 1, 2.8) * CFrame.Angles(0, 0, math.rad(90)),
		Anchored = false,
	})
	turretBase.Parent = model
	weld(chassis, turretBase)

	local turret = newPart({
		Name = "Turret", Size = Vector3.new(0.7, 0.7, 3.4),
		Color = Color3.fromRGB(70, 70, 80), Material = Enum.Material.Metal,
		CFrame = turretBase.CFrame * CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.rad(-90)) * CFrame.new(0, 0.8, -1),
		Anchored = false,
	})
	turret.Parent = model

	local baseAttachment = Instance.new("Attachment")
	baseAttachment.Name = "TurretPivot"
	baseAttachment.Orientation = Vector3.new(0, 0, 90) -- ось вращения вертикально
	baseAttachment.Parent = turretBase

	local turretAttachment = Instance.new("Attachment")
	turretAttachment.Position = Vector3.new(0, -0.8, 1)
	turretAttachment.Orientation = Vector3.new(0, 90, 0)
	turretAttachment.Parent = turret

	local turretHinge = Instance.new("HingeConstraint")
	turretHinge.Name = "TurretHinge"
	turretHinge.Attachment0 = baseAttachment
	turretHinge.Attachment1 = turretAttachment
	turretHinge.ActuatorType = Enum.ActuatorType.Servo
	turretHinge.ServoMaxTorque = 50000
	turretHinge.AngularSpeed = 6
	turretHinge.Parent = turretBase

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0, -1.9)
	muzzle.Parent = turret

	model.PrimaryPart = chassis
	return model
end

return ModelFactory
