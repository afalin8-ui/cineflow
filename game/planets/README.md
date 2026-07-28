# Картинки планет

Планеты в игре — не модели, а **одна картинка на планету**: развёртка
поверхности. Игра сама натягивает её на шар, добавляет свет звезды,
терминатор (границу дня и ночи), атмосферный венец, блик на воде,
слой облаков и огни городов на ночной стороне.

Поэтому генерировать надо **плоскую карту**, а не красивый шарик в
космосе. Шарик игра соберёт лучше — с правильным светом и вращением.

---

## 1. Что именно генерировать

| Карта | Обязательна | Что на ней |
|---|---|---|
| `map` — цвет поверхности | **да** | материки, океаны, пустыни, лёд. Без теней и облаков |
| `clouds` — облака | нет | белые вихри на прозрачном фоне (PNG) |
| `lights` — ночные огни | нет | жёлтые точки городов на чёрном фоне |
| `normal` — рельеф | нет | сиренево-голубая карта нормалей |

Начни с одной `map`. Остальное — когда захочется добавить.
Блики на воде игра вычисляет сама: тёмно-синие участки карты цвета
считаются водой и делаются зеркальными.

### Формат

- **Пропорции 2:1** — ширина ровно вдвое больше высоты (2048×1024 или
  4096×2048). Это «равнопрямоугольная проекция», как школьная карта мира.
- Если генератор не умеет 2:1 — бери самый широкий горизонтальный формат
  (например 1536×1024). Игра растянет сама, материки станут процентов на
  тридцать шире — на глаз почти незаметно.
- JPG или PNG. Облака и огни — обязательно PNG.

---

## 2. Куда положить

Файлы кидай в эту папку (`game/planets/`), затем впиши их в
`manifest.json`:

```json
{
  "planets": {
    "klotho":  { "map": "klotho.jpg", "clouds": "klotho_clouds.png" },
    "green":   { "map": "green.jpg" },
    "desert":  "desert.jpg",
    "ice":     { "map": "ice.jpg", "atmo": "#9fd8ff" },
    "tartarus":{ "map": "tartarus.jpg", "lights": "tartarus_lights.png" }
  }
}
```

Ключ — либо **биом** (одна картинка на все такие миры), либо **имя
конкретной планеты** (только для неё). Имя планеты важнее биома.

**Биомы:** `klotho`, `green`, `desert`, `ice`, `rock`, `city`

**Имена планет:** `prometheus` (Прометей), `klotho` (Клото),
`lachesis` (Лахесис), `atropos` (Атропос), `vespa` (Рудники Веспы),
`erebus` (Эреб), `gate` (Гиперворота), `xanthia` (Ксантия),
`phlegethon` (Флегетон), `styx` (Стикс), `tartarus` (Тартар),
`wolfdelta` (Дельта Волка), `morbelt` (Пояс Мора), `ferrum` (Феррум)

Необязательные поля: `"atmo": "#9fd8ff"` — цвет атмосферного венца,
`"atmoPower": 2.4` — его плотность, `"water": false` — отключить блик
на воде (для безводных миров).

---

## 3. Промты для GPT Image 2

Копируй как есть — английский для картиночных генераторов надёжнее.
В конце каждого промта идёт **технический хвост**: без него генератор
норовит нарисовать красивый шар в космосе вместо карты.

### Технический хвост (добавляется к каждому промту)

```
Equirectangular map projection, 2:1 aspect ratio, full 360x180 degree
coverage. Flat texture map filling the entire frame edge to edge.
Left and right edges must be open ocean so they tile seamlessly.
Uniform featureless polar band along the very top and very bottom edges.
NOT a sphere, NOT a globe, NOT a planet render, no stars, no black space
background, no vignette, no lighting, no shadows, no terminator, no clouds,
no atmosphere glow, no text, no labels, no grid lines, no borders, no frame.
Flat evenly-lit albedo map, orbital satellite imagery, photorealistic,
extremely detailed, 8k.
```

### Клото — родина клана Тройден (`klotho`)

```
Surface texture map of an arid ochre world. Vast tan and dust-yellow
savanna plains, ridged mountain chains casting no shadow, dry cracked
riverbeds, salt flats, scattered shallow turquoise inland seas with pale
sandy shelves, thin olive-green vegetation belts along the coasts,
rust-brown highlands, fine wind-streak patterns across the deserts.
```
*+ технический хвост*

### Зелёный мир — Ксантия (`green`)

```
Surface texture map of an Earth-like habitable world. Deep blue oceans
with pale continental shelves, green forested continents, dark boreal
forest belts, tan desert bands near the tropics, grey-brown mountain
ranges, river deltas, large lakes, white ice caps at the poles.
```
*+ технический хвост*

### Пустынный мир — Эреб, Флегетон, Феррум (`desert`)

```
Surface texture map of a hot desert world. Endless orange and rust-red
sand seas with dune ridge patterns, dark basalt plateaus, enormous canyon
systems, dry impact basins, pale yellow salt pans, iron-oxide streaks,
no water at all, no vegetation.
```
*+ технический хвост*

### Ледяной мир — Прометей, Атропос, Стикс (`ice`)

```
Surface texture map of a frozen world. White and pale blue ice sheets,
cracked pack ice with dark fracture lines, deep teal frozen seas, grey
rock ridges breaking through the ice, glacial flow patterns, snow dunes,
frost-covered highlands, no vegetation.
```
*+ технический хвост*

### Каменный мир — Лахесис, Веспа, Дельта Волка, Пояс Мора (`rock`)

```
Surface texture map of an airless cratered moon-like world. Grey-brown
regolith, thousands of impact craters of all sizes with bright ejecta rays,
dark basalt maria, long rilles and fault scarps, mining scars and pale dust
aprons, no water, no vegetation, no atmosphere.
```
*+ технический хвост* и в манифесте `"water": false`

### Город-планета — Гиперворота, Тартар (`city`)

```
Surface texture map of an ecumenopolis, a world entirely covered by one
city. Dense grey and steel-blue urban sprawl from pole to pole, geometric
megablock districts, glowing arterial highways, industrial zones with
rust and soot staining, dark reservoirs and canals, spaceport clearings,
layered megastructures.
```
*+ технический хвост*

---

## 4. Промты для дополнительных карт

### Облака (`clouds`)

```
Cloud layer texture map. White and light grey cloud formations on a fully
transparent background: spiral cyclones, banded cloud streets, scattered
cumulus fields, thin cirrus wisps. Clouds cover about 45 percent of the
frame, the rest is transparent. No land, no ocean, no colour except white
and grey.
```
*+ технический хвост.* Сохранять **PNG с прозрачностью**. Если генератор
не умеет прозрачность — проси белые облака на **чёрном** фоне, тоже сгодится.

### Ночные огни (`lights`)

```
City lights map of an inhabited planet at night. Warm yellow-white
clusters of city lights on a pure black background, dense along coastlines
and river valleys, thin chains along highways between cities, dark
interiors of deserts and oceans. Nothing else, no land colour, no clouds.
```
*+ технический хвост.* Только для обитаемых миров (`green`, `city`, `klotho`).

---

## 5. Как проверить, что получилось

Открой игру, экран «Галактика» — планеты в системе Капелла будут
с новыми картинками. Если планета осталась прежней:

- проверь имя файла в `manifest.json` — оно чувствительно к регистру;
- ключ должен быть из списка выше (`klotho`, `ice`, `tartarus`…);
- открой консоль браузера: не открывшийся файл пишет предупреждение
  «Планета «имя»: не открылась карта …».

Игра работает и без единой картинки — тогда планеты рисуются
процедурным шумом, как раньше.
