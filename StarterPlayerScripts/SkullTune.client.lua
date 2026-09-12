--!strict
-- LocalScript: StarterPlayerScripts.SkullTune
-- ДЕВ-ПОДКРУТКА ЧЕРЕПОВ-РАНГОВ И КРАСКИ КУЗОВА. Только Studio (как NeonTune/PhotoMode).
--
-- ЗАЧЕМ. Режим наложения, плотность, подъём яркости, цвет черепа и краска кузова
-- подбираются глазами, а в Edit-свете затенённые поверхности синеют от неба —
-- судить можно только в Play. Юзер: «на экран я сделаю как надо, а ты потом зашьёшь в
-- код» — здесь крутит он, P печатает числа в Output, я переношу их в GameConfig /
-- RankSkull / ShopCatalog.
--
-- ЛЕВАЯ КОЛОНКА — ПО КУЗОВАМ (2026-09-12: багги и гроб просят разного — «на багги
-- сильнее», «череп цвета ржавчины с наложением», «придави тон на багги»):
--   BODY          кнопка: чьи ручки крутим — buggy / coffin (стартует с той машины,
--                 в которой сидишь; вторую можно настроить вслепую и посмотреть потом)
--   MODE          режим наложения черепа на этом кузове
--   RANK          какую форму (ленту с именем) показывать на своей машине
--   OPACITY/LIFT  плотность и подъём черепа на этом кузове
--   SKULL R G B   цвет черепа на этом кузове
--   TONE          тон холста: домножение текстуры до краски (темнее — контрастнее череп)
--   PAINT STR     сила краски: 1 — краска домножает целиком, меньше — текстура
--                 просвечивает (BLOOD уходит из красного в тёмно-коричневый)
--   TOP POS/SIZE  место (0 — у кабины, 1 — у носа) и высота черепа на капоте/крышке
--   SIDE POS      место черепа на бортах: доля длины от кормы (0.5 — по центру)
--   PAINT R G B   краска кузова (общая, как RUST)
-- ПРАВАЯ КОЛОНКА — GARAGE: гараж-песочница вне заезда — сервер (DevGarage) ставит над
-- стартом площадку со ВСЕМИ кузовами × ВСЕМИ красками, камера орбитальная (ПКМ —
-- крутить, колесо — зум, СКМ — сдвиг), заставка и блюр на время гаснут; ручки слева
-- красят все экземпляры сразу. В гараже же ОРУЖЕЙНАЯ ПЕСОЧНИЦА: ряд турельных стоек со
-- всеми стволами и стена-мишень; кнопка WEAPON выбирает стойку, ЛКМ по сцене (не по
-- панели) стреляет с неё в точку под курсором — трассер/вспышка/звук как в заезде
-- (ShotFX, статы из Weapons), удержание — очередь в темпе ствола. Ниже мох: MOSS (вкл + перебор режима), MOSS OFF,
-- M OPAC/COVER/SCALE/SEED, MOSS R G B. \ — сброс к конфигу, P — напечатать всё,
-- Z — зомби выкл/вкл.
--   F3            вкл / выкл панели. НЕ F8: в Studio это «Run» (сервер без игрока) —
--                 нажатие в Play роняло сессию в серверный режим, «меню пропало»
--                 (2026-09-12). F7 — тоже Studio, F6 — NeonTune, F4 — PhotoMode.
-- Пересборка текстуры ~0.05с на изменение; ползунок тянуть можно, пересобирается на
-- отпускании и раз в 0.15с по ходу (тяжёлые — мох — только на отпускании).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

if not RunService:IsStudio() then
	return
end

