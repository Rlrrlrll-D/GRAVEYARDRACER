--!strict
-- Script: ServerScriptService.SettingsService
-- Опции игрока (веха 5): приём SaveSettings → sanitize по SettingsSchema → эхо
-- PushSettings обратно клиенту. Потребители на клиенте (AudioController, BatFX,
-- UIController, TurretAimClient) подписаны на PushSettings — единый путь
-- доставки. Пока значения живут в памяти сессии; DataStore-персистентность
-- (+статистика: убитые зомби, победы) — веха 6b, добавится вокруг этого же кода.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local SettingsSchema = require(ReplicatedStorage:WaitForChild("SettingsSchema"))

local saveSettings = Net.get(Net.Events.SaveSettings)
local pushSettings = Net.get(Net.Events.PushSettings)

local settingsOf: { [Player]: { [string]: any } } = {}

local function push(player: Player)
	local s = settingsOf[player]
	if s then
		pushSettings:FireClient(player, s)
	end
end

local function onJoin(player: Player)
	settingsOf[player] = SettingsSchema.defaults() -- TODO веха 6b: загрузка из DataStore
	push(player)
end

Players.PlayerAdded:Connect(onJoin)
for _, p in Players:GetPlayers() do
	onJoin(p)
end
Players.PlayerRemoving:Connect(function(player)
	-- TODO веха 6b: сохранить settingsOf[player] в DataStore
	settingsOf[player] = nil
end)

saveSettings.OnServerEvent:Connect(function(player, raw)
	if type(raw) ~= "table" then
		return
	end
	settingsOf[player] = SettingsSchema.sanitize(raw)
	push(player)
end)

print("[SettingsService] Опции: SaveSettings→sanitize→PushSettings (DataStore — веха 6b).")
