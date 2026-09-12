--!strict
-- LocalScript: StarterPlayerScripts.ShopUI
-- ВИТРИНА. Устроена как панель опций и живёт по тем же правилам: строго по центру,
-- та же костяная подложка-мазок, тот же атрибут игрока LobbyPanel для взаимного
-- исключения панелей (здесь значение "Shop"), тот же BACK внизу.
--
-- ЧТО ПОКАЗЫВАТЬ, РЕШАЕТ НЕ ЭТОТ ФАЙЛ. Список берётся из ReplicatedStorage.ShopCatalog
-- — того же модуля, по которому сервер проверяет покупку. Ненастроенные товары
-- (нулевой id пропуска/продукта) каталог не отдаёт вовсе, поэтому «пустых» плашек на
-- витрине не бывает.
--
-- КЛИЕНТ НИЧЕГО НЕ РЕШАЕТ. Нажатие шлёт серверу только действие и id товара; цену,
-- право покупки и списание считает ShopService. Здесь цена рисуется исключительно
-- ради глаз: соврать ею нельзя, сервер её всё равно перечитает.
--
-- ПРОКРУТКА, А НЕ ПОДГОНКА ПОД СЕМЬ СТРОК. Товаров сейчас семь, но каталог для того и
-- сделан, чтобы расти. Строки лежат в ScrollingFrame — добавление товара не требует
-- пересчёта высот и не ломает вёрстку.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local PlateArt = require(ReplicatedStorage:WaitForChild("PlateArt"))
local ShopCatalog = require(ReplicatedStorage:WaitForChild("ShopCatalog"))
local Net = require(ReplicatedStorage:WaitForChild("Net"))

local BONE = UITheme.Palette.Bone
local DARK = UITheme.Shadow -- буквы по костяной подложке
local INK = UITheme.Ink -- буквы по тёмным плашкам
local MOSS = UITheme.Palette.Green
local GREEN_LIGHT = UITheme.Palette.GreenLight
local RED = UITheme.Palette.Red

local PANEL_ATTR = "LobbyPanel"
local PANEL_VALUE = "Shop"

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local shopAction = Net.get(Net.Events.ShopAction)
local shopState = Net.get(Net.Events.ShopState)
local purchaseResult = Net.get(Net.Events.PurchaseResult)

-- Состояние приходит с сервера; до первого пакета показываем пустой кошелёк, а не
-- врём цифрой из воздуха.
local state = {
	bones = 0,
	owned = {} :: { [string]: boolean },
	equipped = ShopCatalog.DefaultSkin,
	equippedBody = ShopCatalog.DefaultBody,
}

local gui = Instance.new("ScreenGui")
gui.Name = "ShopUI"
gui.ResetOnSpawn = false
-- Единая лестница слоёв — в MOBILE_AUDIT.md, раздел 1. Держать номера УНИКАЛЬНЫМИ:
-- при равном DisplayOrder порядок решает положение в PlayerGui, то есть случай, а
-- кнопки сенсорной раскладки (20) — TextButton, они бы съедали касания магазина.
gui.DisplayOrder = 60 -- панель: выше раскладки (20) и прицела (50)
gui.IgnoreGuiInset = true
gui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "Root"
root.Size = UDim2.fromScale(1, 1)
root.BackgroundTransparency = 1
root.Parent = gui
-- МОБИЛЬНЫЙ ЗАЖИМ НИЖЕ ОБЩЕГО (0.5 -> 0.42). Панель высотой 580 при зажиме 0.5
-- требует 290 точек вьюпорта, а телефон отдаёт около 265 — низ панели вместе с
-- кнопкой BACK уезжал за край экрана. 0.42 даёт 244 и вписывает панель целиком.
-- На компьютере не меняется ничего: там множитель упирается в потолок 1.
UITheme.fitToScreen(root, { minScale = 0.42 })