local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local RankSkull = require(ReplicatedStorage:WaitForChild("RankSkull"))
local ShopCatalog = require(ReplicatedStorage:WaitForChild("ShopCatalog"))
local EnvironmentConfig = require(ReplicatedStorage:WaitForChild("EnvironmentConfig"))
local Weapons = require(ReplicatedStorage:WaitForChild("Weapons"))
local ShotFX = require(ReplicatedStorage:WaitForChild("ShotFX"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local TOGGLE_KEY = Enum.KeyCode.F3
local FONT = Enum.Font.Code
local MODES = { "overlay", "multiply", "screen", "softlight", "lineardodge", "normal" }
local BODIES = { "buggy", "coffin" }
-- Ступени рангов: кнопка RANK перебирает их, на машину идёт ФОРМА ступени (SkullShapes).
local RANKS = {}
for _, t in GameConfig.Ranks.Tiers do
	table.insert(RANKS, t)
end
local PATCH_MODES = { "tint", "multiply", "overlay", "screen", "softlight", "lineardodge", "normal" }

-- // Исходные значения — чтобы «\» возвращал к конфигу ---------------------------
type BodyState = {
	modeIndex: number, opacity: number, lift: number,
	skull: { number }, -- цвет черепа 0..255
	tone: number, paintStrength: number, topPos: number, topSize: number,
	sidePos: number, -- место черепа на бортах: доля длины от кормы (left.ta; right зеркально)
}
local function bodyDefaults(bodyId: string): BodyState
	local cb = GameConfig.Ranks.SkullBody and GameConfig.Ranks.SkullBody[bodyId] or nil
	local spec = RankSkull.Bodies[bodyId]
	local top = spec and spec.zones.top
	local left = spec and spec.zones.left
	local c = RankSkull.Colors[(cb and cb.color) or (RANKS[1].skull and RANKS[1].skull.color) or "bone"] or Color3.new(1, 1, 1)
	return {
		modeIndex = table.find(MODES, (cb and cb.mode) or GameConfig.Ranks.SkullMode) or 1,
		opacity = (cb and cb.opacity) or GameConfig.Ranks.SkullOpacity,
		lift = (cb and cb.lift) or GameConfig.Ranks.SkullLift or 0,
		skull = { c.R * 255, c.G * 255, c.B * 255 },
		tone = (spec and spec.baseTone) or 1,
		paintStrength = (spec and spec.paintStrength) or 1,
		topPos = top and top.tb or 0.5,
		topSize = top and top.height or 3,
		sidePos = left and left.ta or 0.5,
	}
end
local base = { bodies = {} :: { [string]: BodyState } }
for _, b in BODIES do
	base.bodies[b] = bodyDefaults(b)
end
local rustItem = ShopCatalog.get(ShopCatalog.DefaultSkin)
base.paint = (rustItem and rustItem.color) or Color3.new(1, 1, 1)
-- Мох: пятнистая краска из каталога (ShopCatalog.moss.patchy)
local mossItem = ShopCatalog.get("moss")
local mossPatchy = (mossItem and mossItem.patchy) or { coverage = 1 / 6, scale = 9, seed = 7, mode = "tint", opacity = 1 }
base.moss = {
	color = (mossItem and mossItem.color) or Color3.fromRGB(52, 90, 64),
	coverage = mossPatchy.coverage, scale = mossPatchy.scale, seed = mossPatchy.seed,
	mode = mossPatchy.mode or "tint", opacity = mossPatchy.opacity or 1,
}

local function cloneBody(s: BodyState): BodyState
	local c = table.clone(s)
	c.skull = table.clone(s.skull)
	return c
end

local state = {
	bodyIndex = 1,
	bodyAuto = true, -- пока юзер не жал BODY — крутим ту машину, в которой сидит
	bodies = {} :: { [string]: BodyState },
	tierIndex = 1,
	paint = { base.paint.R * 255, base.paint.G * 255, base.paint.B * 255 },
	mossOn = false, -- показывать мох поверх RUST (что бы ни было надето)
	mossModeIndex = table.find(PATCH_MODES, base.moss.mode) or 1,
	mossOpacity = base.moss.opacity,
	mossCoverage = base.moss.coverage,
	mossScale = base.moss.scale,
	mossSeed = base.moss.seed,
	moss = { base.moss.color.R * 255, base.moss.color.G * 255, base.moss.color.B * 255 },
}
for _, b in BODIES do
	state.bodies[b] = cloneBody(base.bodies[b])
end

local function bodyName(): string
	return BODIES[state.bodyIndex]
end
local function cur(): BodyState
	return state.bodies[bodyName()]
end

-- Кузов своей машины (тег PlayerVehicle + OwnerUserId), nil — машины нет.
local function drivenBody(): string?
	for _, car in CollectionService:GetTagged("PlayerVehicle") do
		if car:GetAttribute("OwnerUserId") == player.UserId then
			local body = car:FindFirstChild("BuggyBody")
			local id = body and body:GetAttribute("BodyId")
			if type(id) == "string" then
				return id
			end
		end
	end
	return nil
end

local active = false

-- Выключатель зомби — тот же ремоут, что у NeonTune (PhotoModeService, только Studio).
local zombiesOff = false
local zombiesRemote: RemoteEvent? = nil
local garageRemote: RemoteEvent? = nil
task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 20)
	local r = remotes and remotes:WaitForChild("DevZombies", 20)
	if r and r:IsA("RemoteEvent") then
		zombiesRemote = r
	end
	local g = remotes and remotes:WaitForChild("DevGarage", 20)
	if g and g:IsA("RemoteEvent") then
		garageRemote = g
	end
end)
local garageOn = false
local setGarage: (boolean) -> () -- ниже
local nightOn = false
local setNight: (boolean) -> () -- ниже
local WEAPON_IDS = {}
for _, item in ShopCatalog.weapons() do
	table.insert(WEAPON_IDS, item.id)
