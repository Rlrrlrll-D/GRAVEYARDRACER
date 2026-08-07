--!strict
-- LocalScript: StarterPlayerScripts.WheelDust
-- НИЗКИЙ ШЛЕЙФ ПЫЛИ ИЗ-ПОД КОЛЁС. Плоские лоскуты у самой земли: появляются за задним
-- колесом, расползаются, приподнимаются на ладонь и тают за полсекунды.
--
-- ПОЧЕМУ НЕ РОДНОЙ ДЫМ A-CHASSIS. Плагин «Smoke [FE+]» в машине есть, но мёртвый: он
-- ждёт `car.Smoke_FE`, которого туда никто не копирует, и вечно висит на WaitForChild.
-- Оживлять его незачем — это классический AC6-дым (спрайт 34098552, частицы до 9.4
-- studs, живут 3.5с), то самое мутное пятно, которое юзер велел выкинуть. И срабатывает
-- он только на пробуксовке, а не при обычной езде по грунту.
--
-- ПОЧЕМУ ЛОСКУТ — ЭТО ДЕТАЛЬ, А НЕ СПРАЙТ. Ни текстуры, ни частиц: приплюснутый шар
-- с чистым цветом. У него резкий силуэт, он не размывается вблизи и не «мылит» кадр —
-- ровно то требование к эффектам, что и у остальных (анимация объекта, не облако).
--
-- ИМЕННО ШАР, А НЕ ЛЕЖАЩИЙ ДИСК. Первый заход рисовал плоские блины на грунте: сверху
-- они читались пятнами краски, а с низкой камеры — с ребра, то есть никак. Приплюснутый
-- шар (высота ≈ 0.45 ширины) даёт объём с любого угла и всё равно стелется низко.
--
-- ЦВЕТ БЕРЁТСЯ ОТ ЗЕМЛИ ПОД КОЛЕСОМ, а не задан константой: трасса идёт и по грунту, и
-- по траве, и пыль обязана быть цвета того, что колесо разрыло. Луч всё равно нужен —
-- по нему же понятно, что колесо вообще касается земли (в прыжке пыли нет).
--
-- КЛИЕНТ-ОНЛИ И ПУЛ. Лоскуты живут только у зрителя (сервер о них не знает, трафика
-- ноль) и переиспользуются: создавать десятки деталей в кадре — это фриз на встроенной
-- графике. Занятый лоскут НИКОГДА не отбираем: кончился пул — пропускаем выброс.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local POOL_SIZE = 64 -- машина в разгоне держит в воздухе до 18 лоскутов; рядом всегда пара машин
local PARK = Vector3.new(0, -900, 0) -- «гараж» простаивающих лоскутов, под картой
local PUFF_LIFE = 0.6
local EMIT_PERIOD = 0.035 -- как часто машина роняет лоскут (чередуя колёса)
local MIN_SPEED = 12 -- studs/с: медленнее — колесо не разрывает грунт
local FULL_SPEED = 60 -- на этой скорости шлейф максимальный
local TELEPORT_SPEED = 300 -- быстрее этого — не езда, а перенос на грид: пыли не будет
local START_W, END_W = 1.3, 5.6 -- ширина лоскута в начале и в конце жизни
-- ПРОЗРАЧНОСТЬ ВЫСОКАЯ С САМОГО НАЧАЛА. Плотный диск на дороге читается пятном
-- краски, а не взвесью; шлейф собирается из НАЛОЖЕНИЯ бледных лоскутов, поэтому
-- каждый по отдельности обязан быть еле виден.
local START_T = 0.55
local FLATNESS = 0.45 -- насколько шар приплюснут: 1 = мяч, 0.45 = низкое облачко
local RISE = 1.4 -- на сколько поднимется за жизнь: пыль всё-таки всплывает, а не лежит
local LIFT = 0.35 -- на сколько приподнят над грунтом в момент рождения
local TILT = math.rad(8) -- случайный завал лоскута: идеально плоская лента выдаёт декаль
local DRIFT_BACK = 5 -- studs/с назад по ходу машины: пыль отстаёт, а не летит с колесом
local VIEW_RANGE = 220 -- дальше камеры не рисуем: чужую пыль за полкарты всё равно не видно

local folder = Instance.new("Folder")
folder.Name = "_DustFX"
folder.Parent = workspace

type Puff = {
	part: Part,
	mesh: SpecialMesh,
	born: number,
	base: CFrame,
	drift: Vector3,
}

local pool: { Part } = {}
local live: { Puff } = {}

