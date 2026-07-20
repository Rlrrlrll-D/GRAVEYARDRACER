# PLAN.md — Сборка Graveyard Racer через Roblox Studio MCP

Ты — Claude Code, подключённый к Roblox Studio через MCP-сервер
(инструменты `run_code` / `insert_model`). Твоя задача — внедрить в
**уже существующий** плейс систему игры Graveyard Racer.

**Критично: проект НЕ пустой.** В нём уже есть объекты, модели и,
возможно, скрипты из прошлых сессий. Ничего не удалять и не перезаписывать
без проверки. Сначала аудит, потом адаптация, потом установка.

Все исходники скриптов лежат рядом с этим файлом в папке `GraveyardRacer/`
— читай код оттуда, не сочиняй свой.

---

## Этап 0. Аудит существующего плейса

Через `run_code` собери и выведи инвентарь:

```lua
-- 1. Скрипты: перечисли все Script/LocalScript/ModuleScript в
--    ServerScriptService, ReplicatedStorage, StarterPlayerScripts
--    (имя, класс, полный путь).
-- 2. Теги: game:GetService("CollectionService"):GetAllTags() и число
--    объектов на каждом теге.
-- 3. Кандидаты в машины: модели с VehicleSeat внутри (путь, имя сиденья,
--    есть ли TurretBase/Turret/Muzzle).
-- 4. Кандидаты в декор: модели/парты, в именах которых есть
--    grave/tomb/stone/cross/tree/lamp/light/могил/надгроб (без учёта регистра).
-- 5. ServerStorage: есть ли ZombieTemplate, MapTemplates.
-- 6. Lighting: ClockTime, наличие Atmosphere/Sky/ColorCorrection/Bloom.
-- 7. Terrain: есть ли нарисованный рельеф (Terrain:GetRegion не нужен,
--    достаточно понять, пуст ли Terrain визуально — проверь
--    workspace.Terrain:CalculateВoxels недоступно, поэтому просто отметь
--    наличие Baseplate и спроси пользователя, если неясно).
```

**Останови работу и покажи пользователю сводку аудита** с вопросами,
если обнаружены конфликты (например: уже есть скрипт с именем
`VehicleController`, уже есть тег `Hazard` на 12 объектах, уже есть машина).
Действуй дальше только после подтверждения.

## Правила адаптации: MapLayout — единственный источник истины по координатам

Баланс игры закодирован в координатах `MapLayout` (кластеры могил вокруг
Hazard-зон, штраф скорости → зомби догоняют). Поэтому:

1. **Расстановка декора — только программная, через MapBuilder.**
   Существующие вручную расставленные надгробия, могилы, фонари и деревья,
   стоящие НЕ по координатам MapLayout, подлежат удалению и перестановке.

2. **Не удалять безвозвратно — переносить в бэкап.** Перед перестановкой
   создай в ServerStorage папку `_ManualBackup_<дата>` и перемести туда
   все ручные объекты декора (Parent = папка бэкапа). Так пользователь
   сможет откатиться или забрать оттуда модели.

3. **Сохранить визуал, заменить координаты.** Если ручные модели выглядят
   лучше заглушек ModelFactory — возьми по одному лучшему экземпляру
   каждого типа (надгробие, могила, фонарь, дерево) и помести в
   `ServerStorage/MapTemplates` под именами `Tombstone`, `GraveMarker`,
   `Lamp`, `DeadTree`. MapBuilder тогда расставит ИМЕННО их, но по
   правильным координатам. Спроси пользователя, какие модели считать
   эталонными, если кандидатов несколько.

4. **Допуск на совпадение.** Если ручной объект уже стоит в пределах
   ~6 studs от координаты из MapLayout — его можно не трогать, а просто
   навесить нужный тег (Hazard/Grave/FlickerLight) и исключить эту
   координату из работы MapBuilder, чтобы не было дубля.

5. **Что НЕ подпадает под снос:** машина игрока, ZombieTemplate, Terrain,
   ограда по периметру, крупные ориентиры (мавзолей/часовня/ворота — их
   при расхождении с MapLayout.Landmarks предложи передвинуть, но реши
   с пользователем), а также любые объекты, не относящиеся к декору
   трассы (спавны игроков, тестовые объекты и т.п.).

6. **Существующие скрипты с совпадающими именами** — не перезаписывать
   молча: показать пользователю, что за скрипт там сейчас, и спросить,
   заменить или переименовать.

7. **Lighting**: если пользователь уже настраивал атмосферу — спросить,
   применять ли AtmosphereSetup или оставить его настройки.

## Этап 1. Модули в ReplicatedStorage

