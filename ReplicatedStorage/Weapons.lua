--!strict
-- ModuleScript: ReplicatedStorage.Weapons
-- СЛОТ WEAPON (PLAN_SHOP §6 шаг 5, 2026-09-12): характеристики стволов и всё, что должно
-- совпадать у клиента и сервера. Клиент рисует выстрел предсказанием, сервер считает
-- попадания — поэтому разброс дробин у обоих считается ОДНОЙ функцией от одного seed
-- (клиент шлёт seed вместе с направлением): трассеры совпадают с тем, куда прилетело.
--
-- Что надето, лежит в атрибуте игрока EquippedWeapon (ShopService/PlayerData), меш
-- ствола подставляет PlayerFlow.applyWeapon по ShopCatalog.Item.mount.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))

local Weapons = {}

export type Stats = {
	id: string,
	damage: number, -- урон ОДНОЙ дробины
	range: number,
	fireRate: number, -- выстрелов в секунду
	pellets: number, -- дробин за выстрел (1 — обычная пуля)
	spread: number, -- полуугол конуса разброса, градусы (0 — точно)
	-- вид и звук выстрела (только клиент)
	tracerColor: Color3,
	tracerWidth: number, -- 0 — трассера нет, только вспышка (дробовик)
	flashSize: number,
	flashColor: Color3,
	flashLife: number?, -- с; по умолчанию 0.05
	flashLength: number?, -- язык огня: вытянуть вспышку вдоль выстрела на столько studs (дробовик)
	lightBrightness: number?, -- PointLight вспышки; по умолчанию 6
	lightRange: number?, -- по умолчанию 10 + 4·flashSize
	flashTransparency: number?, -- 0 — плотный шар; >0 — прозрачность (для спрайта — его ImageTransparency)
	-- малое ядро внутри вспышки: свой цвет, при flashLength — та же вытянутая форма своей
	-- длины (length), и свой малый PointLight (light/lightRange)
	flashCore: { size: number, color: Color3, length: number?, light: number?, lightRange: number?, up: number? }?, -- up: сдвиг над пламенем, studs
	-- Спрайт вместо неонового шара (дробовик): мягкое свечение без плотного ядра —
	-- билборд с встроенной текстурой Roblox, всегда полной яркости (LightInfluence 0).
	flashSprite: string?,
	soundId: string,
	soundVolume: number,
	soundPitch: number, -- множитель PlaybackSpeed
	soundRange: number?, -- RollOffMaxDistance; по умолчанию 220
}

Weapons.Default = "machinegun"