end
local weaponIndex = 1

-- // Панель ------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "SkullTune"
gui.ResetOnSpawn = false
gui.DisplayOrder = 1003
gui.Enabled = false
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0, 1)
panel.Position = UDim2.new(0, 16, 1, -16)
panel.Size = UDim2.fromOffset(330, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundColor3 = UITheme.PanelBg
panel.BackgroundTransparency = 0.15
panel.BorderSizePixel = 0
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)
local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 10)
pad.PaddingBottom = UDim.new(0, 10)
pad.PaddingLeft = UDim.new(0, 14)
pad.PaddingRight = UDim.new(0, 14)
pad.Parent = panel
local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 2)
layout.Parent = panel

-- ВТОРАЯ КОЛОНКА: с секцией мха одна колонка перестала влезать по высоте (верх уезжал
-- за экран). Конструкторы кладут строки в `column`; перед секцией мха она меняется.
local panelR = panel:Clone()
panelR:ClearAllChildren()
Instance.new("UICorner", panelR).CornerRadius = UDim.new(0, 8)
-- Правый нижний угол, зеркально левой: посередине колонка закрывала машину.
panelR.AnchorPoint = Vector2.new(1, 1)
panelR.Position = UDim2.new(1, -16, 1, -16)
panelR.Parent = gui
local padR = pad:Clone(); padR.Parent = panelR
local layoutR = layout:Clone(); layoutR.Parent = panelR
local column: Frame = panel

local refreshers: { () -> () } = {}
local applyAll -- ниже

local function makeLabel(order: number, text: string, size: number): TextLabel
	local l = Instance.new("TextLabel")
	l.LayoutOrder = order
	l.Size = UDim2.new(1, 0, 0, size + 4)
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.TextSize = size
	l.TextColor3 = UITheme.Palette.Bone
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = column
	return l
end

local function makeButton(order: number, get: () -> string, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.LayoutOrder = order
	b.Size = UDim2.new(1, 0, 0, 22)
	b.BackgroundColor3 = UITheme.Palette.Green
	b.BorderSizePixel = 0
	b.Font = FONT
	b.TextSize = 13
	b.TextColor3 = UITheme.Palette.Bone
	b.Text = get()
	b.Parent = column
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
	table.insert(refreshers, function()
		b.Text = get()
	end)
	b.Activated:Connect(function()
		onClick()
		applyAll()
	end)
	return b
end

-- Ползунок 0..max; при max <= 5 подпись с двумя знаками, иначе целое.
local function makeSlider(order: number, name: string, max: number, get: () -> number, set: (number) -> (), heavy: boolean?)
	local row = Instance.new("Frame")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 23)
	row.BackgroundTransparency = 1
	row.Parent = column
	local caption = Instance.new("TextLabel")
	caption.Size = UDim2.new(1, 0, 0, 13)
	caption.BackgroundTransparency = 1
	caption.Font = FONT
	caption.TextSize = 13
	caption.TextColor3 = UITheme.Palette.Bone
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.Parent = row
	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, 0, 0, 6)
	track.Position = UDim2.new(0, 0, 0, 15)
	track.BackgroundColor3 = UITheme.Shadow
	track.BorderSizePixel = 0
	track.Parent = row
	Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = UITheme.Palette.GreenLight
	fill.BorderSizePixel = 0
	fill.Parent = track
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(12, 12)
	knob.BackgroundColor3 = UITheme.Palette.Bone
	knob.BorderSizePixel = 0
	knob.ZIndex = 2
	knob.Parent = track
	Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
	local function refresh()
		local alpha = math.clamp(get() / max, 0, 1)
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.new(alpha, 0, 0.5, 0)
		caption.Text = if max <= 5 then string.format("%-9s %.2f", name, get()) else string.format("%-9s %3d", name, math.floor(get() + 0.5))
	end
	table.insert(refreshers, refresh)
	local hit = Instance.new("TextButton")
	hit.Size = UDim2.fromScale(1, 1)
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Text = ""
	hit.Parent = row
	local dragging = false
	local lastApply = 0
	local function setFromX(x: number, final: boolean)
		local width = math.max(track.AbsoluteSize.X, 1)
		set(math.clamp((x - track.AbsolutePosition.X) / width, 0, 1) * max)
		refresh()
		-- тяжёлые (мох: пересчёт шума ~1 с) — только на отпускании
		if final or (not heavy and os.clock() - lastApply > 0.15) then
			lastApply = os.clock()
			applyAll()
		end
	end
	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			setFromX(input.Position.X, false)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			setFromX(input.Position.X, false)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
			setFromX(input.Position.X, true)
		end
	end)
