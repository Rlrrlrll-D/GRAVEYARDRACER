# Проверка на вредоносное содержимое — 2026-08-11

> Повод: сторонние ассеты из Toolbox известны бэкдорами (`require(<id>)` тянет чужой
> код уже после вставки модели). В игре есть код, которого нет в репозитории:
> A-Chassis и `Animate` зомби живут только в `.rbxl`.

---

## 1. Итог: бэкдоров нет

Просканированы **все 73 скрипта** места. Обход шёл по всему дереву (`game:GetDescendants`),
а не по списку сервисов, — полный обход дал те же 73, то есть скриптов в неожиданных
местах нет. В репозитории 57; разница в 16 — это `ServerStorage.VehicleTemplate`
(A-Chassis авторства SecondLogic @ Inspare) и `ZombieTemplate.Animate`.

| Признак | Совпадений |
|---|---|
| `require(<числовой id>)` | 0 |
| `loadstring` / `getfenv` / `setfenv` | 0 |
| Обфускация: `\x`-escape, цепочки `string.char` | 0 |
| `HttpService`, `HttpGet` / `HttpPost` | 0 |
| `InsertService`, `GetObjects` | 0 |

`DataStoreService` и `MarketplaceService` встречаются только в своих скриптах
(`PlayerData`, `ShopService`, `ShopUI`).

Три выключенных скрипта в `VehicleTemplate` — штатные FE-обработчики A-Chassis;
README A-Chassis (строка 209) описывает этот приём, `Initialize:439` включает их
после инициализации.

**Не проверялось:** ID звуков, мешей и картинок — кода они не исполняют. Побайтовое
совпадение `Drive` с официальным релизом A-Chassis не сверялось — не с чем, но по
признакам он чист.

### 1.1 Плагины Studio — их нет вовсе

Проверено 2026-08-11. Это более опасный вектор, чем ассеты: модель исполняет код только
в игре, а плагин работает в редакторе с полными правами и может дописать что угодно
прямо в место, между сохранениями.

| Что смотрел | Результат |
|---|---|
| `PluginsDir` в `GlobalSettings_13.xml` | `%LOCALAPPDATA%\Roblox\Plugins` — путь по умолчанию, не переопределён |
| Содержимое этой папки | **0 объектов** |
| `.rbxm` / `.rbxmx` в остальном профиле | ни одного вне поставки Roblox |
| `LoadInternalPlugins` | `false` |

Всё найденное на диске лежит в `BuiltInStandalonePlugins`, `StudioContent` и
`ExtraContent` внутри папок версий — поставка самого Roblox.

MCP-мост, через который идёт работа со Studio, отдельным плагином НЕ ставится: вызовы
исполняет встроенный `Assistant.rbxm` (видно по путям в его ошибках,
`sabuiltin_Assistant.rbxm.Assistant…Tools.ExecuteLuauTool`). Поэтому папка плагинов и
осталась пустой.

**Правило на будущее:** после установки любого плагина прогнать место этим же сканом.
Эталон — 73 скрипта; новые в дереве видно сразу.

---

## 2. Что нашлось: дыра в ремоутах A-Chassis

Не бэкдор — кражи данных и выполнения чужого кода нет. Но возможность гадить была
настоящая, и она закрыта 2026-08-11.

Оба клиент→сервер канала игры принадлежали A-Chassis и принимали что угодно без
проверок. Ремоуты лежат внутри машины в `Workspace`, то есть доступны **любому**
клиенту, а не только водителю. Через `newSound` игрок мог создать на сервере звук с
произвольным `SoundId`, произвольной громкостью, зациклённый и прикреплённый к любому
объекту игры — слышный всем. Ограничения Roblox на чужое аудио тут не помогают: взять
можно ID звука из самой игры.

Легальных вызовов всего четыре (`script_grep` по `FireServer`), и имя звука всегда `Rev`:

```
Smoke [FE+]:56       handler:FireServer("UpdateSmoke", slipOf(RL), slipOf(RR))
AC6_Stock_Sound:33   handler:FireServer("newSound","Rev",car.DriveSeat,script.Rev.SoundId,0,script.Rev.Volume,true)
AC6_Stock_Sound:34   handler:FireServer("playSound","Rev")
AC6_Stock_Sound:41   handler:FireServer("updateSound","Rev",script.Rev.SoundId,pitch,script.Rev.Volume)
```

