# План продвижения — с чего начинать

> Заведён 2026-08-11. Ролики и раскадровки — в `PROMO_SHORTS.md`, здесь каналы,
> тексты и порядок.
>
> Ссылка на игру: `https://www.roblox.com/games/91578422014822/GraveyardRacer`

---

## 0. Что определяет всю стратегию

**Охват игры — `Ages 16+ and trusted friends`.** Младшая аудитория закрыта, пока не
наберутся 500 вовлечённых игроков за 60 дней (разбор — `PUBLISH_CHECKLIST.md`, 1.1a-1).

Отсюда главное: **обычная Roblox-аудитория сейчас нецелевая**. Ребёнок из ленты не
откроет игру, даже перейдя по прямой ссылке. Значит бить надо туда, где люди с большей
вероятностью старше и прошли проверку возраста:

1. **Разработчики Roblox** — почти все взрослые, любят пробовать чужое, дают развёрнутый
   отзыв. Плюс им интересно КАК сделано, а у нас есть что показать.
2. **Взрослые игроки хорроров и гонок** — вне Roblox-площадок.
3. Обычная детская аудитория — **потом**, когда откроется охват.

Это временный перекос, а не навсегда. Но первые 500 придут скорее отсюда.

---

## 1. Что можно сделать СЕГОДНЯ, без съёмки

Материала уже хватает: иконка, превью, скриншоты. Ролики подождут до записи с зомби.

### 1.1 DevForum, раздел Creations Feedback

**Раздел называется именно так** (проверено по форуму 2026-08-11). «Cool Creations» —
устаревшее имя, его переименовали; в первой версии этого плана я ошибся.

Описание раздела: *«This category serves as a showcase for anything on Roblox that you'd
like feedback or discussion on. You can showcase your games, artwork, scripts…»*. Раздел
живой — порядка 57 тем в неделю.

**Проверить перед постом:** есть ли кнопка **New Topic**. Категорию видно всем, а право
создавать тему зависит от уровня на форуме (Visitor / Member / Regular / Leader). Нет
кнопки — идём в 1.2.

**Подача важна: это раздел ОБРАТНОЙ СВЯЗИ, а не витрина.** Просьба о ней должна стоять
вверху, а не в конце, и быть конкретной — три названных вопроса собирают ответы, а общее
«что думаете» не собирает ничего.

Заголовок:

```
Graveyard Racer — a night-graveyard racer with zombies. Looking for feedback on the driving feel
```

Тело:

```
I've just published my first proper experience and I'd like some outside eyes on it,
mainly on how the car feels to drive.

Three laps, three lives, and a graveyard that keeps handing zombies back to the track.
You drive a rust-eaten buggy, run them down for bones, or use the turret bolted to the
roll cage. Lose all three lives and you're out — the race carries on without you.

What I'd most like feedback on:
• Driving feel — it's A-Chassis with tuning, and I genuinely can't tell any more
  whether it's heavy or just sluggish.
• Whether the checkpoint markers read clearly at speed, or you lose track of where
  to go next.
• Mobile: steering and pedals are custom, and the turret auto-aims there. No idea
  how that lands for someone who isn't me.

A few things that might interest people here:
• The checkpoint skulls aren't decals. They're ribbons generated at runtime from the
  original vector outline via EditableMesh, so the line stays smooth at any thickness.
• The glow is bloom, not the material — Neon on its own gives a flat fill. That means
  the halo disappears on low graphics settings, which took me embarrassingly long to
  work out.
• A-Chassis has no touch branch at all, so mobile steering and pedals feed the chassis
  through player attributes.

https://www.roblox.com/games/91578422014822/GraveyardRacer

It's 16+ for now while it earns its audience reach.
```

Картинку приложить: `art/badges/`-стиль не нужен, годится кадр из игры —
`thumbs\thumb_1.jpg`.

Формат, который там читают: не реклама, а рассказ с деталями. Люди голосуют за то, что
интересно сделано.

```
Graveyard Racer — a night-graveyard racer where the dead get in the way

Three laps, three lives, and a graveyard that keeps handing zombies back to the track.
You drive a rust-eaten buggy, run them down for bones, or use the turret bolted to the
roll cage. Lose all three lives and you're out — the race carries on without you.

A few things I ended up building that might be interesting:

• The checkpoint skulls aren't decals. They're ribbons generated at runtime from the
  original vector outline via EditableMesh, so the line stays smooth at any thickness.
• The glow is bloom, not the material — Neon on its own gives a flat fill. That means
  the halo disappears on low graphics settings, which took me embarrassingly long to
  work out.
• A-Chassis has no touch branch at all, so mobile steering and pedals feed the chassis
  through player attributes.

Link: https://www.roblox.com/games/91578422014822/GraveyardRacer

It's 16+ for now while it earns its audience reach. Feedback very welcome, especially
on the driving feel — that's the part I'm least sure about.
```