local function engrave(text: string, size: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = UITheme.Font
	l.Text = text
	l.TextColor3 = DARK
	l.TextStrokeTransparency = 1
	l.TextSize = size
	l.ZIndex = 2
	return l
end

-- // Панель — те же размеры, что у опций и ростера ----------------------------
local PANEL_W, PANEL_H = 620, 580
-- ПОЛЕ ПО БОКАМ 132, А НЕ 110 (просьба юзера 2026-09-07): у подложки рваный край,
-- и на 110 строки подходили к самой щетине мазка. Ширины хватает: на контент
-- остаётся 356, из них название 176 и кнопка 158.
local PAD = 132

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Active = true
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.BackgroundTransparency = 1
panel.Visible = false
panel.Parent = root

local backdrop = PlateArt.backdrop(BONE)
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.ZIndex = 1
backdrop.Parent = panel

-- ПОЛЕ СВЕРХУ 36, А НЕ 16 (просьба юзера, общая для всех панелей). У подложки
-- рваный верхний край: на 16 пикселях заголовок садится прямо на щетину мазка и
-- читается прижатым к обрезу. Такой же отступ у панели опций и у ростера.
local TOP_PAD = 36

local title = engrave("SHOP", 48)
title.Size = UDim2.new(1, -2 * PAD, 0, 72)
title.Position = UDim2.fromOffset(PAD, TOP_PAD)
title.TextScaled = true
title.TextXAlignment = Enum.TextXAlignment.Center
title.Parent = panel

-- Кошелёк. Стоит под заголовком и обновляется сам: без него цена на кнопке ни о чём
-- не говорит — игрок не знает, хватает ли ему.
local wallet = engrave("BONES: 0", 30)
wallet.Size = UDim2.new(1, -2 * PAD, 0, 32)
wallet.Position = UDim2.fromOffset(PAD, TOP_PAD + 72)
wallet.TextXAlignment = Enum.TextXAlignment.Center
wallet.Parent = panel

-- Строка ответа сервера («not enough bones», «bought …»). Живёт под кошельком и
-- гаснет сама: всплывающих окон в этом интерфейсе нет.
local notice = engrave("", 22)
notice.Size = UDim2.new(1, -2 * PAD, 0, 24)
notice.Position = UDim2.fromOffset(PAD, TOP_PAD + 106)
notice.TextXAlignment = Enum.TextXAlignment.Center
notice.TextTransparency = 0.15
notice.Parent = panel

-- // Список товаров -----------------------------------------------------------
-- ВЫСОТА СПИСКА ЗАДАНА ЧИСЛОМ, А НЕ «ВСЁ ОСТАВШЕЕСЯ». Первая сборка вычитала из
-- панели только высоту BACK, и список доходил ровно до него: последняя строка
-- обрезалась пополам, а рваный низ подложки резал её ещё раз — читалось как поломка,
-- а не как прокрутка. Теперь между списком и BACK есть чистая полоса, и обрез
-- приходится на плотную часть краски.
-- Высота — РОВНО пять шагов строки (62 + 4 просвета), а не круглое число: иначе
-- нижняя строка обрезается посередине кнопки и читается как поломка вёрстки, а не
-- как «дальше есть ещё». Прокрутку показывает полоса справа.
local ROW_H = 52 -- было 58: строка ужата на 6, чтобы BACK поднялся, а строк осталось пять
local ROW_GAP = 4
local LIST_TOP = TOP_PAD + 140
local LIST_H = 5 * (ROW_H + ROW_GAP) - ROW_GAP

local list = Instance.new("ScrollingFrame")
list.Name = "Items"
list.Position = UDim2.fromOffset(PAD, LIST_TOP)
list.Size = UDim2.new(1, -2 * PAD, 0, LIST_H)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 3
list.ScrollBarImageColor3 = DARK
list.ScrollBarImageTransparency = 0.4
list.CanvasSize = UDim2.new(0, 0, 0, 0)
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.ZIndex = 2
list.Parent = panel

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, ROW_GAP)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

type Row = {
	item: ShopCatalog.Item,
	holder: Frame, -- вся строка: прячется целиком, когда товар закрыт рангом
	button: TextButton,
	caption: TextLabel,
}
local rows: { Row } = {}

-- ЦЕНУ В РОБУКСАХ СПРАШИВАЕМ У ROBLOX, А НЕ ХРАНИМ У СЕБЯ. Она живёт на Creator
-- Dashboard, её можно поменять там в любой момент — вписанная в каталог копия рано
-- или поздно разойдётся с настоящей, и игрок увидит на витрине одно, а в окне
-- покупки другое. Запрос идёт один раз на товар и кэшируется на сессию; пока ответа
-- нет (или его не будет вовсе), на кнопке стоит «R$» — честное «цена в робуксах».
local robuxPrice: { [string]: number } = {}

local function priceText(item: ShopCatalog.Item): string
	if item.bones and item.bones > 0 then
		return tostring(item.bones)
	end
	local r = robuxPrice[item.id]
	return r and (tostring(r) .. " R$") or "R$"
end