end

local function makeSwatch(order: number): Frame
	local sw = Instance.new("Frame")
	sw.LayoutOrder = order
	sw.Size = UDim2.new(1, 0, 0, 12)
	sw.BorderSizePixel = 0
	sw.Parent = column
	Instance.new("UICorner", sw).CornerRadius = UDim.new(0, 4)
	return sw
end

makeLabel(1, "SKULL TUNE   (F3, \\ сброс, P печать, Z зомби)", 15)
makeButton(2, function()
	local driven = drivenBody()
	return "BODY: " .. bodyName() .. (if driven == bodyName() then "   (твоя машина)" elseif driven then "   (сидишь в " .. driven .. ")" else "")
end, function()
	state.bodyAuto = false
	state.bodyIndex = state.bodyIndex % #BODIES + 1
end)
makeButton(3, function()
	return "MODE: " .. MODES[cur().modeIndex]
end, function()
	cur().modeIndex = cur().modeIndex % #MODES + 1
end)
makeButton(4, function()
	return "RANK: " .. RANKS[state.tierIndex].name
end, function()
	state.tierIndex = state.tierIndex % #RANKS + 1
end)
makeSlider(5, "OPACITY", 1, function()
	return cur().opacity
end, function(v)
	cur().opacity = v
end)
makeSlider(6, "LIFT", 1, function()
	return cur().lift
end, function(v)
	cur().lift = v
end)
local swatch = makeSwatch(7)
for i, ch in { "R", "G", "B" } do
	makeSlider(7 + i, "SKULL " .. ch, 255, function()
		return cur().skull[i]
	end, function(v)
		cur().skull[i] = v
	end)
end
makeSlider(11, "TONE", 1.5, function()
	return cur().tone
end, function(v)
	cur().tone = math.max(0.1, v)
end)
makeSlider(12, "PAINT STR", 1, function()
	return cur().paintStrength
end, function(v)
	cur().paintStrength = v
end)
makeSlider(13, "TOP POS", 1, function()
	return cur().topPos
end, function(v)
	cur().topPos = v
end)
makeSlider(14, "TOP SIZE", 5, function()
	return cur().topSize
end, function(v)
	cur().topSize = math.max(0.5, v)
end)
makeSlider(15, "SIDE POS", 1, function()
	return cur().sidePos
end, function(v)
	cur().sidePos = v
end)
local paintSwatch = makeSwatch(16)
for i, ch in { "R", "G", "B" } do
	makeSlider(16 + i, "PAINT " .. ch, 255, function()
		return state.paint[i]
	end, function(v)
		state.paint[i] = v
	end)
