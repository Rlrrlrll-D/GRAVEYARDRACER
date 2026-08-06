--!strict
-- ModuleScript: ReplicatedStorage.ShopCatalog
-- ЕДИНЫЙ СПИСОК ТОВАРОВ — и для витрины, и для проверки на сервере. Тем же приёмом,
-- что и SettingsSchema: клиент строит магазин по этому списку, ShopService по нему же
-- валидирует покупку. Один источник — нельзя купить то, чего нет на витрине, и
-- нельзя нарисовать на витрине то, чего сервер не знает.
--
-- ЧТО ЗДЕСЬ НАСТРАИВАТЬ РУКАМИ. `gamePass` и `product` — числовые id из Creator
-- Dashboard, и создаются они ТОЛЬКО там, кодом их не завести. Пока стоит 0, товар
-- считается ненастроенным: на витрину он не попадает, купить его нельзя, сервер о
-- нём молчит. Впиши номера — товар появится сам, больше ничего менять не надо.
--
-- Заведено 2026-08-06 во вселенной 10439035420 (GraveyardRacer). Id привязаны к
-- ВСЕЛЕННОЙ: в другой копии места они не сработают — UserOwnsGamePassAsync ответит
-- «не куплено», а окно покупки откроется от чужого экспириенса. Цены на Dashboard:
-- BLOOD RED 75, GHOST 99, DOUBLE BONES 149, ONE MORE LIFE 25, SACK OF BONES 49.
-- У пропусков отдельно включён «Item for sale», managed pricing выключен.
--
-- ЦЕНЫ В КОСТЯХ прикинуты от заработка (см. GameConfig.Economy): победный заезд
-- приносит около 220 костей, проигранный, но доеханный — около 145. То есть скин за
-- 1500 — это примерно десяток заездов.

local ShopCatalog = {}

export type Item = {
	id: string, -- внутренний ключ; он же ключ владения в записи игрока
	name: string, -- подпись на витрине (английская: шрифт Creepster без кириллицы)
	blurb: string, -- строка пояснения под названием
	kind: "skin" | "perk" | "consumable",
	bones: number?, -- цена в костях; nil = за кости не продаётся
	gamePass: number?, -- id game pass; 0 = ещё не заведён на Dashboard
	product: number?, -- id developer product; 0 = ещё не заведён
	color: Color3?, -- скин: цвет кузова
	material: Enum.Material?, -- скин: материал кузова
	grantBones: number?, -- расходник: сколько костей выдать
	lives: number?, -- расходник: сколько жизней добавить в заезде
}

-- Скин по умолчанию есть у всех и не продаётся: с него игра начинается, и на него
-- же откатывается витрина, если игрок продал/потерял остальное.
ShopCatalog.DefaultSkin = "rust"

ShopCatalog.Items = {
	-- // Скины кузова -------------------------------------------------------
	{
		id = "rust", name = "RUST", blurb = "the one you started with",
		kind = "skin", color = Color3.fromRGB(163, 162, 165), material = Enum.Material.Plastic,
	},
	{
		id = "bone", name = "BONE WHITE", blurb = "scrubbed clean, mostly",
		kind = "skin", bones = 1500,
		color = Color3.fromRGB(224, 214, 170), material = Enum.Material.Sand,
	},
	{
		id = "moss", name = "GRAVE MOSS", blurb = "parked too long in the wrong row",
		kind = "skin", bones = 2500,
		color = Color3.fromRGB(52, 90, 64), material = Enum.Material.Grass,
	},
	{
		id = "blood", name = "BLOOD RED", blurb = "don't ask whose",
		kind = "skin", gamePass = 1936671086,
		color = Color3.fromRGB(150, 30, 30), material = Enum.Material.Metal,
	},
	{
		id = "ghost", name = "GHOST", blurb = "barely there",
		kind = "skin", gamePass = 1939076495,
		color = Color3.fromRGB(198, 214, 214), material = Enum.Material.Glass,
	},

	-- // Постоянные улучшения ------------------------------------------------
	{
		id = "double_bones", name = "DOUBLE BONES", blurb = "every bone counts twice, forever",
		kind = "perk", gamePass = 1936736851,
	},

	-- // Расходники ---------------------------------------------------------
	{
		id = "extra_life", name = "ONE MORE LIFE", blurb = "get back in the race",
		kind = "consumable", product = 3631288689, lives = 1,
	},
	{
		id = "bone_bag", name = "SACK OF BONES", blurb = "2500 bones, no digging",
		kind = "consumable", product = 3631294206, grantBones = 2500,
	},
} :: { Item }

local byId: { [string]: Item } = {}
for _, item in ShopCatalog.Items do
	byId[item.id] = item
end

function ShopCatalog.get(id: any): Item?
	return type(id) == "string" and byId[id] or nil
end

-- Настроен ли товар: за кости — есть цена; за робуксы — вписан ненулевой id.
-- Скин по умолчанию настроен всегда: он бесплатный и выдаётся сам.
function ShopCatalog.isConfigured(item: Item): boolean
	if item.id == ShopCatalog.DefaultSkin then
		return true
	end
	return (item.bones ~= nil and item.bones > 0)
		or (item.gamePass ~= nil and item.gamePass > 0)
		or (item.product ~= nil and item.product > 0)
end

-- Что показывать на витрине. Ненастроенные товары скрыты: пустая плашка «скоро»
-- хуже, чем её отсутствие, а купить её всё равно нельзя.
function ShopCatalog.onSale(): { Item }
	local list: { Item } = {}
	for _, item in ShopCatalog.Items do
		if ShopCatalog.isConfigured(item) and item.id ~= ShopCatalog.DefaultSkin then
			table.insert(list, item)
		end
	end
	return list
end

-- Скины, доступные для примерки: бесплатный по умолчанию + всё купленное.
function ShopCatalog.skins(): { Item }
	local list: { Item } = {}
	for _, item in ShopCatalog.Items do
		if item.kind == "skin" then
			table.insert(list, item)
		end
	end
	return list
end

return ShopCatalog