-- Тюнинг: пулемёт — прежние числа (GameConfig.Weapon), от него и считались остальные.
-- NAILER — дробовик: восемь гвоздей по 14 в упор кладут зомби с одного выстрела, но
-- медленно и близко. RATTLE — гатлинг: тонкая струя, урон в секунду чуть выше пулемёта,
-- зато лёгкий разброс и промахи на ходу.
local mg = GameConfig.Weapon
local MG_SOUND = "rbxassetid://88311346538102" -- «Machine gun shot», 0.22 с (Free Creator Store)
Weapons.Stats = {
	machinegun = {
		id = "machinegun", damage = mg.Damage, range = mg.Range, fireRate = mg.FireRate, pellets = 1, spread = 0,
		tracerColor = Color3.fromRGB(224, 214, 170), tracerWidth = 0.15, flashSize = 1.1, flashColor = Color3.fromRGB(255, 220, 130),
		soundId = MG_SOUND, soundVolume = 0.55, soundPitch = 1.0,
	},
	nailer = {
		id = "nailer", damage = 14, range = 110, fireRate = 1.4, pellets = 8, spread = 7,
		-- Красный (юзер 2026-09-13: трассеры разных стволов — разных оттенков). Трассеров
		-- нет, вспышка — тот же неоновый шар, что у остальных, только крупнее (юзер: «сделай
		-- как у других, только без трассеров»); звук ниже и громче.
		-- Цвет вспышки ТЁМНО-красный нарочно: неон яркого цвета под блюмом выгорает в
		-- жёлто-белое ядро («жёлтый круг в середине») — это рендер неона, а не второй шар;
		-- у (150,30,30) ядра нет.
		-- вспышка — язык огня из ствола: эллипсоид 0.4 в поперечнике и 1.1 в длину (юзер
		-- 2026-09-13: было 1.5×4.5, «уменьшь вчетверо»). ЦВЕТ ЯРКО-КРАСНЫЙ: неон светится
		-- пропорционально яркости цвета, тёмный (150,30,30) не светился вовсе; свет на
		-- сцену — отдельный сильный красный PointLight («мне нужен красный СВЕТ»).
		-- Свет на сцену — как у соседей (яркость 6): 24 клало плотное красное пятно вокруг;
		-- мягкое удалённое свечение даёт та же яркость с радиусом побольше. Источник ярче
		-- цветом (255,60,50).
		-- Два света: красное пламя 0.4×2.0 и внутри тёплое ядро 0.16×1.6 цвета пулемётной
		-- вспышки со своим малым светом (юзер 2026-09-13); оба вытянуты по выстрелу.
		tracerColor = Color3.fromRGB(255, 84, 60), tracerWidth = 0, flashSize = 0.4, flashLength = 2.0, flashColor = Color3.fromRGB(255, 60, 50), flashLife = 0.08,
		lightBrightness = 6, lightRange = 22,
		-- пламя полупрозрачное: неон непрозрачен, и ядро внутри было не видно —
		-- «светлый источник должен быть выше красного» (юзер 2026-09-13)
		-- пламя заметно прозрачное (0.7): 0.22 визуально не отличалось от плотного (юзер)
		flashTransparency = 0.7,
		-- ядро — над пламенем, не внутри, и крупнее (0.08 на дистанции не читалось)
		flashCore = { size = 0.16, color = Color3.fromRGB(255, 220, 130), length = 1.2, light = 4, lightRange = 12, up = 0.36 },
		soundId = "rbxassetid://85341259642501", soundVolume = 1.6, soundPitch = 0.8, soundRange = 320, -- «HM Alternate Shotgun Shot», 1.28 с
	},
	rattle = {
		id = "rattle", damage = 9, range = 260, fireRate = 15, pellets = 1, spread = 2.2,
		-- зелёный, могильный
		tracerColor = Color3.fromRGB(150, 255, 110), tracerWidth = 0.12, flashSize = 1.6, flashColor = Color3.fromRGB(190, 255, 140), -- 0.9→1.6: «увеличить радиус свечения»
		soundId = MG_SOUND, soundVolume = 0.4, soundPitch = 1.35,
	},
} :: { [string]: Stats }

function Weapons.get(id: any): Stats
	return (type(id) == "string" and Weapons.Stats[id]) or Weapons.Stats[Weapons.Default]
end

function Weapons.forPlayer(player: Player): Stats
	return Weapons.get(player:GetAttribute("EquippedWeapon"))
end

-- Направления дробин: конус вокруг direction, раскладка детерминирована seed'ом — клиент
-- и сервер получают один и тот же веер. Первая дробина всегда точно по центру.
function Weapons.pelletDirections(direction: Vector3, stats: Stats, seed: number): { Vector3 }
	local dir = direction.Unit
	local n = math.max(1, stats.pellets)
	local dirs = table.create(n)
	if stats.spread <= 0 then
		for i = 1, n do
			dirs[i] = dir
		end
		return dirs
	end
	local rng = Random.new(seed)
	local up = if math.abs(dir.Y) < 0.99 then Vector3.yAxis else Vector3.xAxis
	local right = dir:Cross(up).Unit
	local upv = right:Cross(dir).Unit
	local maxR = math.tan(math.rad(stats.spread))
	for i = 1, n do
		if i == 1 and n > 1 then
			dirs[i] = dir
		else
			-- равномерно по кругу, а не по радиусу: иначе дробь кучкуется в центре
			local r = maxR * math.sqrt(rng:NextNumber())
			local a = rng:NextNumber() * 2 * math.pi
			dirs[i] = (dir + right * (r * math.cos(a)) + upv * (r * math.sin(a))).Unit
		end
	end
	return dirs
end

return Weapons