-- Что написано на кнопке и какого она цвета — целиком производная от состояния.
-- Отдельной «логики нажатия» нет: обработчик смотрит на то же состояние.
local function renderRow(row: Row)
	local item = row.item
	local owned = state.owned[item.id] == true
	-- Закрытое рангом — не на витрине вовсе (PLAN_SHOP §4): строка схлопывается,
	-- UIListLayout невидимые не считает. Купленное показываем при любом ранге.
	row.holder.Visible = owned or not ShopCatalog.lockedByRank(item, player)
	if owned then
		if item.kind == "skin" or item.kind == "body" then
			-- Кузов и краска — надеваемые слоты, и надет всегда ровно один из каждого.
			-- Подписи USE / IN USE, а не WEAR / WORN (правка юзера 2026-09-07): пара
			-- «надень / надето» читалась двусмысленно — WORN можно понять и как
			-- «изношенный». USE — действие, IN USE — состояние, спутать нечем.
			local worn = (item.kind == "body" and state.equippedBody or state.equipped) == item.id
			row.caption.Text = worn and "IN USE" or "USE"
			PlateArt.tint(row.button, worn and GREEN_LIGHT or MOSS)
		else
			row.caption.Text = "ACTIVE"
			PlateArt.tint(row.button, GREEN_LIGHT)
		end
		return
	end
	if item.bones and item.bones > 0 then
		local enough = state.bones >= item.bones
		row.caption.Text = priceText(item)
		-- Красный тут — «не по карману», тот же единственный красный проекта, каким
		-- в меню помечено «ещё не готов». Никакого второго красного не заводим.
		PlateArt.tint(row.button, enough and MOSS or RED)
	else
		row.caption.Text = priceText(item)
		PlateArt.tint(row.button, MOSS)
	end
end

local function renderAll()
	wallet.Text = "BONES: " .. tostring(state.bones)
	for _, row in rows do
		renderRow(row)
	end
end

local function buildRow(item: ShopCatalog.Item, index: number)
	local holder = Instance.new("Frame")
	holder.Name = item.id
	holder.Size = UDim2.new(1, 0, 0, ROW_H)
	holder.BackgroundTransparency = 1
	holder.LayoutOrder = index
	holder.ZIndex = 2
	holder.Parent = list

	local name = engrave(item.name, 25)
	name.Size = UDim2.new(1, -180, 0, 26)
	name.Position = UDim2.fromOffset(0, 2)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.ZIndex = 3
	name.Parent = holder

	local blurb = engrave(item.blurb, 17)
	blurb.Size = UDim2.new(1, -180, 0, 20)
	blurb.Position = UDim2.fromOffset(0, 28)
	blurb.TextXAlignment = Enum.TextXAlignment.Left
	blurb.TextTransparency = 0.3 -- пояснение тише названия, но читается
	blurb.ZIndex = 3
	blurb.Parent = holder

	-- Номер плашки = порядковый номер строки: PlateArt чередует мазки и повороты,
	-- поэтому две соседние кнопки не выглядят штампованными.
	local button = PlateArt.button(index, MOSS)
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Size = UDim2.fromOffset(146, 42)
	-- Отступ справа — под полосу прокрутки: без него она ложится прямо на кнопки.
	button.Position = UDim2.new(1, -12, 0.5, 0)
	button.ZIndex = 3
	local caption = PlateArt.caption(button, "", INK, 16)
	caption.ZIndex = 4
	button.Parent = holder

	local row: Row = { item = item, holder = holder, button = button, caption = caption }
	table.insert(rows, row)

	button.Activated:Connect(function()
		local owned = state.owned[item.id] == true
		if owned then
			local worn = (item.kind == "body" and state.equippedBody or state.equipped) == item.id
			if (item.kind == "skin" or item.kind == "body") and not worn then
				shopAction:FireServer("equip", item.id)
			end
			return -- надетое и постоянные улучшения нажимать незачем
		end
		if item.bones and item.bones > 0 then
			shopAction:FireServer("buy", item.id)
		else
			shopAction:FireServer("prompt", item.id) -- окно покупки Roblox
		end
	end)
end