Создай ModuleScript'ы (через `run_code`: `Instance.new("ModuleScript")`,
свойство `Source` = содержимое файла, `Parent` = ReplicatedStorage):

| Имя | Файл |
|---|---|
| GameConfig | GraveyardRacer/ReplicatedStorage/GameConfig.lua |
| VehicleRegistry | GraveyardRacer/ReplicatedStorage/VehicleRegistry.lua |
| EnvironmentConfig | GraveyardRacer/ReplicatedStorage/EnvironmentConfig.lua |
| MapLayout | GraveyardRacer/ReplicatedStorage/MapLayout.lua |

Проверка: `require` каждого модуля через run_code не должен падать.

## Этап 2. Серверные скрипты в ServerScriptService

Сначала ModuleScript'ы: `ZombieAI`, `ModelFactory`.
Затем Script'ы (класс Script, RunContext по умолчанию):
`Bootstrap`, `VehicleController`, `ZombieSpawner`, `WeaponServer`,
`HazardManager`, `StatsService`, `AtmosphereSetup` (если согласовано),
`GraveyardAmbience`, `FlickerLight`, `MapBuilder` (если согласовано),
`BuildTemplates` (в адаптированном виде по правилам выше).

Источники — одноимённые файлы `GraveyardRacer/ServerScriptService/*.lua`.

## Этап 3. Клиентские скрипты

В StarterPlayer.StarterPlayerScripts создай LocalScript'ы:
`TurretAimClient`, `UIController`
(файлы из GraveyardRacer/StarterPlayerScripts/).

## Этап 4. Перестановка декора по MapLayout и объекты

Порядок строгий:

1. **Бэкап**: перемести весь ручной декор трассы (надгробия, могилы,
   фонари, деревья не по координатам MapLayout) в
   `ServerStorage/_ManualBackup_<дата>`.
2. **Эталоны**: лучшие ручные модели каждого типа → `ServerStorage/MapTemplates`
   под именами Tombstone / GraveMarker / Lamp / DeadTree (согласуй выбор
   с пользователем). Чего не хватает — создаст ModelFactory.
3. **Расстановка**: убедись, что MapBuilder установлен, и выполни его
   логику (или запусти Play) — объекты встанут по координатам MapLayout
   с рейкастом на землю и получат теги Hazard/Grave/FlickerLight
   автоматически.
4. Если машины нет — построй через ModelFactory.Buggy() + тег PlayerVehicle
   + секция управления колёсами из BuildTemplates. Если машина есть —
   проверь наличие DriveSeat/TurretBase/Turret/TurretHinge/Muzzle и
   дострой недостающее, согласовав с пользователем.
5. Если нет ZombieTemplate в ServerStorage — сообщи пользователю: нужен
   риг с Humanoid + HumanoidRootPart (можно R15 Dummy через Rig Builder,
   это ручной шаг) ИЛИ предложи временно собрать примитивного зомби кодом.
6. Финальная сверка: число объектов с тегом Hazard = числу записей в
   MapLayout.Hazards (и так же для Graves/Lamps). Дубликаты — в бэкап.

## Этап 5. Верификация (обязательно)

Через `run_code` проверь и выведи чек-лист:

- [ ] ReplicatedStorage.Remotes существует и содержит 4 RemoteEvent
      (появляется после первого запуска Bootstrap — если Remotes нет,
      запусти игру или выполни логику Bootstrap напрямую)
- [ ] Все 4 модуля в ReplicatedStorage require-ятся без ошибок
- [ ] Теги: PlayerVehicle ≥ 1; число Hazard/Grave/FlickerLight-объектов
      совпадает с числом записей в MapLayout (Hazards/Graves/Lamps),
      позиции — в пределах ~6 studs от координат MapLayout × Scale
- [ ] Ручной декор не остался на трассе — всё лишнее в _ManualBackup_
- [ ] У машины: DriveSeat (VehicleSeat), TurretBase, Turret,
      TurretHinge (ActuatorType = Servo), Muzzle (Attachment), PrimaryPart
- [ ] ServerStorage.ZombieTemplate существует, внутри Humanoid + HumanoidRootPart
- [ ] В Output нет красных ошибок от наших скриптов

Затем попроси пользователя нажать Play и проверить руками:
HUD появляется при посадке, турель крутится за мышью, выстрел рисует
трассер, зомби вылезает из могилы и бежит к машине, таран на скорости
убивает зомби, удар о надгобие трясёт камеру и режет скорость.

## Этап 6. Blender: меши моделей (через blender-mcp)

Выполняется, только если подключён второй MCP-сервер — BlenderMCP.
Если его нет — пропусти этап, игра полноценно работает на моделях
ModelFactory. Стиль всех моделей: стилизованный low-poly, flat shading,
без текстур (только материалы-цвета) — под ретро-эстетику.

