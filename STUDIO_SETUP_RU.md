# Graveyard Racer — Пошаговая инструкция для Roblox Studio

## Шаг 0. Подготовка

1. Откройте **Roblox Studio** → создайте новый проект **Baseplate**.
2. Откройте окно **Explorer** (View → Explorer) и **Properties** (View → Properties) —
   они понадобятся постоянно.
3. Откройте панель **Toolbox** (View → Toolbox) — пригодится для поиска
   готовой модели зомби/машины, если не хотите строить с нуля.

---

## Шаг 1. Вставляем скрипты в правильные места

В Roblox Studio есть три типа скриптов, и важно вставлять именно нужный тип:

| Тип файла | Как вставить в Studio |
|---|---|
| **Script** (обычный серверный) | ПКМ на папке → Insert Object → **Script** |
| **LocalScript** (клиентский) | ПКМ на папке → Insert Object → **LocalScript** |
| **ModuleScript** | ПКМ на папке → Insert Object → **ModuleScript** |

Порядок действий:

### 1.1 ReplicatedStorage
1. В Explorer найдите **ReplicatedStorage**.
2. ПКМ → Insert Object → **ModuleScript** → переименуйте в `GameConfig`.
3. Откройте его двойным кликом (откроется редактор кода) → удалите содержимое
   по умолчанию → вставьте код из файла `GameConfig.lua`.
4. Повторите то же самое: ещё один ModuleScript `VehicleRegistry` →
   вставьте код из `VehicleRegistry.lua`.

### 1.2 ServerScriptService
Найдите **ServerScriptService** в Explorer. Вставляйте туда:
- **Script** `Bootstrap` → код из `Bootstrap.server.lua`
- **Script** `VehicleController` → код из `VehicleController.server.lua`
- **ModuleScript** `ZombieAI` → код из `ZombieAI.lua`
- **Script** `ZombieSpawner` → код из `ZombieSpawner.server.lua`
- **Script** `WeaponServer` → код из `WeaponServer.server.lua`
- **Script** `HazardManager` → код из `HazardManager.server.lua`
- **Script** `StatsService` → код из `StatsService.server.lua`

> ⚠️ Названия скриптов (Name в Properties) должны совпадать в точности
> с указанными — некоторые скрипты обращаются друг к другу по имени
> (например, `ZombieSpawner` делает `require(script.Parent:WaitForChild("ZombieAI"))`,
> так что `ZombieAI` обязательно должен лежать **рядом** с `ZombieSpawner`
> в ServerScriptService).

### 1.3 StarterPlayer → StarterPlayerScripts
1. В Explorer раскройте **StarterPlayer**.
2. Внутри найдите (или создайте) папку **StarterPlayerScripts**.
3. Вставьте туда:
   - **LocalScript** `TurretAimClient` → код из `TurretAimClient.client.lua`
   - **LocalScript** `UIController` → код из `UIController.client.lua`

На этом весь код на месте. Дальше — сборка мира.

---

## Шаг 2. Строим машину

### 2.1 Базовая модель
Самый быстрый способ — взять готовую машину:
1. В **Toolbox** введите в поиск `car` или `buggy`, выберите модель,
   перетащите в Workspace.
2. Либо соберите вручную из Part'ов (Insert → Part) и объедините в **Model**
   (выделите все части → ПКМ → Group, либо через Model tab → Group).

### 2.2 Обязательные части модели
Внутри Model машины должны быть:

**DriveSeat** — сиденье водителя:
1. Insert Object → **VehicleSeat** внутри модели машины.
2. В Properties переименуйте в `DriveSeat`.
3. Расположите его как сиденье (обычно сверху корпуса).

**TurretBase** — основание турели:
1. Insert → **Part**, переименуйте в `TurretBase`.
2. Приварите (Weld) к корпусу машины — выделите TurretBase + корпус →
   вкладка **Model** → **Weld** (или добавьте `WeldConstraint` вручную).
3. Расположите сверху машины.

**Turret** — сама вращающаяся часть турели:
1. Insert → **Part**, переименуйте в `Turret`.
2. Поставьте прямо над TurretBase (по центру).

**Соединяем Turret и TurretBase через HingeConstraint:**
1. Вкладка **Model** → **Constraints** → **Hinge Constraint**.
2. Кликните сначала на TurretBase, затем на Turret — Studio создаст
   `HingeConstraint` (обычно внутри TurretBase или отдельным объектом
   в Workspace/модели).
3. Выделите созданный HingeConstraint → в Properties переименуйте в
   `TurretHinge`.
4. **Важно** — убедитесь, что HingeConstraint лежит именно как **потомок
   TurretBase** (если Studio создала его в другом месте — перетащите в
   Explorer внутрь TurretBase).
5. В Properties HingeConstraint выставьте:
   - `ActuatorType` → **Servo** (без этого TargetAngle не будет работать!)
   - `ServoMaxTorque` → например `50000`
   - `AngularVelocity` → например `4`