end
-- // Гараж и мох (вторая колонка) -----------------------------------------------
column = panelR
makeButton(17, function()
	return "GARAGE: " .. (garageOn and "ON   (ПКМ крутить, колесо зум, СКМ сдвиг)" or "OFF")
end, function()
	setGarage(not garageOn)
end)
makeButton(18, function()
	return "LIGHT: " .. (nightOn and "NIGHT (как в заезде)" or "DAY (как в лобби)")
end, function()
	setNight(not nightOn)
end)
makeButton(18, function()
	local item = ShopCatalog.get(WEAPON_IDS[weaponIndex])
	return "WEAPON: " .. (item and item.name or "?") .. "   (ЛКМ по сцене — стрелять)"
end, function()
	weaponIndex = weaponIndex % #WEAPON_IDS + 1
end)
makeLabel(19, "MOSS  (пятнистая краска)", 15)
makeButton(20, function()
	return "MOSS: " .. (state.mossOn and "ON" or "OFF") .. "   mode " .. PATCH_MODES[state.mossModeIndex]
end, function()
	if not state.mossOn then
		state.mossOn = true
	else
		state.mossModeIndex = state.mossModeIndex % #PATCH_MODES + 1
	end
end)
makeButton(21, function()
	return "MOSS OFF"
end, function()
	state.mossOn = false
end)
makeSlider(22, "M OPAC", 1, function()
	return state.mossOpacity
end, function(v)
	state.mossOpacity = v
end)
makeSlider(23, "M COVER", 1, function()
	return state.mossCoverage
end, function(v)
	state.mossCoverage = math.max(0.02, v)
end)
makeSlider(24, "M SCALE", 30, function()
	return state.mossScale
end, function(v)
	state.mossScale = math.max(1, v)
end, true)
makeSlider(25, "M SEED", 60, function()
	return state.mossSeed
end, function(v)
	state.mossSeed = math.floor(v + 0.5)
end, true)
local mossSwatch = makeSwatch(26)
for i, ch in { "R", "G", "B" } do
	makeSlider(26 + i, "MOSS " .. ch, 255, function()
		return state.moss[i]
	end, function(v)
		state.moss[i] = v
	end)
end

local info = makeLabel(30, "", 11)
info.TextWrapped = true
info.Size = UDim2.new(1, 0, 0, 150)

-- // Применение ----------------------------------------------------------------
local function rgb(t: { number }): Color3
	return Color3.fromRGB(math.floor(t[1] + 0.5), math.floor(t[2] + 0.5), math.floor(t[3] + 0.5))
end
local function paintColor(): Color3
	return rgb(state.paint)
end
local function mossColor(): Color3
	return rgb(state.moss)
end

local function bodyLine(b: string): string
	local s = state.bodies[b]
	return ("%s: mode=%s opacity=%.2f lift=%.2f skull=(%d,%d,%d) tone=%.2f paintStrength=%.2f top tb=%.2f height=%.2f side ta=%.2f"):format(
		b, MODES[s.modeIndex], s.opacity, s.lift, s.skull[1] + 0.5, s.skull[2] + 0.5, s.skull[3] + 0.5, s.tone, s.paintStrength, s.topPos, s.topSize, s.sidePos)
end

local function summary(): string
	local p = state.paint
	local m = state.moss
	return ("%s\n%s\nrust=(%d,%d,%d) | moss=(%d,%d,%d) mode=%s opacity=%.2f coverage=%.3f scale=%.1f seed=%d"):format(
		bodyLine("buggy"), bodyLine("coffin"), p[1] + 0.5, p[2] + 0.5, p[3] + 0.5,
		m[1] + 0.5, m[2] + 0.5, m[3] + 0.5, PATCH_MODES[state.mossModeIndex], state.mossOpacity, state.mossCoverage, state.mossScale, state.mossSeed)
end

-- Поля спеки кузова (тон, сила краски, место/размер черепа на капоте) панель правит на
-- живую — они в ключе кэша RankSkull.compose, пересборка честная. Без панели — как в коде.
local function pushSpec(b: string, s: BodyState)
	local spec = RankSkull.Bodies[b]
	if not spec then
		return
	end
	spec.baseTone = s.tone
	spec.paintStrength = s.paintStrength
	local top = spec.zones.top
	if top then
		top.tb = s.topPos
		top.height = s.topSize
	end
	local left, right = spec.zones.left, spec.zones.right
	if left and right then
		left.ta = s.sidePos
		right.ta = 1 - s.sidePos -- у right ta = 0 у носа, зеркально
	end