Фактические значения, по которым выставлены зажимы: `Rev` — громкость 0.35, зациклён;
`SQ` — громкость считается как `Rate/50`, а `Rate` клиент сам режет по `SLIP_MAX = 50`.

### Как починено

Двумя слоями, потому что одной проверки владельца не хватает.

1. **Право голоса.** Пока в машине есть водитель, команды принимаются только от него.
   Пустая машина не проверяется намеренно: первый `newSound` прилетает в момент посадки
   и мог бы опередить появление седока на сервере — тогда мотор молчал бы весь заезд.
2. **Ограничение возможностей.** Даже принятая команда не может лишнего: родитель звука
   всегда `DriveSeat` этой машины, `SoundId` — только из тех, что уже лежат в самой
   машине, громкость и высота зажаты, имя сверяется со списком. Поэтому захват пустой
   машины не даёт ничего, кроме как переиграть её собственный мотор.

Попутно убран отладочный `print(parent)`, висевший в стоке на `AncestryChanged`, и
устаревшее `Sound.Pitch` заменено на `PlaybackSpeed`.

---

## 3. Оригиналы для отката

`VehicleTemplate` живёт в `.rbxl` и в git не попадает, поэтому сток сохранён здесь
дословно. Чтобы откатиться — вернуть эти тексты в те же два скрипта.

### `ServerStorage.VehicleTemplate.A-Chassis Tune.Plugins.AC6_Stock_Sound.AC6_FE_Sounds.Handler`

```lua
local Sounds = {}
local F = {}

F.newSound = function(name,par,id,pitch,volume,loop)
	for i,v in pairs(Sounds) do
		if i==name then
			v:Stop()
			v:Destroy()
		end
	end
	local sn = Instance.new("Sound",par)
	sn.Name = name
	sn.SoundId = id
	sn.Pitch = pitch
	sn.Volume = volume
	sn.Looped = loop
	sn.AncestryChanged:connect(function(child,parent) print(parent) end)
	Sounds[name]=sn
end

F.updateSound = function(sound,id,pit,vol)
	local sn = Sounds[sound]
	if id~=sn.SoundId then sn.SoundId = id end
	if pit~=sn.Pitch then sn.Pitch = pit end
	if vol~=sn.Volume then sn.Volume = vol end
end

F.playSound = function(sound)
	Sounds[sound]:Play()
end

F.pauseSound = function(sound)
	Sounds[sound]:Pause()
end

F.stopSound = function(sound)
	Sounds[sound]:Stop()
end

F.removeSound = function(sound)
	Sounds[sound]:Stop()
	Sounds[sound]:Destroy()
	Sounds[sound]=nil
end

script.Parent.OnServerEvent:connect(function(pl,Fnc,...)
	F[Fnc](...)
end)
```

### `ServerStorage.VehicleTemplate.A-Chassis Tune.Plugins.Smoke [FE+].Smoke_FE.Handler`

```lua
local car = script.Parent.Parent
local F = {}

F.UpdateSmoke = function(rl,rr)
	car.Wheels.RL.Smoke.Rate = rl
	car.Wheels.RR.Smoke.Rate = rr
	car.Wheels.RL.SQ.Volume = rl/50
	car.Wheels.RR.SQ.Volume = rr/50
end

script.Parent.OnServerEvent:connect(function(pl,Fnc,...)
	F[Fnc](...)
end)

car.DriveSeat.ChildRemoved:connect(function(child)
	if child.Name=="SeatWeld" then
		car.Wheels.RL.SQ:Stop()
		car.Wheels.RR.SQ:Stop()
		car.Wheels.RL.Smoke.Rate=0
		car.Wheels.RR.Smoke.Rate=0
	end
end)

for i,v in pairs(car.Wheels:GetChildren()) do
	if v.Name=="RL" or v.Name=="RR" or v.Name=="R" then
		local sq = script.Parent.SQ:Clone()
		sq.Parent=v
		local sm = script.Parent.Smoke:Clone()
		sm.Parent=v
	end
end
```

---

## 4. Что проверить плей-тестом

Правки лежат в шаблоне машины, а он собирается только в игре. После заезда убедиться:

- мотор звучит и меняет тон с оборотами (это `newSound` + `updateSound`);
- при пробуксовке идёт дым из-под задних колёс и слышен визг;
- при высадке водителя визг глохнет, дым прекращается;
- в Output нет ошибок от `Handler`.
