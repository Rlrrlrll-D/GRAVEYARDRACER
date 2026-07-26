-- LocalScript: StarterPlayerScripts.DecorPreload
-- Фон-прелоад мешей карты. Roblox подгружает ГЕОМЕТРИЮ/ТЕКСТУРУ меша при первом
-- показе камерой — отсюда рывки «на участках трассы» (въехал в новую зону с
-- надгробиями/деревьями → кадр грузит их меши → фриз). Прогреваем всё разом в
-- начале, пока игрок под заставкой, чтобы в заезде дороги не спотыкались.
-- Дёшево: PreloadAsync дедуплицирует по ассету; в списке — только уникальные ID.

local ContentProvider = game:GetService("ContentProvider")

task.spawn(function()
	local gm = workspace:WaitForChild("GeneratedMap", 45)
	if not gm then
		return
	end
	task.wait(1) -- дать декору догенериться

	local seen: { [string]: boolean } = {}
	local urls: { string } = {}
	local function collect(root: Instance?)
		if not root then
			return
		end
		for _, d in root:GetDescendants() do
			if d:IsA("MeshPart") then
				for _, id in { d.MeshId, d.TextureID } do
					if id ~= "" and not seen[id] then
						seen[id] = true
						table.insert(urls, id)
					end
				end
			elseif d:IsA("Decal") or d:IsA("Texture") then
				local id = d.Texture
				if id ~= "" and not seen[id] then
					seen[id] = true
					table.insert(urls, id)
				end
			end
		end
	end
	collect(gm)
	collect(workspace:FindFirstChild("PerimeterFence"))
	collect(workspace:FindFirstChild("StartGate"))
	collect(workspace:FindFirstChild("GateSign"))

	pcall(function()
		ContentProvider:PreloadAsync(urls)
	end)
end)