end

applyAll = function()
	if state.bodyAuto then
		local d = drivenBody()
		local i = d and table.find(BODIES, d)
		if i then
			state.bodyIndex = i
		end
	end
	local byBody: { [string]: RankSkull.BodyOverride } = {}
	for _, b in BODIES do
		local s = if active then state.bodies[b] else base.bodies[b]
		pushSpec(b, s)
		RankSkull.Colors["dev_" .. b] = rgb(s.skull)
		byBody[b] = { mode = MODES[s.modeIndex], opacity = s.opacity, lift = s.lift, colorName = "dev_" .. b }
	end
	RankSkull.Overrides = if active then {
		tint = paintColor(),
		colorName = "dev_" .. bodyName(),
		shape = (RANKS[state.tierIndex].skull and RANKS[state.tierIndex].skull.shape) or RANKS[state.tierIndex].name,
		byBody = byBody,
		patch = if state.mossOn then {
			color = mossColor(), coverage = state.mossCoverage, scale = state.mossScale, seed = state.mossSeed,
			mode = PATCH_MODES[state.mossModeIndex], opacity = state.mossOpacity,
		} else nil,
		patchOff = not state.mossOn,
	} else nil
	RankSkull.OverridesChanged:Fire()
	swatch.BackgroundColor3 = rgb(cur().skull)
	paintSwatch.BackgroundColor3 = paintColor()
	mossSwatch.BackgroundColor3 = mossColor()
	for _, f in refreshers do
		f()
	end
	-- ПАНЕЛЬ КРАСИТ КАК RUST, а без панели кузов носит НАДЕТУЮ краску. Юзер 2026-09-12:
	-- «со старта багги зелёное, не то, что настраивал» — на нём была надета GRAVE MOSS.
	-- Пишем это прямо в панели, чтобы не искать.
	local worn = tostring(player:GetAttribute("EquippedSkin") or "?")
	local note = ""
	if worn ~= ShopCatalog.DefaultSkin then
		note = "\n!! НАДЕТА КРАСКА " .. string.upper(worn) .. " — без панели кузов такой. Панель красит как RUST: SHOP → RUST → USE"
	end
	info.Text = summary() .. note
end

local function reset()
	for _, b in BODIES do
		state.bodies[b] = cloneBody(base.bodies[b])
	end
	state.paint = { base.paint.R * 255, base.paint.G * 255, base.paint.B * 255 }
	state.mossModeIndex = table.find(PATCH_MODES, base.moss.mode) or 1
	state.mossOpacity = base.moss.opacity
	state.mossCoverage = base.moss.coverage
	state.mossScale = base.moss.scale
	state.mossSeed = base.moss.seed
	state.moss = { base.moss.color.R * 255, base.moss.color.G * 255, base.moss.color.B * 255 }
	applyAll()
end

-- // Гараж-песочница ------------------------------------------------------------
-- Сервер (ServerScriptService.DevGarage) ставит модель workspace.DevGarage с атрибутом
-- Origin; экземпляры одевает сторож RankSkull.client по тегу DevGarageBody. Здесь —
-- камера-орбита и подавление заставки/блюра (как в PhotoMode, короче: только LobbyUI).
local camera = workspace.CurrentCamera
local orbit = { yaw = math.rad(30), pitch = math.rad(-22), dist = 70, target = Vector3.zero }
local suppressed: { [LayerCollector]: { wanted: boolean, conn: RBXScriptConnection } } = {}
local blurs: { [BlurEffect]: { size: number, conn: RBXScriptConnection } } = {}

local function suppressLobby()
	for _, g in playerGui:GetChildren() do
		if g:IsA("ScreenGui") and g.Name == "LobbyUI" and not suppressed[g] then
			local record = { wanted = g.Enabled } :: any
			-- реагируем только на включение: сигналы свойств отложенные, своё гашение
			-- от чужого флагом не отличить (см. PhotoMode)
			record.conn = g:GetPropertyChangedSignal("Enabled"):Connect(function()
				if g.Enabled then
					record.wanted = true
					g.Enabled = false
				end
			end)
			g.Enabled = false
			suppressed[g] = record
		end
	end
	for _, inst in Lighting:GetDescendants() do
		if inst:IsA("BlurEffect") and not blurs[inst] then
			local record = { size = inst.Size } :: any
			record.conn = inst:GetPropertyChangedSignal("Size"):Connect(function()
				if inst.Size > 0 then
					record.size = inst.Size
					inst.Size = 0
				end
			end)
			inst.Size = 0
			blurs[inst] = record
		end
	end
