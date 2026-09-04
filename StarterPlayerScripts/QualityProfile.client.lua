--!strict
-- LocalScript: StarterPlayerScripts.QualityProfile
-- Профиль качества картинки. Всё, что здесь делается, — КЛИЕНТСКОЕ: ни одно
-- свойство отсюда не реплицируется, поэтому телефон может рисовать сцену иначе,
-- чем компьютер, и никому этим не мешать.
--
-- ЗАЧЕМ (перепись сцены живьём, 2026-09-04, Play):
--   • клиент держит ВСЮ карту — 3978 деталей, 1468 мешей, 724 юниона, 36 фонарей.
--     Стриминг включён, но карта 680×680, а радиус по умолчанию 1024 — он не
--     отсекает ничего;
--   • 990 мешей стояли RenderFidelity = Precise, и 687 из них — травяные кустики
--     размером 3.3×3.8 studs. У Precise НЕТ LOD: кустик на другом конце кладбища
--     рисуется полной геометрией. Это была главная статья расхода, а не зомби
--     (шаблон зомби — 7 деталей R6) и не физика;
--   • 34 фонаря PointLight на месте с Lighting.Technology = ShadowMap: каждый
--     источник пересобирает воксельную сетку света;
--   • 209 деталей с CastShadow при GlobalShadows = true — второй проход геометрии.
--
-- ЧТО ЗДЕСЬ ЕСТЬ: скрытие декора по дистанции, гашение дальних фонарей, тени и
-- пост-эффекты. Всё это включается ТОЛЬКО на сенсорных устройствах: на ПК
-- картинка обязана остаться прежней.
--
-- ЧЕГО ЗДЕСЬ НЕТ И ПОЧЕМУ — два свойства, которые из игрового скрипта не пишутся:
--   • RenderFidelity. Правится НА ШАБЛОНАХ в ServerStorage.MapTemplates (сделано
--     2026-09-04: GrassTuft → Performance, Tombstone_E/Tombstone_H/DeadTree_B/
--     DeadTree_C → Automatic); клоны наследуют, поэтому чинится сразу для всех
--     устройств. Попытка сделать это отсюда даёт «lacking capability Plugin» на
--     каждый меш — проверено, не повторять. Кузов машины (16 Precise-мешей в
--     VehicleTemplate) оставлен как есть: он всегда в упор перед камерой.
--   • StreamingTargetRadius — только руками в Properties, отдельный шаг плана.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- // Ручки ------------------------------------------------------------------
-- Дистанции скрытия мерены от КАМЕРЫ, а не от машины: смотрит игрок именно
-- камерой, и на обзорных ракурсах (итог заезда, зритель) она уезжает от машины.
local GRASS_CULL = 70 -- трава: кустик 3.7 studs дальше 70 — это один-два пикселя
local FENCE_CULL = 200 -- ограда стоит по краю карты, из центра она за туманом
local LAMPS_LIT = 6 -- сколько фонарей горит одновременно (всего их 34)
local TICK = 1 / 3 -- пересчёт три раза в секунду; каждый кадр здесь не нужен

-- Запас на возврат: прячем на дистанции CULL, показываем на CULL − HYSTERESIS.
-- Без него объект на самой границе мигает от дрожания камеры.
local HYSTERESIS = 12

local GRASS_NAME = "GraveGrass"

-- Предикат сенсора тот же, что в TouchControls: планшет с клавиатурой — не телефон.
--
-- ForceMobileProfile — ручка для проверки: телефона под рукой нет, а мобильную
-- ветку надо уметь смотреть на месте. Атрибут ставится на КЛИЕНТЕ (на сервер он
-- не уезжает), поэтому в живой игре им ничего не сломать.
local function isMobile(): boolean
	if player:GetAttribute("ForceMobileProfile") == true then
		return true
	end
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- // Группы для скрытия по дистанции ----------------------------------------
-- Прячем ГРУППАМИ (кустик целиком, секция ограды целиком), а не деталями: у
-- группы одна позиция, и на тике считается одно расстояние вместо семи.
type Group = {
	pos: Vector3,
	parts: { BasePart },
	hidden: boolean,
}