**Muzzle** — точка вылета пуль:
1. Внутри Turret вставьте **Attachment** (Insert Object → Attachment).
2. Переименуйте в `Muzzle`.
3. Сдвиньте его (через Move-инструмент или Properties → Position) чуть
   вперёд от дула турели.

### 2.3 Финальные настройки модели машины
1. Выделите всю модель машины → в Properties (или ПКМ → Set as
   PrimaryPart для нужной части) убедитесь, что **PrimaryPart** установлен
   (обычно корпус/шасси).
2. Дайте модели понятное имя, например `GraveyardBuggy`.
3. **Ставим тег**: выделите модель машины → вкладка **Model** →
   **Tag Editor** → в поле впишите `PlayerVehicle` → нажмите **+ Add**.
   (Если кнопки Tag Editor нет на панели — включите её через
   View → плагин "Tag Editor" есть в стандартной поставке Studio.)

Повторите Шаг 2 для каждой машины, которую хотите разместить на карте.

---

## Шаг 3. Зомби

1. Найдите в Toolbox готовую модель зомби (поиск `zombie`) **или**
   вставьте обычный **R15 Dummy**: Avatar tab → Rig Builder → R15 → OK.
2. Убедитесь, что внутри модели есть `Humanoid` и `HumanoidRootPart`
   (у Rig Builder они уже есть по умолчанию).
3. Переименуйте модель зомби в **`ZombieTemplate`**.
4. Перетащите её в Explorer внутрь **ServerStorage** (не Workspace! —
   это шаблон, который скрипт будет клонировать).
5. *(Необязательно)* Добавьте анимацию атаки: Insert Object → **Animation**
   внутрь ZombieTemplate → переименуйте в `AttackAnimation` → вставьте
   AnimationId в Properties.

---

## Шаг 4. Препятствия (надгробия, деревья)

1. Разместите Part'ы или модели надгробий/деревьев на карте (Toolbox →
   поиск `tombstone`, `dead tree`, либо свои модели).
2. Для каждого препятствия: выделите → вкладка **Model** → **Tag Editor** →
   впишите `Hazard` → **+ Add**.
3. *(Необязательно)* Чтобы задать индивидуальную силу замедления/урона —
   в Properties выделенного препятствия добавьте **Attributes**
   (иконка `+` рядом с Attributes в Properties):
   - `SpeedPenalty` (Number, например `0.1`)
   - `Damage` (Number, например `20`)

---

## Шаг 5. Проверка перед запуском

Чек-лист:
- [ ] `GameConfig` и `VehicleRegistry` — в ReplicatedStorage, тип ModuleScript
- [ ] 6 серверных файлов — в ServerScriptService (5 Script + 1 ModuleScript `ZombieAI`)
- [ ] 2 LocalScript — в StarterPlayer → StarterPlayerScripts
- [ ] У машины есть DriveSeat, TurretBase, Turret (с HingeConstraint
      `TurretHinge`, ActuatorType = Servo), Muzzle, PrimaryPart, тег `PlayerVehicle`
- [ ] `ZombieTemplate` лежит в ServerStorage (не в Workspace)
- [ ] Надгробия/деревья помечены тегом `Hazard`

---

## Шаг 6. Тестирование

1. Вкладка **Test** → рядом с кнопкой Play есть выпадающий список
   **Clients** — выставьте **2** (чтобы проверить мультиплеер и то, что
   турель/HUD у каждого игрока свои).
2. Нажмите **Start** (запустит сервер + 2 клиентских окна).
3. Сядьте в машину (клик по VehicleSeat) → должен появиться HUD
   (здоровье/скорость/счётчик зомби) в левом верхнем углу.
4. Подвигайте мышью — турель должна поворачиваться.
5. ЛКМ / тап — стрельба, должны появляться трассеры.
6. Проедьте на низкой скорости в зомби — машина должна получить урон
   и заглохнуть. Разгонитесь и наедьте снова — зомби должен погибнуть.
7. Врежьтесь в надгробие — экран должен затрястись, скорость упасть.

---

## Частые проблемы

| Проблема | Причина |
|---|---|
| Турель не двигается | `ActuatorType` HingeConstraint не выставлен в **Servo** |
| Ошибка `WaitForChild("DriveSeat")` | VehicleSeat назван не точно `DriveSeat` (с учётом регистра) |
| Зомби не спавнятся | `ZombieTemplate` лежит не в `ServerStorage`, либо у него нет Humanoid |
| Зомби не двигаются | Отсутствует `HumanoidRootPart` в модели зомби |
| HUD не появляется | LocalScript'ы вставлены не в `StarterPlayerScripts`, а например прямо в StarterPlayer |
| Стрельба не работает | `Muzzle` — не Attachment, либо назван иначе |
| Машина не тегируется как `PlayerVehicle` | Tag Editor применён к отдельной части, а не ко всей Model |

Если что-то не заработает с первого раза — это нормально для такого объёма
ручной сборки в Studio. Могу помочь разобрать конкретную ошибку, если
пришлёте текст из окна **Output** в Studio.