end

local function restoreLobby()
	for g, record in suppressed do
		record.conn:Disconnect()
		if g.Parent then
			g.Enabled = record.wanted
		end
	end
	table.clear(suppressed)
	for b, record in blurs do
		record.conn:Disconnect()
		if b.Parent then
			b.Size = record.size
		end
	end
	table.clear(blurs)
end

-- Свет: лобби стоит на вечере (DayNightCycle, anchor < 0), заезд уходит в ночь — а
-- черепа и краски смотрят ночью. Кнопка LIGHT ставит ночную опору EnvironmentConfig
-- локально, как apply(1) в DayNightCycle; на выходе — вечер обратно.
local function applyLight(cfg: any)
	Lighting.ClockTime = cfg.ClockTime % 24
	Lighting.Brightness = cfg.Brightness
	Lighting.OutdoorAmbient = cfg.OutdoorAmbient
	Lighting.Ambient = cfg.OutdoorAmbient
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmo then
		atmo.Density = cfg.Density
	end
	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if cc then
		cc.Saturation = cfg.ColorCorrectionSaturation
		cc.TintColor = cfg.ColorCorrectionTintColor
	end
end

-- Молния (DayNightCycle) после вспышки зовёт apply(0) и возвращает вечер — держим
-- ночь, пока включена: сигнал отложенный, на кадр вспышки не спорим.
local nightConn: RBXScriptConnection? = nil
setNight = function(on: boolean)
	nightOn = on
	if nightConn then
		nightConn:Disconnect()
		nightConn = nil
	end
	applyLight(if on then EnvironmentConfig.Atmosphere else EnvironmentConfig.Evening)
	if on then
		nightConn = Lighting:GetPropertyChangedSignal("ClockTime"):Connect(function()
			if nightOn and math.abs(Lighting.ClockTime - EnvironmentConfig.Atmosphere.ClockTime % 24) > 0.01 then
				applyLight(EnvironmentConfig.Atmosphere)
			end
		end)
	end
	for _, f in refreshers do
		f()
	end
end

local function orbitStep()
	local rot = CFrame.fromEulerAnglesYXZ(orbit.pitch, orbit.yaw, 0)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.new(orbit.target) * rot * CFrame.new(0, 0, orbit.dist)
end

-- Сдвиг мыши считаем сами по Position: InputObject.Delta при незалоченном курсоре
-- пуст — ПКМ/СКМ «не работали», колесо (Position.Z) работало (2026-09-12).
local lastMouse: Vector3? = nil
UserInputService.InputChanged:Connect(function(input)
	if not garageOn then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		local pos = input.Position
		local d = if lastMouse then pos - lastMouse else Vector3.zero
		lastMouse = pos
		if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
			orbit.yaw -= d.X * 0.006
			orbit.pitch = math.clamp(orbit.pitch - d.Y * 0.006, -1.45, 0.4)
		elseif UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton3) then
			local cf = camera.CFrame
			orbit.target -= (cf.RightVector * d.X - cf.UpVector * d.Y) * (orbit.dist * 0.0015)
		end
	elseif input.UserInputType == Enum.UserInputType.MouseWheel then
		orbit.dist = math.clamp(orbit.dist - input.Position.Z * 6, 8, 250)
	end
end)
UserInputService.InputBegan:Connect(function(input)
	if garageOn and (input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.MouseButton3) then
		lastMouse = input.Position
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		garageFiring = false
	end
end)