**Почему так написано:** три конкретные технические детали вместо общих слов. На
DevForum это валюта — по таким постам отвечают, по рекламным проходят мимо. Признание
про блюм добавлено намеренно: честность про собственные грабли читается лучше хвастовства.

### 1.2 r/robloxgamedev — `https://www.reddit.com/r/robloxgamedev/`

**Если DevForum закрыт, начинать отсюда.** Никакого уровня доступа не требует.

Правила самопиара там строгие: голая ссылка улетит в бан. Работает формат «рассказ о
разработке с картинкой».

```
Built a zombie racer in Roblox — the checkpoint markers gave me the most trouble

[картинка: thumb_1.png]

The idea is simple: three laps around a night graveyard, three lives, and the dead
crawling out onto the road. Run them over or shoot them off the turret.

The part that ate my week was the checkpoint markers. I wanted a glowing skull outline,
not a flat sticker. Turned out the glow was never the material — Neon just draws a flat
bright fill. The halo comes entirely from BloomEffect, which also means it vanishes for
anyone playing on low graphics settings. I only found that out when a friend told me
"there's no glow on my machine".

Ended up generating the outline as a ribbon mesh at runtime from the original vector,
so the line stays clean at any thickness.

Happy to answer anything about how it's put together.
```

**ССЫЛКИ В ПОСТЕ НЕТ ВООБЩЕ** — уточнено 2026-08-11 по правилам сабреддита. Правило №4
там звучит как «Direct Advertisements Are Not Allowed», и при такой формулировке даже
ссылка первым комментарием может быть прочитана как реклама. Прежний совет «дать ссылку
первым комментарием» был рискованный.

Пост — честный рассказ о разработке, и всё. Спросят «где поиграть» — дать в ответе.
Выживший пост с обсуждением ценнее удалённого со ссылкой.

**Flair обязателен** (звёздочка в форме). Брать `Creations` / `Show Off` / `Devlog`, но
НЕ `Help` — иначе придут помогать с кодом вместо обсуждения.

**Свежий аккаунт — отдельный риск.** Многие сабреддиты автоматически прячут посты от
аккаунтов без кармы. Пост не появился в ленте — почти наверняка дело в этом, а не в
тексте.

### 1.3 Discord-серверы разработчиков

В большинстве крупных серверов есть канал вроде `#showcase` или `#self-promo`. Короткий
формат:

```
Made a night-graveyard racer — three laps, three lives, zombies on the track.
Turret on the roll cage, bones as currency. 16+ for now while it earns reach.
https://www.roblox.com/games/91578422014822/GraveyardRacer
```

**Только там, где самопиар разрешён каналом.** Рассылка в личку и в чужие общие каналы
— быстрый способ получить бан и репутацию, которая потом мешает.

---

## 2. Когда появится запись с зомби

Тогда включаются ролики из `PROMO_SHORTS.md`: четыре вертикальных под TikTok и Shorts
плюс горизонтальный на витрину.

Порядок: сперва **витринный** (он работает на всех, кто уже дошёл до страницы), потом
вертикальные по одному в день.

---

## 3. Чего НЕ делать

- **Накрутка** — просмотры, лайки, фальшивые отзывы, боты. Roblox считает вовлечённых
  игроков по возрасту аккаунта, истории игр и тратам именно чтобы это отсеять: накрутка
  не приблизит те 500, а рискует игрой.
- **Рассылка в личку и в чужие каналы без разрешения.**
- **Обещать то, чего в игре нет.** Сейчас есть три круга, три жизни, турель, кости и
  магазин — этого достаточно, чтобы показать честно.

---

## 4. Что мерить

- **Impressions и Qualified Play Through Rate** во вкладке Thumbnail performance — там
  видно, кликают ли по карточке. Плохой CTR лечится превью, а не количеством постов.
- **Highly engaged players** — счётчик до 500. Это единственная цифра, которая реально
  меняет положение игры.
- **Average Session Time** — если люди заходят и уходят за минуту, проблема не в
  продвижении, а в игре, и тогда надо чинить её, а не постить больше.

Последний пункт важнее остальных: продвижение приводит людей ОДИН раз. Останутся они
или нет, решает игра.
