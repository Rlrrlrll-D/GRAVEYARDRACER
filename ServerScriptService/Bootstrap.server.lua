--!strict
-- Script: ServerScriptService.Bootstrap
-- Runs once on server start. Creates shared Remotes and configures
-- PhysicsService collision groups. Every other script WaitForChild()s
-- the Remotes folder, so load order relative to this script doesn't matter.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")

-- // Remotes -----------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage

local function newRemoteEvent(name: string): RemoteEvent
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = remotes
	return event
end

newRemoteEvent("FireWeapon")  -- client -> server: (origin: Vector3, direction: Vector3)
newRemoteEvent("BulletFired") -- server -> clients: (origin: Vector3, hitPosition: Vector3)
newRemoteEvent("UpdateStats") -- server -> client: (stats table)
newRemoteEvent("CameraShake") -- server -> client: (intensity: number, duration: number)
newRemoteEvent("RaceUpdate")  -- server -> clients: (race state table)

-- // Collision Groups ---------------------------------------------------
local GROUPS = { "Vehicles", "Zombies", "Obstacles", "Environment", "Projectiles" }

for _, groupName in GROUPS do
	local ok = pcall(function()
		PhysicsService:RegisterCollisionGroup(groupName)
	end)
	if not ok then
		warn(`[Bootstrap] Collision group "{groupName}" already exists, skipping.`)
	end
end

-- Zombies physically collide with vehicles (gives the crush a physical feel)
-- but not with each other or obstacles, to avoid clumping/jitter since we
-- are not doing full pathfinding around scenery.
PhysicsService:CollisionGroupSetCollidable("Vehicles", "Zombies", true)
PhysicsService:CollisionGroupSetCollidable("Vehicles", "Obstacles", true)
PhysicsService:CollisionGroupSetCollidable("Vehicles", "Environment", true)
PhysicsService:CollisionGroupSetCollidable("Zombies", "Zombies", false)
PhysicsService:CollisionGroupSetCollidable("Zombies", "Obstacles", false)
PhysicsService:CollisionGroupSetCollidable("Zombies", "Environment", true)
PhysicsService:CollisionGroupSetCollidable("Projectiles", "Zombies", false) -- hits are raycast, not physical
PhysicsService:CollisionGroupSetCollidable("Projectiles", "Environment", false)

print("[Bootstrap] Remotes created and collision groups configured.")