for _ = 1, POOL_SIZE do
	local p = Instance.new("Part")
	p.Name = "Dust"
	p.Anchored = true
	p.CanCollide = false
	-- CanQuery=false обязателен: иначе лоскуты ловят луч турели и выстрел вязнет в
	-- собственной пыли. CanTouch=false — чтобы не будить Touched у машины и зомби.
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Transparency = 1
	p.Size = Vector3.new(1, 0.25, 1)
	p.Position = PARK
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	p.Parent = folder
	table.insert(pool, p)
end

local function takePuff(): Part?
	return table.remove(pool)
end

local function releasePuff(puff: Puff)
	puff.part.Transparency = 1
	puff.part.Position = PARK
	table.insert(pool, puff.part)
end

-- // Откуда берётся цвет ------------------------------------------------------
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function groundUnder(wheel: BasePart, car: Model): (Vector3?, Color3?, Vector3?)
	rayParams.FilterDescendantsInstances = { car, folder }
	-- Луч начинаем ВЫШЕ центра колеса: на просадке подвески пятно контакта уходит в
	-- грунт, а луч, начатый внутри рельефа, не возвращает ничего — и пыль пропадала бы
	-- ровно там, где её больше всего ждут.
	local reach = wheel.Size.Y / 2 + 3
	local hit = workspace:Raycast(wheel.Position + Vector3.new(0, 1, 0), Vector3.new(0, -reach, 0), rayParams)
	if not hit then
		return nil, nil, nil -- колесо в воздухе: пыли неоткуда взяться
	end
	local color: Color3 = Color3.fromRGB(120, 110, 95) -- запасной грунтовый, если цвет не спросить
	if hit.Instance == workspace.Terrain then
		-- pcall: GetMaterialColor знает не всякий материал (воздух/вода), а ошибка в
		-- Heartbeat — это спам в лог каждый кадр.
		local ok, c = pcall(function()
			return workspace.Terrain:GetMaterialColor(hit.Material)
		end)
		if ok then
			color = c
		end
	elseif hit.Instance:IsA("BasePart") then
		color = (hit.Instance :: BasePart).Color
	end
	-- Пыль СВЕТЛЕЕ грунта: это взвесь, её подсвечивает со всех сторон, и на тёмной
	-- ночной земле лоскут цвета земли попросту не виден.
	color = color:Lerp(Color3.new(1, 1, 1), 0.25)
	return hit.Position, color, hit.Normal
end

-- // Выброс -------------------------------------------------------------------
-- Лоскут ЛОЖИТСЯ НА СКЛОН, а не строго горизонтально: кладбище холмистое, и диск,
-- висящий поперёк уклона, читается как приклеенная к воздуху крышка.
local function lieOnGround(at: Vector3, normal: Vector3, yaw: number): CFrame
	local up = normal.Unit
	local side = up:Cross(Vector3.new(0, 0, 1))
	if side.Magnitude < 0.01 then
		side = up:Cross(Vector3.new(1, 0, 0)) -- склон смотрит вдоль Z: берём другую опору
	end
	side = side.Unit
	return CFrame.fromMatrix(at + up * LIFT, side, up)
		* CFrame.Angles(0, yaw, 0)
		* CFrame.Angles((math.random() - 0.5) * 2 * TILT, 0, (math.random() - 0.5) * 2 * TILT)
end

local function emit(at: Vector3, normal: Vector3, color: Color3, back: Vector3, strength: number)
	local part = takePuff()
	if not part then
		return -- пул кончился: лучше пропустить лоскут, чем отобрать живой
	end
	local mesh = part:FindFirstChildOfClass("SpecialMesh") :: SpecialMesh
	part.Color = color
	table.insert(live, {
		part = part,
		mesh = mesh,
		born = os.clock(),
		base = lieOnGround(at, normal, math.random() * math.pi * 2),
		-- Разброс вбок делает шлейф шлейфом, а не цепочкой одинаковых блинов.
		drift = back * DRIFT_BACK * strength + Vector3.new((math.random() - 0.5) * 2, 0, (math.random() - 0.5) * 2),
	})
end

-- // Цикл ---------------------------------------------------------------------
-- Таблицы СО СЛАБЫМИ КЛЮЧАМИ: машины уничтожаются каждый заезд, и обычная таблица
-- копила бы ссылки на мёртвые модели до конца сессии.
local nextEmitAt: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local wheelToggle: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local lastSeen: { [Model]: { pos: Vector3, at: number, speed: number, heading: Vector3? } } =
	setmetatable({}, { __mode = "k" }) :: any
local STALE_AFTER = 0.35 -- сек без единого сдвига — значит машина правда стоит