setGarage = function(on: boolean)
	local r = garageRemote
	if not r then
		print("[SkullTune] ремоута DevGarage нет — он только в Studio")
		return
	end
	garageOn = on
	r:FireServer(on)
	if on then
		task.spawn(function()
			local model = workspace:WaitForChild("DevGarage", 10)
			local origin = model and model:GetAttribute("Origin")
			if not garageOn or typeof(origin) ~= "Vector3" then
				return
			end
			orbit.target = origin + Vector3.new(0, 3, 0)
			orbit.yaw, orbit.pitch, orbit.dist = math.rad(30), math.rad(-22), 70
			suppressLobby()
			RunService:BindToRenderStep("SkullTuneGarage", Enum.RenderPriority.Camera.Value + 1, orbitStep)
		end)
	else
		RunService:UnbindFromRenderStep("SkullTuneGarage")
		camera.CameraType = Enum.CameraType.Custom
		restoreLobby()
		if nightOn then
			setNight(false)
		end
	end
	for _, f in refreshers do
		f()
	end
end

-- // Оружейная песочница: стрельба со стойки гаража ------------------------------
-- Стойка GarageGun_<id> (DevGarage), дуло — Attachment Muzzle на её люльке. Цель — точка
-- под курсором (луч камеры мимо самих стоек), веер дробин и вид выстрела — как в заезде.
local garageFiring = false
local lastGarageShot = 0

local function garageRig(): Model?
	local g = workspace:FindFirstChild("DevGarage")
	local rig = g and g:FindFirstChild("GarageGun_" .. WEAPON_IDS[weaponIndex])
	return if rig and rig:IsA("Model") then rig else nil
end

local function garageFire()
	local rig = garageRig()
	local muzzle = rig and rig:FindFirstChild("Muzzle", true)
	if not (muzzle and muzzle:IsA("Attachment")) then
		return
	end
	local stats = Weapons.get(WEAPON_IDS[weaponIndex])
	local now = os.clock()
	if now - lastGarageShot < 1 / stats.fireRate then
		return
	end
	lastGarageShot = now
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y - game:GetService("GuiService"):GetGuiInset().Y)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local g = workspace:FindFirstChild("DevGarage")
	local excl: { Instance } = {}
	if g then
		for _, c in g:GetChildren() do
			if c.Name:sub(1, 10) == "GarageGun_" then
				table.insert(excl, c)
			end
		end
	end
	rp.FilterDescendantsInstances = excl
	local aim = workspace:Raycast(ray.Origin, ray.Direction * 500, rp)
	local target = aim and aim.Position or (ray.Origin + ray.Direction * 500)
	local origin = muzzle.WorldPosition
	local direction = (target - origin).Unit
	local hits = {}
	for _, dir in Weapons.pelletDirections(direction, stats, math.random(1, 1073741824)) do
		local res = workspace:Raycast(origin, dir * stats.range, rp)
		table.insert(hits, res and res.Position or (origin + dir * stats.range))
	end
	ShotFX.fire(muzzle, hits, stats)
end

RunService.RenderStepped:Connect(function()
	if garageOn and garageFiring then
		garageFire()
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode == TOGGLE_KEY then
		active = not active
		gui.Enabled = active
		-- В заезде турель прячет системный курсор и перехватывает мышь под прицел —
		-- ползунки не поймать. Тот же договор, что у NeonTune: пока панель открыта,
		-- стоит атрибут DevPanelOpen, и TurretAimClient мышь не трогает.
		player:SetAttribute("DevPanelOpen", active or nil)
		UserInputService.MouseIconEnabled = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		if not active and garageOn then
			setGarage(false)
		end
		applyAll()
		return
	end
	if not active or processed then
		return
	end
	if garageOn and input.UserInputType == Enum.UserInputType.MouseButton1 then
		garageFiring = true
		garageFire()
		return
	end
	if input.KeyCode == Enum.KeyCode.BackSlash then
		reset()
	elseif input.KeyCode == Enum.KeyCode.P then
		print("[SkullTune] " .. summary())
	elseif input.KeyCode == Enum.KeyCode.Z then
		local r = zombiesRemote
		if not r then
			print("[SkullTune] ремоута DevZombies нет — он только в Studio")
			return
		end
		zombiesOff = not zombiesOff
		r:FireServer(zombiesOff)
		print("[SkullTune] зомби: " .. (zombiesOff and "ВЫКЛЮЧЕНЫ" or "включены"))
	end
end)

-- строка «надета краска …» обновляется, когда запись доехала или краску сменили
player:GetAttributeChangedSignal("EquippedSkin"):Connect(function()
	if active then
		applyAll()
	end
end)

applyAll()
print("[SkullTune] подкрутка черепов и краски готова: F3")
