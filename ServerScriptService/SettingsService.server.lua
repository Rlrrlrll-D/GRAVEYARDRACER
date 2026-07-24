--!strict
-- Script: ServerScriptService.SettingsService
-- Опции игрока: SaveSettings → sanitize по SettingsSchema → PlayerData
-- (персистентно, веха 6b) → эхо PushSettings. При входе PlayerData грузит
-- запись из DataStore и по событию Loaded клиенту уходят сохранённые опции.
-- Потребители на клиенте (AudioController, BatFX, UIController, TurretAimClient,
-- OptionsMenu-UI) подписаны на PushSettings — единый путь доставки.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local SettingsSchema = require(ReplicatedStorage:WaitForChild("SettingsSchema"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local saveSettings = Net.get(Net.Events.SaveSettings)
local pushSettings = Net.get(Net.Events.PushSettings)

local function push(player: Player)
	pushSettings:FireClient(player, PlayerData.get(player).settings)
end

PlayerData.Loaded:Connect(push) -- сохранённые опции уезжают клиенту при входе
for _, p in Players:GetPlayers() do
	if PlayerData.isLoaded(p) then
		push(p) -- успел загрузиться до нашей подписки
	end
end

saveSettings.OnServerEvent:Connect(function(player, raw)
	if type(raw) ~= "table" then
		return
	end
	PlayerData.setSettings(player, SettingsSchema.sanitize(raw))
	push(player)
end)

print("[SettingsService] Опции: sanitize→PlayerData(DataStore)→PushSettings.")
