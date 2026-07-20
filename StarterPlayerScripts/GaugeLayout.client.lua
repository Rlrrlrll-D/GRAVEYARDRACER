--!strict
-- LocalScript: StarterPlayerScripts.GaugeLayout
-- Полностью убирает штатный интерфейс A-Chassis (спидометр/тахометр/передача/
-- кнопка Controls) — выключает ScreenGui "A-Chassis Interface" (Enabled=false),
-- как только он появляется в PlayerGui. Скрипты вождения/звука/камеры внутри
-- продолжают работать (Enabled влияет только на отрисовку). Свою скорость игрок
-- видит в собственном HUD (UIController).

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function hideInterface(iface: Instance)
	if iface:IsA("LayerCollector") then
		local sg = iface :: LayerCollector
		sg.Enabled = false
		sg:GetPropertyChangedSignal("Enabled"):Connect(function()
			if sg.Enabled then
				sg.Enabled = false -- A-Chassis не должен вернуть приборы обратно
			end
		end)
	else
		for _, c in iface:GetChildren() do
			if c:IsA("GuiObject") then
				(c :: GuiObject).Visible = false
			end
		end
	end
end

for _, gui in playerGui:GetChildren() do
	if gui.Name == "A-Chassis Interface" then
		hideInterface(gui)
	end
end
playerGui.ChildAdded:Connect(function(gui)
	if gui.Name == "A-Chassis Interface" then
		hideInterface(gui)
	end
end)