-- modelsOnly нужен ограде: помимо секций забора в PerimeterFence лежат ЧЕТЫРЕ
-- каменных цоколя — длинные коллайдящие барьеры на всю сторону карты. Их центр
-- в середине стороны, то есть «расстояние до камеры» для них бессмысленно, а
-- спрятать их значит поставить машине невидимую стену. Цоколи — голые Part,
-- секции — Model, отсюда и фильтр.
local function collectGroups(root: Instance, namePattern: string?, modelsOnly: boolean?): { Group }
	local groups: { Group } = {}
	for _, child in root:GetChildren() do
		if namePattern and not child.Name:match(namePattern) then
			continue
		end
		if modelsOnly and not child:IsA("Model") then
			continue
		end
		local parts: { BasePart } = {}
		if child:IsA("BasePart") then
			table.insert(parts, child)
		end
		for _, d in child:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(parts, d)
			end
		end
		if #parts > 0 then
			local pos = if child:IsA("Model") then child:GetPivot().Position else parts[1].Position
			table.insert(groups, { pos = pos, parts = parts, hidden = false })
		end
	end
	return groups
end

-- Скрываем через LocalTransparencyModifier, а не Transparency: модификатор
-- живёт только в нашем клиенте и не трогает реплицированное свойство, поэтому
-- сервер, стриминг и фото-режим о нашей уборке ничего не знают.
local function setHidden(group: Group, hidden: boolean)
	if group.hidden == hidden then
		return
	end
	group.hidden = hidden
	local value = if hidden then 1 else 0
	for _, p in group.parts do
		p.LocalTransparencyModifier = value
	end
end

local function cull(groups: { Group }, camPos: Vector3, range: number)
	local back = range - HYSTERESIS
	for _, g in groups do
		local dist = (g.pos - camPos).Magnitude
		if g.hidden then
			if dist < back then
				setHidden(g, false)
			end
		elseif dist > range then
			setHidden(g, true)
		end
	end
end

-- // Точка входа ------------------------------------------------------------
local map = workspace:WaitForChild("GeneratedMap", 60)
if not map then
	warn("[QualityProfile] GeneratedMap не появился за 60 с — профиль не применён.")
	return
end

-- // Мобильный профиль ------------------------------------------------------
local mobileApplied = false

