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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ranks = require(ReplicatedStorage:WaitForChild("Ranks"))

local ShopCatalog = {}

export type Item = {
	id: string, -- внутренний ключ; он же ключ владения в записи игрока
	name: string, -- подпись на витрине (английская: шрифт Creepster без кириллицы)
	blurb: string, -- строка пояснения под названием
	kind: "skin" | "body" | "perk" | "consumable",
	bones: number?, -- цена в костях; nil = за кости не продаётся
	gamePass: number?, -- id game pass; 0 = ещё не заведён на Dashboard
	product: number?, -- id developer product; 0 = ещё не заведён
	color: Color3?, -- скин: цвет кузова
	material: Enum.Material?, -- скин: материал кузова
	bodyTemplate: string?, -- кузов: имя шаблона в ServerStorage.BodyTemplates
	grantBones: number?, -- расходник: сколько костей выдать
	lives: number?, -- расходник: сколько жизней добавить в заезде
	minRank: string?, -- ранг (имя из GameConfig.Ranks), ниже которого товар скрыт и не продаётся
	-- Пятнистая краска: цвет ложится не сплошь, а локальными пятнами по шуму на
	-- базовой ржавчине (RankSkull.compose). coverage — доля площади под пятнами,
	-- scale — пятен на ширину атласа (больше = мельче), seed — раскладка.
	patchy: { coverage: number, scale: number, seed: number, mode: string?, opacity: number? }?,
}

-- Скин по умолчанию есть у всех и не продаётся: с него игра начинается, и на него
-- же откатывается витрина, если игрок продал/потерял остальное.
ShopCatalog.DefaultSkin = "rust"

-- Кузов по умолчанию — тот самый старый багги, с которого игра начинается. Он не
-- продаётся и есть у всех: слот BODY обязан быть чем-то занят всегда, иначе машина
-- соберётся без кузова. Остальные кузова покупаются и надеваются поверх него.
ShopCatalog.DefaultBody = "buggy"

ShopCatalog.Items = {
	-- // Кузова -------------------------------------------------------------
	-- ФОРМУ КУЗОВА СКРИПТОМ НЕ ПОМЕНЯТЬ: `MeshId` доступен только импортёру
	-- («lacking capability NotAccessible»). Поэтому каждый кузов — отдельный
	-- MeshPart-шаблон в ServerStorage.BodyTemplates, а здесь лежит только ссылка
	-- на его имя. Добавляешь кузов — сперва импортируешь меш руками, потом строку.
	{
		id = "buggy", name = "OLD BUGGY", blurb = "rusted, loud, and yours",
		kind = "body", bodyTemplate = "Buggy",
	},
	{
		id = "coffin", name = "COFFIN", blurb = "you will not need it later",
		kind = "body", bones = 3500, bodyTemplate = "Coffin", minRank = "PALLBEARER",
	},

	-- // Скины кузова -------------------------------------------------------
	{
		id = "rust", name = "RUST", blurb = "the one you started with",
		-- Цвет ДОМНОЖАЕТ текстуру ржавчины — но не сам по себе: текстура на MeshPart
		-- отключает Color3, домножение делает RankSkull в композите (2026-09-11). До этого
		-- краски на багги цвет не давали вовсе, и ржавчина шла в полную яркость (×1.0).
		-- Подобрано юзером в SkullTune 2026-09-12: тёплый тинт ×0.9/0.85/0.74 (229,217,188);
		-- старые 163 дали бы ×0.64 и совсем тёмный кузов.
		kind = "skin", color = Color3.fromRGB(229, 217, 188), material = Enum.Material.Plastic,
	},
	{
		id = "bone", name = "BONE WHITE", blurb = "scrubbed clean, mostly",
		kind = "skin", bones = 1500,
		color = Color3.fromRGB(224, 214, 170), material = Enum.Material.Sand,
	},
	{
		id = "moss", name = "GRAVE MOSS", blurb = "parked too long in the wrong row",
		kind = "skin", bones = 2500,
		-- Мох пятнами, а не сплошь (юзер: «локальными участками»). Цвет и пятна подобраны
		-- юзером в SkullTune 2026-09-12 (было 52,90,64 сплошь; потом 1/6 tint): треть
		-- кузова под мхом, Soft Light 0.70, пятна мельче (scale 12.4), раскладка seed 18.
		color = Color3.fromRGB(45, 78, 37), material = Enum.Material.Grass,
		patchy = { coverage = 0.308, scale = 12.4, seed = 18, mode = "softlight", opacity = 0.70 },
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
	if item.id == ShopCatalog.DefaultSkin or item.id == ShopCatalog.DefaultBody then
		return true
	end
	return (item.bones ~= nil and item.bones > 0)
		or (item.gamePass ~= nil and item.gamePass > 0)
		or (item.product ~= nil and item.product > 0)
end

-- ГЕЙТ ПО РАНГУ (PLAN_SHOP §4): товар с `minRank` до этого ранга не показывается и
-- не продаётся — первая крупная покупка не должна случиться в первые десять минут,
-- иначе цель кончится, не начавшись. Уже купленное гейт не трогает: владение
-- решает само. Проверяют и витрина, и сервер — по одному и тому же Ranks.
function ShopCatalog.lockedByRank(item: Item, player: Player): boolean
	local need = item.minRank and Ranks.indexOf(item.minRank)
	if not need then
		return false
	end
	return Ranks.forPlayer(player).index < need
end

-- Что показывать на витрине. Ненастроенные товары скрыты: пустая плашка «скоро»
-- хуже, чем её отсутствие, а купить её всё равно нельзя.
function ShopCatalog.onSale(): { Item }
	local list: { Item } = {}
	for _, item in ShopCatalog.Items do
		local isDefault = item.id == ShopCatalog.DefaultSkin or item.id == ShopCatalog.DefaultBody
		if ShopCatalog.isConfigured(item) and not isDefault then
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

-- Кузова, доступные для примерки: базовый багги + всё купленное.
function ShopCatalog.bodies(): { Item }
	local list: { Item } = {}
	for _, item in ShopCatalog.Items do
		if item.kind == "body" then
			table.insert(list, item)
		end
	end
	return list
end

return ShopCatalog
