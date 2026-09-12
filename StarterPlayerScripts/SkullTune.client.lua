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
--   PAINT R G B   краска кузова (общая, как RUST)
-- ПРАВАЯ КОЛОНКА — мох: MOSS (вкл + перебор режима), MOSS OFF, M OPAC/COVER/SCALE/SEED,
-- MOSS R G B. \ — сброс к конфигу, P — напечатать всё, Z — зомби выкл/вкл.
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

if not RunService:IsStudio() then
	return
end

local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local RankSkull = require(ReplicatedStorage:WaitForChild("RankSkull"))
local ShopCatalog = require(ReplicatedStorage:WaitForChild("ShopCatalog"))

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
}
local function bodyDefaults(bodyId: string): BodyState
	local cb = GameConfig.Ranks.SkullBody and GameConfig.Ranks.SkullBody[bodyId] or nil
	local spec = RankSkull.Bodies[bodyId]
	local top = spec and spec.zones.top
	local c = RankSkull.Colors[(RANKS[1].skull and RANKS[1].skull.color) or "bone"] or Color3.new(1, 1, 1)
	return {
		modeIndex = table.find(MODES, (cb and cb.mode) or GameConfig.Ranks.SkullMode) or 1,
		opacity = (cb and cb.opacity) or GameConfig.Ranks.SkullOpacity,
		lift = (cb and cb.lift) or GameConfig.Ranks.SkullLift or 0,
		skull = { c.R * 255, c.G * 255, c.B * 255 },
		tone = (spec and spec.baseTone) or 1,
		paintStrength = (spec and spec.paintStrength) or 1,
		topPos = top and top.tb or 0.5,
		topSize = top and top.height or 3,
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
task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 20)
	local r = remotes and remotes:WaitForChild("DevZombies", 20)
	if r and r:IsA("RemoteEvent") then
		zombiesRemote = r
	end
end)

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
local paintSwatch = makeSwatch(15)
for i, ch in { "R", "G", "B" } do
	makeSlider(15 + i, "PAINT " .. ch, 255, function()
		return state.paint[i]
	end, function(v)
		state.paint[i] = v
	end)
end
-- // Мох (вторая колонка) -------------------------------------------------------
column = panelR
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
	return ("%s: mode=%s opacity=%.2f lift=%.2f skull=(%d,%d,%d) tone=%.2f paintStrength=%.2f top tb=%.2f height=%.2f"):format(
		b, MODES[s.modeIndex], s.opacity, s.lift, s.skull[1] + 0.5, s.skull[2] + 0.5, s.skull[3] + 0.5, s.tone, s.paintStrength, s.topPos, s.topSize)
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
		applyAll()
		return
	end
	if not active or processed then
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