-- СКОРОСТЬ МЕРЯЕМ СМЕЩЕНИЕМ, А НЕ AssemblyLinearVelocity. Скорость сборки честна
-- только там, где физику считает этот клиент; у чужих машин она приходит рывками, а у
-- закреплённой (удержание на отсчёте) равна нулю, хотя модель может переезжать. Разница
-- позиций между кадрами верна всегда и стоит одно вычитание.
-- Возвращает скорость и направление движения (не курс: в заносе и на заднем ходу
-- пыль обязана лететь против ХОДА, а не против носа машины).
-- МЕРЯЕМ ОТ ПОСЛЕДНЕГО РЕАЛЬНОГО СДВИГА, А НЕ ОТ ПРОШЛОГО КАДРА. Своя машина
-- движется каждый кадр, а ЧУЖАЯ приезжает пакетами физрепликации (~20 раз в секунду):
-- в кадрах между пакетами разница позиций равна нулю, и наивный расчёт объявлял бы
-- машину стоящей две трети времени — шлейф у соперников рвался бы в клочья. Поэтому
-- кадры без сдвига отдают ПРОШЛУЮ скорость, и только затянувшаяся тишина (STALE_AFTER)
-- считается настоящей остановкой.
local function motionOf(car: Model, seat: BasePart, now: number): (number, Vector3?)
	local pos = seat.Position
	local prev = lastSeen[car]
	if not prev then
		lastSeen[car] = { pos = pos, at = now, speed = 0, heading = nil }
		return 0, nil
	end
	local moved = pos - prev.pos
	local flat = Vector3.new(moved.X, 0, moved.Z)
	if flat.Magnitude < 1e-3 then
		if now - prev.at > STALE_AFTER then
			return 0, nil
		end
		return prev.speed, prev.heading
	end
	local dt = now - prev.at
	local speed = if dt > 0 then flat.Magnitude / dt else 0
	-- Скачок на грид в начале заезда — это не разгон: пылить на телепорте нельзя.
	if speed > TELEPORT_SPEED then
		lastSeen[car] = { pos = pos, at = now, speed = 0, heading = nil }
		return 0, nil
	end
	local heading = flat.Unit
	lastSeen[car] = { pos = pos, at = now, speed = speed, heading = heading }
	return speed, heading
end

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	local camPos = workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position or Vector3.zero

	-- 1) живые лоскуты: растут, всплывают, тают
	for i = #live, 1, -1 do
		local puff = live[i]
		local alpha = (now - puff.born) / PUFF_LIFE
		if alpha >= 1 then
			releasePuff(puff)
			table.remove(live, i)
		else
			-- Ширина по корню: в первые кадры лоскут распахивается резко, дальше почти
			-- стоит. Линейный рост читается как надувание шарика, а не как выброс.
			local w = START_W + (END_W - START_W) * math.sqrt(alpha)
			puff.mesh.Scale = Vector3.new(w, w * FLATNESS, w)
			puff.part.CFrame = puff.base + puff.drift * alpha * PUFF_LIFE + Vector3.new(0, RISE * alpha, 0)
			puff.part.Transparency = START_T + (1 - START_T) * alpha
		end
	end

	-- 2) машины: кто едет по земле — тот пылит
	for _, car in CollectionService:GetTagged("PlayerVehicle") do
		if not (car:IsA("Model") and car.Parent) then
			continue
		end
		local wheels = car:FindFirstChild("Wheels")
		local seat = car:FindFirstChild("DriveSeat") :: BasePart?
		if not (wheels and seat) then
			continue
		end
		if (seat.Position - camPos).Magnitude > VIEW_RANGE then
			continue
		end
		local speed, heading = motionOf(car, seat, now)
		if speed < MIN_SPEED or not heading then
			continue
		end
		local due = nextEmitAt[car]
		if due and now < due then
			continue
		end
		-- Чем быстрее едем, тем чаще лоскуты: на пределе вдвое чаще, чем на пороге.
		local strength = math.clamp((speed - MIN_SPEED) / (FULL_SPEED - MIN_SPEED), 0, 1)
		nextEmitAt[car] = now + EMIT_PERIOD / (0.5 + strength)

		local rear = wheelToggle[car]
		wheelToggle[car] = not rear
		local wheel = wheels:FindFirstChild(if rear then "RL" else "RR")
		if wheel and wheel:IsA("BasePart") then
			local at, color, normal = groundUnder(wheel, car)
			if at and color and normal then
				emit(at, normal, color, -heading, 0.4 + strength * 0.6)
			end
		end
	end
end)