**Конвенции (обязательно):**
- Масштаб: 1 unit Blender = 1 stud. Перед экспортом Apply All Transforms.
- Pivot (origin) каждой модели — в центре подошвы (нижней грани), потому
  что MapBuilder ставит модели на землю рейкастом от подошвы.
- Экспорт: FBX, по одному файлу на модель, в папку `GraveyardRacer/meshes/`.
- Полигонаж: декор ≤ 800 трис, машина ≤ 4000, зомби ≤ 6000.

**6.1 Декор (в порядке приоритета):**
| Модель | Размер (studs) | Ключевые детали |
|---|---|---|
| Tombstone_A | ~3×4×1.2 | плита со скруглённым верхом, фаска Bevel, лёгкий наклон 3–7°, щербины (Displace/ручные вырезы) |
| Tombstone_B | ~2.5×5×1 | обелиск/крест — вариант для разнообразия |
| GraveMarker | ~4×1×7 | земляной холмик (Subdivide+Randomize) + покосившийся деревянный крест |
| Lamp | ~1.5×10×1.5 | кованый столб с завитком-кронштейном, плафон-клетка, отдельный материал Emission для лампы |
| DeadTree | ~6×14×6 | Skin/Curve-модификатор: изогнутый ствол, 3–5 голых ветвей, без листвы |
| Mausoleum | ~18×14×13 | портик с 2 колоннами, двускатная крыша, углублённый чёрный проём |
| Chapel | ~10×16×8 | башенка со шпилем, стрельчатое окно |
| StartGate | ~14×12×2 | кованая арка с пиками, столбы-тумбы |

**6.2 Машина (визуальный корпус):**
- Смоделируй корпус багги (~6×3×10) в стиле «ржавый кладбищенский
  хот-род»: капот, крылья, каркас безопасности. БЕЗ колёс и БЕЗ турели.
- В Studio корпус вешается как MeshPart поверх функционального
  Chassis из ModelFactory (weld), физика остаётся на part-схеме:
  колёса-цилиндры и констрейнты не трогать. Турель также остаётся
  part-based (TurretBase/Turret/Muzzle — их имена завязаны на скрипты).

**6.3 Зомби:**
Два пути, выбрать с пользователем:
- **Путь А (надёжный, рекомендую):** смоделировать 15 отдельных мешей
  частей тела под R15 (Head, UpperTorso, LowerTorso, L/R UpperArm,
  LowerArm, Hand, L/R UpperLeg, LowerLeg, Foot) и в Studio заменить
  ими части стандартного R15 Dummy (через свойство MeshId соразмерных
  MeshPart). Скелет, Motor6D и анимации остаются родными Roblox —
  ZombieAI и AttackAnimation работают без изменений.
- **Путь Б (продвинутый):** полноценный skinned mesh с арматурой
  (кости с R15-именованием), экспорт FBX с ригом, импорт через
  Avatar Setup. Красивее (бесшовное тело), но капризнее: если
  импорт рига даст ошибки — откатиться на путь А.
- Внешность: рваная одежда, серо-зелёная кожа, впалые глаза — 2–3
  цветовых варианта материалов для разнообразия толпы.

**6.4 Интеграция в Studio:**
1. Пользователь импортирует FBX-файлы через Avatar/Import 3D
   (этот клик — ручной, MCP его не делает) в папку workspace или
   сразу в ServerStorage.
2. Через roblox-mcp: перемести импортированные меши в
   `ServerStorage/MapTemplates` под каноничными именами (Tombstone,
   GraveMarker, Lamp, DeadTree), Tombstone_B добавь как альтернативу —
   MapBuilder можно доработать на случайный выбор из вариантов.
3. Собранного мешевого зомби помести как `ServerStorage/ZombieTemplate`
   (старый шаблон — в _ManualBackup_). Проверь: Humanoid,
   HumanoidRootPart, части не Anchored.
4. Корпус машины: weld к Chassis существующего багги, прежний
   part-декор корпуса (Hood) — Transparency = 1 или в бэкап.
5. Запусти верификацию Этапа 5 заново.

## Известные точки подгонки (не баги)

- Part-based багги может требовать тюнинга: MotorMaxTorque, WHEEL_SPEED,
  масса шасси, размер колёс — крутить по ощущениям на конкретном рельефе.
- В GraveyardAmbience звуки — заглушки `rbxassetid://0`; пользователь
  должен подставить свои ID (чужие старые ID дают ошибку
  "Asset is not approved for the requester").
- Весь баланс — в GameConfig, расстановка — в MapLayout.
