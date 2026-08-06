--!strict
-- Script: ServerScriptService.ShopService
-- МАГАЗИН. Три источника денег, и все три сходятся здесь:
--   * кости         — внутренняя валюта, тратит Economy.spend;
--   * game pass     — постоянные покупки (скины, «двойные кости»); владение
--                     спрашивается у Roblox, а НЕ хранится в нашей записи;
--   * dev product   — расходники (жизнь, мешок костей), приходят в ProcessReceipt.
--
-- ЧТО ЗДЕСЬ КРИТИЧНО, И ПОЧЕМУ ИМЕННО ТАК:
--
-- 1. ПОВТОРНАЯ ВЫДАЧА. Roblox вызывает ProcessReceipt СНОВА, если мы не успели
--    ответить PurchaseGranted — после падения сервера, таймаута, чего угодно. Без
--    защиты игрок получал бы «мешок костей» дважды за одну оплату. Поэтому у чеков
--    свой DataStore, и покупка СНАЧАЛА застолбляется через UpdateAsync (атомарно,
--    даже если два сервера обрабатывают один чек), и только потом выдаётся. Если
--    столбик уже стоит — значит выдали раньше, отвечаем Granted и ничего не делаем.
--
-- 2. ВЛАДЕНИЕ ПРОПУСКОМ НЕ КЭШИРУЕТСЯ В ЗАПИСЬ. Отозванный/возвращённый пропуск
--    остался бы «купленным» навсегда. Кэш только на сессию и только в памяти —
--    UserOwnsGamePassAsync это сетевой вызов, дёргать его на каждый клик нельзя.
--
-- 3. КЛИЕНТ НЕ НАЗЫВАЕТ ЦЕНУ. Он присылает только id товара; цену, вид и право на
--    покупку сервер берёт из ShopCatalog заново. Присланное «купить за 0» ничего не
--    значит — такого поля в протоколе просто нет.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local ShopCatalog = require(ReplicatedStorage:WaitForChild("ShopCatalog"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local Economy = require(script.Parent:WaitForChild("Economy"))
local VehicleRegistry = require(ReplicatedStorage:WaitForChild("VehicleRegistry"))

local shopAction = Net.get(Net.Events.ShopAction)
local shopState = Net.get(Net.Events.ShopState)
local purchaseResult = Net.get(Net.Events.PurchaseResult)

local RECEIPTS_STORE = "ShopReceipts_v1"
local receipts: GlobalDataStore? = nil
do
	local ok, s = pcall(function()
		return DataStoreService:GetDataStore(RECEIPTS_STORE)
	end)
	if ok then
		receipts = s
	else
		warn("[ShopService] DataStore чеков недоступен: " .. tostring(s))
	end
end

-- // Владение пропусками ------------------------------------------------------
-- Кэш на сессию: { [player] = { [gamePassId] = boolean } }.
local passCache: { [Player]: { [number]: boolean } } = {}

local function ownsPass(player: Player, passId: number): boolean
	if passId <= 0 then
		return false
	end
	local mine = passCache[player]
	if not mine then
		mine = {}
		passCache[player] = mine
	end
	local known = mine[passId]
	if known ~= nil then
		return known
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
	end)
	if not ok then
		return false -- сеть отвалилась: НЕ кэшируем, спросим в следующий раз
	end
	mine[passId] = owns
	return owns
end

-- Владеет ли игрок товаром: либо куплено за кости (запись), либо есть пропуск.
local function ownsItem(player: Player, item: ShopCatalog.Item): boolean
	if item.id == ShopCatalog.DefaultSkin then
		return true
	end
	if PlayerData.owns(player, item.id) then
		return true
	end
	return item.gamePass ~= nil and ownsPass(player, item.gamePass)
end

-- // Применение купленного ----------------------------------------------------
-- «Двойные кости» — множитель для Economy. Ставится атрибутом, чтобы Economy не
-- знала про MarketplaceService, а зависимость шла в одну сторону.
local function refreshMultiplier(player: Player)
	local perk = ShopCatalog.get("double_bones")
	local double = perk ~= nil and perk.gamePass ~= nil and ownsPass(player, perk.gamePass)
	player:SetAttribute("BonesMultiplier", double and 2 or 1)
end

-- Скин красит кузов. Меш кузова один (BuggyBody), у него есть текстура — цвет её
-- домножает, ровно как у деревьев в MapBuilder.
local function paintVehicle(player: Player)
	local car = VehicleRegistry.GetVehicleForPlayer(player)
	if not car then
		return
	end
	local skin = ShopCatalog.get(player:GetAttribute("EquippedSkin"))
	if not (skin and skin.kind == "skin") then
		skin = ShopCatalog.get(ShopCatalog.DefaultSkin)
	end
	local body = car:FindFirstChild("BuggyBody")
	if body and body:IsA("BasePart") and skin then
		if skin.color then
			body.Color = skin.color
		end
		if skin.material then
			body.Material = skin.material
		end
	end
end

-- // Пакет состояния ----------------------------------------------------------
local function pushState(player: Player)
	if not player.Parent then
		return
	end
	local owned = PlayerData.ownedList(player)
	-- Пропуска в список владения досыпаем на лету: в записи их нет и быть не должно.
	for _, item in ShopCatalog.Items do
		if item.gamePass and item.gamePass > 0 and ownsPass(player, item.gamePass) then
			owned[item.id] = true
		end
	end
	owned[ShopCatalog.DefaultSkin] = true
	shopState:FireClient(player, {
		bones = Economy.balance(player),
		owned = owned,
		equipped = player:GetAttribute("EquippedSkin") or ShopCatalog.DefaultSkin,
	})
end

local function reply(player: Player, ok: boolean, itemId: string?, message: string)
	purchaseResult:FireClient(player, { ok = ok, item = itemId, message = message })
	pushState(player)
end

-- // Действия игрока ----------------------------------------------------------
local function doBuy(player: Player, item: ShopCatalog.Item)
	if not (item.bones and item.bones > 0) then
		reply(player, false, item.id, "not sold for bones")
		return
	end
	if ownsItem(player, item) then
		reply(player, false, item.id, "already owned")
		return
	end
	if not Economy.spend(player, item.bones, "магазин: " .. item.id) then
		reply(player, false, item.id, "not enough bones")
		return
	end
	PlayerData.grant(player, item.id)
	reply(player, true, item.id, "bought " .. item.name)
end

local function doEquip(player: Player, item: ShopCatalog.Item)
	if item.kind ~= "skin" then
		reply(player, false, item.id, "not a skin")
		return
	end
	if not ownsItem(player, item) then
		reply(player, false, item.id, "not owned")
		return
	end
	player:SetAttribute("EquippedSkin", item.id)
	paintVehicle(player)
	reply(player, true, item.id, "equipped " .. item.name)
end

local function doPrompt(player: Player, item: ShopCatalog.Item)
	if item.gamePass and item.gamePass > 0 then
		if ownsPass(player, item.gamePass) then
			reply(player, false, item.id, "already owned")
			return
		end
		pcall(function()
			MarketplaceService:PromptGamePassPurchase(player, item.gamePass)
		end)
	elseif item.product and item.product > 0 then
		pcall(function()
			MarketplaceService:PromptProductPurchase(player, item.product)
		end)
	else
		reply(player, false, item.id, "not available yet")
	end
end

shopAction.OnServerEvent:Connect(function(player, action, itemId)
	if type(action) ~= "string" then
		return
	end
	-- «Обновить» товара не называет — разбираем ДО поиска в каталоге, иначе витрина
	-- при открытии получает «нет такого товара» вместо состояния.
	if action == "refresh" then
		pushState(player)
		return
	end
	local item = ShopCatalog.get(itemId)
	if not item or not ShopCatalog.isConfigured(item) then
		reply(player, false, nil, "no such item")
		return
	end
	if action == "buy" then
		doBuy(player, item)
	elseif action == "equip" then
		doEquip(player, item)
	elseif action == "prompt" then
		doPrompt(player, item)
	end
end)

-- // Расходники: ProcessReceipt ----------------------------------------------
-- Возвращает true, если ЭТОТ вызов застолбил чек (то есть выдавать надо нам).
-- Уже застолблённый чек значит «выдали раньше» — повторять нельзя.
local function claimReceipt(key: string): boolean?
	if not receipts then
		return nil -- без DataStore защиты от повтора нет; лучше не выдавать вообще
	end
	local ok, fresh = pcall(function()
		return (receipts :: GlobalDataStore):UpdateAsync(key, function(old)
			if old ~= nil then
				return nil -- отменяем транзакцию: чек уже обработан
			end
			return os.time()
		end)
	end)
	if not ok then
		return nil -- сеть: пусть Roblox повторит вызов позже
	end
	return fresh ~= nil
end

local function grantProduct(player: Player, item: ShopCatalog.Item): boolean
	if item.grantBones and item.grantBones > 0 then
		Economy.award(player, item.grantBones, "покупка: " .. item.id)
		return true
	end
	if item.lives and item.lives > 0 then
		-- Жизнь имеет смысл ТОЛЬКО в идущем заезде: машина есть — добавляем, нет —
		-- честно отказываемся, и Roblox вернёт деньги (мы не отвечаем Granted).
		local car = VehicleRegistry.GetVehicleForPlayer(player)
		if not car then
			return false
		end
		car:SetAttribute("Lives", ((car:GetAttribute("Lives") :: number?) or 0) + item.lives)
		return true
	end
	-- Товар без эффекта — считаем выданным, иначе Roblox будет звонить вечно.
	PlayerData.grant(player, item.id)
	return true
end

local function productItem(productId: number): ShopCatalog.Item?
	for _, item in ShopCatalog.Items do
		if item.product == productId and productId > 0 then
			return item
		end
	end
	return nil
end

MarketplaceService.ProcessReceipt = function(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		-- Ушёл до выдачи. НЕ Granted: Roblox позвонит снова, когда он вернётся.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local item = productItem(info.ProductId)
	if not item then
		warn(("[ShopService] Оплачен неизвестный товар %d (%s) — в каталоге его нет."):format(info.ProductId, player.Name))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local key = "r" .. tostring(info.PurchaseId)
	local claimed = claimReceipt(key)
	if claimed == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- нет связи, повторим позже
	end
	if not claimed then
		-- Этот чек уже отработан раньше. Товар выдан, второй раз не выдаём.
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	if not grantProduct(player, item) then
		-- Выдать не смогли (нет машины для «ещё одной жизни»). Столбик снимаем,
		-- иначе оплата сгорит вместе с ним.
		pcall(function()
			(receipts :: GlobalDataStore):RemoveAsync(key)
		end)
		reply(player, false, item.id, "cannot use that right now")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	print(("[ShopService] %s купил %s (чек %s)"):format(player.Name, item.id, tostring(info.PurchaseId)))
	reply(player, true, item.id, "purchased " .. item.name)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Пропуск куплен прямо сейчас — сразу применяем, не дожидаясь перезахода.
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
	if not wasPurchased then
		return
	end
	local mine = passCache[player]
	if mine then
		mine[passId] = true
	end
	refreshMultiplier(player)
	pushState(player)
end)

-- // Жизненный цикл -----------------------------------------------------------
local function onLoaded(player: Player)
	if player:GetAttribute("EquippedSkin") == nil then
		player:SetAttribute("EquippedSkin", ShopCatalog.DefaultSkin)
	end
	refreshMultiplier(player)
	pushState(player)
end

PlayerData.Loaded:Connect(onLoaded)
for _, p in Players:GetPlayers() do
	if PlayerData.isLoaded(p) then
		task.spawn(onLoaded, p)
	end
end

Players.PlayerRemoving:Connect(function(player)
	passCache[player] = nil
end)

-- Кости меняются постоянно (чекпоинт, зомби, финиш) — витрина должна видеть свежий
-- баланс, не переспрашивая. Но слать пакет на КАЖДОЕ изменение нельзя: в заезде это
-- десятки посылок в минуту на игрока, а смотреть на них в этот момент некому.
-- Поэтому отложенная склейка: первое изменение ставит таймер, все следующие за
-- секунду в него сливаются.
local statePending: { [Player]: boolean } = {}
local function pushStateSoon(player: Player)
	if statePending[player] then
		return
	end
	statePending[player] = true
	task.delay(1, function()
		statePending[player] = nil
		pushState(player)
	end)
end

local function watchBones(player: Player)
	player:GetAttributeChangedSignal("Bones"):Connect(function()
		pushStateSoon(player)
	end)
end
Players.PlayerAdded:Connect(watchBones)
for _, p in Players:GetPlayers() do
	watchBones(p)
end

print("[ShopService] Магазин: " .. #ShopCatalog.onSale() .. " настроенных товаров из " .. #ShopCatalog.Items .. ".")