local function applyMobileProfile()
	if mobileApplied then
		return
	end
	mobileApplied = true

	-- ШАГ 4: ТЕНИ. На телефоне тень — второй проход по всей видимой геометрии.
	-- Гасим и сам расчёт (GlobalShadows), и флаги у деталей: без второго теневая
	-- карта всё равно перестраивалась бы на движении.
	Lighting.GlobalShadows = false
	local function dropShadow(inst: Instance)
		if inst:IsA("BasePart") and inst.CastShadow then
			inst.CastShadow = false
		end
	end
	for _, d in map:GetDescendants() do
		dropShadow(d)
	end
	map.DescendantAdded:Connect(dropShadow)

	-- ШАГ 5: ПОСТ-ЭФФЕКТЫ. В ЗАЕЗДЕ гасим Bloom и цветокоррекцию — это
	-- полноэкранные проходы, каждый стоит заметной доли кадра. В ЛОББИ
	-- возвращаем: сцена там статична, кадров хватает, а заставку с ореолом
	-- вокруг тайтла игрок видит первой. BlurEffect не трогаем — им заведует
	-- LobbyUI, он гаснет на старте сам.
	-- ЦЕНА, ОСОЗНАННАЯ: вместе с блюмом на телефоне пропадёт ореол вокруг
	-- черепов-чекпоинтов (сам Neon его не рисует). Ровно то же самое уже
	-- происходит на низком авто-качестве — см. разбор в AtmosphereSetup.
	type EffectState = { effect: PostEffect, wasEnabled: boolean }
	local effects: { EffectState } = {}
	for _, e in Lighting:GetChildren() do
		if e:IsA("BloomEffect") or e:IsA("ColorCorrectionEffect") then
			table.insert(effects, { effect = e, wasEnabled = e.Enabled })
		end
	end

	local effectsMuted = false
	local function muteEffects(mute: boolean)
		if effectsMuted == mute then
			return
		end
		effectsMuted = mute
		for _, s in effects do
			if s.effect.Parent then
				s.effect.Enabled = if mute then false else s.wasEnabled
			end
		end
	end

	-- Признак «идёт заезд» — тот же, которым пользуется прицел: включённый HUD.
	-- Держим единственный источник правды, чтобы экраны не разъезжались.
	local playerGui = player:WaitForChild("PlayerGui")
	local hudGui: ScreenGui? = nil
	task.spawn(function()
		local g = playerGui:WaitForChild("GraveyardHUD", 60)
		if g and g:IsA("ScreenGui") then
			hudGui = g
		end
	end)
	local function raceOnScreen(): boolean
		local g = hudGui
		return g ~= nil and g.Parent ~= nil and g.Enabled
	end

	-- ШАГИ 2 и 3: скрытие по дистанции и фонари.
	local grass = collectGroups(map, "^" .. GRASS_NAME)
	local fence = workspace:FindFirstChild("PerimeterFence")
	local fencePieces = if fence then collectGroups(fence, nil, true) else {}

	-- Фонари собираем отдельно от геометрии: гасим САМ ИСТОЧНИК, столб остаётся
	-- стоять. Мерцание (серверный FlickerLight) пишет только Brightness, наш
	-- Enabled оно не перебьёт — сверено по коду FlickerLight.
	type Lamp = { light: Light, pos: Vector3, dist: number }
	local lamps: { Lamp } = {}
	for _, d in map:GetDescendants() do
		if d:IsA("Light") then
			local holder = d.Parent
			if holder and holder:IsA("BasePart") then
				table.insert(lamps, { light = d, pos = holder.Position, dist = 0 })
			end
		end
	end

	print(("[QualityProfile] мобильный профиль: трава %d, секций ограды %d, фонарей %d")
		:format(#grass, #fencePieces, #lamps))

	task.spawn(function()
		while true do
			task.wait(TICK)
			local cam = workspace.CurrentCamera
			if not cam then
				continue
			end
			local camPos = cam.CFrame.Position

			cull(grass, camPos, GRASS_CULL)
			cull(fencePieces, camPos, FENCE_CULL)

			-- Горят LAMPS_LIT ближайших. Дальний фонарь на воксельной сетке
			-- света стоит столько же, сколько ближний, а даёт пятно в два пикселя.
			if #lamps > 0 then
				for _, l in lamps do
					l.dist = (l.pos - camPos).Magnitude
				end
				table.sort(lamps, function(a, b)
					return a.dist < b.dist
				end)
				for i, l in lamps do
					local shouldBeOn = i <= LAMPS_LIT
					if l.light.Enabled ~= shouldBeOn then
						l.light.Enabled = shouldBeOn
					end
				end
			end

			muteEffects(raceOnScreen())
		end
	end)
end

if isMobile() then
	applyMobileProfile()
else
	-- Устройство может «стать сенсорным» позже: подключили экран, включили
	-- эмуляцию устройства в Studio. Обратного пути нет и не надо — снимать
	-- ужимки на ходу сложнее, чем один раз их не включить.
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(function()
		if isMobile() then
			applyMobileProfile()
		end
	end)
	UserInputService:GetPropertyChangedSignal("KeyboardEnabled"):Connect(function()
		if isMobile() then
			applyMobileProfile()
		end
	end)
	player:GetAttributeChangedSignal("ForceMobileProfile"):Connect(function()
		if isMobile() then
			applyMobileProfile()
		end
	end)
end