-- Стартовый багги на витрину через onSale не попадает: он не продаётся. Но в списке
-- он нужен — купив гроб, игрок должен уметь вернуться на багги. Ставим его первой
-- строкой, надеть его можно всегда.
local function showcase(): { ShopCatalog.Item }
	local list: { ShopCatalog.Item } = {}
	local base = ShopCatalog.get(ShopCatalog.DefaultBody)
	if base then
		table.insert(list, base)
	end
	-- И базовая краска тоже: без неё, надев GRAVE MOSS, вернуться на RUST было негде
	-- (юзер 2026-09-12: «где переключать краску с мха на раст»). Сервер считает её
	-- купленной всегда, кнопка — USE / IN USE, как у багги.
	local baseSkin = ShopCatalog.get(ShopCatalog.DefaultSkin)
	if baseSkin then
		table.insert(list, baseSkin)
	end
	for _, item in ShopCatalog.onSale() do
		table.insert(list, item)
	end
	return list
end

for i, item in showcase() do
	buildRow(item, i)
end

-- Цены за робуксы — фоном, по одному запросу на товар. Витрина уже нарисована и
-- работает без них: придут — просто перерисуемся.
task.spawn(function()
	local MarketplaceService = game:GetService("MarketplaceService")
	local got = false
	for _, item in ShopCatalog.onSale() do
		local id, kind = nil, nil
		if item.gamePass and item.gamePass > 0 then
			id, kind = item.gamePass, Enum.InfoType.GamePass
		elseif item.product and item.product > 0 then
			id, kind = item.product, Enum.InfoType.Product
		end
		if id then
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(id, kind)
			end)
			if ok and type(info) == "table" and tonumber(info.PriceInRobux) then
				robuxPrice[item.id] = tonumber(info.PriceInRobux) :: number
				got = true
			end
		end
	end
	if got then
		renderAll()
	end
end)

-- // BACK — как в опциях: без плашки, одна тёмная надпись ---------------------
local backBtn = Instance.new("TextButton")
backBtn.Name = "BackPlate"
backBtn.AnchorPoint = Vector2.new(0.5, 1)
backBtn.Size = UDim2.fromOffset(340, 52)
-- BACK ПОДНЯТ (просьба юзера 2026-09-07): на -16 кнопка сидела прямо на рваном
-- нижнем крае подложки и читалась прижатой к обрезу. Высвободили место, ужав строку
-- списка с 58 до 52 — пять строк на витрине сохранились.
backBtn.Position = UDim2.new(0.5, 0, 1, -48)
backBtn.BackgroundTransparency = 1
backBtn.AutoButtonColor = false
backBtn.Text = "BACK"
backBtn.TextScaled = true
backBtn.Font = UITheme.Font
backBtn.TextColor3 = DARK
backBtn.TextStrokeTransparency = 1
backBtn.ZIndex = 2
backBtn.Parent = panel
backBtn.MouseEnter:Connect(function()
	backBtn.TextColor3 = RED
end)
backBtn.MouseLeave:Connect(function()
	backBtn.TextColor3 = DARK
end)
backBtn.Activated:Connect(function()
	player:SetAttribute(PANEL_ATTR, "")
end)

-- // Связь с сервером ---------------------------------------------------------
shopState.OnClientEvent:Connect(function(s)
	if type(s) ~= "table" then
		return
	end
	state.bones = tonumber(s.bones) or 0
	state.owned = type(s.owned) == "table" and s.owned or {}
	state.equipped = tostring(s.equipped or ShopCatalog.DefaultSkin)
	state.equippedBody = tostring(s.equippedBody or ShopCatalog.DefaultBody)
	renderAll()
end)

local noticeToken = 0
purchaseResult.OnClientEvent:Connect(function(r)
	if type(r) ~= "table" then
		return
	end
	notice.Text = string.upper(tostring(r.message or ""))
	notice.TextColor3 = r.ok and DARK or RED
	noticeToken += 1
	local mine = noticeToken
	task.delay(4, function()
		if mine == noticeToken then
			notice.Text = ""
		end
	end)
end)

-- Ранг считается из атрибутов ZombiesDefeated/Wins (Ranks.forPlayer) — они
-- реплицируются сами, и когда после заезда ранг вырос, закрытые строки открываются
-- без запроса к серверу.
for _, attr in { "ZombiesDefeated", "Wins" } do
	player:GetAttributeChangedSignal(attr):Connect(renderAll)
end

-- Панель видна ровно тогда, когда меню просит именно её. При открытии просим
-- свежее состояние: кости могли вырасти в заезде, пока витрина была закрыта.
local function applyPanel()
	local open = player:GetAttribute(PANEL_ATTR) == PANEL_VALUE
	panel.Visible = open
	if open then
		notice.Text = ""
		shopAction:FireServer("refresh")
	end
end
player:GetAttributeChangedSignal(PANEL_ATTR):Connect(applyPanel)
applyPanel()

renderAll()
