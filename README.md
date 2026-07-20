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
