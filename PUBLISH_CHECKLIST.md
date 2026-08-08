# Чек-лист публикации — Graveyard Racer

> Заведён 2026-08-07. Вселенная `10439035420`, место `91578422014822`.
> Здесь только то, что осталось СДЕЛАТЬ, и то, что уже проверено и трогать не нужно.
> Кодом эти вещи не ставятся: почти всё живёт в Game Settings и на Creator Dashboard.

---

## 1. Настройки места — руками в Studio

### 1.1 Размер сервера — СДЕЛАНО 2026-08-08

Поставлено **8** на Creator Dashboard (Configure → Places → место → Server Size).
Из скрипта не пишется — `Players.MaxPlayers` read-only, это настройка места.

Было 60 при восьми местах на стартовой решётке (`PlayerFlow.MaxSlots = 8`): на полном
сервере 52 человека сидели бы в лобби и ждали заезда, в который их не возьмут —
`runCountdown` обрезает список участников по `MaxSlots`, лишние остаются смотреть.

Проверять только в СВЕЖЕЙ сессии Studio: настройки места читаются при открытии, и уже
открытый Studio продолжает показывать старое значение (`Players.MaxPlayers`).

Почему именно 8, а не больше: при восьми каждый, кто зашёл, гарантированно едет.
Матчмейкинг разведёт людей по мелким серверам, где заезд собирается из трёх готовых,
вместо одного сервера с толпой зрителей. Захочешь зрителей — поднимай вместе с
`PlayerFlow.MaxSlots` и решёткой, а не отдельно.

### 1.2 Прочее в Game Settings

| Что | Значение | Где |
|---|---|---|
| ~~Server Size~~ | ~~8~~ — сделано, см. 1.1 | Places → Server Size |
| Genre / жанр | гонки (уточнить по текущему списку Roblox) | Basic Info |
| Возрастной рейтинг | пройти анкету честно: зомби давят машиной и расстреливают из турели — это ненастоящее насилие над фэнтезийными существами | Basic Info → Age Guidelines |
| Allow Copying | **выключено** | Security |
| Third-party sales/teleports | выключено, если не нужно | Security |
| HTTP Requests | сейчас **включён** — я включал его для синка репо→Studio. Игре он не нужен, можно гасить | Security |

Уже стоит правильно, трогать не надо: `StreamingEnabled = true` (без него A-Chassis
рвётся на репликации по частям), `GlobalShadows = true`, гравитация 196.2.

---

## 2. Creator Dashboard

### 2.1 Значки — ждут заведения

Кодом значки создать нельзя. Завести четыре, номера вписать в `Badges.Ids`
(`ServerScriptService/Badges.lua`) — дальше они выдаются сами, менять ничего не надо.
Пока стоит 0, выдача молча пропускается.

| Ключ в коде | Название | Описание |
|---|---|---|
| `first_race` | First Ride | Finish a race for the first time. |
| `first_win` | Gravedigger | Win your first race in the graveyard. |
| `ten_wins` | Known by the Dead | Win ten races. The dead know your name. |
| `hundred_zombies` | Hundred Down | Put a hundred zombies back in the ground. |

### 2.2 Товары — заведены, проверять не нужно

Пропуски и девпродукты уже созданы во вселенной `10439035420` и вписаны в
`ReplicatedStorage/ShopCatalog.lua`: BLOOD RED 75, GHOST 99, DOUBLE BONES 149,
ONE MORE LIFE 25, SACK OF BONES 49. Ненастроенный товар на витрину не попадает,
поэтому лишних плашек не будет.

### 2.3 Иконка и thumbnail'ы

Загрузить не могу — upload картинок из моей сессии отдаёт 401. Нужны от тебя.
Что просят по формату: иконка 512×512, thumbnail'ы 1920×1080.

---

## 3. Текст страницы — черновик

**Название:** Graveyard Racer

**Описание (английское — интерфейс игры английский):**

> Three laps. Three lives. A graveyard that doesn't keep its dead.
>
> Race a rust-eaten buggy through a night cemetery while the dead claw their way out
> of the ground and reach for your wheels. Run them down for bones, or hold the
> trigger and let the turret do the talking. Lose all three lives and you're out —
> the race goes on without you.
>
> • Races for up to 8 drivers, three laps, last one breathing takes it
> • Turret on the roll cage: aim with the mouse, hold to fire
> • Every zombie you put down is bones
> • Spend bones in the shop — skins, an extra life, a sack of bones
> • Fog, bats, and things moving just past the headlights

**Теги:** racing, zombie, horror, survival, cars, spooky, halloween, shooter

Слоган «the dead don't brake» из лобби убран по твоей просьбе — на странице он бы
сработал, но решать тебе.

---

## 4. Что уже проверено кодом и в порядке

- **Накрутка костей через ремоуты невозможна.** `WeaponServer` проверяет типы, режет
  частоту и притягивает присланную точку выстрела к настоящему дулу (подменив её,
  можно было бы выбивать зомби через всю карту). `Economy.spend` сверяет баланс и
  списывает без единого yield — двойная покупка за одну цену исключена. Атрибут
  `Bones` клиент переписать не может: серверные атрибуты с клиента не реплицируются.
- **Сохранения переживают сбой сети.** `PlayerData` ходит в DataStore через `withRetry`
  (4 попытки), держит замок сессии и автосохраняется раз в 150 с.
- **Одиночка не заперт в лобби.** Порог `MinRacers = 3` мягкий: через
  `Race.SoloWaitSeconds = 45` заезд стартует с теми, кто есть.
- **Новичку объясняют игру.** Пять подсказок первого заезда, флаг в записи DataStore.

---

## 5. Чего в плане ещё не касались

Полировка баланса и звука: скорость, три жизни, плотность зомби, громкости.
Это правится в `GameConfig`, но судить на слух и по ощущениям — только плей-тестом.
