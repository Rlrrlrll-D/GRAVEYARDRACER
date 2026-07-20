--!strict
-- ModuleScript: ReplicatedStorage.SettingsSchema
-- Описание игровых опций: дефолты + тип + подпись для меню. Клиент строит панель
-- опций по этой схеме; SettingsService (сервер) валидирует по ней же перед
-- сохранением в DataStore. Один источник — нет рассинхрона меню и валидации.

export type Option = {
	key: string,
	label: string,
	kind: "toggle" | "slider",
	default: any,
	min: number?, -- для slider
	max: number?, -- для slider
}

local SettingsSchema = {}

SettingsSchema.Options = {
	{ key = "masterVolume", label = "Общая громкость", kind = "slider", default = 0.8, min = 0, max = 1 },
	{ key = "musicVolume",  label = "Музыка",          kind = "slider", default = 0.6, min = 0, max = 1 },
	{ key = "sfxVolume",    label = "Звуки",           kind = "slider", default = 0.9, min = 0, max = 1 },
	{ key = "cameraShake",  label = "Тряска камеры",   kind = "toggle", default = true },
	{ key = "jumpscares",   label = "Скримеры (мыши)", kind = "toggle", default = true }, -- уважение к пугливым
	{ key = "aimSens",      label = "Чувствит. турели",kind = "slider", default = 0.5, min = 0.1, max = 1 },
} :: { Option }

-- Собрать таблицу дефолтов { key = default }.
function SettingsSchema.defaults(): { [string]: any }
	local t: { [string]: any } = {}
	for _, opt in SettingsSchema.Options do
		t[opt.key] = opt.default
	end
	return t
end

-- Привести пришедшие от клиента значения к валидным (клип слайдеров, буль тумблеров).
function SettingsSchema.sanitize(raw: { [string]: any }): { [string]: any }
	local clean = SettingsSchema.defaults()
	for _, opt in SettingsSchema.Options do
		local v = raw[opt.key]
		if opt.kind == "toggle" and type(v) == "boolean" then
			clean[opt.key] = v
		elseif opt.kind == "slider" and type(v) == "number" then
			clean[opt.key] = math.clamp(v, opt.min or 0, opt.max or 1)
		end
	end
	return clean
end

return SettingsSchema
