# Graveyard Racer — Setup Guide

## 1. Where each script goes (Explorer)

```
ReplicatedStorage
├── GameConfig            (ModuleScript)
└── VehicleRegistry       (ModuleScript)

ServerScriptService
├── Bootstrap             (Script)
├── VehicleController     (Script)
├── ZombieAI              (ModuleScript)
├── ZombieSpawner         (Script)
├── WeaponServer          (Script)
├── HazardManager         (Script)
└── StatsService          (Script)

StarterPlayer
└── StarterPlayerScripts
    ├── TurretAimClient   (LocalScript)
    └── UIController      (LocalScript)
```

`Bootstrap` creates `ReplicatedStorage.Remotes` (a Folder of RemoteEvents) and
the PhysicsService collision groups at server start — you don't need to
create those by hand.

## 2. World setup

**Vehicle** — build or import a buggy/car model into `Workspace`:
- A `VehicleSeat` named **DriveSeat**.
- A `Part` named **TurretBase**, welded to the chassis.
- A `Part` named **Turret**, connected to TurretBase with a **HingeConstraint**
  named `TurretHinge` (`ActuatorType = Servo`, give it a decent
  `ServoMaxTorque` and `AngularVelocity` so it turns smoothly).
- An `Attachment` named **Muzzle** as a child of Turret (marks where bullets
  originate).
- Set the Model's `PrimaryPart`.
- Tag the Model with CollectionService tag **PlayerVehicle**
  (Studio: select it → Model tab → Tag Editor → type `PlayerVehicle` → Add).

You can place multiple vehicles in the world; each is tracked independently.

**Zombie template** — put a Model named **ZombieTemplate** in `ServerStorage`
containing a `Humanoid` + `HumanoidRootPart` (an R15 dummy or a Toolbox
"Zombie" rig both work). Optionally add a child `Animation` named
`AttackAnimation` for the attack pose.

**Hazards** — tag every tombstone / dead tree Part or Model with
CollectionService tag **Hazard**. Optionally set `SpeedPenalty` (0–1) and
`Damage` Attributes on individual hazards to override the defaults in
`GameConfig`.

## 3. Tuning

All gameplay numbers (crush speed threshold, zombie health, weapon damage,
spawn rates, hazard penalties, etc.) live in one place:
`ReplicatedStorage.GameConfig`. Edit that module instead of hunting through
each script.

## 4. How the pieces talk to each other

- Vehicle stats (Health, MaxHealth, Fuel, Speed, SpeedMultiplier, Destroyed)
  are stored as **Attributes** on the vehicle Model — any script can read or
  write them without needing a reference passed around.
- `VehicleRegistry` (ModuleScript) maps Player ↔ vehicle Model, updated
  whenever someone sits in or leaves a DriveSeat.
- `StatsService` polls those attributes 5×/second and fires
  `Remotes.UpdateStats` to each driver, which `UIController` renders.
- `WeaponServer` is authoritative: the client only sends an aim direction,
  the server raycasts, applies damage, then broadcasts `Remotes.BulletFired`
  so every client (including the shooter) can draw a tracer.
- Crushing zombies is handled directly in `VehicleController` via `Touched`
  events, checking the vehicle's current `Speed` attribute against
  `GameConfig.Vehicle.CrushSpeedThreshold`.

## 5. Testing tips

- Test with 2+ Studio clients (Test tab → Clients: 2) since vehicle
  ownership/turret aiming is per-player.
- If the turret doesn't rotate, double check the HingeConstraint's
  `ActuatorType` is set to **Servo** — `TargetAngle` is ignored otherwise.
- If zombies don't move, confirm `ZombieTemplate` has `Humanoid.RootPart`
  correctly linked (Studio usually wires this automatically for R15 rigs).
- `StreamingEnabled`: all scripts use `WaitForChild`/tag-listener patterns
  rather than assuming instances exist at load time, so they're safe with
  StreamingEnabled on.

## 6. Taking screenshots (Photo Mode)

`StarterPlayerScripts.PhotoMode` + `ServerScriptService.PhotoModeService` are a
dev-only pair for shooting teasers / the experience thumbnail. Both bail out
unless `RunService:IsStudio()` (add your UserId to `ALLOWED_USER_IDS` in
`PhotoMode` to use it in the live game).

Shoot in **Play**, never in Edit — local lights (lanterns, headlights) aren't
rendered in Edit and the dusk arc hasn't started.

Press **F4**. Then: RMB + mouse to look, WASD/QE to fly, Shift/Ctrl for ×4/×0.25
speed, scroll for base speed, Z/C roll (X resets), `[`/`]` FOV, **T** autofocus
the depth of field, **F** freeze the world, **G** rule-of-thirds grid,
**B** 2.39:1 letterbox, **U** keep the game HUD in frame, **H** hide the photo UI
*and the mouse cursor*.

**U** exists because a storefront shot often reads better *with* the HUD — lap,
position, lives and the zombie counter explain the game better than scenery does.
The Roblox topbar and the cursor stay hidden either way, and so does the lobby
blur: it blurs the world, not the interface.

**H hides the cursor for a reason**: Roblox draws the pointer inside the frame,
so the Screenshot button captures it along with the scene — and by then you've
released RMB and are moving the mouse toward the ribbon, straight across the shot.

Saving the image is on Studio: the shot itself is the ribbon's **View →
Screenshot**, which captures the bare viewport, never the editor chrome. Game
code can't write the file — `CaptureService:CaptureScreenshot` only yields a
temporary `rbxtemp://` id and `SaveScreenshotCapture` is gated behind the
`RobloxScript` capability. Flow: frame it → **H** → View → Screenshot → click
back into the viewport.

### Resolution

The saved PNG is exactly what the viewport rendered, so resolution is bound only
by viewport size — and the window does **not** have to fit on screen. Enlarging
it past the monitor pushes the ribbon and panels off the edge; the viewport still
renders in full. `tools/photo-window.ps1` sets that size (`-Restore` undoes it).

Careful with the units: Roblox writes the file in **physical** pixels while
`Camera.ViewportSize` reports **logical** ones. At 125% Windows scaling a
1920×1080 viewport lands on disk as **2400×1350** — above Full HD, which is the
good case: downscaling that to 1920×1080 beats rendering at 1080 directly.

Don't use Studio's own freecam (Shift+P) at the same time — both grab the camera.
